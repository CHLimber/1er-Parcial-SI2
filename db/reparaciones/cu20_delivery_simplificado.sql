-- =====================================================================
--  Reparacion/migracion: CU20 "Entrega a Domicilio" -- simplificacion a servicio externo
--
--  Decision de negocio (2026-09-18): FashionStore NO reparte con personal propio, contrata
--  un servicio de delivery externo. La sucursal solo controla dos momentos: cuando el
--  paquete SALE hacia el servicio de delivery (DESPACHADO) y cuando el servicio confirma
--  que LLEGO (ENTREGADO) o que fallo (FALLIDO). Por eso esta migracion:
--
--    1. Colapsa estado_envio: ASIGNADO y EN_RUTA pasan a DESPACHADO (se agrega el valor
--       nuevo, se reasignan las filas, se recrea el tipo sin los valores viejos).
--    2. Quita el concepto de "repartidor" empleado: columna envio.repartidor_id (y su
--       constraint/indice), columna envio.asignado_en, permiso REPARTIDOR de cargo_empleado,
--       y el rol REPARTIDOR (con sus permisos y usuarios reasignados a ALMACEN, desactivados
--       para que un ADMIN los revise y les asigne un cargo real desde CU13).
--
--  Corre DESPUES de db/reparaciones/cu20_delivery.sql (asume que esas tablas ya existen).
--  Es re-ejecutable: si ya se corrio, las partes que dependen de 'REPARTIDOR'/'ASIGNADO'/
--  'EN_RUTA' quedan como no-ops porque esos valores ya no estan.
--
--  Uso:
--    docker run --rm -i postgres:16 psql "<DATABASE_PUBLIC_URL>" -v ON_ERROR_STOP=1 \
--      < db/reparaciones/cu20_delivery_simplificado.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Agregar el valor nuevo del enum antes de poder usarlo en un UPDATE.
--    ALTER TYPE ... ADD VALUE no puede correr dentro de la misma transaccion que lo consume.
-- ---------------------------------------------------------------------

ALTER TYPE estado_envio ADD VALUE IF NOT EXISTS 'DESPACHADO';

BEGIN;

-- ---------------------------------------------------------------------
-- 2. Colapsar ASIGNADO/EN_RUTA -> DESPACHADO en los datos existentes
--    (no-op si esos valores ya no estan en el tipo).
-- ---------------------------------------------------------------------

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
         WHERE t.typname = 'estado_envio' AND e.enumlabel IN ('ASIGNADO','EN_RUTA')
    ) THEN
        UPDATE envio SET estado = 'DESPACHADO'
         WHERE estado::text IN ('ASIGNADO','EN_RUTA');
        UPDATE envio_evento SET estado = 'DESPACHADO'
         WHERE estado::text IN ('ASIGNADO','EN_RUTA');
    END IF;
END
$$;

-- ---------------------------------------------------------------------
-- 3. Reasignar cualquier empleado/usuario con cargo o rol REPARTIDOR antes de poder
--    borrar esos valores. Se los desactiva para que un ADMIN los revise desde CU13 y les
--    ponga un cargo real -- no se asume que "ALMACEN" sea correcto para esa persona.
-- ---------------------------------------------------------------------

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
                WHERE t.typname = 'cargo_empleado' AND e.enumlabel = 'REPARTIDOR') THEN
        UPDATE empleado SET cargo = 'ALMACEN', activo = FALSE
         WHERE cargo::text = 'REPARTIDOR';
    END IF;

    IF EXISTS (SELECT 1 FROM rol WHERE nombre = 'REPARTIDOR') THEN
        UPDATE usuario SET rol_id = (SELECT id FROM rol WHERE nombre = 'ALMACEN'), activo = FALSE
         WHERE rol_id = (SELECT id FROM rol WHERE nombre = 'REPARTIDOR');

        DELETE FROM rol_permiso WHERE rol_id = (SELECT id FROM rol WHERE nombre = 'REPARTIDOR');
        DELETE FROM rol WHERE nombre = 'REPARTIDOR';
    END IF;
