"""CU06 - confirmar (o rechazar) un pago ya iniciado.

La logica de "cerrar" un pago es la misma sin importar quien la dispare: el webhook firmado de
Stripe, o el CAJERO de la sucursal cuando verifica un pago QR o cobra un pedido en EFECTIVO
(caja/router.py, 2.19.1.b/c -- antes el QR lo "aprobaba" la propia clienta y el efectivo se
aprobaba solo en el checkout). Por eso vive aca y no en pagos/router.py: la usan pagos/router.py
(webhook de Stripe), caja/router.py (verificacion en caja) y ventas/router.py (aviso a los
cajeros en el checkout con efectivo), y ventas/router.py no puede importar de pagos/router.py sin
generar un ciclo. Mismo criterio que envios/servicio.py: es la excepcion a "cada modulo se basta
a si mismo" para las funciones que de verdad comparten varios casos.
"""

import asyncio
import logging
from decimal import Decimal
from uuid import UUID, uuid4

import asyncpg
import stripe

from app.modules.envios.servicio import crear_envio_de_venta

logger = logging.getLogger(__name__)


async def confirmar_aprobado(conn: asyncpg.Connection, pago_id: UUID, venta: dict) -> dict:
    """Vuelca el carrito a venta_detalle (dispara fn_mover_inventario via trigger), marca el pago
    APROBADO y la venta PAGADA. Si el stock cambio entre el checkout y esta confirmacion, la venta
    se anula en vez de romper: si la plata ya se habia cobrado (Stripe, deposito QR) el pago queda
    REEMBOLSADO; si era EFECTIVO todavia no se cobro nada, asi que queda RECHAZADO.

    Se espera que el llamador ya tenga el pago y la venta bloqueados (FOR UPDATE) dentro de una
    transaccion: el insert de venta_detalle va en un savepoint propio para poder anular sin
    perder lo demas."""
    items = await conn.fetch(
        "SELECT variante_id, cantidad, precio_unitario FROM carrito_item WHERE carrito_id = $1",
        venta["carrito_id"],
    )

    # Se vuelca el carrito TAL COMO ESTA HOY: si la clienta lo cambio despues del checkout (p.ej.
    # con una sesion de Stripe ya abierta) se venderian otras prendas por el monto viejo. El cajero
    # ya lo frena antes de aprobar (caja/router.py); el webhook de Stripe no puede frenarlo porque
    # la plata ya se cobro, asi que se anula y se reembolsa.
    subtotal_venta = await conn.fetchval("SELECT subtotal FROM venta WHERE id = $1", venta["id"])
    subtotal_carrito = sum(item["precio_unitario"] * item["cantidad"] for item in items)
    if subtotal_carrito != subtotal_venta:
        return await _anular_por_conflicto(
            conn, pago_id, venta, "el carrito cambio despues del checkout"
        )

    if venta["reserva_id"] is not None and not await _reserva_respalda_items(
        conn, venta["reserva_id"], items
    ):
        # tg_venta_descuenta_stock libera el compromiso de la reserva antes de descontar: si la
        # reserva ya lo libero (se atendio en el vestidor, se cancelo o expiro) se liberaria dos
        # veces -- soltando lo que reservaron otras clientas -- y la prenda se venderia de nuevo
        return await _anular_por_conflicto(
            conn, pago_id, venta, "la reserva ya no respalda estas prendas"
        )

    try:
        async with conn.transaction():
            for item in items:
                subtotal_item = item["precio_unitario"] * item["cantidad"]
                await conn.execute(
                    """
                    INSERT INTO venta_detalle (venta_id, variante_id, cantidad, precio_unitario, subtotal)
                    VALUES ($1, $2, $3, $4, $5)
                    """,
                    venta["id"],
                    item["variante_id"],
                    item["cantidad"],
                    item["precio_unitario"],
                    subtotal_item,
                )
    except asyncpg.PostgresError as error:
        return await _anular_por_conflicto(conn, pago_id, venta, f"no se pudo descontar stock: {error}")

    await conn.execute(
        "UPDATE pago SET estado = 'APROBADO', confirmado_en = now() WHERE id = $1", pago_id
    )
    await conn.execute("UPDATE venta SET estado = 'PAGADA' WHERE id = $1", venta["id"])
    await conn.execute("UPDATE carrito SET estado = 'CONVERTIDO' WHERE id = $1", venta["carrito_id"])

    if venta["reserva_id"] is not None:
        variante_ids = [item["variante_id"] for item in items]
        await conn.execute(
            """
            UPDATE reserva_detalle SET estado_item = 'COMPRADO'
            WHERE reserva_id = $1 AND variante_id = ANY($2::uuid[])
            """,
            venta["reserva_id"],
            variante_ids,
        )
        # PREPARADO tambien cuenta: si la clienta saco del carrito una prenda que ya estaba
        # preparada, esa prenda sigue comprometida y la reserva no puede darse por CONVERTIDA
        # (fn_expirar_reservas ya no la miraria y el stock quedaria trabado para siempre)
        pendientes = await conn.fetchval(
            "SELECT COUNT(*) FROM reserva_detalle "
            "WHERE reserva_id = $1 AND estado_item IN ('RESERVADO', 'PREPARADO')",
            venta["reserva_id"],
        )
        if pendientes == 0:
            await conn.execute("UPDATE reserva SET estado = 'CONVERTIDA' WHERE id = $1", venta["reserva_id"])

    numero_comprobante = f"C-{uuid4().hex[:10].upper()}"
    await conn.execute(
        "INSERT INTO comprobante (venta_id, numero) VALUES ($1, $2)", venta["id"], numero_comprobante
    )
    # 2.19.3: la clienta no recibia ningun aviso cuando su pago se aprobaba
    await conn.execute(
        """
        INSERT INTO notificacion (usuario_id, tipo, titulo, mensaje, entidad_tipo, entidad_id)
        SELECT usuario_id, 'VENTA', 'Pago aprobado',
               'Tu pago del pedido ' || numero || ' fue aprobado. Comprobante ' || $2 || '.',
               'VENTA', id
        FROM venta WHERE id = $1 AND usuario_id IS NOT NULL
        """,
        venta["id"],
        numero_comprobante,
    )

    # CU20: recien con el pago aprobado hay algo que repartir. crear_envio_de_venta es idempotente
    # (UNIQUE en envio.venta_id) y devuelve None si la venta se retira en tienda.
    envio_id = await crear_envio_de_venta(conn, venta["id"])
    if envio_id is not None:
        await conn.execute(
            """
            INSERT INTO notificacion (usuario_id, tipo, titulo, mensaje, entidad_tipo, entidad_id)
            SELECT usuario_id, 'VENTA', 'Tu pedido sale a reparto',
                   'Preparamos el pedido ' || numero || ' para llevarlo a tu domicilio. '
                   || 'Te avisamos cuando lo despachemos al servicio de delivery.',
                   'ENVIO', $2
            FROM venta WHERE id = $1
            """,
            venta["id"],
            envio_id,
        )

    await _alertar_stock_bajo(conn, venta["sucursal_id"], venta["id"])

    return {"venta_estado": "PAGADA", "pago_estado": "APROBADO", "mensaje": "Pago confirmado"}


