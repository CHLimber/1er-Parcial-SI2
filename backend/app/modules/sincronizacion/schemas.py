from datetime import date, datetime, time
from decimal import Decimal
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, Field, model_validator

EstadoServidor = Literal["CONFIRMADA", "RECHAZADA", "CONFLICTO"]


class ItemVentaOffline(BaseModel):
    variante_id: UUID
    cantidad: int = Field(ge=1, le=99)
    # el precio que el dispositivo conocia al vender: si el servidor tiene otro, CONFLICTO
    precio_unitario: Decimal = Field(ge=0)


class VentaOffline(BaseModel):
    items: list[ItemVentaOffline] = Field(min_length=1, max_length=50)
    # RN07: sin conexion solo se vende de contado (no hay pasarela ni verificacion posible)
    metodo_pago: Literal["EFECTIVO"] = "EFECTIVO"
    total: Decimal = Field(ge=0)  # con IVA, como lo cobro el dispositivo
    monto_recibido: Decimal | None = Field(default=None, ge=0)
    sesion_caja_id: UUID | None = None  # la sesion abierta que el dispositivo conocia
    cliente_email: str | None = Field(default=None, max_length=150)


class ItemReservaOffline(BaseModel):
    variante_id: UUID
    cantidad: int = Field(ge=1, le=10)


class ReservaOffline(BaseModel):
    cliente_email: str = Field(min_length=3, max_length=150)
    fecha_visita: date
    hora_visita: time
    items: list[ItemReservaOffline] = Field(min_length=1, max_length=20)
    observaciones: str | None = Field(default=None, max_length=500)


class OperacionIn(BaseModel):
    """Una operacion registrada sin conexion (RN10: id unico, empresa, sucursal y responsable)."""

    id: UUID  # generado en el dispositivo (UUID v4)
    tipo: Literal["VENTA", "RESERVA"]
    empresa_id: UUID
    sucursal_id: UUID
    usuario_id: UUID  # el responsable que la registro (tiene que ser el del token)
    registrada_en: datetime  # hora del dispositivo
    venta: VentaOffline | None = None
    reserva: ReservaOffline | None = None

    @model_validator(mode="after")
    def _cuerpo_segun_tipo(self) -> "OperacionIn":
        if self.tipo == "VENTA" and self.venta is None:
            raise ValueError("Una operacion VENTA necesita el campo venta")
        if self.tipo == "RESERVA" and self.reserva is None:
            raise ValueError("Una operacion RESERVA necesita el campo reserva")
        return self


class LoteIn(BaseModel):
    operaciones: list[OperacionIn] = Field(min_length=1, max_length=100)


class ResultadoOperacionOut(BaseModel):
    id: UUID
    tipo: str
    estado: EstadoServidor
    codigo_motivo: str | None = None
    motivo: str | None = None
    resultado: dict[str, Any] | None = None  # venta/reserva creada
    duplicada: bool = False  # ya se habia recibido: se devuelve lo guardado (RN11)
    intentos: int = 1
    recibida_en: datetime | None = None
    resuelta_en: datetime | None = None
    resolucion: str | None = None


class LoteOut(BaseModel):
    resultados: list[ResultadoOperacionOut]
    confirmadas: int
    rechazadas: int
    en_conflicto: int


class OperacionServidorOut(ResultadoOperacionOut):
    """Una fila del log de sincronizacion (panel del encargado, CU20/CU21)."""

    sucursal: str
    usuario: str
    registrada_en: datetime
    payload: dict[str, Any]


class ResolverIn(BaseModel):
    """CU21 - Resolver conflicto. REINTENTAR vuelve a procesar la operacion tal cual (p.ej.
    despues de abrir la caja o de que entro stock); ACEPTAR_PRECIO_ACTUAL la reprocesa con el
    precio que hoy tiene el servidor; DESCARTAR la cierra como RECHAZADA (la plata cobrada se
    devuelve fuera del sistema y queda anotado)."""

    accion: Literal["REINTENTAR", "ACEPTAR_PRECIO_ACTUAL", "DESCARTAR"]
    nota: str | None = Field(default=None, max_length=250)


class VarianteOfflineOut(BaseModel):
    id: UUID
    sku: str
    talla: str
    color: str
    codigo_hex: str
    precio: float
    disponible: int  # en la sucursal, al momento de la descarga


class ProductoOfflineOut(BaseModel):
    id: UUID
    codigo: str
    nombre: str
    slug: str
    categoria: str
    imagen_url: str | None
    precio_base: float
    variantes: list[VarianteOfflineOut]


class ClienteOfflineOut(BaseModel):
    id: UUID
    nombre: str
    email: str
    telefono: str | None


class SucursalOfflineOut(BaseModel):
    id: UUID
    codigo: str
    nombre: str
    hora_apertura: time | None
    hora_cierre: time | None


class PaqueteOfflineOut(BaseModel):
    """CU13 - Descargar catalogo para uso offline: un subconjunto pensado para operar una
    sucursal sin red (prendas activas con precio y existencias de ESA sucursal, sus datos y la
    cartera minima de clientas para registrar reservas)."""

    generado_en: datetime
    empresa_id: UUID
    empresa: str
    sucursal: SucursalOfflineOut
    sesion_caja_id: UUID | None  # la sesion abierta del usuario, si tiene una
    iva_tasa: float
    productos: list[ProductoOfflineOut]
    clientes: list[ClienteOfflineOut]
