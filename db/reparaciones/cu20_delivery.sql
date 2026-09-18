-- =====================================================================
--  Reparacion/migracion: CU20 "Entrega a Domicilio (Delivery)"
--
--  Sirve para una base YA desplegada (tipico: Railway) que no se puede recrear con
--  "docker compose down -v", y que por lo tanto no tiene nada de lo que CU20 agrego al
--  esquema. Sin esto, el backend nuevo arranca pero /envios y /direcciones fallan con
--  "relation envio does not exist" y el checkout a domicilio no puede cotizar.
--
--  Que agrega:
--    1. El valor 'REPARTIDOR' en el ENUM cargo_empleado y el ENUM estado_envio.
--    2. venta.costo_envio.
--    3. Las tablas envio y envio_evento con sus indices.
--    4. fn_cotizar_envio() y el trigger tg_envio_historial.
--    5. Los permisos envios.leer / envios.actualizar, el rol REPARTIDOR y sus asignaciones.
--    6. Los parametros de tarifa en la tabla configuracion.
--    7. Las coordenadas de las 3 sucursales seed (solo si estan en NULL): sin lat/long
--       no hay distancia que cobrar.
--
--  NO crea el usuario repartidor de demo: en una base real el personal se da de alta
--  desde CU13. Si se quiere el de la demo, al final hay un INSERT comentado.
--
--  Es idempotente: se puede correr las veces que haga falta.
--
--  Uso:
--    docker run --rm -i postgres:16 psql "<DATABASE_PUBLIC_URL>" -v ON_ERROR_STOP=1 \
--      < db/reparaciones/cu20_delivery.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tipos enumerados
--    ALTER TYPE ... ADD VALUE no corre dentro de un bloque de transaccion en
--    Postgres < 12 y ademas no puede usarse en la misma transaccion que lo consume,
--    asi que estos dos van sueltos, antes del BEGIN.
-- ---------------------------------------------------------------------

ALTER TYPE cargo_empleado ADD VALUE IF NOT EXISTS 'REPARTIDOR';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'estado_envio') THEN
        CREATE TYPE estado_envio AS ENUM
            ('PENDIENTE','ASIGNADO','EN_RUTA','ENTREGADO','FALLIDO','CANCELADO');
    END IF;
END
$$;

BEGIN;

-- ---------------------------------------------------------------------
-- 2. Costo del envio en la venta
-- ---------------------------------------------------------------------

ALTER TABLE venta
    ADD COLUMN IF NOT EXISTS costo_envio NUMERIC(12,2) NOT NULL DEFAULT 0;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_venta_costo_envio') THEN
        ALTER TABLE venta ADD CONSTRAINT ck_venta_costo_envio CHECK (costo_envio >= 0);
    END IF;
END
$$;

