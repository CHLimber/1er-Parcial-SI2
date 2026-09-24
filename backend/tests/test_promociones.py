"""Tests unitarios de _validar_promocion (CU10, app/modules/catalogo/admin_router.py), sin
base de datos: es la validacion que corta con un 422 legible antes de que llegue al cliente la
excepcion cruda de un CHECK de Postgres (ck_promo_alcance/ck_promo_fechas)."""

from datetime import date, timedelta
from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.modules.catalogo.admin_router import _validar_promocion
from app.modules.catalogo.admin_schemas import PromocionIn

HOY = date.today()
MANIANA = HOY + timedelta(days=30)
CATEGORIA_ID = uuid4()
TEMPORADA_ID = uuid4()


def _promo(**overrides) -> PromocionIn:
    base = dict(
        nombre="Descuento de prueba",
        codigo_cupon="TEST10",
        tipo="PORCENTAJE",
        valor=10,
        alcance="TODO",
        categoria_id=None,
        temporada_id=None,
        monto_minimo=None,
        fecha_inicio=HOY,
        fecha_fin=MANIANA,
        uso_maximo=None,
    )
    base.update(overrides)
    return PromocionIn(**base)


def test_promocion_valida_no_lanza():
    _validar_promocion(_promo())  # no debe lanzar


def test_tipo_invalido_lanza_422():
    with pytest.raises(HTTPException) as exc_info:
        _validar_promocion(_promo(tipo="DESCUENTAZO"))
    assert exc_info.value.status_code == 422


def test_alcance_invalido_lanza_422():
    with pytest.raises(HTTPException) as exc_info:
        _validar_promocion(_promo(alcance="SUCURSAL"))
    assert exc_info.value.status_code == 422


def test_fecha_fin_anterior_a_inicio_lanza_422():
    with pytest.raises(HTTPException) as exc_info:
        _validar_promocion(_promo(fecha_inicio=MANIANA, fecha_fin=HOY))
    assert exc_info.value.status_code == 422


def test_porcentaje_mayor_a_100_lanza_422():
    with pytest.raises(HTTPException) as exc_info:
        _validar_promocion(_promo(tipo="PORCENTAJE", valor=150))
    assert exc_info.value.status_code == 422


def test_porcentaje_exactamente_100_no_lanza():
    _validar_promocion(_promo(tipo="PORCENTAJE", valor=100))


def test_monto_fijo_puede_superar_100():
    # el tope de 100 es solo para PORCENTAJE
    _validar_promocion(_promo(tipo="MONTO_FIJO", valor=500))


@pytest.mark.parametrize(
    "categoria_id,temporada_id",
    [(CATEGORIA_ID, None), (None, TEMPORADA_ID), (CATEGORIA_ID, TEMPORADA_ID)],
)
def test_alcance_todo_no_admite_categoria_ni_temporada(categoria_id, temporada_id):
    with pytest.raises(HTTPException) as exc_info:
        _validar_promocion(
            _promo(alcance="TODO", categoria_id=categoria_id, temporada_id=temporada_id)
        )
    assert exc_info.value.status_code == 422


def test_alcance_categoria_necesita_categoria_y_ninguna_temporada():
    with pytest.raises(HTTPException):
        _validar_promocion(_promo(alcance="CATEGORIA", categoria_id=None, temporada_id=None))
    with pytest.raises(HTTPException):
        _validar_promocion(
            _promo(alcance="CATEGORIA", categoria_id=CATEGORIA_ID, temporada_id=TEMPORADA_ID)
        )


def test_alcance_temporada_necesita_temporada_y_ninguna_categoria():
    with pytest.raises(HTTPException):
        _validar_promocion(_promo(alcance="TEMPORADA", categoria_id=None, temporada_id=None))
    with pytest.raises(HTTPException):
        _validar_promocion(
            _promo(alcance="TEMPORADA", categoria_id=CATEGORIA_ID, temporada_id=TEMPORADA_ID)
        )
