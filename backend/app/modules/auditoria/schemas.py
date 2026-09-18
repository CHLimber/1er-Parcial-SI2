from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel


class AuditoriaOut(BaseModel):
    id: int
    fecha: datetime
    usuario_id: UUID | None
    usuario_nombre: str | None
    usuario_email: str | None
    entidad: str
    entidad_id: str
    accion: str
    datos_antes: dict[str, Any] | None
    datos_despues: dict[str, Any] | None
    ip: str | None


class AuditoriaPaginadoOut(BaseModel):
    total: int
    pagina: int
    tamanio_pagina: int
    items: list[AuditoriaOut]
