from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class LineaTraspasoIn(BaseModel):
    variante_id: UUID
    cantidad: int = Field(gt=0, le=100_000)


class TraspasoIn(BaseModel):
    sucursal_origen_id: UUID | None = None  # si no se manda, la sucursal del empleado
    sucursal_destino_id: UUID
    lineas: list[LineaTraspasoIn] = Field(min_length=1, max_length=200)


class LineaRecibidaIn(BaseModel):
    detalle_id: UUID
    cantidad_recibida: int = Field(ge=0, le=100_000)


class RecibirIn(BaseModel):
    """Las lineas que no se mandan se toman como recibidas completas."""

    lineas: list[LineaRecibidaIn] = Field(default_factory=list, max_length=200)
    observacion: str | None = Field(default=None, max_length=250)


class DetalleTraspasoOut(BaseModel):
    id: UUID
    variante_id: UUID
    sku: str
    producto: str
    talla: str
    color: str
    codigo_hex: str
    cantidad_solicitada: int
    cantidad_recibida: int | None
    disponible_origen: int
    disponible_destino: int


class TraspasoOut(BaseModel):
    id: UUID
    numero: str
    estado: str
    sucursal_origen_id: UUID
    origen: str
    sucursal_destino_id: UUID
    destino: str
    fecha_solicitud: datetime
    fecha_despacho: datetime | None
    fecha_recepcion: datetime | None
    solicitado_por: str | None
    recibido_por: str | None
    observacion: str | None
    lineas: int
    unidades_solicitadas: int
    unidades_recibidas: int | None
    # desde que lado lo mira quien consulta: ORIGEN, DESTINO o AMBOS (ADMIN). La web lo usa para
    # ofrecer despachar/recibir/anular; quien autoriza igual es el backend.
    mi_lado: str = "AMBOS"


class TraspasoDetalleOut(TraspasoOut):
    detalle: list[DetalleTraspasoOut]


class VarianteTraspasoOut(BaseModel):
    id: UUID
    sku: str
    producto: str
    talla: str
    color: str
    codigo_hex: str
    disponible_origen: int
    disponible_destino: int


class MovimientoTraspasoOut(BaseModel):
    sucursal: str
    tipo: str
    sku: str
    producto: str
    cantidad: int
    saldo_anterior: int
    saldo_nuevo: int
    fecha: datetime
