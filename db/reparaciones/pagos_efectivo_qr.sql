-- =====================================================================
--  Reparacion/migracion: pago en Efectivo y renombre de Libelula a QR (CU05/CU06)
--
--  Sirve para una base YA desplegada (tipico: Railway) que no se puede recrear con
--  "docker compose down -v". Que agrega:
--    1. Renombra el valor 'LIBELULA' del ENUM pasarela_pago a 'QR' (misma pasarela
--       simulada de siempre, solo cambia el nombre que ve la clienta).
--
--  metodo_pago ya tenia 'EFECTIVO' desde el esquema original (lo usa CU07/POS), asi que
--  el checkout web/movil con EFECTIVO no necesita ningun cambio de esquema -- solo el
--  backend nuevo, que ya sabe insertar pago.pasarela = NULL para ese metodo.
--
--  Es idempotente: se puede correr las veces que haga falta.
--
--  Uso:
--    docker run --rm -i postgres:18 psql "<DATABASE_PUBLIC_URL>" -v ON_ERROR_STOP=1 \
--      < db/reparaciones/pagos_efectivo_qr.sql
-- =====================================================================

-- ALTER TYPE ... RENAME VALUE no corre dentro de una transaccion que ademas lo consuma,
-- asi que va suelto, antes de cualquier BEGIN.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
        WHERE t.typname = 'pasarela_pago' AND e.enumlabel = 'LIBELULA'
    ) THEN
        ALTER TYPE pasarela_pago RENAME VALUE 'LIBELULA' TO 'QR';
    END IF;
END
$$;
