"""Webhook de Stripe: eventos sin pago asociado (payment_intent.succeeded de la web), cobros de
intentos ya abandonados (se reembolsan) y cancelar_intento_stripe. Sin Postgres ni Stripe: la
firma se saltea con monkeypatch y la base es falsa. El fixture stripe_falso vive en conftest.py."""

from uuid import uuid4

import pytest
import stripe
from fastapi.testclient import TestClient

from app.core.db import get_connection
from app.main import app
from app.modules.pagos import servicio
from tests.conexion_falsa import ConexionFalsa

PAGO = uuid4()
VENTA = uuid4()


@pytest.fixture
def webhook(monkeypatch):
    """POSTea un evento al webhook con la base falsa dada, sin validar la firma."""

    def enviar(conn: ConexionFalsa, tipo: str, objeto: dict):
        evento = {"id": f"evt_{uuid4().hex}", "type": tipo, "data": {"object": objeto}}
        monkeypatch.setattr(stripe.Webhook, "construct_event", lambda *a: evento)

        async def _conn():
            yield conn

        app.dependency_overrides[get_connection] = _conn
        return TestClient(app, raise_server_exceptions=False).post(
            "/pagos/webhook/stripe", content=b"{}", headers={"stripe-signature": "t=1"}
        )

    yield enviar
    app.dependency_overrides.pop(get_connection, None)


def _conn_con_pago(estado: str | None) -> ConexionFalsa:
    return ConexionFalsa(
        {
            "WHERE pasarela = $1 AND id_transaccion": (
                None if estado is None else {"id": PAGO, "venta_id": VENTA}
            ),
            "SELECT estado FROM pago": {"estado": estado},
        }
    )


# --- 3: evento sin pago asociado -----------------------------------------------------------------


def test_evento_sin_pago_asociado_responde_200_para_que_stripe_no_reintente(webhook):
    # el payment_intent.succeeded que genera el Checkout Session de la web: el pago guarda cs_
    respuesta = webhook(_conn_con_pago(None), "payment_intent.succeeded", {"id": "pi_web"})
    assert respuesta.status_code == 200
    assert respuesta.json()["procesado"] is False


# --- 2: cobro de un intento abandonado -----------------------------------------------------------


def test_cobro_de_un_intento_abandonado_se_reembolsa(webhook, stripe_falso):
    conn = _conn_con_pago("RECHAZADO")
    respuesta = webhook(
        conn, "checkout.session.completed", {"id": "cs_viejo", "payment_status": "paid"}
    )
    assert respuesta.status_code == 200
    assert respuesta.json()["pago_estado"] == "REEMBOLSADO"
    assert stripe_falso["refund"] == ["pi_de_cs_viejo"]
    assert conn.ejecuto("SET estado = 'REEMBOLSADO'")
    assert conn.ejecuto("'Pago reembolsado'")


def test_cobro_movil_de_un_intento_abandonado_se_reembolsa(webhook, stripe_falso):
    respuesta = webhook(_conn_con_pago("RECHAZADO"), "payment_intent.succeeded", {"id": "pi_viejo"})
    assert respuesta.status_code == 200
    assert stripe_falso["refund"] == ["pi_viejo"]


def test_si_stripe_no_acepta_el_reembolso_responde_error_para_reintentar(
    webhook, stripe_falso, monkeypatch
):
    def _falla(payment_intent):
        raise stripe.error.APIConnectionError("sin red")

    monkeypatch.setattr(stripe.Refund, "create", _falla)
    conn = _conn_con_pago("RECHAZADO")
    respuesta = webhook(conn, "payment_intent.succeeded", {"id": "pi_viejo"})
    assert respuesta.status_code == 502
    assert not conn.ejecuto("SET estado = 'REEMBOLSADO'")


@pytest.mark.parametrize("estado", ["APROBADO", "REEMBOLSADO"])
def test_aprobacion_repetida_de_un_pago_resuelto_no_reembolsa(webhook, stripe_falso, estado):
    respuesta = webhook(_conn_con_pago(estado), "payment_intent.succeeded", {"id": "pi_x"})
    assert respuesta.status_code == 200
    assert respuesta.json()["procesado"] is False
    assert stripe_falso["refund"] == []


def test_cancelacion_de_un_intento_ya_abandonado_no_reembolsa(webhook, stripe_falso):
    # el propio checkout cancela el intento al abandonarlo: Stripe avisa con canceled/expired
    respuesta = webhook(_conn_con_pago("RECHAZADO"), "payment_intent.canceled", {"id": "pi_x"})
    assert respuesta.status_code == 200
    assert respuesta.json()["procesado"] is False
    assert stripe_falso["refund"] == []


# --- 2: el checkout cierra en Stripe el intento que abandona -------------------------------------


@pytest.mark.parametrize(
    ("id_transaccion", "llamada"), [("cs_viejo", "expire"), ("pi_viejo", "cancel")]
)
async def test_cancelar_intento_stripe_cierra_session_o_payment_intent(
    stripe_falso, id_transaccion, llamada
):
    await servicio.cancelar_intento_stripe(id_transaccion)
    assert stripe_falso[llamada] == [id_transaccion]


async def test_cancelar_intento_stripe_no_rompe_si_stripe_falla(monkeypatch):
    def _falla(cs):
        raise stripe.error.InvalidRequestError("ya esta complete", None)

    monkeypatch.setattr(stripe.checkout.Session, "expire", _falla)
    await servicio.cancelar_intento_stripe("cs_pagado")  # no levanta
