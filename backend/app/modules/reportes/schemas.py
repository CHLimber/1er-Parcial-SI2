from datetime import date
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field


class IndicadoresOut(BaseModel):
    desde: date
    hasta: date
    ventas_cantidad: int
    ventas_monto: float
    ticket_promedio: float
    reservas_creadas: int
    reservas_convertidas: int
    tasa_conversion_reservas: float
    variantes_stock_bajo: int
    variantes_agotadas: int


class VentaDiariaOut(BaseModel):
    dia: date
    sucursal_id: UUID
    sucursal: str
    canal: str
    cantidad_ventas: int
    monto_total: float
    ticket_promedio: float


class VentaPorSucursalOut(BaseModel):
    sucursal_id: UUID
    sucursal: str
    cantidad_ventas: int
    monto_total: float
    ticket_promedio: float


class ProductoRankingOut(BaseModel):
    producto_id: UUID
    producto: str
    unidades_vendidas: int
    monto_vendido: float


class StockSucursalOut(BaseModel):
    sucursal_id: UUID
    sucursal: str
    total_fisico: int
    total_reservado: int
    total_disponible: int
    variantes_agotadas: int
    variantes_stock_bajo: int


class ReservaEstadoOut(BaseModel):
    estado: str
    cantidad: int


class EnvioEstadoOut(BaseModel):
    estado: str
    cantidad: int


class ProductoSinMovimientoOut(BaseModel):
    variante_id: UUID
    producto: str
    talla: str
    color: str
    sucursal_id: UUID
    sucursal: str
    cantidad_fisica: int


class ClienteRankingOut(BaseModel):
    usuario_id: UUID
    cliente: str
    email: str
    cantidad_compras: int
    monto_total: float


class CajaOcupacionOut(BaseModel):
    sucursal_id: UUID
    sucursal: str
    total_cajas: int
    cajas_abiertas: int


class RecepcionPendienteProveedorOut(BaseModel):
    proveedor_id: UUID
    proveedor: str
    cantidad: int
    monto_total: float


class VendedorOut(BaseModel):
    id: UUID
    nombre: str


class MensajeReporteIn(BaseModel):
    """Igual que asistente.schemas.MensajeIn (CU18), duplicado a proposito: ningun modulo
    importa schemas de otro, ver CLAUDE.md."""

    rol: Literal["user", "assistant"]
    texto: str = Field(min_length=1, max_length=2000)


class ConsultaIaIn(BaseModel):
    # Sin persistencia, igual que CU18: el frontend reenvia la conversacion completa.
    mensajes: list[MensajeReporteIn] = Field(min_length=1, max_length=20)


class ColumnaOut(BaseModel):
    clave: str
    etiqueta: str


class ConsultaIaOut(BaseModel):
    respuesta: str
    titulo: str | None = None
    columnas: list[ColumnaOut] = Field(default_factory=list)
    # Filas crudas de la ultima herramienta llamada (para tabla + export en el frontend). Los
    # valores de plata ya vienen convertidos a float (ver _normalizar en router.py) para no caer
    # en el mismo problema que Decimal: Pydantic v2 lo serializa como string en el JSON.
    tabla: list[dict] = Field(default_factory=list)
