"""Push al celular con Firebase Cloud Messaging (API HTTP v1).

Sin dependencia nueva: la API v1 pide un token OAuth2 que se saca firmando un JWT con la clave de
la cuenta de servicio (python-jose, que ya esta por el login) y cambiandolo por un access token en
Google. httpx ya esta por Resend.

`FIREBASE_CREDENCIALES_JSON` vacio = el push esta apagado: `enviar_push` devuelve sin hacer nada y
el resto del sistema (campana, correo) sigue igual.

Un token que Firebase da por muerto (la app se desinstalo, el usuario revoco el permiso) se
devuelve en la lista de invalidos para que quien llama lo borre de `dispositivo_push`.
"""

import base64
import json
import logging
import time
from functools import lru_cache

import httpx
from jose import jwt

from app.core.config import settings

log = logging.getLogger(__name__)

ALCANCE = "https://www.googleapis.com/auth/firebase.messaging"
URL_ENVIO = "https://fcm.googleapis.com/v1/projects/{proyecto}/messages:send"
CANAL_ANDROID = "fashionstore_avisos"  # el movil crea un canal con este id (push_service.dart)

_acceso: dict = {"token": None, "vence": 0.0}


@lru_cache(maxsize=1)
def _credenciales() -> dict | None:
    crudo = settings.firebase_credenciales_json.strip()
    if not crudo:
        return None
    try:
        if not crudo.startswith("{"):
            crudo = base64.b64decode(crudo).decode("utf-8")
        datos = json.loads(crudo)
        for campo in ("project_id", "client_email", "private_key"):
            if not datos.get(campo):
                raise ValueError(f"falta {campo}")
    except (ValueError, UnicodeDecodeError):
        log.exception("FIREBASE_CREDENCIALES_JSON no es una cuenta de servicio valida: push apagado")
        return None
    return datos


def push_configurado() -> bool:
    return _credenciales() is not None


async def _token_acceso(cliente: httpx.AsyncClient) -> str:
    """Access token de Google, cacheado hasta un minuto antes de que venza (dura 1 hora)."""
    ahora = time.time()
    if _acceso["token"] and ahora < _acceso["vence"] - 60:
        return _acceso["token"]
    creds = _credenciales()
    destino = creds.get("token_uri") or "https://oauth2.googleapis.com/token"
    asercion = jwt.encode(
        {
            "iss": creds["client_email"],
            "scope": ALCANCE,
            "aud": destino,
            "iat": int(ahora),
            "exp": int(ahora) + 3600,
        },
        creds["private_key"],
        algorithm="RS256",
    )
    respuesta = await cliente.post(
        destino,
        data={"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": asercion},
    )
    respuesta.raise_for_status()
    cuerpo = respuesta.json()
    _acceso["token"] = cuerpo["access_token"]
    _acceso["vence"] = ahora + int(cuerpo.get("expires_in", 3600))
    return _acceso["token"]


def armar_mensaje(token: str, titulo: str, cuerpo: str, datos: dict[str, str]) -> dict:
    """Mensaje FCM v1. `data` solo admite strings; `notification` lo dibuja el sistema aunque la
    app este cerrada, y con la app abierta lo recibe el handler de primer plano."""
    return {
        "message": {
            "token": token,
            "notification": {"title": titulo, "body": cuerpo},
            "data": {clave: str(valor) for clave, valor in datos.items() if valor is not None},
            "android": {
                "priority": "HIGH",
                "notification": {"channel_id": CANAL_ANDROID},
            },
        }
    }


async def enviar_push(
    tokens: list[str], titulo: str, cuerpo: str, datos: dict[str, str] | None = None
) -> list[str]:
    """Manda el aviso a cada token. Devuelve los tokens invalidos (para borrarlos). Un fallo de
    red o de credenciales se registra y no levanta: un push que no sale no puede romper el job."""
    if not tokens or not push_configurado():
        return []
    creds = _credenciales()
    invalidos: list[str] = []
    try:
        async with httpx.AsyncClient(timeout=15) as cliente:
            acceso = await _token_acceso(cliente)
            for token in tokens:
                respuesta = await cliente.post(
                    URL_ENVIO.format(proyecto=creds["project_id"]),
                    headers={"Authorization": f"Bearer {acceso}"},
                    json=armar_mensaje(token, titulo, cuerpo, datos or {}),
                )
                if respuesta.status_code == 200:
                    continue
                estado = ""
                try:
                    estado = respuesta.json().get("error", {}).get("status", "")
                except ValueError:
                    pass
                # UNREGISTERED: token muerto. INVALID_ARGUMENT: token mal formado.
                if estado in ("UNREGISTERED", "INVALID_ARGUMENT", "NOT_FOUND"):
                    invalidos.append(token)
                else:
                    log.warning("FCM respondio %s: %s", respuesta.status_code, respuesta.text[:300])
    except (httpx.HTTPError, KeyError, ValueError):
        log.exception("No se pudo mandar el push")
    return invalidos
