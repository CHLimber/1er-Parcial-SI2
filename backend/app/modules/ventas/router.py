import asyncio
from decimal import Decimal
from uuid import UUID, uuid4

import asyncpg
import stripe
from fastapi import APIRouter, Depends, HTTPException, status

from app.core.config import settings
from app.core.db import get_connection
from app.core.deps import get_cajero_actual, get_current_usuario
from app.modules.caja.router import obtener_sesion_abierta
from app.modules.ventas.schemas import (
    CheckoutIn,
    CheckoutOut,
    ComprobanteOut,
    ItemRechazadoPosOut,
    PagoOut,
    VentaItemOut,
    VentaOut,
    VentaPosIn,
    VentaPosOut,
    VentaResumenOut,
)

router = APIRouter(prefix="/ventas", tags=["ventas"])

IVA_TASA = Decimal("0.13")

stripe.api_key = settings.stripe_secret_key


async def _crear_sesion_stripe(venta_id: UUID, numero: str, total: Decimal) -> tuple[str, str]:
    """CU06 paso 1: envia la orden de cobro a la pasarela. Devuelve (id_transaccion, url_pago)."""
    try:
        sesion = await asyncio.to_thread(
            stripe.checkout.Session.create,
            mode="payment",
            payment_method_types=["card"],
            line_items=[
                {
                    "price_data": {
                        "currency": "bob",
                        "product_data": {"name": f"Pedido {numero} - FashionStore"},
                        "unit_amount": int(total * 100),
                    },
                    "quantity": 1,
                }
            ],
            success_url=f"{settings.frontend_url}/compra/{venta_id}",
            cancel_url=f"{settings.frontend_url}/carrito",
            metadata={"venta_id": str(venta_id), "numero": numero},
        )
    except stripe.error.StripeError as error:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"No se pudo iniciar el pago con Stripe: {error}",
        ) from error
    return sesion.id, sesion.url


async def _url_pago_pendiente(pasarela: str, id_transaccion: str, venta_id: UUID) -> str:
    if pasarela != "STRIPE":
        return f"/pago-simulado/{venta_id}"
    try:
        sesion = await asyncio.to_thread(stripe.checkout.Session.retrieve, id_transaccion)
    except stripe.error.StripeError:
        return f"/pago-simulado/{venta_id}"
    return sesion.url or f"/pago-simulado/{venta_id}"


def _exigir_cliente(usuario: dict) -> None:
    if usuario["tipo"] != "CLIENTE":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo un cliente puede comprar por web/app",
        )


async def _aplicar_cupon(
    conn: asyncpg.Connection, codigo: str, items: list[asyncpg.Record], subtotal: Decimal
) -> tuple[UUID, Decimal]:
    promo = await conn.fetchrow(
        """
        SELECT id, tipo, valor, alcance, categoria_id, temporada_id, monto_minimo,
               uso_maximo, usos_actuales
        FROM promocion
        WHERE codigo_cupon = $1 AND activa AND CURRENT_DATE BETWEEN fecha_inicio AND fecha_fin
        """,
        codigo.strip().upper(),
    )
    if promo is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Ese cupon no existe, vencio o esta inactivo",
        )
    if promo["uso_maximo"] is not None and promo["usos_actuales"] >= promo["uso_maximo"]:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Ese cupon ya alcanzo su limite de usos",
        )
    if promo["monto_minimo"] is not None and subtotal < promo["monto_minimo"]:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Ese cupon requiere una compra minima de Bs {promo['monto_minimo']}",
        )

    if promo["alcance"] == "TODO":
        base = subtotal
    else:
        columna = "categoria_id" if promo["alcance"] == "CATEGORIA" else "temporada_id"
        objetivo = promo[columna]
        base = sum(
            (Decimal(str(item["precio_unitario"])) * item["cantidad"] for item in items if item[columna] == objetivo),
            Decimal("0"),
        )
    if base <= 0:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Ese cupon no aplica a ninguna prenda de tu carrito",
        )

    if promo["tipo"] == "PORCENTAJE":
        descuento = (base * Decimal(str(promo["valor"])) / Decimal("100")).quantize(Decimal("0.01"))
    else:
        descuento = min(Decimal(str(promo["valor"])), base)

    await conn.execute(
        "UPDATE promocion SET usos_actuales = usos_actuales + 1 WHERE id = $1", promo["id"]
    )
    return promo["id"], descuento


