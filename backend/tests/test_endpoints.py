"""Tests de endpoints con httpx/TestClient que NO tocan Postgres.

app.main arma un solo FastAPI() con lifespan (connect_pool contra la base real), asi que estos
tests usan TestClient(app) SIN el bloque `with` -- Starlette solo corre startup/shutdown cuando
el TestClient se usa como context manager, asi que el pool nunca se crea y no hace falta un
Postgres real para estos casos.

Las rutas protegidas resuelven asyncpg.Connection = Depends(get_connection) ANTES de ejecutar el
cuerpo de la dependencia de autorizacion (FastAPI resuelve todo el arbol de dependencias antes de
llamar al endpoint), asi que hasta el caso "401 sin token" necesita `get_connection` pisado con
dependency_overrides para no golpear el pool real -- no cambia nada de produccion, es pura
plomeria de test."""

from collections.abc import AsyncGenerator

import pytest
from fastapi.testclient import TestClient

from app.core.db import get_connection
from app.core.deps import get_current_usuario
from app.main import app


async def _fake_get_connection() -> AsyncGenerator[None, None]:
    yield None


@pytest.fixture
def client():
    # Deliberadamente SIN "with": Starlette solo corre el lifespan (connect_pool contra
    # Postgres real) cuando el TestClient se usa como context manager. Sin el "with" nunca se
    # llama a connect_pool, asi que no hace falta Postgres levantado para estos tests.
    app.dependency_overrides[get_connection] = _fake_get_connection
    try:
        yield TestClient(app, raise_server_exceptions=False)
    finally:
        app.dependency_overrides.pop(get_connection, None)


def test_endpoint_protegido_sin_token_devuelve_401(client):
    # /notificaciones exige sesion (get_current_usuario) y no necesita ningun permiso extra.
    respuesta = client.get("/notificaciones")
    assert respuesta.status_code == 401


def test_endpoint_protegido_con_token_invalido_devuelve_401(client):
    respuesta = client.get(
        "/notificaciones", headers={"Authorization": "Bearer token-que-no-existe"}
    )
    assert respuesta.status_code == 401


def test_asistente_chat_sin_anthropic_api_key_devuelve_503(client):
    # conftest.py fija ANTHROPIC_API_KEY="" (variable de entorno de prueba, nunca la real):
    # _cliente_ia() en app/modules/asistente/router.py responde 503 antes de tocar la base o
    # de llamar a la API de Claude.
    app.dependency_overrides[get_current_usuario] = lambda: {"id": "cliente-de-prueba", "tipo": "CLIENTE"}
    try:
        respuesta = client.post(
            "/asistente/chat",
            json={"mensajes": [{"rol": "user", "texto": "hola, busco un vestido"}]},
        )
    finally:
        app.dependency_overrides.pop(get_current_usuario, None)
    assert respuesta.status_code == 503


def test_asistente_chat_para_staff_devuelve_403_antes_de_mirar_la_api_key():
    # _exigir_cliente corre ANTES de _cliente_ia(): un STAFF nunca deberia llegar a depender de
    # si hay o no ANTHROPIC_API_KEY.
    app.dependency_overrides[get_connection] = _fake_get_connection
    app.dependency_overrides[get_current_usuario] = lambda: {"id": "staff-de-prueba", "tipo": "STAFF"}
    try:
        c = TestClient(app, raise_server_exceptions=False)
        respuesta = c.post(
            "/asistente/chat",
            json={"mensajes": [{"rol": "user", "texto": "hola"}]},
        )
    finally:
        app.dependency_overrides.pop(get_connection, None)
        app.dependency_overrides.pop(get_current_usuario, None)
    assert respuesta.status_code == 403


def test_healthcheck_raiz_no_requiere_auth(client):
    # cualquier ruta publica que no dependa de get_current_usuario debe responder sin 401;
    # /docs de FastAPI sirve como smoke test de que la app arranca sin romperse.
    respuesta = client.get("/docs")
    assert respuesta.status_code == 200
