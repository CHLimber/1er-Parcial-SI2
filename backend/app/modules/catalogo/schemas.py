from uuid import UUID

from pydantic import BaseModel


class ProductoOut(BaseModel):
    id: UUID
    codigo: str
    nombre: str
    slug: str
    descripcion: str | None
    precio_base: float
    genero: str | None
    categoria: str
    marca: str | None
    destacado: bool
