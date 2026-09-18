from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.auditoria import registrar_auditoria
from app.core.db import get_connection
from app.core.deps import requiere_permiso
from app.modules.sucursales.admin_schemas import (
    CajaEstadoIn,
    CajaIn,
    CajaOut,
    EstadoIn,
    SucursalAdminOut,
    SucursalIn,
)

router = APIRouter(prefix="/admin/sucursales", tags=["sucursales-admin"])

puede_ver = requiere_permiso("sucursales.leer", "sucursales.crear", "sucursales.actualizar", "sucursales.eliminar")
puede_crear = requiere_permiso("sucursales.crear")
puede_actualizar = requiere_permiso("sucursales.actualizar")
# baja/reactivacion via PATCH .../estado: cualquiera de las dos alcanza para prender o apagar
puede_cambiar_estado = requiere_permiso("sucursales.actualizar", "sucursales.eliminar")

SELECT_SUCURSAL = """
SELECT s.id, s.codigo, s.nombre, s.ciudad, s.direccion, s.telefono, s.latitud, s.longitud,
       s.hora_apertura, s.hora_cierre, s.cantidad_vestidores, s.activa,
       (SELECT COUNT(*) FROM empleado e WHERE e.sucursal_id = s.id AND e.activo) AS empleados,
       (SELECT COUNT(*) FROM caja c     WHERE c.sucursal_id = s.id AND c.activa) AS cajas
FROM sucursal s
"""


def _validar_horario(body: SucursalIn) -> None:
    if body.hora_apertura and body.hora_cierre and body.hora_cierre <= body.hora_apertura:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="La hora de cierre debe ser posterior a la de apertura",
        )


async def _obtener(conn: asyncpg.Connection, sucursal_id: UUID) -> SucursalAdminOut:
    fila = await conn.fetchrow(SELECT_SUCURSAL + "WHERE s.id = $1", sucursal_id)
    if fila is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sucursal no encontrada")
    return SucursalAdminOut(**dict(fila))


@router.get("/ciudades", response_model=list[str])
async def listar_ciudades(
    conn: asyncpg.Connection = Depends(get_connection),
    _staff: dict = Depends(puede_ver),
) -> list[str]:
    """Los valores validos de ciudad viven en el ENUM ciudad_bo del esquema, no en el codigo
    Python (ver CLAUDE.md): se leen del catalogo de Postgres."""
    filas = await conn.fetch(
        """
        SELECT e.enumlabel AS ciudad
        FROM pg_enum e
        JOIN pg_type t ON t.oid = e.enumtypid
        WHERE t.typname = 'ciudad_bo'
        ORDER BY e.enumsortorder
        """
    )
    return [fila["ciudad"] for fila in filas]


@router.get("", response_model=list[SucursalAdminOut])
async def listar_sucursales_admin(
    activa: bool | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    _staff: dict = Depends(puede_ver),
) -> list[SucursalAdminOut]:
    """CU12 - Gestionar Sucursales. A diferencia de GET /sucursales (publico), este listado
    incluye las sucursales dadas de baja."""
    filas = await conn.fetch(
        SELECT_SUCURSAL
        + "WHERE ($1::boolean IS NULL OR s.activa = $1) ORDER BY s.activa DESC, s.nombre",
        activa,
    )
    return [SucursalAdminOut(**dict(fila)) for fila in filas]


@router.post("", response_model=SucursalAdminOut, status_code=status.HTTP_201_CREATED)
async def crear_sucursal(
    body: SucursalIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_crear),
) -> SucursalAdminOut:
    _validar_horario(body)
    try:
        async with conn.transaction():
            nuevo_id = await conn.fetchval(
                """
                INSERT INTO sucursal (codigo, nombre, ciudad, direccion, telefono, latitud, longitud,
                                      hora_apertura, hora_cierre, cantidad_vestidores)
                VALUES ($1, $2, $3::ciudad_bo, $4, $5, $6, $7, $8, $9, $10)
                RETURNING id
                """,
                body.codigo.upper(),
                body.nombre,
                body.ciudad,
                body.direccion,
                body.telefono,
                body.latitud,
                body.longitud,
                body.hora_apertura,
                body.hora_cierre,
                body.cantidad_vestidores,
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="sucursal",
                entidad_id=nuevo_id,
                accion="CREAR",
                datos_despues=body.model_dump(mode="json"),
            )
    except asyncpg.UniqueViolationError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Ese codigo de sucursal ya existe"
        )
    except asyncpg.InvalidTextRepresentationError:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Ciudad invalida")

    return await _obtener(conn, nuevo_id)


@router.get("/{sucursal_id}", response_model=SucursalAdminOut)
async def obtener_sucursal(
    sucursal_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    _staff: dict = Depends(puede_ver),
) -> SucursalAdminOut:
    return await _obtener(conn, sucursal_id)


