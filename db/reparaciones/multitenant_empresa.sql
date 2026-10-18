-- =====================================================================
--  Migracion: tenant = EMPRESA (segundo parcial, reemplaza "tenant = sucursal")
--
--  Para bases creadas antes de este cambio (Railway, Docker con volumen) que ya tienen aplicado
--  db/reparaciones/segundo_parcial.sql. Una base nueva no la necesita: 01-04 ya traen todo.
--
--  Que hace, en una transaccion:
--    1. Crea `empresa` y pasa todo lo existente a FashionStore (id fijo ...0001).
--    2. Agrega empresa_id a sucursal, catalogo, proveedor, promocion, usuario, rol y auditoria;
--       las unicidades de slug/codigo/cupon/rol pasan a ser por empresa.
--    3. Rol SUPERADMIN + usuario superadmin@fashionstore.bo (demo1234) y los permisos nuevos
--       (empresas.*, planes.actualizar, sincronizacion.*, analitica.*).
--    4. Planes de la consigna: Basico (2 sucursales, sin IA) y Profesional (10, con IA); el
--       viejo Premium queda inactivo. La suscripcion pasa a ser una por empresa.
--    5. Cartera de clientas por empresa, venta/reserva.operacion_id y tabla operacion_sync.
--    6. Vistas y fn_mover_inventario con el chequeo de tenant (copiadas de 02_logica.sql).
--    7. Siembra las empresas de prueba Boutique Andina y Moda Urbana (si no estan).
--
--  Correr con:  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/reparaciones/multitenant_empresa.sql
--  Es re-ejecutable: una segunda corrida no cambia nada.
-- =====================================================================

BEGIN;

DO $$ BEGIN
    CREATE TYPE estado_operacion_sync AS ENUM ('CONFIRMADA','RECHAZADA','CONFLICTO');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE TYPE tipo_operacion_sync AS ENUM ('VENTA','RESERVA');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 1. EMPRESA -----------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS empresa (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    slug         VARCHAR(40)  NOT NULL UNIQUE,
    nombre       VARCHAR(120) NOT NULL,
    razon_social VARCHAR(180) NOT NULL,
    nit          VARCHAR(30)  NOT NULL,
    email        VARCHAR(150),
    telefono     VARCHAR(30),
    activa       BOOLEAN      NOT NULL DEFAULT TRUE,
    creada_en    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT ck_empresa_slug CHECK (slug ~ '^[a-z0-9][a-z0-9-]{1,38}$')
);

INSERT INTO empresa (id, slug, nombre, razon_social, nit, email, telefono)
VALUES ('e0000000-0000-4000-8000-000000000001', 'fashionstore', 'FashionStore',
        COALESCE((SELECT valor FROM configuracion WHERE clave = 'empresa_razon_social'), 'FashionStore Bolivia S.R.L.'),
        COALESCE((SELECT valor FROM configuracion WHERE clave = 'empresa_nit'), '1234567890'),
        'contacto@fashionstore.bo', '33400000')
ON CONFLICT (id) DO NOTHING;
DELETE FROM configuracion WHERE clave IN ('empresa_razon_social', 'empresa_nit');

-- 2. EMPRESA_ID EN LO QUE ES DE CADA TENANT ------------------------------------------------------
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['sucursal','proveedor','categoria','marca','temporada','coleccion',
                             'producto','promocion'] LOOP
        EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS empresa_id UUID REFERENCES empresa(id)', t);
        EXECUTE format('UPDATE %I SET empresa_id = %L WHERE empresa_id IS NULL', t,
                       'e0000000-0000-4000-8000-000000000001');
        EXECUTE format('ALTER TABLE %I ALTER COLUMN empresa_id SET NOT NULL', t);
    END LOOP;
END $$;

ALTER TABLE usuario   ADD COLUMN IF NOT EXISTS empresa_id UUID REFERENCES empresa(id);
ALTER TABLE rol       ADD COLUMN IF NOT EXISTS empresa_id UUID REFERENCES empresa(id) ON DELETE CASCADE;
ALTER TABLE auditoria ADD COLUMN IF NOT EXISTS empresa_id UUID REFERENCES empresa(id);

ALTER TABLE categoria DROP CONSTRAINT IF EXISTS categoria_slug_key;
ALTER TABLE marca     DROP CONSTRAINT IF EXISTS marca_nombre_key;
ALTER TABLE producto  DROP CONSTRAINT IF EXISTS producto_codigo_key;
ALTER TABLE producto  DROP CONSTRAINT IF EXISTS producto_slug_key;
ALTER TABLE promocion DROP CONSTRAINT IF EXISTS promocion_codigo_cupon_key;
ALTER TABLE rol       DROP CONSTRAINT IF EXISTS rol_nombre_key;
CREATE UNIQUE INDEX IF NOT EXISTS categoria_empresa_id_slug_key ON categoria(empresa_id, slug);
CREATE UNIQUE INDEX IF NOT EXISTS marca_empresa_id_nombre_key   ON marca(empresa_id, nombre);
CREATE UNIQUE INDEX IF NOT EXISTS producto_empresa_id_codigo_key ON producto(empresa_id, codigo);
CREATE UNIQUE INDEX IF NOT EXISTS producto_empresa_id_slug_key  ON producto(empresa_id, slug);
CREATE UNIQUE INDEX IF NOT EXISTS promocion_empresa_id_codigo_cupon_key ON promocion(empresa_id, codigo_cupon);
CREATE UNIQUE INDEX IF NOT EXISTS ux_rol_nombre_empresa ON rol(empresa_id, nombre) WHERE empresa_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_rol_nombre_sistema ON rol(nombre) WHERE empresa_id IS NULL;
CREATE INDEX IF NOT EXISTS ix_usuario_empresa   ON usuario(empresa_id) WHERE empresa_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_sucursal_empresa  ON sucursal(empresa_id) WHERE activa;
CREATE INDEX IF NOT EXISTS ix_producto_empresa  ON producto(empresa_id) WHERE activo;
CREATE INDEX IF NOT EXISTS ix_auditoria_empresa ON auditoria(empresa_id, fecha DESC);

