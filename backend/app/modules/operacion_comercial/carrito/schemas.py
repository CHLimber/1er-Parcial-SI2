from uuid import UUID

from pydantic import BaseModel, Field


class CarritoItemIn(BaseModel):
    variante_id: UUID
    cantidad: int = Field(default=1, ge=1, le=20)


class CarritoItemCantidadIn(BaseModel):
    cantidad: int = Field(ge=1, le=20)


class CarritoItemOut(BaseModel):
    id: UUID
    variante_id: UUID
    sku: str
    producto: str
    producto_slug: str
    talla: str
    color: str
    codigo_hex: str
    imagen_url: str | None
    precio_unitario: float
    cantidad: int
    subtotal: float


class CarritoOut(BaseModel):
    id: UUID
    estado: str
    reserva_id: UUID | None
    reserva_codigo: str | None
    items: list[CarritoItemOut]
    cantidad_items: int
    subtotal: float
