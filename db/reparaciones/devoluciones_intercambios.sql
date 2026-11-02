-- =====================================================================
--  Reparacion/migracion: devoluciones e intercambios (PENDIENTES 10)
--
--   - estado_devolucion suma CONFIRMADA, CANCELADA y EXPIRADA (solicitudes online).
--   - devolucion: tipo (DEVOLUCION/INTERCAMBIO), origen (CAJA/ONLINE), visita y vencimiento,
--     montos del intercambio (monto_cambio, monto_reintegrado, diferencia_cobrada/metodo),
--     stock_comprometido y el estado del correo del comprobante.
--   - una sola devolucion/intercambio vigente por compra (indice unico parcial).
--   - fn_total_efectivo_sesion resta lo REINTEGRADO en EFECTIVO o QR.
--   - fn_devolucion_stock libera las prendas pedidas a cambio; fn_expirar_devoluciones nueva.
--   - configuracion: plazos de 3 dias y tope de 3 prendas por compra.
--   - CAJERO recibe devoluciones.leer/crear/actualizar.
--   - precios distintos por talla/color en las variantes que no tenian precio propio.
--
--  Idempotente. Las funciones son copia exacta de db/02_logica.sql. Los ALTER TYPE van fuera de la
--  transaccion: un valor nuevo de un ENUM no se puede usar (en el indice) hasta que se confirma.
--
--  Uso:
--    docker run --rm -i postgres:16 psql "<DATABASE_PUBLIC_URL>" -v ON_ERROR_STOP=1 \
--      < db/reparaciones/devoluciones_intercambios.sql
--    (local: docker compose exec -T db psql -U fashionstore -d fashionstore -v ON_ERROR_STOP=1 < ...)
-- =====================================================================

ALTER TYPE estado_devolucion ADD VALUE IF NOT EXISTS 'CONFIRMADA' AFTER 'SOLICITADA';
ALTER TYPE estado_devolucion ADD VALUE IF NOT EXISTS 'CANCELADA';
ALTER TYPE estado_devolucion ADD VALUE IF NOT EXISTS 'EXPIRADA';

BEGIN;

ALTER TABLE devolucion ADD COLUMN IF NOT EXISTS tipo VARCHAR(12) NOT NULL DEFAULT 'DEVOLUCION';
ALTER TABLE devolucion ADD COLUMN IF NOT EXISTS origen VARCHAR(10) NOT NULL DEFAULT 'CAJA';
ALTER TABLE devolucion ADD COLUMN IF NOT EXISTS fecha_visita DATE;
ALTER TABLE devolucion ADD COLUMN IF NOT EXISTS hora_visita TIME;
ALTER TABLE devolucion ADD COLUMN IF NOT EXISTS expira_en TIMESTAMPTZ;
ALTER TABLE devolucion ADD COLUMN IF NOT EXISTS monto_cambio NUMERIC(12,2) NOT NULL DEFAULT 0;
ALTER TABLE devolucion ADD COLUMN IF NOT EXISTS monto_reintegrado NUMERIC(12,2) NOT NULL DEFAULT 0;
ALTER TABLE devolucion ADD COLUMN IF NOT EXISTS diferencia_cobrada NUMERIC(12,2) NOT NULL DEFAULT 0;
ALTER TABLE devolucion ADD COLUMN IF NOT EXISTS diferencia_metodo VARCHAR(20);
ALTER TABLE devolucion ADD COLUMN IF NOT EXISTS stock_comprometido BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE devolucion ADD COLUMN IF NOT EXISTS correo_enviado_en TIMESTAMPTZ;
ALTER TABLE devolucion ADD COLUMN IF NOT EXISTS correo_intentos INT NOT NULL DEFAULT 0;
ALTER TABLE devolucion_detalle ADD COLUMN IF NOT EXISTS precio_solicitado NUMERIC(12,2);

