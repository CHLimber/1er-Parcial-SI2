"""CU19 - Consultar Bitacora de Auditoria.

Solo lectura sobre la tabla `auditoria` (bloque 7 del esquema, ver db/01_schema.sql:639),
poblada por `app/core/auditoria.py` desde los CU de gestion (CU10 a CU13) y por el login
(usuarios/router.py). Permiso unico `auditoria.leer`, sembrado solo para ADMIN en
db/03_datos_iniciales.sql: a diferencia de `reportes.leer` (acotado por sucursal), la
bitacora es del sistema completo -- usuarios, roles, catalogo, sucursales, proveedores,
recepciones -- y `auditoria` no tiene `sucursal_id` para acotar, asi que no se le da a
ENCARGADO ni a ningun otro rol.

asyncpg no tiene un codec de jsonb configurado (ver app/core/db.py), asi que las columnas
`datos_antes`/`datos_despues` llegan como texto JSON y se parsean a mano en `_fila_a_esquema`.
"""

import json
from datetime import date, datetime, time, timezone
from typing import Any
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.db import get_connection
from app.core.deps import requiere_permiso
from app.modules.auditoria.schemas import AuditoriaOut, AuditoriaPaginadoOut

router = APIRouter(prefix="/auditoria", tags=["auditoria"])

puede_ver = requiere_permiso("auditoria.leer")


def _parsear_json(valor: str | None) -> dict[str, Any] | None:
    return json.loads(valor) if valor is not None else None


def _fila_a_esquema(fila: asyncpg.Record) -> AuditoriaOut:
    return AuditoriaOut(
        id=fila["id"],
        fecha=fila["fecha"],
        usuario_id=fila["usuario_id"],
        usuario_nombre=(
            f"{fila['nombre']} {fila['apellido']}" if fila["nombre"] is not None else None
        ),
        usuario_email=fila["email"],
        entidad=fila["entidad"],
        entidad_id=fila["entidad_id"],
        accion=fila["accion"],
        datos_antes=_parsear_json(fila["datos_antes"]),
        datos_despues=_parsear_json(fila["datos_despues"]),
        ip=str(fila["ip"]) if fila["ip"] is not None else None,
    )


@router.get("", response_model=AuditoriaPaginadoOut)
async def listar_auditoria(
    usuario_id: UUID | None = Query(default=None),
    entidad: str | None = Query(default=None),
    entidad_id: str | None = Query(default=None),
    accion: str | None = Query(default=None, pattern="^(CREAR|ACTUALIZAR|ELIMINAR|LOGIN)$"),
    desde: date | None = Query(default=None),
    hasta: date | None = Query(default=None),
    pagina: int = Query(default=1, ge=1),
    tamanio_pagina: int = Query(default=20, ge=1, le=100),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> AuditoriaPaginadoOut:
    if desde is not None and hasta is not None and desde > hasta:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="La fecha 'desde' no puede ser posterior a 'hasta'",
        )
    # `fecha` es TIMESTAMPTZ; el filtro de fecha viene como date "de calendario",
    # asi que se expande al dia completo en UTC.
    desde_dt = datetime.combine(desde, time.min, tzinfo=timezone.utc) if desde else None
    hasta_dt = datetime.combine(hasta, time.max, tzinfo=timezone.utc) if hasta else None

    filtros = """
        WHERE ($1::uuid IS NULL OR a.usuario_id = $1)
          AND ($2::varchar IS NULL OR a.entidad = $2)
          AND ($3::varchar IS NULL OR a.entidad_id = $3)
          AND ($4::accion_auditoria IS NULL OR a.accion = $4)
          AND ($5::timestamptz IS NULL OR a.fecha >= $5)
          AND ($6::timestamptz IS NULL OR a.fecha <= $6)
    """
    parametros = [usuario_id, entidad, entidad_id, accion, desde_dt, hasta_dt]

    total = await conn.fetchval(
        f"SELECT COUNT(*) FROM auditoria a {filtros}",
        *parametros,
    )

    filas = await conn.fetch(
        f"""
        SELECT a.id, a.fecha, a.usuario_id, u.nombre, u.apellido, u.email,
               a.entidad, a.entidad_id, a.accion::text AS accion,
               a.datos_antes, a.datos_despues, a.ip
        FROM auditoria a
        LEFT JOIN usuario u ON u.id = a.usuario_id
        {filtros}
        ORDER BY a.fecha DESC
        LIMIT ${len(parametros) + 1} OFFSET ${len(parametros) + 2}
        """,
        *parametros,
        tamanio_pagina,
        (pagina - 1) * tamanio_pagina,
    )

    return AuditoriaPaginadoOut(
        total=total,
        pagina=pagina,
        tamanio_pagina=tamanio_pagina,
        items=[_fila_a_esquema(fila) for fila in filas],
    )


@router.get("/entidades", response_model=list[str])
async def listar_entidades(
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[str]:
    """Valores distintos de `entidad` ya registrados, para armar el filtro en el panel."""
    filas = await conn.fetch("SELECT DISTINCT entidad FROM auditoria ORDER BY entidad")
    return [fila["entidad"] for fila in filas]
