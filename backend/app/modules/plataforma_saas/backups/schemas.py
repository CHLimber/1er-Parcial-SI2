from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class BackupOut(BaseModel):
    id: UUID
    empresa_id: UUID | None  # None = copia general de la plataforma
    empresa: str | None
    tipo: str  # AUTOMATICO | MANUAL
    estado: str  # EN_CURSO | COMPLETADO | FALLIDO
    iniciado_en: datetime
    terminado_en: datetime | None
    duracion_segundos: float | None
    creado_por: str | None  # None = lo hizo el sistema (copia automatica)
    tamano_bytes: int | None
    total_tablas: int | None
    total_filas: int | None
    sha256: str | None
    # False si el archivo ya no esta en disco (p. ej. se perdio el volumen): no se puede bajar
    disponible: bool
    error: str | None
    tablas: dict[str, int] | None


class ProgramacionOut(BaseModel):
    """Cuando corre la copia automatica de la plataforma (lo que ve el SUPERADMIN)."""

    activa: bool
    frecuencia: str
    hora: str  # HH:MM, hora de Bolivia
    zona: str
    proxima_ejecucion: datetime | None  # None si esta desactivada
    retencion_automaticas: int
    retencion_manuales: int
    ultima: BackupOut | None
    ultima_exitosa: BackupOut | None


class BackupEmpresaIn(BaseModel):
    """La plataforma indica de que empresa; el administrador de una empresa lo omite."""

    empresa_id: UUID | None = None