@router.post("/checkout", response_model=CheckoutOut, status_code=status.HTTP_201_CREATED)
async def iniciar_checkout(
    body: CheckoutIn,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> CheckoutOut:
    _exigir_cliente(usuario)

    carrito = await conn.fetchrow(
        "SELECT id, reserva_id FROM carrito WHERE usuario_id = $1 AND estado = 'ACTIVO'",
        usuario["id"],
    )
    if carrito is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="No tenes un carrito activo"
        )

    items = await conn.fetch(
        """
        SELECT ci.id, ci.variante_id, ci.cantidad, ci.precio_unitario,
               p.categoria_id, p.temporada_id
        FROM carrito_item ci
        JOIN producto_variante pv ON pv.id = ci.variante_id
        JOIN producto p ON p.id = pv.producto_id
        WHERE ci.carrito_id = $1
        """,
        carrito["id"],
    )
    if not items:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Tu carrito esta vacio"
        )

    # reintento de un checkout que ya se inicio (doble click): reusar la venta/pago pendientes
    pendiente = await conn.fetchrow(
        """
        SELECT v.id AS venta_id, v.numero, v.subtotal, v.descuento, v.iva, v.total, v.estado,
               p.id AS pago_id, p.pasarela, p.id_transaccion
        FROM venta v
        JOIN pago p ON p.venta_id = v.id
        WHERE v.carrito_id = $1 AND v.estado = 'PENDIENTE' AND p.estado = 'PENDIENTE'
        ORDER BY v.fecha DESC
        LIMIT 1
        """,
        carrito["id"],
    )
    if pendiente is not None:
        url_pago = await _url_pago_pendiente(
            pendiente["pasarela"], pendiente["id_transaccion"], pendiente["venta_id"]
        )
        return CheckoutOut(
            venta_id=pendiente["venta_id"],
            numero=pendiente["numero"],
            pago_id=pendiente["pago_id"],
            pasarela=pendiente["pasarela"],
            id_transaccion=pendiente["id_transaccion"],
            url_pago=url_pago,
            subtotal=float(pendiente["subtotal"]),
            descuento=float(pendiente["descuento"]),
            iva=float(pendiente["iva"]),
            total=float(pendiente["total"]),
            estado=pendiente["estado"],
        )

    if carrito["reserva_id"] is not None:
        # una compra nacida de una reserva se retira en la misma sucursal donde se comprometio el stock
        reserva = await conn.fetchrow(
            "SELECT sucursal_id FROM reserva WHERE id = $1", carrito["reserva_id"]
        )
        sucursal_id = reserva["sucursal_id"]
        entrega = "RETIRO_SUCURSAL"
        direccion_id = None
    else:
        if body.sucursal_id is None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Elegi la sucursal desde la que se despacha tu pedido",
            )
        sucursal = await conn.fetchrow(
            "SELECT id FROM sucursal WHERE id = $1 AND activa", body.sucursal_id
        )
        if sucursal is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sucursal no encontrada")
        sucursal_id = body.sucursal_id
        entrega = body.entrega
        direccion_id = body.direccion_id

        if entrega == "DOMICILIO":
            if direccion_id is None:
                direccion = await conn.fetchrow(
                    "SELECT id FROM direccion WHERE usuario_id = $1 AND es_principal", usuario["id"]
                )
                if direccion is None:
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail="No tenes una direccion registrada para el envio a domicilio",
                    )
                direccion_id = direccion["id"]
            else:
                direccion = await conn.fetchrow(
                    "SELECT id FROM direccion WHERE id = $1 AND usuario_id = $2",
                    direccion_id,
                    usuario["id"],
                )
                if direccion is None:
                    raise HTTPException(
                        status_code=status.HTTP_404_NOT_FOUND, detail="Esa direccion no te pertenece"
                    )

    variante_ids = [item["variante_id"] for item in items]
    disponibilidad = await conn.fetch(
        """
        SELECT variante_id, COALESCE(disponible, 0) AS disponible
        FROM inventario
        WHERE sucursal_id = $1 AND variante_id = ANY($2::uuid[])
        """,
        sucursal_id,
        variante_ids,
    )
    disponible_por_variante = {fila["variante_id"]: fila["disponible"] for fila in disponibilidad}
    sin_stock = [
        str(item["variante_id"])
        for item in items
        if disponible_por_variante.get(item["variante_id"], 0) < item["cantidad"]
    ]
    if sin_stock:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "mensaje": "Algunas prendas ya no tienen stock suficiente en esa sucursal",
                "variantes_sin_stock": sin_stock,
            },
        )

    subtotal = sum(
        (Decimal(str(item["precio_unitario"])) * item["cantidad"] for item in items), Decimal("0")
    )
    descuento = Decimal("0")
    promocion_id = None
    if body.codigo_cupon:
        promocion_id, descuento = await _aplicar_cupon(conn, body.codigo_cupon, items, subtotal)

    base_imponible = subtotal - descuento
    iva = (base_imponible * IVA_TASA).quantize(Decimal("0.01"))
    total = (base_imponible + iva).quantize(Decimal("0.01"))

    numero = f"V-{uuid4().hex[:10].upper()}"
    async with conn.transaction():
        venta = await conn.fetchrow(
            """
            INSERT INTO venta (sucursal_id, usuario_id, canal, entrega, direccion_id, reserva_id,
                                carrito_id, promocion_id, numero, subtotal, descuento, iva, total)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
            RETURNING id, numero, subtotal, descuento, iva, total, estado
            """,
            sucursal_id,
            usuario["id"],
            body.canal,
            entrega,
            direccion_id,
            carrito["reserva_id"],
            carrito["id"],
            promocion_id,
            numero,
            subtotal,
            descuento,
            iva,
            total,
        )
        if body.pasarela == "STRIPE":
            id_transaccion, url_pago = await _crear_sesion_stripe(venta["id"], venta["numero"], total)
        else:
            id_transaccion = f"SIM-{uuid4().hex}"
            url_pago = f"/pago-simulado/{venta['id']}"

        pago = await conn.fetchrow(
            """
            INSERT INTO pago (venta_id, metodo, pasarela, monto, id_transaccion)
            VALUES ($1, 'PASARELA', $2, $3, $4)
            RETURNING id, pasarela, id_transaccion
            """,
            venta["id"],
            body.pasarela,
            total,
            id_transaccion,
        )

    return CheckoutOut(
        venta_id=venta["id"],
        numero=venta["numero"],
        pago_id=pago["id"],
        pasarela=pago["pasarela"],
        id_transaccion=pago["id_transaccion"],
        url_pago=url_pago,
        subtotal=float(venta["subtotal"]),
        descuento=float(venta["descuento"]),
        iva=float(venta["iva"]),
        total=float(venta["total"]),
        estado=venta["estado"],
    )


