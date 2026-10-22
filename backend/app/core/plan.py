"""SaaS: que puede usar cada tenant segun su plan (segundo parcial, Modulo A).

Tenant = EMPRESA. Cada una tiene una fila en `suscripcion` con su `plan`; el plan dice que
funciones habilita (columnas booleanas de `plan`: perfiles_clientes, traspasos,
operacion_offline, reportes, ia_reportes, analitica_ml) y cuantos recursos admite
(max_sucursales / max_empleados / max_cajas, NULL = sin limite). Todo eso es dato: el
SUPERADMIN lo edita con PUT /saas/planes/{codigo} y rige en el request siguiente.

Politica de suscripcion vencida (RN06): una suscripcion vencida (vence_en pasado, o estado
VENCIDA/CANCELADA) bloquea con 402 las funciones de gestion que pasan por
requiere_funcion_plan y la sincronizacion de operaciones offline registradas despues del
vencimiento. El personal igual puede entrar, ver su plan y renovarlo. La tienda publica y lo ya
comprado por las clientas no se cortan: no se castiga a la clienta por una deuda de la empresa.

`requiere_funcion_plan` combina el chequeo de permiso de CU13 del primer parcial con el del plan,
asi un endpoint reemplaza su `requiere_permiso(...)` por `requiere_funcion_plan("traspasos", ...)`
sin cambiar nada mas. El SUPERADMIN no depende de ningun plan (no es de ninguna empresa).
"""

from datetime import datetime, timezone
from uuid import UUID

import asyncpg
from fastapi import Depends, HTTPException, status

from app.core.db import get_connection
from app.core.deps import requiere_permiso

# funcion del plan -> como se le nombra al usuario
FUNCIONES_PLAN = {
    "perfiles_clientes": "el perfil de clientas",
    "traspasos": "los traspasos entre sucursales",
    "operacion_offline": "la operacion sin conexion",
    "reportes": "los reportes",
    "ia_reportes": "los reportes generativos con IA",
    "analitica_ml": "la analitica con machine learning",
}

RECURSOS_PLAN = {
    "sucursales": "max_sucursales",
    "empleados": "max_empleados",
    "cajas": "max_cajas",
}

SELECT_PLAN_EMPRESA = """
SELECT su.id AS suscripcion_id, su.estado::text AS estado, su.vence_en, su.inicio,
       p.id AS plan_id, p.codigo AS plan_codigo, p.nombre AS plan_nombre,
       p.precio_mensual, p.max_sucursales, p.max_empleados, p.max_cajas,
       p.perfiles_clientes, p.traspasos, p.operacion_offline, p.reportes, p.ia_reportes,
       p.analitica_ml
FROM suscripcion su
JOIN plan p ON p.id = su.plan_id
WHERE su.empresa_id = $1
"""


def esta_vigente(plan: dict | asyncpg.Record, ahora: datetime | None = None) -> bool:
    ahora = ahora or datetime.now(timezone.utc)
    return plan["estado"] in ("PRUEBA", "ACTIVA") and plan["vence_en"] > ahora


def funciones_habilitadas(plan: dict | asyncpg.Record | None) -> list[str]:
    """Las funciones que el plan incluye y se pueden usar hoy (vacia si vencio). Viaja en
    UsuarioOut para que web y movil oculten lo que la API igual rechazaria."""
    if plan is None or not esta_vigente(plan):
        return []
    return [f for f in FUNCIONES_PLAN if plan[f]]


def evaluar_acceso(
    plan: dict | asyncpg.Record | None,
    funcion: str | None,
    plan_minimo: str | None = None,
    ahora: datetime | None = None,
) -> tuple[int, str] | None:
    """(status, detalle) si el tenant NO puede usar la funcion; None si puede. Funcion pura para
    poder probar las reglas sin base."""
    if plan is None:
        return (
            status.HTTP_402_PAYMENT_REQUIRED,
            "Tu empresa no tiene una suscripcion: elegi un plan en Mi suscripcion",
        )
    if not esta_vigente(plan, ahora):
        vence = plan["vence_en"].strftime("%d/%m/%Y")
        return (
            status.HTTP_402_PAYMENT_REQUIRED,
            f"La suscripcion de tu empresa vencio el {vence}: renovala en Mi suscripcion",
        )
    if funcion is not None and not plan[funcion]:
        sugerencia = f"; esta incluido desde el plan {plan_minimo}" if plan_minimo else ""
        return (
            status.HTTP_403_FORBIDDEN,
            f"Tu plan {plan['plan_nombre']} no incluye {FUNCIONES_PLAN[funcion]}{sugerencia}",
        )
    return None


