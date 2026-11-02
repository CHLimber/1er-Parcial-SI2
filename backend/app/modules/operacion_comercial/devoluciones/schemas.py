from datetime import date, datetime, time
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

MotivoTipo = Literal["TALLA", "COLOR", "DEFECTO", "NO_GUSTO", "OTRO"]
MetodoDiferencia = Literal["EFECTIVO", "TARJETA", "QR"]


class LineaDevolucionIn(BaseModel):
    venta_detalle_id: UUID
    cantidad: int = Field(gt=0, le=10_000)
    # Intercambio (motivo_tipo TALLA o COLOR): la variante de la misma prenda que la clienta se
    # lleva a cambio. Obligatoria en esos motivos, prohibida en el resto.
    variante_solicitada_id: UUID | None = None


class DevolucionIn(BaseModel):
    """Registro en caja (origen CAJA): la clienta esta en la sucursal con la prenda."""

    venta_id: UUID
    motivo_tipo: MotivoTipo = "OTRO"
    motivo: str = Field(min_length=3, max_length=250)
    # Condiciones de la prenda verificadas por el personal al recibirla (PENDIENTES 5.8)
    con_etiqueta: bool = True
    sin_uso: bool = True
    con_comprobante: bool = True
    lineas: list[LineaDevolucionIn] = Field(min_length=1, max_length=200)


class SolicitudClienteIn(BaseModel):
    """Solicitud online (origen ONLINE) desde Mis compras. Las condiciones de la prenda las
    verifica el personal cuando la clienta llega a la sucursal."""

    venta_id: UUID
    motivo_tipo: MotivoTipo = "OTRO"
    motivo: str = Field(min_length=3, max_length=250)
    fecha_visita: date
    hora_visita: time
    lineas: list[LineaDevolucionIn] = Field(min_length=1, max_length=20)


class AprobacionIn(BaseModel):
    """Concretar en caja. Las condiciones, si vienen, pisan las registradas (en una solicitud
    online recien se ven aca). diferencia_metodo: como paga la clienta lo que falta en un
    intercambio que sale mas caro."""

    con_etiqueta: bool | None = None
    sin_uso: bool | None = None
    con_comprobante: bool | None = None
    diferencia_metodo: MetodoDiferencia | None = None


class RechazoIn(BaseModel):
    motivo: str = Field(min_length=3, max_length=250)


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
    en_tramite: int  # unidades en devoluciones SOLICITADAS/CONFIRMADAS
    devolvible: int  # vendida - devuelta - en_tramite
    reembolso_unitario: Decimal  # lo que vale cada unidad devuelta (descuento e IVA prorrateados)


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
    cambio_vence_en: datetime  # venta.fecha + configuracion.cambio_plazo_dias
    fuera_de_plazo_cambio: bool
    reintegro_metodo: str | None  # como se devolveria la plata (segun el pago de la venta)
    max_unidades: int  # tope de prendas por compra (configuracion.devolucion_max_unidades)
    # Una sola devolucion/intercambio por compra: el numero de la que ya esta en tramite o
    # aprobada, si la hay (entonces no se puede registrar otra)
    solicitud_vigente: str | None = None
    es_venta_de_cambio: bool = False  # nacio de un intercambio: no se devuelve de nuevo
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
    # Intercambio: lo que la clienta se lleva a cambio y su precio de lista pactado
    variante_solicitada_id: UUID | None = None
    talla_solicitada: str | None = None
    color_solicitado: str | None = None
    sku_solicitado: str | None = None
    precio_solicitado: Decimal | None = None


class DevolucionOut(BaseModel):
    id: UUID
    numero: str  # numero de la nota (NDV-000001)
    tipo: str  # DEVOLUCION | INTERCAMBIO
    origen: str  # CAJA | ONLINE
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
    # Plata (con IVA): monto_devuelto = lo que vale lo devuelto (credito en un intercambio);
    # monto_cambio = lo que valen las prendas nuevas; diferencia = monto_cambio - monto_devuelto
    # (> 0 la clienta paga, < 0 se le devuelve). Antes de aprobar son estimados.
    monto_devuelto: Decimal
    monto_cambio: Decimal = Decimal("0")
    diferencia: Decimal = Decimal("0")
    monto_reintegrado: Decimal = Decimal("0")  # lo que efectivamente volvio a la clienta
    diferencia_cobrada: Decimal = Decimal("0")
    diferencia_metodo: str | None = None
    estado: str
    fecha: datetime
    fecha_visita: date | None = None
    hora_visita: time | None = None
    expira_en: datetime | None = None
    registrada_por: str | None
    resuelta_por: str | None
    resuelta_en: datetime | None
    motivo_rechazo: str | None
    lineas: int
    unidades: int
    # Reintegro (se fija al aprobar): STRIPE (API, referencia = Refund re_...), EFECTIVO o QR
    # (sale del cajon de la sesion de caja de quien aprobo) o TARJETA/TRANSFERENCIA (manual).
    reintegro_metodo: str | None = None
    reintegro_referencia: str | None = None
    # Intercambio: la venta con las prendas nuevas, armada al aprobar
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
    """Otra talla/color de la misma prenda, con su precio de lista y su disponible en la sucursal."""

    variante_id: UUID
    sku: str
    talla: str
    color: str
    precio: Decimal  # precio de lista sin IVA (el de la variante o el base de la prenda)
    disponible: int


# --- lado de la clienta (Mis compras) ------------------------------------------------------------


class LineaClienteOut(BaseModel):
    venta_detalle_id: UUID
    variante_id: UUID
    producto: str
    talla: str
    color: str
    cantidad_vendida: int
    devolvible: int
    precio_unitario: Decimal  # lo que figura en la compra (sin IVA)
    reembolso_unitario: Decimal  # lo que vale cada unidad devuelta (con IVA y descuento)
    variantes_cambio: list[VarianteCambioOut]


class OpcionesDevolucionOut(BaseModel):
    """Lo que la clienta necesita para pedir una devolucion o un intercambio de una compra."""

    venta_id: UUID
    numero: str
    fecha: datetime
    sucursal_id: UUID
    sucursal: str
    sucursal_direccion: str | None
    hora_apertura: time | None
    hora_cierre: time | None
    plazo_vence_en: datetime  # hasta cuando puede pedir (y visitar la sucursal)
    max_unidades: int
    iva_tasa: Decimal  # para estimar la diferencia en pantalla (precios de lista sin IVA)
    reintegro_metodo: str | None
    puede_solicitar: bool
    motivo_no: str | None = None  # por que no puede (fuera de plazo, ya pidio una, ...)
    lineas: list[LineaClienteOut]