-- ---------------------------------------------------------------------
-- 3. Tablas del envio
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS envio (
    id                 UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    venta_id           UUID          NOT NULL UNIQUE REFERENCES venta(id) ON DELETE CASCADE,
    sucursal_id        UUID          NOT NULL REFERENCES sucursal(id),
    direccion_id       UUID          REFERENCES direccion(id) ON DELETE SET NULL,
    repartidor_id      UUID          REFERENCES usuario(id),
    estado             estado_envio  NOT NULL DEFAULT 'PENDIENTE',
    proveedor_ruteo    VARCHAR(20)   NOT NULL DEFAULT 'HAVERSINE',
    distancia_km       NUMERIC(8,3)  NOT NULL CHECK (distancia_km >= 0),
    duracion_min       INT           NOT NULL DEFAULT 0 CHECK (duracion_min >= 0),
    costo              NUMERIC(12,2) NOT NULL CHECK (costo >= 0),
    ciudad             ciudad_bo     NOT NULL,
    direccion_texto    VARCHAR(250)  NOT NULL,
    referencia         VARCHAR(250),
    latitud            NUMERIC(10,7),
    longitud           NUMERIC(10,7),
    observacion        VARCHAR(250),
    actualizado_por_id UUID          REFERENCES usuario(id),
    creado_en          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    asignado_en        TIMESTAMPTZ,
    despachado_en      TIMESTAMPTZ,
    cerrado_en         TIMESTAMPTZ,
    CONSTRAINT ck_envio_repartidor CHECK (estado IN ('PENDIENTE','CANCELADO') OR repartidor_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS ix_envio_sucursal ON envio(sucursal_id, estado, creado_en DESC);
CREATE INDEX IF NOT EXISTS ix_envio_repartidor ON envio(repartidor_id, estado) WHERE repartidor_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS envio_evento (
    id         BIGSERIAL    PRIMARY KEY,
    envio_id   UUID         NOT NULL REFERENCES envio(id) ON DELETE CASCADE,
    estado     estado_envio NOT NULL,
    nota       VARCHAR(250),
    usuario_id UUID         REFERENCES usuario(id),
    fecha      TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_envio_evento ON envio_evento(envio_id, fecha);

-- ---------------------------------------------------------------------
-- 4. Logica: tarifa y bitacora (identicas a db/02_logica.sql)
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_cotizar_envio(
    p_distancia_km NUMERIC,
    p_monto_pedido NUMERIC DEFAULT 0
)
RETURNS TABLE (
    costo            NUMERIC,
    tarifa_base      NUMERIC,
    precio_km        NUMERIC,
    radio_km         NUMERIC,
    gratis_desde     NUMERIC,
    es_gratis        BOOLEAN,
    dentro_cobertura BOOLEAN
)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_base    NUMERIC;
    v_km      NUMERIC;
    v_minimo  NUMERIC;
    v_radio   NUMERIC;
    v_gratis  NUMERIC;
    v_costo   NUMERIC;
BEGIN
    SELECT COALESCE((SELECT valor FROM configuracion WHERE clave = 'delivery_tarifa_base'),  '8')::NUMERIC,
           COALESCE((SELECT valor FROM configuracion WHERE clave = 'delivery_precio_km'),    '3.5')::NUMERIC,
           COALESCE((SELECT valor FROM configuracion WHERE clave = 'delivery_costo_minimo'), '10')::NUMERIC,
           COALESCE((SELECT valor FROM configuracion WHERE clave = 'delivery_radio_km'),     '12')::NUMERIC,
           COALESCE((SELECT valor FROM configuracion WHERE clave = 'delivery_gratis_desde'), '800')::NUMERIC
      INTO v_base, v_km, v_minimo, v_radio, v_gratis;

    v_costo := GREATEST(v_base + (v_km * GREATEST(p_distancia_km, 0)), v_minimo);

    costo            := ROUND(v_costo, 2);
    tarifa_base      := v_base;
    precio_km        := v_km;
    radio_km         := v_radio;
    gratis_desde     := v_gratis;
    es_gratis        := v_gratis > 0 AND COALESCE(p_monto_pedido, 0) >= v_gratis;
    dentro_cobertura := p_distancia_km IS NOT NULL AND p_distancia_km <= v_radio;

    IF es_gratis THEN
        costo := 0;
    END IF;

    RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION fn_envio_historial()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO envio_evento (envio_id, estado, nota, usuario_id)
        VALUES (NEW.id, NEW.estado, 'Envio generado por el pago aprobado', NEW.actualizado_por_id);
    ELSIF NEW.estado IS DISTINCT FROM OLD.estado THEN
        INSERT INTO envio_evento (envio_id, estado, nota, usuario_id)
        VALUES (NEW.id, NEW.estado, NEW.observacion, NEW.actualizado_por_id);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_envio_historial ON envio;
CREATE TRIGGER tg_envio_historial
    AFTER INSERT OR UPDATE ON envio
    FOR EACH ROW EXECUTE FUNCTION fn_envio_historial();

-- ---------------------------------------------------------------------
-- 5. Permisos, rol REPARTIDOR y asignaciones
-- ---------------------------------------------------------------------

INSERT INTO permiso (codigo, modulo, descripcion) VALUES
    ('envios.leer',       'envios', 'Consultar los envios a domicilio y su hoja de ruta'),
    ('envios.actualizar', 'envios', 'Asignar repartidor y mover el estado de un envio')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO rol (nombre, descripcion, es_sistema)
VALUES ('REPARTIDOR', 'Lleva los pedidos a domicilio (CU20)', TRUE)
ON CONFLICT (nombre) DO NOTHING;

-- ADMIN: todo
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'ADMIN'), p.id
  FROM permiso p
 WHERE p.codigo IN ('envios.leer','envios.actualizar')
ON CONFLICT DO NOTHING;

-- ENCARGADO: despacha lo de su sucursal
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'ENCARGADO'), p.id
  FROM permiso p
 WHERE p.codigo IN ('envios.leer','envios.actualizar')
ON CONFLICT DO NOTHING;

-- REPARTIDOR: solo su hoja de ruta (el backend acota ademas por repartidor_id)
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'REPARTIDOR'), p.id
  FROM permiso p
 WHERE p.codigo IN ('envios.leer','envios.actualizar')
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 6. Parametros de la tarifa
-- ---------------------------------------------------------------------

