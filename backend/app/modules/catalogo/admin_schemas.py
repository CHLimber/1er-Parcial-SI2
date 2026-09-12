from datetime import date
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, Field


class ProductoIn(BaseModel):
    codigo: str = Field(min_length=2, max_length=40)
    nombre: str = Field(min_length=2, max_length=180)
    descripcion: str | None = None
    categoria_id: UUID
    marca_id: UUID | None = None
    proveedor_id: UUID | None = None
    temporada_id: UUID | None = None
    coleccion_id: UUID | None = None
    material: str | None = Field(default=None, max_length=120)
    genero: str | None = None
    precio_base: Decimal = Field(ge=0, max_digits=12, decimal_places=2)
    destacado: bool = False


class VarianteIn(BaseModel):
    talla_id: int
    color_id: int
    sku: str = Field(min_length=2, max_length=60)
    codigo_barras: str | None = Field(default=None, max_length=60)
    # ambos opcionales: si van vacios la variante hereda producto.precio_base
    precio: Decimal | None = Field(default=None, ge=0, max_digits=12, decimal_places=2)
    precio_oferta: Decimal | None = Field(default=None, ge=0, max_digits=12, decimal_places=2)


class ImagenIn(BaseModel):
    url: str = Field(min_length=4)
    uso: str = "CATALOGO"
    formato: str | None = None
    color_id: int | None = None
    es_principal: bool = False
    orden: int = 0


class EstadoIn(BaseModel):
    activo: bool


class CategoriaIn(BaseModel):
    nombre: str = Field(min_length=2, max_length=80)
    categoria_padre_id: UUID | None = None
    imagen_url: str | None = None
    orden: int = 0


class CategoriaEstadoIn(BaseModel):
    activa: bool


class MarcaIn(BaseModel):
    nombre: str = Field(min_length=1, max_length=80)
    logo_url: str | None = None


class ImagenOut(BaseModel):
    id: UUID
    url: str
    uso: str
    formato: str | None
    color_id: int | None
    es_principal: bool
    orden: int


class VarianteAdminOut(BaseModel):
    id: UUID
    sku: str
    codigo_barras: str | None
    talla_id: int
    talla: str
    color_id: int
    color: str
    codigo_hex: str
    precio: Decimal | None
    precio_oferta: Decimal | None
    activa: bool
    stock_fisico: int
    stock_disponible: int


class ProductoAdminOut(BaseModel):
    id: UUID
    codigo: str
    nombre: str
    slug: str
    descripcion: str | None
    categoria_id: UUID
    categoria: str
    marca_id: UUID | None
    marca: str | None
    proveedor_id: UUID | None
    proveedor: str | None
    temporada_id: UUID | None
    temporada: str | None
    coleccion_id: UUID | None
    coleccion: str | None
    material: str | None
    genero: str | None
    precio_base: Decimal
    destacado: bool
    activo: bool
    variantes_activas: int
    stock_total: int


class ProductoAdminDetalleOut(ProductoAdminOut):
    variantes: list[VarianteAdminOut]
    imagenes: list[ImagenOut]


class CategoriaAdminOut(BaseModel):
    id: UUID
    nombre: str
    slug: str
    categoria_padre_id: UUID | None
    categoria_padre: str | None
    imagen_url: str | None
    orden: int
    activa: bool
    productos: int


class MarcaAdminOut(BaseModel):
    id: UUID
    nombre: str
    logo_url: str | None


class OpcionOut(BaseModel):
    id: UUID
    nombre: str


class TemporadaAdminOut(BaseModel):
    id: UUID
    nombre: str
    tipo: str
    fecha_inicio: date
    fecha_fin: date


class ColeccionOut(BaseModel):
    id: UUID
    nombre: str
    temporada_id: UUID


class TallaOut(BaseModel):
    id: int
    codigo: str
    tipo: str


class ColorOut(BaseModel):
    id: int
    nombre: str
    codigo_hex: str


class ReferenciasOut(BaseModel):
    """Todo lo que el formulario de alta de prenda necesita en un solo viaje."""

    categorias: list[CategoriaAdminOut]
    marcas: list[MarcaAdminOut]
    proveedores: list[OpcionOut]
    temporadas: list[TemporadaAdminOut]
    colecciones: list[ColeccionOut]
    tallas: list[TallaOut]
    colores: list[ColorOut]
    generos: list[str]
