"""SaaS multi-tenant: empresas, planes y suscripciones (segundo parcial, Modulo A).

Tenant = EMPRESA (ver db/01_schema.sql, bloques 0 y 8). Dos audiencias:

  - La PLATAFORMA (rol SUPERADMIN, usuario sin empresa): registra empresas con su
    administrador (CU01), les asigna/cambia plan con fechas (CU02), registra renovaciones
    simuladas sin cobro real (CU04), configura los planes (CU05) y suspende/reactiva empresas.
    Permisos `empresas.*` y `planes.actualizar`, que ninguna empresa puede asignarse.
  - Cada EMPRESA (permiso `suscripciones.*`, ADMIN; el ENCARGADO solo consulta): ve su plan, su
    uso contra los topes y su historial (CU03), y puede pagar/cambiar de plan con Stripe.

Pago con Stripe: POST /saas/suscripcion/checkout crea el pago_suscripcion PENDIENTE y una
Checkout Session hospedada (moneda bob, metadata tipo=SUSCRIPCION). Lo aprueba el webhook de
Stripe (pagos/router.py lo deriva a servicio.procesar_evento_stripe) o POST
/saas/pagos/verificar al volver del Checkout. Aprobar extiende vence_en desde el fin del periodo
vigente (o desde hoy si ya vencio) y deja el plan pagado como plan de la empresa.

Bajar de plan: no se permite pasar a un plan cuyo tope de sucursales/personal/cajas ya esta
superado (409): primero hay que dar de baja lo que sobra.
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
from app.core.plan import RECURSOS_PLAN, esta_vigente, uso_de_empresa
from app.core.security import hash_password
from app.core.tenant import es_plataforma, no_encontrado
from app.modules.saas import servicio
from app.modules.saas.schemas import (
    AsignarPlanIn,
    CheckoutSuscripcionIn,
    CheckoutSuscripcionOut,
    EmpresaDatosIn,
    EmpresaIn,
    EmpresaOut,
    EstadoEmpresaIn,
    PagoManualIn,
    PagoSuscripcionOut,
    PlanIn,
    PlanOut,
    SuscripcionOut,
    TiendaOut,
    UsoOut,
)

router = APIRouter(prefix="/saas", tags=["saas"])

stripe.api_key = settings.stripe_secret_key

puede_ver = requiere_permiso("suscripciones.leer", "suscripciones.actualizar")
puede_pagar = requiere_permiso("suscripciones.actualizar")
plataforma_ver = requiere_permiso("empresas.leer")
plataforma_crear = requiere_permiso("empresas.crear")
plataforma_editar = requiere_permiso("empresas.actualizar")
plataforma_planes = requiere_permiso("planes.actualizar")

CAMPOS_PLAN = """
p.id AS plan_id, p.codigo, p.nombre, p.descripcion, p.precio_mensual, p.max_sucursales,
p.max_empleados, p.max_cajas, p.perfiles_clientes, p.traspasos, p.operacion_offline, p.reportes,
p.ia_reportes, p.analitica_ml
"""

SELECT_PLAN = "SELECT " + CAMPOS_PLAN + " FROM plan p "

SELECT_SUSCRIPCION = (
    """
SELECT su.empresa_id, e.nombre AS empresa, e.slug AS empresa_slug, e.activa AS empresa_activa,
       su.estado::text AS estado, su.inicio, su.vence_en, """
    + CAMPOS_PLAN
    + """
FROM suscripcion su
JOIN empresa e ON e.id = su.empresa_id
JOIN plan p    ON p.id = su.plan_id
"""
)

SELECT_PAGO = """
SELECT ps.id, e.nombre AS empresa, p.nombre AS plan, ps.meses, ps.monto, ps.metodo,
       ps.estado::text AS estado, ps.periodo_desde, ps.periodo_hasta,
       (u.nombre || ' ' || u.apellido) AS pagado_por, ps.creado_en, ps.confirmado_en
