"""CU13 - Gestionar Usuarios y Roles.

El alta de clientes es autoservicio (CU02); aca el administrador gestiona al personal, y sobre
todo define que puede hacer cada rol. Los codigos de permiso que se asignan en este modulo son
los mismos que consume requiere_permiso() en app/core/deps.py, asi que un cambio hecho desde
esta pantalla se siente en toda la API sin tocar codigo.
"""

from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.auditoria import registrar_auditoria
from app.core.db import get_connection
from app.core.deps import requiere_permiso
from app.core.security import hash_password
from app.modules.usuarios.admin_schemas import (
    ClienteUpdate,
    EmpleadoOut,
    EstadoIn,
    PasswordIn,
    PermisoOut,
    PermisosIn,
    RolIn,
    RolOut,
    StaffIn,
    StaffUpdate,
    UsuarioAdminOut,
)

router = APIRouter(prefix="/admin", tags=["usuarios-admin"])

puede_ver_usuarios = requiere_permiso(
    "usuarios.leer", "usuarios.crear", "usuarios.actualizar", "usuarios.eliminar"
)
puede_crear_usuarios = requiere_permiso("usuarios.crear")
puede_actualizar_usuarios = requiere_permiso("usuarios.actualizar")
# baja/reactivacion via PATCH .../estado: cualquiera de las dos alcanza para prender o apagar
puede_cambiar_estado_usuario = requiere_permiso("usuarios.actualizar", "usuarios.eliminar")

puede_ver_roles = requiere_permiso("roles.leer", "roles.crear", "roles.actualizar", "roles.eliminar")
puede_crear_roles = requiere_permiso("roles.crear")
puede_actualizar_roles = requiere_permiso("roles.actualizar")
puede_eliminar_roles = requiere_permiso("roles.eliminar")

# Actores humanos de la tienda (PENDIENTES 2.19.1.d): el ENCARGADO absorbio lo de ALMACEN y el
# CAJERO lo de VENDEDOR. El ADMIN es un rol, no un cargo: su fila de empleado usa ENCARGADO.
CARGOS = {"ENCARGADO", "CAJERO"}

SELECT_USUARIO = """
SELECT u.id, u.email, u.nombre, u.apellido, u.telefono, u.tipo, u.rol_id, r.nombre AS rol,
       u.activo, u.email_verificado, u.ultimo_acceso, u.creado_en,
       e.sucursal_id, s.nombre AS sucursal, e.cargo, e.ci, e.fecha_ingreso,
       e.activo AS empleado_activo
FROM usuario u
LEFT JOIN rol r      ON r.id = u.rol_id
LEFT JOIN empleado e ON e.usuario_id = u.id
LEFT JOIN sucursal s ON s.id = e.sucursal_id
"""


def _a_usuario(fila: asyncpg.Record) -> UsuarioAdminOut:
    empleado = None
    if fila["sucursal_id"] is not None:
        empleado = EmpleadoOut(
            sucursal_id=fila["sucursal_id"],
            sucursal=fila["sucursal"],
            cargo=fila["cargo"],
            ci=fila["ci"],
            fecha_ingreso=fila["fecha_ingreso"],
            activo=fila["empleado_activo"],
        )
    return UsuarioAdminOut(
        id=fila["id"],
        email=fila["email"],
        nombre=fila["nombre"],
        apellido=fila["apellido"],
        telefono=fila["telefono"],
        tipo=fila["tipo"],
        rol_id=fila["rol_id"],
        rol=fila["rol"],
        activo=fila["activo"],
        email_verificado=fila["email_verificado"],
        ultimo_acceso=fila["ultimo_acceso"],
        creado_en=fila["creado_en"],
        empleado=empleado,
    )


async def _obtener_usuario(conn: asyncpg.Connection, usuario_id: UUID) -> UsuarioAdminOut:
    fila = await conn.fetchrow(SELECT_USUARIO + "WHERE u.id = $1", usuario_id)
    if fila is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Usuario no encontrado")
    return _a_usuario(fila)


def _validar_cargo(cargo: str) -> str:
    if cargo not in CARGOS:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Cargo invalido. Valores posibles: {', '.join(sorted(CARGOS))}",
        )
    return cargo


async def _validar_rol_staff(conn: asyncpg.Connection, rol_id: int) -> None:
    existe = await conn.fetchval("SELECT 1 FROM rol WHERE id = $1", rol_id)
    if not existe:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="El rol no existe")


# ---------------------------------------------------------------------
#  USUARIOS
# ---------------------------------------------------------------------


