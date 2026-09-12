"""Registro de auditoria (tabla auditoria del bloque 7 del esquema).

Los casos de uso de gestion (CU10 a CU13) dejan rastro de quien creo, modifico o dio de baja
cada entidad maestra. No se usa un trigger generico porque interesa guardar el usuario de la
sesion HTTP, que la base no conoce.
"""

import json
from typing import Any
from uuid import UUID

import asyncpg


def _serializar(datos: dict[str, Any] | None) -> str | None:
    if datos is None:
        return None
    return json.dumps(datos, default=str, ensure_ascii=False)


async def registrar_auditoria(
    conn: asyncpg.Connection,
    *,
    usuario_id: UUID | None,
    entidad: str,
    entidad_id: Any,
    accion: str,
    datos_antes: dict[str, Any] | None = None,
    datos_despues: dict[str, Any] | None = None,
) -> None:
    await conn.execute(
        """
        INSERT INTO auditoria (usuario_id, entidad, entidad_id, accion, datos_antes, datos_despues)
        VALUES ($1, $2, $3, $4::accion_auditoria, $5::jsonb, $6::jsonb)
        """,
        usuario_id,
        entidad,
        str(entidad_id),
        accion,
        _serializar(datos_antes),
        _serializar(datos_despues),
    )
