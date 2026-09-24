"""Tests unitarios de la politica de contrasenas (CU02/CU13), sin base de datos.

app/modules/usuarios/politica_password.py es la unica fuente de verdad de las 5 reglas; el
frontend y el movil las espejan a mano (ver comentario en el propio archivo). Estos tests
fijan el contrato para que si alguien afloja o rompe una regla aca, se note en el CI local.
"""

import pytest

from app.modules.usuarios.politica_password import REGLAS_PASSWORD, validar_password


def test_password_valida_no_lanza():
    assert validar_password("Abcdefg1!") == "Abcdefg1!"


@pytest.mark.parametrize(
    "password",
    [
        "Abc1!",  # muy corta
        "abcdefg1!",  # sin mayuscula
        "ABCDEFG1!",  # sin minuscula
        "Abcdefgh!",  # sin numero
        "Abcdefg12",  # sin caracter especial
        "",  # vacia: falla todas las reglas
    ],
)
def test_password_invalida_lanza_value_error(password):
    with pytest.raises(ValueError):
        validar_password(password)


def test_mensaje_de_error_lista_las_reglas_que_faltan():
    with pytest.raises(ValueError) as exc_info:
        validar_password("abc")
    mensaje = str(exc_info.value)
    # "abc" cumple minuscula pero falla longitud, mayuscula, numero y especial
    assert "longitud" not in mensaje  # las etiquetas son legibles, no los codigos internos
    assert "Al menos 8 caracteres" in mensaje
    assert "Al menos una letra mayuscula" in mensaje
    assert "Al menos un numero" in mensaje
    assert "Al menos un caracter especial" in mensaje
    assert "Al menos una letra minuscula" not in mensaje


def test_hay_exactamente_cinco_reglas():
    # snapshot deliberado: si se agrega/quita una regla aca hay que actualizar el espejo en
    # frontend/shared/validacion-password.ts y movil/compartido/widgets.dart (ver CLAUDE.md).
    assert len(REGLAS_PASSWORD) == 5