@router.put("/{sucursal_id}", response_model=SucursalAdminOut)
async def actualizar_sucursal(
    sucursal_id: UUID,
    body: SucursalIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_actualizar),
) -> SucursalAdminOut:
    _validar_horario(body)
    antes = await _obtener(conn, sucursal_id)

    try:
        async with conn.transaction():
            await conn.execute(
                """
                UPDATE sucursal
                   SET codigo = $2, nombre = $3, ciudad = $4::ciudad_bo, direccion = $5,
                       telefono = $6, latitud = $7, longitud = $8,
                       hora_apertura = $9, hora_cierre = $10, cantidad_vestidores = $11
                 WHERE id = $1
                """,
                sucursal_id,
                body.codigo.upper(),
                body.nombre,
                body.ciudad,
                body.direccion,
                body.telefono,
                body.latitud,
                body.longitud,
                body.hora_apertura,
                body.hora_cierre,
                body.cantidad_vestidores,
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="sucursal",
                entidad_id=sucursal_id,
                accion="ACTUALIZAR",
                datos_antes=antes.model_dump(mode="json"),
                datos_despues=body.model_dump(mode="json"),
            )
    except asyncpg.UniqueViolationError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Ese codigo de sucursal ya existe"
        )
    except asyncpg.InvalidTextRepresentationError:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Ciudad invalida")

    return await _obtener(conn, sucursal_id)


@router.patch("/{sucursal_id}/estado", response_model=SucursalAdminOut)
async def cambiar_estado_sucursal(
    sucursal_id: UUID,
    body: EstadoIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_cambiar_estado),
) -> SucursalAdminOut:
    """Baja logica. Se bloquea si queda una caja abierta o reservas en curso: cerrar la sucursal
    con stock comprometido dejaria el inventario inconsistente."""
    antes = await _obtener(conn, sucursal_id)

    if not body.activa:
        caja_abierta = await conn.fetchval(
            """
            SELECT 1 FROM sesion_caja sc
            JOIN caja c ON c.id = sc.caja_id
            WHERE c.sucursal_id = $1 AND sc.estado = 'ABIERTA'
            """,
            sucursal_id,
        )
        if caja_abierta:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="No se puede desactivar: hay una sesion de caja abierta",
            )

        reservas_activas = await conn.fetchval(
            """
            SELECT COUNT(*) FROM reserva
            WHERE sucursal_id = $1
              AND estado IN ('PENDIENTE','CONFIRMADA','PREPARADA','CLIENTE_PRESENTE')
            """,
            sucursal_id,
        )
        if reservas_activas:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"No se puede desactivar: hay {reservas_activas} reserva(s) en curso",
            )

    async with conn.transaction():
        await conn.execute("UPDATE sucursal SET activa = $2 WHERE id = $1", sucursal_id, body.activa)
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="sucursal",
            entidad_id=sucursal_id,
            accion="ACTUALIZAR" if body.activa else "ELIMINAR",
            datos_antes={"activa": antes.activa},
            datos_despues={"activa": body.activa},
        )
    return await _obtener(conn, sucursal_id)


# ---------------------------------------------------------------------
#  CAJAS DE LA SUCURSAL
# ---------------------------------------------------------------------

SELECT_CAJA = """
SELECT c.id, c.sucursal_id, c.codigo, c.nombre, c.activa,
       EXISTS (
           SELECT 1 FROM sesion_caja sc WHERE sc.caja_id = c.id AND sc.estado = 'ABIERTA'
       ) AS sesion_abierta
FROM caja c
"""


async def _obtener_caja(conn: asyncpg.Connection, caja_id: UUID) -> CajaOut:
    fila = await conn.fetchrow(SELECT_CAJA + "WHERE c.id = $1", caja_id)
    if fila is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Caja no encontrada")
    return CajaOut(**dict(fila))


@router.patch("/cajas/{caja_id}/estado", response_model=CajaOut)
async def cambiar_estado_caja(
    caja_id: UUID,
    body: CajaEstadoIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_cambiar_estado),
) -> CajaOut:
    caja = await _obtener_caja(conn, caja_id)
    if not body.activa and caja.sesion_abierta:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="No se puede desactivar una caja con la sesion abierta",
        )

    async with conn.transaction():
        await conn.execute("UPDATE caja SET activa = $2 WHERE id = $1", caja_id, body.activa)
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="caja",
            entidad_id=caja_id,
            accion="ACTUALIZAR" if body.activa else "ELIMINAR",
            datos_antes={"activa": caja.activa},
            datos_despues={"activa": body.activa},
        )
    return await _obtener_caja(conn, caja_id)


@router.get("/{sucursal_id}/cajas", response_model=list[CajaOut])
async def listar_cajas(
    sucursal_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    _staff: dict = Depends(puede_ver),
) -> list[CajaOut]:
    filas = await conn.fetch(SELECT_CAJA + "WHERE c.sucursal_id = $1 ORDER BY c.codigo", sucursal_id)
    return [CajaOut(**dict(fila)) for fila in filas]


@router.post("/{sucursal_id}/cajas", response_model=CajaOut, status_code=status.HTTP_201_CREATED)
async def crear_caja(
    sucursal_id: UUID,
    body: CajaIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_crear),
) -> CajaOut:
    await _obtener(conn, sucursal_id)
    try:
        async with conn.transaction():
            nueva_id = await conn.fetchval(
                "INSERT INTO caja (sucursal_id, codigo, nombre) VALUES ($1, $2, $3) RETURNING id",
                sucursal_id,
                body.codigo.upper(),
                body.nombre,
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="caja",
                entidad_id=nueva_id,
                accion="CREAR",
                datos_despues={"sucursal_id": str(sucursal_id), **body.model_dump(mode="json")},
            )
    except asyncpg.UniqueViolationError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Esa sucursal ya tiene una caja con ese codigo",
        )
    return await _obtener_caja(conn, nueva_id)
