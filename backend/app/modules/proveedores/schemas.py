from uuid import UUID

from pydantic import BaseModel, EmailStr, Field


class ProveedorIn(BaseModel):
    nombre: str = Field(min_length=2, max_length=150)
    nit: str | None = Field(default=None, max_length=30)
    contacto: str | None = Field(default=None, max_length=120)
    email: EmailStr | None = None
    telefono: str | None = Field(default=None, max_length=30)


class EstadoIn(BaseModel):
    activo: bool


class ProveedorOut(BaseModel):
    id: UUID
    nombre: str
    nit: str | None
    contacto: str | None
    email: str | None
    telefono: str | None
    activo: bool
    # para que el panel muestre por que un proveedor no se puede borrar
    productos: int = 0
    recepciones: int = 0
