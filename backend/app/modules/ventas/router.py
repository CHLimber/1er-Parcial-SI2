from decimal import Decimal
from uuid import UUID, uuid4

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status

from app.core.db import get_connection
from app.core.deps import get_current_usuario
from app.modules.ventas.schemas import (
    CheckoutIn,
    CheckoutOut,
    ComprobanteOut,
    PagoOut,
    VentaItemOut,
    VentaOut,
    VentaResumenOut,
)

router = APIRouter(prefix="/ventas", tags=["ventas"])

IVA_TASA = Decimal("0.13")


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
        return CheckoutOut(
            venta_id=pendiente["venta_id"],
            numero=pendiente["numero"],
            pago_id=pendiente["pago_id"],
            pasarela=pendiente["pasarela"],
            id_transaccion=pendiente["id_transaccion"],
            url_pago=f"/pago-simulado/{pendiente['venta_id']}",
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
        id_transaccion = f"SIM-{uuid4().hex}"
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
        url_pago=f"/pago-simulado/{venta['id']}",
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
