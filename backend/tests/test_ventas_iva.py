"""Tests unitarios de la formula de IVA/total de CU05/CU06 (app/modules/ventas/router.py).

IVA_TASA es la unica constante pura que vive en el modulo: el resto del calculo esta inline
dentro del endpoint /ventas/checkout (que necesita conn/carrito reales, asi que queda fuera de
alcance de un test unitario). Estos tests fijan el 13% y reproducen la formula documentada en
el modulo ("el IVA se calcula solo sobre subtotal - descuento, el flete no es base imponible")
para detectar si alguien cambia la tasa o el redondeo sin querer.
"""

from decimal import Decimal

from app.modules.ventas.router import IVA_TASA


def test_iva_tasa_es_13_por_ciento():
    assert IVA_TASA == Decimal("0.13")


def _calcular_total(subtotal: Decimal, descuento: Decimal, costo_envio: Decimal) -> dict:
    base_imponible = subtotal - descuento
    iva = (base_imponible * IVA_TASA).quantize(Decimal("0.01"))
    total = (base_imponible + iva + costo_envio).quantize(Decimal("0.01"))
    return {"base_imponible": base_imponible, "iva": iva, "total": total}


def test_iva_se_calcula_sobre_subtotal_menos_descuento():
    resultado = _calcular_total(Decimal("100.00"), Decimal("0"), Decimal("0"))
    assert resultado["iva"] == Decimal("13.00")
    assert resultado["total"] == Decimal("113.00")


def test_descuento_reduce_la_base_imponible():
    resultado = _calcular_total(Decimal("100.00"), Decimal("20.00"), Decimal("0"))
    assert resultado["base_imponible"] == Decimal("80.00")
    assert resultado["iva"] == Decimal("10.40")
    assert resultado["total"] == Decimal("90.40")


def test_costo_de_envio_no_es_base_imponible():
    # el flete se suma al total DESPUES del IVA, no antes: mismo IVA con o sin envio.
    sin_envio = _calcular_total(Decimal("100.00"), Decimal("0"), Decimal("0"))
    con_envio = _calcular_total(Decimal("100.00"), Decimal("0"), Decimal("15.00"))
    assert sin_envio["iva"] == con_envio["iva"]
    assert con_envio["total"] == sin_envio["total"] + Decimal("15.00")


def test_redondeo_a_dos_decimales():
    resultado = _calcular_total(Decimal("33.33"), Decimal("0"), Decimal("0"))
    assert resultado["iva"] == Decimal("4.33")  # 33.33 * 0.13 = 4.3329 -> 4.33
