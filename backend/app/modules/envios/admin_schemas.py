from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

# Transiciones validas del envio (las valida el router, no la base):
#   PENDIENTE -> ASIGNADO | CANCELADO
#   ASIGNADO  -> EN_RUTA  | PENDIENTE (se libera al repartidor) | CANCELADO
#   EN_RUTA   -> ENTREGADO | FALLIDO
#   FALLIDO   -> EN_RUTA (segundo intento) | CANCELADO
#   ENTREGADO -> terminal
EstadoEnvio = Literal["PENDIENTE", "ASIGNADO", "EN_RUTA", "ENTREGADO", "FALLIDO", "CANCELADO"]


class AsignarRepartidorIn(BaseModel):
    repartidor_id: UUID
    observacion: str | None = Field(default=None, max_length=250)


class CambioEstadoIn(BaseModel):
    estado: EstadoEnvio
    observacion: str | None = Field(default=None, max_length=250)


class RepartidorOut(BaseModel):
    id: UUID
    nombre: str
    sucursal_id: UUID
    sucursal: str
    envios_activos: int


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
    repartidor_id: UUID | None
    repartidor: str | None
    observacion: str | None
    creado_en: datetime
    asignado_en: datetime | None
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
    asignados: int
    en_ruta: int
    entregados_hoy: int
    fallidos: int
