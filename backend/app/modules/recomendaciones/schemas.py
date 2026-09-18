from uuid import UUID

from pydantic import BaseModel


class ProductoRecomendadoOut(BaseModel):
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
    motivo: str
