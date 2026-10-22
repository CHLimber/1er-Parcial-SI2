"""Etapa 1 del Modulo G: generacion de datos sinteticos (con semilla, reproducibles).

No hay anios de historia real para entrenar, asi que se simula un proceso generativo con las
reglas que conocemos del negocio (las mismas que reparten el stock del seed por clima):

DEMANDA (modelo supervisado). Una fila por dia x clima de la ciudad x tipo de prenda:
    unidades ~ Poisson(lambda), con
    lambda = base(tipo) * estacion(mes, clima, tipo) * dia_semana * promo * precio^-1.2
             * fecha_especial * tendencia
  - estacion: hemisferio sur (invierno jun-ago). En clima CALIDO pesa la ropa de verano todo
    el anio, en FRIO la de invierno; TEMPLADO sigue la estacion.
  - dia_semana: sabado x1.6, domingo x1.3, viernes x1.2.
  - promo: 15% de los dias, x1.35. indice_precio en [0.85, 1.15] con elasticidad -1.2.
  - fechas especiales: dia de la madre (27/5), aguinaldo (dic), carnaval (feb) x1.5.
  - tendencia: +8% anual.
  Variables: dia_semana, mes (seno/coseno), clima (one-hot), tipo (one-hot), promo,
  indice_precio, fecha_especial y dos rezagos (unidades de hace 7 dias y media de los 7 dias
  previos), que en produccion se calculan con las ventas reales de la sucursal.

CLIENTAS (modelo no supervisado). Cinco perfiles latentes (VIP, frecuente, ocasional,
cazadora de ofertas, inactiva) generan: compras en 90 dias, monto total, dias desde la ultima
compra, ticket promedio, % de compras en promocion y % online. El perfil latente NO entra al
modelo: solo se usa despues para medir cuanto se parecen los grupos encontrados a los reales
(indice de Rand ajustado), algo que solo se puede hacer con datos sinteticos.
"""

from datetime import date, timedelta

import numpy as np

CLIMAS = ["CALIDO", "FRIO", "TEMPLADO"]
TIPOS = ["VERANO", "INVIERNO", "ATEMPORAL", "ACCESORIO"]
BASE_TIPO = {"VERANO": 7.0, "INVIERNO": 6.0, "ATEMPORAL": 8.0, "ACCESORIO": 3.5}
FACTOR_DIA = {0: 1.0, 1: 0.95, 2: 1.0, 3: 1.05, 4: 1.2, 5: 1.6, 6: 1.3}

COLUMNAS_DEMANDA = (
    ["dia_semana", "mes_sin", "mes_cos"]
    + [f"clima_{c.lower()}" for c in CLIMAS]
    + [f"tipo_{t.lower()}" for t in TIPOS]
    + ["promo", "indice_precio", "fecha_especial", "lag_7", "media_7"]
)

PERFILES = ["VIP", "FRECUENTE", "OCASIONAL", "OFERTAS", "INACTIVA"]
COLUMNAS_CLIENTES = [
    "compras_90d", "monto_total", "recencia_dias", "ticket_promedio", "pct_promo", "pct_online",
]


def fecha_especial(dia: date) -> int:
    return int(
        (dia.month == 5 and 20 <= dia.day <= 27)
        or (dia.month == 12 and dia.day >= 10)
        or (dia.month == 2 and dia.day <= 15)
    )


def factor_estacion(mes: int, clima: str, tipo: str) -> float:
    # 1 en pleno invierno austral (julio), -1 en pleno verano (enero)
    invierno = np.cos((mes - 7) / 12 * 2 * np.pi)
    if tipo == "VERANO":
        f = 1 - 0.55 * invierno
        return f * {"CALIDO": 1.6, "FRIO": 0.45, "TEMPLADO": 1.0}[clima]
    if tipo == "INVIERNO":
        f = 1 + 0.6 * invierno
        return f * {"CALIDO": 0.35, "FRIO": 1.7, "TEMPLADO": 1.0}[clima]
    return 1.0


