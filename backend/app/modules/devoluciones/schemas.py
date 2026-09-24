from datetime import datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, Field


class LineaDevolucionIn(BaseModel):
    venta_detalle_id: UUID
    cantidad: int = Field(gt=0, le=10_000)


class DevolucionIn(BaseModel):
    venta_id: UUID
    motivo: str = Field(min_length=3, max_length=250)
    lineas: list[LineaDevolucionIn] = Field(min_length=1, max_length=200)


class RechazoIn(BaseModel):
    motivo: str = Field(min_length=3, max_length=250)


class LineaVentaOut(BaseModel):
    """Una linea de la venta con lo que todavia se puede devolver de ella."""

    venta_detalle_id: UUID
    variante_id: UUID
    sku: str
    producto: str
    talla: str
    color: str
    cantidad_vendida: int
    precio_unitario: Decimal
    subtotal: Decimal
    devuelta: int  # unidades en devoluciones APROBADAS
    en_tramite: int  # unidades en devoluciones SOLICITADAS
    devolvible: int  # vendida - devuelta - en_tramite
    reembolso_unitario: Decimal  # lo que se reintegra por unidad (descuento e IVA prorrateados)


class VentaDevolvibleOut(BaseModel):
    venta_id: UUID
    numero: str
    fecha: datetime
    estado: str
    canal: str
    sucursal_id: UUID
    sucursal: str
    cliente: str | None
    subtotal: Decimal
    descuento: Decimal
    costo_envio: Decimal
    total: Decimal
    total_devuelto: Decimal  # suma de devoluciones APROBADAS
    lineas: list[LineaVentaOut]


class DetalleDevolucionOut(BaseModel):
    id: UUID
    venta_detalle_id: UUID
    variante_id: UUID
    sku: str
    producto: str
    talla: str
    color: str
    cantidad: int
    cantidad_vendida: int
    precio_unitario: Decimal


class DevolucionOut(BaseModel):
    id: UUID
    venta_id: UUID
    venta_numero: str
    venta_total: Decimal
    sucursal_id: UUID
    sucursal: str
    cliente: str | None
    motivo: str
    monto_devuelto: Decimal
    estado: str
    fecha: datetime
    registrada_por: str | None
    resuelta_por: str | None
    resuelta_en: datetime | None
    motivo_rechazo: str | None
    lineas: int
    unidades: int


class DevolucionDetalleOut(DevolucionOut):
    detalle: list[DetalleDevolucionOut]
    pago_reembolsado: bool  # True si la devolucion completo la venta y el pago paso a REEMBOLSADO
