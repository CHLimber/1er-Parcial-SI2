import asyncio

import asyncpg

from app.core.db import get_pool
from app.modules.pagos.servicio import confirmar_rechazado

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
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # nunca debe tumbar el backend por un fallo transitorio de la BD
            print(f"job_expirar_reservas: fallo un ciclo ({exc!r}), reintenta en el proximo")
        await asyncio.sleep(intervalo_segundos)