END
$$;

-- ---------------------------------------------------------------------
-- 4. Columnas y objetos de envio que ya no aplican
-- ---------------------------------------------------------------------

ALTER TABLE envio DROP CONSTRAINT IF EXISTS ck_envio_repartidor;
DROP INDEX IF EXISTS ix_envio_repartidor;
ALTER TABLE envio DROP COLUMN IF EXISTS repartidor_id;
ALTER TABLE envio DROP COLUMN IF EXISTS asignado_en;

-- ---------------------------------------------------------------------
-- 5. Descripciones de permisos (cosmetico, no cambia codigos ni asignaciones)
-- ---------------------------------------------------------------------

UPDATE permiso SET descripcion = 'Consultar los envios a domicilio y su estado de despacho'
 WHERE codigo = 'envios.leer';
UPDATE permiso SET descripcion = 'Marcar un envio como despachado, entregado o fallido'
 WHERE codigo = 'envios.actualizar';

COMMIT;

-- ---------------------------------------------------------------------
-- 6. Recrear estado_envio y cargo_empleado sin los valores viejos.
--    ALTER TYPE ... DROP VALUE no existe en Postgres: hay que recrear el tipo.
--    Va fuera de la transaccion anterior porque ALTER TYPE ... ADD VALUE (paso 1) tampoco
--    puede compartir transaccion con esto, y conviene mantener cada tipo en su propio bloque.
-- ---------------------------------------------------------------------

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
                WHERE t.typname = 'estado_envio' AND e.enumlabel IN ('ASIGNADO','EN_RUTA')) THEN
        CREATE TYPE estado_envio_nuevo AS ENUM ('PENDIENTE','DESPACHADO','ENTREGADO','FALLIDO','CANCELADO');

        ALTER TABLE envio ALTER COLUMN estado DROP DEFAULT;
        ALTER TABLE envio ALTER COLUMN estado TYPE estado_envio_nuevo USING estado::text::estado_envio_nuevo;
        ALTER TABLE envio ALTER COLUMN estado SET DEFAULT 'PENDIENTE';
        ALTER TABLE envio_evento ALTER COLUMN estado TYPE estado_envio_nuevo USING estado::text::estado_envio_nuevo;

        DROP TYPE estado_envio;
        ALTER TYPE estado_envio_nuevo RENAME TO estado_envio;
    END IF;
END
$$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
                WHERE t.typname = 'cargo_empleado' AND e.enumlabel = 'REPARTIDOR') THEN
        CREATE TYPE cargo_empleado_nuevo AS ENUM ('ENCARGADO','CAJERO','VENDEDOR','ALMACEN');

        ALTER TABLE empleado ALTER COLUMN cargo TYPE cargo_empleado_nuevo
            USING cargo::text::cargo_empleado_nuevo;

        DROP TYPE cargo_empleado;
        ALTER TYPE cargo_empleado_nuevo RENAME TO cargo_empleado;
    END IF;
END
$$;

-- Resultado esperado: 0 filas de REPARTIDOR en ambos casos, y el tipo ya sin esos valores.
SELECT (SELECT count(*) FROM empleado WHERE cargo::text = 'REPARTIDOR')      AS empleados_repartidor,
       (SELECT count(*) FROM rol WHERE nombre = 'REPARTIDOR')                AS rol_repartidor,
       (SELECT count(*) FROM envio WHERE estado::text IN ('ASIGNADO','EN_RUTA')) AS envios_sin_migrar,
       (SELECT array_agg(enumlabel) FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
          WHERE t.typname = 'estado_envio')                                  AS estados_envio_actuales,
       (SELECT array_agg(enumlabel) FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
          WHERE t.typname = 'cargo_empleado')                                AS cargos_actuales;
