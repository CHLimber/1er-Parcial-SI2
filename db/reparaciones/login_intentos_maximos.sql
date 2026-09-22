-- =====================================================================
--  Reparacion/migracion: intentos maximos de login + politica de contrasena
--  con caracter especial.
--
--  Sirve para una base ya desplegada (Railway) que no tiene las columnas
--  nuevas de `usuario` (intentos_fallidos, bloqueado_hasta) ni los parametros
--  de `configuracion` que POST /auth/login pasa a exigir.
--
--  Sintoma sin este script: POST /auth/login responde 500
--  "column u.intentos_fallidos does not exist" para CUALQUIER login, incluso
--  con credenciales correctas -- es bloqueante, no un detalle cosmetico.
--
--  Es idempotente (ADD COLUMN IF NOT EXISTS / ON CONFLICT DO NOTHING): se
--  puede correr las veces que haga falta. No toca usuarios existentes (todos
--  arrancan con 0 intentos fallidos y sin bloqueo).
--
--  Este archivo vive en db/reparaciones/ a proposito: docker-entrypoint-
--  initdb.d solo ejecuta lo que esta en el primer nivel de db/, asi que no
--  se corre solo en local (docker compose down -v ya toma la version nueva
--  de 01_schema.sql/03_datos_iniciales.sql directamente).
--
--  Uso:
--    docker run --rm -i postgres:16 psql "<DATABASE_PUBLIC_URL>" -v ON_ERROR_STOP=1 \
--      < db/reparaciones/login_intentos_maximos.sql
-- =====================================================================

BEGIN;

ALTER TABLE usuario ADD COLUMN IF NOT EXISTS intentos_fallidos SMALLINT NOT NULL DEFAULT 0;
ALTER TABLE usuario ADD COLUMN IF NOT EXISTS bloqueado_hasta TIMESTAMPTZ;

INSERT INTO configuracion (clave, valor, descripcion) VALUES
    ('login_max_intentos',    '5',  'Intentos fallidos de login permitidos antes de bloquear la cuenta'),
    ('login_bloqueo_minutos', '15', 'Minutos que la cuenta queda bloqueada tras superar login_max_intentos')
ON CONFLICT (clave) DO NOTHING;

COMMIT;

-- Verificacion rapida.
SELECT column_name, data_type, column_default
  FROM information_schema.columns
 WHERE table_name = 'usuario' AND column_name IN ('intentos_fallidos', 'bloqueado_hasta');

SELECT clave, valor FROM configuracion WHERE clave LIKE 'login_%';
