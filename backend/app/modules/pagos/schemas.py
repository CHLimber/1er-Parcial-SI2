from typing import Literal

from pydantic import BaseModel


class WebhookIn(BaseModel):
    evento_id: str
    id_transaccion: str
    estado: Literal["APROBADO", "RECHAZADO"]


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
