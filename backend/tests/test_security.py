"""Tests unitarios de app/core/security.py (hash/verify de password con bcrypt, crear y
decodificar JWT). Sin base de datos: usa las variables de entorno de prueba de conftest.py
(JWT_SECRET/JWT_ALGORITHM/JWT_EXPIRE_MINUTES), nunca el JWT_SECRET real."""

from datetime import datetime, timedelta, timezone

from jose import jwt

from app.core.config import settings
from app.core.security import (
    create_access_token,
    decode_access_token,
    hash_password,
    verify_password,
)


def test_hash_password_no_guarda_el_texto_plano():
    hashed = hash_password("Abcdefg1!")
    assert hashed != "Abcdefg1!"
    assert hashed.startswith("$2b$")  # formato bcrypt


def test_verify_password_acepta_la_password_correcta():
    hashed = hash_password("Abcdefg1!")
    assert verify_password("Abcdefg1!", hashed) is True


def test_verify_password_rechaza_la_password_incorrecta():
    hashed = hash_password("Abcdefg1!")
    assert verify_password("otra-password", hashed) is False


def test_hash_password_es_no_determinista_por_el_salt():
    # bcrypt genera un salt nuevo cada vez: dos hashes de la misma password difieren.
    assert hash_password("Abcdefg1!") != hash_password("Abcdefg1!")


def test_create_access_token_incluye_subject_y_claims_extra():
    token = create_access_token("usuario-123", {"tipo": "CLIENTE"})
    payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    assert payload["sub"] == "usuario-123"
    assert payload["tipo"] == "CLIENTE"
    assert "exp" in payload


def test_decode_access_token_devuelve_el_payload_de_un_token_valido():
    token = create_access_token("usuario-123", {"tipo": "STAFF"})
    payload = decode_access_token(token)
    assert payload is not None
    assert payload["sub"] == "usuario-123"
    assert payload["tipo"] == "STAFF"


def test_decode_access_token_devuelve_none_con_token_invalido():
    assert decode_access_token("esto-no-es-un-jwt") is None


def test_decode_access_token_devuelve_none_con_firma_de_otro_secreto():
    payload = {"sub": "usuario-123", "exp": datetime.now(timezone.utc) + timedelta(minutes=5)}
    token_ajeno = jwt.encode(payload, "otro-secreto-distinto", algorithm=settings.jwt_algorithm)
    assert decode_access_token(token_ajeno) is None


def test_decode_access_token_devuelve_none_si_expiro():
    payload = {
        "sub": "usuario-123",
        "exp": datetime.now(timezone.utc) - timedelta(minutes=1),
    }
    token_vencido = jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)
    assert decode_access_token(token_vencido) is None
