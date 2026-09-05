from datetime import date, datetime, time
from typing import Literal
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


# --- CU08: Atender Reserva (Encargado de Sucursal) --------------------------


class ClienteBreveOut(BaseModel):
    nombre: str
    apellido: str
    email: str
    telefono: str | None


class ReservaStaffOut(BaseModel):
    id: UUID
    codigo: str
    cliente: ClienteBreveOut
    sucursal_id: UUID
    sucursal: str
    estado: str
    fecha_visita: date
    hora_visita: time
    expira_en: datetime
    creada_en: datetime
    observaciones: str | None
    vestidor_asignado: str | None
    atendida_en: datetime | None
    items: list[ReservaItemOut]


class ItemDisponibilidadIn(BaseModel):
    variante_id: UUID
    disponible: bool = True
    motivo: str | None = Field(default=None, max_length=250)


class PrepararReservaIn(BaseModel):
    items: list[ItemDisponibilidadIn] = Field(min_length=1, max_length=20)


class MarcarPresenteIn(BaseModel):
    vestidor_asignado: str | None = Field(default=None, max_length=20)


class DecisionItemIn(BaseModel):
    variante_id: UUID
    comprado: bool


class ResolverReservaIn(BaseModel):
    decisiones: list[DecisionItemIn] = Field(min_length=1, max_length=20)
    metodo_pago: Literal["EFECTIVO", "TARJETA", "QR"] | None = None
    monto_recibido: float | None = Field(default=None, ge=0)


class ResolverReservaOut(BaseModel):
    reserva: ReservaStaffOut
    venta_id: UUID | None
    venta_numero: str | None
    comprobante_numero: str | None
    total_cobrado: float | None
