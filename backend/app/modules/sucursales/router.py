import asyncpg
from fastapi import APIRouter, Depends

from app.core.db import get_connection
from app.modules.sucursales.schemas import SucursalOut

router = APIRouter(prefix="/sucursales", tags=["sucursales"])


@router.get("", response_model=list[SucursalOut])
async def listar_sucursales(conn: asyncpg.Connection = Depends(get_connection)) -> list[SucursalOut]:
    filas = await conn.fetch(
        """
        SELECT id, codigo, nombre, ciudad, direccion, hora_apertura, hora_cierre, cantidad_vestidores
        FROM sucursal
        WHERE activa
        ORDER BY nombre
        """
    )
    return [SucursalOut(**dict(fila)) for fila in filas]
