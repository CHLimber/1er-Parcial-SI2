"""Envio de correos (hoy solo la recuperacion de cuenta).

Dos vias, en este orden:

1. **Resend** (API HTTPS, puerto 443) si hay `RESEND_API_KEY`. Es la que sirve en Railway, que
   bloquea el SMTP saliente (25/465/587) fuera del plan Pro.
2. **SMTP** si hay `SMTP_HOST` (Gmail con contrasena de aplicacion, Brevo, etc.). Sirve en local.

Sin ninguna de las dos no se envia nada: `enviar_correo` devuelve False y quien llama decide que
hacer (la recuperacion deja el enlace en el log). smtplib bloquea, asi que se corre en un hilo
para no frenar el event loop.
"""

import asyncio
import logging
import smtplib
from email.message import EmailMessage

import httpx

from app.core.config import settings

log = logging.getLogger(__name__)

RESEND_URL = "https://api.resend.com/emails"


def correo_configurado() -> bool:
    return bool(settings.resend_api_key or settings.smtp_host)


def _enviar_smtp(destino: str, asunto: str, texto: str, html: str | None) -> None:
    mensaje = EmailMessage()
    mensaje["From"] = settings.smtp_from or settings.smtp_user
    mensaje["To"] = destino
    mensaje["Subject"] = asunto
    mensaje.set_content(texto)
    if html:
        mensaje.add_alternative(html, subtype="html")
    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=15) as servidor:
        if settings.smtp_starttls:
            servidor.starttls()
        if settings.smtp_user:
            servidor.login(settings.smtp_user, settings.smtp_password)
        servidor.send_message(mensaje)


async def _enviar_resend(destino: str, asunto: str, texto: str, html: str | None) -> None:
    cuerpo = {"from": settings.resend_from, "to": [destino], "subject": asunto, "text": texto}
    if html:
        cuerpo["html"] = html
    async with httpx.AsyncClient(timeout=15) as cliente:
        respuesta = await cliente.post(
            RESEND_URL,
            headers={"Authorization": f"Bearer {settings.resend_api_key}"},
            json=cuerpo,
        )
    if respuesta.status_code >= 400:
        # Resend explica el motivo en el cuerpo (p. ej. dominio sin verificar: solo deja enviar
        # al correo de la propia cuenta); sin esto el log solo diria "fallo".
        raise RuntimeError(f"Resend respondio {respuesta.status_code}: {respuesta.text[:300]}")


async def enviar_correo(destino: str, asunto: str, texto: str, html: str | None = None) -> bool:
    """True si el correo salio. `texto` es el cuerpo plano (y el respaldo de `html`). Un fallo
    del proveedor se registra y devuelve False: el usuario no tiene por que enterarse de por
    que no llego."""
    if not correo_configurado():
        return False
    try:
        if settings.resend_api_key:
            await _enviar_resend(destino, asunto, texto, html)
        else:
            await asyncio.to_thread(_enviar_smtp, destino, asunto, texto, html)
    except (OSError, smtplib.SMTPException, httpx.HTTPError, RuntimeError):
        log.exception("No se pudo enviar el correo a %s", destino)
        return False
    return True
