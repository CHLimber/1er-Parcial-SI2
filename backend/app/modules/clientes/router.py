"""Cartera y perfil de clientas por tenant (Segundo parcial, PENDIENTES 5.7).

"Cada administracion podra hacer el perfil de sus clientes": la cartera de una sucursal son las
clientas que compraron o reservaron ahi, mas las que su administracion dio de alta a mano (por
email de una cuenta CLIENTE existente). Sobre cada una, la sucursal arma su propia ficha en
`cliente_perfil_tenant` (segmento, talla habitual, estilo, telefono de contacto, notas): la ficha
de Equipetrol no la ve Cochabamba. Es distinta de `perfil_cliente`, que es lo que declara la
propia clienta.

El segmento se sugiere del historial en ESA sucursal (segmento_sugerido) y la administracion lo
puede fijar a mano; si no lo fija, vale el sugerido.

Permisos clientes.leer / clientes.actualizar (ENCARGADO; VENDEDOR solo lee) y el plan del
tenant tiene que incluir perfiles_clientes (Profesional o Premium). El ADMIN de la plataforma
opera sobre cualquier sucursal pasando ?sucursal_id.
"""

from datetime import datetime, timedelta, timezone
from decimal import Decimal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.auditoria import registrar_auditoria
from app.core.db import get_connection
from app.core.plan import es_admin_plataforma, requiere_funcion_plan
from app.modules.clientes.schemas import AltaClienteIn, ClienteTenantOut, PerfilClienteIn

router = APIRouter(prefix="/clientes", tags=["clientes"])

puede_ver = requiere_funcion_plan("perfiles_clientes", "clientes.leer", "clientes.actualizar")
puede_editar = requiere_funcion_plan("perfiles_clientes", "clientes.actualizar")

UMBRAL_VIP = Decimal("2000")  # Bs comprados en la sucursal
COMPRAS_FRECUENTE = 3
DIAS_INACTIVA = 90


def segmento_sugerido(
    compras: int, total: Decimal, ultima_compra: datetime | None, ahora: datetime | None = None
) -> str:
    ahora = ahora or datetime.now(timezone.utc)
    if compras == 0 or ultima_compra is None:
        return "NUEVA"
    if ahora - ultima_compra > timedelta(days=DIAS_INACTIVA):
        return "INACTIVA"
    if total >= UMBRAL_VIP:
        return "VIP"
    if compras >= COMPRAS_FRECUENTE:
        return "FRECUENTE"
    return "NUEVA"


# $1 = sucursal. Una fila por clienta de la cartera, con su historial en la sucursal y la ficha.
SELECT_CARTERA = """
WITH compras AS (
    SELECT v.usuario_id, COUNT(*)::int AS compras, COALESCE(SUM(v.total), 0) AS total,
           MAX(v.fecha) AS ultima
    FROM venta v
    WHERE v.sucursal_id = $1 AND v.usuario_id IS NOT NULL AND v.estado IN ('PAGADA','ENTREGADA')
    GROUP BY v.usuario_id
),
reservas AS (
    SELECT r.usuario_id, COUNT(*)::int AS reservas
    FROM reserva r WHERE r.sucursal_id = $1
    GROUP BY r.usuario_id
),
cartera AS (
    SELECT usuario_id FROM compras
    UNION SELECT usuario_id FROM reservas
    UNION SELECT usuario_id FROM cliente_perfil_tenant WHERE sucursal_id = $1
)
SELECT u.id AS usuario_id, (u.nombre || ' ' || u.apellido) AS nombre, u.email, u.telefono,
       COALESCE(c.compras, 0) AS compras, COALESCE(c.total, 0) AS total_comprado,
       c.ultima AS ultima_compra, COALESCE(r.reservas, 0) AS reservas,
       (cp.usuario_id IS NOT NULL) AS tiene_perfil, cp.segmento AS segmento_fijado,
       cp.talla_habitual, cp.estilo_preferido, cp.telefono_contacto,
       COALESCE(cp.acepta_whatsapp, FALSE) AS acepta_whatsapp, cp.notas, cp.actualizado_en,
       (ua.nombre || ' ' || ua.apellido) AS actualizado_por
FROM cartera k
JOIN usuario u ON u.id = k.usuario_id AND u.tipo = 'CLIENTE'
LEFT JOIN compras c  ON c.usuario_id = u.id
LEFT JOIN reservas r ON r.usuario_id = u.id
LEFT JOIN cliente_perfil_tenant cp ON cp.sucursal_id = $1 AND cp.usuario_id = u.id
LEFT JOIN usuario ua ON ua.id = cp.actualizado_por_id
"""


def _armar(fila: asyncpg.Record) -> ClienteTenantOut:
    datos = dict(fila)
    fijado = datos.pop("segmento_fijado")
    sugerido = segmento_sugerido(datos["compras"], datos["total_comprado"], datos["ultima_compra"])
    return ClienteTenantOut(**datos, segmento_sugerido=sugerido, segmento=fijado or sugerido)