async def plan_de_empresa(conn: asyncpg.Connection, empresa_id: UUID) -> asyncpg.Record | None:
    return await conn.fetchrow(SELECT_PLAN_EMPRESA, empresa_id)


async def _plan_minimo(conn: asyncpg.Connection, funcion: str) -> str | None:
    # funcion viene de FUNCIONES_PLAN (nunca del usuario), por eso se puede interpolar
    return await conn.fetchval(
        f"SELECT nombre FROM plan WHERE activo AND {funcion} ORDER BY orden LIMIT 1"
    )


async def exigir_funcion_empresa(
    conn: asyncpg.Connection, empresa_id: UUID, funcion: str | None
) -> None:
    """Corta con 402/403 si la empresa no puede usar la funcion."""
    plan = await plan_de_empresa(conn, empresa_id)
    bloqueo = evaluar_acceso(plan, funcion)
    if bloqueo is None:
        return
    if bloqueo[0] == status.HTTP_403_FORBIDDEN and funcion is not None:
        # solo cuando corta por plan se busca a que plan subir (una consulta menos por request)
        bloqueo = evaluar_acceso(plan, funcion, await _plan_minimo(conn, funcion))
    raise HTTPException(status_code=bloqueo[0], detail=bloqueo[1])


async def exigir_funcion(conn: asyncpg.Connection, staff: dict, funcion: str | None) -> None:
    """Version para el personal: la empresa es la del usuario. La plataforma pasa siempre."""
    if staff.get("empresa_id") is None:
        return
    await exigir_funcion_empresa(conn, staff["empresa_id"], funcion)


def requiere_funcion_plan(funcion: str | None, *codigos: str):
    """Permiso de CU13 del primer parcial (uno de `codigos`) + plan de la empresa que habilite
    `funcion` y este al dia. funcion=None solo exige la suscripcion vigente."""
    if funcion is not None and funcion not in FUNCIONES_PLAN:
        raise ValueError(f"Funcion de plan desconocida: {funcion}")
    con_permiso = requiere_permiso(*codigos)

    async def verificar(
        staff: dict = Depends(con_permiso),
        conn: asyncpg.Connection = Depends(get_connection),
    ) -> dict:
        await exigir_funcion(conn, staff, funcion)
        return staff

    return verificar


async def uso_de_empresa(conn: asyncpg.Connection, empresa_id: UUID) -> dict[str, int]:
    fila = await conn.fetchrow(
        """
        SELECT
          (SELECT COUNT(*) FROM sucursal s WHERE s.empresa_id = $1 AND s.activa)::int AS sucursales,
          (SELECT COUNT(*) FROM empleado e
             JOIN usuario u  ON u.id = e.usuario_id
             JOIN sucursal s ON s.id = e.sucursal_id
            WHERE s.empresa_id = $1 AND e.activo AND u.activo)::int AS empleados,
          (SELECT COUNT(*) FROM caja c JOIN sucursal s ON s.id = c.sucursal_id
            WHERE s.empresa_id = $1 AND c.activa)::int AS cajas
        """,
        empresa_id,
    )
    return dict(fila)


def evaluar_limite(plan: dict | asyncpg.Record | None, recurso: str, actuales: int) -> str | None:
    """Mensaje de rechazo si agregar uno mas pasaria el tope del plan; None si entra. Pura,
    para probar las reglas sin base."""
    if plan is None:
        return None  # empresa sin suscripcion (base vieja): no se limita
    tope = plan[RECURSOS_PLAN[recurso]]
    if tope is None or actuales < tope:
        return None
    return (
        f"El plan {plan['plan_nombre']} de tu empresa admite hasta {tope} {recurso} activas: "
        "subi de plan para agregar mas"
        if recurso == "sucursales"
        else f"El plan {plan['plan_nombre']} de tu empresa admite hasta {tope} {recurso}: "
        "subi de plan para agregar mas"
    )


async def exigir_limite(conn: asyncpg.Connection, empresa_id: UUID, recurso: str) -> None:
    """recurso: 'sucursales', 'empleados' o 'cajas'. 409 si el plan de la empresa ya llego a
    su tope (RN04). Se llama antes de dar de alta o de reactivar."""
    if recurso not in RECURSOS_PLAN:
        raise ValueError(f"Recurso de plan desconocido: {recurso}")
    plan = await plan_de_empresa(conn, empresa_id)
    uso = await uso_de_empresa(conn, empresa_id)
    rechazo = evaluar_limite(plan, recurso, uso[recurso])
    if rechazo is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=rechazo)
