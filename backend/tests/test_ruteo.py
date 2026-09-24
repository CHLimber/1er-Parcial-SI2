"""Tests unitarios del respaldo Haversine de app/core/ruteo.py (CU20). Solo la parte que no
pega a ningun servicio externo: distancia_haversine_km y _ruta_de_respaldo. calcular_ruta/
trazar_ruta/buscar_direccion/direccion_de_punto SI hacen httpx.AsyncClient contra ORS/OSRM y
quedan fuera a proposito (serian tests de integracion, no unitarios)."""

import math

from app.core.ruteo import (
    FACTOR_SINUOSIDAD,
    PROVEEDOR_RESPALDO,
    VELOCIDAD_KMH,
    _ruta_de_respaldo,
    distancia_haversine_km,
    hay_proveedor_externo,
)


def test_distancia_haversine_de_un_punto_a_si_mismo_es_cero():
    assert distancia_haversine_km(-17.78, -63.18, -17.78, -63.18) == 0.0


def test_distancia_haversine_simetrica():
    a = (-17.78, -63.18)  # Santa Cruz
    b = (-16.5, -68.15)  # La Paz
    ida = distancia_haversine_km(*a, *b)
    vuelta = distancia_haversine_km(*b, *a)
    assert math.isclose(ida, vuelta, rel_tol=1e-9)


def test_distancia_haversine_santa_cruz_la_paz_orden_de_magnitud():
    # ~530 km en linea recta entre Santa Cruz y La Paz; no hace falta el numero exacto, solo
    # que la formula no este devolviendo algo disparatado (radianes mal convertidos, etc.).
    km = distancia_haversine_km(-17.78, -63.18, -16.5, -68.15)
    assert 480 < km < 580


def test_ruta_de_respaldo_marca_proveedor_haversine():
    ruta = _ruta_de_respaldo(-17.78, -63.18, -17.79, -63.19)
    assert ruta.proveedor == PROVEEDOR_RESPALDO


def test_ruta_de_respaldo_aplica_el_factor_de_sinuosidad():
    lat1, lon1, lat2, lon2 = -17.78, -63.18, -17.9, -63.3
    directa = distancia_haversine_km(lat1, lon1, lat2, lon2)
    ruta = _ruta_de_respaldo(lat1, lon1, lat2, lon2)
    assert math.isclose(ruta.distancia_km, round(directa * FACTOR_SINUOSIDAD, 3), rel_tol=1e-6)


def test_ruta_de_respaldo_distancia_cero_da_duracion_cero():
    ruta = _ruta_de_respaldo(-17.78, -63.18, -17.78, -63.18)
    assert ruta.distancia_km == 0.0
    assert ruta.duracion_min == 0


def test_ruta_de_respaldo_duracion_coherente_con_la_velocidad_media():
    ruta = _ruta_de_respaldo(-17.78, -63.18, -17.9, -63.3)
    minutos_esperados = max(int(round(ruta.distancia_km / VELOCIDAD_KMH * 60)), 1)
    assert ruta.duracion_min == minutos_esperados


def test_hay_proveedor_externo_es_false_sin_ors_api_key():
    # conftest.py fija ORS_API_KEY="" para no pegarle a ORS desde un test unitario.
    assert hay_proveedor_externo() is False
