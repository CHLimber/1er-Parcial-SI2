from datetime import date
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field, field_validator

from app.modules.usuarios.politica_password import validar_password


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class CambiarPasswordRequest(BaseModel):
    """Cambiar la propia contrasena (CLIENTE o STAFF, cualquier usuario logueado). A
    diferencia de PasswordIn (CU13, `POST /admin/usuarios/{id}/password`, que resetea la
    de otro sin pedirla), esta exige la actual."""

    password_actual: str = Field(max_length=72)
    password_nueva: str = Field(max_length=72)

    @field_validator("password_nueva")
    @classmethod
    def password_segura(cls, value: str) -> str:
        return validar_password(value)


class RegistroRequest(BaseModel):
    email: EmailStr
    password: str = Field(max_length=72)
    nombre: str = Field(min_length=1, max_length=80)
    apellido: str = Field(min_length=1, max_length=80)
    telefono: str | None = Field(default=None, max_length=30)
    fecha_nacimiento: date | None = None
    acepta_marketing: bool = False

    @field_validator("password")
    @classmethod
    def password_segura(cls, value: str) -> str:
        return validar_password(value)


class UsuarioOut(BaseModel):
    id: UUID
    email: str
    nombre: str
    apellido: str
    tipo: str
    rol: str | None = None
    # cargo del empleado: el permiso dice QUE puede hacer, el cargo QUIEN es (ENCARGADO,
    # CAJERO, VENDEDOR o ALMACEN). El reparto a domicilio (CU20) lo hace un servicio externo,
    # no personal con este cargo.
    cargo: str | None = None
    # codigos de permiso del rol (CU13). El frontend los usa para mostrar u ocultar el panel.
    permisos: list[str] = []


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    usuario: UsuarioOut
