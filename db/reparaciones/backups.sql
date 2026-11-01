-- =====================================================================
--  Migracion: copias de seguridad (tabla backup + permisos backups.*)
--
--  Para bases ya desplegadas (Railway, o el volumen local de Docker sin recrear): crea los tipos,
--  la tabla `backup` y los permisos, y se los da al ADMIN de cada empresa y al SUPERADMIN.
--  Idempotente: se puede correr las veces que haga falta. No toca datos de negocio.
--
--  Uso:
--    docker run --rm -i postgres:18 psql "<DATABASE_PUBLIC_URL>" -v ON_ERROR_STOP=1 \
--      < db/reparaciones/backups.sql
-- =====================================================================

BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tipo_backup') THEN
        CREATE TYPE tipo_backup AS ENUM ('AUTOMATICO','MANUAL');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'estado_backup') THEN
        CREATE TYPE estado_backup AS ENUM ('EN_CURSO','COMPLETADO','FALLIDO');
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS backup (
    id            UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id    UUID          REFERENCES empresa(id) ON DELETE CASCADE,
    tipo          tipo_backup   NOT NULL,
    estado        estado_backup NOT NULL DEFAULT 'EN_CURSO',
    iniciado_en   TIMESTAMPTZ   NOT NULL DEFAULT now(),
    terminado_en  TIMESTAMPTZ,
    creado_por_id UUID          REFERENCES usuario(id) ON DELETE SET NULL,
    archivo       VARCHAR(200),
    tamano_bytes  BIGINT,
    total_tablas  INT,
    total_filas   BIGINT,
    sha256        CHAR(64),
    detalle       JSONB,
    error         VARCHAR(500),
    CONSTRAINT ck_backup_automatico_general CHECK (tipo <> 'AUTOMATICO' OR empresa_id IS NULL)
);
CREATE INDEX IF NOT EXISTS ix_backup_empresa ON backup(empresa_id, iniciado_en DESC);
CREATE UNIQUE INDEX IF NOT EXISTS ux_backup_en_curso
    ON backup ((COALESCE(empresa_id, '00000000-0000-0000-0000-000000000000'::uuid)))
    WHERE estado = 'EN_CURSO';

INSERT INTO permiso (codigo, modulo, descripcion) VALUES
    ('backups.leer',     'backups', 'Ver y descargar las copias de seguridad'),
    ('backups.crear',    'backups', 'Generar una copia de seguridad manual'),
    ('backups.eliminar', 'backups', 'Eliminar una copia de seguridad')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id
  FROM rol r, permiso p
 WHERE r.nombre IN ('ADMIN', 'SUPERADMIN') AND p.modulo = 'backups'
ON CONFLICT DO NOTHING;

COMMIT;
