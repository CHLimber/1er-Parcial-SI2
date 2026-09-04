from datetime import time
from uuid import UUID

from pydantic import BaseModel


class SucursalOut(BaseModel):
    id: UUID
    codigo: str
    nombre: str
    ciudad: str
    direccion: str
    hora_apertura: time | None
    hora_cierre: time | None
    cantidad_vestidores: int
