"""Gobierno de la plataforma: la plataforma (SUPERADMIN) controla las cuentas, los roles y los
permisos de todas las empresas, como el panel de un SaaS multi-tenant.

- Cuentas: lista de todas (personal de cualquier empresa, clientas y equipo de la plataforma)
  con filtro por empresa, edicion de datos y de rol, baja/reactivacion, contrasena nueva y
  desbloqueo. No hay forma de leer una contrasena. Alta de otro integrante del equipo.
- Roles y permisos: la matriz de TODOS los roles. Los roles del sistema (ADMIN, ENCARGADO,
  CAJERO...) los comparten todas las empresas, asi que un cambio aca se siente en todas; los
  que una empresa creo tambien se pueden ajustar. Crea roles del sistema (plantillas para
  todas) o propios de una empresa.

Cada accion queda en la bitacora (CU19), con la empresa afectada cuando es de una sola.
Permisos `empresas.leer` (consultar) y `empresas.actualizar` (modificar): solo SUPERADMIN.
Las salvaguardas evitan dejar la plataforma o una empresa sin llave: nadie se da de baja a si
mismo, SUPERADMIN no cambia sus permisos y ADMIN conserva usuarios, roles y suscripcion.
"""

from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.auditoria import registrar_auditoria
from app.core.db import get_connection
from app.core.deps import requiere_permiso
from app.core.plan import exigir_limite
from app.core.security import hash_password
from app.core.tenant import no_encontrado
from app.modules.acceso_y_organizacion.usuarios.admin_schemas import (
    EstadoIn,
    PasswordIn,
    PermisoOut,
    PermisosIn,
)
from app.modules.plataforma_saas.saas.gobierno_schemas import (
    CuentaOut,
    CuentaUpdate,
    EquipoIn,
    RolPlataformaIn,
    RolPlataformaOut,
    RolPlataformaUpdate,
)

router = APIRouter(prefix="/saas", tags=["saas-gobierno"])

plataforma_ver = requiere_permiso("empresas.leer")
plataforma_editar = requiere_permiso("empresas.actualizar")

# roles que el codigo nombra (agregar_administrador busca 'ADMIN', el login distingue SUPERADMIN...)
ROLES_PROTEGIDOS = {"SUPERADMIN", "ADMIN", "ENCARGADO", "CAJERO"}
# modulos de permiso que son solo de la plataforma: no se asignan a ningun otro rol
MODULOS_PLATAFORMA = ("empresas", "planes")
# lo minimo que conserva el ADMIN de toda empresa para no quedarse sin la llave de su cuenta
PERMISOS_MINIMOS_ADMIN = (
    "usuarios.leer",
    "usuarios.crear",
    "usuarios.actualizar",
    "roles.leer",
    "roles.crear",
    "roles.actualizar",
    "suscripciones.leer",
    "suscripciones.actualizar",
)

SELECT_CUENTA = """
SELECT u.id, u.email, u.nombre, u.apellido, u.telefono, u.tipo::text AS tipo, u.rol_id,
       r.nombre AS rol, u.empresa_id, em.nombre AS empresa, u.activo,
       (u.bloqueado_hasta IS NOT NULL AND u.bloqueado_hasta > now()) AS bloqueado,
       u.ultimo_acceso, u.creado_en
FROM usuario u
LEFT JOIN rol r      ON r.id = u.rol_id
LEFT JOIN empresa em ON em.id = u.empresa_id
"""

SELECT_ROL = """
SELECT r.id, r.nombre, r.descripcion, r.es_sistema, r.empresa_id, em.nombre AS empresa,
       (SELECT COUNT(*) FROM usuario u WHERE u.rol_id = r.id) AS usuarios,
       COALESCE(
           (SELECT array_agg(rp.permiso_id ORDER BY rp.permiso_id)
              FROM rol_permiso rp WHERE rp.rol_id = r.id),
           ARRAY[]::int[]
       ) AS permisos
FROM rol r
LEFT JOIN empresa em ON em.id = r.empresa_id
"""


def _cuenta(fila: asyncpg.Record) -> CuentaOut:
    return CuentaOut(**dict(fila))


async def _obtener_cuenta(conn: asyncpg.Connection, usuario_id: UUID) -> CuentaOut:
    fila = await conn.fetchrow(SELECT_CUENTA + "WHERE u.id = $1", usuario_id)
    if fila is None:
        raise no_encontrado("Cuenta no encontrada")
    return _cuenta(fila)


def _rol(fila: asyncpg.Record) -> RolPlataformaOut:
    datos = dict(fila)
    protegido = datos["empresa_id"] is None and datos["nombre"] in ROLES_PROTEGIDOS
    return RolPlataformaOut(**datos, protegido=protegido)