-- los roles propios que CU13 creo eran de la unica empresa que habia
UPDATE rol SET empresa_id = 'e0000000-0000-4000-8000-000000000001'
 WHERE NOT es_sistema AND empresa_id IS NULL;
DO $$ BEGIN
    ALTER TABLE rol ADD CONSTRAINT ck_rol_sistema CHECK (NOT es_sistema OR empresa_id IS NULL);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 3. PLATAFORMA: SUPERADMIN Y PERMISOS NUEVOS -----------------------------------------------------
INSERT INTO rol (nombre, descripcion, es_sistema)
SELECT 'SUPERADMIN', 'Administracion de la plataforma SaaS: empresas, planes y suscripciones', TRUE
 WHERE NOT EXISTS (SELECT 1 FROM rol WHERE nombre = 'SUPERADMIN' AND empresa_id IS NULL);
UPDATE rol SET descripcion = 'Administracion de una empresa: todo lo de su tenant'
 WHERE nombre = 'ADMIN' AND empresa_id IS NULL;

INSERT INTO permiso (codigo, modulo, descripcion) VALUES
    ('sincronizacion.leer',   'sincronizacion','Consultar las operaciones offline sincronizadas y sus conflictos'),
    ('sincronizacion.actualizar','sincronizacion','Resolver conflictos de sincronizacion (reintentar, aceptar precio, descartar)'),
    ('analitica.leer',        'analitica',   'Consultar el dashboard analitico (modelos de machine learning)'),
    ('analitica.actualizar',  'analitica',   'Reentrenar los modelos de machine learning'),
    ('empresas.leer',         'empresas',    'Consultar las empresas contratantes de la plataforma'),
    ('empresas.crear',        'empresas',    'Registrar una empresa contratante con su administrador'),
    ('empresas.actualizar',   'empresas',    'Editar, suspender o reactivar una empresa y asignarle plan'),
    ('planes.actualizar',     'planes',      'Configurar precio, limites y funciones de los planes')
ON CONFLICT (codigo) DO NOTHING;
UPDATE permiso SET descripcion = 'Consultar el plan, la suscripcion y el uso de la empresa' WHERE codigo = 'suscripciones.leer';
UPDATE permiso SET descripcion = 'Cambiar de plan y pagar la suscripcion de la empresa' WHERE codigo = 'suscripciones.actualizar';
UPDATE permiso SET descripcion = 'Consultar la cartera de clientas de la empresa' WHERE codigo = 'clientes.leer';
UPDATE permiso SET descripcion = 'Editar el perfil de una clienta en la empresa' WHERE codigo = 'clientes.actualizar';

-- ADMIN de empresa: todo menos lo de la plataforma
DELETE FROM rol_permiso rp USING permiso p, rol r
 WHERE rp.permiso_id = p.id AND rp.rol_id = r.id AND r.nombre = 'ADMIN' AND r.empresa_id IS NULL
   AND p.modulo IN ('empresas', 'planes');
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id FROM rol r CROSS JOIN permiso p
 WHERE r.nombre = 'ADMIN' AND r.empresa_id IS NULL AND p.modulo NOT IN ('empresas', 'planes')
ON CONFLICT DO NOTHING;
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id FROM rol r CROSS JOIN permiso p
 WHERE r.nombre = 'SUPERADMIN' AND r.empresa_id IS NULL
   AND (p.modulo IN ('empresas', 'planes')
        OR p.codigo IN ('suscripciones.leer', 'suscripciones.actualizar', 'auditoria.leer',
                        'analitica.leer', 'analitica.actualizar'))
ON CONFLICT DO NOTHING;
-- ENCARGADO: consulta la suscripcion (la paga el ADMIN), resuelve conflictos, ve la analitica
DELETE FROM rol_permiso rp USING permiso p, rol r
 WHERE rp.permiso_id = p.id AND rp.rol_id = r.id AND r.nombre = 'ENCARGADO'
   AND r.empresa_id IS NULL AND p.codigo = 'suscripciones.actualizar';
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id
  FROM (VALUES
        ('ENCARGADO', ARRAY['sincronizacion.leer','sincronizacion.actualizar','analitica.leer']),
        ('CAJERO',    ARRAY['clientes.leer','sincronizacion.leer']),
        ('VENDEDOR',  ARRAY['sincronizacion.leer'])) AS x(rol, codigos)
  JOIN rol r     ON r.nombre = x.rol AND r.empresa_id IS NULL
  JOIN permiso p ON p.codigo = ANY(x.codigos)
ON CONFLICT DO NOTHING;

UPDATE usuario SET empresa_id = 'e0000000-0000-4000-8000-000000000001'
 WHERE tipo = 'STAFF' AND empresa_id IS NULL
   AND rol_id <> (SELECT id FROM rol WHERE nombre = 'SUPERADMIN' AND empresa_id IS NULL);