@router.get("/usuarios", response_model=list[UsuarioAdminOut])
async def listar_usuarios(
    q: str | None = Query(default=None, description="Busca por nombre, apellido o email"),
    tipo: str | None = Query(default=None, pattern="^(CLIENTE|STAFF)$"),
    activo: bool | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    _staff: dict = Depends(puede_ver_usuarios),
) -> list[UsuarioAdminOut]:
    filas = await conn.fetch(
        SELECT_USUARIO
        + """
        WHERE ($1::text IS NULL OR u.nombre ILIKE '%' || $1 || '%'
                                OR u.apellido ILIKE '%' || $1 || '%'
                                OR u.email ILIKE '%' || $1 || '%')
          AND ($2::text IS NULL OR u.tipo::text = $2)
          AND ($3::boolean IS NULL OR u.activo = $3)
        ORDER BY u.tipo, u.activo DESC, u.apellido, u.nombre
        """,
        q,
        tipo,
        activo,
    )
    return [_a_usuario(fila) for fila in filas]


@router.get("/usuarios/{usuario_id}", response_model=UsuarioAdminOut)
async def obtener_usuario(
    usuario_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    _staff: dict = Depends(puede_ver_usuarios),
) -> UsuarioAdminOut:
    return await _obtener_usuario(conn, usuario_id)


@router.post("/usuarios", response_model=UsuarioAdminOut, status_code=status.HTTP_201_CREATED)
async def crear_staff(
    body: StaffIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_crear_usuarios),
) -> UsuarioAdminOut:
    """Alta de personal. Crea el usuario STAFF y su fila en empleado en la misma transaccion:
    un STAFF sin sucursal no podria operar caja ni atender reservas."""
    _validar_cargo(body.cargo)
    await _validar_rol_staff(conn, body.rol_id)

    sucursal = await conn.fetchval("SELECT activa FROM sucursal WHERE id = $1", body.sucursal_id)
    if sucursal is None:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="La sucursal no existe")
    if not sucursal:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="No se puede asignar personal a una sucursal dada de baja",
        )

    try:
        async with conn.transaction():
            nuevo_id = await conn.fetchval(
                """
                INSERT INTO usuario (email, password_hash, nombre, apellido, telefono,
                                     tipo, rol_id, email_verificado)
                VALUES ($1, $2, $3, $4, $5, 'STAFF', $6, TRUE)
                RETURNING id
                """,
                body.email,
                hash_password(body.password),
                body.nombre,
                body.apellido,
                body.telefono,
                body.rol_id,
            )
            await conn.execute(
                """
                INSERT INTO empleado (usuario_id, sucursal_id, ci, cargo, fecha_ingreso)
                VALUES ($1, $2, $3, $4::cargo_empleado, COALESCE($5, CURRENT_DATE))
                """,
                nuevo_id,
                body.sucursal_id,
                body.ci,
                body.cargo,
                body.fecha_ingreso,
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="usuario",
                entidad_id=nuevo_id,
                accion="CREAR",
                datos_despues=body.model_dump(mode="json", exclude={"password"}),
            )
    except asyncpg.UniqueViolationError:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Ese correo ya esta registrado")

    return await _obtener_usuario(conn, nuevo_id)


@router.put("/usuarios/{usuario_id}", response_model=UsuarioAdminOut)
async def actualizar_staff(
    usuario_id: UUID,
    body: StaffUpdate,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_actualizar_usuarios),
) -> UsuarioAdminOut:
    antes = await _obtener_usuario(conn, usuario_id)
    if antes.tipo != "STAFF":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Este usuario es un cliente: usa el endpoint de clientes",
        )

    _validar_cargo(body.cargo)
    await _validar_rol_staff(conn, body.rol_id)

    try:
        async with conn.transaction():
            await conn.execute(
                """
                UPDATE usuario
                   SET email = $2, nombre = $3, apellido = $4, telefono = $5, rol_id = $6
                 WHERE id = $1
                """,
                usuario_id,
                body.email,
                body.nombre,
                body.apellido,
                body.telefono,
                body.rol_id,
            )
            await conn.execute(
                """
                INSERT INTO empleado (usuario_id, sucursal_id, ci, cargo, fecha_ingreso)
                VALUES ($1, $2, $3, $4::cargo_empleado, COALESCE($5, CURRENT_DATE))
                ON CONFLICT (usuario_id) DO UPDATE
                   SET sucursal_id = EXCLUDED.sucursal_id,
                       ci = EXCLUDED.ci,
                       cargo = EXCLUDED.cargo,
                       fecha_ingreso = EXCLUDED.fecha_ingreso
                """,
                usuario_id,
                body.sucursal_id,
                body.ci,
                body.cargo,
                body.fecha_ingreso,
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="usuario",
                entidad_id=usuario_id,
                accion="ACTUALIZAR",
                datos_antes=antes.model_dump(mode="json"),
                datos_despues=body.model_dump(mode="json"),
            )
    except asyncpg.UniqueViolationError:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Ese correo ya esta registrado")

    return await _obtener_usuario(conn, usuario_id)


