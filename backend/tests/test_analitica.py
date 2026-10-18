"""Modulo G: los datos sinteticos son reproducibles, el modelo supervisado le gana a las
referencias, la segmentacion encuentra grupos y la deteccion de anomalias marca un pico
inyectado. Sin Postgres (entrena chico para que corra rapido)."""

from datetime import date

import numpy as np
import pytest

from app.modules.analitica import modelos, sinteticos


def test_los_datos_sinteticos_son_reproducibles_con_la_semilla():
    X1, y1, _ = sinteticos.generar_demanda(60, 3, hasta=date(2026, 6, 30))
    X2, y2, _ = sinteticos.generar_demanda(60, 3, hasta=date(2026, 6, 30))
    assert np.array_equal(X1, X2) and np.array_equal(y1, y2)
    assert X1.shape[1] == len(sinteticos.COLUMNAS_DEMANDA)


def test_en_invierno_el_clima_frio_vende_mas_abrigo_que_el_calido():
    assert sinteticos.factor_estacion(7, "FRIO", "INVIERNO") > 3 * sinteticos.factor_estacion(7, "CALIDO", "INVIERNO")


@pytest.fixture(scope="module")
def demanda():
    return modelos.entrenar_demanda(300, 11)


def test_random_forest_le_gana_al_pronostico_ingenuo(demanda):
    m = demanda["metricas"]
    assert m["random_forest"]["mae"] < m["ingenuo_semana_anterior"]["mae"]
    assert m["random_forest"]["r2"] > 0.4


def test_particion_temporal_y_validacion_cruzada(demanda):
    assert demanda["filas_prueba"] > 0 and demanda["filas_entrenamiento"] > demanda["filas_prueba"]
    assert len(demanda["cv_mae"]) == 5
    assert set(demanda["medias_sinteticas"]) == {
        f"{c}|{t}" for c in sinteticos.CLIMAS for t in sinteticos.TIPOS
    }


def test_segmentacion_elige_k_por_silueta_y_nombra_los_grupos():
    resultado = modelos.entrenar_clientes(600, 5)
    assert 3 <= resultado["k"] <= 7
    assert resultado["silueta"] > 0.2
    assert "Inactivas" in resultado["nombres"] and "VIP" in resultado["nombres"]
    assert resultado["ari_vs_perfiles"] > 0.2  # se parece a los perfiles con que se genero


def test_anomalias_marca_un_pico_inyectado():
    rng = np.random.default_rng(0)
    serie = [{"total": float(rng.normal(900, 60)), "tickets": int(rng.integers(3, 6)), "dia_semana": i % 7}
             for i in range(60)]
    serie[42] = {"total": 6000.0, "tickets": 20, "dia_semana": 0}
    assert 42 in modelos.anomalias(serie)


def test_con_pocos_dias_no_se_buscan_anomalias():
    assert modelos.anomalias([{"total": 1.0, "tickets": 1, "dia_semana": 0}] * 5) == []
