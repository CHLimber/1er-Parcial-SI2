import asyncpg
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.db import get_connection
from app.core.security import decode_access_token

bearer_scheme = HTTPBearer(auto_error=False)


async def get_current_usuario(
    credenciales: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    conn: asyncpg.Connection = Depends(get_connection),
) -> dict:
    sesion_invalida = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED, detail="Sesion invalida o expirada"
    )
    if credenciales is None:
        raise sesion_invalida

    payload = decode_access_token(credenciales.credentials)
    if payload is None or "sub" not in payload:
        raise sesion_invalida

    fila = await conn.fetchrow(
        "SELECT id, tipo, activo FROM usuario WHERE id = $1::uuid",
        payload["sub"],
    )
    if fila is None or not fila["activo"]:
        raise sesion_invalida

    return {"id": fila["id"], "tipo": fila["tipo"]}


async def get_cajero_actual(
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> dict:
    """CU07: exige que el usuario sea STAFF con cargo CAJERO. No hay middleware de roles/permisos
    todavia (ver CLAUDE.md), asi que se valida igual que _exigir_cliente en otros routers."""
    if usuario["tipo"] != "STAFF":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo un cajero puede operar la caja",
        )

    empleado = await conn.fetchrow(
        "SELECT usuario_id, sucursal_id FROM empleado WHERE usuario_id = $1 AND activo AND cargo = 'CAJERO'",
        usuario["id"],
    )
    if empleado is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tu usuario no tiene el cargo de Cajero",
        )

    return {"usuario_id": empleado["usuario_id"], "sucursal_id": empleado["sucursal_id"]}