async def _reserva_respalda_items(
    conn: asyncpg.Connection, reserva_id: UUID, items: list[asyncpg.Record]
) -> bool:
    """Misma regla que ventas/router.py::_validar_reserva_del_carrito, pero al aprobar el pago:
    la reserva sigue viva y compromete al menos lo que se va a vender. La bloquea (FOR UPDATE)
    para que el Encargado no la resuelva entre este chequeo y el insert de venta_detalle."""
    estado = await conn.fetchval(
        "SELECT estado::text FROM reserva WHERE id = $1 FOR UPDATE", reserva_id
    )
    if estado not in ("PENDIENTE", "CONFIRMADA", "PREPARADA", "CLIENTE_PRESENTE"):
        return False
    comprometido = await conn.fetch(
        """
        SELECT variante_id, cantidad FROM reserva_detalle
        WHERE reserva_id = $1 AND estado_item IN ('RESERVADO', 'PREPARADO')
        """,
        reserva_id,
    )
    cantidad = {fila["variante_id"]: fila["cantidad"] for fila in comprometido}
    return all(cantidad.get(item["variante_id"], 0) >= item["cantidad"] for item in items)


async def _anular_por_conflicto(
    conn: asyncpg.Connection, pago_id: UUID, venta: dict, motivo: str
) -> dict:
    """La venta no se puede completar tal como se pago (stock o carrito cambiaron): se anula. Si
    la plata ya se habia cobrado (Stripe, deposito QR) el pago queda REEMBOLSADO; si era EFECTIVO
    todavia no se cobro nada, asi que queda RECHAZADO."""
    pago = await conn.fetchrow(
        "SELECT metodo::text AS metodo, pasarela::text AS pasarela, id_transaccion "
        "FROM pago WHERE id = $1",
        pago_id,
    )
    cobrado = pago["metodo"] != "EFECTIVO"
    estado_pago = "REEMBOLSADO" if cobrado else "RECHAZADO"
    if pago["pasarela"] == "STRIPE" and pago["id_transaccion"]:
        # REEMBOLSADO no puede ser solo un estado: con Stripe la plata se devuelve de verdad. El QR
        # es simulado (no hay API de la pasarela), su devolucion queda a cargo de la sucursal.
        await _reembolsar_stripe(pago["id_transaccion"])
    await conn.execute(
        "UPDATE pago SET estado = $2::estado_pago, confirmado_en = now() WHERE id = $1",
        pago_id,
        estado_pago,
    )
    await conn.execute("UPDATE venta SET estado = 'ANULADA' WHERE id = $1", venta["id"])
    # el cupon que habia consumido el checkout vuelve a quedar libre, igual que en un rechazo
    await conn.execute(
        """
        UPDATE promocion SET usos_actuales = GREATEST(usos_actuales - 1, 0)
        WHERE id = (SELECT promocion_id FROM venta WHERE id = $1)
        """,
        venta["id"],
    )
    texto = (
        "Recibimos tu pago del pedido {numero} pero el stock o tu carrito cambiaron antes de "
        "confirmarlo. "
        "Se genero un reembolso."
        if cobrado
        else "No pudimos completar tu pedido {numero}: el stock o tu carrito cambiaron antes de que la "
        "sucursal confirmara el cobro en efectivo. No se te cobro nada."
    )
    await conn.execute(
        """
        INSERT INTO notificacion (usuario_id, tipo, titulo, mensaje, entidad_tipo, entidad_id)
        SELECT usuario_id, 'VENTA', 'Pedido no se pudo completar',
               replace($2, '{numero}', numero), 'VENTA', id
        FROM venta WHERE id = $1 AND usuario_id IS NOT NULL
        """,
        venta["id"],
        texto,
    )
    return {
        "venta_estado": "ANULADA",
        "pago_estado": estado_pago,
        "mensaje": f"Venta anulada: {motivo}",
    }