def _sucursal(staff: dict, pedida: UUID | None) -> UUID:
    if pedida is not None and es_admin_plataforma(staff):
        return pedida
    if pedida is not None and pedida != staff["sucursal_id"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo podes ver la cartera de clientas de tu sucursal",
        )
    if staff["sucursal_id"] is None:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Indica la sucursal")
    return staff["sucursal_id"]


@router.get("", response_model=list[ClienteTenantOut])
async def listar_cartera(
    sucursal_id: UUID | None = Query(default=None),
    q: str | None = Query(default=None, max_length=80, description="Nombre o email"),
    segmento: str | None = Query(default=None, pattern="^(NUEVA|FRECUENTE|VIP|INACTIVA)$"),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[ClienteTenantOut]:
    sucursal = _sucursal(staff, sucursal_id)
    filas = await conn.fetch(
        SELECT_CARTERA
        + """
        WHERE ($2::text IS NULL OR (u.nombre || ' ' || u.apellido) ILIKE '%' || $2 || '%'
                                OR u.email ILIKE '%' || $2 || '%')
        ORDER BY COALESCE(c.total, 0) DESC, u.nombre
        LIMIT 300
        """,
        sucursal,
        q.strip() if q else None,
    )
    clientes = [_armar(f) for f in filas]
    if segmento:
        clientes = [c for c in clientes if c.segmento == segmento]
    return clientes


async def _uno(conn: asyncpg.Connection, sucursal: UUID, usuario_id: UUID) -> ClienteTenantOut:
    fila = await conn.fetchrow(SELECT_CARTERA + "WHERE u.id = $2", sucursal, usuario_id)
    if fila is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Esa clienta no esta en la cartera de la sucursal",
        )
    return _armar(fila)


@router.get("/{usuario_id}", response_model=ClienteTenantOut)
async def obtener_cliente(
    usuario_id: UUID,
    sucursal_id: UUID | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> ClienteTenantOut:
    return await _uno(conn, _sucursal(staff, sucursal_id), usuario_id)


async def _guardar_perfil(
    conn: asyncpg.Connection, sucursal: UUID, usuario_id: UUID, body: PerfilClienteIn, staff: dict
) -> None:
    antes = await conn.fetchrow(
        "SELECT segmento, talla_habitual, estilo_preferido, notas FROM cliente_perfil_tenant "
        "WHERE sucursal_id = $1 AND usuario_id = $2",
        sucursal,
        usuario_id,
    )
    await conn.execute(
        """
        INSERT INTO cliente_perfil_tenant (sucursal_id, usuario_id, segmento, talla_habitual,
                                           estilo_preferido, telefono_contacto, acepta_whatsapp,
                                           notas, actualizado_por_id)
        VALUES ($1, $2, COALESCE($3, 'NUEVA'), $4, $5, $6, $7, $8, $9)
        ON CONFLICT (sucursal_id, usuario_id) DO UPDATE
           SET segmento = COALESCE($3, cliente_perfil_tenant.segmento),
               talla_habitual = $4, estilo_preferido = $5, telefono_contacto = $6,
               acepta_whatsapp = $7, notas = $8, actualizado_por_id = $9, actualizado_en = now()
        """,
        sucursal,
        usuario_id,
        body.segmento,
        body.talla_habitual,
        body.estilo_preferido,
        body.telefono_contacto,
        body.acepta_whatsapp,
        body.notas,
        staff["id"],
    )
    await registrar_auditoria(
        conn,
        usuario_id=staff["id"],
        entidad="cliente_perfil_tenant",
        entidad_id=usuario_id,
        accion="ACTUALIZAR" if antes else "CREAR",
        datos_antes=dict(antes) if antes else None,
        datos_despues={"sucursal_id": str(sucursal), **body.model_dump()},
    )


@router.put("/{usuario_id}/perfil", response_model=ClienteTenantOut)
async def editar_perfil(
    usuario_id: UUID,
    body: PerfilClienteIn,
    sucursal_id: UUID | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_editar),
) -> ClienteTenantOut:
    sucursal = _sucursal(staff, sucursal_id)
    await _uno(conn, sucursal, usuario_id)  # tiene que estar en la cartera
    async with conn.transaction():
        await _guardar_perfil(conn, sucursal, usuario_id, body, staff)
    return await _uno(conn, sucursal, usuario_id)


@router.post("", response_model=ClienteTenantOut, status_code=status.HTTP_201_CREATED)
async def agregar_a_cartera(
    body: AltaClienteIn,
    sucursal_id: UUID | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_editar),
) -> ClienteTenantOut:
    sucursal = _sucursal(staff, sucursal_id)
    usuario_id = await conn.fetchval(
        "SELECT id FROM usuario WHERE lower(email) = lower($1) AND tipo = 'CLIENTE' AND activo",
        body.email,
    )
    if usuario_id is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No hay una clienta con ese email (tiene que registrarse primero)",
        )
    async with conn.transaction():
        await _guardar_perfil(conn, sucursal, usuario_id, body, staff)
    return await _uno(conn, sucursal, usuario_id)
