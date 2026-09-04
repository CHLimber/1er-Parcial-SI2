import asyncpg
from fastapi import APIRouter, Depends, Query

from app.core.db import get_connection
from app.modules.catalogo.schemas import ProductoOut

router = APIRouter(prefix="/catalogo", tags=["catalogo"])


@router.get("/productos", response_model=list[ProductoOut])
async def listar_productos(
    conn: asyncpg.Connection = Depends(get_connection),
    categoria_slug: str | None = Query(default=None),
    q: str | None = Query(default=None, description="Busqueda por nombre"),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> list[ProductoOut]:
    filas = await conn.fetch(
        """
        SELECT p.id, p.codigo, p.nombre, p.slug, p.descripcion, p.precio_base,
               p.genero, c.nombre AS categoria, m.nombre AS marca, p.destacado
        FROM producto p
        JOIN categoria c ON c.id = p.categoria_id
        LEFT JOIN marca m ON m.id = p.marca_id
        WHERE p.activo
          AND ($1::text IS NULL OR c.slug = $1)
          AND ($2::text IS NULL OR p.nombre ILIKE '%' || $2 || '%')
        ORDER BY p.creado_en DESC
        LIMIT $3 OFFSET $4
        """,
        categoria_slug,
        q,
        limit,
        offset,
    )
    return [ProductoOut(**dict(fila)) for fila in filas]