async def _obtener_rol(conn: asyncpg.Connection, rol_id: int) -> RolPlataformaOut:
    fila = await conn.fetchrow(SELECT_ROL + "WHERE r.id = $1", rol_id)
    if fila is None:
        raise no_encontrado("Rol no encontrado")
    return _rol(fila)


async def _exigir_empresa(conn: asyncpg.Connection, empresa_id: UUID) -> None:
    if not await conn.fetchval("SELECT 1 FROM empresa WHERE id = $1", empresa_id):
        raise no_encontrado("Empresa no encontrada")


def _conflicto(detalle: str) -> HTTPException:
    return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=detalle)


# ---------------------------------------------------------------------
#  CUENTAS
# ---------------------------------------------------------------------


@router.get("/cuentas", response_model=list[CuentaOut])
async def listar_cuentas(
    q: str | None = Query(default=None, description="Busca por nombre, apellido o correo"),
    tipo: str | None = Query(default=None, pattern="^(CLIENTE|STAFF)$"),
    empresa_id: UUID | None = Query(default=None),
    activo: bool | None = Query(default=None),
    limite: int = Query(default=200, ge=1, le=500),
    conn: asyncpg.Connection = Depends(get_connection),
    _staff: dict = Depends(plataforma_ver),
) -> list[CuentaOut]:
    filas = await conn.fetch(
        SELECT_CUENTA
        + """
        WHERE ($1::text IS NULL OR u.nombre ILIKE '%' || $1 || '%'
                                OR u.apellido ILIKE '%' || $1 || '%'
                                OR u.email ILIKE '%' || $1 || '%')
          AND ($2::text IS NULL OR u.tipo::text = $2)
          AND ($3::uuid IS NULL OR u.empresa_id = $3)
          AND ($4::boolean IS NULL OR u.activo = $4)
        ORDER BY u.tipo DESC, (u.empresa_id IS NULL) DESC, em.nombre, u.activo DESC,
                 u.apellido, u.nombre
        LIMIT $5
        """,
        q,
        tipo,
        empresa_id,
        activo,
        limite,
    )
    return [_cuenta(f) for f in filas]


@router.post("/equipo", response_model=CuentaOut, status_code=status.HTTP_201_CREATED)
async def agregar_al_equipo(
    body: EquipoIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(plataforma_editar),
) -> CuentaOut:
    """Otro integrante del equipo de la plataforma: SUPERADMIN, sin empresa."""
    try:
        async with conn.transaction():
            nuevo_id = await conn.fetchval(
                """
                INSERT INTO usuario (email, password_hash, nombre, apellido, tipo, rol_id,
                                     empresa_id, email_verificado)
                VALUES ($1, $2, $3, $4, 'STAFF',
                        (SELECT id FROM rol WHERE nombre = 'SUPERADMIN' AND empresa_id IS NULL),
                        NULL, TRUE)
                RETURNING id
                """,
                body.email,
                hash_password(body.password),
                body.nombre,
                body.apellido,
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="usuario",
                entidad_id=nuevo_id,
                accion="CREAR",
                datos_despues={"email": body.email, "rol": "SUPERADMIN"},
            )
    except asyncpg.UniqueViolationError:
        raise _conflicto("Ese email ya esta registrado en la plataforma")
    return await _obtener_cuenta(conn, nuevo_id)


@router.put("/cuentas/{usuario_id}", response_model=CuentaOut)
async def actualizar_cuenta(
    usuario_id: UUID,
    body: CuentaUpdate,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(plataforma_editar),
) -> CuentaOut:
    antes = await _obtener_cuenta(conn, usuario_id)

    nuevo_rol = body.rol_id if body.rol_id is not None else antes.rol_id
    if nuevo_rol != antes.rol_id:
        if antes.tipo != "STAFF" or antes.empresa_id is None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Solo el personal de una empresa cambia de rol",
            )
        # un rol del sistema (no SUPERADMIN: es de la plataforma) o uno propio de SU empresa
        valido = await conn.fetchval(
            """
            SELECT 1 FROM rol
             WHERE id = $1
               AND (empresa_id = $2 OR (empresa_id IS NULL AND nombre <> 'SUPERADMIN'))
            """,
            nuevo_rol,
            antes.empresa_id,
        )
        if not valido:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="El rol no existe o no corresponde a esa empresa",
            )

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
                nuevo_rol,
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="usuario",
                entidad_id=usuario_id,
                accion="ACTUALIZAR",
                datos_antes=antes.model_dump(mode="json"),
                datos_despues={**body.model_dump(mode="json"), "rol_id": nuevo_rol},
                empresa_id=antes.empresa_id,
            )
    except asyncpg.UniqueViolationError:
        raise _conflicto("Ese email ya esta registrado en la plataforma")
    return await _obtener_cuenta(conn, usuario_id)


