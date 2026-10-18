"""Etapas 2 a 5 del Modulo G: preprocesamiento, entrenamiento y evaluacion.

- Supervisado (demanda): RandomForestRegressor contra dos referencias -- el pronostico ingenuo
  "lo mismo que hace una semana" (lag_7) y una regresion lineal --, con particion TEMPORAL
  (entrena con el pasado, evalua con los ultimos 90 dias: mezclar fechas filtraria el futuro)
  y validacion cruzada temporal (TimeSeriesSplit). Metricas: MAE, RMSE, R2 y MAPE.
- No supervisado (clientas): StandardScaler + KMeans, eligiendo k entre 3 y 7 por coeficiente de
  silueta (k >= 3); como los datos son sinteticos se mide ademas el indice de Rand ajustado contra los
  perfiles con que se generaron. Cada grupo recibe un nombre por su centroide.
- No supervisado (anomalias): IsolationForest sobre las ventas diarias reales de cada sucursal;
  se entrena en el momento con los datos del tenant (no necesita etiquetas ni datos sinteticos).

Los modelos entrenados (solo con datos sinteticos, sin nada de ningun tenant) se guardan con
joblib en settings.modelos_dir y se cachean en memoria.
"""

import threading
from datetime import datetime, timezone
from pathlib import Path

import joblib
import numpy as np
from sklearn.cluster import KMeans
from sklearn.ensemble import IsolationForest, RandomForestRegressor
from sklearn.linear_model import LinearRegression
from sklearn.metrics import (
    adjusted_rand_score,
    mean_absolute_error,
    mean_squared_error,
    r2_score,
    silhouette_score,
)
from sklearn.model_selection import TimeSeriesSplit
from sklearn.preprocessing import StandardScaler

from app.core.config import settings
from app.modules.analitica import sinteticos

ARCHIVO = "modelos_fashionstore.joblib"
# subir cuando cambie lo que guarda el paquete: uno de otra version se reentrena al cargar
VERSION = 2
_cache: dict | None = None
_candado = threading.Lock()


def _metricas(real: np.ndarray, predicho: np.ndarray) -> dict[str, float]:
    mascara = real > 0
    return {
        "mae": round(float(mean_absolute_error(real, predicho)), 3),
        "rmse": round(float(np.sqrt(mean_squared_error(real, predicho))), 3),
        "r2": round(float(r2_score(real, predicho)), 3),
        "mape": round(float(np.mean(np.abs((real[mascara] - predicho[mascara]) / real[mascara])) * 100), 1),
    }


def entrenar_demanda(dias: int, semilla: int) -> dict:
    X, y, fechas = sinteticos.generar_demanda(dias, semilla)
    corte = fechas[-1].toordinal() - 90
    entrenamiento = np.array([f.toordinal() <= corte for f in fechas])
    X_tr, y_tr, X_te, y_te = X[entrenamiento], y[entrenamiento], X[~entrenamiento], y[~entrenamiento]

    bosque = RandomForestRegressor(
        n_estimators=200, max_depth=12, min_samples_leaf=3, random_state=semilla, n_jobs=-1
    ).fit(X_tr, y_tr)
    lineal = LinearRegression().fit(X_tr, y_tr)
    idx_lag = sinteticos.COLUMNAS_DEMANDA.index("lag_7")

    metricas = {
        "random_forest": _metricas(y_te, bosque.predict(X_te)),
        "regresion_lineal": _metricas(y_te, lineal.predict(X_te)),
        "ingenuo_semana_anterior": _metricas(y_te, X_te[:, idx_lag]),
    }
    # validacion cruzada temporal del bosque (5 cortes crecientes, cada uno evalua el futuro)
    cv = []
    for tr, te in TimeSeriesSplit(n_splits=5).split(X):
        modelo = RandomForestRegressor(
            n_estimators=80, max_depth=12, min_samples_leaf=3, random_state=semilla, n_jobs=-1
        ).fit(X[tr], y[tr])
        cv.append(mean_absolute_error(y[te], modelo.predict(X[te])))
    # media de unidades por combinacion clima x tipo: sirve para llevar las ventas reales de un
    # tenant (mucho mas chicas) a la escala con la que se entreno el modelo, y volver
    medias = {}
    for clima in sinteticos.CLIMAS:
        for tipo in sinteticos.TIPOS:
            ci = sinteticos.COLUMNAS_DEMANDA.index(f"clima_{clima.lower()}")
            ti = sinteticos.COLUMNAS_DEMANDA.index(f"tipo_{tipo.lower()}")
            mascara = (X[:, ci] == 1) & (X[:, ti] == 1)
            medias[f"{clima}|{tipo}"] = round(float(y[mascara].mean()), 3)
    importancias = sorted(
        zip(sinteticos.COLUMNAS_DEMANDA, bosque.feature_importances_), key=lambda x: -x[1]
    )
    # para predecir en el request se usa un solo hilo: con pocas filas por llamada el reparto
    # entre hilos cuesta mas de lo que ahorra
    bosque.set_params(n_jobs=1)
    return {
        "modelo": bosque,
        "metricas": metricas,
        "cv_mae": [round(float(v), 3) for v in cv],
        "importancias": [{"variable": v, "importancia": round(float(i), 4)} for v, i in importancias],
        "medias_sinteticas": medias,
        "filas": int(len(y)),
        "filas_entrenamiento": int(entrenamiento.sum()),
        "filas_prueba": int((~entrenamiento).sum()),
        "periodo": [fechas[0].isoformat(), fechas[-1].isoformat()],
    }


