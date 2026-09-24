-- =====================================================================
--  Reparacion/migracion: pagos EFECTIVO y QR verificados por el cajero (2.19.1.b/c)
--
--  Sirve para una base YA desplegada (Railway) que no se puede recrear con
--  "docker compose down -v". Agrega a `pago` las columnas que usan
--  POST /pagos/qr/{venta_id}/informar (la clienta avisa que ya pago) y
--  POST /caja/pagos/{pago_id}/aprobar|rechazar (el cajero lo resuelve):
--    - informado_en        cuando la clienta aviso "ya pague" (solo QR)
--    - referencia_cliente  nro. de operacion / comentario que dejo la clienta
--    - verificado_por_id   cajero que aprobo o rechazo el pago
--
--  Sintoma sin este script: GET /ventas/{id}, GET /caja/pagos-pendientes y el
--  checkout responden 500 "column ... informado_en does not exist".
--
--  Es idempotente (ADD COLUMN IF NOT EXISTS): se puede correr las veces que haga
--  falta. No toca pagos existentes. Vive en db/reparaciones/ para que
--  docker-entrypoint-initdb.d no lo ejecute en local (ahi ya lo trae 01_schema.sql).
--
--  Uso:
--    docker run --rm -i postgres:16 psql "<DATABASE_PUBLIC_URL>" -v ON_ERROR_STOP=1 \
--      < db/reparaciones/pagos_verificacion_caja.sql
-- =====================================================================

BEGIN;

ALTER TABLE pago ADD COLUMN IF NOT EXISTS informado_en       TIMESTAMPTZ;
ALTER TABLE pago ADD COLUMN IF NOT EXISTS referencia_cliente VARCHAR(200);
ALTER TABLE pago ADD COLUMN IF NOT EXISTS verificado_por_id  UUID REFERENCES usuario(id);

COMMIT;

-- Verificacion rapida.
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'pago'
  AND column_name IN ('informado_en', 'referencia_cliente', 'verificado_por_id')
ORDER BY column_name;
