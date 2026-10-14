"""Cambio de prenda por talla/color (Segundo parcial, PENDIENTES 5.8 a 5.10): condiciones de la
prenda, variante pedida a cambio y rango del mes de la consulta. Sin Postgres: las reglas son
funciones puras y los rechazos tempranos del endpoint no llegan a tocar la base."""

from datetime import date
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.core.db import get_connection
from app.main import app
from app.modules.devoluciones import router as devoluciones_router
from tests.conexion_falsa import ConexionFalsa

ADMIN = {"id": uuid4(), "permisos": ["sucursales.actualizar"], "sucursal_id": None}


@pytest.fixture
def cliente():
    async def _conn():
        yield ConexionFalsa({})

    app.dependency_overrides[get_connection] = _conn
    app.dependency_overrides[devoluciones_router.puede_crear] = lambda: ADMIN
    yield TestClient(app, raise_server_exceptions=False)
    app.dependency_overrides.clear()


# --- condiciones de la prenda --------------------------------------------------------------------


def test_un_cambio_por_talla_en_buen_estado_se_acepta():
    assert devoluciones_router.condiciones_faltantes("TALLA", True, True, True) == []


def test_un_cambio_por_talla_exige_etiqueta_sin_uso_y_comprobante():
    faltan = devoluciones_router.condiciones_faltantes("TALLA", False, False, False)
    assert faltan == ["el comprobante de compra", "la etiqueta original", "la prenda sin uso"]


def test_por_defecto_alcanza_con_el_comprobante():
    # la prenda pudo usarse (y perder la etiqueta) hasta que aparecio la falla
    assert devoluciones_router.condiciones_faltantes("DEFECTO", False, False, True) == []
    assert devoluciones_router.condiciones_faltantes("DEFECTO", True, True, False) == [
        "el comprobante de compra"
    ]


# --- variante pedida a cambio --------------------------------------------------------------------

PRENDA = uuid4()


def _var(producto=PRENDA, talla=1, color=1) -> dict:
    return {"producto_id": producto, "talla_id": talla, "color_id": color}


def test_cambio_por_talla_valido():
    assert devoluciones_router.validar_variante_cambio("TALLA", _var(talla=2), _var(talla=3)) is None


def test_cambio_por_talla_a_la_misma_talla_no_sirve():
    error = devoluciones_router.validar_variante_cambio("TALLA", _var(talla=2), _var(talla=2, color=5))
    assert error == "un cambio por talla tiene que pedir otra talla"


def test_cambio_por_color_tiene_que_cambiar_el_color():
    assert devoluciones_router.validar_variante_cambio("COLOR", _var(color=1), _var(color=2)) is None
    assert (
        devoluciones_router.validar_variante_cambio("COLOR", _var(color=1), _var(talla=4, color=1))
        == "un cambio por color tiene que pedir otro color"
    )


def test_el_cambio_es_siempre_por_la_misma_prenda():
    error = devoluciones_router.validar_variante_cambio("TALLA", _var(), _var(producto=uuid4(), talla=2))
    assert error == "el cambio tiene que ser por la misma prenda"


# --- rechazos tempranos del endpoint --------------------------------------------------------------


def _body(motivo_tipo: str, **extra) -> dict:
    linea = {"venta_detalle_id": str(uuid4()), "cantidad": 1}
    linea.update(extra.pop("linea", {}))
    return {"venta_id": str(uuid4()), "motivo_tipo": motivo_tipo, "motivo": "Le quedo chica",
            "lineas": [linea], **extra}


def test_post_rechaza_una_prenda_usada_sin_tocar_la_base(cliente):
    respuesta = cliente.post("/devoluciones", json=_body("TALLA", sin_uso=False,
                                                         linea={"variante_solicitada_id": str(uuid4())}))
    assert respuesta.status_code == 409
    assert "la prenda sin uso" in respuesta.json()["detail"]


def test_post_cambio_por_talla_sin_decir_que_se_lleva_es_422(cliente):
    respuesta = cliente.post("/devoluciones", json=_body("TALLA"))
    assert respuesta.status_code == 422
    assert "a cambio" in respuesta.json()["detail"]


def test_post_devolucion_comun_no_acepta_prenda_a_cambio(cliente):
    respuesta = cliente.post(
        "/devoluciones", json=_body("NO_GUSTO", linea={"variante_solicitada_id": str(uuid4())})
    )
    assert respuesta.status_code == 422


def test_motivo_desconocido_lo_rechaza_el_schema(cliente):
    assert cliente.post("/devoluciones", json=_body("CAPRICHO")).status_code == 422


# --- rango del mes de "cambios del mes" ----------------------------------------------------------


@pytest.mark.parametrize(
    ("anio", "mes", "esperado"),
    [
        (2026, 10, (date(2026, 10, 1), date(2026, 11, 1))),
        (2026, 12, (date(2026, 12, 1), date(2027, 1, 1))),
        (2027, 2, (date(2027, 2, 1), date(2027, 3, 1))),
    ],
)
def test_rango_del_mes(anio, mes, esperado):
    assert devoluciones_router.rango_del_mes(anio, mes) == esperado