INSERT INTO usuario (email, password_hash, nombre, apellido, tipo, rol_id, email_verificado)
VALUES ('superadmin@fashionstore.bo', crypt('demo1234', gen_salt('bf')), 'Plataforma', 'SaaS',
        'STAFF', (SELECT id FROM rol WHERE nombre = 'SUPERADMIN' AND empresa_id IS NULL), TRUE)
ON CONFLICT (email) DO NOTHING;
UPDATE auditoria a SET empresa_id = u.empresa_id
  FROM usuario u WHERE u.id = a.usuario_id AND a.empresa_id IS NULL AND u.empresa_id IS NOT NULL;

-- 4. PLANES Y SUSCRIPCION POR EMPRESA -------------------------------------------------------------
ALTER TABLE plan ADD COLUMN IF NOT EXISTS max_sucursales    INT CHECK (max_sucursales > 0);
ALTER TABLE plan ADD COLUMN IF NOT EXISTS operacion_offline BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE plan ADD COLUMN IF NOT EXISTS reportes          BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE plan ADD COLUMN IF NOT EXISTS analitica_ml      BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE plan ALTER COLUMN perfiles_clientes SET DEFAULT TRUE;
ALTER TABLE plan ALTER COLUMN traspasos SET DEFAULT TRUE;
UPDATE plan SET nombre = 'Basico', precio_mensual = 350, max_sucursales = 2, max_empleados = NULL,
       max_cajas = NULL, perfiles_clientes = TRUE, traspasos = TRUE, operacion_offline = TRUE,
       reportes = TRUE, ia_reportes = FALSE, analitica_ml = FALSE, orden = 1, activo = TRUE,
       descripcion = 'Hasta 2 sucursales: productos, ventas, reservas, operacion offline y reportes convencionales'
 WHERE codigo = 'BASICO' AND max_sucursales IS NULL;
UPDATE plan SET nombre = 'Profesional', precio_mensual = 900, max_sucursales = 10, max_empleados = NULL,
       max_cajas = NULL, perfiles_clientes = TRUE, traspasos = TRUE, operacion_offline = TRUE,
       reportes = TRUE, ia_reportes = TRUE, analitica_ml = TRUE, orden = 2, activo = TRUE,
       descripcion = 'Hasta 10 sucursales: todo lo del Basico mas reportes generativos con IA y analitica de ML'
 WHERE codigo = 'PROFESIONAL' AND max_sucursales IS NULL;
UPDATE plan SET activo = FALSE WHERE codigo = 'PREMIUM';

ALTER TABLE suscripcion ADD COLUMN IF NOT EXISTS empresa_id UUID REFERENCES empresa(id) ON DELETE CASCADE;
DO $$
DECLARE
    v_conservar UUID;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_name = 'suscripcion' AND column_name = 'sucursal_id') THEN
        -- una sola suscripcion para FashionStore: se conserva la que vence mas tarde, con sus
        -- pagos y los de las demas (la historia no se pierde)
        SELECT id INTO v_conservar FROM suscripcion ORDER BY vence_en DESC LIMIT 1;
        IF v_conservar IS NOT NULL THEN
            UPDATE pago_suscripcion SET suscripcion_id = v_conservar WHERE suscripcion_id <> v_conservar;
            DELETE FROM suscripcion WHERE id <> v_conservar;
            UPDATE suscripcion
               SET empresa_id = 'e0000000-0000-4000-8000-000000000001',
                   plan_id = (SELECT id FROM plan WHERE codigo = 'PROFESIONAL'),
                   estado = 'ACTIVA', vence_en = GREATEST(vence_en, now() + interval '30 days')
             WHERE id = v_conservar;
        END IF;
        ALTER TABLE suscripcion DROP COLUMN sucursal_id;
    END IF;
END $$;
INSERT INTO suscripcion (empresa_id, plan_id, estado, inicio, vence_en)
SELECT 'e0000000-0000-4000-8000-000000000001', (SELECT id FROM plan WHERE codigo = 'PROFESIONAL'),
       'ACTIVA', now(), now() + interval '30 days'
 WHERE NOT EXISTS (SELECT 1 FROM suscripcion WHERE empresa_id = 'e0000000-0000-4000-8000-000000000001');
ALTER TABLE suscripcion ALTER COLUMN empresa_id SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS suscripcion_empresa_id_key ON suscripcion(empresa_id);
COMMENT ON TABLE suscripcion IS
    'Suscripcion del tenant (empresa). Vigente = estado PRUEBA/ACTIVA y vence_en > now(); '
    'el backend la trata como VENCIDA aunque el estado no se haya actualizado todavia.';

-- 5. CARTERA POR EMPRESA, OPERACIONES OFFLINE ----------------------------------------------------
ALTER TABLE cliente_perfil_tenant ADD COLUMN IF NOT EXISTS empresa_id UUID REFERENCES empresa(id) ON DELETE CASCADE;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_name = 'cliente_perfil_tenant' AND column_name = 'sucursal_id') THEN
        UPDATE cliente_perfil_tenant cp SET empresa_id = s.empresa_id
          FROM sucursal s WHERE s.id = cp.sucursal_id;
        -- si una clienta tenia ficha en dos sucursales, queda la editada mas recientemente
        DELETE FROM cliente_perfil_tenant cp
         WHERE EXISTS (SELECT 1 FROM cliente_perfil_tenant o
                        WHERE o.empresa_id = cp.empresa_id AND o.usuario_id = cp.usuario_id
                          AND (o.actualizado_en, o.sucursal_id) > (cp.actualizado_en, cp.sucursal_id));
        ALTER TABLE cliente_perfil_tenant DROP CONSTRAINT cliente_perfil_tenant_pkey;
        ALTER TABLE cliente_perfil_tenant DROP COLUMN sucursal_id;
        ALTER TABLE cliente_perfil_tenant ALTER COLUMN empresa_id SET NOT NULL;
        ALTER TABLE cliente_perfil_tenant ADD PRIMARY KEY (empresa_id, usuario_id);
    END IF;
