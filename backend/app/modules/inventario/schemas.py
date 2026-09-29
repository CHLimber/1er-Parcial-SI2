from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class VarianteBuscadaOut(BaseModel):
    """Resultado del buscador para elegir que variante ajustar (mismo shape que
    recepciones.VarianteBuscadaOut, duplicado a proposito: cada modulo mantiene el suyo)."""

    id: UUID
    sku: str
    producto: str
    talla: str
    color: str
    codigo_hex: str
    sucursal_id: UUID
    sucursal: str
    cantidad_fisica: int
    cantidad_reservada: int
    disponible: int


class AjusteIn(BaseModel):
    sucursal_id: UUID
    variante_id: UUID
    # fn_mover_inventario() trata AJUSTE como el saldo fisico ABSOLUTO nuevo, no como un delta.
    # Puede ser 0: el recuento que registra que se perdio o se danio la ultima unidad (necesita
    # db/reparaciones/ajuste_stock_a_cero.sql en una base creada antes de ese cambio).
    cantidad_fisica_nueva: int = Field(ge=0, le=1_000_000)
    motivo: str = Field(min_length=3, max_length=200)


class AjusteOut(BaseModel):
    movimiento_id: int
    sucursal_id: UUID
    variante_id: UUID
    saldo_anterior: int
    saldo_nuevo: int
    motivo: str
    fecha: datetime


class MovimientoKardexOut(BaseModel):
    """saldo_anterior/saldo_nuevo son el DISPONIBLE (cantidad_fisica - cantidad_reservada) antes
    y despues del movimiento para todos los tipos salvo AJUSTE, donde son cantidad_fisica cruda
    (fn_mover_inventario, db/02_logica.sql)."""

    id: int
    tipo: str
    cantidad: int
    saldo_anterior: int
    saldo_nuevo: int
    motivo: str | None
    documento_tipo: str | None
    documento_id: UUID | None
    usuario: str | None
    fecha: datetime