@router.put("/clientes/{usuario_id}", response_model=UsuarioAdminOut)
async def actualizar_cliente(
    usuario_id: UUID,
    body: ClienteUpdate,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_actualizar_usuarios),
) -> UsuarioAdminOut:
    """Correccion de datos de contacto de un cliente. No toca rol ni tipo: la constraint
    ck_usuario_rol prohibe que un CLIENTE tenga rol operativo."""
    antes = await _obtener_usuario(conn, usuario_id)
    if antes.tipo != "CLIENTE":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Este usuario es personal, no un cliente"
        )

    try:
        async with conn.transaction():
            await conn.execute(
                "UPDATE usuario SET email = $2, nombre = $3, apellido = $4, telefono = $5 WHERE id = $1",
                usuario_id,
                body.email,
                body.nombre,
                body.apellido,
                body.telefono,
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="usuario",
                entidad_id=usuario_id,
                accion="ACTUALIZAR",
                datos_antes=antes.model_dump(mode="json"),
                datos_despues=body.model_dump(mode="json"),
            )
    except asyncpg.UniqueViolationError:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Ese correo ya esta registrado")

    return await _obtener_usuario(conn, usuario_id)


@router.patch("/usuarios/{usuario_id}/estado", response_model=UsuarioAdminOut)
async def cambiar_estado_usuario(
    usuario_id: UUID,
    body: EstadoIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_cambiar_estado_usuario),
) -> UsuarioAdminOut:
    """Baja logica. El usuario queda referenciado por ventas, reservas y kardex, asi que nunca
    se borra: se desactiva y el login lo rechaza."""
    if usuario_id == staff["id"] and not body.activo:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="No podes desactivar tu propia cuenta"
        )

    antes = await _obtener_usuario(conn, usuario_id)

    if not body.activo and antes.empleado is not None:
        caja_abierta = await conn.fetchval(
            "SELECT 1 FROM sesion_caja WHERE empleado_id = $1 AND estado = 'ABIERTA'", usuario_id
        )
        if caja_abierta:
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
            datos_antes={"activo": antes.activo},
            datos_despues={"activo": body.activo},
        )
    return await _obtener_usuario(conn, usuario_id)


@router.post("/usuarios/{usuario_id}/password", status_code=status.HTTP_204_NO_CONTENT)
async def restablecer_password(
    usuario_id: UUID,
    body: PasswordIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_actualizar_usuarios),
) -> None:
    await _obtener_usuario(conn, usuario_id)
    async with conn.transaction():
        await conn.execute(
            "UPDATE usuario SET password_hash = $2 WHERE id = $1",
            usuario_id,
            hash_password(body.password),
        )
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="usuario",
            entidad_id=usuario_id,
            accion="ACTUALIZAR",
            datos_despues={"password": "restablecida"},
        )


# ---------------------------------------------------------------------
#  ROLES Y PERMISOS
# ---------------------------------------------------------------------

SELECT_ROL = """
SELECT r.id, r.nombre, r.descripcion, r.es_sistema,
       (SELECT COUNT(*) FROM usuario u WHERE u.rol_id = r.id) AS usuarios,
       COALESCE(
           (SELECT array_agg(rp.permiso_id ORDER BY rp.permiso_id)
              FROM rol_permiso rp WHERE rp.rol_id = r.id),
           ARRAY[]::int[]
       ) AS permisos
FROM rol r
"""


async def _obtener_rol(conn: asyncpg.Connection, rol_id: int) -> RolOut:
    fila = await conn.fetchrow(SELECT_ROL + "WHERE r.id = $1", rol_id)
    if fila is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Rol no encontrado")
    return RolOut(**dict(fila))