async def _reembolsar_stripe(id_transaccion: str) -> bool:
    """Pide el reembolso total del cobro a Stripe. id_transaccion es una Checkout Session (`cs_`,
    web) o un PaymentIntent (`pi_`, movil). Devuelve False si Stripe fallo; _anular_por_conflicto
    no se corta por eso (la venta no se puede entregar igual): queda en el log para devolverlo a
    mano desde el dashboard."""
    try:
        payment_intent = id_transaccion
        if id_transaccion.startswith("cs_"):
            sesion = await asyncio.to_thread(stripe.checkout.Session.retrieve, id_transaccion)
            payment_intent = sesion["payment_intent"]
        if payment_intent:
            await asyncio.to_thread(stripe.Refund.create, payment_intent=payment_intent)
        return True
    except stripe.error.StripeError:
        logger.exception("No se pudo reembolsar en Stripe la transaccion %s", id_transaccion)
        return False


async def reembolsar_parcial_stripe(id_transaccion: str, monto: Decimal, clave: str) -> str:
    """Reembolso PARCIAL de un cobro de Stripe (devolucion de algunas prendas). Devuelve el id del
    Refund (`re_...`). A diferencia de _reembolsar_stripe no se traga el error: la devolucion no
    se puede aprobar si la plata no vuelve, asi que el llamador deshace la transaccion. `clave` va
    como idempotency key, asi reintentar la misma aprobacion no reembolsa dos veces."""
    payment_intent = id_transaccion
    if id_transaccion.startswith("cs_"):
        sesion = await asyncio.to_thread(stripe.checkout.Session.retrieve, id_transaccion)
        payment_intent = sesion["payment_intent"]
    reembolso = await asyncio.to_thread(
        stripe.Refund.create,
        payment_intent=payment_intent,
        amount=int((monto * 100).to_integral_value()),
        idempotency_key=clave,
    )
    return reembolso["id"]


async def reembolsar_pago_tardio(
    conn: asyncpg.Connection, pago_id: UUID, venta_id: UUID, id_transaccion: str
) -> bool:
    """Stripe confirmo el cobro de un intento que el checkout ya habia abandonado (pago
    RECHAZADO, venta ANULADA): se devuelve la plata y el pago queda REEMBOLSADO. Devuelve False
    si Stripe no acepto el reembolso, sin tocar la base, para que el webhook pida reintento."""
    if not await _reembolsar_stripe(id_transaccion):
        return False
    await conn.execute(
        "UPDATE pago SET estado = 'REEMBOLSADO', confirmado_en = now() WHERE id = $1", pago_id
    )
    await conn.execute(
        """
        INSERT INTO notificacion (usuario_id, tipo, titulo, mensaje, entidad_tipo, entidad_id)
        SELECT usuario_id, 'VENTA', 'Pago reembolsado',
               'Recibimos un pago del pedido ' || numero || ', que ya habias reemplazado por '
               || 'otro. Te lo devolvimos completo a tu tarjeta.',
               'VENTA', id
        FROM venta WHERE id = $1 AND usuario_id IS NOT NULL
        """,
        venta_id,
    )
    return True


