"""SaaS: planes y suscripcion de cada tenant (Segundo parcial, PENDIENTES 5.4 a 5.6).

Tenant = sucursal (ver db/01_schema.sql, bloque 8). Quien gestiona la suscripcion de una
sucursal es su administracion (permiso `suscripciones.*`, sembrado para ENCARGADO); el ADMIN de
la plataforma ve todos los tenants y puede registrar pagos recibidos fuera de Stripe.

Pago (PENDIENTES 5.5): POST /saas/suscripcion/checkout crea el pago_suscripcion PENDIENTE y una
Checkout Session hospedada de Stripe (moneda bob, metadata tipo=SUSCRIPCION). Lo aprueba:
  - el webhook de Stripe (pagos/router.py lo deriva a servicio.procesar_evento_stripe), o
  - POST /saas/pagos/verificar al volver del Checkout, que le pregunta a Stripe por la sesion
    (sirve en local sin `stripe listen`).
Aprobar extiende vence_en desde el fin del periodo vigente (o desde hoy si ya vencio) y deja el
plan pagado como plan del tenant -- asi tambien se cambia de plan.
"""

import asyncio
from datetime import datetime, timezone
from uuid import UUID

import asyncpg
import stripe
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.auditoria import registrar_auditoria
from app.core.config import settings
from app.core.db import get_connection
from app.core.deps import requiere_permiso
from app.core.plan import es_admin_plataforma, esta_vigente
from app.modules.saas import servicio
from app.modules.saas.schemas import (
    CheckoutSuscripcionIn,
    CheckoutSuscripcionOut,
    PagoManualIn,
    PagoSuscripcionOut,
    PlanOut,
    SuscripcionOut,
)

router = APIRouter(prefix="/saas", tags=["saas"])

stripe.api_key = settings.stripe_secret_key

puede_ver = requiere_permiso("suscripciones.leer", "suscripciones.actualizar")
puede_pagar = requiere_permiso("suscripciones.actualizar")

SELECT_PLAN = """
SELECT id, codigo, nombre, descripcion, precio_mensual, max_empleados, max_cajas,
       perfiles_clientes, traspasos, ia_reportes
FROM plan
"""

SELECT_SUSCRIPCION = """
SELECT su.sucursal_id, s.nombre AS sucursal, s.ciudad::text AS ciudad,
       su.estado::text AS estado, su.inicio, su.vence_en,
       p.id AS plan_id, p.codigo, p.nombre, p.descripcion, p.precio_mensual, p.max_empleados,
       p.max_cajas, p.perfiles_clientes, p.traspasos, p.ia_reportes,
       (SELECT COUNT(*) FROM empleado e JOIN usuario u ON u.id = e.usuario_id
         WHERE e.sucursal_id = s.id AND e.activo AND u.activo)::int AS empleados,
       (SELECT COUNT(*) FROM caja c WHERE c.sucursal_id = s.id AND c.activa)::int AS cajas
FROM suscripcion su
JOIN sucursal s ON s.id = su.sucursal_id
JOIN plan p     ON p.id = su.plan_id
"""

SELECT_PAGO = """
SELECT ps.id, s.nombre AS sucursal, p.nombre AS plan, ps.meses, ps.monto, ps.metodo,
       ps.estado::text AS estado, ps.periodo_desde, ps.periodo_hasta,
       (u.nombre || ' ' || u.apellido) AS pagado_por, ps.creado_en, ps.confirmado_en
FROM pago_suscripcion ps
JOIN suscripcion su ON su.id = ps.suscripcion_id
JOIN sucursal s     ON s.id = su.sucursal_id
JOIN plan p         ON p.id = ps.plan_id
LEFT JOIN usuario u ON u.id = ps.pagado_por_id
"""


def _armar(fila: asyncpg.Record) -> SuscripcionOut:
    ahora = datetime.now(timezone.utc)
    return SuscripcionOut(
        sucursal_id=fila["sucursal_id"],
        sucursal=fila["sucursal"],
        ciudad=fila["ciudad"],
        plan=PlanOut(id=fila["plan_id"], **{k: fila[k] for k in PlanOut.model_fields if k != "id"}),
        estado=fila["estado"],
        vigente=esta_vigente(fila, ahora),
        inicio=fila["inicio"],
        vence_en=fila["vence_en"],
        dias_restantes=max((fila["vence_en"] - ahora).days, 0),
        empleados=fila["empleados"],
        cajas=fila["cajas"],
    )


