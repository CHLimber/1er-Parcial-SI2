from datetime import datetime
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field

Segmento = Literal["NUEVA", "FRECUENTE", "VIP", "INACTIVA"]


class PerfilClienteIn(BaseModel):
    segmento: Segmento | None = None  # None = usar el sugerido por el historial
    talla_habitual: str | None = Field(default=None, max_length=10)
    estilo_preferido: str | None = Field(default=None, max_length=60)
    telefono_contacto: str | None = Field(default=None, max_length=30)
    acepta_whatsapp: bool = False
    notas: str | None = Field(default=None, max_length=500)


class AltaClienteIn(PerfilClienteIn):
    """Suma a la cartera de la sucursal una clienta que ya tiene cuenta (por su email)."""

    email: EmailStr


class ClienteTenantOut(BaseModel):
    usuario_id: UUID
    nombre: str
    email: str
    telefono: str | None
    compras: int  # en ESTA sucursal
    total_comprado: Decimal
    ultima_compra: datetime | None
    reservas: int
    segmento_sugerido: str  # calculado del historial en la sucursal
    tiene_perfil: bool
    segmento: str  # el del perfil si existe; si no, el sugerido
    talla_habitual: str | None
    estilo_preferido: str | None
    telefono_contacto: str | None
    acepta_whatsapp: bool
    notas: str | None
    actualizado_en: datetime | None
    actualizado_por: str | None