def nombrar_grupos(centroides: np.ndarray) -> list[str]:
    """Nombre de negocio de cada grupo segun su centroide (en escala original)."""
    col = {c: i for i, c in enumerate(sinteticos.COLUMNAS_CLIENTES)}
    nombres = [""] * len(centroides)
    restantes = set(range(len(centroides)))

    def tomar(indice: int, nombre: str) -> None:
        nombres[indice] = nombre
        restantes.discard(indice)

    tomar(int(np.argmax(centroides[:, col["recencia_dias"]])), "Inactivas")
    for criterio, nombre in [("monto_total", "VIP"), ("pct_promo", "Cazadoras de ofertas"),
                             ("compras_90d", "Frecuentes")]:
        if not restantes:
            break
        mejor = max(restantes, key=lambda i: centroides[i, col[criterio]])
        tomar(mejor, nombre)
    for i in sorted(restantes):
        nombres[i] = "Ocasionales" if "Ocasionales" not in nombres else f"Grupo {i + 1}"
    return nombres


def entrenar_clientes(n: int, semilla: int) -> dict:
    X, perfiles = sinteticos.generar_clientes(n, semilla)
    escalador = StandardScaler().fit(X)
    Xe = escalador.transform(X)
    evaluacion = []
    mejor = None
    # k desde 3: con 2 grupos la silueta sale alta pero solo separa "activas" de "inactivas",
    # que no le sirve al negocio para armar campanias
    for k in range(3, 8):
        km = KMeans(n_clusters=k, n_init=10, random_state=semilla).fit(Xe)
        sil = float(silhouette_score(Xe, km.labels_))
        evaluacion.append({"k": k, "silueta": round(sil, 4), "inercia": round(float(km.inertia_), 1)})
        if mejor is None or sil > mejor[1]:
            mejor = (km, sil)
    km, silueta = mejor
    centroides = escalador.inverse_transform(km.cluster_centers_)
    return {
        "escalador": escalador,
        "modelo": km,
        "k": int(km.n_clusters),
        "silueta": round(silueta, 4),
        "ari_vs_perfiles": round(float(adjusted_rand_score(perfiles, km.labels_)), 4),
        "evaluacion_k": evaluacion,
        "nombres": nombrar_grupos(centroides),
        "centroides": centroides.round(2).tolist(),
        "filas": int(n),
    }


def entrenar(dias: int = 540, clientes: int = 1500, semilla: int = 42) -> dict:
    global _cache
    paquete = {
        "version": VERSION,
        "entrenado_en": datetime.now(timezone.utc).isoformat(),
        "semilla": semilla,
        "demanda": entrenar_demanda(dias, semilla),
        "clientes": entrenar_clientes(clientes, semilla),
    }
    ruta = Path(settings.modelos_dir)
    ruta.mkdir(parents=True, exist_ok=True)
    joblib.dump(paquete, ruta / ARCHIVO)
    with _candado:
        _cache = paquete
    return paquete


def cargar() -> dict:
    """El paquete de modelos: de memoria, del disco o -- la primera vez -- entrenandolo."""
    global _cache
    with _candado:
        if _cache is not None:
            return _cache
        archivo = Path(settings.modelos_dir) / ARCHIVO
        if archivo.exists():
            try:
                guardado = joblib.load(archivo)
                if guardado.get("version") == VERSION:
                    _cache = guardado
                    return _cache
            except Exception:  # archivo de otra version de sklearn: se reentrena
                pass
    return entrenar()


def anomalias(series: list[dict], contaminacion: float = 0.06) -> list[int]:
    """Indices de los dias atipicos. series: [{total, tickets, dia_semana}] de UNA sucursal."""
    if len(series) < 20:
        return []
    X = np.array([[s["total"], s["tickets"], s["total"] / max(s["tickets"], 1), s["dia_semana"]]
                  for s in series])
    modelo = IsolationForest(contamination=contaminacion, random_state=0).fit(X)
    return [i for i, v in enumerate(modelo.predict(X)) if v == -1]


def resumen_publico(paquete: dict) -> dict:
    """Lo que se puede mostrar del paquete (sin los objetos de sklearn)."""
    d, c = paquete["demanda"], paquete["clientes"]
    return {
        "entrenado_en": paquete["entrenado_en"],
        "semilla": paquete["semilla"],
        "demanda": {k: v for k, v in d.items() if k != "modelo"},
        "clientes": {k: v for k, v in c.items() if k not in ("modelo", "escalador")},
    }
