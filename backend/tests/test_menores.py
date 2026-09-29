"""JWT_SECRET de ejemplo en Railway y cancelacion de PaymentIntents del movil abandonados."""

from uuid import uuid4

import pytest
import stripe

from app.core import jobs
from app.core.config import JWT_SECRET_DE_EJEMPLO, Settings, verificar_jwt_secret


def _ajustes(secreto: str) -> Settings:
    return Settings(jwt_secret=secreto)


def test_jwt_secret_de_ejemplo_corta_el_arranque_en_railway(monkeypatch):
    monkeypatch.setenv("RAILWAY_ENVIRONMENT", "production")
    with pytest.raises(RuntimeError):
        verificar_jwt_secret(_ajustes(JWT_SECRET_DE_EJEMPLO))


def test_jwt_secret_vacio_corta_el_arranque_en_railway(monkeypatch):
    monkeypatch.setenv("RAILWAY_ENVIRONMENT", "production")
    with pytest.raises(RuntimeError):
        verificar_jwt_secret(_ajustes(""))


def test_jwt_secret_de_ejemplo_en_local_solo_avisa(monkeypatch, caplog):
    monkeypatch.delenv("RAILWAY_ENVIRONMENT", raising=False)
    verificar_jwt_secret(_ajustes(JWT_SECRET_DE_EJEMPLO))
    assert "JWT_SECRET" in caplog.text


def test_jwt_secret_propio_en_railway_arranca(monkeypatch):
    monkeypatch.setenv("RAILWAY_ENVIRONMENT", "production")
    verificar_jwt_secret(_ajustes("un-secreto-largo-de-verdad"))


# --- PaymentIntents vencidos ---------------------------------------------------------------------


class _Transaccion:
    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False


class _Conexion:
    def __init__(self, candidatos, fila_bloqueada):
        self.candidatos = candidatos
        self.fila_bloqueada = fila_bloqueada

    def transaction(self):
        return _Transaccion()

    async def fetch(self, sql, *args):
        return self.candidatos

    async def fetchrow(self, sql, *args):
        return self.fila_bloqueada


@pytest.fixture
def con_stripe(monkeypatch):
    monkeypatch.setattr(jobs.settings, "stripe_secret_key", "sk_test_falsa")
    rechazados = []

    async def _rechazar(conn, pago_id, venta, mensaje_cliente=None):
        rechazados.append(pago_id)

    monkeypatch.setattr(jobs, "confirmar_rechazado", _rechazar)
    return rechazados


def _fila(pago_id):
    return {
        "pago_id": pago_id, "id": uuid4(), "sucursal_id": uuid4(), "carrito_id": uuid4(),
        "reserva_id": None, "promocion_id": None, "numero": "V-TEST",
    }


async def test_payment_intent_vencido_se_cancela_en_stripe_y_se_anula(monkeypatch, con_stripe):
    pago_id = uuid4()
    cancelados = []
    monkeypatch.setattr(stripe.PaymentIntent, "cancel", lambda pi: cancelados.append(pi))
    conn = _Conexion([{"pago_id": pago_id, "id_transaccion": "pi_123"}], _fila(pago_id))

    assert await jobs.cancelar_payment_intents_vencidos(conn) == 1
    assert cancelados == ["pi_123"]
    assert con_stripe == [pago_id]


async def test_si_stripe_no_deja_cancelar_no_se_anula(monkeypatch, con_stripe):
    # p.ej. el PaymentIntent ya se cobro: lo resuelve el webhook payment_intent.succeeded
    def _falla(pi):
        raise stripe.error.InvalidRequestError("ya esta succeeded", None)

    monkeypatch.setattr(stripe.PaymentIntent, "cancel", _falla)
    pago_id = uuid4()
    conn = _Conexion([{"pago_id": pago_id, "id_transaccion": "pi_123"}], _fila(pago_id))

    assert await jobs.cancelar_payment_intents_vencidos(conn) == 0
    assert con_stripe == []


async def test_si_el_webhook_ya_lo_resolvio_no_se_anula_dos_veces(monkeypatch, con_stripe):
    monkeypatch.setattr(stripe.PaymentIntent, "cancel", lambda pi: None)
    conn = _Conexion([{"pago_id": uuid4(), "id_transaccion": "pi_123"}], None)

    assert await jobs.cancelar_payment_intents_vencidos(conn) == 0
    assert con_stripe == []


async def test_sin_clave_de_stripe_no_hace_nada(monkeypatch):
    monkeypatch.setattr(jobs.settings, "stripe_secret_key", "")
    assert await jobs.cancelar_payment_intents_vencidos(object()) == 0
