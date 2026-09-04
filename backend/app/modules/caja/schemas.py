from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class CajaOut(BaseModel):
    id: UUID
    codigo: str
    nombre: str
    tiene_sesion_abierta: bool


class AbrirSesionIn(BaseModel):
    caja_id: UUID
    monto_inicial: float = Field(default=0, ge=0)


class SesionCajaOut(BaseModel):
    id: UUID
    caja_id: UUID
    caja_nombre: str
    abierta_en: datetime
    monto_inicial: float
    estado: str


class VarianteBusquedaOut(BaseModel):
    variante_id: UUID
    sku: str
    producto: str
    talla: str
    color: str
    precio: float
    disponible: int
