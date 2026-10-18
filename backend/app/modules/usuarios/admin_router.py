"""CU13 - Gestionar Usuarios y Roles.

El alta de clientes es autoservicio (CU02); aca el administrador gestiona al personal, y sobre
todo define que puede hacer cada rol. Los codigos de permiso que se asignan en este modulo son
los mismos que consume requiere_permiso() en app/core/deps.py, asi que un cambio hecho desde
esta pantalla se siente en toda la API sin tocar codigo.

Multi-tenant: cada empresa gestiona SU personal (usuario.empresa_id) y sus roles propios
(rol.empresa_id). Los roles del sistema (empresa_id NULL) los comparten todas las empresas, por
eso aca son de solo lectura: cambiarle los permisos al ADMIN de una empresa se los cambiaria a
todas. Los permisos de la plataforma (modulos empresas/planes) nunca se listan ni se asignan.
Las cuentas de las clientas son de la plataforma: una empresa ve las de su cartera pero no les
cambia email, contrasena ni estado (eso seria tomar una cuenta que tambien compra en otras
tiendas); la ficha propia de la clienta se edita en /clientes.
"""

from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.auditoria import registrar_auditoria
from app.core.db import get_connection
from app.core.deps import requiere_permiso
from app.core.plan import exigir_limite
from app.core.security import hash_password
from app.core.tenant import empresa_de, no_encontrado
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

# El ADMIN es un rol, no un cargo: su fila de empleado usa ENCARGADO.
CARGOS = {"ENCARGADO", "CAJERO", "VENDEDOR", "ALMACEN"}

# modulos de permiso que son de la plataforma, no de una empresa
MODULOS_PLATAFORMA = ("empresas", "planes")

# Usuarios que una empresa puede ver: su personal y las clientas de su cartera (alta a mano o
# que compraron/reservaron en alguna de sus sucursales). $1 = empresa.
FILTRO_EMPRESA = """
(u.empresa_id = $1
 OR (u.tipo = 'CLIENTE' AND (
       EXISTS (SELECT 1 FROM cliente_perfil_tenant cp WHERE cp.usuario_id = u.id AND cp.empresa_id = $1)
    OR EXISTS (SELECT 1 FROM venta v JOIN sucursal sv ON sv.id = v.sucursal_id
                WHERE v.usuario_id = u.id AND sv.empresa_id = $1)
    OR EXISTS (SELECT 1 FROM reserva r JOIN sucursal sr ON sr.id = r.sucursal_id
                WHERE r.usuario_id = u.id AND sr.empresa_id = $1))))
"""

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


async def _obtener_usuario(
    conn: asyncpg.Connection, usuario_id: UUID, empresa_id: UUID
) -> UsuarioAdminOut:
    """404 si el usuario no es de la empresa (ni personal ni de su cartera)."""
    fila = await conn.fetchrow(
        SELECT_USUARIO + "WHERE u.id = $2 AND " + FILTRO_EMPRESA, empresa_id, usuario_id
    )
    if fila is None:
        raise no_encontrado("Usuario no encontrado")
    return _a_usuario(fila)


async def _obtener_staff_propio(
    conn: asyncpg.Connection, usuario_id: UUID, empresa_id: UUID
) -> UsuarioAdminOut:
    usuario = await _obtener_usuario(conn, usuario_id, empresa_id)
    if usuario.tipo != "STAFF":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="La cuenta de una clienta es de la plataforma: su ficha se edita en Clientes",
        )
    return usuario


def _validar_cargo(cargo: str) -> str:
    if cargo not in CARGOS:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Cargo invalido. Valores posibles: {', '.join(sorted(CARGOS))}",
        )
    return cargo


async def _validar_rol_staff(conn: asyncpg.Connection, rol_id: int, empresa_id: UUID) -> None:
    """El rol tiene que ser del sistema (salvo SUPERADMIN, que es de la plataforma) o propio
    de la empresa."""
    existe = await conn.fetchval(
        """
        SELECT 1 FROM rol
         WHERE id = $1
           AND (empresa_id = $2 OR (empresa_id IS NULL AND nombre <> 'SUPERADMIN'))
        """,
        rol_id,
        empresa_id,
    )
    if not existe:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="El rol no existe")


async def _validar_sucursal_activa(
    conn: asyncpg.Connection, sucursal_id: UUID, empresa_id: UUID
) -> None:
    sucursal = await conn.fetchval(
        "SELECT activa FROM sucursal WHERE id = $1 AND empresa_id = $2", sucursal_id, empresa_id
    )
    if sucursal is None:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="La sucursal no existe")
    if not sucursal:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="No se puede asignar personal a una sucursal dada de baja",
        )


# ---------------------------------------------------------------------
#  USUARIOS
# ---------------------------------------------------------------------


