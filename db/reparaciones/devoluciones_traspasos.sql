-- =====================================================================
--  Reparacion/migracion: devoluciones y traspasos entre sucursales (PENDIENTES 2.7)
--
--  Para una base ya desplegada (Railway) creada antes de que existieran los modulos
--  app/modules/devoluciones y app/modules/traspasos. Railway no re-ejecuta
--  db/01..03 con un git push, asi que sin este script:
--   - POST /devoluciones y POST /traspasos responden 500 (columnas resuelta_por_id,
--     motivo_rechazo, actualizado_por_id, fecha_despacho, observacion inexistentes);
--   - aprobar una devolucion o despachar/recibir un traspaso NO mueve el stock
--     (faltan los triggers tg_devolucion_stock y tg_traspaso_stock);
--   - el menu del panel no muestra Devoluciones/Traspasos y la API responde 403
--     (faltan los permisos devoluciones.* y traspasos.* y su asignacion a roles).
--
--  Es idempotente: ADD COLUMN IF NOT EXISTS, CREATE OR REPLACE FUNCTION,
--  DROP TRIGGER IF EXISTS + CREATE TRIGGER, INSERT ... ON CONFLICT DO NOTHING.
--  No toca datos existentes.
--
--  Este archivo vive en db/reparaciones/ a proposito: docker-entrypoint-initdb.d solo
--  ejecuta lo que esta en el primer nivel de db/ (en local, docker compose down -v ya
--  toma 01_schema.sql, 02_logica.sql y 03_datos_iniciales.sql con todo esto).
--
--  Uso:
--    docker run --rm -i postgres:16 psql "<DATABASE_PUBLIC_URL>" -v ON_ERROR_STOP=1 --      < db/reparaciones/devoluciones_traspasos.sql
-- =====================================================================

BEGIN;

-- 1. Columnas nuevas (ver db/01_schema.sql)
ALTER TABLE devolucion
    ADD COLUMN IF NOT EXISTS resuelta_por_id UUID REFERENCES usuario(id),
    ADD COLUMN IF NOT EXISTS resuelta_en     TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS motivo_rechazo  VARCHAR(250);
CREATE INDEX IF NOT EXISTS ix_devolucion_venta ON devolucion(venta_id);

ALTER TABLE traspaso
    ADD COLUMN IF NOT EXISTS fecha_despacho     TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS actualizado_por_id UUID REFERENCES usuario(id),
    ADD COLUMN IF NOT EXISTS observacion        VARCHAR(250);

-- 2. Triggers que mueven el stock (copia del bloque de db/02_logica.sql)
-- ---------------------------------------------------------------------
--  DEVOLUCIONES (PENDIENTES 2.7): al aprobarla vuelve el stock
--  Mismo patron que tg_confirmar_recepcion: el backend solo mueve el estado
--  (SOLICITADA -> APROBADA) y es la base la que reingresa cada linea con
--  fn_mover_inventario tipo DEVOLUCION, en la sucursal de la devolucion.
--  Ademas la base es la ultima barrera de dos reglas:
--   * una devolucion resuelta (APROBADA/RECHAZADA) no cambia mas de estado;
--   * lo APROBADO de cada linea de venta no supera lo vendido. La venta se
--     bloquea con FOR UPDATE para que dos aprobaciones simultaneas de la misma
--     venta se serialicen y la segunda vea la primera.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_devolucion_stock()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    d RECORD;
BEGIN
    IF NEW.estado = OLD.estado THEN
        RETURN NEW;
    END IF;
    IF OLD.estado <> 'SOLICITADA' THEN
        RAISE EXCEPTION 'La devolucion ya esta % y no puede cambiar de estado', lower(OLD.estado::text);
    END IF;

    IF NEW.estado = 'APROBADA' THEN
        PERFORM 1 FROM venta WHERE id = NEW.venta_id FOR UPDATE;

        FOR d IN
            SELECT vd.id, vd.variante_id, vd.cantidad AS vendida, dd.cantidad,
                   (SELECT COALESCE(SUM(dd2.cantidad), 0)
                      FROM devolucion_detalle dd2
                      JOIN devolucion dv ON dv.id = dd2.devolucion_id
                     WHERE dd2.venta_detalle_id = vd.id
                       AND dv.estado = 'APROBADA') AS aprobada
              FROM devolucion_detalle dd
              JOIN venta_detalle vd ON vd.id = dd.venta_detalle_id
             WHERE dd.devolucion_id = NEW.id
        LOOP
            -- "aprobada" ya incluye esta devolucion (el trigger es AFTER UPDATE)
            IF d.aprobada > d.vendida THEN
                RAISE EXCEPTION 'Se devolverian % unidad(es) de una linea que vendio %',
                                d.aprobada, d.vendida;
            END IF;
            PERFORM fn_mover_inventario(
                NEW.sucursal_id, d.variante_id, 'DEVOLUCION', d.cantidad,
                'Devolucion de venta: ' || left(NEW.motivo, 150), 'DEVOLUCION', NEW.id,
                NEW.resuelta_por_id);
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_devolucion_stock ON devolucion;
CREATE TRIGGER tg_devolucion_stock
    AFTER UPDATE OF estado ON devolucion
    FOR EACH ROW EXECUTE FUNCTION fn_devolucion_stock();


