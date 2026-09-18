from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

CiudadBO = Literal[
    "SANTA_CRUZ",
    "LA_PAZ",
    "EL_ALTO",
    "COCHABAMBA",
    "SUCRE",
    "ORURO",
    "POTOSI",
    "TARIJA",
    "TRINIDAD",
    "COBIJA",
]


class DireccionIn(BaseModel):
    alias: str = Field(min_length=2, max_length=50)
    ciudad: CiudadBO
    direccion: str = Field(min_length=5, max_length=250)
    referencia: str | None = Field(default=None, max_length=250)
    # opcionales en el modelo, pero sin ellas el delivery no se puede cotizar: el frontend
    # siempre manda el pin del mapa (ver pages/mis-direcciones en la web)
    latitud: float | None = Field(default=None, ge=-90, le=90)
    longitud: float | None = Field(default=None, ge=-180, le=180)
    es_principal: bool = False


class DireccionOut(BaseModel):
    id: UUID
    alias: str
    ciudad: str
    direccion: str
    referencia: str | None
    latitud: float | None
    longitud: float | None
    es_principal: bool


class SugerenciaDireccionOut(BaseModel):
    """Resultado del geocodificador (Pelias de openrouteservice), acotado a Bolivia."""

    etiqueta: str
    latitud: float
    longitud: float
    ciudad: str | None


class BusquedaDireccionOut(BaseModel):
    # False cuando no hay ORS_API_KEY: la web lo usa para explicar que hay que ubicar el pin
    # en el mapa a mano en vez de mostrar una lista vacia sin motivo
    geocodificador_disponible: bool
    resultados: list[SugerenciaDireccionOut]
