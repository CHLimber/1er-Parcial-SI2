"""CU20 - distancia de ruta y geocodificacion para el delivery.

Proveedor: openrouteservice (ORS) de HeiGIT, que corre sobre datos de OpenStreetMap y tiene
un plan gratuito sin tarjeta de credito (matriz: 500 req/dia, geocoding Pelias: 1000 req/dia).
Se usa la API de matriz en vez de directions porque no falla cuando el punto cae fuera de la
red vial: engancha al nodo mas cercano y devuelve igual la distancia.

Si no hay ORS_API_KEY, o el servicio no responde a tiempo, NO se rompe la compra: se cae a una
distancia Haversine (linea recta) multiplicada por un factor de sinuosidad urbana. La
cotizacion dice con que proveedor se calculo, y ese dato queda guardado en envio.proveedor_ruteo
para poder auditar despues por que se cobro lo que se cobro.

Solo resuelve GEOMETRIA (cuantos km y cuantos minutos hay hasta el domicilio). El precio lo
pone Postgres en fn_cotizar_envio(), ver db/02_logica.sql.
"""

import math
from dataclasses import dataclass

import httpx

from app.core.config import settings

# Una ruta urbana real es mas larga que la linea recta entre los dos puntos. 1.35 es el factor
# habitual para una traza de ciudad; sirve solo para el respaldo sin ORS.
FACTOR_SINUOSIDAD = 1.35
# Velocidad media de reparto en moto dentro de una ciudad boliviana, para estimar la duracion.
VELOCIDAD_KMH = 22.0

PROVEEDOR_ORS = "ORS"
PROVEEDOR_RESPALDO = "HAVERSINE"


@dataclass(frozen=True)
class Ruta:
    distancia_km: float
    duracion_min: int
    proveedor: str


@dataclass(frozen=True)
class Lugar:
    etiqueta: str
    latitud: float
    longitud: float
    ciudad: str | None = None


def hay_proveedor_externo() -> bool:
    return bool(settings.ors_api_key)


def distancia_haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Distancia en linea recta sobre la esfera terrestre, en kilometros."""
    radio_tierra = 6371.0088
    d_lat = math.radians(lat2 - lat1)
    d_lon = math.radians(lon2 - lon1)
    a = (
        math.sin(d_lat / 2) ** 2
        + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(d_lon / 2) ** 2
    )
    return 2 * radio_tierra * math.asin(math.sqrt(a))


def _ruta_de_respaldo(lat1: float, lon1: float, lat2: float, lon2: float) -> Ruta:
    km = distancia_haversine_km(lat1, lon1, lat2, lon2) * FACTOR_SINUOSIDAD
    minutos = max(int(round(km / VELOCIDAD_KMH * 60)), 1) if km > 0 else 0
    return Ruta(distancia_km=round(km, 3), duracion_min=minutos, proveedor=PROVEEDOR_RESPALDO)


async def calcular_ruta(
    origen_lat: float, origen_lon: float, destino_lat: float, destino_lon: float
) -> Ruta:
    """Kilometros y minutos de manejo entre la sucursal y el domicilio."""
    if not hay_proveedor_externo():
        return _ruta_de_respaldo(origen_lat, origen_lon, destino_lat, destino_lon)

    url = f"{settings.ors_base_url}/v2/matrix/{settings.ors_perfil}"
    cuerpo = {
        # ORS trabaja en [longitud, latitud], al reves de lo que uno escribe en un mapa
        "locations": [[origen_lon, origen_lat], [destino_lon, destino_lat]],
        "sources": [0],
        "destinations": [1],
        "metrics": ["distance", "duration"],
        "units": "km",
    }
    try:
        async with httpx.AsyncClient(timeout=settings.ors_timeout) as cliente:
            respuesta = await cliente.post(
                url,
                json=cuerpo,
                headers={
                    "Authorization": settings.ors_api_key,
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                },
            )
            respuesta.raise_for_status()
            datos = respuesta.json()
        km = float(datos["distances"][0][0])
        segundos = float(datos["durations"][0][0])
    except (httpx.HTTPError, KeyError, IndexError, TypeError, ValueError):
        # el delivery no puede quedarse sin cotizar porque un servicio de mapas este caido
        return _ruta_de_respaldo(origen_lat, origen_lon, destino_lat, destino_lon)

    return Ruta(
        distancia_km=round(km, 3),
        duracion_min=max(int(round(segundos / 60)), 1) if km > 0 else 0,
        proveedor=PROVEEDOR_ORS,
    )


async def buscar_direccion(texto: str, limite: int = 5) -> list[Lugar]:
    """Geocodificacion directa (Pelias de ORS), acotada a Bolivia. Sin API key devuelve vacio:
    el frontend entonces deja que la clienta mueva el pin del mapa a mano."""
    if not hay_proveedor_externo() or not texto.strip():
        return []

    try:
        async with httpx.AsyncClient(timeout=settings.ors_timeout) as cliente:
            respuesta = await cliente.get(
                f"{settings.ors_base_url}/geocode/search",
                params={
                    "api_key": settings.ors_api_key,
                    "text": texto,
                    "boundary.country": "BO",
                    "size": limite,
                },
            )
            respuesta.raise_for_status()
            datos = respuesta.json()
    except (httpx.HTTPError, ValueError):
        return []

    lugares: list[Lugar] = []
    for elemento in datos.get("features", []):
        coordenadas = (elemento.get("geometry") or {}).get("coordinates") or []
        propiedades = elemento.get("properties") or {}
        if len(coordenadas) != 2:
            continue
        lugares.append(
            Lugar(
                etiqueta=propiedades.get("label") or propiedades.get("name") or texto,
                latitud=float(coordenadas[1]),
                longitud=float(coordenadas[0]),
                ciudad=propiedades.get("locality") or propiedades.get("region"),
            )
        )
    return lugares


async def direccion_de_punto(latitud: float, longitud: float) -> Lugar | None:
    """Geocodificacion inversa: que direccion hay donde la clienta solto el pin del mapa."""
    if not hay_proveedor_externo():
        return None

    try:
        async with httpx.AsyncClient(timeout=settings.ors_timeout) as cliente:
            respuesta = await cliente.get(
                f"{settings.ors_base_url}/geocode/reverse",
                params={
                    "api_key": settings.ors_api_key,
                    "point.lat": latitud,
                    "point.lon": longitud,
                    "size": 1,
                },
            )
            respuesta.raise_for_status()
            datos = respuesta.json()
    except (httpx.HTTPError, ValueError):
        return None

    elementos = datos.get("features") or []
    if not elementos:
        return None
    propiedades = elementos[0].get("properties") or {}
    return Lugar(
        etiqueta=propiedades.get("label") or "",
        latitud=latitud,
        longitud=longitud,
        ciudad=propiedades.get("locality") or propiedades.get("region"),
    )
