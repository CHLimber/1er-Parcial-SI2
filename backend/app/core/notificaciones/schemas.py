from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class NotificacionOut(BaseModel):
    id: UUID
    tipo: str  # tipo_notificacion: RESERVA / VENTA / STOCK / PROMO / SUSCRIPCION
    titulo: str
    mensaje: str
    # A que apunta el aviso (RESERVA, VENTA, ENVIO, ...). VARCHAR libre en la tabla, no ENUM.
    entidad_tipo: str | None
    entidad_id: UUID | None
    # Venta a la que pertenece el aviso, resuelta en el servidor: igual a entidad_id si
    # entidad_tipo es VENTA, y la venta del envio si es ENVIO. Sirve para que la web y el movil
    # abran /compra/{venta_id} sin tener que conocer la tabla envio.
    venta_id: UUID | None
    leida: bool
    fecha: datetime


class NotificacionPaginadoOut(BaseModel):
    total: int
    no_leidas: int
    pagina: int
    tamanio_pagina: int
    items: list[NotificacionOut]


class CantidadNoLeidasOut(BaseModel):
    no_leidas: int


class LeerTodasOut(BaseModel):
    marcadas: int


class DispositivoIn(BaseModel):
    """Token de Firebase del celular. Lo manda la app al iniciar sesion y cada vez que Firebase lo
    renueva; al cerrar sesion lo da de baja."""

    token: str = Field(min_length=20, max_length=4096)
    plataforma: str = Field(default="ANDROID", max_length=20)
