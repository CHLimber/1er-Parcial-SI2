from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class WebhookOut(BaseModel):
    procesado: bool
    venta_estado: str | None = None
    pago_estado: str | None = None
    mensaje: str


class ConfigPagoOut(BaseModel):
    """CU06: la publishable key de Stripe no es secreta (esta pensada para viajar al navegador),
    asi que se expone por un endpoint publico en vez de hornearla en el build del frontend --
    asi cambia por entorno (local/Railway) sin recompilar."""

    stripe_publishable_key: str


class InformarPagoIn(BaseModel):
    """2.19.1.c: la clienta avisa que ya pago el QR. La referencia (nro. de operacion del banco,
    nombre del titular, etc.) es opcional y solo ayuda al cajero a encontrar el deposito."""

    referencia: str | None = Field(default=None, max_length=200)


class InformarPagoOut(BaseModel):
    venta_id: UUID
    pago_id: UUID
    pago_estado: str
    informado_en: datetime
    referencia_cliente: str | None
    mensaje: str