ALTER TABLE devolucion DROP CONSTRAINT IF EXISTS devolucion_tipo_check;
ALTER TABLE devolucion ADD CONSTRAINT devolucion_tipo_check CHECK (tipo IN ('DEVOLUCION','INTERCAMBIO'));
ALTER TABLE devolucion DROP CONSTRAINT IF EXISTS devolucion_origen_check;
ALTER TABLE devolucion ADD CONSTRAINT devolucion_origen_check CHECK (origen IN ('CAJA','ONLINE'));
ALTER TABLE devolucion DROP CONSTRAINT IF EXISTS devolucion_monto_cambio_check;
ALTER TABLE devolucion ADD CONSTRAINT devolucion_monto_cambio_check CHECK (monto_cambio >= 0);
ALTER TABLE devolucion DROP CONSTRAINT IF EXISTS devolucion_monto_reintegrado_check;
ALTER TABLE devolucion ADD CONSTRAINT devolucion_monto_reintegrado_check CHECK (monto_reintegrado >= 0);
ALTER TABLE devolucion DROP CONSTRAINT IF EXISTS devolucion_diferencia_cobrada_check;
ALTER TABLE devolucion ADD CONSTRAINT devolucion_diferencia_cobrada_check CHECK (diferencia_cobrada >= 0);
ALTER TABLE devolucion DROP CONSTRAINT IF EXISTS devolucion_diferencia_metodo_check;
ALTER TABLE devolucion ADD CONSTRAINT devolucion_diferencia_metodo_check
    CHECK (diferencia_metodo IN ('EFECTIVO','TARJETA','QR'));

-- Lo que ya existia: los cambios por talla/color pasan a ser intercambios, y lo reintegrado de una
-- devolucion aprobada era todo lo que valia (el modelo viejo devolvia la plata entera).
UPDATE devolucion SET tipo = 'INTERCAMBIO' WHERE motivo_tipo IN ('TALLA','COLOR') AND tipo <> 'INTERCAMBIO';
UPDATE devolucion SET monto_reintegrado = monto_devuelto
 WHERE estado = 'APROBADA' AND monto_reintegrado = 0 AND monto_devuelto > 0;
-- Los correos de devoluciones viejas no se mandan (el job solo mira el ultimo dia, igual se marcan)
UPDATE devolucion SET correo_enviado_en = COALESCE(resuelta_en, fecha)
 WHERE estado = 'APROBADA' AND correo_enviado_en IS NULL;

-- Una sola vigente por compra. Si una base vieja ya tiene dos por la misma venta, el indice no se
-- crea (avisa) y el backend igual lo controla con la venta bloqueada.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ux_devolucion_una_por_venta') THEN
        IF EXISTS (SELECT venta_id FROM devolucion
                    WHERE estado::text IN ('SOLICITADA','CONFIRMADA','APROBADA')
                    GROUP BY venta_id HAVING COUNT(*) > 1) THEN
            RAISE NOTICE 'Hay ventas con mas de una devolucion vigente: no se crea ux_devolucion_una_por_venta';
        ELSE
            CREATE UNIQUE INDEX ux_devolucion_una_por_venta ON devolucion(venta_id)
                WHERE estado IN ('SOLICITADA','CONFIRMADA','APROBADA');
        END IF;
    END IF;
END $$;
CREATE INDEX IF NOT EXISTS ix_devolucion_vigentes ON devolucion(expira_en)
    WHERE estado IN ('SOLICITADA','CONFIRMADA') AND origen = 'ONLINE';

-- Parametria
UPDATE configuracion SET valor = '3', actualizado_en = now() WHERE clave = 'devolucion_plazo_dias';
UPDATE configuracion SET valor = '3', actualizado_en = now(),
       descripcion = 'Dias desde la venta para aceptar un intercambio de prenda por talla o color'
 WHERE clave = 'cambio_plazo_dias';
INSERT INTO configuracion (clave, valor, descripcion) VALUES
    ('devolucion_plazo_dias', '3', 'Dias desde la venta para aceptar una devolucion'),
    ('cambio_plazo_dias', '3', 'Dias desde la venta para aceptar un intercambio de prenda por talla o color'),
    ('devolucion_max_unidades', '3', 'Prendas que se pueden devolver o cambiar como maximo por compra')
ON CONFLICT (clave) DO NOTHING;

-- CAJERO concreta devoluciones e intercambios en caja (roles del sistema y los de cada empresa
-- que se llamen CAJERO)
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id
  FROM rol r
  JOIN permiso p ON p.codigo IN ('devoluciones.leer','devoluciones.crear','devoluciones.actualizar')
 WHERE r.nombre = 'CAJERO'
ON CONFLICT DO NOTHING;