@router.get("/permisos", response_model=list[PermisoOut])
async def listar_permisos(
    conn: asyncpg.Connection = Depends(get_connection),
    _staff: dict = Depends(puede_ver_roles),
) -> list[PermisoOut]:
    filas = await conn.fetch("SELECT id, codigo, modulo, descripcion FROM permiso ORDER BY modulo, codigo")
    return [PermisoOut(**dict(fila)) for fila in filas]


@router.get("/roles", response_model=list[RolOut])
async def listar_roles(
    conn: asyncpg.Connection = Depends(get_connection),
    _staff: dict = Depends(puede_ver_roles),
) -> list[RolOut]:
    filas = await conn.fetch(SELECT_ROL + "ORDER BY r.es_sistema DESC, r.nombre")
    return [RolOut(**dict(fila)) for fila in filas]


@router.post("/roles", response_model=RolOut, status_code=status.HTTP_201_CREATED)
async def crear_rol(
    body: RolIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_crear_roles),
) -> RolOut:
    try:
        async with conn.transaction():
            nuevo_id = await conn.fetchval(
                "INSERT INTO rol (nombre, descripcion, es_sistema) VALUES ($1, $2, FALSE) RETURNING id",
                body.nombre.upper(),
                body.descripcion,
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="rol",
                entidad_id=nuevo_id,
                accion="CREAR",
                datos_despues=body.model_dump(mode="json"),
            )
    except asyncpg.UniqueViolationError:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Ya existe un rol con ese nombre")
    return await _obtener_rol(conn, nuevo_id)


@router.put("/roles/{rol_id}", response_model=RolOut)
async def actualizar_rol(
    rol_id: int,
    body: RolIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_actualizar_roles),
) -> RolOut:
    antes = await _obtener_rol(conn, rol_id)
    if antes.es_sistema and body.nombre.upper() != antes.nombre:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Un rol del sistema no se puede renombrar, solo cambiar su descripcion y permisos",
        )

    try:
        async with conn.transaction():
            await conn.execute(
                "UPDATE rol SET nombre = $2, descripcion = $3 WHERE id = $1",
                rol_id,
                body.nombre.upper(),
                body.descripcion,
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="rol",
                entidad_id=rol_id,
                accion="ACTUALIZAR",
                datos_antes=antes.model_dump(mode="json"),
                datos_despues=body.model_dump(mode="json"),
            )
    except asyncpg.UniqueViolationError:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Ya existe un rol con ese nombre")
    return await _obtener_rol(conn, rol_id)


@router.put("/roles/{rol_id}/permisos", response_model=RolOut)
async def asignar_permisos(
    rol_id: int,
    body: PermisosIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_actualizar_roles),
) -> RolOut:
    """Reemplaza la matriz de permisos del rol. Se impide dejar al rol ADMIN sin la llave de
    usuarios/roles: seria imposible volver a entrar a gestionar permisos."""
    antes = await _obtener_rol(conn, rol_id)

    if antes.nombre == "ADMIN":
        llaves = await conn.fetch(
            "SELECT id FROM permiso WHERE codigo IN ('usuarios.actualizar','roles.actualizar')"
        )
        faltantes = [fila["id"] for fila in llaves if fila["id"] not in body.permisos]
        if faltantes:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="El rol ADMIN debe conservar los permisos usuarios.actualizar y roles.actualizar",
            )

    try:
        async with conn.transaction():
            await conn.execute("DELETE FROM rol_permiso WHERE rol_id = $1", rol_id)
            if body.permisos:
                await conn.executemany(
                    "INSERT INTO rol_permiso (rol_id, permiso_id) VALUES ($1, $2)",
                    [(rol_id, permiso_id) for permiso_id in set(body.permisos)],
                )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="rol_permiso",
                entidad_id=rol_id,
                accion="ACTUALIZAR",
                datos_antes={"permisos": antes.permisos},
                datos_despues={"permisos": body.permisos},
            )
    except asyncpg.ForeignKeyViolationError:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Alguno de los permisos no existe"
        )
    return await _obtener_rol(conn, rol_id)


@router.delete("/roles/{rol_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar_rol(
    rol_id: int,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_eliminar_roles),
) -> None:
    rol = await _obtener_rol(conn, rol_id)
    if rol.es_sistema:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Los roles del sistema no se pueden eliminar"
        )
    if rol.usuarios:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"El rol tiene {rol.usuarios} usuario(s) asignado(s)",
        )

    async with conn.transaction():
        await conn.execute("DELETE FROM rol WHERE id = $1", rol_id)
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="rol",
            entidad_id=rol_id,
            accion="ELIMINAR",
            datos_antes=rol.model_dump(mode="json"),
        )
