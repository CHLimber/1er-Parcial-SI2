from uuid import UUID

import asyncpg
import stripe
from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.core.config import settings
from app.core.db import get_connection
from app.core.deps import get_current_usuario
from app.modules.pagos.schemas import ConfigPagoOut, InformarPagoIn, InformarPagoOut, WebhookOut
from app.modules.pagos.servicio import (
    confirmar_aprobado,
    confirmar_rechazado,
    notificar_cajeros,
)

router = APIRouter(prefix="/pagos", tags=["pagos"])

stripe.api_key = settings.stripe_secret_key


@router.get("/config", response_model=ConfigPagoOut)
async def obtener_config() -> ConfigPagoOut:
    return ConfigPagoOut(stripe_publishable_key=settings.stripe_publishable_key)


@router.post("/webhook/stripe", response_model=WebhookOut, include_in_schema=False)
async def webhook_stripe(
    request: Request,
    conn: asyncpg.Connection = Depends(get_connection),
) -> WebhookOut:
    """Webhook real de Stripe (CU06). El payload llega firmado en el header Stripe-Signature y se
    valida contra STRIPE_WEBHOOK_SECRET antes de confiar en nada -- sin esa validacion cualquiera
    podria llamar a este endpoint y aprobar un pago sin haber pagado."""
    payload = await request.body()
    firma = request.headers.get("stripe-signature", "")
    try:
        event = stripe.Webhook.construct_event(payload, firma, settings.stripe_webhook_secret)
    except (ValueError, stripe.error.SignatureVerificationError) as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Firma de webhook invalida"
        ) from error

    tipo = event["type"]
    objeto = event["data"]["object"]

    if tipo == "checkout.session.completed":
        # CU06 canal WEB: Checkout Session embebida.
        if objeto.get("payment_status") != "paid":
            # metodo de pago asincrono (p.ej. transferencia): esperamos el evento de resultado
            return WebhookOut(procesado=False, mensaje="Pago asincrono pendiente de confirmacion")
        aprobado = True
    elif tipo == "checkout.session.async_payment_succeeded":
        aprobado = True
    elif tipo in ("checkout.session.async_payment_failed", "checkout.session.expired"):
        # E1: timeout/expiracion de la sesion de pago -- se trata como rechazo
        aprobado = False
    elif tipo == "payment_intent.succeeded":
        # CU06 canal MOVIL: PaymentIntent confirmado in-app por el PaymentSheet de flutter_stripe.
        aprobado = True
    elif tipo == "payment_intent.canceled":
        # Terminal de verdad (alguien cancelo el PaymentIntent explicitamente). A diferencia de
        # Checkout Session, un PaymentIntent no expira solo y "payment_intent.payment_failed" NO
        # se trata aca como rechazo: ese evento se dispara en CADA intento de tarjeta declinada
        # dentro del mismo PaymentSheet (el cliente puede seguir probando otra tarjeta sin cerrarlo)
        # -- tratarlo como rechazo anularia el pedido mientras la clienta todavia esta reintentando.
        aprobado = False
    else:
        return WebhookOut(procesado=False, mensaje=f"Evento ignorado: {tipo}")

    return await _procesar_evento(
        conn,
        pasarela="STRIPE",
        id_transaccion=objeto["id"],
        evento_id=event["id"],
        aprobado=aprobado,
    )


