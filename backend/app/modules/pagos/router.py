from uuid import uuid4

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status

from app.core.db import get_connection
from app.modules.pagos.schemas import WebhookIn, WebhookOut

router = APIRouter(prefix="/pagos", tags=["pagos"])


@router.post("/webhook/{pasarela}", response_model=WebhookOut)
async def webhook_pasarela(
    pasarela: str,
    body: WebhookIn,
    conn: asyncpg.Connection = Depends(get_connection),
) -> WebhookOut:
    """Notificacion asincrona de la pasarela de pago (CU06). Sin autenticacion de usuario -- como
    en un webhook real, quien llama es el servidor de la pasarela, no el navegador del cliente."""
    pasarela = pasarela.upper()
    if pasarela not in ("STRIPE", "LIBELULA"):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pasarela desconocida")

    pago = await conn.fetchrow(
        "SELECT id, venta_id FROM pago WHERE pasarela = $1 AND id_transaccion = $2",
        pasarela,
        body.id_transaccion,
    )
    if pago is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="No existe un pago con esa transaccion"
        )

    async with conn.transaction():
        try:
            await conn.execute(
                "INSERT INTO evento_pasarela (evento_externo_id, pasarela, pago_id) VALUES ($1, $2, $3)",
                body.evento_id,
                pasarela,
                pago["id"],
            )
        except asyncpg.UniqueViolationError:
            # E2: webhook duplicado -- reintento de la pasarela, se ignora sin volver a cobrar
            return WebhookOut(
                procesado=False, mensaje="Este evento ya habia sido procesado antes (idempotencia)"
            )

        pago_actual = await conn.fetchrow(
            "SELECT estado FROM pago WHERE id = $1 FOR UPDATE", pago["id"]
        )
        if pago_actual["estado"] != "PENDIENTE":
            return WebhookOut(
                procesado=False,
                pago_estado=pago_actual["estado"],
                mensaje="Este pago ya habia sido resuelto antes",
            )

        venta = await conn.fetchrow(
            "SELECT id, sucursal_id, carrito_id, reserva_id, promocion_id, numero FROM venta "
            "WHERE id = $1 FOR UPDATE",
            pago["venta_id"],
        )

        if body.estado == "RECHAZADO":
            return await _procesar_rechazo(conn, pago["id"], venta)

        return await _procesar_aprobacion(conn, pago["id"], venta)


async def _procesar_rechazo(conn: asyncpg.Connection, pago_id, venta: asyncpg.Record) -> WebhookOut:
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
    return WebhookOut(
        procesado=True, venta_estado="ANULADA", pago_estado="RECHAZADO", mensaje="Pago rechazado"
    )


async def _procesar_aprobacion(conn: asyncpg.Connection, pago_id, venta: asyncpg.Record) -> WebhookOut:
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
        # el pago ya se cobro pero el stock cambio entre el checkout y la confirmacion:
        # no se puede completar la venta, se marca para reembolso y se avisa al cliente
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
        return WebhookOut(
            procesado=True,
            venta_estado="ANULADA",
            pago_estado="REEMBOLSADO",
            mensaje=f"No se pudo descontar stock: {error}",
        )

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

    await _alertar_stock_bajo(conn, venta)

    return WebhookOut(
        procesado=True, venta_estado="PAGADA", pago_estado="APROBADO", mensaje="Pago confirmado"
    )


async def _alertar_stock_bajo(conn: asyncpg.Connection, venta: asyncpg.Record) -> None:
    variante_ids = [
        fila["variante_id"]
        for fila in await conn.fetch(
            "SELECT variante_id FROM venta_detalle WHERE venta_id = $1", venta["id"]
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
        venta["sucursal_id"],
        variante_ids,
    )
    if not bajos:
        return

    encargados = await conn.fetch(
        "SELECT usuario_id FROM empleado WHERE sucursal_id = $1 AND activo AND cargo = 'ENCARGADO'",
        venta["sucursal_id"],
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
            venta["id"],
        )
