"""Job de avisos salientes: correo del comprobante y push al celular.

Por que un job y no mandarlo en el sitio donde nace el aviso: hoy las notificaciones se insertan
con SQL crudo en una decena de lugares (webhook de Stripe, caja, reservas, traspasos...), casi
todos DENTRO de una transaccion que todavia no se confirmo, y mandar un correo o un push desde ahi
tendria que (a) esperar a la red con la fila bloqueada y (b) arriesgar avisar de algo que luego se
deshace. Con una cola leida por el job:

  - cualquier INSERT en `notificacion` y cualquier `comprobante` nuevo se avisa solo, sin tocar a
    quien los crea;
  - solo se avisa de lo ya confirmado (el job ve unicamente filas commiteadas);
  - un correo o push que falla no afecta al pago.

Cada fila se "reclama" con un UPDATE ... FOR UPDATE SKIP LOCKED antes de mandarla, asi dos
instancias del backend no mandan lo mismo dos veces. El push es "a lo sumo una vez" (si FCM falla
no se reintenta: el aviso sigue en la campana); el correo se reintenta hasta MAX_INTENTOS_CORREO.
"""

import asyncio
import logging

import asyncpg

from app.core.comprobante import MAX_INTENTOS_CORREO, enviar_comprobante
from app.core.correo import correo_configurado
from app.core.db import get_pool
from app.core.push import enviar_push, push_configurado

log = logging.getLogger(__name__)

# Lo mas viejo que el job todavia manda. Evita un diluvio si el backend estuvo caido un dia.
VENTANA = "interval '1 day'"


async def procesar_correos_pendientes(conn: asyncpg.Connection) -> int:
    """Manda el comprobante a las compras recien aprobadas. Devuelve cuantos correos salieron."""
    if not correo_configurado():
        return 0
    reclamados = await conn.fetch(
        f"""
        UPDATE comprobante SET correo_intentos = correo_intentos + 1
        WHERE id IN (
            SELECT c.id FROM comprobante c
            JOIN venta v ON v.id = c.venta_id
            WHERE c.correo_enviado_en IS NULL
              AND c.correo_intentos < $1
              AND c.emitido_en > now() - {VENTANA}
              AND v.usuario_id IS NOT NULL
            ORDER BY c.emitido_en
            LIMIT 10
            FOR UPDATE OF c SKIP LOCKED
        )
        RETURNING venta_id
        """,
        MAX_INTENTOS_CORREO,
    )
    enviados = 0
    for fila in reclamados:
        if await enviar_comprobante(conn, fila["venta_id"]):
            enviados += 1
    return enviados


async def procesar_push_pendientes(conn: asyncpg.Connection) -> int:
    """Convierte en push las notificaciones nuevas de la campana. Devuelve cuantos avisos se
    mandaron (no cuantos celulares)."""
    reclamadas = await conn.fetch(
        f"""
        UPDATE notificacion n SET push_enviado_en = now()
        WHERE n.id IN (
            SELECT id FROM notificacion
            WHERE push_enviado_en IS NULL AND fecha > now() - {VENTANA}
            ORDER BY fecha
            LIMIT 50
            FOR UPDATE SKIP LOCKED
        )
        RETURNING n.id, n.usuario_id, n.titulo, n.mensaje, n.tipo::text AS tipo,
                  n.entidad_tipo, n.entidad_id
        """
    )
    # Las que quedaron mas viejas que la ventana se cierran sin mandar, para que el indice parcial
    # no acumule filas que nunca se van a avisar.
    await conn.execute(
        f"UPDATE notificacion SET push_enviado_en = now() "
        f"WHERE push_enviado_en IS NULL AND fecha <= now() - {VENTANA}"
    )
    if not reclamadas or not push_configurado():
        return 0

    usuarios = list({fila["usuario_id"] for fila in reclamadas})
    dispositivos = await conn.fetch(
        "SELECT usuario_id, token FROM dispositivo_push WHERE usuario_id = ANY($1::uuid[])",
        usuarios,
    )
    tokens_de: dict = {}
    for fila in dispositivos:
        tokens_de.setdefault(fila["usuario_id"], []).append(fila["token"])

    mandados = 0
    muertos: list[str] = []
    for fila in reclamadas:
        tokens = tokens_de.get(fila["usuario_id"])
        if not tokens:
            continue
        muertos += await enviar_push(
            tokens,
            fila["titulo"],
            fila["mensaje"],
            {
                "tipo": fila["tipo"],
                "entidad_tipo": fila["entidad_tipo"],
                "entidad_id": fila["entidad_id"],
                "notificacion_id": fila["id"],
            },
        )
        mandados += 1
    if muertos:
        await conn.execute("DELETE FROM dispositivo_push WHERE token = ANY($1::text[])", muertos)
    return mandados


async def job_avisos(intervalo_segundos: int) -> None:
    """Loop del lifespan. Cada tarea tiene su propio try: que falle una no frena la otra, y ningun
    error tumba el backend."""
    while True:
        try:
            pool = get_pool()
            async with pool.acquire() as conn:
                try:
                    correos = await procesar_correos_pendientes(conn)
                    if correos:
                        log.info("job_avisos: %s comprobante(s) enviado(s) por correo", correos)
                except Exception:  # noqa: BLE001
                    log.exception("job_avisos: fallo el envio de comprobantes")
                try:
                    pushes = await procesar_push_pendientes(conn)
                    if pushes:
                        log.info("job_avisos: %s aviso(s) mandado(s) como push", pushes)
                except Exception:  # noqa: BLE001
                    log.exception("job_avisos: fallo el envio de push")
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001
            log.exception("job_avisos: fallo un ciclo, reintenta en el proximo")
        await asyncio.sleep(intervalo_segundos)
