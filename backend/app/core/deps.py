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


async def get_encargado_actual(
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> dict:
    """CU08: exige que el usuario sea STAFF con cargo ENCARGADO de una sucursal."""
    if usuario["tipo"] != "STAFF":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo un encargado de sucursal puede atender reservas",
        )

    empleado = await conn.fetchrow(
        "SELECT usuario_id, sucursal_id FROM empleado WHERE usuario_id = $1 AND activo AND cargo = 'ENCARGADO'",
        usuario["id"],
    )
    if empleado is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tu usuario no tiene el cargo de Encargado",
        )

    return {"usuario_id": empleado["usuario_id"], "sucursal_id": empleado["sucursal_id"]}


async def obtener_permisos(conn: asyncpg.Connection, usuario_id) -> list[str]:
    """Codigos de permiso que el rol del usuario tiene concedidos (tablas rol, rol_permiso,
    permiso). Un CLIENTE nunca tiene rol, asi que siempre devuelve lista vacia."""
    filas = await conn.fetch(
        """
        SELECT p.codigo
        FROM usuario u
        JOIN rol_permiso rp ON rp.rol_id = u.rol_id
        JOIN permiso p      ON p.id = rp.permiso_id
        WHERE u.id = $1
        ORDER BY p.codigo
        """,
        usuario_id,
    )
    return [fila["codigo"] for fila in filas]


async def get_staff_actual(
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> dict:
    """Usuario STAFF con su rol, sus permisos y (si esta atado a una) su sucursal."""
    if usuario["tipo"] != "STAFF":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Esta seccion es solo para personal de FashionStore",
        )

    fila = await conn.fetchrow(
        """
        SELECT u.id, r.nombre AS rol, e.sucursal_id, e.cargo
        FROM usuario u
        LEFT JOIN rol r      ON r.id = u.rol_id
        LEFT JOIN empleado e ON e.usuario_id = u.id AND e.activo
        WHERE u.id = $1
        """,
        usuario["id"],
    )
    if fila is None or fila["rol"] is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tu usuario no tiene un rol asignado",
        )

    return {
        "id": fila["id"],
        "rol": fila["rol"],
        "sucursal_id": fila["sucursal_id"],
        "cargo": fila["cargo"],
        "permisos": await obtener_permisos(conn, fila["id"]),
    }


def requiere_permiso(*codigos: str):
    """Dependencia de autorizacion por permiso (CU13). Basta con tener uno de los codigos
    pedidos. Reemplaza a la validacion por cargo que usaban CU07/CU08."""

    async def verificar(staff: dict = Depends(get_staff_actual)) -> dict:
        if not any(codigo in staff["permisos"] for codigo in codigos):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Tu rol no tiene permiso para esta operacion",
            )
        return staff

    return verificar
