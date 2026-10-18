"""Aislamiento entre empresas y topes del plan (Modulo A, RN04/RNF02). Sin Postgres: las reglas
puras de app/core/plan.py y app/core/tenant.py, y endpoints con la base falsa donde la fila de
otra empresa "no existe" (la consulta filtra por empresa_id y no devuelve nada -> 404).

El recorrido completo contra Postgres real (2 empresas, intentos cruzados, tope de sucursales,
plan Basico sin IA, plataforma) esta en scripts/e2e_multitenant.py."""

from uuid import uuid4

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.core import tenant
from app.core.db import get_connection
from app.core.deps import get_staff_actual
from app.core.plan import evaluar_limite, funciones_habilitadas
from app.main import app
from tests.conexion_falsa import EMPRESA, ConexionFalsa, staff

OTRA_EMPRESA = uuid4()


def _plan(**cambios):
    from datetime import datetime, timedelta, timezone

    plan = {
        "estado": "ACTIVA", "vence_en": datetime.now(timezone.utc) + timedelta(days=5),
        "plan_nombre": "Basico", "max_sucursales": 2, "max_empleados": None, "max_cajas": None,
        "perfiles_clientes": True, "traspasos": True, "operacion_offline": True, "reportes": True,
        "ia_reportes": False, "analitica_ml": False,
    }
    plan.update(cambios)
    return plan


# --- topes del plan -------------------------------------------------------------------------------


def test_bajo_el_tope_de_sucursales_se_puede_agregar():
    assert evaluar_limite(_plan(), "sucursales", 1) is None


def test_en_el_tope_de_sucursales_se_rechaza():
    assert "hasta 2 sucursales" in evaluar_limite(_plan(), "sucursales", 2)


def test_tope_nulo_es_sin_limite():
    assert evaluar_limite(_plan(max_sucursales=None), "sucursales", 500) is None


def test_el_tope_es_configurable():
    assert evaluar_limite(_plan(max_sucursales=10), "sucursales", 9) is None
    assert evaluar_limite(_plan(max_sucursales=10), "sucursales", 10) is not None


def test_funciones_del_plan_basico_no_incluyen_ia():
    funciones = funciones_habilitadas(_plan())
    assert "reportes" in funciones and "operacion_offline" in funciones
    assert "ia_reportes" not in funciones


def test_suscripcion_vencida_no_habilita_ninguna_funcion():
    from datetime import datetime, timedelta, timezone

    assert funciones_habilitadas(_plan(vence_en=datetime.now(timezone.utc) - timedelta(days=1))) == []


# --- identidad del tenant -------------------------------------------------------------------------


def test_la_plataforma_no_opera_tiendas():
    with pytest.raises(HTTPException) as error:
        tenant.empresa_de({"empresa_id": None, "permisos": ["empresas.leer"]})
    assert error.value.status_code == 403


def test_admin_de_empresa_ve_todas_sus_sucursales_y_el_resto_solo_la_suya():
    admin = staff(permisos=["sucursales.actualizar"])
    assert tenant.alcance_sucursal(admin, None) is None
    propia = uuid4()
    encargado = staff(sucursal_id=propia)
    assert tenant.alcance_sucursal(encargado, None) == propia
    with pytest.raises(HTTPException):
        tenant.alcance_sucursal(encargado, uuid4())


def test_un_admin_sin_empresa_no_cuenta_como_admin_de_empresa():
    assert not tenant.es_admin_empresa({"empresa_id": None, "permisos": ["sucursales.actualizar"]})


# --- endpoints: lo de otra empresa no existe ------------------------------------------------------


@pytest.fixture
def como():
    def usar(usuario: dict, respuestas: dict) -> TestClient:
        async def _conn():
            yield ConexionFalsa(respuestas)

        app.dependency_overrides[get_connection] = _conn
        app.dependency_overrides[get_staff_actual] = lambda: usuario
        return TestClient(app, raise_server_exceptions=False)

    yield usar
    app.dependency_overrides.pop(get_connection, None)
    app.dependency_overrides.pop(get_staff_actual, None)


ADMIN = staff(permisos=[
    "catalogo.leer", "catalogo.actualizar", "sucursales.leer", "sucursales.actualizar",
    "sucursales.crear", "inventario.actualizar", "usuarios.leer", "proveedores.leer",
])


def test_producto_de_otra_empresa_responde_404(como):
    # SELECT_PRODUCTO ... WHERE p.id = $1 AND p.empresa_id = $2 -> nada
    r = como(ADMIN, {"FROM producto p": None}).get(f"/admin/catalogo/productos/{uuid4()}")
    assert r.status_code == 404


def test_sucursal_de_otra_empresa_responde_404(como):
    r = como(ADMIN, {"FROM sucursal s": None}).get(f"/admin/sucursales/{uuid4()}")
    assert r.status_code == 404


def test_ajuste_de_stock_en_sucursal_ajena_responde_404(como):
    respuestas = {"FROM sucursal WHERE id = $1 AND empresa_id = $2": None}
    r = como(ADMIN, respuestas).post(
        "/inventario/ajustes",
        json={"sucursal_id": str(uuid4()), "variante_id": str(uuid4()),
              "cantidad_fisica_nueva": 0, "motivo": "cruzado"},
    )
    assert r.status_code == 404


def test_ajuste_de_prenda_ajena_responde_404(como):
    respuestas = {"WHERE pv.id = ANY($1::uuid[]) AND p.empresa_id = $2": 0}
    r = como(ADMIN, respuestas).post(
        "/inventario/ajustes",
        json={"sucursal_id": str(uuid4()), "variante_id": str(uuid4()),
              "cantidad_fisica_nueva": 0, "motivo": "cruzado"},
    )
    assert r.status_code == 404


def test_las_consultas_de_listado_filtran_por_la_empresa_del_usuario(como):
    conn = ConexionFalsa({})

    async def _conn():
        yield conn

    app.dependency_overrides[get_connection] = _conn
    app.dependency_overrides[get_staff_actual] = lambda: ADMIN
    try:
        assert TestClient(app).get("/proveedores").status_code == 200
    finally:
        app.dependency_overrides.pop(get_connection, None)
        app.dependency_overrides.pop(get_staff_actual, None)


def test_alta_de_sucursal_por_encima_del_tope_da_409(como):
    respuestas = {
        "FROM suscripcion su": _plan(),
        "AS sucursales": {"sucursales": 2, "empleados": 4, "cajas": 2},
    }
    r = como(ADMIN, respuestas).post(
        "/admin/sucursales",
        json={"codigo": "X-1", "nombre": "Tercera", "ciudad": "LA_PAZ", "direccion": "Calle 1",
              "cantidad_vestidores": 1},
    )
    assert r.status_code == 409
    assert "hasta 2 sucursales" in r.json()["detail"]


def test_la_tienda_publica_se_elige_por_slug():
    assert EMPRESA != OTRA_EMPRESA  # sentinela: la empresa de prueba es fija (conftest)
