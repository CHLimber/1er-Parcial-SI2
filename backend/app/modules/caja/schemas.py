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


class ArqueoOut(BaseModel):
    """Foto de la sesion abierta para que el cajero cuente el cajon ANTES de declarar el cierre.
    monto_sistema es lo que deberia haber en efectivo: monto_inicial + ventas cobradas en
    EFECTIVO (las de TARJETA/QR/TRANSFERENCIA/PASARELA no tocan el cajon fisico)."""

    sesion_id: UUID
    monto_inicial: float
    monto_sistema: float
    cantidad_ventas: int
    total_ventas: float
    por_metodo: dict[str, float]


class CerrarSesionIn(BaseModel):
    monto_declarado: float = Field(ge=0, description="Lo que el cajero conto de verdad en el cajon")


class SesionCerradaOut(BaseModel):
    id: UUID
    caja_id: UUID
    caja_nombre: str
    abierta_en: datetime
    cerrada_en: datetime
    monto_inicial: float
    monto_sistema: float
    monto_declarado: float
    diferencia: float
    estado: str


class VarianteBusquedaOut(BaseModel):
    variante_id: UUID
    sku: str
    producto: str
    talla: str
    color: str
    precio: float
    disponible: int
