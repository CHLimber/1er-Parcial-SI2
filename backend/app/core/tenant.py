"""Aislamiento multi-tenant (segundo parcial, Modulo A).

Tenant = EMPRESA. La regla de la consigna es doble: el backend valida que el usuario tenga el
PERMISO (requiere_permiso, CU13 del primer parcial) y ademas que el RECURSO pertenezca a su
empresa. Lo segundo vive aca, en funciones chicas que los routers llaman antes de leer o escribir:

  - empresa_de(staff): la empresa del personal; la cuenta de la plataforma (SUPERADMIN, sin
    empresa) no opera tiendas y recibe 403.
  - exigir_sucursal(conn, sucursal_id, empresa_id): 404 si la sucursal es de otra empresa. Se
    responde 404 y no 403 a proposito: a quien no es de la empresa no se le confirma ni que
    el recurso existe.
  - exigir_variantes / exigir_fila: lo mismo para prendas y para cualquier tabla con
    empresa_id (o colgada de una sucursal).
  - empresa_publica: la tienda publica (catalogo, sucursales para reservar, asistente) es de
    una empresa por request, elegida con el header X-Empresa o ?empresa=slug.

Defensa en profundidad: aunque un router se olvide de recortar, fn_mover_inventario
(db/02_logica.sql) rechaza cualquier movimiento de stock de una prenda de otra empresa.
"""

from uuid import UUID

import asyncpg
from fastapi import Depends, Header, HTTPException, Query, status

from app.core.config import settings
from app.core.db import get_connection


def es_plataforma(staff: dict) -> bool:
    """El administrador del SaaS: sin empresa y con el modulo `empresas`."""
    return staff.get("empresa_id") is None and "empresas.leer" in staff["permisos"]


def es_admin_empresa(staff: dict) -> bool:
    """Ve todas las sucursales de SU empresa (mismo criterio que antes tenia el ADMIN de la
    cadena: el que puede editar sucursales). El resto ve solo la suya."""
    return staff.get("empresa_id") is not None and "sucursales.actualizar" in staff["permisos"]


def empresa_de(staff: dict) -> UUID:
    if staff.get("empresa_id") is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Esta operacion es de una empresa: la cuenta de la plataforma no opera tiendas",
        )
    return staff["empresa_id"]


def no_encontrado(detalle: str = "No encontrado") -> HTTPException:
    return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=detalle)


async def exigir_sucursal(
    conn: asyncpg.Connection, sucursal_id: UUID | None, empresa_id: UUID, *, activa: bool = False
) -> None:
    """404 si la sucursal no existe o es de otra empresa."""
    if sucursal_id is None:
        return
    fila = await conn.fetchrow(
        "SELECT activa FROM sucursal WHERE id = $1 AND empresa_id = $2", sucursal_id, empresa_id
    )
    if fila is None:
        raise no_encontrado("Sucursal no encontrada")
    if activa and not fila["activa"]:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="La sucursal esta dada de baja"
        )


def alcance_sucursal(staff: dict, pedida: UUID | None) -> UUID | None:
    """Que sucursal mira una consulta de gestion: el admin de la empresa la que pida (o todas
    las de su empresa con None); el resto siempre la propia. La pertenencia de `pedida` a la
    empresa la valida exigir_sucursal."""
    if es_admin_empresa(staff):
        return pedida
    if staff.get("sucursal_id") is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tu usuario no esta asignado a ninguna sucursal",
        )
    if pedida is not None and pedida != staff["sucursal_id"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo podes consultar tu sucursal",
        )
    return staff["sucursal_id"]


async def exigir_variantes(
    conn: asyncpg.Connection, variante_ids: list[UUID], empresa_id: UUID
) -> None:
    """404 si alguna prenda no existe o es del catalogo de otra empresa."""
    ids = list({v for v in variante_ids})
    if not ids:
        return
    propias = await conn.fetchval(
        """
        SELECT COUNT(*) FROM producto_variante pv
          JOIN producto p ON p.id = pv.producto_id
         WHERE pv.id = ANY($1::uuid[]) AND p.empresa_id = $2
        """,
        ids,
        empresa_id,
    )
    if propias != len(ids):
        raise no_encontrado("Prenda no encontrada")


# tablas con empresa_id propio (para exigir_fila); los nombres son constantes del codigo,
# nunca vienen del usuario
_TABLAS_CON_EMPRESA = {
    "producto", "categoria", "marca", "temporada", "coleccion", "proveedor", "promocion",
}


async def exigir_fila(
    conn: asyncpg.Connection, tabla: str, fila_id, empresa_id: UUID, detalle: str
) -> None:
    """404 si la fila de `tabla` no existe o es de otra empresa."""
    if fila_id is None:
        return
    if tabla not in _TABLAS_CON_EMPRESA:
        raise ValueError(f"Tabla sin empresa_id: {tabla}")
    existe = await conn.fetchval(
        f"SELECT EXISTS (SELECT 1 FROM {tabla} WHERE id = $1 AND empresa_id = $2)",
        fila_id,
        empresa_id,
    )
    if not existe:
        raise no_encontrado(detalle)


async def empresa_de_variante(conn: asyncpg.Connection, variante_id: UUID) -> UUID | None:
    return await conn.fetchval(
        """
        SELECT p.empresa_id FROM producto_variante pv
          JOIN producto p ON p.id = pv.producto_id
         WHERE pv.id = $1
        """,
        variante_id,
    )


async def empresa_de_sucursal(conn: asyncpg.Connection, sucursal_id: UUID) -> UUID | None:
    return await conn.fetchval("SELECT empresa_id FROM sucursal WHERE id = $1", sucursal_id)


async def empresa_publica(
    x_empresa: str | None = Header(default=None, alias="X-Empresa"),
    empresa: str | None = Query(default=None, max_length=40, description="slug de la tienda"),
    conn: asyncpg.Connection = Depends(get_connection),
) -> UUID:
    """La tienda publica que se esta mirando. ?empresa= gana sobre el header (sirve para
    compartir un link), y sin ninguno se usa settings.empresa_por_defecto."""
    slug = (empresa or x_empresa or settings.empresa_por_defecto).strip().lower()
    empresa_id = await conn.fetchval(
        "SELECT id FROM empresa WHERE slug = $1 AND activa", slug
    )
    if empresa_id is None:
        raise no_encontrado("Esa tienda no existe o no esta activa")
    return empresa_id
