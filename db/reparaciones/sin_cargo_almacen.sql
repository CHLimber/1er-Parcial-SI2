-- =====================================================================
--  Reparacion/migracion: se elimina el cargo y el rol ALMACEN (PENDIENTES 9.9)
--
--  Los actores documentados son CLIENTE, SUPERADMIN, ADMIN, ENCARGADO y el empleado (CAJERO o
--  VENDEDOR). ALMACEN solo recibia mercaderia y ajustaba stock, y ENCARGADO ya tiene todos esos
--  permisos, asi que:
--
--    1. Las cuentas con rol ALMACEN pasan a ENCARGADO y sus filas de empleado tambien.
--    2. Se borra el rol ALMACEN (y su matriz de permisos).
--    3. Se recrea el tipo cargo_empleado sin ALMACEN (Postgres no soporta DROP VALUE).
--
--  Los usuarios de demo que el seed ya no crea (almacen.scz, cajera.lapaz, encargado.cbba,
--  cajero.sucre, cajera.tarija, cajera.oruro) NO se tocan: una base existente puede tener
--  actividad de ellos. Se desactivan desde CU13 (/panel/usuarios) o recreando el volumen.
--
--  Es re-ejecutable. Uso:
--    docker run --rm -i postgres:16 psql "<DATABASE_PUBLIC_URL>" -v ON_ERROR_STOP=1 \
--      < db/reparaciones/sin_cargo_almacen.sql
-- =====================================================================

BEGIN;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM rol WHERE nombre = 'ALMACEN' AND empresa_id IS NULL) THEN
        UPDATE usuario
           SET rol_id = (SELECT id FROM rol WHERE nombre = 'ENCARGADO' AND empresa_id IS NULL)
         WHERE rol_id = (SELECT id FROM rol WHERE nombre = 'ALMACEN' AND empresa_id IS NULL);

        DELETE FROM rol_permiso
         WHERE rol_id = (SELECT id FROM rol WHERE nombre = 'ALMACEN' AND empresa_id IS NULL);
        DELETE FROM rol WHERE nombre = 'ALMACEN' AND empresa_id IS NULL;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
                WHERE t.typname = 'cargo_empleado' AND e.enumlabel = 'ALMACEN') THEN
        UPDATE empleado SET cargo = 'ENCARGADO' WHERE cargo::text = 'ALMACEN';

        CREATE TYPE cargo_empleado_nuevo AS ENUM ('ENCARGADO','CAJERO','VENDEDOR');
        ALTER TABLE empleado ALTER COLUMN cargo TYPE cargo_empleado_nuevo
            USING cargo::text::cargo_empleado_nuevo;
        DROP TYPE cargo_empleado;
        ALTER TYPE cargo_empleado_nuevo RENAME TO cargo_empleado;
    END IF;
END
$$;

COMMENT ON TABLE rol IS 'SUPERADMIN (plataforma), ADMIN (de empresa), ENCARGADO, CAJERO, VENDEDOR (los del sistema; CU13 puede crear otros por empresa). Solo aplica a usuarios STAFF.';

COMMIT;

-- Resultado esperado: sin rol ALMACEN y cargos {ENCARGADO,CAJERO,VENDEDOR}
SELECT (SELECT count(*) FROM rol WHERE nombre = 'ALMACEN') AS rol_almacen,
       (SELECT array_agg(enumlabel ORDER BY enumsortorder) FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
          WHERE t.typname = 'cargo_empleado') AS cargos_actuales;
