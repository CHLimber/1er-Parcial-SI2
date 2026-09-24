"""Tests unitarios de las funciones puras de app/modules/reportes/router.py (CU15): sin base
de datos, no llaman a asyncpg.Connection."""

from datetime import date, timedelta
from decimal import Decimal

import pytest
from fastapi import HTTPException

from app.modules.reportes.router import _normalizar, _rango_fechas


class _FilaFalsa(dict):
    """asyncpg.Record se comporta como un mapping; un dict alcanza para _normalizar, que solo
    hace dict(fila).items()."""


def test_normalizar_convierte_decimal_a_float():
    fila = _FilaFalsa(total=Decimal("123.45"), cantidad=3, nombre="Vestido")
    resultado = _normalizar(fila)
    assert resultado == {"total": 123.45, "cantidad": 3, "nombre": "Vestido"}
    assert isinstance(resultado["total"], float)
    assert isinstance(resultado["cantidad"], int)  # no convierte lo que no es Decimal


def test_normalizar_no_rompe_sin_decimales():
    fila = _FilaFalsa(a=1, b="texto", c=None)
    assert _normalizar(fila) == {"a": 1, "b": "texto", "c": None}


def test_rango_fechas_usa_ultimos_30_dias_sin_filtro():
    desde, hasta = _rango_fechas(None, None)
    assert hasta == date.today()
    assert desde == date.today() - timedelta(days=30)


def test_rango_fechas_respeta_las_fechas_explicitas():
    d = date(2026, 1, 1)
    h = date(2026, 1, 31)
    assert _rango_fechas(d, h) == (d, h)


def test_rango_fechas_desde_posterior_a_hasta_lanza_422():
    with pytest.raises(HTTPException) as exc_info:
        _rango_fechas(date(2026, 2, 1), date(2026, 1, 1))
    assert exc_info.value.status_code == 422


def test_rango_fechas_con_solo_desde_usa_hoy_como_hasta():
    d = date.today() - timedelta(days=5)
    desde, hasta = _rango_fechas(d, None)
    assert desde == d
    assert hasta == date.today()
