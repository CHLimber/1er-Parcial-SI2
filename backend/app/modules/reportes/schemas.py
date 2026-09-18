from datetime import date
from uuid import UUID

from pydantic import BaseModel


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
