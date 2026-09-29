import asyncio
import logging

import asyncpg
import stripe

from app.core.config import settings
from app.core.db import get_pool
from app.modules.pagos.servicio import confirmar_rechazado

logger = logging.getLogger(__name__)

# Si falta la clave 'pago_pendiente_horas_vigencia' en configuracion (base vieja sin la
# migracion db/reparaciones/expirar_reservas_skip_locked.sql), se usa este plazo.
PAGO_PENDIENTE_HORAS_POR_DEFECTO = 48

MENSAJE_PEDIDO_VENCIDO = (
    "Anulamos tu pedido {numero} porque nadie lo pago ni informo el pago a tiempo. "
    "No se te cobro nada y tu carrito sigue disponible para volver a intentarlo."
)


async def anular_pedidos_pendientes_vencidos(conn: asyncpg.Connection) -> int:
    """Pedidos online (WEB/MOVIL) en EFECTIVO o QR que quedaron PENDIENTE mas alla del plazo
    configurado sin que la clienta informara el pago: nadie los iba a vencer (el cajero solo ve
    su bandeja) y ademas le bloquean el carrito a la clienta (carrito/router.py). Si la clienta ya
    informo el QR (informado_en) no se toca: hay un deposito que el cajero tiene que verificar.

    FOR UPDATE ... SKIP LOCKED sobre pago y venta: si el cajero (o la clienta informando el QR)
    tiene tomado alguno, se saltea y se reintenta en el proximo ciclo; el recheck del WHERE sobre
    la fila bloqueada descarta los que se resolvieron o informaron mientras tanto. No hay stock
    que liberar: venta_detalle se inserta recien al aprobar el pago."""
    async with conn.transaction():
        vencidos = await conn.fetch(
            """
            SELECT p.id AS pago_id, v.id, v.sucursal_id, v.carrito_id, v.reserva_id,
                   v.promocion_id, v.numero
            FROM pago p
            JOIN venta v ON v.id = p.venta_id
            WHERE v.canal IN ('WEB', 'MOVIL')
              AND v.estado = 'PENDIENTE'
              AND p.estado = 'PENDIENTE'
              AND (p.metodo = 'EFECTIVO' OR p.pasarela = 'QR')
              AND p.informado_en IS NULL
              AND v.fecha < now() - interval '1 hour' * COALESCE(
                    (SELECT valor::numeric FROM configuracion
                      WHERE clave = 'pago_pendiente_horas_vigencia'),
                    $1::int)
            ORDER BY v.fecha
            LIMIT 100
            FOR UPDATE OF p, v SKIP LOCKED
            """,
            PAGO_PENDIENTE_HORAS_POR_DEFECTO,
        )
        for fila in vencidos:
            await confirmar_rechazado(
                conn, fila["pago_id"], dict(fila), mensaje_cliente=MENSAJE_PEDIDO_VENCIDO
            )
    return len(vencidos)


MENSAJE_TARJETA_VENCIDA = (
    "Anulamos tu pedido {numero} porque el pago con tarjeta no se completo a tiempo. "
    "No se te cobro nada y tu carrito sigue disponible para volver a intentarlo."
)

# mismo plazo que los pedidos en efectivo/QR (configuracion.pago_pendiente_horas_vigencia)
_FILTRO_PAYMENT_INTENT_VENCIDO = """
    v.canal IN ('WEB', 'MOVIL')
    AND v.estado = 'PENDIENTE'
    AND p.estado = 'PENDIENTE'
    AND p.pasarela = 'STRIPE'
    AND p.id_transaccion LIKE 'pi\\_%'
    AND v.fecha < now() - interval '1 hour' * COALESCE(
          (SELECT valor::numeric FROM configuracion
            WHERE clave = 'pago_pendiente_horas_vigencia'),
          $1::int)
"""


