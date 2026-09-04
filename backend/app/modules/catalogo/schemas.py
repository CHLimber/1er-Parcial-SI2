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
    categoria_slug: str
    marca: str | None
    destacado: bool
    imagen_url: str | None
    tallas: list[str]
    agotado: bool


class CategoriaOut(BaseModel):
    id: UUID
    nombre: str
    slug: str
    categoria_padre_id: UUID | None


class TallaOut(BaseModel):
    id: int
    codigo: str
    tipo: str


class ColorOut(BaseModel):
    id: int
    nombre: str
    codigo_hex: str


class TemporadaOut(BaseModel):
    id: UUID
    nombre: str
    tipo: str


class FiltrosOut(BaseModel):
    categorias: list[CategoriaOut]
    tallas: list[TallaOut]
    colores: list[ColorOut]
    temporadas: list[TemporadaOut]


class DisponibilidadSucursalOut(BaseModel):
    sucursal_id: UUID
    sucursal: str
    ciudad: str
    disponible: int
    situacion: str


class VarianteOut(BaseModel):
    id: UUID
    sku: str
    talla: str
    color: str
    codigo_hex: str
    precio: float
    disponibilidad: list[DisponibilidadSucursalOut]


class ProductoDetalleOut(ProductoOut):
    material: str | None
    variantes: list[VarianteOut]
