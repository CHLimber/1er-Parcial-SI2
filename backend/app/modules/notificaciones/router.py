"""Notificaciones internas (PENDIENTES.txt 2.19.3).

Solo lectura (y marcar leida) sobre la tabla `notificacion` del bloque 7 del esquema. La tabla
la escriben otros modulos (reservas/router.py, pagos/servicio.py, ...) directo con INSERT; este
modulo no inserta nada. Cada usuario ve SOLO sus propias notificaciones, sea CLIENTE o STAFF, por
eso no se usa el sistema de permisos de CU13: basta con la sesion (`get_current_usuario`).

El contador de no leidas lo consulta la web/movil por polling (~60s) y va contra el indice
parcial `ix_notificacion_pendiente (usuario_id, fecha DESC) WHERE NOT leida`.
"""

from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.db import get_connection
from app.core.deps import get_current_usuario
from app.modules.notificaciones.schemas import (
    CantidadNoLeidasOut,
    LeerTodasOut,
    NotificacionOut,
    NotificacionPaginadoOut,
)

router = APIRouter(prefix="/notificaciones", tags=["notificaciones"])

# venta_id se resuelve aca para que el cliente no tenga que saber que ENVIO apunta a envio.id:
# VENTA -> la propia entidad_id, ENVIO -> envio.venta_id. El resto queda NULL.
_SELECT_NOTIFICACION = """
    SELECT n.id, n.tipo::text AS tipo, n.titulo, n.mensaje, n.entidad_tipo, n.entidad_id,
           CASE
               WHEN n.entidad_tipo = 'VENTA' THEN n.entidad_id
               WHEN n.entidad_tipo = 'ENVIO' THEN e.venta_id
           END AS venta_id,
           n.leida, n.fecha
    FROM notificacion n
    LEFT JOIN envio e ON n.entidad_tipo = 'ENVIO' AND e.id = n.entidad_id
"""


def _fila_a_esquema(fila: asyncpg.Record) -> NotificacionOut:
    return NotificacionOut(
        id=fila["id"],
        tipo=fila["tipo"],
        titulo=fila["titulo"],
        mensaje=fila["mensaje"],
        entidad_tipo=fila["entidad_tipo"],
        entidad_id=fila["entidad_id"],
        venta_id=fila["venta_id"],
        leida=fila["leida"],
        fecha=fila["fecha"],
    )


async def _contar_no_leidas(conn: asyncpg.Connection, usuario_id: UUID) -> int:
    return await conn.fetchval(
        "SELECT COUNT(*) FROM notificacion WHERE usuario_id = $1 AND NOT leida",
        usuario_id,
    )


@router.get("", response_model=NotificacionPaginadoOut)
async def listar_notificaciones(
    solo_no_leidas: bool = Query(default=False),
    pagina: int = Query(default=1, ge=1),
    tamanio_pagina: int = Query(default=20, ge=1, le=100),
    conn: asyncpg.Connection = Depends(get_connection),
    usuario: dict = Depends(get_current_usuario),
) -> NotificacionPaginadoOut:
    filtros = "WHERE n.usuario_id = $1 AND ($2::boolean IS FALSE OR NOT n.leida)"

    total = await conn.fetchval(
        f"SELECT COUNT(*) FROM notificacion n {filtros}",
        usuario["id"],
        solo_no_leidas,
    )
    filas = await conn.fetch(
        f"""
        {_SELECT_NOTIFICACION}
        {filtros}
        ORDER BY n.fecha DESC, n.id
        LIMIT $3 OFFSET $4
        """,
        usuario["id"],
        solo_no_leidas,
        tamanio_pagina,
        (pagina - 1) * tamanio_pagina,
    )

    return NotificacionPaginadoOut(
        total=total,
        no_leidas=await _contar_no_leidas(conn, usuario["id"]),
        pagina=pagina,
        tamanio_pagina=tamanio_pagina,
        items=[_fila_a_esquema(fila) for fila in filas],
    )


@router.get("/no-leidas/cantidad", response_model=CantidadNoLeidasOut)
async def cantidad_no_leidas(
    conn: asyncpg.Connection = Depends(get_connection),
    usuario: dict = Depends(get_current_usuario),
) -> CantidadNoLeidasOut:
    return CantidadNoLeidasOut(no_leidas=await _contar_no_leidas(conn, usuario["id"]))


@router.post("/leer-todas", response_model=LeerTodasOut)
async def leer_todas(
    conn: asyncpg.Connection = Depends(get_connection),
    usuario: dict = Depends(get_current_usuario),
) -> LeerTodasOut:
    resultado = await conn.execute(
        "UPDATE notificacion SET leida = TRUE WHERE usuario_id = $1 AND NOT leida",
        usuario["id"],
    )
    # asyncpg devuelve el tag del comando, p.ej. "UPDATE 3"
    return LeerTodasOut(marcadas=int(resultado.split()[-1]))


@router.post("/{notificacion_id}/leida", response_model=NotificacionOut)
async def marcar_leida(
    notificacion_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    usuario: dict = Depends(get_current_usuario),
) -> NotificacionOut:
    # Filtrar por usuario_id en el mismo UPDATE: una notificacion ajena da 404 igual que una
    # inexistente, sin revelar que el id existe. Idempotente: marcar dos veces no falla.
    actualizada = await conn.fetchval(
        "UPDATE notificacion SET leida = TRUE WHERE id = $1 AND usuario_id = $2 RETURNING id",
        notificacion_id,
        usuario["id"],
    )
    if actualizada is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Notificacion no encontrada"
        )

    fila = await conn.fetchrow(f"{_SELECT_NOTIFICACION} WHERE n.id = $1", notificacion_id)
    return _fila_a_esquema(fila)
