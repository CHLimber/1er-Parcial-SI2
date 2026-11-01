"""La plataforma (SUPERADMIN) atiende las cuentas de personal de una empresa.

Caso tipico: el administrador de una empresa olvida su contrasena o su cuenta queda bloqueada, y
nadie mas de esa empresa puede arreglarlo (el ADMIN es quien gestiona usuarios, CU13). La
plataforma puede, SOLO sobre cuentas STAFF de una empresa: listarlas, dar de alta otro
administrador, activarlas/desactivarlas, restablecer la contrasena y quitar un bloqueo por
intentos. Nunca toca roles ni permisos ni cuentas de clientas, y no hay forma de leer una
contrasena. Todo queda en la bitacora (CU19) con la empresa afectada. Permiso `empresas.actualizar`.
"""

from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status

from app.core.auditoria import registrar_auditoria
from app.core.db import get_connection
from app.core.deps import requiere_permiso
from app.core.security import hash_password
from app.core.tenant import no_encontrado
from app.modules.plataforma_saas.saas.schemas import (
    AdminEmpresaIn,
    EstadoPersonalIn,
    PasswordPersonalIn,
    PersonalEmpresaOut,
)

router = APIRouter(prefix="/saas", tags=["saas-personal"])

plataforma_ver = requiere_permiso("empresas.leer")
plataforma_editar = requiere_permiso("empresas.actualizar")

SELECT_PERSONAL = """
SELECT u.id, u.email, u.nombre, u.apellido, u.activo, u.ultimo_acceso, u.empresa_id,
       r.nombre AS rol, e.cargo, s.nombre AS sucursal,
       (u.bloqueado_hasta IS NOT NULL AND u.bloqueado_hasta > now()) AS bloqueado
FROM usuario u
LEFT JOIN rol r      ON r.id = u.rol_id
LEFT JOIN empleado e ON e.usuario_id = u.id
LEFT JOIN sucursal s ON s.id = e.sucursal_id
WHERE u.tipo = 'STAFF' AND u.empresa_id IS NOT NULL
"""


def _salida(fila: asyncpg.Record) -> PersonalEmpresaOut:
    return PersonalEmpresaOut(**{k: fila[k] for k in PersonalEmpresaOut.model_fields})


async def _personal(conn: asyncpg.Connection, usuario_id: UUID) -> asyncpg.Record:
    """Cuenta de personal de una empresa; 404 si no existe o no es de ninguna empresa (la de la
    plataforma y las clientas no se tocan desde aca)."""
    fila = await conn.fetchrow(SELECT_PERSONAL + "AND u.id = $1", usuario_id)
    if fila is None:
        raise no_encontrado("Cuenta de personal no encontrada")
    return fila


@router.get("/empresas/{empresa_id}/usuarios", response_model=list[PersonalEmpresaOut])
async def listar_personal(
    empresa_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    _staff: dict = Depends(plataforma_ver),
) -> list[PersonalEmpresaOut]:
    if not await conn.fetchval("SELECT 1 FROM empresa WHERE id = $1", empresa_id):
        raise no_encontrado("Empresa no encontrada")
    filas = await conn.fetch(
        SELECT_PERSONAL
        + "AND u.empresa_id = $1 ORDER BY (r.nombre = 'ADMIN') DESC, u.activo DESC, u.apellido, u.nombre",
        empresa_id,
    )
    return [_salida(f) for f in filas]


@router.post(
    "/empresas/{empresa_id}/administradores",
    response_model=PersonalEmpresaOut,
    status_code=status.HTTP_201_CREATED,
)
async def agregar_administrador(
    empresa_id: UUID,
    body: AdminEmpresaIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(plataforma_editar),
) -> PersonalEmpresaOut:
    """Otro administrador para la empresa (por ejemplo, si el original dejo la empresa)."""
    if not await conn.fetchval("SELECT 1 FROM empresa WHERE id = $1", empresa_id):
        raise no_encontrado("Empresa no encontrada")
    try:
        async with conn.transaction():
            nuevo_id = await conn.fetchval(
                """
                INSERT INTO usuario (email, password_hash, nombre, apellido, tipo, rol_id,
                                     empresa_id, email_verificado)
                VALUES ($1, $2, $3, $4, 'STAFF',
                        (SELECT id FROM rol WHERE nombre = 'ADMIN' AND empresa_id IS NULL), $5, TRUE)
                RETURNING id
                """,
                body.email,
                hash_password(body.password),
                body.nombre,
                body.apellido,
                empresa_id,
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="usuario",
                entidad_id=nuevo_id,
                accion="CREAR",
                datos_despues={"email": body.email, "rol": "ADMIN"},
                empresa_id=empresa_id,
            )
    except asyncpg.UniqueViolationError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Ese email ya esta registrado en la plataforma"
        )
    return _salida(await _personal(conn, nuevo_id))


@router.patch("/usuarios/{usuario_id}/estado", response_model=PersonalEmpresaOut)
async def cambiar_estado_personal(
    usuario_id: UUID,
    body: EstadoPersonalIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(plataforma_editar),
) -> PersonalEmpresaOut:
    antes = await _personal(conn, usuario_id)
    if not body.activo and antes["activo"]:
        if await conn.fetchval(
            "SELECT 1 FROM sesion_caja WHERE empleado_id = $1 AND estado = 'ABIERTA'", usuario_id
        ):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="No se puede desactivar: tiene una sesion de caja abierta",
            )
    async with conn.transaction():
        await conn.execute("UPDATE usuario SET activo = $2 WHERE id = $1", usuario_id, body.activo)
        await conn.execute("UPDATE empleado SET activo = $2 WHERE usuario_id = $1", usuario_id, body.activo)
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="usuario",
            entidad_id=usuario_id,
            accion="ACTUALIZAR" if body.activo else "ELIMINAR",
            datos_antes={"activo": antes["activo"]},
            datos_despues={"activo": body.activo},
            empresa_id=antes["empresa_id"],
        )
    return _salida(await _personal(conn, usuario_id))


@router.post("/usuarios/{usuario_id}/password", status_code=status.HTTP_204_NO_CONTENT)
async def restablecer_password_personal(
    usuario_id: UUID,
    body: PasswordPersonalIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(plataforma_editar),
) -> None:
    """Contrasena nueva para una cuenta de la empresa; ademas la desbloquea, porque quien
    olvido su contrasena casi seguro agoto los intentos."""
    antes = await _personal(conn, usuario_id)
    async with conn.transaction():
        await conn.execute(
            """
            UPDATE usuario SET password_hash = $2, intentos_fallidos = 0, bloqueado_hasta = NULL
             WHERE id = $1
            """,
            usuario_id,
            hash_password(body.password),
        )
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="usuario",
            entidad_id=usuario_id,
            accion="ACTUALIZAR",
            datos_despues={"password": "restablecida por la plataforma"},
            empresa_id=antes["empresa_id"],
        )


@router.post("/usuarios/{usuario_id}/desbloquear", response_model=PersonalEmpresaOut)
async def desbloquear_personal(
    usuario_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(plataforma_editar),
) -> PersonalEmpresaOut:
    antes = await _personal(conn, usuario_id)
    async with conn.transaction():
        await conn.execute(
            "UPDATE usuario SET intentos_fallidos = 0, bloqueado_hasta = NULL WHERE id = $1", usuario_id
        )
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="usuario",
            entidad_id=usuario_id,
            accion="ACTUALIZAR",
            datos_despues={"bloqueo": "quitado por la plataforma"},
            empresa_id=antes["empresa_id"],
        )
    return _salida(await _personal(conn, usuario_id))
