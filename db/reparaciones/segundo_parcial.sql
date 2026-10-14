-- =====================================================================
--  Migracion: Segundo parcial (PENDIENTES 5.4 a 5.13)
--
--  Deja una base ya inicializada (Railway, o el Docker local con volumen) igual que un init
--  limpio con 01_schema.sql + 03_datos_iniciales.sql actuales:
--    1. Devoluciones: ENUM motivo_devolucion, numero de nota NDV-xxxxxx, motivo_tipo y
--       condiciones de la prenda, variante solicitada en el cambio por talla/color, y el
--       parametro cambio_plazo_dias.
--    2. Bloque 8 SaaS: plan, suscripcion, pago_suscripcion, cliente_perfil_tenant, los tres
--       planes y los permisos suscripciones.* / clientes.*.
--    3. Si la base trae el seed demo (sucursal SC-01): suma Sucre, Tarija y Oruro con caja,
--       personal e inventario, y una suscripcion para cada sucursal.
--  Despues, opcionalmente, db/04_historial_demo.sql (60 dias de ventas demo; re-ejecutable).
--
--  Re-ejecutable: todo se guarda por existencia.
--  Uso:
--    docker run --rm -i postgres:16 psql "<DATABASE_PUBLIC_URL>" -v ON_ERROR_STOP=1 \
--      < db/reparaciones/segundo_parcial.sql
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. Devoluciones: cambio por talla, condiciones y nota
-- ---------------------------------------------------------------------

DO $$ BEGIN
    CREATE TYPE motivo_devolucion AS ENUM ('TALLA','COLOR','DEFECTO','NO_GUSTO','OTRO');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE estado_suscripcion AS ENUM ('PRUEBA','ACTIVA','VENCIDA','CANCELADA');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Aviso al personal cuando se aprueba el pago de la suscripcion (saas/servicio.py)
ALTER TYPE tipo_notificacion ADD VALUE IF NOT EXISTS 'SUSCRIPCION';

CREATE SEQUENCE IF NOT EXISTS seq_nota_devolucion;

ALTER TABLE devolucion ADD COLUMN IF NOT EXISTS numero VARCHAR(20);
UPDATE devolucion d
   SET numero = 'NDV-' || lpad(nextval('seq_nota_devolucion')::text, 6, '0')
  FROM (SELECT id FROM devolucion WHERE numero IS NULL ORDER BY fecha) x
 WHERE d.id = x.id;
ALTER TABLE devolucion
    ALTER COLUMN numero SET DEFAULT ('NDV-' || lpad(nextval('seq_nota_devolucion')::text, 6, '0')),
    ALTER COLUMN numero SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS devolucion_numero_key ON devolucion(numero);

ALTER TABLE devolucion ADD COLUMN IF NOT EXISTS motivo_tipo motivo_devolucion NOT NULL DEFAULT 'OTRO';
ALTER TABLE devolucion ADD COLUMN IF NOT EXISTS con_etiqueta    BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE devolucion ADD COLUMN IF NOT EXISTS sin_uso         BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE devolucion ADD COLUMN IF NOT EXISTS con_comprobante BOOLEAN NOT NULL DEFAULT TRUE;
CREATE INDEX IF NOT EXISTS ix_devolucion_fecha ON devolucion(fecha DESC);

ALTER TABLE devolucion_detalle
    ADD COLUMN IF NOT EXISTS variante_solicitada_id UUID REFERENCES producto_variante(id);

INSERT INTO configuracion (clave, valor, descripcion) VALUES
    ('cambio_plazo_dias', '15', 'Dias desde la venta para aceptar un cambio de prenda por talla o color')
ON CONFLICT (clave) DO NOTHING;