async def cancelar_intento_stripe(id_transaccion: str) -> None:
    """Cierra en Stripe un intento de cobro que el checkout abandono, para que ya no se pueda
    pagar: expira la Checkout Session (web, `cs_`) o cancela el PaymentIntent (movil, `pi_`). Si
    Stripe no deja (p.ej. justo se pago) no pasa nada: el webhook ve el pago RECHAZADO y lo
    reembolsa (reembolsar_pago_tardio)."""
    try:
        if id_transaccion.startswith("cs_"):
            await asyncio.to_thread(stripe.checkout.Session.expire, id_transaccion)
        elif id_transaccion.startswith("pi_"):
            await asyncio.to_thread(stripe.PaymentIntent.cancel, id_transaccion)
    except stripe.error.StripeError:
        logger.warning("No se pudo cerrar en Stripe el intento abandonado %s", id_transaccion)


async def confirmar_rechazado(
    conn: asyncpg.Connection,
    pago_id: UUID,
    venta: dict,
    mensaje_cliente: str | None = None,
) -> dict:
    """E1: pago rechazado -- se notifica al cliente y el carrito sigue disponible para reintentar.
    mensaje_cliente reemplaza el texto por defecto (p.ej. el cajero que no encontro el deposito
    QR, o el pedido en efectivo que nadie paso a retirar); '{numero}' se reemplaza por el numero
    de la venta."""
    if mensaje_cliente is None:
        mensaje_cliente = (
            "Tu pago para el pedido {numero} fue rechazado. Tu carrito sigue disponible "
            "para volver a intentarlo."
        )
    await conn.execute(
        "UPDATE pago SET estado = 'RECHAZADO', confirmado_en = now() WHERE id = $1", pago_id
    )
    await conn.execute("UPDATE venta SET estado = 'ANULADA' WHERE id = $1", venta["id"])
    if venta["promocion_id"] is not None:
        await conn.execute(
            "UPDATE promocion SET usos_actuales = GREATEST(usos_actuales - 1, 0) WHERE id = $1",
            venta["promocion_id"],
        )
    await conn.execute(
        """
        INSERT INTO notificacion (usuario_id, tipo, titulo, mensaje, entidad_tipo, entidad_id)
        SELECT usuario_id, 'VENTA', 'Pago rechazado', replace($2, '{numero}', numero),
               'VENTA', id
        FROM venta WHERE id = $1 AND usuario_id IS NOT NULL
        """,
        venta["id"],
        mensaje_cliente,
    )
    return {"venta_estado": "ANULADA", "pago_estado": "RECHAZADO", "mensaje": "Pago rechazado"}


async def notificar_cajeros(
    conn: asyncpg.Connection, sucursal_id: UUID, venta_id: UUID, titulo: str, mensaje: str
) -> None:
    """Avisa a los cajeros activos de la sucursal que tienen un pago online por verificar
    (checkout en EFECTIVO o pago QR informado por la clienta)."""
    await conn.execute(
        """
        INSERT INTO notificacion (usuario_id, tipo, titulo, mensaje, entidad_tipo, entidad_id)
        SELECT e.usuario_id, 'VENTA', $2, $3, 'VENTA', $4
        FROM empleado e
        WHERE e.sucursal_id = $1 AND e.activo AND e.cargo = 'CAJERO'
        """,
        sucursal_id,
        titulo,
        mensaje,
        venta_id,
    )


async def _alertar_stock_bajo(conn: asyncpg.Connection, sucursal_id: UUID, venta_id: UUID) -> None:
    variante_ids = [
        fila["variante_id"]
        for fila in await conn.fetch(
            "SELECT variante_id FROM venta_detalle WHERE venta_id = $1", venta_id
        )
    ]
    bajos = await conn.fetch(
        """
        SELECT DISTINCT p.nombre AS producto
        FROM inventario i
        JOIN producto_variante pv ON pv.id = i.variante_id
        JOIN producto p ON p.id = pv.producto_id
        WHERE i.sucursal_id = $1 AND i.variante_id = ANY($2::uuid[])
          AND i.disponible <= i.stock_minimo
        """,
        sucursal_id,
        variante_ids,
    )
    if not bajos:
        return

    encargados = await conn.fetch(
        "SELECT usuario_id FROM empleado WHERE sucursal_id = $1 AND activo AND cargo = 'ENCARGADO'",
        sucursal_id,
    )
    nombres = ", ".join(fila["producto"] for fila in bajos)
    for encargado in encargados:
        await conn.execute(
            """
            INSERT INTO notificacion (usuario_id, tipo, titulo, mensaje, entidad_tipo, entidad_id)
            VALUES ($1, 'STOCK', 'Stock bajo el minimo', $2, 'VENTA', $3)
            """,
            encargado["usuario_id"],
            f"Quedo poco stock de: {nombres}",
            venta_id,
        )
