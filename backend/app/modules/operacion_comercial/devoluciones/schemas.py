from datetime import date, datetime
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

MotivoTipo = Literal["TALLA", "COLOR", "DEFECTO", "NO_GUSTO", "OTRO"]


class LineaDevolucionIn(BaseModel):
    venta_detalle_id: UUID
    cantidad: int = Field(gt=0, le=10_000)
    # Cambio por talla/color (motivo_tipo TALLA o COLOR): la variante de la misma prenda que la
    # clienta se lleva a cambio. Obligatoria en esos motivos, prohibida en el resto.
    variante_solicitada_id: UUID | None = None


class DevolucionIn(BaseModel):
    venta_id: UUID
    motivo_tipo: MotivoTipo = "OTRO"
    motivo: str = Field(min_length=3, max_length=250)
    # Condiciones de la prenda verificadas por el personal al recibirla (PENDIENTES 5.8)
    con_etiqueta: bool = True
    sin_uso: bool = True
    con_comprobante: bool = True
    lineas: list[LineaDevolucionIn] = Field(min_length=1, max_length=200)


class RechazoIn(BaseModel):
    motivo: str = Field(min_length=3, max_length=250)


class CambioIn(BaseModel):
    """Cambio de prenda: la venta nueva (cobrada en caja) que reemplaza lo devuelto."""

    venta_numero: str = Field(min_length=3, max_length=40)


class LineaVentaOut(BaseModel):
    """Una linea de la venta con lo que todavia se puede devolver de ella."""

    venta_detalle_id: UUID
    variante_id: UUID
    sku: str
    producto: str
    talla: str
    color: str
    cantidad_vendida: int
    precio_unitario: Decimal
    subtotal: Decimal
    devuelta: int  # unidades en devoluciones APROBADAS
    en_tramite: int  # unidades en devoluciones SOLICITADAS
    devolvible: int  # vendida - devuelta - en_tramite
    reembolso_unitario: Decimal  # lo que se reintegra por unidad (descuento e IVA prorrateados)


class VentaDevolvibleOut(BaseModel):
    venta_id: UUID
    numero: str
    fecha: datetime
    estado: str
    canal: str
    sucursal_id: UUID
    sucursal: str
    cliente: str | None
    subtotal: Decimal
    descuento: Decimal
    costo_envio: Decimal
    total: Decimal
    total_devuelto: Decimal  # suma de devoluciones APROBADAS
    plazo_vence_en: datetime  # venta.fecha + configuracion.devolucion_plazo_dias
    fuera_de_plazo: bool  # True: POST /devoluciones responde 409
    # Cambio por talla/color: corre configuracion.cambio_plazo_dias (mas corto)
    cambio_vence_en: datetime
    fuera_de_plazo_cambio: bool
    reintegro_metodo: str | None  # como se devolveria la plata (segun el pago de la venta)
    lineas: list[LineaVentaOut]


class DetalleDevolucionOut(BaseModel):
    id: UUID
    venta_detalle_id: UUID
    variante_id: UUID
    sku: str
    producto: str
    talla: str
    color: str
    cantidad: int
    cantidad_vendida: int
    precio_unitario: Decimal
    # Cambio por talla/color: lo que la clienta se lleva a cambio
    variante_solicitada_id: UUID | None = None
    talla_solicitada: str | None = None
    color_solicitado: str | None = None
    sku_solicitado: str | None = None


class DevolucionOut(BaseModel):
    id: UUID
    numero: str  # numero de la nota de devolucion (NDV-000001)
    venta_id: UUID
    venta_numero: str
    venta_total: Decimal
    sucursal_id: UUID
    sucursal: str
    cliente: str | None
    motivo_tipo: str
    motivo: str
    con_etiqueta: bool
    sin_uso: bool
    con_comprobante: bool
    monto_devuelto: Decimal
    estado: str
    fecha: datetime
    registrada_por: str | None
    resuelta_por: str | None
    resuelta_en: datetime | None
    motivo_rechazo: str | None
    lineas: int
    unidades: int
    # Reintegro (se fija al aprobar): STRIPE (API, referencia = Refund re_...), EFECTIVO (sale
    # del cajon de la sesion de caja de quien aprobo) o TARJETA/QR/TRANSFERENCIA (manual).
    reintegro_metodo: str | None = None
    reintegro_referencia: str | None = None
    # Cambio de prenda: la venta nueva vinculada, si la hay
    venta_cambio_id: UUID | None = None
    venta_cambio_numero: str | None = None


class DevolucionDetalleOut(DevolucionOut):
    detalle: list[DetalleDevolucionOut]
    pago_reembolsado: bool  # True si la devolucion completo la venta y el pago paso a REEMBOLSADO


class CambioMesOut(BaseModel):
    """Una fila de "que prendas solicitaron cambio en el mes": prenda devuelta (talla/color
    original) contra lo que se pidio a cambio, con cuantas solicitudes y unidades hubo."""

    producto_id: UUID
    producto: str
    motivo_tipo: str
    talla_original: str
    color_original: str
    talla_solicitada: str | None
    color_solicitado: str | None
    solicitudes: int
    unidades: int
    aprobadas: int
    rechazadas: int
    pendientes: int
    sucursales: list[str]


class CambiosMesOut(BaseModel):
    anio: int
    mes: int
    desde: date
    hasta: date
    total_solicitudes: int
    total_unidades: int
    filas: list[CambioMesOut]


class NotaDevolucionOut(BaseModel):
    """Comprobante imprimible de la devolucion (PENDIENTES 5.9)."""

    empresa_razon_social: str
    empresa_nit: str
    sucursal_direccion: str | None
    sucursal_ciudad: str
    venta_fecha: datetime
    plazo_dias: int
    devolucion: DevolucionDetalleOut


class VarianteCambioOut(BaseModel):
    """Otra talla/color de la misma prenda, con su disponible en la sucursal."""

    variante_id: UUID
    sku: str
    talla: str
    color: str
    disponible: int