@router.get("/usuarios", response_model=list[UsuarioAdminOut])
async def listar_usuarios(
    q: str | None = Query(default=None, description="Busca por nombre, apellido o email"),
    tipo: str | None = Query(default=None, pattern="^(CLIENTE|STAFF)$"),
    activo: bool | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver_usuarios),
) -> list[UsuarioAdminOut]:
    filas = await conn.fetch(
        SELECT_USUARIO
        + "WHERE "
        + FILTRO_EMPRESA
        + """
          AND ($2::text IS NULL OR u.nombre ILIKE '%' || $2 || '%'
                                OR u.apellido ILIKE '%' || $2 || '%'
                                OR u.email ILIKE '%' || $2 || '%')
          AND ($3::text IS NULL OR u.tipo::text = $3)
          AND ($4::boolean IS NULL OR u.activo = $4)
        ORDER BY u.tipo, u.activo DESC, u.apellido, u.nombre
        """,
        empresa_de(staff),
        q,
        tipo,
        activo,
    )
    return [_a_usuario(fila) for fila in filas]


@router.get("/usuarios/{usuario_id}", response_model=UsuarioAdminOut)
async def obtener_usuario(
    usuario_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver_usuarios),
) -> UsuarioAdminOut:
    return await _obtener_usuario(conn, usuario_id, empresa_de(staff))


@router.post("/usuarios", response_model=UsuarioAdminOut, status_code=status.HTTP_201_CREATED)
async def crear_staff(
    body: StaffIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_crear_usuarios),
) -> UsuarioAdminOut:
    """Alta de personal. Crea el usuario STAFF y su fila en empleado en la misma transaccion:
    un STAFF sin sucursal no podria operar caja ni atender reservas."""
    empresa_id = empresa_de(staff)
    _validar_cargo(body.cargo)
    await _validar_rol_staff(conn, body.rol_id, empresa_id)
    await _validar_sucursal_activa(conn, body.sucursal_id, empresa_id)

    # SaaS: el plan de la empresa limita cuanto personal puede tener
    await exigir_limite(conn, empresa_id, "empleados")
    try:
        async with conn.transaction():
            nuevo_id = await conn.fetchval(
                """
                INSERT INTO usuario (email, password_hash, nombre, apellido, telefono,
                                     tipo, rol_id, empresa_id, email_verificado)
                VALUES ($1, $2, $3, $4, $5, 'STAFF', $6, $7, TRUE)
                RETURNING id
                """,
                body.email,
                hash_password(body.password),
                body.nombre,
                body.apellido,
                body.telefono,
                body.rol_id,
                empresa_id,
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

    return await _obtener_usuario(conn, nuevo_id, empresa_id)


@router.put("/usuarios/{usuario_id}", response_model=UsuarioAdminOut)
async def actualizar_staff(
    usuario_id: UUID,
    body: StaffUpdate,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_actualizar_usuarios),
) -> UsuarioAdminOut:
    empresa_id = empresa_de(staff)
    antes = await _obtener_usuario(conn, usuario_id, empresa_id)
    if antes.tipo != "STAFF":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Este usuario es un cliente: usa el endpoint de clientes",
        )

    _validar_cargo(body.cargo)
    await _validar_rol_staff(conn, body.rol_id, empresa_id)
    await _validar_sucursal_activa(conn, body.sucursal_id, empresa_id)

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

    return await _obtener_usuario(conn, usuario_id, empresa_id)


@router.put("/clientes/{usuario_id}", response_model=UsuarioAdminOut)
async def actualizar_cliente(
    usuario_id: UUID,
    body: ClienteUpdate,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_actualizar_usuarios),
) -> UsuarioAdminOut:
    """Antes (una sola cadena) corregia email/nombre/telefono de una clienta. Con varias
    empresas la cuenta es de la plataforma y la comparten todas las tiendas: una empresa no la
    puede editar (cambiar el email seria quedarse con la cuenta). Los datos que la empresa
    lleva de la clienta van en su ficha (PUT /clientes/{id}/perfil)."""
    antes = await _obtener_usuario(conn, usuario_id, empresa_de(staff))
    if antes.tipo != "CLIENTE":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Este usuario es personal, no un cliente"
        )
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="La cuenta de una clienta es de la plataforma: su ficha se edita en Clientes",
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

    empresa_id = empresa_de(staff)
    antes = await _obtener_staff_propio(conn, usuario_id, empresa_id)

    if body.activo and not antes.activo:
        await exigir_limite(conn, empresa_id, "empleados")

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
    return await _obtener_usuario(conn, usuario_id, empresa_id)


@router.post("/usuarios/{usuario_id}/password", status_code=status.HTTP_204_NO_CONTENT)
async def restablecer_password(
    usuario_id: UUID,
    body: PasswordIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_actualizar_usuarios),
) -> None:
    await _obtener_staff_propio(conn, usuario_id, empresa_de(staff))
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

