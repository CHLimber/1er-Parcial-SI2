"""Envio de correos por SMTP (hoy solo la recuperacion de cuenta).

Sin SMTP_HOST no se envia nada: `enviar_correo` devuelve False y quien llama decide que hacer
(la recuperacion deja el enlace en el log). Es smtplib de la libreria estandar, que bloquea, asi
que se corre en un hilo para no frenar el event loop.
"""

import asyncio
import logging
import smtplib
from email.message import EmailMessage

from app.core.config import settings

log = logging.getLogger(__name__)


def correo_configurado() -> bool:
    return bool(settings.smtp_host)


def _enviar(destino: str, asunto: str, texto: str) -> None:
    mensaje = EmailMessage()
    mensaje["From"] = settings.smtp_from or settings.smtp_user
    mensaje["To"] = destino
    mensaje["Subject"] = asunto
    mensaje.set_content(texto)
    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=15) as servidor:
        if settings.smtp_starttls:
            servidor.starttls()
        if settings.smtp_user:
            servidor.login(settings.smtp_user, settings.smtp_password)
        servidor.send_message(mensaje)


async def enviar_correo(destino: str, asunto: str, texto: str) -> bool:
    """True si el correo salio. Un fallo del servidor SMTP se registra y devuelve False: el
    usuario no tiene por que enterarse de por que no llego."""
    if not correo_configurado():
        return False
    try:
        await asyncio.to_thread(_enviar, destino, asunto, texto)
    except (OSError, smtplib.SMTPException):
        log.exception("No se pudo enviar el correo a %s", destino)
        return False
    return True
