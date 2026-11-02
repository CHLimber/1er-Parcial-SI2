"""enviar_correo: Resend por HTTPS tiene prioridad sobre SMTP y un fallo devuelve False."""

import asyncio

import httpx

from app.core import correo
from app.core.config import settings


def _con(monkeypatch, **valores):
    for nombre in ("resend_api_key", "smtp_host"):
        monkeypatch.setattr(settings, nombre, valores.get(nombre, ""))


def _cliente_falso(monkeypatch, status):
    pedidos = []

    def responder(request: httpx.Request) -> httpx.Response:
        pedidos.append(request)
        return httpx.Response(status, json={"id": "x"} if status < 400 else {"message": "no"})

    real = httpx.AsyncClient
    monkeypatch.setattr(
        correo.httpx, "AsyncClient",
        lambda **kw: real(transport=httpx.MockTransport(responder), **kw),
    )
    return pedidos


def test_sin_configurar_no_envia(monkeypatch):
    _con(monkeypatch)
    assert asyncio.run(correo.enviar_correo("a@b.bo", "hola", "texto")) is False


def test_resend_manda_bearer_y_destino(monkeypatch):
    _con(monkeypatch, resend_api_key="re_123", smtp_host="smtp.x")
    pedidos = _cliente_falso(monkeypatch, 200)
    assert asyncio.run(correo.enviar_correo("a@b.bo", "hola", "texto")) is True
    assert pedidos[0].headers["authorization"] == "Bearer re_123"
    assert b'"to":["a@b.bo"]' in pedidos[0].content.replace(b" ", b"")


def test_resend_con_error_devuelve_false(monkeypatch):
    _con(monkeypatch, resend_api_key="re_123")
    _cliente_falso(monkeypatch, 403)
    assert asyncio.run(correo.enviar_correo("a@b.bo", "hola", "texto")) is False
