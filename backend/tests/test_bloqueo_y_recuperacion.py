"""Reglas de acceso de una empresa (suspendida / suscripcion vencida), validaciones al asignar un
plan y recuperacion de cuenta. Sin Postgres: ConexionFalsa y dependency_overrides."""

import asyncio
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from uuid import UUID, uuid4

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.core.db import get_connection
from app.core.deps import (
    MOTIVO_EMPRESA_SUSPENDIDA,
    MOTIVO_SUSCRIPCION_VENCIDA,
    exigir_empresa_operativa,
    get_staff_actual,
)
from app.main import app
from app.modules.acceso_y_organizacion.usuarios.recuperacion import (
    crear_token_recuperacion,
    huella_coincide,
    leer_token_recuperacion,
)
from app.modules.plataforma_saas.saas import router as saas_router
from tests.conexion_falsa import EMPRESA, ConexionFalsa, staff

USUARIO = uuid4()


def _operativa(activa=True, vigente=True, rol="CAJERO", ruta=None):
    conn = ConexionFalsa({"FROM empresa em": {"activa": activa, "rol": rol, "vigente": vigente}})
    asyncio.run(exigir_empresa_operativa(conn, USUARIO, EMPRESA, ruta))


def test_empresa_al_dia_deja_pasar_a_todos():
    _operativa()


def test_la_plataforma_no_depende_de_ninguna_empresa():
    asyncio.run(exigir_empresa_operativa(ConexionFalsa({}), USUARIO, None))


def test_empresa_suspendida_corta_a_todos_con_403_y_motivo():
    for rol in ("ADMIN", "CAJERO"):
        with pytest.raises(HTTPException) as error:
            _operativa(activa=False, rol=rol)
        assert error.value.status_code == 403
        assert error.value.headers["X-Motivo"] == MOTIVO_EMPRESA_SUSPENDIDA


def test_suscripcion_vencida_corta_al_personal_con_402_y_motivo():
    with pytest.raises(HTTPException) as error:
        _operativa(vigente=False, rol="CAJERO")
    assert error.value.status_code == 402
    assert error.value.headers["X-Motivo"] == MOTIVO_SUSCRIPCION_VENCIDA
    assert "renueve" in error.value.detail


def test_el_admin_entra_con_la_suscripcion_vencida_para_renovar():
    _operativa(vigente=False, rol="ADMIN")


def test_la_sincronizacion_de_lo_registrado_antes_del_vencimiento_no_se_corta():
    _operativa(vigente=False, rol="CAJERO", ruta="/sync/operaciones")


# --- asignar plan: coherencia estado / fecha / empresa --------------------------------------------


@pytest.fixture
def cliente():
    yield
    app.dependency_overrides.clear()


def _asignar(monkeypatch, *, activa=True, estado="ACTIVA", dias=10):
    async def _empresa(conn, empresa_id):
        return SimpleNamespace(activa=activa)

    async def _plan(conn, codigo):
        return {"plan_id": 1, "codigo": "BASICO", "nombre": "Basico"}

    monkeypatch.setattr(saas_router, "_obtener_empresa", _empresa)
    monkeypatch.setattr(saas_router, "_plan_por_codigo", _plan)

    async def _conn():
        yield ConexionFalsa({})

    app.dependency_overrides[get_connection] = _conn
    app.dependency_overrides[get_staff_actual] = lambda: staff(
        empresa_id=None, permisos=["empresas.leer", "empresas.actualizar"]
    )
    vence = datetime.now(timezone.utc) + timedelta(days=dias)
    return TestClient(app, raise_server_exceptions=False).put(
        f"/saas/empresas/{uuid4()}/plan",
        json={"plan_codigo": "BASICO", "estado": estado, "vence_en": vence.isoformat()},
    )


def test_no_se_asigna_un_plan_activo_que_vence_en_el_pasado(cliente, monkeypatch):
    # el vencimiento tiene que ser posterior al inicio: con inicio por defecto (ahora) y fecha
    # pasada falla antes, por eso se pide que sea futuro para ACTIVA/PRUEBA
    respuesta = _asignar(monkeypatch, dias=-3)
    assert respuesta.status_code == 422