-- Precio por talla/color (mismo UPDATE que db/03_datos_iniciales.sql); no pisa precios cargados
UPDATE producto_variante pv
   SET precio = round(p.precio_base
                      * (CASE WHEN (t.tipo = 'LETRA' AND t.codigo IN ('XL', 'XXL'))
                              OR (t.tipo = 'NUMERO' AND t.codigo IN ('42', '44'))
                              OR (t.tipo = 'CALZADO' AND t.codigo IN ('39', '40'))
                            THEN 1.10 ELSE 1 END)
                      * (CASE WHEN c.nombre IN ('Vino', 'Camel', 'Rosa Palo') THEN 1.05 ELSE 1 END))
  FROM producto p, talla t, color c
 WHERE p.id = pv.producto_id AND t.id = pv.talla_id AND c.id = pv.color_id
   AND pv.precio IS NULL
   AND ((t.tipo = 'LETRA' AND t.codigo IN ('XL', 'XXL'))
        OR (t.tipo = 'NUMERO' AND t.codigo IN ('42', '44'))
        OR (t.tipo = 'CALZADO' AND t.codigo IN ('39', '40'))
        OR c.nombre IN ('Vino', 'Camel', 'Rosa Palo'));

CREATE OR REPLACE FUNCTION fn_total_efectivo_sesion(p_sesion_id UUID)
RETURNS NUMERIC(12,2)
LANGUAGE sql STABLE
AS $$
    SELECT
        COALESCE((SELECT SUM(p.monto)
                    FROM pago p
                    JOIN venta v ON v.id = p.venta_id
                   WHERE v.sesion_caja_id = p_sesion_id
                     AND p.estado IN ('APROBADO', 'REEMBOLSADO')
                     AND p.metodo = 'EFECTIVO'), 0)
      - COALESCE((SELECT SUM(d.monto_reintegrado)
                    FROM devolucion d
                   WHERE d.sesion_caja_id = p_sesion_id
                     AND d.estado = 'APROBADA'
                     AND d.reintegro_metodo IN ('EFECTIVO', 'QR')), 0);
$$;

CREATE OR REPLACE FUNCTION fn_devolucion_stock()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    d RECORD;
BEGIN
    IF NEW.estado = OLD.estado THEN
        RETURN NEW;
    END IF;
    IF OLD.estado NOT IN ('SOLICITADA', 'CONFIRMADA') THEN
        RAISE EXCEPTION 'La devolucion ya esta % y no puede cambiar de estado', lower(OLD.estado::text);
    END IF;
    IF NEW.estado IN ('SOLICITADA', 'CONFIRMADA') AND OLD.estado = 'CONFIRMADA' THEN
        RAISE EXCEPTION 'Una devolucion confirmada no vuelve a quedar %', lower(NEW.estado::text);
    END IF;

    IF NEW.estado <> 'CONFIRMADA' AND OLD.stock_comprometido THEN
        FOR d IN
            SELECT dd.variante_solicitada_id, dd.cantidad
              FROM devolucion_detalle dd
             WHERE dd.devolucion_id = NEW.id AND dd.variante_solicitada_id IS NOT NULL
        LOOP
            PERFORM fn_mover_inventario(
                NEW.sucursal_id, d.variante_solicitada_id, 'LIBERACION', d.cantidad,
                'Cierre del intercambio (' || lower(NEW.estado::text) || '): se libera la prenda pedida',
                'DEVOLUCION', NEW.id, NEW.resuelta_por_id);
        END LOOP;
        -- el trigger es AFTER UPDATE OF estado: este UPDATE no lo vuelve a disparar
        UPDATE devolucion SET stock_comprometido = FALSE WHERE id = NEW.id;
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

CREATE OR REPLACE FUNCTION fn_expirar_devoluciones()
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE
    r          RECORD;
    v_contador INT := 0;
BEGIN
    FOR r IN
        SELECT d.id, d.numero, d.tipo, v.usuario_id, v.id AS venta_id, v.numero AS venta_numero
          FROM devolucion d
          JOIN venta v ON v.id = d.venta_id
         WHERE d.estado IN ('SOLICITADA', 'CONFIRMADA')
           AND d.origen = 'ONLINE'
           AND d.expira_en < now()
         ORDER BY d.expira_en
           FOR UPDATE OF d SKIP LOCKED
    LOOP
        UPDATE devolucion SET estado = 'EXPIRADA' WHERE id = r.id;
        IF r.usuario_id IS NOT NULL THEN
            INSERT INTO notificacion (usuario_id, tipo, titulo, mensaje, entidad_tipo, entidad_id)
            VALUES (r.usuario_id, 'VENTA',
                    CASE WHEN r.tipo = 'INTERCAMBIO' THEN 'Intercambio vencido' ELSE 'Devolucion vencida' END,
                    'Tu solicitud ' || r.numero || ' de la compra ' || r.venta_numero
                        || ' vencio porque no pasaste por la sucursal en la fecha elegida.',
                    'DEVOLUCION', r.id);
        END IF;
        v_contador := v_contador + 1;
    END LOOP;
    RETURN v_contador;
END;
$$;

COMMIT;