END $$;

ALTER TABLE venta   ADD COLUMN IF NOT EXISTS operacion_id UUID UNIQUE;
ALTER TABLE reserva ADD COLUMN IF NOT EXISTS operacion_id UUID UNIQUE;

CREATE TABLE IF NOT EXISTS operacion_sync (
    id              UUID                  PRIMARY KEY,
    empresa_id      UUID                  NOT NULL REFERENCES empresa(id),
    sucursal_id     UUID                  REFERENCES sucursal(id),
    usuario_id      UUID                  NOT NULL REFERENCES usuario(id),
    tipo            tipo_operacion_sync   NOT NULL,
    estado          estado_operacion_sync NOT NULL,
    codigo_motivo   VARCHAR(40),
    motivo          VARCHAR(300),
    payload         JSONB                 NOT NULL,
    resultado       JSONB,
    registrada_en   TIMESTAMPTZ           NOT NULL,
    recibida_en     TIMESTAMPTZ           NOT NULL DEFAULT now(),
    intentos        INT                   NOT NULL DEFAULT 1,
    ultimo_intento  TIMESTAMPTZ           NOT NULL DEFAULT now(),
    resuelta_por_id UUID                  REFERENCES usuario(id),
    resuelta_en     TIMESTAMPTZ,
    resolucion      VARCHAR(300)
);
CREATE INDEX IF NOT EXISTS ix_operacion_sync_empresa ON operacion_sync(empresa_id, recibida_en DESC);
CREATE INDEX IF NOT EXISTS ix_operacion_sync_abiertas ON operacion_sync(empresa_id)
    WHERE estado = 'CONFLICTO' AND resuelta_en IS NULL;

-- 6. VISTAS Y FUNCION DE INVENTARIO (copiadas de db/02_logica.sql) -------------------------------
CREATE OR REPLACE VIEW v_disponibilidad AS
SELECT
    p.id                AS producto_id,
    p.nombre            AS producto,
    pv.id               AS variante_id,
    pv.sku,
    t.codigo            AS talla,
    c.nombre            AS color,
    s.id                AS sucursal_id,
    s.nombre            AS sucursal,
    s.ciudad,
    i.cantidad_fisica,
    i.cantidad_reservada,
    i.disponible,
    CASE
        WHEN i.disponible > 0                    THEN 'DISPONIBLE'
        WHEN i.cantidad_reservada > 0            THEN 'RESERVADA'
        ELSE                                          'AGOTADA'
    END AS situacion,
    s.empresa_id
FROM inventario i
JOIN producto_variante pv ON pv.id = i.variante_id
JOIN producto p           ON p.id  = pv.producto_id
JOIN talla t              ON t.id  = pv.talla_id
JOIN color c              ON c.id  = pv.color_id
JOIN sucursal s           ON s.id  = i.sucursal_id
WHERE p.activo AND pv.activa AND s.activa;

CREATE OR REPLACE VIEW v_stock_global AS
SELECT
    pv.id  AS variante_id,
    pv.sku,
    p.nombre AS producto,
    SUM(i.cantidad_fisica)    AS total_fisico,
    SUM(i.cantidad_reservada) AS total_reservado,
    SUM(i.disponible)         AS total_disponible,
    COUNT(*) FILTER (WHERE i.disponible > 0) AS sucursales_con_stock,
    p.empresa_id
FROM producto_variante pv
JOIN producto p    ON p.id = pv.producto_id
LEFT JOIN inventario i ON i.variante_id = pv.id
GROUP BY pv.id, pv.sku, p.nombre, p.empresa_id;

CREATE OR REPLACE VIEW v_ventas_diarias AS
WITH neta AS (
    SELECT v.*,
           v.total - COALESCE((SELECT SUM(d.monto_devuelto) FROM devolucion d
                                WHERE d.venta_id = v.id AND d.estado = 'APROBADA'), 0) AS total_neto
    FROM venta v
    WHERE v.estado IN ('PAGADA','ENTREGADA')
      AND NOT EXISTS (SELECT 1 FROM pago p WHERE p.venta_id = v.id AND p.estado = 'REEMBOLSADO')
)
SELECT
    v.fecha::date      AS dia,
    s.nombre           AS sucursal,
    v.canal,
    COUNT(*)           AS cantidad_ventas,
    SUM(v.total_neto)  AS monto_total,
    AVG(v.total_neto)  AS ticket_promedio,
    s.empresa_id
FROM neta v
JOIN sucursal s ON s.id = v.sucursal_id
GROUP BY 1, 2, 3, s.empresa_id;