@router.post("/qr/{venta_id}/informar", response_model=InformarPagoOut)
async def informar_pago_qr(
    venta_id: UUID,
    body: InformarPagoIn,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> InformarPagoOut:
    """2.19.1.c: la clienta avisa que ya escaneo el QR y deposito. NO aprueba nada -- antes la
    propia clienta pulsaba "Aprobar" en /pago-simulado contra un webhook publico, sin
    autenticacion. Ahora solo deja constancia (informado_en + referencia opcional) y avisa a los
    cajeros de la sucursal, que verifican el deposito y aprueban o rechazan desde caja
    (POST /caja/pagos/{pago_id}/aprobar|rechazar). Idempotente: informar de nuevo solo actualiza
    la referencia, sin volver a notificar."""
    if usuario["tipo"] != "CLIENTE":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="Solo la clienta informa su propio pago"
        )

    referencia = body.referencia.strip() if body.referencia else None
    async with conn.transaction():
        pago = await conn.fetchrow(
            """
            SELECT p.id, p.estado, p.informado_en, v.sucursal_id, v.numero, v.total
            FROM pago p
            JOIN venta v ON v.id = p.venta_id
            WHERE p.venta_id = $1 AND v.usuario_id = $2 AND p.pasarela = 'QR'
            ORDER BY p.creado_en DESC
            LIMIT 1
            FOR UPDATE OF p
            """,
            venta_id,
            usuario["id"],
        )
        if pago is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND, detail="No tenes un pago QR para ese pedido"
            )
        if pago["estado"] != "PENDIENTE":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Ese pago ya fue resuelto ({pago['estado']})",
            )

        fila = await conn.fetchrow(
            """
            UPDATE pago
               SET informado_en = COALESCE(informado_en, now()),
                   referencia_cliente = COALESCE($2, referencia_cliente)
             WHERE id = $1
            RETURNING informado_en, referencia_cliente
            """,
            pago["id"],
            referencia,
        )
        if pago["informado_en"] is None:
            await notificar_cajeros(
                conn,
                pago["sucursal_id"],
                venta_id,
                "Pago QR por verificar",
                f"La clienta informo el pago QR del pedido {pago['numero']} "
                f"(Bs {pago['total']}). Verifica el deposito y aprobalo desde caja.",
            )

    return InformarPagoOut(
        venta_id=venta_id,
        pago_id=pago["id"],
        pago_estado=pago["estado"],
        informado_en=fila["informado_en"],
        referencia_cliente=fila["referencia_cliente"],
        mensaje="Avisamos a la sucursal. Te notificamos cuando verifiquen el deposito.",
    )


async def _procesar_evento(
    conn: asyncpg.Connection,
    pasarela: str,
    id_transaccion: str,
    evento_id: str,
    aprobado: bool,
) -> WebhookOut:
    pago = await conn.fetchrow(
        "SELECT id, venta_id FROM pago WHERE pasarela = $1 AND id_transaccion = $2",
        pasarela,
        id_transaccion,
    )
    if pago is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="No existe un pago con esa transaccion"
        )

    async with conn.transaction():
        try:
            await conn.execute(
                "INSERT INTO evento_pasarela (evento_externo_id, pasarela, pago_id) VALUES ($1, $2, $3)",
                evento_id,
                pasarela,
                pago["id"],
            )
        except asyncpg.UniqueViolationError:
            # E2: webhook duplicado -- reintento de la pasarela, se ignora sin volver a cobrar
            return WebhookOut(
                procesado=False, mensaje="Este evento ya habia sido procesado antes (idempotencia)"
            )

        pago_actual = await conn.fetchrow(
            "SELECT estado FROM pago WHERE id = $1 FOR UPDATE", pago["id"]
        )
        if pago_actual["estado"] != "PENDIENTE":
            return WebhookOut(
                procesado=False,
                pago_estado=pago_actual["estado"],
                mensaje="Este pago ya habia sido resuelto antes",
            )

        venta = await conn.fetchrow(
            "SELECT id, sucursal_id, carrito_id, reserva_id, promocion_id, numero FROM venta "
            "WHERE id = $1 FOR UPDATE",
            pago["venta_id"],
        )

        if not aprobado:
            resultado = await confirmar_rechazado(conn, pago["id"], dict(venta))
        else:
            resultado = await confirmar_aprobado(conn, pago["id"], dict(venta))
        return WebhookOut(procesado=True, **resultado)
