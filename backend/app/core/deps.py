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


# CU07 y CU08 autorizan por PERMISO (PENDIENTES 3.1), igual que el resto del sistema: el cargo
# ya no decide quien opera. Ademas del permiso exigen una fila activa en `empleado`, porque
# caja y reservas son operaciones DE UNA SUCURSAL y los routers necesitan su sucursal_id.
#   - Caja (CU07, /caja/* y /ventas/pos): permiso `caja.crear` (operar la caja: abrir sesion,
#     cobrar, verificar pagos QR/efectivo, cerrar). Lo tienen CAJERO, ENCARGADO y ADMIN.
#   - Reservas (CU08, /reservas/sucursal y confirmar/rechazar/preparar/...): permiso
#     `reservas.actualizar`. Lo tienen ENCARGADO y ADMIN.
# Decision: el ADMIN puede operar caja y reservas, pero solo las de la sucursal de su propia
# fila de empleado (en el seed, Equipetrol). Un ADMIN sin fila de empleado recibe 403: no hay
# una sucursal "por defecto" sobre la que operar.
# Los destinatarios de notificaciones (reservas/router.py, pagos/servicio.py) se siguen
# eligiendo por cargo ENCARGADO/CAJERO: eso dice QUIEN es la persona, no QUE puede hacer.


async def _empleado_con_permiso(
    conn: asyncpg.Connection, usuario: dict, codigo: str, detalle: str
) -> dict:
    if usuario["tipo"] != "STAFF":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=detalle)

    if codigo not in await obtener_permisos(conn, usuario["id"]):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tu rol no tiene permiso para esta operacion",
        )

    empleado = await conn.fetchrow(
        "SELECT usuario_id, sucursal_id FROM empleado WHERE usuario_id = $1 AND activo",
        usuario["id"],
    )
    if empleado is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tu usuario no esta asignado a una sucursal",
        )

    return {"usuario_id": empleado["usuario_id"], "sucursal_id": empleado["sucursal_id"]}


async def get_cajero_actual(
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> dict:
    """CU07: STAFF con permiso `caja.crear` y sucursal asignada."""
    return await _empleado_con_permiso(
        conn, usuario, "caja.crear", "Solo el personal de caja puede operar la caja"
    )


async def get_encargado_actual(
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> dict:
    """CU08: STAFF con permiso `reservas.actualizar` y sucursal asignada."""
    return await _empleado_con_permiso(
        conn,
        usuario,
        "reservas.actualizar",
        "Solo el encargado de sucursal puede atender reservas",
    )


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
    pedidos."""

    async def verificar(staff: dict = Depends(get_staff_actual)) -> dict:
        if not any(codigo in staff["permisos"] for codigo in codigos):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Tu rol no tiene permiso para esta operacion",
            )
        return staff

    return verificar
