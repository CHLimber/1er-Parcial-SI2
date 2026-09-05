#!/usr/bin/env bash
# Aplica el esquema, la logica de negocio y (opcionalmente) los datos semilla a una base
# Postgres externa -- pensado para el Postgres que provisiona Railway, que no ejecuta estos
# .sql automaticamente como si hace docker-entrypoint-initdb.d en desarrollo local.
#
# Uso:
#   ./aplicar_en_railway.sh "postgresql://user:pass@host:puerto/db"          # con datos demo
#   ./aplicar_en_railway.sh "postgresql://user:pass@host:puerto/db" --sin-seed  # sin 03_datos_iniciales.sql
#
# La URL debe ser la PUBLICA del plugin Postgres de Railway (variable DATABASE_PUBLIC_URL en
# el tab "Variables" del servicio Postgres) -- la variable DATABASE_URL interna
# (postgres.railway.internal) no es alcanzable desde fuera de la red privada de Railway.
#
# No requiere psql instalado localmente: corre un contenedor postgres:16 descartable.
set -euo pipefail

DSN="${1:?Uso: $0 <DATABASE_PUBLIC_URL> [--sin-seed]}"
SIN_SEED="${2:-}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ARCHIVOS=(01_schema.sql 02_logica.sql)
if [ "$SIN_SEED" != "--sin-seed" ]; then
  ARCHIVOS+=(03_datos_iniciales.sql)
fi

for archivo in "${ARCHIVOS[@]}"; do
  echo "== Aplicando $archivo =="
  docker run --rm -i postgres:16 psql "$DSN" -v ON_ERROR_STOP=1 < "$DIR/$archivo"
done

echo "Listo: esquema aplicado a la base de Railway."