INSERT INTO configuracion (clave, valor, descripcion) VALUES
    ('delivery_tarifa_base',  '8',   'Bs fijos por salida de reparto'),
    ('delivery_precio_km',    '3.5', 'Bs por kilometro de ruta entre la sucursal y el domicilio'),
    ('delivery_costo_minimo', '10',  'Piso de la tarifa de delivery en Bs'),
    ('delivery_radio_km',     '12',  'Radio maximo de reparto de una sucursal, en km'),
    ('delivery_gratis_desde', '800', 'Monto de compra en Bs desde el que el envio es gratis')
ON CONFLICT (clave) DO NOTHING;

-- ---------------------------------------------------------------------
-- 7. Coordenadas de las sucursales seed (solo si faltan)
-- ---------------------------------------------------------------------

UPDATE sucursal SET latitud = -17.7620000, longitud = -63.1970000
 WHERE codigo = 'SC-01' AND (latitud IS NULL OR longitud IS NULL);
UPDATE sucursal SET latitud = -16.5090000, longitud = -68.1290000
 WHERE codigo = 'LP-01' AND (latitud IS NULL OR longitud IS NULL);
UPDATE sucursal SET latitud = -17.3660000, longitud = -66.1540000
 WHERE codigo = 'CB-01' AND (latitud IS NULL OR longitud IS NULL);

COMMIT;

-- ---------------------------------------------------------------------
-- OPCIONAL: repartidor de demo (password demo1234), el mismo del seed local.
-- Descomentar solo si se quiere probar el circuito completo en la nube.
-- ---------------------------------------------------------------------
-- INSERT INTO usuario (email, password_hash, nombre, apellido, tipo, rol_id, email_verificado)
-- VALUES ('repartidor.scz@fashionstore.bo', crypt('demo1234', gen_salt('bf')), 'Diego', 'Suarez',
--         'STAFF', (SELECT id FROM rol WHERE nombre = 'REPARTIDOR'), TRUE)
-- ON CONFLICT (email) DO NOTHING;
-- INSERT INTO empleado (usuario_id, sucursal_id, cargo, fecha_ingreso)
-- SELECT u.id, (SELECT id FROM sucursal WHERE codigo = 'SC-01'), 'REPARTIDOR', CURRENT_DATE
--   FROM usuario u WHERE u.email = 'repartidor.scz@fashionstore.bo'
-- ON CONFLICT (usuario_id) DO NOTHING;

-- Resultado esperado: las dos filas de permisos, el rol REPARTIDOR con 2 permisos y
-- las 3 sucursales con coordenadas.
SELECT (SELECT count(*) FROM permiso WHERE modulo = 'envios')                     AS permisos_envios,
       (SELECT count(*) FROM rol_permiso rp
          JOIN rol r ON r.id = rp.rol_id WHERE r.nombre = 'REPARTIDOR')           AS permisos_del_repartidor,
       (SELECT count(*) FROM sucursal WHERE latitud IS NOT NULL)                  AS sucursales_ubicadas,
       (SELECT count(*) FROM configuracion WHERE clave LIKE 'delivery%')          AS parametros_tarifa;