FROM pago_suscripcion ps
JOIN suscripcion su ON su.id = ps.suscripcion_id
JOIN empresa e      ON e.id = su.empresa_id
JOIN plan p         ON p.id = ps.plan_id
LEFT JOIN usuario u ON u.id = ps.pagado_por_id
"""


def _plan_out(fila: asyncpg.Record) -> PlanOut:
    return PlanOut(id=fila["plan_id"], **{k: fila[k] for k in PlanOut.model_fields if k != "id"})


async def _armar(conn: asyncpg.Connection, fila: asyncpg.Record) -> SuscripcionOut:
    ahora = datetime.now(timezone.utc)
    return SuscripcionOut(
        empresa_id=fila["empresa_id"],
        empresa=fila["empresa"],
        empresa_slug=fila["empresa_slug"],
        empresa_activa=fila["empresa_activa"],
        plan=_plan_out(fila),
        estado=fila["estado"],
        vigente=esta_vigente(fila, ahora),
        inicio=fila["inicio"],
        vence_en=fila["vence_en"],
        dias_restantes=max((fila["vence_en"] - ahora).days, 0),
        uso=UsoOut(**await uso_de_empresa(conn, fila["empresa_id"])),
    )


async def _suscripcion(conn: asyncpg.Connection, empresa_id: UUID) -> SuscripcionOut | None:
    fila = await conn.fetchrow(SELECT_SUSCRIPCION + "WHERE su.empresa_id = $1", empresa_id)
    return await _armar(conn, fila) if fila else None


def _empresa_objetivo(staff: dict, pedida: UUID | None) -> UUID:
    """La empresa sobre la que se opera: la propia; la plataforma elige cualquiera."""
    if es_plataforma(staff):
        if pedida is None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Indica la empresa"
            )
        return pedida
    if pedida is not None and pedida != staff["empresa_id"]:
        raise no_encontrado("Empresa no encontrada")
    if staff["empresa_id"] is None:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Tu usuario no es de una empresa")
    return staff["empresa_id"]


async def _plan_por_codigo(conn: asyncpg.Connection, codigo: str) -> asyncpg.Record:
    plan = await conn.fetchrow(SELECT_PLAN + "WHERE p.codigo = upper($1) AND p.activo", codigo.strip())
    if plan is None:
        raise no_encontrado("Ese plan no existe")
    return plan


async def _exigir_entra_en_plan(conn: asyncpg.Connection, empresa_id: UUID, plan: asyncpg.Record) -> None:
    """No se baja a un plan cuyos topes la empresa ya supera."""
    uso = await uso_de_empresa(conn, empresa_id)
    for recurso, columna in RECURSOS_PLAN.items():
        tope = plan[columna]
        if tope is not None and uso[recurso] > tope:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    f"La empresa tiene {uso[recurso]} {recurso} activas y el plan {plan['nombre']} "
                    f"admite {tope}: da de baja lo que sobra antes de cambiar de plan"
                ),
            )


# ---------------------------------------------------------------------
#  PLANES
# ---------------------------------------------------------------------


@router.get("/planes", response_model=list[PlanOut])
async def listar_planes(conn: asyncpg.Connection = Depends(get_connection)) -> list[PlanOut]:
    """Publico: lo muestra la pagina de planes antes de iniciar sesion."""
    filas = await conn.fetch(SELECT_PLAN + "WHERE p.activo ORDER BY p.orden")
    return [_plan_out(f) for f in filas]


@router.get("/tiendas", response_model=list[TiendaOut])
async def listar_tiendas(conn: asyncpg.Connection = Depends(get_connection)) -> list[TiendaOut]:
    """Publico: las tiendas activas de la plataforma, para el selector de la vitrina (cada una
    se mira con ?empresa=slug / header X-Empresa)."""
    filas = await conn.fetch("SELECT slug, nombre FROM empresa WHERE activa ORDER BY nombre")
    return [TiendaOut(**dict(f)) for f in filas]


@router.put("/planes/{codigo}", response_model=PlanOut)
async def configurar_plan(
    codigo: str,
    body: PlanIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(plataforma_planes),
) -> PlanOut:
    """CU05 - Configurar limites del plan. Rige desde el request siguiente para todas las
    empresas de ese plan (requiere_funcion_plan y exigir_limite leen la fila en cada request).
    Bajar un tope por debajo del uso de una empresa no le borra nada: solo le impide agregar."""
    antes = await conn.fetchrow(SELECT_PLAN + "WHERE p.codigo = upper($1)", codigo.strip())
    if antes is None:
        raise no_encontrado("Ese plan no existe")
    async with conn.transaction():
        await conn.execute(
            """
            UPDATE plan
               SET nombre = $2, descripcion = $3, precio_mensual = $4, max_sucursales = $5,
                   max_empleados = $6, max_cajas = $7, perfiles_clientes = $8, traspasos = $9,
                   operacion_offline = $10, reportes = $11, ia_reportes = $12,
                   analitica_ml = $13, activo = $14
             WHERE id = $1
            """,
            antes["plan_id"],
            body.nombre,
            body.descripcion,
            body.precio_mensual,
            body.max_sucursales,
            body.max_empleados,
            body.max_cajas,
            body.perfiles_clientes,
            body.traspasos,
            body.operacion_offline,
            body.reportes,
            body.ia_reportes,
            body.analitica_ml,
            body.activo,
        )
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="plan",
            entidad_id=antes["codigo"],
            accion="ACTUALIZAR",
            datos_antes={k: antes[k] for k in PlanIn.model_fields if k in antes.keys()},
            datos_despues=body.model_dump(mode="json"),
        )
    return _plan_out(await conn.fetchrow(SELECT_PLAN + "WHERE p.id = $1", antes["plan_id"]))


# ---------------------------------------------------------------------
#  EMPRESAS (plataforma)
# ---------------------------------------------------------------------


async def _empresa_out(conn: asyncpg.Connection, fila: asyncpg.Record) -> EmpresaOut:
    admins = await conn.fetch(
        """
        SELECT u.email FROM usuario u JOIN rol r ON r.id = u.rol_id
         WHERE u.empresa_id = $1 AND r.nombre = 'ADMIN' AND u.activo ORDER BY u.email
        """,
        fila["id"],
    )
    return EmpresaOut(
        **{k: fila[k] for k in EmpresaOut.model_fields if k not in ("administradores", "suscripcion")},
        administradores=[a["email"] for a in admins],
        suscripcion=await _suscripcion(conn, fila["id"]),
    )


async def _obtener_empresa(conn: asyncpg.Connection, empresa_id: UUID) -> EmpresaOut:
    fila = await conn.fetchrow("SELECT * FROM empresa WHERE id = $1", empresa_id)
    if fila is None:
        raise no_encontrado("Empresa no encontrada")
    return await _empresa_out(conn, fila)


@router.get("/empresas", response_model=list[EmpresaOut])
async def listar_empresas(
    conn: asyncpg.Connection = Depends(get_connection),
    _staff: dict = Depends(plataforma_ver),
) -> list[EmpresaOut]:
    filas = await conn.fetch("SELECT * FROM empresa ORDER BY activa DESC, nombre")
    return [await _empresa_out(conn, f) for f in filas]


@router.get("/empresas/{empresa_id}", response_model=EmpresaOut)
async def obtener_empresa(
    empresa_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    _staff: dict = Depends(plataforma_ver),
) -> EmpresaOut:
    return await _obtener_empresa(conn, empresa_id)


@router.post("/empresas", response_model=EmpresaOut, status_code=status.HTTP_201_CREATED)
async def registrar_empresa(
    body: EmpresaIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(plataforma_crear),
) -> EmpresaOut:
    """CU01 - Registrar empresa: crea el tenant, su suscripcion en PRUEBA del plan elegido y su
    administrador (rol ADMIN, RN03). Con `sucursal`, ademas su primera sucursal con una caja y
    el administrador asignado ahi (asi puede operar caja y reservas desde el primer dia)."""
    plan = await _plan_por_codigo(conn, body.plan_codigo)
    try:
        async with conn.transaction():
            empresa_id = await conn.fetchval(
                """
                INSERT INTO empresa (slug, nombre, razon_social, nit, email, telefono)
                VALUES ($1, $2, $3, $4, $5, $6) RETURNING id
                """,
                body.slug,
                body.nombre,
                body.razon_social,
                body.nit,
                body.email,
                body.telefono,
            )
            await conn.execute(
                """
                INSERT INTO suscripcion (empresa_id, plan_id, estado, vence_en)
                VALUES ($1, $2, 'PRUEBA', now() + make_interval(days => $3))
                """,
                empresa_id,
                plan["plan_id"],
                body.dias_prueba,
            )
            admin_id = await conn.fetchval(
                """
                INSERT INTO usuario (email, password_hash, nombre, apellido, tipo, rol_id,
                                     empresa_id, email_verificado)
                VALUES ($1, $2, $3, $4, 'STAFF',
                        (SELECT id FROM rol WHERE nombre = 'ADMIN' AND empresa_id IS NULL), $5, TRUE)
                RETURNING id
                """,
                body.administrador.email,
                hash_password(body.administrador.password),
                body.administrador.nombre,
                body.administrador.apellido,
                empresa_id,
            )
            if body.sucursal is not None:
                sucursal_id = await conn.fetchval(
                    """
                    INSERT INTO sucursal (empresa_id, codigo, nombre, ciudad, direccion,
                                          hora_apertura, hora_cierre)
                    VALUES ($1, upper($2), $3, $4::ciudad_bo, $5, $6, $7) RETURNING id
                    """,
                    empresa_id,
                    body.sucursal.codigo,
                    body.sucursal.nombre,
                    body.sucursal.ciudad,
                    body.sucursal.direccion,
                    body.sucursal.hora_apertura,
                    body.sucursal.hora_cierre,
                )
                await conn.execute(
                    "INSERT INTO caja (sucursal_id, codigo, nombre) VALUES ($1, 'CAJA-01', 'Caja principal')",
                    sucursal_id,
                )
                await conn.execute(
                    """
                    INSERT INTO empleado (usuario_id, sucursal_id, cargo, fecha_ingreso)
                    VALUES ($1, $2, 'ENCARGADO', CURRENT_DATE)
                    """,
                    admin_id,
                    sucursal_id,
                )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="empresa",
                entidad_id=empresa_id,
                accion="CREAR",
                datos_despues=body.model_dump(mode="json", exclude={"administrador": {"password"}}),
            )
    except asyncpg.UniqueViolationError as error:
        detalle = {
            "empresa_slug_key": "Ya existe una empresa con ese identificador",
            "usuario_email_key": "Ese email ya esta registrado en la plataforma",
            "sucursal_codigo_key": "Ese codigo de sucursal ya existe",
        }.get(error.constraint_name, "Ya existe un registro con esos datos")
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=detalle)
    except asyncpg.InvalidTextRepresentationError:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Ciudad invalida")
    return await _obtener_empresa(conn, empresa_id)


@router.put("/empresas/{empresa_id}", response_model=EmpresaOut)
async def editar_empresa(
    empresa_id: UUID,
    body: EmpresaDatosIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(plataforma_editar),
) -> EmpresaOut:
    antes = await _obtener_empresa(conn, empresa_id)
    async with conn.transaction():
        await conn.execute(
            """
            UPDATE empresa SET nombre = $2, razon_social = $3, nit = $4, email = $5, telefono = $6
             WHERE id = $1
            """,
            empresa_id,
            body.nombre,
            body.razon_social,
            body.nit,
            body.email,
            body.telefono,
        )
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="empresa",
            entidad_id=empresa_id,
            accion="ACTUALIZAR",
            datos_antes=antes.model_dump(mode="json", include=set(EmpresaDatosIn.model_fields)),
            datos_despues=body.model_dump(mode="json"),
        )
    return await _obtener_empresa(conn, empresa_id)


@router.patch("/empresas/{empresa_id}/estado", response_model=EmpresaOut)
async def cambiar_estado_empresa(
    empresa_id: UUID,
    body: EstadoEmpresaIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(plataforma_editar),
) -> EmpresaOut:
    """Suspender una empresa deja a todo su personal sin acceso (403 en el login y en cada
    request, app/core/deps.py) y saca su tienda publica; no borra nada."""
    antes = await _obtener_empresa(conn, empresa_id)
    async with conn.transaction():
        await conn.execute("UPDATE empresa SET activa = $2 WHERE id = $1", empresa_id, body.activa)
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="empresa",
            entidad_id=empresa_id,
            accion="ACTUALIZAR" if body.activa else "ELIMINAR",
            datos_antes={"activa": antes.activa},
            datos_despues={"activa": body.activa},
        )
    return await _obtener_empresa(conn, empresa_id)


@router.put("/empresas/{empresa_id}/plan", response_model=SuscripcionOut)
async def asignar_plan(
    empresa_id: UUID,
    body: AsignarPlanIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(plataforma_editar),
) -> SuscripcionOut:
    """CU02 - Asignar / cambiar plan con fecha de inicio y vencimiento (administrativo, sin
    cobro). Para registrar un cobro recibido esta POST /saas/suscripciones/{id}/pago-manual."""
    await _obtener_empresa(conn, empresa_id)
    plan = await _plan_por_codigo(conn, body.plan_codigo)
    inicio = body.inicio or datetime.now(timezone.utc)
    if body.vence_en <= inicio:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="El vencimiento tiene que ser posterior al inicio",
        )
    await _exigir_entra_en_plan(conn, empresa_id, plan)
    antes = await _suscripcion(conn, empresa_id)
    async with conn.transaction():
        await conn.execute(
            """
            INSERT INTO suscripcion (empresa_id, plan_id, estado, inicio, vence_en)
            VALUES ($1, $2, $3::estado_suscripcion, $4, $5)
            ON CONFLICT (empresa_id) DO UPDATE
               SET plan_id = EXCLUDED.plan_id, estado = EXCLUDED.estado, inicio = EXCLUDED.inicio,
                   vence_en = EXCLUDED.vence_en, actualizado_en = now()
            """,
            empresa_id,
            plan["plan_id"],
            body.estado,
            inicio,
            body.vence_en,
        )
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="suscripcion",
            entidad_id=empresa_id,
            accion="ACTUALIZAR",
            datos_antes=(
                {"plan": antes.plan.codigo, "estado": antes.estado, "vence_en": antes.vence_en}
                if antes
                else None
            ),
            datos_despues=body.model_dump(mode="json"),
        )
    return await _suscripcion(conn, empresa_id)


# ---------------------------------------------------------------------
#  SUSCRIPCION DE LA EMPRESA
# ---------------------------------------------------------------------


@router.get("/suscripcion", response_model=SuscripcionOut)
async def mi_suscripcion(
    empresa_id: UUID | None = Query(default=None, description="Solo la plataforma la elige"),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> SuscripcionOut:
    """CU03 - Consultar estado de suscripcion: plan, vigencia, uso y topes."""
    suscripcion = await _suscripcion(conn, _empresa_objetivo(staff, empresa_id))
    if suscripcion is None:
        raise no_encontrado("La empresa no tiene suscripcion")
    return suscripcion


@router.get("/suscripciones", response_model=list[SuscripcionOut])
async def listar_suscripciones(
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[SuscripcionOut]:
    """Todas las empresas (plataforma); una empresa ve solo la suya."""
    if es_plataforma(staff):
        filas = await conn.fetch(SELECT_SUSCRIPCION + "ORDER BY su.vence_en")
    else:
        filas = await conn.fetch(
            SELECT_SUSCRIPCION + "WHERE su.empresa_id = $1", staff["empresa_id"]
        )
    return [await _armar(conn, f) for f in filas]


@router.get("/pagos", response_model=list[PagoSuscripcionOut])
async def listar_pagos(
    empresa_id: UUID | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[PagoSuscripcionOut]:
    filtro = empresa_id if es_plataforma(staff) else _empresa_objetivo(staff, empresa_id)
    filas = await conn.fetch(
        SELECT_PAGO
        + "WHERE ($1::uuid IS NULL OR su.empresa_id = $1) ORDER BY ps.creado_en DESC LIMIT 100",
        filtro,
    )
    return [PagoSuscripcionOut(**dict(f)) for f in filas]


async def _crear_pago(
    conn: asyncpg.Connection, empresa_id: UUID, plan: asyncpg.Record, meses: int, metodo: str, staff: dict
) -> asyncpg.Record:
    suscripcion_id = await conn.fetchval(
        "SELECT id FROM suscripcion WHERE empresa_id = $1", empresa_id
    )
    if suscripcion_id is None:
        # empresa de una base vieja sin suscripcion: se crea vencida para que el pago la active
        suscripcion_id = await conn.fetchval(
            """
            INSERT INTO suscripcion (empresa_id, plan_id, estado, vence_en)
            VALUES ($1, $2, 'VENCIDA', now()) RETURNING id
            """,
            empresa_id,
            plan["plan_id"],
        )
    return await conn.fetchrow(
        """
        INSERT INTO pago_suscripcion (suscripcion_id, plan_id, meses, monto, metodo, pagado_por_id)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING id, monto
        """,
        suscripcion_id,
        plan["plan_id"],
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
    empresa_id = _empresa_objetivo(staff, None)
    plan = await _plan_por_codigo(conn, body.plan_codigo)
    await _exigir_entra_en_plan(conn, empresa_id, plan)
    pago = await _crear_pago(conn, empresa_id, plan, body.meses, "STRIPE", staff)
    nombre = await conn.fetchval("SELECT nombre FROM empresa WHERE id = $1", empresa_id)
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
        SELECT ps.id, su.empresa_id FROM pago_suscripcion ps
        JOIN suscripcion su ON su.id = ps.suscripcion_id
        WHERE ps.id_transaccion = $1
        """,
        sesion,
    )
    if pago is None:
        raise no_encontrado("Pago no encontrado")
    if not es_plataforma(staff):
        _empresa_objetivo(staff, pago["empresa_id"])
    try:
        datos = await asyncio.to_thread(stripe.checkout.Session.retrieve, sesion)
    except stripe.error.StripeError as error:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY, detail=f"No se pudo consultar Stripe: {error}"
        ) from error
    if datos.get("payment_status") == "paid":
        await servicio.aplicar_pago(conn, pago["id"])
    return await _suscripcion(conn, pago["empresa_id"])


@router.post("/suscripciones/{empresa_id}/pago-manual", response_model=SuscripcionOut)
async def registrar_pago_manual(
    empresa_id: UUID,
    body: PagoManualIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_pagar),
) -> SuscripcionOut:
    """CU04 - Renovar suscripcion (simulada): pago recibido por transferencia o en efectivo.
    Solo la plataforma lo registra y queda aprobado en el acto."""
    if not es_plataforma(staff):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo la administracion de la plataforma registra pagos manuales",
        )
    await _obtener_empresa(conn, empresa_id)
    plan = await _plan_por_codigo(conn, body.plan_codigo)
    await _exigir_entra_en_plan(conn, empresa_id, plan)
    pago = await _crear_pago(conn, empresa_id, plan, body.meses, body.metodo, staff)
    await servicio.aplicar_pago(conn, pago["id"])
    await registrar_auditoria(
        conn,
        usuario_id=staff["id"],
        entidad="suscripcion",
        entidad_id=empresa_id,
        accion="ACTUALIZAR",
        datos_despues={"plan": plan["codigo"], "meses": body.meses, "metodo": body.metodo,
                       "monto": pago["monto"]},
    )
    return await _suscripcion(conn, empresa_id)