@router.patch("/cuentas/{usuario_id}/estado", response_model=CuentaOut)
async def cambiar_estado_cuenta(
    usuario_id: UUID,
    body: EstadoIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(plataforma_editar),
) -> CuentaOut:
    """Baja logica o reactivacion de cualquier cuenta. Nunca se borra: ventas, reservas y kardex
    la referencian; el login rechaza a quien esta de baja."""
    if usuario_id == staff["id"] and not body.activo:
        raise _conflicto("No podes dar de baja tu propia cuenta")
    antes = await _obtener_cuenta(conn, usuario_id)

    if not body.activo and antes.activo and antes.tipo == "STAFF":
        if await conn.fetchval(
            "SELECT 1 FROM sesion_caja WHERE empleado_id = $1 AND estado = 'ABIERTA'", usuario_id
        ):
            raise _conflicto("No se puede dar de baja: tiene una sesion de caja abierta")
    if body.activo and not antes.activo and antes.tipo == "STAFF" and antes.empresa_id is not None:
        await exigir_limite(conn, antes.empresa_id, "empleados")

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
            empresa_id=antes.empresa_id,
        )
    return await _obtener_cuenta(conn, usuario_id)


@router.post("/cuentas/{usuario_id}/password", status_code=status.HTTP_204_NO_CONTENT)
async def restablecer_password_cuenta(
    usuario_id: UUID,
    body: PasswordIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(plataforma_editar),
) -> None:
    """Contrasena nueva para cualquier cuenta; ademas la desbloquea, porque quien la olvido casi
    seguro agoto los intentos."""
    antes = await _obtener_cuenta(conn, usuario_id)
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
            empresa_id=antes.empresa_id,
        )


@router.post("/cuentas/{usuario_id}/desbloquear", response_model=CuentaOut)
async def desbloquear_cuenta(
    usuario_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(plataforma_editar),
) -> CuentaOut:
    antes = await _obtener_cuenta(conn, usuario_id)
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
            empresa_id=antes.empresa_id,
        )
    return await _obtener_cuenta(conn, usuario_id)


# ---------------------------------------------------------------------
#  ROLES Y PERMISOS
# ---------------------------------------------------------------------


@router.get("/permisos", response_model=list[PermisoOut])
async def listar_permisos(
    conn: asyncpg.Connection = Depends(get_connection),
    _staff: dict = Depends(plataforma_ver),
) -> list[PermisoOut]:
    """El catalogo completo, tambien los de la plataforma (solo SUPERADMIN los tiene)."""
    filas = await conn.fetch("SELECT id, codigo, modulo, descripcion FROM permiso ORDER BY modulo, codigo")
    return [PermisoOut(**dict(f)) for f in filas]


@router.get("/roles", response_model=list[RolPlataformaOut])
async def listar_roles(
    empresa_id: UUID | None = Query(default=None, description="Los del sistema y los de esta empresa"),
    conn: asyncpg.Connection = Depends(get_connection),
    _staff: dict = Depends(plataforma_ver),
) -> list[RolPlataformaOut]:
    filas = await conn.fetch(
        SELECT_ROL
        + """
        WHERE ($1::uuid IS NULL OR r.empresa_id IS NULL OR r.empresa_id = $1)
        ORDER BY (r.empresa_id IS NOT NULL), em.nombre, (r.nombre <> 'SUPERADMIN'), r.nombre
        """,
        empresa_id,
    )
    return [_rol(f) for f in filas]


@router.post("/roles", response_model=RolPlataformaOut, status_code=status.HTTP_201_CREATED)
async def crear_rol(
    body: RolPlataformaIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(plataforma_editar),
) -> RolPlataformaOut:
    nombre = body.nombre.upper()
    if body.empresa_id is not None:
        await _exigir_empresa(conn, body.empresa_id)
        # tampoco puede llamarse como uno del sistema (confundiria el selector de roles)
        if await conn.fetchval("SELECT 1 FROM rol WHERE empresa_id IS NULL AND nombre = $1", nombre):
            raise _conflicto("Ya existe un rol del sistema con ese nombre")
    elif await conn.fetchval("SELECT 1 FROM rol WHERE nombre = $1", nombre):
        # un rol del sistema nuevo lo ven todas las empresas: no puede chocar con ningun otro
        raise _conflicto("Ya existe un rol con ese nombre")
    try:
        async with conn.transaction():
            nuevo_id = await conn.fetchval(
                """
                INSERT INTO rol (empresa_id, nombre, descripcion, es_sistema)
                VALUES ($1, $2, $3, $4) RETURNING id
                """,
                body.empresa_id,
                nombre,
                body.descripcion,
                body.empresa_id is None,
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="rol",
                entidad_id=nuevo_id,
                accion="CREAR",
                datos_despues={**body.model_dump(mode="json"), "nombre": nombre},
                empresa_id=body.empresa_id,
            )
    except asyncpg.UniqueViolationError:
        raise _conflicto("Ya existe un rol con ese nombre")
    return await _obtener_rol(conn, nuevo_id)


