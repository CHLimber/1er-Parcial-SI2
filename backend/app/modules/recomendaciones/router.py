"""CU17 - Recibir Recomendaciones de IA.

"IA" aca es un algoritmo de recomendacion basado en contenido (categorias que el cliente ya
compro o reservo), no un modelo de lenguaje: no hay llamada a ningun proveedor externo. Dos
pasadas, las dos en SQL crudo en el router (mismo patron sin capa de servicio que el resto del
backend; los JOIN LATERAL de imagen/tallas/stock son una copia deliberada de los de
catalogo/router.py, cada modulo arma su propio SQL, ver CLAUDE.md):

1. "Personalizadas": las categorias donde el cliente compro (peso 2) o reservo (peso 1) mas,
   completadas con productos activos de esas categorias que todavia no toco, en ese orden de
   preferencia.
2. "Generales" (relleno si 1 no alcanza el cupo pedido, o directamente si el cliente no tiene
   historial): destacados primero, despues los mas vendidos de toda la cadena.

Nunca se recomienda un producto que el cliente ya compro o reservo.
"""

from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.db import get_connection
from app.core.deps import get_current_usuario
from app.modules.recomendaciones.schemas import ProductoRecomendadoOut

router = APIRouter(prefix="/recomendaciones", tags=["recomendaciones"])

VENTA_ESTADOS_CONTADOS = ("PAGADA", "ENTREGADA")

_CAMPOS_PRODUCTO = """
    p.id, p.codigo, p.nombre, p.slug, p.descripcion, p.precio_base, p.genero,
    c.nombre AS categoria, c.slug AS categoria_slug, m.nombre AS marca, p.destacado,
    img.url AS imagen_url,
    COALESCE(tallas_agg.tallas, ARRAY[]::varchar[]) AS tallas,
    COALESCE(stock_agg.total_disponible, 0) <= 0 AS agotado
"""

_JOINS_PRODUCTO = """
    JOIN categoria c ON c.id = p.categoria_id
    LEFT JOIN marca m ON m.id = p.marca_id
    LEFT JOIN LATERAL (
        SELECT url FROM producto_imagen pi
        WHERE pi.producto_id = p.id AND pi.uso = 'CATALOGO'
        ORDER BY pi.es_principal DESC, pi.orden
        LIMIT 1
    ) img ON true
    LEFT JOIN LATERAL (
        SELECT array_agg(codigo ORDER BY orden) AS tallas
        FROM (
            SELECT DISTINCT t.codigo, t.orden
            FROM producto_variante pv
            JOIN talla t ON t.id = pv.talla_id
            WHERE pv.producto_id = p.id AND pv.activa
        ) sub
    ) tallas_agg ON true
    LEFT JOIN LATERAL (
        SELECT SUM(i.disponible) AS total_disponible
        FROM producto_variante pv
        JOIN inventario i ON i.variante_id = pv.id
        WHERE pv.producto_id = p.id AND pv.activa
    ) stock_agg ON true
"""


def _exigir_cliente(usuario: dict) -> None:
    if usuario["tipo"] != "CLIENTE":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Las recomendaciones son solo para clientes",
        )


async def _categorias_preferidas(conn: asyncpg.Connection, cliente_id: UUID) -> list[UUID]:
    filas = await conn.fetch(
        """
        WITH historial AS (
            SELECT p.categoria_id, 2 AS peso
            FROM venta_detalle vd
            JOIN venta v              ON v.id = vd.venta_id
            JOIN producto_variante pv ON pv.id = vd.variante_id
            JOIN producto p           ON p.id = pv.producto_id
            WHERE v.usuario_id = $1 AND v.estado = ANY($2::estado_venta[])
            UNION ALL
            SELECT p.categoria_id, 1 AS peso
            FROM reserva_detalle rd
            JOIN reserva r             ON r.id = rd.reserva_id
            JOIN producto_variante pv  ON pv.id = rd.variante_id
            JOIN producto p            ON p.id = pv.producto_id
            WHERE r.usuario_id = $1
        )
        SELECT categoria_id FROM historial
        GROUP BY categoria_id
        ORDER BY SUM(peso) DESC
        LIMIT 3
        """,
        cliente_id,
        list(VENTA_ESTADOS_CONTADOS),
    )
    return [fila["categoria_id"] for fila in filas]