def test_no_se_da_un_plan_vigente_a_una_empresa_suspendida(cliente, monkeypatch):
    respuesta = _asignar(monkeypatch, activa=False, estado="PRUEBA")
    assert respuesta.status_code == 409
    assert "suspendida" in respuesta.json()["detail"]


def test_una_empresa_suspendida_si_puede_quedar_con_plan_vencido(cliente, monkeypatch):
    respuesta = _asignar(monkeypatch, activa=False, estado="VENCIDA")
    # pasa las validaciones: el 500 de despues es de la conexion falsa, que no sabe del UPSERT
    assert respuesta.status_code not in (409, 422)


# --- recuperacion de cuenta ----------------------------------------------------------------------


def test_el_token_de_recuperacion_se_lee_y_trae_la_huella_del_hash():
    usuario = str(UUID(int=7))
    token = crear_token_recuperacion(usuario, "hash-actual")
    leido = leer_token_recuperacion(token)
    assert leido is not None
    assert leido[0] == usuario
    assert huella_coincide("hash-actual", leido[1])


def test_el_token_deja_de_servir_apenas_cambia_la_contrasena():
    """Un solo uso sin tabla: al cambiar el hash la huella ya no coincide."""
    token = crear_token_recuperacion(str(UUID(int=7)), "hash-viejo")
    _, huella = leer_token_recuperacion(token)
    assert not huella_coincide("hash-nuevo", huella)


def test_un_token_cualquiera_no_es_de_recuperacion():
    assert leer_token_recuperacion("no-es-un-jwt") is None


def test_el_token_de_recuperacion_no_abre_una_sesion(cliente):
    """get_current_usuario rechaza todo token con `uso`: no se puede usar el enlace como Bearer."""
    token = crear_token_recuperacion(str(UUID(int=7)), "hash")

    async def _conn():
        yield ConexionFalsa({"FROM usuario WHERE id": {"id": UUID(int=7), "tipo": "STAFF", "activo": True, "empresa_id": EMPRESA}})

    app.dependency_overrides[get_connection] = _conn
    respuesta = TestClient(app, raise_server_exceptions=False).get(
        "/auth/yo", headers={"Authorization": f"Bearer {token}"}
    )
    assert respuesta.status_code == 401


def test_recuperar_responde_igual_si_el_correo_no_existe(cliente):
    async def _conn():
        yield ConexionFalsa({})

    app.dependency_overrides[get_connection] = _conn
    respuesta = TestClient(app, raise_server_exceptions=False).post(
        "/auth/recuperar", json={"email": "nadie@fashionstore.bo"}
    )
    assert respuesta.status_code == 200
    assert respuesta.json()["enlace"] is None
    assert "Si el correo corresponde" in respuesta.json()["mensaje"]


def test_restablecer_con_un_enlace_invalido_da_400(cliente):
    async def _conn():
        yield ConexionFalsa({})

    app.dependency_overrides[get_connection] = _conn
    respuesta = TestClient(app, raise_server_exceptions=False).post(
        "/auth/restablecer", json={"token": "x" * 40, "password_nueva": "Nueva123!"}
    )
    assert respuesta.status_code == 400


def test_restablecer_exige_la_politica_de_contrasena(cliente):
    token = crear_token_recuperacion(str(UUID(int=7)), "hash")

    async def _conn():
        yield ConexionFalsa({})

    app.dependency_overrides[get_connection] = _conn
    respuesta = TestClient(app, raise_server_exceptions=False).post(
        "/auth/restablecer", json={"token": token, "password_nueva": "corta"}
    )
    assert respuesta.status_code == 422


# --- el personal de una empresa lo atiende la plataforma, no otra empresa ---------------------------


def test_un_admin_de_empresa_no_toca_el_personal_de_otra(cliente):
    async def _conn():
        yield ConexionFalsa({})

    app.dependency_overrides[get_connection] = _conn
    app.dependency_overrides[get_staff_actual] = lambda: staff(permisos=["usuarios.actualizar", "empresas.leer"])
    # sin `empresas.actualizar` ningun endpoint de la plataforma deja restablecer una contrasena
    respuesta = TestClient(app, raise_server_exceptions=False).post(
        f"/saas/usuarios/{uuid4()}/password", json={"password": "Nueva123!"}
    )
    assert respuesta.status_code == 403