@router.get("", response_model=list[VentaResumenOut])
async def listar_mis_ventas(
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> list[VentaResumenOut]:
    _exigir_cliente(usuario)
    filas = await conn.fetch(
        """
        SELECT v.id, v.numero, v.canal, v.estado, v.total, v.fecha, s.nombre AS sucursal
        FROM venta v
        JOIN sucursal s ON s.id = v.sucursal_id
        WHERE v.usuario_id = $1
        ORDER BY v.fecha DESC
        """,
        usuario["id"],
    )
    return [
        VentaResumenOut(
            id=fila["id"],
            numero=fila["numero"],
            canal=fila["canal"],
            estado=fila["estado"],
            total=float(fila["total"]),
            fecha=fila["fecha"],
            sucursal=fila["sucursal"],
        )
        for fila in filas
    ]


@router.get("/{venta_id}", response_model=VentaOut)
async def obtener_venta(
    venta_id: UUID,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> VentaOut:
    _exigir_cliente(usuario)

    venta = await conn.fetchrow(
        """
        SELECT v.id, v.numero, v.canal, v.entrega, v.estado, v.subtotal, v.descuento, v.iva,
               v.total, v.fecha, v.carrito_id, s.nombre AS sucursal
        FROM venta v
        JOIN sucursal s ON s.id = v.sucursal_id
        WHERE v.id = $1 AND v.usuario_id = $2
        """,
        venta_id,
        usuario["id"],
    )
    if venta is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Venta no encontrada")

    if venta["estado"] in ("PAGADA", "ENTREGADA"):
        filas_items = await conn.fetch(
            """
            SELECT vd.variante_id, vd.cantidad, vd.precio_unitario, vd.subtotal,
                   pv.sku, p.nombre AS producto, t.codigo AS talla, c.nombre AS color
            FROM venta_detalle vd
            JOIN producto_variante pv ON pv.id = vd.variante_id
            JOIN producto p ON p.id = pv.producto_id
            JOIN talla t    ON t.id = pv.talla_id
            JOIN color c    ON c.id = pv.color_id
            WHERE vd.venta_id = $1
            """,
            venta_id,
        )
    else:
        # todavia no hay venta_detalle (se inserta recien cuando el webhook confirma el pago):
        # mostramos lo que habia en el carrito al momento del checkout
        filas_items = await conn.fetch(
            """
            SELECT ci.variante_id, ci.cantidad, ci.precio_unitario,
                   ci.precio_unitario * ci.cantidad AS subtotal,
                   pv.sku, p.nombre AS producto, t.codigo AS talla, c.nombre AS color
            FROM carrito_item ci
            JOIN producto_variante pv ON pv.id = ci.variante_id
            JOIN producto p ON p.id = pv.producto_id
            JOIN talla t    ON t.id = pv.talla_id
            JOIN color c    ON c.id = pv.color_id
            WHERE ci.carrito_id = $1
            """,
            venta["carrito_id"],
        )

    items = [
        VentaItemOut(
            variante_id=fila["variante_id"],
            sku=fila["sku"],
            producto=fila["producto"],
            talla=fila["talla"],
            color=fila["color"],
            cantidad=fila["cantidad"],
            precio_unitario=float(fila["precio_unitario"]),
            subtotal=float(fila["subtotal"]),
        )
        for fila in filas_items
    ]

    pago = await conn.fetchrow(
        """
        SELECT id, metodo, pasarela, monto, estado, id_transaccion, creado_en, confirmado_en
        FROM pago WHERE venta_id = $1
        ORDER BY creado_en DESC LIMIT 1
        """,
        venta_id,
    )
    comprobante = await conn.fetchrow(
        "SELECT numero, tipo, emitido_en FROM comprobante WHERE venta_id = $1", venta_id
    )

    return VentaOut(
        id=venta["id"],
        numero=venta["numero"],
        canal=venta["canal"],
        entrega=venta["entrega"],
        estado=venta["estado"],
        sucursal=venta["sucursal"],
        subtotal=float(venta["subtotal"]),
        descuento=float(venta["descuento"]),
        iva=float(venta["iva"]),
        total=float(venta["total"]),
        fecha=venta["fecha"],
        items=items,
        pago=(
            PagoOut(
                id=pago["id"],
                metodo=pago["metodo"],
                pasarela=pago["pasarela"],
                monto=float(pago["monto"]),
                estado=pago["estado"],
                id_transaccion=pago["id_transaccion"],
                creado_en=pago["creado_en"],
                confirmado_en=pago["confirmado_en"],
            )
            if pago
            else None
        ),
        comprobante=(
            ComprobanteOut(
                numero=comprobante["numero"],
                tipo=comprobante["tipo"],
                emitido_en=comprobante["emitido_en"],
            )
            if comprobante
            else None
        ),
    )


@router.post("/pos", response_model=VentaPosOut, status_code=status.HTTP_201_CREATED)
async def registrar_venta_pos(
    body: VentaPosIn,
    cajero: dict = Depends(get_cajero_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> VentaPosOut:
    """CU07: el Cajero cobra en el mostrador. A diferencia del checkout web (CU05/CU06) el cobro
    ya se confirmo en persona -- no hay pasarela ni webhook, la venta se marca PAGADA de una."""
    sesion = await obtener_sesion_abierta(conn, cajero["usuario_id"])
    if sesion is None:
        # E1: sesion de caja no abierta -- el cajero debe abrirla antes de vender
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Abri una sesion de caja antes de registrar una venta",
        )

    variante_ids = [item.variante_id for item in body.items]
    filas = await conn.fetch(
        """
        SELECT pv.id AS variante_id, pv.sku, pv.activa, p.nombre AS producto,
               t.codigo AS talla, c.nombre AS color,
               COALESCE(pv.precio_oferta, pv.precio, p.precio_base) AS precio,
               COALESCE(i.disponible, 0) AS disponible
        FROM producto_variante pv
        JOIN producto p ON p.id = pv.producto_id
        JOIN talla t    ON t.id = pv.talla_id
        JOIN color c    ON c.id = pv.color_id
        LEFT JOIN inventario i ON i.variante_id = pv.id AND i.sucursal_id = $2
        WHERE pv.id = ANY($1::uuid[])
        """,
        variante_ids,
        cajero["sucursal_id"],
    )
    info_por_variante = {fila["variante_id"]: fila for fila in filas}

    numero = f"V-{uuid4().hex[:10].upper()}"
    aceptados: list[tuple] = []
    rechazados: list[ItemRechazadoPosOut] = []

    async with conn.transaction():
        venta = await conn.fetchrow(
            """
            INSERT INTO venta (sucursal_id, canal, entrega, sesion_caja_id, numero,
                                subtotal, descuento, iva, total, registrada_por_id)
            VALUES ($1, 'POS', 'RETIRO_SUCURSAL', $2, $3, 0, 0, 0, 0, $4)
            RETURNING id
            """,
            cajero["sucursal_id"],
            sesion["id"],
            numero,
            cajero["usuario_id"],
        )

        for item in body.items:
            info = info_por_variante.get(item.variante_id)
            if info is None or not info["activa"]:
                rechazados.append(
                    ItemRechazadoPosOut(
                        variante_id=item.variante_id,
                        sku=info["sku"] if info else "?",
                        motivo="Esa prenda ya no esta disponible en el catalogo",
                    )
                )
                continue
            if info["disponible"] < item.cantidad:
                rechazados.append(
                    ItemRechazadoPosOut(
                        variante_id=item.variante_id,
                        sku=info["sku"],
                        motivo=f"Stock insuficiente en esta sucursal ({info['disponible']} disponible(s))",
                    )
                )
                continue

            precio = Decimal(str(info["precio"]))
            subtotal_item = precio * item.cantidad
            try:
                async with conn.transaction():
                    await conn.execute(
                        """
                        INSERT INTO venta_detalle (venta_id, variante_id, cantidad, precio_unitario, subtotal)
                        VALUES ($1, $2, $3, $4, $5)
                        """,
                        venta["id"],
                        item.variante_id,
                        item.cantidad,
                        precio,
                        subtotal_item,
                    )
            except asyncpg.PostgresError:
                # E2: stock insuficiente detectado recien al descontar (venta concurrente en otra caja)
                rechazados.append(
                    ItemRechazadoPosOut(
                        variante_id=item.variante_id,
                        sku=info["sku"],
                        motivo="Otra venta se llevo el stock justo antes",
                    )
                )
                continue

            aceptados.append((item, info, subtotal_item))

        if not aceptados:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={
                    "mensaje": "No se pudo vender ninguna prenda: sin stock en esta sucursal",
                    "rechazados": [
                        {"variante_id": str(r.variante_id), "sku": r.sku, "motivo": r.motivo}
                        for r in rechazados
                    ],
                },
            )

        subtotal = sum((x[2] for x in aceptados), Decimal("0"))
        iva = (subtotal * IVA_TASA).quantize(Decimal("0.01"))
        total = (subtotal + iva).quantize(Decimal("0.01"))

        await conn.execute(
            "UPDATE venta SET subtotal = $1, iva = $2, total = $3, estado = 'PAGADA' WHERE id = $4",
            subtotal,
            iva,
            total,
            venta["id"],
        )
        await conn.execute(
            """
            INSERT INTO pago (venta_id, metodo, monto, estado, confirmado_en)
            VALUES ($1, $2, $3, 'APROBADO', now())
            """,
            venta["id"],
            body.metodo_pago,
            total,
        )
        numero_comprobante = f"C-{uuid4().hex[:10].upper()}"
        await conn.execute(
            "INSERT INTO comprobante (venta_id, numero) VALUES ($1, $2)",
            venta["id"],
            numero_comprobante,
        )

    await _alertar_stock_bajo(conn, cajero["sucursal_id"], venta["id"])

    vuelto = None
    if body.metodo_pago == "EFECTIVO" and body.monto_recibido is not None:
        vuelto = float(Decimal(str(body.monto_recibido)) - total)

    return VentaPosOut(
        venta_id=venta["id"],
        numero=numero,
        comprobante_numero=numero_comprobante,
        items=[
            VentaItemOut(
                variante_id=item.variante_id,
                sku=info["sku"],
                producto=info["producto"],
                talla=info["talla"],
                color=info["color"],
                cantidad=item.cantidad,
                precio_unitario=float(info["precio"]),
                subtotal=float(subtotal_item),
            )
            for item, info, subtotal_item in aceptados
        ],
        rechazados=rechazados,
        subtotal=float(subtotal),
        iva=float(iva),
        total=float(total),
        vuelto=vuelto,
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