CREATE OR REPLACE FUNCTION fn_mover_inventario(
    p_sucursal_id    UUID,
    p_variante_id    UUID,
    p_tipo           tipo_movimiento,
    p_cantidad       INT,
    p_motivo         VARCHAR DEFAULT NULL,
    p_documento_tipo VARCHAR DEFAULT NULL,
    p_documento_id   UUID    DEFAULT NULL,
    p_usuario_id     UUID    DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_inv          inventario%ROWTYPE;
    v_saldo_previo INT;
    v_saldo_nuevo  INT;
    v_mov_id       BIGINT;
BEGIN
    -- AJUSTE es un recuento absoluto y puede dejar la prenda en 0; el resto son deltas
    IF p_cantidad < 0 OR (p_cantidad = 0 AND p_tipo <> 'AJUSTE') THEN
        RAISE EXCEPTION 'La cantidad del movimiento debe ser positiva (recibido: %)', p_cantidad;
    END IF;

    -- Multi-tenant: la prenda tiene que ser del catalogo de la misma empresa que la sucursal.
    -- El backend ya lo valida al armar cada operacion; esto es la ultima barrera, asi ni una
    -- venta, ni una reserva, ni un traspaso, ni una recepcion pueden mover stock ajeno.
    IF NOT EXISTS (SELECT 1
                     FROM producto_variante pv
                     JOIN producto p ON p.id = pv.producto_id
                     JOIN sucursal s ON s.id = p_sucursal_id
                    WHERE pv.id = p_variante_id AND p.empresa_id = s.empresa_id) THEN
        RAISE EXCEPTION 'La prenda no pertenece a la empresa de la sucursal (variante %, sucursal %)',
                        p_variante_id, p_sucursal_id;
    END IF;

    -- crea la fila de inventario si la prenda nunca estuvo en esta sucursal
    INSERT INTO inventario (sucursal_id, variante_id)
    VALUES (p_sucursal_id, p_variante_id)
    ON CONFLICT (sucursal_id, variante_id) DO NOTHING;
 
    -- FOR UPDATE: si dos clientes reservan la ultima prenda a la vez,
    -- el segundo espera y ve el saldo ya actualizado
    SELECT * INTO v_inv
    FROM inventario
    WHERE sucursal_id = p_sucursal_id AND variante_id = p_variante_id
    FOR UPDATE;
 
    -- AJUSTE fija cantidad_fisica al valor absoluto p_cantidad (un recuento fisico, no un
    -- delta): el saldo que le importa a quien ajusta es el fisico, no el disponible (que
    -- ademas resta lo reservado y no coincidiria con el numero que la persona acaba de
    -- contar). El resto de los tipos siguen trackeando disponible, que es lo correcto para
    -- ellos -- una RESERVA, por ejemplo, no toca lo fisico.
    IF p_tipo = 'AJUSTE' THEN
        v_saldo_previo := v_inv.cantidad_fisica;
    ELSE
        v_saldo_previo := v_inv.cantidad_fisica - v_inv.cantidad_reservada;
    END IF;

    CASE p_tipo
        -- movimientos que cambian la existencia fisica
        WHEN 'ENTRADA', 'DEVOLUCION', 'TRASPASO_ENT' THEN
            UPDATE inventario
               SET cantidad_fisica = cantidad_fisica + p_cantidad,
                   actualizado_en  = now()
             WHERE id = v_inv.id;
 
        WHEN 'SALIDA', 'TRASPASO_SAL' THEN
            IF v_saldo_previo < p_cantidad THEN
                RAISE EXCEPTION 'Stock insuficiente: hay % disponible(s), se piden %',
                                v_saldo_previo, p_cantidad;
            END IF;
            UPDATE inventario
               SET cantidad_fisica = cantidad_fisica - p_cantidad,
                   actualizado_en  = now()
             WHERE id = v_inv.id;
 
        -- la reserva COMPROMETE: no toca lo fisico
        WHEN 'RESERVA' THEN
            IF v_saldo_previo < p_cantidad THEN
                RAISE EXCEPTION 'No se puede reservar: hay % disponible(s), se piden %',
                                v_saldo_previo, p_cantidad;
            END IF;
            UPDATE inventario
               SET cantidad_reservada = cantidad_reservada + p_cantidad,
                   actualizado_en     = now()
             WHERE id = v_inv.id;
 
        -- liberacion: cancelacion, expiracion o prenda descartada tras probarsela
        WHEN 'LIBERACION' THEN
            UPDATE inventario
               SET cantidad_reservada = GREATEST(cantidad_reservada - p_cantidad, 0),
                   actualizado_en     = now()
             WHERE id = v_inv.id;
 
        WHEN 'AJUSTE' THEN
            UPDATE inventario
               SET cantidad_fisica = p_cantidad,
                   actualizado_en  = now()
             WHERE id = v_inv.id;
    END CASE;
 
    IF p_tipo = 'AJUSTE' THEN
        SELECT cantidad_fisica INTO v_saldo_nuevo FROM inventario WHERE id = v_inv.id;
    ELSE
        SELECT cantidad_fisica - cantidad_reservada INTO v_saldo_nuevo
          FROM inventario WHERE id = v_inv.id;
    END IF;

    INSERT INTO movimiento_inventario (
        sucursal_id, variante_id, tipo, cantidad,
        saldo_anterior, saldo_nuevo, motivo,
        documento_tipo, documento_id, usuario_id)
    VALUES (
        p_sucursal_id, p_variante_id, p_tipo, p_cantidad,
        v_saldo_previo, v_saldo_nuevo, p_motivo,
        p_documento_tipo, p_documento_id, p_usuario_id)
    RETURNING id INTO v_mov_id;
 
    RETURN v_mov_id;
END;
$$;

CREATE OR REPLACE VIEW v_existencias_consolidadas AS
WITH vendidas AS (
    -- Unidades vendidas historicas, netas de devoluciones APROBADAS. venta_detalle se inserta
    -- recien al aprobar el pago, y se cuentan los mismos estados que los reportes de CU15
    -- (PAGADA/ENTREGADA).
    SELECT v.sucursal_id, vd.variante_id,
           SUM(vd.cantidad - COALESCE((SELECT SUM(dd.cantidad)
                                         FROM devolucion_detalle dd
                                         JOIN devolucion d ON d.id = dd.devolucion_id
                                        WHERE dd.venta_detalle_id = vd.id
                                          AND d.estado = 'APROBADA'), 0))::int AS vendidas
    FROM venta_detalle vd
    JOIN venta v ON v.id = vd.venta_id
    WHERE v.estado IN ('PAGADA', 'ENTREGADA')
    GROUP BY v.sucursal_id, vd.variante_id
),
entrantes AS (
    -- Mercaderia cargada en una recepcion BORRADOR: todavia no entro al kardex (eso lo hace
    -- tg_confirmar_recepcion al confirmar), pero ya se sabe que viene.
    SELECT r.sucursal_id, rd.variante_id, SUM(rd.cantidad)::int AS proximas_a_ingresar
    FROM recepcion_detalle rd
    JOIN recepcion r ON r.id = rd.recepcion_id
    WHERE r.estado = 'BORRADOR'
    GROUP BY r.sucursal_id, rd.variante_id
),
base AS (
    -- Una variante nueva que todavia no tiene fila en inventario de esa sucursal pero ya viene
    -- en una recepcion pendiente tambien tiene que aparecer (como PROXIMA_A_INGRESAR).
    SELECT sucursal_id, variante_id FROM inventario
    UNION
    SELECT sucursal_id, variante_id FROM entrantes
)
SELECT
    p.id                                    AS producto_id,
    p.nombre                                AS producto,
    cat.id                                  AS categoria_id,
    cat.nombre                              AS categoria,
    pv.id                                   AS variante_id,
    pv.sku,
    t.codigo                                AS talla,
    t.orden                                 AS talla_orden,
    c.nombre                                AS color,
    s.id                                    AS sucursal_id,
    s.nombre                                AS sucursal,
    s.ciudad,
    COALESCE(i.cantidad_fisica, 0)          AS cantidad_fisica,
    COALESCE(i.cantidad_reservada, 0)       AS cantidad_reservada,
    COALESCE(i.disponible, 0)               AS disponible,
    COALESCE(i.stock_minimo, 0)             AS stock_minimo,
    COALESCE(ve.vendidas, 0)                AS vendidas,
    COALESCE(en.proximas_a_ingresar, 0)     AS proximas_a_ingresar,
    (CASE
        WHEN COALESCE(i.disponible, 0) > 0          THEN 'DISPONIBLE'
        WHEN COALESCE(i.cantidad_reservada, 0) > 0  THEN 'RESERVADA'
        WHEN COALESCE(en.proximas_a_ingresar, 0) > 0 THEN 'PROXIMA_A_INGRESAR'
        ELSE                                             'AGOTADA'
    END)::text                              AS situacion,
    s.empresa_id
FROM base b
JOIN producto_variante pv ON pv.id  = b.variante_id
JOIN producto p           ON p.id   = pv.producto_id
JOIN categoria cat        ON cat.id = p.categoria_id
JOIN talla t              ON t.id   = pv.talla_id
JOIN color c              ON c.id   = pv.color_id
JOIN sucursal s           ON s.id   = b.sucursal_id
LEFT JOIN inventario i    ON i.sucursal_id  = b.sucursal_id AND i.variante_id  = b.variante_id
LEFT JOIN vendidas ve     ON ve.sucursal_id = b.sucursal_id AND ve.variante_id = b.variante_id
LEFT JOIN entrantes en    ON en.sucursal_id = b.sucursal_id AND en.variante_id = b.variante_id
WHERE p.activo AND pv.activa AND s.activa;

-- 7. EMPRESAS DE PRUEBA ----------------------------------------------------------------------------
DO $demo$
BEGIN
IF EXISTS (SELECT 1 FROM empresa WHERE slug = 'andina') THEN
    RAISE NOTICE 'Empresas de prueba ya cargadas';
    RETURN;
END IF;

INSERT INTO empresa (id, slug, nombre, razon_social, nit, email, telefono) VALUES
    ('e0000000-0000-4000-8000-000000000002', 'andina', 'Boutique Andina',
     'Boutique Andina Textiles S.R.L.', '4455667788', 'hola@andina.bo', '22790000'),
    ('e0000000-0000-4000-8000-000000000003', 'moda-urbana', 'Moda Urbana',
     'Moda Urbana Potosi S.R.L.', '9988776655', 'ventas@modaurbana.bo', '26220000');

-- =====================================================================
--  EMPRESA 2: BOUTIQUE ANDINA (tenant independiente, plan Basico)
--  Tejidos de altura para el frio: 2 sucursales (el tope del plan Basico, asi dar de alta
--  una tercera muestra el limite), su propio personal, catalogo, proveedor e inventario.
--  Comparte con FashionStore solo lo que es de la plataforma: tallas, colores y planes.
-- =====================================================================

INSERT INTO sucursal (empresa_id, codigo, nombre, ciudad, direccion, latitud, longitud,
                      hora_apertura, hora_cierre, cantidad_vestidores) VALUES
    ('e0000000-0000-4000-8000-000000000002', 'AN-LP1', 'Andina San Miguel', 'LA_PAZ',
     'Calle 21 de Calacoto #8050', -16.5410000, -68.0790000, '10:00', '20:00', 2),
    ('e0000000-0000-4000-8000-000000000002', 'AN-EA1', 'Andina Ceja El Alto', 'EL_ALTO',
     'Av. 6 de Marzo #1200', -16.5050000, -68.1630000, '09:00', '19:00', 1);

INSERT INTO caja (sucursal_id, codigo, nombre) VALUES
    ((SELECT id FROM sucursal WHERE codigo = 'AN-LP1'), 'CAJA-01', 'Caja San Miguel'),
    ((SELECT id FROM sucursal WHERE codigo = 'AN-EA1'), 'CAJA-01', 'Caja El Alto');

INSERT INTO usuario (email, password_hash, nombre, apellido, tipo, rol_id, empresa_id, email_verificado) VALUES
    ('admin@andina.bo',              crypt('demo1234', gen_salt('bf')), 'Ximena',  'Apaza',
     'STAFF', (SELECT id FROM rol WHERE nombre = 'ADMIN'),     'e0000000-0000-4000-8000-000000000002', TRUE),
    ('encargada.sanmiguel@andina.bo', crypt('demo1234', gen_salt('bf')), 'Carla',  'Mendoza',
     'STAFF', (SELECT id FROM rol WHERE nombre = 'ENCARGADO'), 'e0000000-0000-4000-8000-000000000002', TRUE),
    ('cajero.sanmiguel@andina.bo',   crypt('demo1234', gen_salt('bf')), 'Iver',    'Quisbert',
     'STAFF', (SELECT id FROM rol WHERE nombre = 'CAJERO'),    'e0000000-0000-4000-8000-000000000002', TRUE),
    ('cajera.elalto@andina.bo',      crypt('demo1234', gen_salt('bf')), 'Wara',    'Ticona',
     'STAFF', (SELECT id FROM rol WHERE nombre = 'CAJERO'),    'e0000000-0000-4000-8000-000000000002', TRUE);

INSERT INTO empleado (usuario_id, sucursal_id, cargo, fecha_ingreso) VALUES
    ((SELECT id FROM usuario WHERE email = 'admin@andina.bo'),
     (SELECT id FROM sucursal WHERE codigo = 'AN-LP1'), 'ENCARGADO', CURRENT_DATE),
    ((SELECT id FROM usuario WHERE email = 'encargada.sanmiguel@andina.bo'),
     (SELECT id FROM sucursal WHERE codigo = 'AN-LP1'), 'ENCARGADO', CURRENT_DATE),
    ((SELECT id FROM usuario WHERE email = 'cajero.sanmiguel@andina.bo'),
     (SELECT id FROM sucursal WHERE codigo = 'AN-LP1'), 'CAJERO', CURRENT_DATE),
    ((SELECT id FROM usuario WHERE email = 'cajera.elalto@andina.bo'),
     (SELECT id FROM sucursal WHERE codigo = 'AN-EA1'), 'CAJERO', CURRENT_DATE);

INSERT INTO proveedor (empresa_id, nombre, nit, contacto, email, telefono) VALUES
    ('e0000000-0000-4000-8000-000000000002', 'Tejidos Altiplano', '330011223', 'Felix Mamani',
     'pedidos@tejidosaltiplano.bo', '71122334');

-- Mismo slug que en FashionStore ('abrigos', 'accesorios'): la unicidad es por empresa.
INSERT INTO categoria (empresa_id, nombre, slug) VALUES
    ('e0000000-0000-4000-8000-000000000002', 'Abrigos',    'abrigos'),
    ('e0000000-0000-4000-8000-000000000002', 'Tejidos',    'tejidos'),
    ('e0000000-0000-4000-8000-000000000002', 'Accesorios', 'accesorios');

INSERT INTO marca (empresa_id, nombre) VALUES
    ('e0000000-0000-4000-8000-000000000002', 'Andina Alpaca');

INSERT INTO temporada (empresa_id, nombre, tipo, fecha_inicio, fecha_fin, activa) VALUES
    ('e0000000-0000-4000-8000-000000000002', 'Invierno Andino 2026', 'OTONO_INVIERNO',
     '2026-04-01', '2026-12-31', TRUE);

INSERT INTO producto (empresa_id, categoria_id, marca_id, proveedor_id, temporada_id,
                      codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
SELECT 'e0000000-0000-4000-8000-000000000002', c.id, m.id, pr.id, t.id,
       x.codigo, x.nombre, x.slug, x.descripcion, x.material, 'MUJER', x.precio, x.destacado
  FROM (VALUES
        ('AND-001', 'Poncho de Alpaca Tejido', 'poncho-de-alpaca-tejido', 'abrigos',
         'Poncho tejido a mano con guarda andina, abrigado y liviano.', 'Alpaca 100%', 420.00, TRUE),
        ('AND-002', 'Chompa de Alpaca Cuello Alto', 'chompa-de-alpaca-cuello-alto', 'tejidos',
         'Chompa de punto grueso con cuello alto, ideal para El Alto.', 'Alpaca 70% lana 30%', 290.00, TRUE),
        ('AND-003', 'Cardigan Tejido Largo', 'cardigan-tejido-largo', 'tejidos',
         'Cardigan largo de punto trenzado con bolsillos.', 'Lana de oveja', 260.00, FALSE),
        ('AND-004', 'Chalina Andina con Flecos', 'chalina-andina-con-flecos', 'accesorios',
         'Chalina con flecos y diseno de aguayo.', 'Alpaca 50% acrilico 50%', 120.00, FALSE)
       ) AS x(codigo, nombre, slug, cat, descripcion, material, precio, destacado)
  JOIN categoria c ON c.empresa_id = 'e0000000-0000-4000-8000-000000000002' AND c.slug = x.cat
  JOIN marca m     ON m.empresa_id = 'e0000000-0000-4000-8000-000000000002'
  JOIN proveedor pr ON pr.empresa_id = 'e0000000-0000-4000-8000-000000000002'
  JOIN temporada t ON t.empresa_id = 'e0000000-0000-4000-8000-000000000002';

-- SKU con prefijo AND-: el SKU es unico en toda la plataforma (lo lee el lector de codigos).
INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT p.id, t.id, c.id, p.codigo || '-' || t.codigo || '-' || left(c.nombre, 3)
  FROM producto p
  JOIN talla t ON t.tipo = 'LETRA'
              AND ((p.codigo = 'AND-004' AND t.codigo = 'UNICA')
                OR (p.codigo <> 'AND-004' AND t.codigo IN ('S', 'M', 'L')))
  JOIN color c ON c.nombre IN ('Gris', 'Camel', 'Vino')
 WHERE p.empresa_id = 'e0000000-0000-4000-8000-000000000002';

-- Fotos: el catalogo demo reusa las de prendas parecidas de /media/catalogo
INSERT INTO producto_imagen (producto_id, uso, url, formato, es_principal, orden)
SELECT p.id, 'CATALOGO', 'http://localhost:8081/media/catalogo/' || x.foto, 'JPG', TRUE, 0
  FROM (VALUES ('AND-001', 'tapado-de-lana-largo.jpg'),
               ('AND-002', 'cardigan-de-punto-grueso.jpg'),
               ('AND-003', 'cardigan-de-punto-grueso.jpg'),
               ('AND-004', 'chalina-de-alpaca.jpg')) AS x(codigo, foto)
  JOIN producto p ON p.codigo = x.codigo
                 AND p.empresa_id = 'e0000000-0000-4000-8000-000000000002';

INSERT INTO inventario (sucursal_id, variante_id, cantidad_fisica, stock_minimo)
SELECT s.id, pv.id, (6 + random() * 10)::int, 2
  FROM producto_variante pv
  JOIN producto p ON p.id = pv.producto_id
  JOIN sucursal s ON s.empresa_id = p.empresa_id
 WHERE p.empresa_id = 'e0000000-0000-4000-8000-000000000002';

-- Mismo codigo de cupon que FashionStore usaria en otra empresa: no chocan.
INSERT INTO promocion (empresa_id, nombre, codigo_cupon, tipo, valor, alcance, fecha_inicio, fecha_fin)
VALUES ('e0000000-0000-4000-8000-000000000002', 'Bienvenida Andina 10%', 'BIENVENIDA10',
        'PORCENTAJE', 10, 'TODO', '2026-01-01', '2026-12-31');

INSERT INTO suscripcion (empresa_id, plan_id, estado, inicio, vence_en)
VALUES ('e0000000-0000-4000-8000-000000000002', (SELECT id FROM plan WHERE codigo = 'BASICO'),
        'ACTIVA', now() - interval '40 days', now() + interval '20 days');


-- =====================================================================
--  EMPRESA 3: MODA URBANA (suscripcion VENCIDA)
--  Sirve para mostrar la politica de suscripcion vencida: su personal entra, ve su plan y
--  puede renovar, pero las funciones de gestion responden 402.
-- =====================================================================

INSERT INTO sucursal (empresa_id, codigo, nombre, ciudad, direccion, latitud, longitud,
                      hora_apertura, hora_cierre, cantidad_vestidores) VALUES
    ('e0000000-0000-4000-8000-000000000003', 'MU-PT1', 'Moda Urbana Potosi', 'POTOSI',
     'Calle Sucre #30', -19.5890000, -65.7530000, '09:30', '19:30', 1);

INSERT INTO usuario (email, password_hash, nombre, apellido, tipo, rol_id, empresa_id, email_verificado) VALUES
    ('admin@modaurbana.bo', crypt('demo1234', gen_salt('bf')), 'Sergio', 'Flores',
     'STAFF', (SELECT id FROM rol WHERE nombre = 'ADMIN'), 'e0000000-0000-4000-8000-000000000003', TRUE);

INSERT INTO empleado (usuario_id, sucursal_id, cargo, fecha_ingreso) VALUES
    ((SELECT id FROM usuario WHERE email = 'admin@modaurbana.bo'),
     (SELECT id FROM sucursal WHERE codigo = 'MU-PT1'), 'ENCARGADO', CURRENT_DATE);

INSERT INTO suscripcion (empresa_id, plan_id, estado, inicio, vence_en)
VALUES ('e0000000-0000-4000-8000-000000000003', (SELECT id FROM plan WHERE codigo = 'BASICO'),
        'VENCIDA', now() - interval '45 days', now() - interval '3 days');

INSERT INTO pago_suscripcion (suscripcion_id, plan_id, meses, monto, metodo, estado,
                              periodo_desde, periodo_hasta, creado_en, confirmado_en)
SELECT su.id, su.plan_id, 1, p.precio_mensual, 'TRANSFERENCIA', 'APROBADO',
       su.vence_en - interval '1 month', su.vence_en,
       su.vence_en - interval '1 month', su.vence_en - interval '1 month'
  FROM suscripcion su JOIN plan p ON p.id = su.plan_id
 WHERE su.empresa_id IN ('e0000000-0000-4000-8000-000000000002',
                         'e0000000-0000-4000-8000-000000000003');
END
$demo$;

COMMIT;