def _sucursal_objetivo(staff: dict, pedida: UUID | None) -> UUID:
    """La sucursal sobre la que se opera: la propia, o cualquiera si es el ADMIN."""
    if pedida is not None:
        if not es_admin_plataforma(staff) and pedida != staff["sucursal_id"]:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Solo podes ver la suscripcion de tu sucursal",
            )
        return pedida
    if staff["sucursal_id"] is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Indica la sucursal"
        )
    return staff["sucursal_id"]


async def _plan_por_codigo(conn: asyncpg.Connection, codigo: str) -> asyncpg.Record:
    plan = await conn.fetchrow(SELECT_PLAN + "WHERE codigo = upper($1) AND activo", codigo.strip())
    if plan is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Ese plan no existe")
    return plan


@router.get("/planes", response_model=list[PlanOut])
async def listar_planes(conn: asyncpg.Connection = Depends(get_connection)) -> list[PlanOut]:
    """Publico: lo muestra la pagina de planes antes de iniciar sesion."""
    filas = await conn.fetch(SELECT_PLAN + "WHERE activo ORDER BY orden")
    return [PlanOut(**dict(f)) for f in filas]


@router.get("/suscripcion", response_model=SuscripcionOut)
async def mi_suscripcion(
    sucursal_id: UUID | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> SuscripcionOut:
    sucursal = _sucursal_objetivo(staff, sucursal_id)
    fila = await conn.fetchrow(SELECT_SUSCRIPCION + "WHERE su.sucursal_id = $1", sucursal)
    if fila is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="La sucursal no tiene suscripcion"
        )
    return _armar(fila)


@router.get("/suscripciones", response_model=list[SuscripcionOut])
async def listar_suscripciones(
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[SuscripcionOut]:
    """Todos los tenants (ADMIN de la plataforma); el resto ve solo el suyo."""
    if es_admin_plataforma(staff):
        filas = await conn.fetch(SELECT_SUSCRIPCION + "ORDER BY su.vence_en")
    else:
        filas = await conn.fetch(
            SELECT_SUSCRIPCION + "WHERE su.sucursal_id = $1", staff["sucursal_id"]
        )
    return [_armar(f) for f in filas]


@router.get("/pagos", response_model=list[PagoSuscripcionOut])
async def listar_pagos(
    sucursal_id: UUID | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[PagoSuscripcionOut]:
    filtro = sucursal_id if es_admin_plataforma(staff) else _sucursal_objetivo(staff, sucursal_id)
    filas = await conn.fetch(
        SELECT_PAGO + "WHERE ($1::uuid IS NULL OR su.sucursal_id = $1) ORDER BY ps.creado_en DESC LIMIT 100",
        filtro,
    )
    return [PagoSuscripcionOut(**dict(f)) for f in filas]


async def _crear_pago(
    conn: asyncpg.Connection, sucursal: UUID, plan: asyncpg.Record, meses: int, metodo: str, staff: dict
) -> asyncpg.Record:
    suscripcion_id = await conn.fetchval(
        "SELECT id FROM suscripcion WHERE sucursal_id = $1", sucursal
    )
    if suscripcion_id is None:
        # tenant de una base vieja sin suscripcion: se crea vencida para que el pago la active
        suscripcion_id = await conn.fetchval(
            """
            INSERT INTO suscripcion (sucursal_id, plan_id, estado, vence_en)
            VALUES ($1, $2, 'VENCIDA', now()) RETURNING id
            """,
            sucursal,
            plan["id"],
        )
    return await conn.fetchrow(
        """
        INSERT INTO pago_suscripcion (suscripcion_id, plan_id, meses, monto, metodo, pagado_por_id)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING id, monto
        """,
        suscripcion_id,
        plan["id"],
        meses,
        plan["precio_mensual"] * meses,
        metodo,
        staff["id"],
    )


@router.post("/suscripcion/checkout", response_model=CheckoutSuscripcionOut)
async def iniciar_pago(
    body: CheckoutSuscripcionIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_pagar),
) -> CheckoutSuscripcionOut:
    if not settings.stripe_secret_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="El pago con tarjeta no esta configurado (falta STRIPE_SECRET_KEY)",
        )
    sucursal = _sucursal_objetivo(staff, body.sucursal_id)
    plan = await _plan_por_codigo(conn, body.plan_codigo)
    pago = await _crear_pago(conn, sucursal, plan, body.meses, "STRIPE", staff)
    nombre = await conn.fetchval("SELECT nombre FROM sucursal WHERE id = $1", sucursal)
    try:
        sesion = await asyncio.to_thread(
            stripe.checkout.Session.create,
            mode="payment",
            payment_method_types=["card"],
            line_items=[
                {
                    "price_data": {
                        "currency": "bob",
                        "product_data": {
                            "name": f"Plan {plan['nombre']} x {body.meses} mes(es) - {nombre}"
                        },
                        "unit_amount": int(pago["monto"] * 100),
                    },
                    "quantity": 1,
                }
            ],
            metadata={"tipo": "SUSCRIPCION", "pago_suscripcion_id": str(pago["id"])},
            success_url=f"{settings.frontend_url}/panel/suscripcion?sesion={{CHECKOUT_SESSION_ID}}",
            cancel_url=f"{settings.frontend_url}/panel/suscripcion?cancelado=1",
        )
    except stripe.error.StripeError as error:
        await servicio.rechazar_pago(conn, pago["id"])
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"No se pudo iniciar el pago con Stripe: {error}",
        ) from error
    await conn.execute(
        "UPDATE pago_suscripcion SET id_transaccion = $2 WHERE id = $1", pago["id"], sesion.id
    )
    return CheckoutSuscripcionOut(pago_id=pago["id"], monto=pago["monto"], url_pago=sesion.url)


