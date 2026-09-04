from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status

from app.core.db import get_connection
from app.core.deps import get_current_usuario
from app.modules.carrito.schemas import (
    CarritoItemCantidadIn,
    CarritoItemIn,
    CarritoItemOut,
    CarritoOut,
)

router = APIRouter(prefix="/carrito", tags=["carrito"])


def _exigir_cliente(usuario: dict) -> None:
    if usuario["tipo"] != "CLIENTE":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo un cliente puede usar el carrito de compras",
        )


async def _obtener_o_crear_carrito(conn: asyncpg.Connection, usuario_id: UUID) -> asyncpg.Record:
    carrito = await conn.fetchrow(
        "SELECT id, estado, reserva_id FROM carrito WHERE usuario_id = $1 AND estado = 'ACTIVO'",
        usuario_id,
    )
    if carrito is not None:
        return carrito
    return await conn.fetchrow(
        "INSERT INTO carrito (usuario_id) VALUES ($1) RETURNING id, estado, reserva_id",
        usuario_id,
    )


async def _armar_carrito_out(conn: asyncpg.Connection, carrito: asyncpg.Record) -> CarritoOut:
    filas = await conn.fetch(
        """
        SELECT ci.id, ci.variante_id, ci.cantidad, ci.precio_unitario,
               pv.sku, p.nombre AS producto, p.slug AS producto_slug,
               t.codigo AS talla, c.nombre AS color, c.codigo_hex,
               img.url AS imagen_url
        FROM carrito_item ci
        JOIN producto_variante pv ON pv.id = ci.variante_id
        JOIN producto p ON p.id = pv.producto_id
        JOIN talla t    ON t.id = pv.talla_id
        JOIN color c    ON c.id = pv.color_id
        LEFT JOIN LATERAL (
            SELECT url FROM producto_imagen pi
            WHERE pi.producto_id = p.id AND pi.uso = 'CATALOGO'
            ORDER BY pi.es_principal DESC, pi.orden
            LIMIT 1
        ) img ON true
        WHERE ci.carrito_id = $1
        ORDER BY ci.agregado_en
        """,
        carrito["id"],
    )

    reserva_codigo = None
    if carrito["reserva_id"] is not None:
        fila_reserva = await conn.fetchrow(
            "SELECT codigo FROM reserva WHERE id = $1", carrito["reserva_id"]
        )
        reserva_codigo = fila_reserva["codigo"] if fila_reserva else None

    items = [
        CarritoItemOut(
            id=fila["id"],
            variante_id=fila["variante_id"],
            sku=fila["sku"],
            producto=fila["producto"],
            producto_slug=fila["producto_slug"],
            talla=fila["talla"],
            color=fila["color"],
            codigo_hex=fila["codigo_hex"],
            imagen_url=fila["imagen_url"],
            precio_unitario=float(fila["precio_unitario"]),
            cantidad=fila["cantidad"],
            subtotal=float(fila["precio_unitario"]) * fila["cantidad"],
        )
        for fila in filas
    ]

    return CarritoOut(
        id=carrito["id"],
        estado=carrito["estado"],
        reserva_id=carrito["reserva_id"],
        reserva_codigo=reserva_codigo,
        items=items,
        cantidad_items=sum(item.cantidad for item in items),
        subtotal=sum(item.subtotal for item in items),
    )


@router.get("", response_model=CarritoOut)
async def ver_carrito(
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> CarritoOut:
    _exigir_cliente(usuario)
    carrito = await _obtener_o_crear_carrito(conn, usuario["id"])
    return await _armar_carrito_out(conn, carrito)


@router.post("/items", response_model=CarritoOut, status_code=status.HTTP_201_CREATED)
async def agregar_item(
    body: CarritoItemIn,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> CarritoOut:
    _exigir_cliente(usuario)

    variante = await conn.fetchrow(
        """
        SELECT pv.id, pv.activa,
               COALESCE(pv.precio_oferta, pv.precio, p.precio_base) AS precio,
               COALESCE(SUM(i.disponible), 0) AS disponible
        FROM producto_variante pv
        JOIN producto p ON p.id = pv.producto_id
        LEFT JOIN inventario i ON i.variante_id = pv.id
        WHERE pv.id = $1
        GROUP BY pv.id, pv.activa, pv.precio_oferta, pv.precio, p.precio_base
        """,
        body.variante_id,
    )
    if variante is None or not variante["activa"]:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Esa prenda ya no esta disponible"
        )
    if variante["disponible"] < body.cantidad:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Solo hay {variante['disponible']} unidad(es) disponible(s) en toda la cadena",
        )

    carrito = await _obtener_o_crear_carrito(conn, usuario["id"])
    if carrito["reserva_id"] is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Este carrito viene de una reserva; vacialo antes de agregar otras prendas",
        )

    await conn.execute(
        """
        INSERT INTO carrito_item (carrito_id, variante_id, cantidad, precio_unitario)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (carrito_id, variante_id)
        DO UPDATE SET cantidad = carrito_item.cantidad + EXCLUDED.cantidad
        """,
        carrito["id"],
        body.variante_id,
        body.cantidad,
        variante["precio"],
    )
    await conn.execute("UPDATE carrito SET actualizado_en = now() WHERE id = $1", carrito["id"])
    return await _armar_carrito_out(conn, carrito)