@router.put("/roles/{rol_id}", response_model=RolPlataformaOut)
async def actualizar_rol(
    rol_id: int,
    body: RolPlataformaUpdate,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(plataforma_editar),
) -> RolPlataformaOut:
    antes = await _obtener_rol(conn, rol_id)
    nombre = body.nombre.upper()
    if antes.protegido and nombre != antes.nombre:
        raise _conflicto(f"El rol {antes.nombre} lo nombra el codigo y no se renombra")
    try:
        async with conn.transaction():
            await conn.execute(
                "UPDATE rol SET nombre = $2, descripcion = $3 WHERE id = $1",
                rol_id,
                nombre,
                body.descripcion,
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="rol",
                entidad_id=rol_id,
                accion="ACTUALIZAR",
                datos_antes={"nombre": antes.nombre, "descripcion": antes.descripcion},
                datos_despues={"nombre": nombre, "descripcion": body.descripcion},
                empresa_id=antes.empresa_id,
            )
    except asyncpg.UniqueViolationError:
        raise _conflicto("Ya existe un rol con ese nombre")
    return await _obtener_rol(conn, rol_id)


@router.put("/roles/{rol_id}/permisos", response_model=RolPlataformaOut)
async def asignar_permisos(
    rol_id: int,
    body: PermisosIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(plataforma_editar),
) -> RolPlataformaOut:
    """Reemplaza la matriz de permisos del rol. Si es del sistema, el cambio llega a todas las
    empresas que lo usan (a quien lo tenga puesto, desde su proximo pedido)."""
    antes = await _obtener_rol(conn, rol_id)
    if antes.empresa_id is None and antes.nombre == "SUPERADMIN":
        raise _conflicto("SUPERADMIN no cambia sus permisos: es la llave de la plataforma")

    pedidos = list(set(body.permisos))
    if pedidos:
        filas = await conn.fetch(
            "SELECT id, codigo, modulo FROM permiso WHERE id = ANY($1::int[])", pedidos
        )
        if len(filas) != len(pedidos):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Alguno de los permisos no existe"
            )
        if any(f["modulo"] in MODULOS_PLATAFORMA for f in filas):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Los permisos de la plataforma (empresas, planes) no se asignan a otros roles",
            )
        codigos = {f["codigo"] for f in filas}
    else:
        codigos = set()

    if antes.empresa_id is None and antes.nombre == "ADMIN":
        faltan = [c for c in PERMISOS_MINIMOS_ADMIN if c not in codigos]
        if faltan:
            raise _conflicto(
                "El ADMIN de cada empresa conserva usuarios, roles y suscripcion; falta: "
                + ", ".join(faltan)
            )

    async with conn.transaction():
        await conn.execute("DELETE FROM rol_permiso WHERE rol_id = $1", rol_id)
        if pedidos:
            await conn.executemany(
                "INSERT INTO rol_permiso (rol_id, permiso_id) VALUES ($1, $2)",
                [(rol_id, permiso_id) for permiso_id in pedidos],
            )
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="rol_permiso",
            entidad_id=rol_id,
            accion="ACTUALIZAR",
            datos_antes={"rol": antes.nombre, "permisos": antes.permisos},
            datos_despues={"rol": antes.nombre, "permisos": sorted(pedidos)},
            empresa_id=antes.empresa_id,
        )
    return await _obtener_rol(conn, rol_id)


@router.delete("/roles/{rol_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar_rol(
    rol_id: int,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(plataforma_editar),
) -> None:
    rol = await _obtener_rol(conn, rol_id)
    if rol.protegido:
        raise _conflicto(f"El rol {rol.nombre} lo nombra el codigo y no se elimina")
    if rol.usuarios:
        raise _conflicto(f"El rol tiene {rol.usuarios} usuario(s) asignado(s)")
    async with conn.transaction():
        await conn.execute("DELETE FROM rol WHERE id = $1", rol_id)
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="rol",
            entidad_id=rol_id,
            accion="ELIMINAR",
            datos_antes={"nombre": rol.nombre, "descripcion": rol.descripcion},
            empresa_id=rol.empresa_id,
        )
