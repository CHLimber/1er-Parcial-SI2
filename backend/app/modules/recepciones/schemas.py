from datetime import date, datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, Field


class RecepcionIn(BaseModel):
    sucursal_id: UUID | None = None  # si no se manda, la sucursal del empleado
    proveedor_id: UUID
    coleccion_id: UUID | None = None
    numero: str | None = Field(default=None, max_length=40)
    fecha: date | None = None


class DetalleIn(BaseModel):
    variante_id: UUID
    cantidad: int = Field(gt=0, le=100_000)
    costo_unitario: Decimal = Field(ge=0, max_digits=12, decimal_places=2)


class DetalleOut(BaseModel):
    id: UUID
    variante_id: UUID
    sku: str
    producto: str
    talla: str
    color: str
    cantidad: int
    costo_unitario: Decimal
    subtotal: Decimal


class RecepcionOut(BaseModel):
    id: UUID
    numero: str
    fecha: date
    estado: str
    sucursal_id: UUID
    sucursal: str
    proveedor_id: UUID
    proveedor: str
    coleccion_id: UUID | None
    coleccion: str | None
    total: Decimal | None
    usuario_id: UUID | None
    registrado_por: str | None
    lineas: int
    unidades: int


class RecepcionDetalleOut(RecepcionOut):
    detalle: list[DetalleOut]


class VarianteBuscadaOut(BaseModel):
    id: UUID
    sku: str
    producto: str
    talla: str
    color: str
    codigo_hex: str
    precio_base: Decimal
    stock_sucursal: int


class MovimientoOut(BaseModel):
    """Asiento del kardex generado al confirmar la recepcion, para mostrar el efecto real."""

    variante_id: UUID
    sku: str
    producto: str
    cantidad: int
    saldo_anterior: int
    saldo_nuevo: int
    fecha: datetime
