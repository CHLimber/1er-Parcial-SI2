import re
from collections.abc import Callable

# Unica fuente de verdad de la politica de contrasenas del backend: la usan tanto
# RegistroRequest (CU02) como StaffIn/PasswordIn (CU13, alta de personal y reset). El
# frontend (shared/validacion-password.ts) y el movil (compartido/widgets.dart) espejan
# estas mismas 5 reglas a mano para el checklist en vivo -- si se cambia una acá, hay que
# tocar las otras dos.
REGLAS_PASSWORD: list[tuple[str, str, Callable[[str], bool]]] = [
    ("longitud", "Al menos 8 caracteres", lambda v: len(v) >= 8),
    ("minuscula", "Al menos una letra minuscula", lambda v: bool(re.search(r"[a-z]", v))),
    ("mayuscula", "Al menos una letra mayuscula", lambda v: bool(re.search(r"[A-Z]", v))),
    ("numero", "Al menos un numero", lambda v: bool(re.search(r"\d", v))),
    ("especial", "Al menos un caracter especial (!@#$%^&*...)", lambda v: bool(re.search(r"[^\w\s]", v))),
]


def validar_password(value: str) -> str:
    faltantes = [etiqueta for _, etiqueta, cumple in REGLAS_PASSWORD if not cumple(value)]
    if faltantes:
        raise ValueError("La contrasena debe cumplir: " + "; ".join(faltantes))
    return value