def fila_demanda(
    dia: date, clima: str, tipo: str, promo: int, indice_precio: float, lag_7: float, media_7: float
) -> list[float]:
    """El vector de variables del modelo (mismo orden que COLUMNAS_DEMANDA)."""
    return (
        [dia.weekday(), np.sin(2 * np.pi * dia.month / 12), np.cos(2 * np.pi * dia.month / 12)]
        + [1.0 if c == clima else 0.0 for c in CLIMAS]
        + [1.0 if t == tipo else 0.0 for t in TIPOS]
        + [promo, indice_precio, fecha_especial(dia), lag_7, media_7]
    )


def generar_demanda(dias: int = 540, semilla: int = 42, hasta: date | None = None):
    """(X, y, fechas): una fila por dia x clima x tipo, ordenadas por fecha."""
    rng = np.random.default_rng(semilla)
    hasta = hasta or date.today()
    inicio = hasta - timedelta(days=dias - 1)
    historia: dict[tuple[str, str], list[float]] = {(c, t): [] for c in CLIMAS for t in TIPOS}
    X, y, fechas = [], [], []
    for n in range(dias):
        dia = inicio + timedelta(days=n)
        tendencia = 1 + 0.08 * n / 365
        for clima in CLIMAS:
            for tipo in TIPOS:
                promo = int(rng.random() < 0.15)
                precio = float(rng.uniform(0.85, 1.15))
                lam = (
                    BASE_TIPO[tipo]
                    * factor_estacion(dia.month, clima, tipo)
                    * FACTOR_DIA[dia.weekday()]
                    * (1.35 if promo else 1.0)
                    * precio ** -1.2
                    * (1.5 if fecha_especial(dia) else 1.0)
                    * tendencia
                )
                unidades = float(rng.poisson(lam))
                previos = historia[(clima, tipo)]
                lag_7 = previos[-7] if len(previos) >= 7 else lam
                media_7 = float(np.mean(previos[-7:])) if previos else lam
                previos.append(unidades)
                if n < 7:
                    continue  # sin rezagos completos no se usan para entrenar
                X.append(fila_demanda(dia, clima, tipo, promo, precio, lag_7, media_7))
                y.append(unidades)
                fechas.append(dia)
    return np.array(X), np.array(y), fechas


def generar_clientes(n: int = 1500, semilla: int = 7):
    """(X, perfil_latente). X en el orden de COLUMNAS_CLIENTES."""
    rng = np.random.default_rng(semilla)
    # (proporcion, compras_90d, ticket, recencia, pct_promo, pct_online)
    parametros = {
        "VIP":       (0.08, 9.0, 620.0, 8.0,  0.10, 0.45),
        "FRECUENTE": (0.22, 5.0, 260.0, 15.0, 0.20, 0.35),
        "OCASIONAL": (0.35, 1.6, 230.0, 45.0, 0.25, 0.30),
        "OFERTAS":   (0.20, 3.0, 140.0, 25.0, 0.80, 0.60),
        "INACTIVA":  (0.15, 0.3, 200.0, 150.0, 0.30, 0.20),
    }
    perfiles = rng.choice(PERFILES, size=n, p=[parametros[p][0] for p in PERFILES])
    filas = []
    for perfil in perfiles:
        _, compras, ticket, recencia, promo, online = parametros[perfil]
        c = max(0, rng.poisson(compras))
        t = max(40.0, rng.normal(ticket, ticket * 0.25))
        filas.append([
            c,
            c * t,
            min(365.0, max(0.0, rng.exponential(recencia))),
            t,
            float(np.clip(rng.normal(promo, 0.12), 0, 1)),
            float(np.clip(rng.normal(online, 0.15), 0, 1)),
        ])
    return np.array(filas), list(perfiles)