async def cancelar_payment_intents_vencidos(conn: asyncpg.Connection) -> int:
    """Checkouts del movil (PaymentIntent `pi_...`) que la clienta abandono. A diferencia de una
    Checkout Session de la web, que Stripe expira sola a las 24 h y avisa con
    checkout.session.expired, un PaymentIntent no vence nunca: la venta quedaba PENDIENTE para
    siempre. Se cancela en Stripe primero (asi ya no se puede cobrar) y recien despues se anula en
    la base; si Stripe no lo deja cancelar (p.ej. ya se cobro y el webhook viene en camino) se
    saltea y lo resuelve el webhook."""
    if not settings.stripe_secret_key:
        return 0
    candidatos = await conn.fetch(
        f"""
        SELECT p.id AS pago_id, p.id_transaccion
        FROM pago p JOIN venta v ON v.id = p.venta_id
        WHERE {_FILTRO_PAYMENT_INTENT_VENCIDO}
        ORDER BY v.fecha
        LIMIT 50
        """,
        PAGO_PENDIENTE_HORAS_POR_DEFECTO,
    )
    anulados = 0
    for candidato in candidatos:
        try:
            await asyncio.to_thread(stripe.PaymentIntent.cancel, candidato["id_transaccion"])
        except stripe.error.StripeError:
            logger.warning(
                "No se pudo cancelar en Stripe el PaymentIntent %s; queda para el webhook",
                candidato["id_transaccion"],
            )
            continue
        async with conn.transaction():
            # SKIP LOCKED + recheck: si el webhook payment_intent.canceled lo esta procesando (o
            # ya lo proceso) no se pisa
            fila = await conn.fetchrow(
                f"""
                SELECT p.id AS pago_id, v.id, v.sucursal_id, v.carrito_id, v.reserva_id,
                       v.promocion_id, v.numero
                FROM pago p JOIN venta v ON v.id = p.venta_id
                WHERE p.id = $2 AND {_FILTRO_PAYMENT_INTENT_VENCIDO}
                FOR UPDATE OF p, v SKIP LOCKED
                """,
                PAGO_PENDIENTE_HORAS_POR_DEFECTO,
                candidato["pago_id"],
            )
            if fila is None:
                continue
            await confirmar_rechazado(
                conn, fila["pago_id"], dict(fila), mensaje_cliente=MENSAJE_TARJETA_VENCIDA
            )
            anulados += 1
    return anulados


async def job_expirar_reservas(intervalo_segundos: int) -> None:
    """CU04 E2: corre en loop mientras el backend esta arriba y llama a
    fn_expirar_reservas() para liberar el stock comprometido por reservas vencidas.
    Antes de esto, la unica forma de liberarlas era que un Encargado marcara la
    reserva "no se presento" a mano desde CU08 (ver PENDIENTES.txt 2.3).

    En la misma pasada anula los pedidos online en efectivo/QR abandonados
    (anular_pedidos_pendientes_vencidos). Cada tarea tiene su propio try: que falle una no
    impide la otra."""
    while True:
        try:
            pool = get_pool()
            async with pool.acquire() as conn:
                try:
                    expiradas = await conn.fetchval("SELECT fn_expirar_reservas()")
                    if expiradas:
                        print(f"job_expirar_reservas: {expiradas} reserva(s) expirada(s) por vencimiento")
                except Exception as exc:  # noqa: BLE001
                    print(f"job_expirar_reservas: fallo la expiracion de reservas ({exc!r})")
                try:
                    anulados = await anular_pedidos_pendientes_vencidos(conn)
                    if anulados:
                        print(f"job_expirar_reservas: {anulados} pedido(s) efectivo/QR anulado(s) por vencimiento")
                except Exception as exc:  # noqa: BLE001
                    print(f"job_expirar_reservas: fallo la anulacion de pedidos vencidos ({exc!r})")
                try:
                    cancelados = await cancelar_payment_intents_vencidos(conn)
                    if cancelados:
                        print(f"job_expirar_reservas: {cancelados} pago(s) Stripe movil cancelado(s) por vencimiento")
                except Exception as exc:  # noqa: BLE001
                    print(f"job_expirar_reservas: fallo la cancelacion de pagos Stripe ({exc!r})")
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # nunca debe tumbar el backend por un fallo transitorio de la BD
            print(f"job_expirar_reservas: fallo un ciclo ({exc!r}), reintenta en el proximo")
        await asyncio.sleep(intervalo_segundos)
