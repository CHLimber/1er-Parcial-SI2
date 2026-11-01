"""Token de recuperacion de contrasena, sin tabla.

Es un JWT firmado con el mismo secreto que la sesion, con el claim `uso` (get_current_usuario lo
rechaza como sesion) y la huella del hash de contrasena VIGENTE. Esa huella lo vuelve de un solo
uso sin guardar nada: apenas la contrasena cambia, el token deja de coincidir. Vence a los
`recuperacion_minutos` (30 por defecto).
"""

import hashlib
from datetime import datetime, timedelta, timezone

from jose import JWTError, jwt

from app.core.config import settings

USO = "recuperar_password"


def _huella(password_hash: str) -> str:
    return hashlib.sha256(password_hash.encode("utf-8")).hexdigest()[:24]


def crear_token_recuperacion(usuario_id: str, password_hash: str) -> str:
    expira = datetime.now(timezone.utc) + timedelta(minutes=settings.recuperacion_minutos)
    payload = {"sub": usuario_id, "uso": USO, "huella": _huella(password_hash), "exp": expira}
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def leer_token_recuperacion(token: str) -> tuple[str, str] | None:
    """(id de usuario, huella esperada) o None si el token es invalido, vencio o no es de este uso."""
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except JWTError:
        return None
    if payload.get("uso") != USO or "sub" not in payload or "huella" not in payload:
        return None
    return payload["sub"], payload["huella"]


def huella_coincide(password_hash: str, huella: str) -> bool:
    return _huella(password_hash) == huella
