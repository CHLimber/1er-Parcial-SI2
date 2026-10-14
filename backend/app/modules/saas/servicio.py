"""Confirmacion del pago de una suscripcion (PENDIENTES 5.5). Lo llaman el webhook de Stripe
(pagos/router.py, metadata tipo=SUSCRIPCION), la verificacion manual del retorno del Checkout y
el pago manual del ADMIN. Idempotente: un pago que ya no esta PENDIENTE no se vuelve a aplicar."""

from calendar import monthrange
from datetime import datetime, timezone
from uuid import UUID

import asyncpg


def sumar_meses(desde: datetime, meses: int) -> datetime:
    """Mismo dia N meses despues; si ese mes es mas corto, el ultimo dia (31/01 + 1 = 28/02)."""
    mes0 = desde.month - 1 + meses
    anio = desde.year + mes0 // 12
    mes = mes0 % 12 + 1
    dia = min(desde.day, monthrange(anio, mes)[1])
    return desde.replace(year=anio, month=mes, day=dia)


def nuevo_periodo(vence_actual: datetime, meses: int, ahora: datetime | None = None) -> tuple[datetime, datetime]:
    """Una renovacion se suma al final del periodo vigente; si ya vencio, arranca hoy (no se
    cobran los dias en que estuvo vencida)."""
    ahora = ahora or datetime.now(timezone.utc)
    desde = max(vence_actual, ahora)
    return desde, sumar_meses(desde, meses)


async def aplicar_pago(conn: asyncpg.Connection, pago_id: UUID, id_transaccion: str | None = None) -> bool:
    """Aprueba el pago y extiende la suscripcion con el plan pagado. False si ya estaba resuelto."""
    async with conn.transaction():
        pago = await conn.fetchrow(
            """
            SELECT ps.id, ps.suscripcion_id, ps.plan_id, ps.meses, ps.estado::text AS estado,
                   su.vence_en, su.sucursal_id
            FROM pago_suscripcion ps
            JOIN suscripcion su ON su.id = ps.suscripcion_id
            WHERE ps.id = $1
            FOR UPDATE OF ps, su
            """,
            pago_id,
        )
        if pago is None or pago["estado"] != "PENDIENTE":
            return False
        desde, hasta = nuevo_periodo(pago["vence_en"], pago["meses"])
        await conn.execute(
            """
            UPDATE pago_suscripcion
               SET estado = 'APROBADO', confirmado_en = now(), periodo_desde = $2, periodo_hasta = $3,
                   id_transaccion = COALESCE($4, id_transaccion)
             WHERE id = $1
            """,
            pago_id,
            desde,
            hasta,
            id_transaccion,
        )
        await conn.execute(
            """
            UPDATE suscripcion
               SET plan_id = $2, estado = 'ACTIVA', vence_en = $3, actualizado_en = now()
             WHERE id = $1
            """,
            pago["suscripcion_id"],
            pago["plan_id"],
            hasta,
        )
        # Aviso al personal con permiso de suscripcion de la sucursal (mismo canal que el resto)
        await conn.execute(
            """
            INSERT INTO notificacion (usuario_id, tipo, titulo, mensaje)
            SELECT e.usuario_id, 'SUSCRIPCION', 'Suscripcion renovada',
                   'El pago de la suscripcion se aprobo. Vigente hasta el '
                   || to_char($2::timestamptz, 'DD/MM/YYYY') || '.'
              FROM empleado e
             WHERE e.sucursal_id = $1 AND e.activo AND e.cargo = 'ENCARGADO'
            """,
            pago["sucursal_id"],
            hasta,
        )
    return True


async def rechazar_pago(conn: asyncpg.Connection, pago_id: UUID) -> None:
    await conn.execute(
        "UPDATE pago_suscripcion SET estado = 'RECHAZADO' WHERE id = $1 AND estado = 'PENDIENTE'",
        pago_id,
    )


async def procesar_evento_stripe(
    conn: asyncpg.Connection, pago_id: UUID, id_transaccion: str, evento_id: str, aprobado: bool
) -> bool:
    """Webhook: idempotencia por evento_pasarela (mismo registro que las ventas). Todo en una
    transaccion: si aplicar el pago falla, el evento tampoco queda registrado y el reintento de
    Stripe lo vuelve a procesar."""
    async with conn.transaction():
        nuevo = await conn.fetchval(
            """
            INSERT INTO evento_pasarela (evento_externo_id, pasarela)
            VALUES ($1, 'STRIPE') ON CONFLICT DO NOTHING RETURNING evento_externo_id
            """,
            evento_id,
        )
        if nuevo is None:
            return False
        if aprobado:
            return await aplicar_pago(conn, pago_id, id_transaccion)
        await rechazar_pago(conn, pago_id)
        return True
