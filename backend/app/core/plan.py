"""SaaS: que puede usar cada tenant segun su plan (Segundo parcial, PENDIENTES 5.4 a 5.6).

Tenant = sucursal. Cada una tiene una fila en `suscripcion` con su `plan`; el plan dice que
funciones de gestion habilita (columnas booleanas de `plan`: perfiles_clientes, traspasos,
ia_reportes) y cuanto personal y cuantas cajas admite (max_empleados / max_cajas, NULL = sin
limite). Una suscripcion vencida (vence_en pasado, o estado VENCIDA/CANCELADA) bloquea esas
funciones con 402 hasta que se renueve.

El ADMIN (el que puede editar sucursales, mismo criterio que recepciones/traspasos) es el dueño
de la plataforma: no esta atado al plan de ninguna sucursal.

`requiere_funcion_plan` combina el chequeo de permiso de CU13 con el del plan, asi un endpoint
reemplaza su `requiere_permiso(...)` por `requiere_funcion_plan("traspasos", ...)` sin cambiar
nada mas.
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
    "ia_reportes": "los reportes con IA",
}

SELECT_PLAN_SUCURSAL = """
SELECT su.id AS suscripcion_id, su.estado::text AS estado, su.vence_en, su.inicio,
       p.id AS plan_id, p.codigo AS plan_codigo, p.nombre AS plan_nombre,
       p.precio_mensual, p.max_empleados, p.max_cajas,
       p.perfiles_clientes, p.traspasos, p.ia_reportes
FROM suscripcion su
JOIN plan p ON p.id = su.plan_id
WHERE su.sucursal_id = $1
"""


def es_admin_plataforma(staff: dict) -> bool:
    return "sucursales.actualizar" in staff["permisos"]


def esta_vigente(plan: dict | asyncpg.Record, ahora: datetime | None = None) -> bool:
    ahora = ahora or datetime.now(timezone.utc)
    return plan["estado"] in ("PRUEBA", "ACTIVA") and plan["vence_en"] > ahora


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
            "Tu sucursal no tiene una suscripcion: elegi un plan en Mi suscripcion",
        )
    if not esta_vigente(plan, ahora):
        vence = plan["vence_en"].strftime("%d/%m/%Y")
        return (
            status.HTTP_402_PAYMENT_REQUIRED,
            f"La suscripcion de tu sucursal vencio el {vence}: renovala en Mi suscripcion",
        )
    if funcion is not None and not plan[funcion]:
        sugerencia = f"; esta incluido desde el plan {plan_minimo}" if plan_minimo else ""
        return (
            status.HTTP_403_FORBIDDEN,
            f"Tu plan {plan['plan_nombre']} no incluye {FUNCIONES_PLAN[funcion]}{sugerencia}",
        )
    return None


async def plan_de_sucursal(conn: asyncpg.Connection, sucursal_id: UUID) -> asyncpg.Record | None:
    return await conn.fetchrow(SELECT_PLAN_SUCURSAL, sucursal_id)


async def _plan_minimo(conn: asyncpg.Connection, funcion: str) -> str | None:
    # funcion viene de FUNCIONES_PLAN (nunca del usuario), por eso se puede interpolar
    return await conn.fetchval(
        f"SELECT nombre FROM plan WHERE activo AND {funcion} ORDER BY orden LIMIT 1"
    )


async def exigir_funcion(
    conn: asyncpg.Connection, staff: dict, funcion: str | None, sucursal_id: UUID | None = None
) -> None:
    """Corta con 402/403 si la sucursal (la del empleado, o la indicada) no puede usar la
    funcion. El ADMIN de la plataforma pasa siempre."""
    if es_admin_plataforma(staff):
        return
    sucursal = sucursal_id or staff["sucursal_id"]
    if sucursal is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tu usuario no esta asignado a ninguna sucursal",
        )
    plan = await plan_de_sucursal(conn, sucursal)
    bloqueo = evaluar_acceso(plan, funcion)
    if bloqueo is None:
        return
    if bloqueo[0] == status.HTTP_403_FORBIDDEN and funcion is not None:
        # solo cuando corta por plan se busca a que plan subir (una consulta menos por request)
        bloqueo = evaluar_acceso(plan, funcion, await _plan_minimo(conn, funcion))
    raise HTTPException(status_code=bloqueo[0], detail=bloqueo[1])


def requiere_funcion_plan(funcion: str | None, *codigos: str):
    """Permiso de CU13 (uno de `codigos`) + plan del tenant que habilite `funcion` y este al
    dia. funcion=None solo exige la suscripcion vigente."""
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


async def exigir_limite(conn: asyncpg.Connection, sucursal_id: UUID, recurso: str) -> None:
    """recurso: 'empleados' o 'cajas'. 409 si el plan de la sucursal ya llego a su tope."""
    plan = await plan_de_sucursal(conn, sucursal_id)
    if plan is None:
        return  # sucursal sin suscripcion (base vieja): no se limita
    tope = plan["max_empleados"] if recurso == "empleados" else plan["max_cajas"]
    if tope is None:
        return
    if recurso == "empleados":
        actuales = await conn.fetchval(
            """
            SELECT COUNT(*) FROM empleado e JOIN usuario u ON u.id = e.usuario_id
             WHERE e.sucursal_id = $1 AND e.activo AND u.activo
            """,
            sucursal_id,
        )
    else:
        actuales = await conn.fetchval(
            "SELECT COUNT(*) FROM caja WHERE sucursal_id = $1 AND activa", sucursal_id
        )
    if actuales >= tope:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                f"El plan {plan['plan_nombre']} de la sucursal admite hasta {tope} {recurso}: "
                "subi de plan para agregar mas"
            ),
        )