async def _productos_tocados(conn: asyncpg.Connection, cliente_id: UUID) -> list[UUID]:
    """Productos que el cliente ya compro o tiene/tuvo reservados: nunca se recomiendan."""
    filas = await conn.fetch(
        """
        SELECT DISTINCT p.id
        FROM (
            SELECT vd.variante_id
            FROM venta_detalle vd
            JOIN venta v ON v.id = vd.venta_id
            WHERE v.usuario_id = $1 AND v.estado = ANY($2::estado_venta[])
            UNION
            SELECT rd.variante_id
            FROM reserva_detalle rd
            JOIN reserva r ON r.id = rd.reserva_id
            WHERE r.usuario_id = $1
        ) tocados
        JOIN producto_variante pv ON pv.id = tocados.variante_id
        JOIN producto p           ON p.id = pv.producto_id
        """,
        cliente_id,
        list(VENTA_ESTADOS_CONTADOS),
    )
    return [fila["id"] for fila in filas]


async def _personalizados(
    conn: asyncpg.Connection, categoria_ids: list[UUID], excluidos: list[UUID], limite: int
) -> list[asyncpg.Record]:
    return await conn.fetch(
        f"""
        SELECT {_CAMPOS_PRODUCTO}, ('Porque te gusta ' || c.nombre) AS motivo
        FROM producto p
        {_JOINS_PRODUCTO}
        WHERE p.activo
          AND p.categoria_id = ANY($1::uuid[])
          AND NOT (p.id = ANY($2::uuid[]))
        ORDER BY array_position($1::uuid[], p.categoria_id), p.destacado DESC, p.creado_en DESC
        LIMIT $3
        """,
        categoria_ids,
        excluidos,
        limite,
    )


async def _generales(
    conn: asyncpg.Connection, excluidos: list[UUID], limite: int
) -> list[asyncpg.Record]:
    return await conn.fetch(
        f"""
        SELECT {_CAMPOS_PRODUCTO},
               CASE WHEN p.destacado THEN 'Destacado en FashionStore'
                    ELSE 'Tendencia en FashionStore' END AS motivo
        FROM producto p
        {_JOINS_PRODUCTO}
        LEFT JOIN LATERAL (
            SELECT SUM(vd.cantidad) AS unidades
            FROM venta_detalle vd
            JOIN venta v               ON v.id = vd.venta_id
            JOIN producto_variante pv3 ON pv3.id = vd.variante_id
            WHERE pv3.producto_id = p.id AND v.estado = ANY($3::estado_venta[])
        ) pop ON true
        WHERE p.activo
          AND NOT (p.id = ANY($1::uuid[]))
        ORDER BY p.destacado DESC, COALESCE(pop.unidades, 0) DESC, p.creado_en DESC
        LIMIT $2
        """,
        excluidos,
        limite,
        list(VENTA_ESTADOS_CONTADOS),
    )


@router.get("", response_model=list[ProductoRecomendadoOut])
async def obtener_recomendaciones(
    limite: int = Query(default=8, ge=1, le=20),
    conn: asyncpg.Connection = Depends(get_connection),
    usuario: dict = Depends(get_current_usuario),
) -> list[ProductoRecomendadoOut]:
    _exigir_cliente(usuario)
    cliente_id = usuario["id"]

    excluidos = await _productos_tocados(conn, cliente_id)
    categoria_ids = await _categorias_preferidas(conn, cliente_id)

    personalizados: list[asyncpg.Record] = []
    if categoria_ids:
        personalizados = await _personalizados(conn, categoria_ids, excluidos, limite)

    recomendaciones = [ProductoRecomendadoOut(**dict(fila)) for fila in personalizados]

    faltan = limite - len(recomendaciones)
    if faltan > 0:
        ya_elegidos = excluidos + [fila["id"] for fila in personalizados]
        generales = await _generales(conn, ya_elegidos, faltan)
        recomendaciones += [ProductoRecomendadoOut(**dict(fila)) for fila in generales]

    return recomendaciones
