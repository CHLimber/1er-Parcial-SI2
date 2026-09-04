import re
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field, field_validator


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class RegistroRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=72)
    nombre: str = Field(min_length=1, max_length=80)
    apellido: str = Field(min_length=1, max_length=80)
    telefono: str | None = Field(default=None, max_length=30)

    @field_validator("password")
    @classmethod
    def password_segura(cls, value: str) -> str:
        if not re.search(r"[a-z]", value):
            raise ValueError("La contrasena debe tener al menos una letra minuscula")
        if not re.search(r"[A-Z]", value):
            raise ValueError("La contrasena debe tener al menos una letra mayuscula")
        if not re.search(r"\d", value):
            raise ValueError("La contrasena debe tener al menos un numero")
        return value


class UsuarioOut(BaseModel):
    id: UUID
    email: str
    nombre: str
    apellido: str
    tipo: str
    rol: str | None = None


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    usuario: UsuarioOut
