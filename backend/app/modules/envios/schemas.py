from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, model_validator

# Los montos van en float y no en Decimal a proposito: Pydantic v2 serializa Decimal como
# string y el frontend espera number (mismo criterio que catalogo/ y reportes/, ver
# PENDIENTES.txt 2.5).


class CotizacionIn(BaseModel):
    sucursal_id: UUID
    # o se cotiza contra una direccion guardada, o contra un punto suelto del mapa
    # (la clienta todavia no la guardo pero ya quiere ver cuanto le sale)
    direccion_id: UUID | None = None
    latitud: float | None = Field(default=None, ge=-90, le=90)
    longitud: float | None = Field(default=None, ge=-180, le=180)
    monto_pedido: float = Field(default=0, ge=0)

    @model_validator(mode="after")
    def _exigir_destino(self) -> "CotizacionIn":
        if self.direccion_id is None and (self.latitud is None or self.longitud is None):
            raise ValueError("Indica una direccion guardada o un punto del mapa")
        return self


class CotizacionOut(BaseModel):
    distancia_km: float
    duracion_min: int
    # ORS (openrouteservice) o HAVERSINE (respaldo sin API key / servicio caido)
    proveedor: str
    costo: float
    es_gratis: bool
    dentro_cobertura: bool
    radio_km: float
    tarifa_base: float
    precio_km: float
    gratis_desde: float


class EnvioEventoOut(BaseModel):
    estado: str
    nota: str | None
    fecha: datetime


class EnvioOut(BaseModel):
    """Seguimiento del envio para la clienta que compro."""

    id: UUID
    venta_id: UUID
    numero_venta: str
    estado: str
    sucursal: str
    ciudad: str
    direccion: str
    referencia: str | None
    latitud: float | None
    longitud: float | None
    distancia_km: float
    duracion_min: int
    costo: float
    observacion: str | None
    creado_en: datetime
    despachado_en: datetime | None
    cerrado_en: datetime | None
    eventos: list[EnvioEventoOut]
