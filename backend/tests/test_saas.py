"""SaaS (segundo parcial, Modulo A): reglas del plan de la empresa (tenant), periodo de la
suscripcion al pagar y segmento sugerido de la clienta. Sin Postgres ni Stripe. El aislamiento
entre empresas y los topes del plan estan en tests/test_multitenant.py."""

from datetime import datetime, timedelta, timezone
from decimal import Decimal
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.core.db import get_connection
from app.core.deps import get_staff_actual
from app.core.plan import evaluar_acceso
from app.main import app
from app.modules.plataforma_saas.saas.servicio import nuevo_periodo, sumar_meses
from app.modules.relacion_con_la_clienta.clientes.router import segmento_sugerido
from tests.conexion_falsa import ConexionFalsa, staff

AHORA = datetime(2026, 10, 14, 12, 0, tzinfo=timezone.utc)


def _plan(**cambios) -> dict:
    plan = {
        "estado": "ACTIVA", "vence_en": AHORA + timedelta(days=10), "plan_nombre": "Basico",
        "perfiles_clientes": False, "traspasos": False, "ia_reportes": False,
        "operacion_offline": True, "reportes": True, "analitica_ml": False,
    }
    plan.update(cambios)
    return plan


# --- que puede usar el tenant ---------------------------------------------------------------------


def test_plan_vigente_que_incluye_la_funcion_pasa():
    assert evaluar_acceso(_plan(traspasos=True), "traspasos", ahora=AHORA) is None


def test_plan_que_no_incluye_la_funcion_da_403_con_el_plan_minimo():
    codigo, detalle = evaluar_acceso(_plan(), "ia_reportes", "Profesional", ahora=AHORA)
    assert codigo == 403
    assert detalle == (
        "Tu plan Basico no incluye los reportes generativos con IA; "
        "esta incluido desde el plan Profesional"
    )


def test_suscripcion_vencida_da_402_aunque_el_estado_diga_activa():
    plan = _plan(traspasos=True, vence_en=AHORA - timedelta(days=1))
    codigo, detalle = evaluar_acceso(plan, "traspasos", ahora=AHORA)
    assert codigo == 402
    assert "vencio el 13/10/2026" in detalle


@pytest.mark.parametrize("estado", ["VENCIDA", "CANCELADA"])
def test_estado_vencida_o_cancelada_bloquea(estado):
    assert evaluar_acceso(_plan(estado=estado), None, ahora=AHORA)[0] == 402


def test_en_prueba_se_puede_usar_lo_del_plan():
    assert evaluar_acceso(_plan(estado="PRUEBA"), None, ahora=AHORA) is None


def test_empresa_sin_suscripcion_da_402():
    assert evaluar_acceso(None, "traspasos", ahora=AHORA)[0] == 402


# --- periodo al pagar ----------------------------------------------------------------------------


def test_sumar_meses_respeta_el_fin_de_mes():
    assert sumar_meses(datetime(2027, 1, 31, tzinfo=timezone.utc), 1).date().isoformat() == "2027-02-28"
    assert sumar_meses(datetime(2026, 11, 15, tzinfo=timezone.utc), 3).date().isoformat() == "2027-02-15"


def test_renovar_antes_de_vencer_suma_al_final_del_periodo():
    vence = AHORA + timedelta(days=5)
    desde, hasta = nuevo_periodo(vence, 1, ahora=AHORA)
    assert desde == vence
    assert hasta == sumar_meses(vence, 1)


def test_renovar_una_suscripcion_vencida_arranca_hoy():
    desde, hasta = nuevo_periodo(AHORA - timedelta(days=20), 2, ahora=AHORA)
    assert desde == AHORA
    assert hasta == sumar_meses(AHORA, 2)


# --- segmento sugerido de la clienta -------------------------------------------------------------


@pytest.mark.parametrize(
    ("compras", "total", "hace_dias", "esperado"),
    [
        (0, "0", None, "NUEVA"),
        (1, "300", 5, "NUEVA"),
        (3, "900", 5, "FRECUENTE"),
        (2, "2500", 5, "VIP"),
        (8, "5000", 120, "INACTIVA"),
    ],
)
def test_segmento_sugerido(compras, total, hace_dias, esperado):
    ultima = None if hace_dias is None else AHORA - timedelta(days=hace_dias)
    assert segmento_sugerido(compras, Decimal(total), ultima, ahora=AHORA) == esperado


# --- el plan corta el endpoint -------------------------------------------------------------------


@pytest.fixture
def cliente():
    yield
    app.dependency_overrides.clear()


def test_encargado_con_plan_sin_traspasos_no_ve_sugerencias(cliente):
    encargado = staff(permisos=["traspasos.leer"], sucursal_id=uuid4())
    conn = ConexionFalsa(
        {
            "FROM suscripcion su": _plan() | {"plan_nombre": "Basico"},
            "SELECT nombre FROM plan": "Profesional",
        }
    )

    async def _conn():
        yield conn

    app.dependency_overrides[get_connection] = _conn
    app.dependency_overrides[get_staff_actual] = lambda: encargado
    respuesta = TestClient(app, raise_server_exceptions=False).get("/traspasos/sugerencias")
    assert respuesta.status_code == 403
    assert "desde el plan Profesional" in respuesta.json()["detail"]


def test_el_admin_de_empresa_con_un_plan_que_lo_incluye_pasa(cliente):
    admin = staff(permisos=["traspasos.leer", "sucursales.actualizar"])

    async def _conn():
        yield ConexionFalsa({"FROM suscripcion su": _plan(traspasos=True)})

    app.dependency_overrides[get_connection] = _conn
    app.dependency_overrides[get_staff_actual] = lambda: admin
    respuesta = TestClient(app, raise_server_exceptions=False).get("/traspasos/sugerencias")
    assert respuesta.status_code == 200
    assert respuesta.json() == []


def test_el_admin_de_empresa_tambien_depende_del_plan(cliente):
    """Antes (tenant = sucursal) el ADMIN de la cadena saltaba el plan; ahora es el admin de UNA
    empresa y su plan lo alcanza igual que a su personal."""
    admin = staff(permisos=["traspasos.leer", "sucursales.actualizar"])

    async def _conn():
        yield ConexionFalsa(
            {"FROM suscripcion su": _plan(vence_en=AHORA - timedelta(days=1))}
        )

    app.dependency_overrides[get_connection] = _conn
    app.dependency_overrides[get_staff_actual] = lambda: admin
    respuesta = TestClient(app, raise_server_exceptions=False).get("/traspasos/sugerencias")
    assert respuesta.status_code == 402
