from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.auditoria import registrar_auditoria
from app.core.db import get_connection
from app.core.deps import requiere_permiso
from app.modules.proveedores.schemas import EstadoIn, ProveedorIn, ProveedorOut

router = APIRouter(prefix="/proveedores", tags=["proveedores"])

SELECT_PROVEEDOR = """
SELECT pr.id, pr.nombre, pr.nit, pr.contacto, pr.email, pr.telefono, pr.activo,
       (SELECT COUNT(*) FROM producto  p WHERE p.proveedor_id  = pr.id) AS productos,
       (SELECT COUNT(*) FROM recepcion r WHERE r.proveedor_id = pr.id) AS recepciones
FROM proveedor pr
"""


async def _obtener(conn: asyncpg.Connection, proveedor_id: UUID) -> ProveedorOut:
    fila = await conn.fetchrow(SELECT_PROVEEDOR + "WHERE pr.id = $1", proveedor_id)
    if fila is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Proveedor no encontrado")
    return ProveedorOut(**dict(fila))


@router.get("", response_model=list[ProveedorOut])
async def listar_proveedores(
    q: str | None = Query(default=None, description="Busca por nombre, NIT o contacto"),
    activo: bool | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    _staff: dict = Depends(requiere_permiso("proveedores.ver", "proveedores.gestionar")),
) -> list[ProveedorOut]:
    """CU11 - Gestionar Proveedores: listado con busqueda."""
    filas = await conn.fetch(
        SELECT_PROVEEDOR
        + """
        WHERE ($1::text IS NULL OR pr.nombre ILIKE '%' || $1 || '%'
                                OR pr.nit ILIKE '%' || $1 || '%'
                                OR pr.contacto ILIKE '%' || $1 || '%')
          AND ($2::boolean IS NULL OR pr.activo = $2)
        ORDER BY pr.activo DESC, pr.nombre
        """,
        q,
        activo,
    )
    return [ProveedorOut(**dict(fila)) for fila in filas]


@router.get("/{proveedor_id}", response_model=ProveedorOut)
async def obtener_proveedor(
    proveedor_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    _staff: dict = Depends(requiere_permiso("proveedores.ver", "proveedores.gestionar")),
) -> ProveedorOut:
    return await _obtener(conn, proveedor_id)


@router.post("", response_model=ProveedorOut, status_code=status.HTTP_201_CREATED)
async def crear_proveedor(
    body: ProveedorIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(requiere_permiso("proveedores.gestionar")),
) -> ProveedorOut:
    duplicado = await conn.fetchval(
        "SELECT 1 FROM proveedor WHERE lower(nombre) = lower($1)", body.nombre
    )
    if duplicado:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Ya existe un proveedor con ese nombre"
        )

    async with conn.transaction():
        nuevo_id = await conn.fetchval(
            """
            INSERT INTO proveedor (nombre, nit, contacto, email, telefono)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING id
            """,
            body.nombre,
            body.nit,
            body.contacto,
            body.email,
            body.telefono,
        )
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="proveedor",
            entidad_id=nuevo_id,
            accion="CREAR",
            datos_despues=body.model_dump(mode="json"),
        )
    return await _obtener(conn, nuevo_id)


@router.put("/{proveedor_id}", response_model=ProveedorOut)
async def actualizar_proveedor(
    proveedor_id: UUID,
    body: ProveedorIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(requiere_permiso("proveedores.gestionar")),
) -> ProveedorOut:
    antes = await _obtener(conn, proveedor_id)

    duplicado = await conn.fetchval(
        "SELECT 1 FROM proveedor WHERE lower(nombre) = lower($1) AND id <> $2",
        body.nombre,
        proveedor_id,
    )
    if duplicado:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Ya existe otro proveedor con ese nombre"
        )

    async with conn.transaction():
        await conn.execute(
            """
            UPDATE proveedor
               SET nombre = $2, nit = $3, contacto = $4, email = $5, telefono = $6
             WHERE id = $1
            """,
            proveedor_id,
            body.nombre,
            body.nit,
            body.contacto,
            body.email,
            body.telefono,
        )
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="proveedor",
            entidad_id=proveedor_id,
            accion="ACTUALIZAR",
            datos_antes=antes.model_dump(mode="json"),
            datos_despues=body.model_dump(mode="json"),
        )
    return await _obtener(conn, proveedor_id)


@router.patch("/{proveedor_id}/estado", response_model=ProveedorOut)
async def cambiar_estado_proveedor(
    proveedor_id: UUID,
    body: EstadoIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(requiere_permiso("proveedores.gestionar")),
) -> ProveedorOut:
    """Baja logica: el proveedor queda referenciado por productos y recepciones historicas,
    asi que nunca se borra fisicamente."""
    antes = await _obtener(conn, proveedor_id)

    async with conn.transaction():
        await conn.execute("UPDATE proveedor SET activo = $2 WHERE id = $1", proveedor_id, body.activo)
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="proveedor",
            entidad_id=proveedor_id,
            accion="ACTUALIZAR" if body.activo else "ELIMINAR",
            datos_antes={"activo": antes.activo},
            datos_despues={"activo": body.activo},
        )
    return await _obtener(conn, proveedor_id)
