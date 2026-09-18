"""CU06 - confirmar (o rechazar) un pago ya iniciado.

La logica de "cerrar" un pago es la misma sin importar quien la dispare: el webhook firmado de
Stripe, el webhook simulado de QR, o el checkout mismo cuando el metodo es EFECTIVO (se aprueba
al toque, sin pasarela de por medio -- ver ventas/router.py). Por eso vive aca, no en pagos/router.py:
la usan pagos/router.py (los dos webhooks) Y ventas/router.py (el checkout con EFECTIVO), y
ventas/router.py no puede importar de pagos/router.py sin generar un ciclo (pagos/router.py ya
importa de ventas/router.py). Mismo criterio que envios/servicio.py: es la excepcion a "cada
modulo se basta a si mismo" para las funciones que de verdad comparten los tres casos.
"""

from uuid import UUID, uuid4

import asyncpg

from app.modules.envios.servicio import crear_envio_de_venta


async def confirmar_aprobado(conn: asyncpg.Connection, pago_id: UUID, venta: dict) -> dict:
    """Vuelca el carrito a venta_detalle (dispara fn_mover_inventario via trigger), marca el pago
    APROBADO y la venta PAGADA. Si el stock cambio entre el checkout y esta confirmacion, la venta
    se anula y el pago queda REEMBOLSADO en vez de romper: la plata (real o en efectivo) ya se
    tomo por comprometida en ese instante."""
    items = await conn.fetch(
        "SELECT variante_id, cantidad, precio_unitario FROM carrito_item WHERE carrito_id = $1",
        venta["carrito_id"],
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
        await conn.execute(
            "UPDATE pago SET estado = 'REEMBOLSADO', confirmado_en = now() WHERE id = $1", pago_id
        )
        await conn.execute("UPDATE venta SET estado = 'ANULADA' WHERE id = $1", venta["id"])
        await conn.execute(
            """
            INSERT INTO notificacion (usuario_id, tipo, titulo, mensaje, entidad_tipo, entidad_id)
            SELECT usuario_id, 'VENTA', 'Pedido no se pudo completar',
                   'Cobramos tu pedido ' || numero || ' pero el stock cambio antes de confirmarlo. '
                   || 'Se genero un reembolso.',
                   'VENTA', id
            FROM venta WHERE id = $1
            """,
            venta["id"],
        )
        return {
            "venta_estado": "ANULADA",
            "pago_estado": "REEMBOLSADO",
            "mensaje": f"No se pudo descontar stock: {error}",
        }

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
        pendientes = await conn.fetchval(
            "SELECT COUNT(*) FROM reserva_detalle WHERE reserva_id = $1 AND estado_item = 'RESERVADO'",
            venta["reserva_id"],
        )
        if pendientes == 0:
            await conn.execute("UPDATE reserva SET estado = 'CONVERTIDA' WHERE id = $1", venta["reserva_id"])

    numero_comprobante = f"C-{uuid4().hex[:10].upper()}"
    await conn.execute(
        "INSERT INTO comprobante (venta_id, numero) VALUES ($1, $2)", venta["id"], numero_comprobante
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
                   || 'Te avisamos cuando el repartidor salga.',
                   'ENVIO', $2
            FROM venta WHERE id = $1
            """,
            venta["id"],
            envio_id,
        )

    await _alertar_stock_bajo(conn, venta["sucursal_id"], venta["id"])

    return {"venta_estado": "PAGADA", "pago_estado": "APROBADO", "mensaje": "Pago confirmado"}


async def confirmar_rechazado(conn: asyncpg.Connection, pago_id: UUID, venta: dict) -> dict:
    # E1: pago rechazado -- se notifica al cliente y el carrito sigue disponible para reintentar
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
        SELECT usuario_id, 'VENTA', 'Pago rechazado',
               'Tu pago para el pedido ' || numero || ' fue rechazado. Tu carrito sigue disponible '
               || 'para volver a intentarlo.',
               'VENTA', id
        FROM venta WHERE id = $1
        """,
        venta["id"],
    )
    return {"venta_estado": "ANULADA", "pago_estado": "RECHAZADO", "mensaje": "Pago rechazado"}


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
