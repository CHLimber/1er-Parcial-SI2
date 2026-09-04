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
