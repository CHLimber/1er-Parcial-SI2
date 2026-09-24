-- =====================================================================
--  Reparacion/migracion: fn_expirar_reservas con FOR UPDATE SKIP LOCKED +
--  vencimiento de pedidos online EFECTIVO/QR abandonados.
--
--  1) Reemplaza fn_expirar_reservas() (misma firma, RETURNS INT) por la version
--     que bloquea cada reserva vencida (SKIP LOCKED), pasa sus items vivos a
--     DESCARTADO y no expira las que tienen una venta PENDIENTE ligada. La
--     version vieja no bloqueaba nada: podia competir con cancelar/rechazar y
--     liberar el mismo stock dos veces.
--  2) Siembra 'pago_pendiente_horas_vigencia' en configuracion, que lee el job
--     periodico del backend (app/core/jobs.py) para anular pedidos online en
--     EFECTIVO/QR que nadie pago ni informo. Si falta, el job usa 48 por defecto.
--
--  Idempotente (CREATE OR REPLACE / ON CONFLICT DO NOTHING). Vive en
--  db/reparaciones/ porque docker-entrypoint-initdb.d solo corre el primer
--  nivel de db/: en local basta con `docker compose down -v` o con correrlo a mano.
--
--  Uso:
--    docker exec -i fashionstore-db-1 psql -U fashionstore -d fashionstore -v ON_ERROR_STOP=1 --      < db/reparaciones/expirar_reservas_skip_locked.sql
--    docker run --rm -i postgres:16 psql "<DATABASE_PUBLIC_URL>" -v ON_ERROR_STOP=1 --      < db/reparaciones/expirar_reservas_skip_locked.sql
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
--  EXPIRACION DE RESERVAS VENCIDAS
--  La llama el job periodico del backend (app/core/jobs.py) cada pocos minutos.
--  Sin esto, el cliente que no aparece congela el stock para siempre.
--
--  Concurrencia: compite con los endpoints que tambien liberan el compromiso
--  (cancelar/rechazar/no-presentado en reservas/router.py, que bloquean la reserva
--  con FOR UPDATE) y con el checkout de un carrito armado desde la reserva. Por eso:
--   * cada reserva vencida se BLOQUEA (FOR UPDATE SKIP LOCKED) antes de tocarla: si
--     otro la tiene tomada se la saltea y la agarra el proximo ciclo, ya con el
--     estado actualizado (el recheck del WHERE sobre la fila bloqueada descarta la
--     que otro ya paso a CANCELADA/ATENDIDA/...);
--   * los items liberados pasan a DESCARTADO en la misma transaccion (igual que
--     _liberar_compromiso), asi nadie los vuelve a liberar y la reserva EXPIRADA no
--     queda con items "vivos";
--   * no se expira una reserva con una venta PENDIENTE ligada (venta.reserva_id):
--     cuando ese pago se apruebe, tg_venta_descuenta_stock libera el compromiso de la
--     reserva antes de descontar, y si ya lo hubiera liberado este job, se liberaria
--     dos veces. Se re-chequea con una sentencia aparte (snapshot nuevo) DESPUES de
--     tener el lock, porque el checkout inserta la venta con la reserva bloqueada.
--  Devuelve la cantidad de reservas expiradas.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_expirar_reservas()
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE
    r          RECORD;
    d          RECORD;
    v_contador INT := 0;
BEGIN
    FOR r IN
        SELECT res.id, res.sucursal_id
          FROM reserva res
         WHERE res.estado IN ('PENDIENTE','CONFIRMADA','PREPARADA')
           AND res.expira_en < now()
         ORDER BY res.expira_en
           FOR UPDATE SKIP LOCKED
    LOOP
        IF EXISTS (SELECT 1 FROM venta v
                    WHERE v.reserva_id = r.id AND v.estado = 'PENDIENTE') THEN
            CONTINUE;  -- la resuelve el pago en curso; si se anula, la expira el proximo ciclo
        END IF;

        FOR d IN
            SELECT rd.variante_id, rd.cantidad
              FROM reserva_detalle rd
             WHERE rd.reserva_id = r.id
               AND rd.estado_item IN ('RESERVADO','PREPARADO')
        LOOP
            PERFORM fn_mover_inventario(
                r.sucursal_id, d.variante_id, 'LIBERACION', d.cantidad,
                'Reserva expirada sin presentacion del cliente', 'RESERVA', r.id);
        END LOOP;

        UPDATE reserva_detalle
           SET estado_item = 'DESCARTADO'
         WHERE reserva_id = r.id
           AND estado_item IN ('RESERVADO','PREPARADO');

        UPDATE reserva SET estado = 'EXPIRADA' WHERE id = r.id;
        v_contador := v_contador + 1;
    END LOOP;

    RETURN v_contador;
END;
$$;

COMMENT ON FUNCTION fn_expirar_reservas IS
    'Expira las reservas vencidas y libera su stock comprometido (items -> DESCARTADO). '
    'Bloquea cada reserva con FOR UPDATE SKIP LOCKED y saltea las que tienen una venta '
    'PENDIENTE ligada. Debe ejecutarse periodicamente; devuelve cuantas reservas expiro.';

INSERT INTO configuracion (clave, valor, descripcion) VALUES
    ('pago_pendiente_horas_vigencia', '48',
     'Horas antes de anular un pedido online en efectivo/QR sin pagar ni informar')
ON CONFLICT (clave) DO NOTHING;

COMMIT;
