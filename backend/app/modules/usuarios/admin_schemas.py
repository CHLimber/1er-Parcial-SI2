import re
from datetime import date, datetime
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field, field_validator


def _validar_password(value: str) -> str:
    if not re.search(r"[a-z]", value):
        raise ValueError("La contrasena debe tener al menos una letra minuscula")
    if not re.search(r"[A-Z]", value):
        raise ValueError("La contrasena debe tener al menos una letra mayuscula")
    if not re.search(r"\d", value):
        raise ValueError("La contrasena debe tener al menos un numero")
    return value


class EmpleadoOut(BaseModel):
    sucursal_id: UUID
    sucursal: str
    cargo: str
    ci: str | None
    fecha_ingreso: date | None
    activo: bool


class UsuarioAdminOut(BaseModel):
    id: UUID
    email: str
    nombre: str
    apellido: str
    telefono: str | None
    tipo: str
    rol_id: int | None
    rol: str | None
    activo: bool
    email_verificado: bool
    ultimo_acceso: datetime | None
    creado_en: datetime
    empleado: EmpleadoOut | None = None


class StaffIn(BaseModel):
    """Alta de personal (CU13). El esquema exige rol_id para todo usuario STAFF
    (constraint ck_usuario_rol), y empleado lo ata a una sucursal."""

    email: EmailStr
    password: str = Field(min_length=8, max_length=72)
    nombre: str = Field(min_length=1, max_length=80)
    apellido: str = Field(min_length=1, max_length=80)
    telefono: str | None = Field(default=None, max_length=30)
    rol_id: int
    sucursal_id: UUID
    cargo: str
    ci: str | None = Field(default=None, max_length=20)
    fecha_ingreso: date | None = None

    @field_validator("password")
    @classmethod
    def password_segura(cls, value: str) -> str:
        return _validar_password(value)


class StaffUpdate(BaseModel):
    email: EmailStr
    nombre: str = Field(min_length=1, max_length=80)
    apellido: str = Field(min_length=1, max_length=80)
    telefono: str | None = Field(default=None, max_length=30)
    rol_id: int
    sucursal_id: UUID
    cargo: str
    ci: str | None = Field(default=None, max_length=20)
    fecha_ingreso: date | None = None


class ClienteUpdate(BaseModel):
    email: EmailStr
    nombre: str = Field(min_length=1, max_length=80)
    apellido: str = Field(min_length=1, max_length=80)
    telefono: str | None = Field(default=None, max_length=30)


class EstadoIn(BaseModel):
    activo: bool


class PasswordIn(BaseModel):
    password: str = Field(min_length=8, max_length=72)

    @field_validator("password")
    @classmethod
    def password_segura(cls, value: str) -> str:
        return _validar_password(value)


class PermisoOut(BaseModel):
    id: int
    codigo: str
    modulo: str
    descripcion: str | None


class RolOut(BaseModel):
    id: int
    nombre: str
    descripcion: str | None
    es_sistema: bool
    usuarios: int = 0
    permisos: list[int] = []


class RolIn(BaseModel):
    nombre: str = Field(min_length=2, max_length=60)
    descripcion: str | None = Field(default=None, max_length=200)


class PermisosIn(BaseModel):
    permisos: list[int]
