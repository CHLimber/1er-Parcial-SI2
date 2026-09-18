from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field


class MensajeIn(BaseModel):
    rol: Literal["user", "assistant"]
    texto: str = Field(min_length=1, max_length=4000)


class ChatIn(BaseModel):
    # El backend no persiste nada (CU18): el frontend reenvia la conversacion completa en
    # cada request, esta lista es toda la memoria que tiene el asistente de un turno a otro.
    mensajes: list[MensajeIn] = Field(min_length=1, max_length=40)


class ProductoOut(BaseModel):
    """Mismo shape que catalogo.schemas.ProductoOut (duplicado a proposito, ver CLAUDE.md:
    ningun modulo importa schemas de otro) para que el frontend renderice estas sugerencias
    con el mismo <li app-producto-card> que el catalogo y las recomendaciones de CU17."""

    id: UUID
    codigo: str
    nombre: str
    slug: str
    descripcion: str | None
    precio_base: float
    genero: str | None
    categoria: str
    categoria_slug: str
    marca: str | None
    destacado: bool
    imagen_url: str | None
    tallas: list[str]
    agotado: bool


class ChatOut(BaseModel):
    respuesta: str
    productos_sugeridos: list[ProductoOut]
