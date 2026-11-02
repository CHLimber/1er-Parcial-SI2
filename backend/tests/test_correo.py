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


def test_plantilla_recuperacion_trae_enlace_y_vigencia():
    from app.core.correo_plantillas import correo_recuperacion

    enlace = "https://tienda.bo/restablecer-password?token=abc.def&x=1"
    asunto, texto, html = correo_recuperacion("Ana", enlace, 30)
    assert "contraseña" in asunto
    assert enlace in texto and "30 minutos" in texto
    assert "token=abc.def&amp;x=1" in html  # el & va escapado dentro del href
    assert "30 minutos" in html and "Hola, Ana" in html


def test_plantilla_escapa_el_nombre_para_no_inyectar_html():
    from app.core.correo_plantillas import correo_recuperacion

    _, _, html = correo_recuperacion("<script>alert(1)</script>", "https://x.bo/r?token=t", 30)
    assert "<script>" not in html
    assert "&lt;script&gt;" in html


def test_resend_envia_html_y_texto(monkeypatch):
    _con(monkeypatch, resend_api_key="re_123")
    pedidos = _cliente_falso(monkeypatch, 200)
    assert asyncio.run(correo.enviar_correo("a@b.bo", "hola", "plano", "<p>rico</p>")) is True
    cuerpo = pedidos[0].content
    assert b'"html"' in cuerpo and b'"text"' in cuerpo
