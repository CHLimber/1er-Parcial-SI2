-- =====================================================================
--  Reparacion/migracion: se elimina el cargo y el rol VENDEDOR (PENDIENTES 9.10)
--
--  "Cajero y vendedor es la misma cosa": se queda CAJERO, que es el mas versatil. Los actores
--  quedan SUPERADMIN, ADMIN, ENCARGADO y el empleado (CAJERO), asi que:
--
--    1. CAJERO absorbe los permisos del VENDEDOR que no tenia (reservas.leer y
--       reservas.actualizar: el cajero ahora tambien atiende reservas en el piso).
--    2. Las cuentas con rol VENDEDOR pasan a CAJERO y sus filas de empleado tambien.
--    3. Se borra el rol VENDEDOR (y su matriz de permisos).
--    4. Se recrea el tipo cargo_empleado sin VENDEDOR (Postgres no soporta DROP VALUE).
--
--  La cuenta de demo que el seed ya no crea (vendedor.scz) NO se borra: una base existente puede
--  tener actividad de ella (reservas atendidas, ventas registradas). Queda como CAJERO y se
--  desactiva desde CU13 (/panel/usuarios) o recreando el volumen. Despues de migrar, quien ya
--  tenia sesion abierta debe volver a iniciarla para que le lleguen los permisos nuevos.
--
--  Es re-ejecutable. Uso:
--    docker run --rm -i postgres:16 psql "<DATABASE_PUBLIC_URL>" -v ON_ERROR_STOP=1 \
--      < db/reparaciones/sin_cargo_vendedor.sql
-- =====================================================================

BEGIN;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM rol WHERE nombre = 'VENDEDOR' AND empresa_id IS NULL) THEN
        -- Lo que tenia el VENDEDOR y no el CAJERO pasa al CAJERO
        INSERT INTO rol_permiso (rol_id, permiso_id)
        SELECT (SELECT id FROM rol WHERE nombre = 'CAJERO' AND empresa_id IS NULL), rp.permiso_id
          FROM rol_permiso rp
         WHERE rp.rol_id = (SELECT id FROM rol WHERE nombre = 'VENDEDOR' AND empresa_id IS NULL)
        ON CONFLICT DO NOTHING;

        UPDATE usuario
           SET rol_id = (SELECT id FROM rol WHERE nombre = 'CAJERO' AND empresa_id IS NULL)
         WHERE rol_id = (SELECT id FROM rol WHERE nombre = 'VENDEDOR' AND empresa_id IS NULL);

        DELETE FROM rol_permiso
         WHERE rol_id = (SELECT id FROM rol WHERE nombre = 'VENDEDOR' AND empresa_id IS NULL);
        DELETE FROM rol WHERE nombre = 'VENDEDOR' AND empresa_id IS NULL;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
                WHERE t.typname = 'cargo_empleado' AND e.enumlabel = 'VENDEDOR') THEN
        UPDATE empleado SET cargo = 'CAJERO' WHERE cargo::text = 'VENDEDOR';

        CREATE TYPE cargo_empleado_nuevo AS ENUM ('ENCARGADO','CAJERO');
        ALTER TABLE empleado ALTER COLUMN cargo TYPE cargo_empleado_nuevo
            USING cargo::text::cargo_empleado_nuevo;
        DROP TYPE cargo_empleado;
        ALTER TYPE cargo_empleado_nuevo RENAME TO cargo_empleado;
    END IF;
END
$$;

COMMENT ON TABLE rol IS 'SUPERADMIN (plataforma), ADMIN (de empresa), ENCARGADO, CAJERO (los del sistema; CU13 puede crear otros por empresa). Solo aplica a usuarios STAFF.';

COMMIT;

-- Resultado esperado: sin rol VENDEDOR, cargos {ENCARGADO,CAJERO} y CAJERO con reservas.leer/actualizar
SELECT (SELECT count(*) FROM rol WHERE nombre = 'VENDEDOR') AS rol_vendedor,
       (SELECT array_agg(enumlabel ORDER BY enumsortorder) FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
          WHERE t.typname = 'cargo_empleado') AS cargos_actuales,
       (SELECT count(*) FROM rol_permiso rp JOIN rol r ON r.id = rp.rol_id
          JOIN permiso p ON p.id = rp.permiso_id
         WHERE r.nombre = 'CAJERO' AND r.empresa_id IS NULL
           AND p.codigo IN ('reservas.leer', 'reservas.actualizar')) AS cajero_con_reservas;
