from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field


class CheckoutIn(BaseModel):
    sucursal_id: UUID | None = Field(
        default=None, description="Requerido salvo que el carrito venga de una reserva"
    )
    entrega: Literal["RETIRO_SUCURSAL", "DOMICILIO"] = "RETIRO_SUCURSAL"
    direccion_id: UUID | None = None
    pasarela: Literal["STRIPE", "LIBELULA"]
    codigo_cupon: str | None = Field(default=None, max_length=40)
    canal: Literal["WEB", "MOVIL"] = "WEB"


class CheckoutOut(BaseModel):
    venta_id: UUID
    numero: str
    pago_id: UUID
    pasarela: str
    id_transaccion: str
    url_pago: str
    subtotal: float
    descuento: float
    iva: float
    total: float
    estado: str


class VentaItemOut(BaseModel):
    variante_id: UUID
    sku: str
    producto: str
    talla: str
    color: str
    cantidad: int
    precio_unitario: float
    subtotal: float


class PagoOut(BaseModel):
    id: UUID
    metodo: str
    pasarela: str | None
    monto: float
    estado: str
    id_transaccion: str | None
    creado_en: datetime
    confirmado_en: datetime | None


class ComprobanteOut(BaseModel):
    numero: str
    tipo: str
    emitido_en: datetime


class VentaOut(BaseModel):
    id: UUID
    numero: str
    canal: str
    entrega: str
    estado: str
    sucursal: str
    subtotal: float
    descuento: float
    iva: float
    total: float
    fecha: datetime
    items: list[VentaItemOut]
    pago: PagoOut | None
    comprobante: ComprobanteOut | None


class VentaResumenOut(BaseModel):
    id: UUID
    numero: str
    canal: str
    estado: str
    total: float
    fecha: datetime
    sucursal: str


class VentaPosItemIn(BaseModel):
    variante_id: UUID
    cantidad: int = Field(default=1, ge=1, le=50)


class VentaPosIn(BaseModel):
    items: list[VentaPosItemIn] = Field(min_length=1, max_length=50)
    metodo_pago: Literal["EFECTIVO", "TARJETA", "QR"]
    monto_recibido: float | None = Field(default=None, ge=0)


class ItemRechazadoPosOut(BaseModel):
    variante_id: UUID
    sku: str
    motivo: str


class VentaPosOut(BaseModel):
    venta_id: UUID
    numero: str
    comprobante_numero: str
    items: list[VentaItemOut]
    rechazados: list[ItemRechazadoPosOut]
    subtotal: float
    iva: float
    total: float
    vuelto: float | None