# $1 = empresa: cuenta solo SUS usuarios del rol (un rol del sistema lo usan todas)
SELECT_ROL = """
SELECT r.id, r.nombre, r.descripcion, r.es_sistema,
       (SELECT COUNT(*) FROM usuario u WHERE u.rol_id = r.id AND u.empresa_id = $1) AS usuarios,
       COALESCE(
           (SELECT array_agg(rp.permiso_id ORDER BY rp.permiso_id)
              FROM rol_permiso rp WHERE rp.rol_id = r.id),
           ARRAY[]::int[]
       ) AS permisos
FROM rol r
WHERE (r.empresa_id = $1 OR (r.empresa_id IS NULL AND r.nombre <> 'SUPERADMIN'))
"""


async def _obtener_rol(conn: asyncpg.Connection, rol_id: int, empresa_id: UUID) -> RolOut:
    fila = await conn.fetchrow(SELECT_ROL + "AND r.id = $2", empresa_id, rol_id)
    if fila is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Rol no encontrado")
    return RolOut(**dict(fila))


def _solo_rol_propio(rol: RolOut) -> None:
    if rol.es_sistema:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "Los roles del sistema los comparten todas las empresas y no se modifican: "
                "crea un rol propio con los permisos que necesites"
            ),
        )


@router.get("/permisos", response_model=list[PermisoOut])
async def listar_permisos(
    conn: asyncpg.Connection = Depends(get_connection),
    _staff: dict = Depends(puede_ver_roles),
) -> list[PermisoOut]:
    filas = await conn.fetch(
        """
        SELECT id, codigo, modulo, descripcion FROM permiso
         WHERE modulo <> ALL($1::text[])
         ORDER BY modulo, codigo
        """,
        list(MODULOS_PLATAFORMA),
    )
    return [PermisoOut(**dict(fila)) for fila in filas]


@router.get("/roles", response_model=list[RolOut])
async def listar_roles(
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver_roles),
) -> list[RolOut]:
    filas = await conn.fetch(SELECT_ROL + "ORDER BY r.es_sistema DESC, r.nombre", empresa_de(staff))
    return [RolOut(**dict(fila)) for fila in filas]


@router.post("/roles", response_model=RolOut, status_code=status.HTTP_201_CREATED)
async def crear_rol(
    body: RolIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_crear_roles),
) -> RolOut:
    empresa_id = empresa_de(staff)
    nombre = body.nombre.upper()
    # tampoco puede llamarse como uno del sistema (seria confuso en el selector de roles)
    if await conn.fetchval("SELECT 1 FROM rol WHERE empresa_id IS NULL AND nombre = $1", nombre):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Ya existe un rol con ese nombre")
    try:
        async with conn.transaction():
            nuevo_id = await conn.fetchval(
                """
                INSERT INTO rol (empresa_id, nombre, descripcion, es_sistema)
                VALUES ($1, $2, $3, FALSE) RETURNING id
                """,
                empresa_id,
                nombre,
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
    return await _obtener_rol(conn, nuevo_id, empresa_id)


@router.put("/roles/{rol_id}", response_model=RolOut)
async def actualizar_rol(
    rol_id: int,
    body: RolIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_actualizar_roles),
) -> RolOut:
    empresa_id = empresa_de(staff)
    antes = await _obtener_rol(conn, rol_id, empresa_id)
    _solo_rol_propio(antes)

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
    return await _obtener_rol(conn, rol_id, empresa_id)


@router.put("/roles/{rol_id}/permisos", response_model=RolOut)
async def asignar_permisos(
    rol_id: int,
    body: PermisosIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_actualizar_roles),
) -> RolOut:
    """Reemplaza la matriz de permisos de un rol PROPIO de la empresa. Los del sistema (ADMIN
    incluido) no se tocan, asi que nunca se puede dejar a una empresa sin la llave de
    usuarios/roles. Un permiso de la plataforma no se puede asignar."""
    empresa_id = empresa_de(staff)
    antes = await _obtener_rol(conn, rol_id, empresa_id)
    _solo_rol_propio(antes)

    if body.permisos:
        ajenos = await conn.fetchval(
            "SELECT COUNT(*) FROM permiso WHERE id = ANY($1::int[]) AND modulo = ANY($2::text[])",
            list(set(body.permisos)),
            list(MODULOS_PLATAFORMA),
        )
        if ajenos:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Los permisos de la plataforma no se asignan a roles de una empresa",
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
    return await _obtener_rol(conn, rol_id, empresa_id)


@router.delete("/roles/{rol_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar_rol(
    rol_id: int,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_eliminar_roles),
) -> None:
    rol = await _obtener_rol(conn, rol_id, empresa_de(staff))
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