@router.post("/pagos/verificar", response_model=SuscripcionOut)
async def verificar_pago(
    sesion: str = Query(min_length=5, max_length=120, description="id de la Checkout Session"),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> SuscripcionOut:
    """Al volver del Checkout: le pregunta a Stripe si la sesion se pago y, si si, aplica el pago
    (idempotente con el webhook: el que llega segundo no hace nada)."""
    pago = await conn.fetchrow(
        """
        SELECT ps.id, su.sucursal_id FROM pago_suscripcion ps
        JOIN suscripcion su ON su.id = ps.suscripcion_id
        WHERE ps.id_transaccion = $1
        """,
        sesion,
    )
    if pago is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pago no encontrado")
    _sucursal_objetivo(staff, pago["sucursal_id"])
    try:
        datos = await asyncio.to_thread(stripe.checkout.Session.retrieve, sesion)
    except stripe.error.StripeError as error:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY, detail=f"No se pudo consultar Stripe: {error}"
        ) from error
    if datos.get("payment_status") == "paid":
        await servicio.aplicar_pago(conn, pago["id"])
    fila = await conn.fetchrow(SELECT_SUSCRIPCION + "WHERE su.sucursal_id = $1", pago["sucursal_id"])
    return _armar(fila)


@router.post("/suscripciones/{sucursal_id}/pago-manual", response_model=SuscripcionOut)
async def registrar_pago_manual(
    sucursal_id: UUID,
    body: PagoManualIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_pagar),
) -> SuscripcionOut:
    """Pago recibido por transferencia o en efectivo: solo el ADMIN de la plataforma lo registra
    y queda aprobado en el acto."""
    if not es_admin_plataforma(staff):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo la administracion de la plataforma registra pagos manuales",
        )
    plan = await _plan_por_codigo(conn, body.plan_codigo)
    pago = await _crear_pago(conn, sucursal_id, plan, body.meses, body.metodo, staff)
    await servicio.aplicar_pago(conn, pago["id"])
    await registrar_auditoria(
        conn,
        usuario_id=staff["id"],
        entidad="suscripcion",
        entidad_id=sucursal_id,
        accion="ACTUALIZAR",
        datos_despues={"plan": plan["codigo"], "meses": body.meses, "metodo": body.metodo,
                       "monto": pago["monto"]},
    )
    fila = await conn.fetchrow(SELECT_SUSCRIPCION + "WHERE su.sucursal_id = $1", sucursal_id)
    return _armar(fila)
