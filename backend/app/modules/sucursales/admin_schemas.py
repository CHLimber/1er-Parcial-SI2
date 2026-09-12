from datetime import time
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, Field


class SucursalIn(BaseModel):
    codigo: str = Field(min_length=2, max_length=20)
    nombre: str = Field(min_length=2, max_length=120)
    ciudad: str
    direccion: str = Field(min_length=3, max_length=250)
    telefono: str | None = Field(default=None, max_length=30)
    latitud: Decimal | None = Field(default=None, ge=-90, le=90)
    longitud: Decimal | None = Field(default=None, ge=-180, le=180)
    hora_apertura: time | None = None
    hora_cierre: time | None = None
    cantidad_vestidores: int = Field(default=0, ge=0, le=50)


class EstadoIn(BaseModel):
    activa: bool


class CajaIn(BaseModel):
    codigo: str = Field(min_length=2, max_length=20)
    nombre: str = Field(min_length=2, max_length=60)


class CajaEstadoIn(BaseModel):
    activa: bool


class CajaOut(BaseModel):
    id: UUID
    sucursal_id: UUID
    codigo: str
    nombre: str
    activa: bool
    sesion_abierta: bool


class SucursalAdminOut(BaseModel):
    id: UUID
    codigo: str
    nombre: str
    ciudad: str
    direccion: str
    telefono: str | None
    latitud: Decimal | None
    longitud: Decimal | None
    hora_apertura: time | None
    hora_cierre: time | None
    cantidad_vestidores: int
    activa: bool
    empleados: int = 0
    cajas: int = 0