-- ---------------------------------------------------------------------
--  TRASPASOS ENTRE SUCURSALES (PENDIENTES 2.7)
--  El backend solo cambia traspaso.estado (y antes carga cantidad_recibida al
--  recibir); el stock lo mueve este trigger, firmando el kardex con
--  traspaso.actualizado_por_id:
--    SOLICITADO  -> EN_TRANSITO : TRASPASO_SAL en el origen por lo solicitado
--                                 (falla si el origen no tiene disponible).
--    EN_TRANSITO -> RECIBIDO    : TRASPASO_ENT en el destino por lo RECIBIDO.
--                                 Si llego de menos, la diferencia salio del
--                                 origen y no entro en ningun lado: se investiga
--                                 y se corrige con un AJUSTE (el kardex no se
--                                 reescribe), igual que una recepcion.
--    EN_TRANSITO -> ANULADO     : TRASPASO_ENT de vuelta en el ORIGEN (el envio
--                                 no salio o volvio entero).
--    SOLICITADO  -> ANULADO     : nada que mover.
--  Cualquier otra transicion es un error.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_traspaso_stock()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    d RECORD;
BEGIN
    IF NEW.estado = OLD.estado THEN
        RETURN NEW;
    END IF;

    IF OLD.estado = 'SOLICITADO' AND NEW.estado = 'EN_TRANSITO' THEN
        FOR d IN SELECT * FROM traspaso_detalle WHERE traspaso_id = NEW.id LOOP
            PERFORM fn_mover_inventario(
                NEW.sucursal_origen_id, d.variante_id, 'TRASPASO_SAL', d.cantidad_solicitada,
                'Traspaso ' || NEW.numero || ': salida del origen', 'TRASPASO', NEW.id,
                NEW.actualizado_por_id);
        END LOOP;

    ELSIF OLD.estado = 'EN_TRANSITO' AND NEW.estado = 'RECIBIDO' THEN
        FOR d IN SELECT * FROM traspaso_detalle WHERE traspaso_id = NEW.id LOOP
            IF d.cantidad_recibida IS NULL THEN
                RAISE EXCEPTION 'Falta indicar la cantidad recibida de todas las lineas';
            END IF;
            IF d.cantidad_recibida > d.cantidad_solicitada THEN
                RAISE EXCEPTION 'Se recibieron % unidad(es) de una linea que despacho %',
                                d.cantidad_recibida, d.cantidad_solicitada;
            END IF;
            IF d.cantidad_recibida > 0 THEN
                PERFORM fn_mover_inventario(
                    NEW.sucursal_destino_id, d.variante_id, 'TRASPASO_ENT', d.cantidad_recibida,
                    'Traspaso ' || NEW.numero || ': entrada en destino', 'TRASPASO', NEW.id,
                    NEW.actualizado_por_id);
            END IF;
        END LOOP;

    ELSIF OLD.estado = 'EN_TRANSITO' AND NEW.estado = 'ANULADO' THEN
        FOR d IN SELECT * FROM traspaso_detalle WHERE traspaso_id = NEW.id LOOP
            PERFORM fn_mover_inventario(
                NEW.sucursal_origen_id, d.variante_id, 'TRASPASO_ENT', d.cantidad_solicitada,
                'Traspaso ' || NEW.numero || ' anulado en transito: vuelve al origen', 'TRASPASO',
                NEW.id, NEW.actualizado_por_id);
        END LOOP;

    ELSIF NOT (OLD.estado = 'SOLICITADO' AND NEW.estado = 'ANULADO') THEN
        RAISE EXCEPTION 'Un traspaso % no puede pasar a %',
                        lower(OLD.estado::text), lower(NEW.estado::text);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_traspaso_stock ON traspaso;
CREATE TRIGGER tg_traspaso_stock
    AFTER UPDATE OF estado ON traspaso
    FOR EACH ROW EXECUTE FUNCTION fn_traspaso_stock();

-- 3. Permisos (ver db/03_datos_iniciales.sql): ADMIN todo, ENCARGADO todos los nuevos
INSERT INTO permiso (codigo, modulo, descripcion) VALUES
    ('devoluciones.leer',     'devoluciones','Consultar las devoluciones de ventas de la sucursal'),
    ('devoluciones.crear',    'devoluciones','Registrar una devolucion sobre una venta pagada'),
    ('devoluciones.actualizar','devoluciones','Aprobar (reingresa el stock) o rechazar una devolucion'),
    ('traspasos.leer',        'traspasos',   'Consultar los traspasos que salen o llegan a la sucursal'),
    ('traspasos.crear',       'traspasos',   'Solicitar un traspaso desde la propia sucursal a otra'),
    ('traspasos.actualizar',  'traspasos',   'Despachar un traspaso (sale el stock) o recibirlo (entra en destino)'),
    ('traspasos.eliminar',    'traspasos',   'Anular un traspaso solicitado o en transito')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id
  FROM rol r
  JOIN permiso p ON p.modulo IN ('devoluciones', 'traspasos')
 WHERE r.nombre IN ('ADMIN', 'ENCARGADO')
ON CONFLICT DO NOTHING;

COMMIT;
