from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field, field_validator

from app.modules.acceso_y_organizacion.usuarios.politica_password import validar_password


class CuentaOut(BaseModel):
    """Una cuenta cualquiera de la plataforma: personal de una empresa, clienta o equipo de la
    plataforma (SUPERADMIN). `empresa` es NULL para clientas y para el equipo de la plataforma."""

    id: UUID
    email: str
    nombre: str
    apellido: str
    telefono: str | None
    tipo: str  # CLIENTE | STAFF
    rol_id: int | None
    rol: str | None
    empresa_id: UUID | None
    empresa: str | None
    activo: bool
    bloqueado: bool
    ultimo_acceso: datetime | None
    creado_en: datetime


class CuentaUpdate(BaseModel):
    email: EmailStr
    nombre: str = Field(min_length=1, max_length=80)
    apellido: str = Field(min_length=1, max_length=80)
    telefono: str | None = Field(default=None, max_length=30)
    # solo el personal de una empresa tiene rol que cambiar; en el resto se ignora si no cambia
    rol_id: int | None = None


class EquipoIn(BaseModel):
    """Alta de otro integrante del equipo de la plataforma (rol SUPERADMIN)."""

    email: EmailStr
    nombre: str = Field(min_length=1, max_length=80)
    apellido: str = Field(min_length=1, max_length=80)
    password: str = Field(max_length=72)

    @field_validator("password")
    @classmethod
    def password_segura(cls, value: str) -> str:
        return validar_password(value)


class RolPlataformaOut(BaseModel):
    id: int
    nombre: str
    descripcion: str | None
    es_sistema: bool
    empresa_id: UUID | None
    empresa: str | None
    usuarios: int = 0
    permisos: list[int] = []
    # los cuatro roles que el codigo nombra (SUPERADMIN, ADMIN, ENCARGADO, CAJERO): no se
    # renombran ni se eliminan; SUPERADMIN ademas no cambia sus permisos
    protegido: bool = False


class RolPlataformaIn(BaseModel):
    nombre: str = Field(min_length=2, max_length=60)
    descripcion: str | None = Field(default=None, max_length=200)
    # NULL = rol del sistema, compartido por todas las empresas; con valor, rol propio de esa empresa
    empresa_id: UUID | None = None


class RolPlataformaUpdate(BaseModel):
    nombre: str = Field(min_length=2, max_length=60)
    descripcion: str | None = Field(default=None, max_length=200)
