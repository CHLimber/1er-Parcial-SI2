import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query

from app.core.db import get_connection
from app.modules.catalogo.schemas import (
    CategoriaOut,
    ColorOut,
    DisponibilidadSucursalOut,
    FiltrosOut,
    ProductoDetalleOut,
    ProductoOut,
    TallaOut,
    TemporadaOut,
    VarianteOut,
)

router = APIRouter(prefix="/catalogo", tags=["catalogo"])


@router.get("/filtros", response_model=FiltrosOut)
async def obtener_filtros(conn: asyncpg.Connection = Depends(get_connection)) -> FiltrosOut:
    categorias = await conn.fetch(
        "SELECT id, nombre, slug, categoria_padre_id FROM categoria WHERE activa ORDER BY orden, nombre"
    )
    tallas = await conn.fetch("SELECT id, codigo, tipo FROM talla ORDER BY tipo, orden")
    colores = await conn.fetch("SELECT id, nombre, codigo_hex FROM color ORDER BY nombre")
    temporadas = await conn.fetch(
        "SELECT id, nombre, tipo FROM temporada WHERE activa ORDER BY fecha_inicio DESC"
    )
    return FiltrosOut(
        categorias=[CategoriaOut(**dict(fila)) for fila in categorias],
        tallas=[TallaOut(**dict(fila)) for fila in tallas],
        colores=[ColorOut(**dict(fila)) for fila in colores],
        temporadas=[TemporadaOut(**dict(fila)) for fila in temporadas],
    )


@router.get("/productos", response_model=list[ProductoOut])
async def listar_productos(
    conn: asyncpg.Connection = Depends(get_connection),
    categoria_slug: str | None = Query(default=None),
    q: str | None = Query(default=None, description="Busqueda por nombre"),
    temporada_id: str | None = Query(default=None),
    talla_id: int | None = Query(default=None),
    color_id: int | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> list[ProductoOut]:
    filas = await conn.fetch(
        """
        SELECT
            p.id, p.codigo, p.nombre, p.slug, p.descripcion, p.precio_base,
            p.genero, c.nombre AS categoria, c.slug AS categoria_slug,
            m.nombre AS marca, p.destacado,
            img.url AS imagen_url,
            COALESCE(tallas_agg.tallas, ARRAY[]::varchar[]) AS tallas,
            COALESCE(stock_agg.total_disponible, 0) <= 0 AS agotado
        FROM producto p
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
        WHERE p.activo
          AND ($1::text IS NULL OR c.slug = $1)
          AND ($2::text IS NULL OR p.nombre ILIKE '%' || $2 || '%')
          AND ($3::uuid IS NULL OR p.temporada_id = $3)
          AND (
                ($4::int IS NULL AND $5::int IS NULL)
                OR EXISTS (
                    SELECT 1 FROM producto_variante pv2
                    WHERE pv2.producto_id = p.id AND pv2.activa
                      AND ($4::int IS NULL OR pv2.talla_id = $4)
                      AND ($5::int IS NULL OR pv2.color_id = $5)
                )
              )
        ORDER BY p.creado_en DESC
        LIMIT $6 OFFSET $7
        """,
        categoria_slug,
        q,
        temporada_id,
        talla_id,
        color_id,
        limit,
        offset,
    )
    return [ProductoOut(**dict(fila)) for fila in filas]


@router.get("/productos/{slug}", response_model=ProductoDetalleOut)
async def obtener_producto(
    slug: str, conn: asyncpg.Connection = Depends(get_connection)
) -> ProductoDetalleOut:
    producto = await conn.fetchrow(
        """
        SELECT
            p.id, p.codigo, p.nombre, p.slug, p.descripcion, p.precio_base,
            p.genero, p.material, c.nombre AS categoria, c.slug AS categoria_slug,
            m.nombre AS marca, p.destacado,
            img.url AS imagen_url
        FROM producto p
        JOIN categoria c ON c.id = p.categoria_id
        LEFT JOIN marca m ON m.id = p.marca_id
        LEFT JOIN LATERAL (
            SELECT url FROM producto_imagen pi
            WHERE pi.producto_id = p.id AND pi.uso = 'CATALOGO'
            ORDER BY pi.es_principal DESC, pi.orden
            LIMIT 1
        ) img ON true
        WHERE p.slug = $1 AND p.activo
        """,
        slug,
    )
    if producto is None:
        raise HTTPException(status_code=404, detail="Producto no encontrado")

    variantes = await conn.fetch(
        """
        SELECT pv.id, pv.sku, t.codigo AS talla, t.orden AS talla_orden,
               c.nombre AS color, c.codigo_hex,
               COALESCE(pv.precio_oferta, pv.precio, $2) AS precio
        FROM producto_variante pv
        JOIN talla t ON t.id = pv.talla_id
        JOIN color c ON c.id = pv.color_id
        WHERE pv.producto_id = $1 AND pv.activa
        ORDER BY t.orden, c.nombre
        """,
        producto["id"],
        producto["precio_base"],
    )

    disponibilidad = await conn.fetch(
        """
        SELECT variante_id, sucursal_id, sucursal, ciudad, disponible, situacion
        FROM v_disponibilidad
        WHERE producto_id = $1
        ORDER BY sucursal
        """,
        producto["id"],
    )
    disponibilidad_por_variante: dict = {}
    for fila in disponibilidad:
        disponibilidad_por_variante.setdefault(fila["variante_id"], []).append(dict(fila))

    variantes_out: list[VarianteOut] = []
    total_disponible = 0
    for variante in variantes:
        disp_filas = disponibilidad_por_variante.get(variante["id"], [])
        total_disponible += sum(fila["disponible"] for fila in disp_filas)
        variantes_out.append(
            VarianteOut(
                id=variante["id"],
                sku=variante["sku"],
                talla=variante["talla"],
                color=variante["color"],
                codigo_hex=variante["codigo_hex"],
                precio=float(variante["precio"]),
                disponibilidad=[DisponibilidadSucursalOut(**fila) for fila in disp_filas],
            )
        )

    tallas = sorted({v["talla"] for v in variantes})

    return ProductoDetalleOut(
        id=producto["id"],
        codigo=producto["codigo"],
        nombre=producto["nombre"],
        slug=producto["slug"],
        descripcion=producto["descripcion"],
        precio_base=float(producto["precio_base"]),
        genero=producto["genero"],
        categoria=producto["categoria"],
        categoria_slug=producto["categoria_slug"],
        marca=producto["marca"],
        destacado=producto["destacado"],
        imagen_url=producto["imagen_url"],
        material=producto["material"],
        tallas=tallas,
        agotado=total_disponible <= 0,
        variantes=variantes_out,
    )
