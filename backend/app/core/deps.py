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
