import asyncpg
from fastapi import APIRouter, Depends

from app.core.db import get_connection
from app.core.tenant import empresa_publica
from app.modules.sucursales.schemas import SucursalOut

router = APIRouter(prefix="/sucursales", tags=["sucursales"])


@router.get("", response_model=list[SucursalOut])
async def listar_sucursales(
    conn: asyncpg.Connection = Depends(get_connection),
    empresa_id=Depends(empresa_publica),
) -> list[SucursalOut]:
    """Las sucursales de la tienda que se esta mirando (X-Empresa / ?empresa=)."""
    filas = await conn.fetch(
        """
        SELECT id, codigo, nombre, ciudad, direccion, hora_apertura, hora_cierre, cantidad_vestidores
        FROM sucursal
        WHERE activa AND empresa_id = $1
        ORDER BY nombre
        """,
        empresa_id,
    )
    return [SucursalOut(**dict(fila)) for fila in filas]
