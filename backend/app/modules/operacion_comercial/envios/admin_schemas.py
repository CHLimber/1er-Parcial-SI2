from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

# Transiciones validas del envio (las valida el router, no la base). El reparto lo hace un
# servicio de delivery externo, asi que la sucursal solo marca los dos momentos que le tocan:
#   PENDIENTE  -> DESPACHADO | CANCELADO
#   DESPACHADO -> ENTREGADO  | FALLIDO
#   FALLIDO    -> DESPACHADO (segundo intento) | CANCELADO
#   ENTREGADO  -> terminal
EstadoEnvio = Literal["PENDIENTE", "DESPACHADO", "ENTREGADO", "FALLIDO", "CANCELADO"]


class CambioEstadoIn(BaseModel):
    estado: EstadoEnvio
    observacion: str | None = Field(default=None, max_length=250)


class EnvioAdminOut(BaseModel):
    id: UUID
    venta_id: UUID
    numero_venta: str
    estado: str
    sucursal_id: UUID
    sucursal: str
    cliente: str
    cliente_telefono: str | None
    ciudad: str
    direccion: str
    referencia: str | None
    latitud: float | None
    longitud: float | None
    distancia_km: float
    duracion_min: int
    costo: float
    proveedor_ruteo: str
    total_venta: float
    observacion: str | None
    creado_en: datetime
    despachado_en: datetime | None
    cerrado_en: datetime | None


class ItemEnvioOut(BaseModel):
    """Que hay que meter en la bolsa: el detalle de la venta que se reparte."""

    producto: str
    sku: str
    talla: str
    color: str
    cantidad: int


class EventoAdminOut(BaseModel):
    estado: str
    nota: str | None
    usuario: str | None
    fecha: datetime


class EnvioAdminDetalleOut(EnvioAdminOut):
    items: list[ItemEnvioOut]
    eventos: list[EventoAdminOut]


class ResumenEnviosOut(BaseModel):
    """Contadores del tablero de despacho, por estado."""

    pendientes: int
    despachados: int
    entregados_hoy: int
    fallidos: int
