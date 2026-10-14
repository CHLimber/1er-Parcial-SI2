from datetime import datetime
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field


class PlanOut(BaseModel):
    id: int
    codigo: str
    nombre: str
    descripcion: str | None
    precio_mensual: Decimal
    max_empleados: int | None  # None = sin limite
    max_cajas: int | None
    perfiles_clientes: bool
    traspasos: bool
    ia_reportes: bool


class SuscripcionOut(BaseModel):
    """La suscripcion de un tenant (sucursal) con su uso actual contra los topes del plan."""

    sucursal_id: UUID
    sucursal: str
    ciudad: str
    plan: PlanOut
    estado: str  # el guardado; `vigente` es el que manda
    vigente: bool
    inicio: datetime
    vence_en: datetime
    dias_restantes: int
    empleados: int
    cajas: int


class CheckoutSuscripcionIn(BaseModel):
    plan_codigo: str = Field(min_length=3, max_length=20)
    meses: int = Field(default=1, ge=1, le=12)
    sucursal_id: UUID | None = None  # solo el ADMIN de la plataforma elige otra sucursal


class CheckoutSuscripcionOut(BaseModel):
    pago_id: UUID
    monto: Decimal
    url_pago: str  # Checkout hospedado de Stripe


class PagoManualIn(BaseModel):
    """El ADMIN de la plataforma registra un pago recibido fuera de Stripe."""

    plan_codigo: str = Field(min_length=3, max_length=20)
    meses: int = Field(default=1, ge=1, le=12)
    metodo: Literal["EFECTIVO", "TRANSFERENCIA"]


class PagoSuscripcionOut(BaseModel):
    id: UUID
    sucursal: str
    plan: str
    meses: int
    monto: Decimal
    metodo: str
    estado: str
    periodo_desde: datetime | None
    periodo_hasta: datetime | None
    pagado_por: str | None
    creado_en: datetime
    confirmado_en: datetime | None
