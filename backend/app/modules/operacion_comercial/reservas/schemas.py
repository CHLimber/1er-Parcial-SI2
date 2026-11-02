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
    # precio de lista unitario sin IVA (el que se cobra en el vestidor); lo usa la pantalla del
    # personal para mostrar el total antes de cobrar
    precio: float | None = None


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


class CobroStripeIn(BaseModel):
    """Cobro con tarjeta (Stripe) en el vestidor: las mismas decisiones que /resolver, pero la
    venta queda PENDIENTE hasta que Stripe confirma el pago (webhook o verificacion)."""

    decisiones: list[DecisionItemIn] = Field(min_length=1, max_length=20)
    # WEB monta el Checkout embebido (Stripe.js); MOVIL abre el PaymentSheet nativo
    canal: Literal["WEB", "MOVIL"] = "WEB"


class CobroStripeOut(BaseModel):
    """Estado del cobro con tarjeta de una reserva atendida en el vestidor.
    SIN_COBRO: no hay ninguno. PENDIENTE: esperando que la clienta pague (con client_secret para
    mostrar el formulario). PAGADA/ENTREGADA: cobrado, la reserva quedo convertida. ANULADA: se
    cancelo o Stripe lo rechazo."""

    estado: str
    venta_id: UUID | None = None
    venta_numero: str | None = None
    total: float | None = None
    client_secret: str | None = None
    canal: str | None = None
    comprobante_numero: str | None = None
    mensaje: str | None = None


class RechazarReservaIn(BaseModel):
    """2.19.1.a: el Encargado rechaza una reserva PENDIENTE; el motivo le llega al cliente."""

    motivo: str = Field(min_length=3, max_length=150)


class CancelarReservaIn(BaseModel):
    """2.19.2: el cliente cancela su propia reserva; el motivo es opcional."""

    motivo: str | None = Field(default=None, max_length=150)


class ResolverReservaOut(BaseModel):
    reserva: ReservaStaffOut
    venta_id: UUID | None
    venta_numero: str | None
    comprobante_numero: str | None
    total_cobrado: float | None