@router.patch("/items/{item_id}", response_model=CarritoOut)
async def actualizar_cantidad(
    item_id: UUID,
    body: CarritoItemCantidadIn,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> CarritoOut:
    _exigir_cliente(usuario)
    carrito = await _obtener_o_crear_carrito(conn, usuario["id"])

    resultado = await conn.execute(
        "UPDATE carrito_item SET cantidad = $1 WHERE id = $2 AND carrito_id = $3",
        body.cantidad,
        item_id,
        carrito["id"],
    )
    if resultado == "UPDATE 0":
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Ese item no esta en tu carrito"
        )
    return await _armar_carrito_out(conn, carrito)


@router.delete("/items/{item_id}", response_model=CarritoOut)
async def quitar_item(
    item_id: UUID,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> CarritoOut:
    _exigir_cliente(usuario)
    carrito = await _obtener_o_crear_carrito(conn, usuario["id"])
    await conn.execute(
        "DELETE FROM carrito_item WHERE id = $1 AND carrito_id = $2", item_id, carrito["id"]
    )
    return await _armar_carrito_out(conn, carrito)


@router.post(
    "/desde-reserva/{reserva_id}", response_model=CarritoOut, status_code=status.HTTP_201_CREATED
)
async def crear_desde_reserva(
    reserva_id: UUID,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> CarritoOut:
    """Arma un carrito de compra web a partir de las prendas que el cliente ya reservo para
    probarse en sucursal (CU05: 'carrito armado directamente o desde una reserva convertida')."""
    _exigir_cliente(usuario)

    reserva = await conn.fetchrow(
        "SELECT id, estado FROM reserva WHERE id = $1 AND usuario_id = $2",
        reserva_id,
        usuario["id"],
    )
    if reserva is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Reserva no encontrada")
    if reserva["estado"] not in ("PENDIENTE", "CONFIRMADA", "PREPARADA", "CLIENTE_PRESENTE"):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Esta reserva ya no se puede convertir en una compra",
        )

    detalles = await conn.fetch(
        """
        SELECT rd.variante_id, rd.cantidad,
               COALESCE(pv.precio_oferta, pv.precio, p.precio_base) AS precio
        FROM reserva_detalle rd
        JOIN producto_variante pv ON pv.id = rd.variante_id
        JOIN producto p ON p.id = pv.producto_id
        WHERE rd.reserva_id = $1 AND rd.estado_item IN ('RESERVADO', 'PROBADO')
        """,
        reserva_id,
    )
    if not detalles:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Esta reserva no tiene prendas pendientes de compra",
        )

    async with conn.transaction():
        carrito_previo = await conn.fetchrow(
            "SELECT id FROM carrito WHERE usuario_id = $1 AND estado = 'ACTIVO'", usuario["id"]
        )
        if carrito_previo is not None:
            # un carrito solo puede venir de una reserva a la vez: se reemplaza el contenido anterior
            await conn.execute(
                "DELETE FROM carrito_item WHERE carrito_id = $1", carrito_previo["id"]
            )
            await conn.execute(
                "UPDATE carrito SET reserva_id = $1, actualizado_en = now() WHERE id = $2",
                reserva_id,
                carrito_previo["id"],
            )
            carrito_id = carrito_previo["id"]
        else:
            fila = await conn.fetchrow(
                "INSERT INTO carrito (usuario_id, reserva_id) VALUES ($1, $2) RETURNING id",
                usuario["id"],
                reserva_id,
            )
            carrito_id = fila["id"]

        for detalle in detalles:
            await conn.execute(
                """
                INSERT INTO carrito_item (carrito_id, variante_id, cantidad, precio_unitario)
                VALUES ($1, $2, $3, $4)
                ON CONFLICT (carrito_id, variante_id) DO UPDATE SET cantidad = EXCLUDED.cantidad
                """,
                carrito_id,
                detalle["variante_id"],
                detalle["cantidad"],
                detalle["precio"],
            )

    carrito = await conn.fetchrow(
        "SELECT id, estado, reserva_id FROM carrito WHERE id = $1", carrito_id
    )
    return await _armar_carrito_out(conn, carrito)