-- ---------------------------------------------------------------------
-- 2. Bloque 8 SaaS
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS plan (
    id                SERIAL        PRIMARY KEY,
    codigo            VARCHAR(20)   NOT NULL UNIQUE,
    nombre            VARCHAR(60)   NOT NULL,
    descripcion       VARCHAR(300),
    precio_mensual    NUMERIC(12,2) NOT NULL CHECK (precio_mensual >= 0),
    max_empleados     INT,
    max_cajas         INT,
    perfiles_clientes BOOLEAN       NOT NULL DEFAULT FALSE,
    traspasos         BOOLEAN       NOT NULL DEFAULT FALSE,
    ia_reportes       BOOLEAN       NOT NULL DEFAULT FALSE,
    orden             INT           NOT NULL DEFAULT 0,
    activo            BOOLEAN       NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS suscripcion (
    id             UUID               PRIMARY KEY DEFAULT gen_random_uuid(),
    sucursal_id    UUID               NOT NULL UNIQUE REFERENCES sucursal(id) ON DELETE CASCADE,
    plan_id        INT                NOT NULL REFERENCES plan(id),
    estado         estado_suscripcion NOT NULL DEFAULT 'PRUEBA',
    inicio         TIMESTAMPTZ        NOT NULL DEFAULT now(),
    vence_en       TIMESTAMPTZ        NOT NULL,
    actualizado_en TIMESTAMPTZ        NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pago_suscripcion (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    suscripcion_id  UUID          NOT NULL REFERENCES suscripcion(id) ON DELETE CASCADE,
    plan_id         INT           NOT NULL REFERENCES plan(id),
    meses           INT           NOT NULL CHECK (meses BETWEEN 1 AND 12),
    monto           NUMERIC(12,2) NOT NULL CHECK (monto > 0),
    metodo          VARCHAR(20)   NOT NULL CHECK (metodo IN ('STRIPE','EFECTIVO','TRANSFERENCIA')),
    estado          estado_pago   NOT NULL DEFAULT 'PENDIENTE',
    id_transaccion  VARCHAR(120)  UNIQUE,
    periodo_desde   TIMESTAMPTZ,
    periodo_hasta   TIMESTAMPTZ,
    pagado_por_id   UUID          REFERENCES usuario(id),
    creado_en       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    confirmado_en   TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS ix_pago_suscripcion ON pago_suscripcion(suscripcion_id, creado_en DESC);

CREATE TABLE IF NOT EXISTS cliente_perfil_tenant (
    sucursal_id        UUID         NOT NULL REFERENCES sucursal(id) ON DELETE CASCADE,
    usuario_id         UUID         NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    segmento           VARCHAR(20)  NOT NULL DEFAULT 'NUEVA'
                           CHECK (segmento IN ('NUEVA','FRECUENTE','VIP','INACTIVA')),
    talla_habitual     VARCHAR(10),
    estilo_preferido   VARCHAR(60),
    telefono_contacto  VARCHAR(30),
    acepta_whatsapp    BOOLEAN      NOT NULL DEFAULT FALSE,
    notas              VARCHAR(500),
    actualizado_en     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    actualizado_por_id UUID         REFERENCES usuario(id),
    PRIMARY KEY (sucursal_id, usuario_id)
);

INSERT INTO plan (codigo, nombre, descripcion, precio_mensual, max_empleados, max_cajas,
                  perfiles_clientes, traspasos, ia_reportes, orden) VALUES
    ('BASICO',      'Basico',      'Caja, reservas, inventario y devoluciones de una tienda chica',
     350,  3,    1,    FALSE, FALSE, FALSE, 1),
    ('PROFESIONAL', 'Profesional', 'Suma perfil de clientas, traspasos entre sucursales y mas personal',
     750,  8,    2,    TRUE,  TRUE,  FALSE, 2),
    ('PREMIUM',     'Premium',     'Todo lo anterior mas reportes con IA y sin limites de personal ni cajas',
     1400, NULL, NULL, TRUE,  TRUE,  TRUE,  3)
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO permiso (codigo, modulo, descripcion) VALUES
    ('suscripciones.leer',    'suscripciones','Consultar el plan y la suscripcion de la sucursal'),
    ('suscripciones.actualizar','suscripciones','Cambiar de plan y pagar la suscripcion de la sucursal'),
    ('clientes.leer',         'clientes',    'Consultar la cartera de clientas de la sucursal'),
    ('clientes.actualizar',   'clientes',    'Editar el perfil de una clienta en la sucursal')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id
  FROM rol r
  JOIN permiso p ON p.codigo IN ('suscripciones.leer','suscripciones.actualizar',
                                 'clientes.leer','clientes.actualizar')
 WHERE r.nombre IN ('ADMIN','ENCARGADO')
ON CONFLICT DO NOTHING;

INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id FROM rol r JOIN permiso p ON p.codigo = 'clientes.leer'
 WHERE r.nombre = 'VENDEDOR'
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 3. Seed demo: tres sucursales mas (solo si la base trae el seed demo)
-- ---------------------------------------------------------------------

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sucursal WHERE codigo = 'SC-01') THEN
        RAISE NOTICE 'Base sin seed demo: no se agregan sucursales';
        RETURN;
    END IF;

    INSERT INTO sucursal (codigo, nombre, ciudad, direccion, latitud, longitud,
                          hora_apertura, hora_cierre, cantidad_vestidores) VALUES
        ('SU-01', 'FashionStore Sucre Centro', 'SUCRE',  'Calle Arenales #45',
         -19.0476000, -65.2600000, '09:00', '19:30', 1),
        ('TJ-01', 'FashionStore Tarija Las Panosas', 'TARIJA', 'Av. Las Americas #310',
         -21.5355000, -64.7296000, '09:00', '20:00', 2),
        ('OR-01', 'FashionStore Oruro Bolivar', 'ORURO',  'Calle Bolivar #620',
         -17.9667000, -67.1060000, '09:30', '19:00', 1)
    ON CONFLICT (codigo) DO NOTHING;

    INSERT INTO caja (sucursal_id, codigo, nombre)
    SELECT s.id, 'CAJA-01', x.nombre
      FROM (VALUES ('SU-01','Caja principal Sucre'), ('TJ-01','Caja principal Tarija'),
                   ('OR-01','Caja principal Oruro')) AS x(codigo, nombre)
      JOIN sucursal s ON s.codigo = x.codigo
     WHERE NOT EXISTS (SELECT 1 FROM caja c WHERE c.sucursal_id = s.id);

    INSERT INTO usuario (email, password_hash, nombre, apellido, tipo, rol_id, email_verificado)
    SELECT x.email, crypt('demo1234', gen_salt('bf')), x.nombre, x.apellido, 'STAFF',
           (SELECT id FROM rol WHERE nombre = x.rol), TRUE
      FROM (VALUES
            ('encargada.sucre@fashionstore.bo',  'Paola',    'Arancibia', 'ENCARGADO'),
            ('cajero.sucre@fashionstore.bo',     'Diego',    'Salazar',   'CAJERO'),
            ('encargada.tarija@fashionstore.bo', 'Natalia',  'Arce',      'ENCARGADO'),
            ('cajera.tarija@fashionstore.bo',    'Gabriela', 'Paz',       'CAJERO'),
            ('encargado.oruro@fashionstore.bo',  'Hugo',     'Choque',    'ENCARGADO'),
            ('cajera.oruro@fashionstore.bo',     'Rosa',     'Mamani',    'CAJERO')
           ) AS x(email, nombre, apellido, rol)
    ON CONFLICT (email) DO NOTHING;

    INSERT INTO empleado (usuario_id, sucursal_id, cargo, fecha_ingreso)
    SELECT u.id, s.id, x.cargo::cargo_empleado, CURRENT_DATE
      FROM (VALUES
            ('encargada.sucre@fashionstore.bo',  'SU-01', 'ENCARGADO'),
            ('cajero.sucre@fashionstore.bo',     'SU-01', 'CAJERO'),
            ('encargada.tarija@fashionstore.bo', 'TJ-01', 'ENCARGADO'),
            ('cajera.tarija@fashionstore.bo',    'TJ-01', 'CAJERO'),
            ('encargado.oruro@fashionstore.bo',  'OR-01', 'ENCARGADO'),
            ('cajera.oruro@fashionstore.bo',     'OR-01', 'CAJERO')
           ) AS x(email, codigo, cargo)
      JOIN usuario u  ON u.email = x.email
      JOIN sucursal s ON s.codigo = x.codigo
    ON CONFLICT DO NOTHING;

    -- Mismo reparto por clima que 03_datos_iniciales.sql, solo para las sucursales nuevas
    INSERT INTO inventario (sucursal_id, variante_id, cantidad_fisica, stock_minimo)
    SELECT
        s.id,
        pv.id,
        (CASE
            WHEN c.clima = 'CALIDO'   AND t.tipo = 'PRIMAVERA_VERANO' THEN 18 + random() * 10
            WHEN c.clima = 'CALIDO'   AND t.tipo = 'OTONO_INVIERNO'   THEN  1 + random() * 3
            WHEN c.clima = 'FRIO'     AND t.tipo = 'OTONO_INVIERNO'   THEN 16 + random() * 10
            WHEN c.clima = 'FRIO'     AND t.tipo = 'PRIMAVERA_VERANO' THEN  2 + random() * 3
            WHEN c.clima = 'TEMPLADO' AND t.tipo IS NOT NULL          THEN  8 + random() * 7
            ELSE 10 + random() * 8
         END)::int,
        CASE
            WHEN c.clima = 'CALIDO' AND t.tipo = 'OTONO_INVIERNO'   THEN 1
            WHEN c.clima = 'FRIO'   AND t.tipo = 'PRIMAVERA_VERANO' THEN 1
            ELSE 5
        END
    FROM producto_variante pv
    JOIN producto p       ON p.id = pv.producto_id
    JOIN sucursal s       ON s.codigo IN ('SU-01','TJ-01','OR-01')
    CROSS JOIN LATERAL (SELECT CASE
            WHEN s.ciudad IN ('SANTA_CRUZ','TRINIDAD','COBIJA')    THEN 'CALIDO'
            WHEN s.ciudad IN ('LA_PAZ','EL_ALTO','ORURO','POTOSI') THEN 'FRIO'
            ELSE 'TEMPLADO' END AS clima) c
    LEFT JOIN temporada t ON t.id = p.temporada_id
    ON CONFLICT (sucursal_id, variante_id) DO NOTHING;
END $$;

-- Una suscripcion por sucursal que todavia no la tenga. Las del seed demo con su plan; cualquier
-- otra sucursal (alta desde CU12) arranca en prueba del plan Basico por 14 dias.
INSERT INTO suscripcion (sucursal_id, plan_id, estado, inicio, vence_en)
SELECT s.id,
       (SELECT id FROM plan WHERE codigo = COALESCE(x.plan, 'BASICO')),
       COALESCE(x.estado, 'PRUEBA')::estado_suscripcion,
       now() - COALESCE(x.desde, interval '0 days'),
       now() + COALESCE(x.vence, interval '14 days')
  FROM sucursal s
  LEFT JOIN (VALUES
        ('SC-01', 'PREMIUM',     'ACTIVA',  interval '90 days', interval '30 days'),
        ('LP-01', 'PROFESIONAL', 'ACTIVA',  interval '60 days', interval '25 days'),
        ('CB-01', 'PROFESIONAL', 'ACTIVA',  interval '60 days', interval '12 days'),
        ('SU-01', 'BASICO',      'ACTIVA',  interval '30 days', interval '20 days'),
        ('TJ-01', 'BASICO',      'PRUEBA',  interval '5 days',  interval '9 days'),
        ('OR-01', 'BASICO',      'VENCIDA', interval '45 days', interval '-3 days')
       ) AS x(codigo, plan, estado, desde, vence) ON x.codigo = s.codigo
 WHERE NOT EXISTS (SELECT 1 FROM suscripcion su WHERE su.sucursal_id = s.id);

INSERT INTO pago_suscripcion (suscripcion_id, plan_id, meses, monto, metodo, estado,
                              periodo_desde, periodo_hasta, creado_en, confirmado_en)
SELECT su.id, su.plan_id, 1, p.precio_mensual, 'TRANSFERENCIA', 'APROBADO',
       su.vence_en - interval '1 month', su.vence_en,
       su.vence_en - interval '1 month', su.vence_en - interval '1 month'
  FROM suscripcion su
  JOIN plan p ON p.id = su.plan_id
 WHERE su.estado IN ('ACTIVA','VENCIDA')
   AND NOT EXISTS (SELECT 1 FROM pago_suscripcion ps WHERE ps.suscripcion_id = su.id);

COMMIT;
