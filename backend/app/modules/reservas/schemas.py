from datetime import date, datetime, time
from uuid import UUID

from pydantic import BaseModel, Field


class ReservaItemIn(BaseModel):
    variante_id: UUID
    cantidad: int = Field(default=1, ge=1, le=20)


class ReservaCrear(BaseModel):
    sucursal_id: UUID
    fecha_visita: date
    hora_visita: time
    observaciones: str | None = Field(default=None, max_length=250)
    items: list[ReservaItemIn] = Field(min_length=1, max_length=20)


class ItemRechazadoOut(BaseModel):
    variante_id: UUID
    sku: str
    motivo: str


class ReservaItemOut(BaseModel):
    id: UUID
    variante_id: UUID
    sku: str
    producto: str
    talla: str
    color: str
    cantidad: int
    estado_item: str


class ReservaOut(BaseModel):
    id: UUID
    codigo: str
    sucursal_id: UUID
    sucursal: str
    estado: str
    fecha_visita: date
    hora_visita: time
    expira_en: datetime
    creada_en: datetime
    observaciones: str | None
    items: list[ReservaItemOut]
    items_rechazados: list[ItemRechazadoOut] = []
