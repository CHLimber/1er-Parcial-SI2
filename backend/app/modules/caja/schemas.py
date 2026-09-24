from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field


class CajaOut(BaseModel):
    id: UUID
    codigo: str
    nombre: str
    tiene_sesion_abierta: bool


class AbrirSesionIn(BaseModel):
    caja_id: UUID
    monto_inicial: float = Field(default=0, ge=0)


class SesionCajaOut(BaseModel):
    id: UUID
    caja_id: UUID
    caja_nombre: str
    abierta_en: datetime
    monto_inicial: float
    estado: str


class ArqueoOut(BaseModel):
    """Foto de la sesion abierta para que el cajero cuente el cajon ANTES de declarar el cierre.
    monto_sistema es lo que deberia haber en efectivo: monto_inicial + ventas cobradas en
    EFECTIVO (las de TARJETA/QR/TRANSFERENCIA/PASARELA no tocan el cajon fisico)."""

    sesion_id: UUID
    monto_inicial: float
    monto_sistema: float
    cantidad_ventas: int
    total_ventas: float
    por_metodo: dict[str, float]


class CerrarSesionIn(BaseModel):
    monto_declarado: float = Field(ge=0, description="Lo que el cajero conto de verdad en el cajon")


class SesionCerradaOut(BaseModel):
    id: UUID
    caja_id: UUID
    caja_nombre: str
    abierta_en: datetime
    cerrada_en: datetime
    monto_inicial: float
    monto_sistema: float
    monto_declarado: float
    diferencia: float
    estado: str


class VarianteBusquedaOut(BaseModel):
    variante_id: UUID
    sku: str
    producto: str
    talla: str
    color: str
    precio: float
    disponible: int


class ItemPagoPendienteOut(BaseModel):
    sku: str
    producto: str
    talla: str
    color: str
    cantidad: int


class PagoPorVerificarOut(BaseModel):
    """2.19.1.b/c: pedido online (WEB/MOVIL) de esta sucursal cuyo pago espera al cajero.
    metodo es EFECTIVO (cobrar en tienda o rendicion del delivery) o QR (verificar el deposito).
    informado_en solo aplica a QR: None = la clienta todavia no aviso que pago.
    carrito_modificado: la clienta cambio su carrito despues del checkout, asi que lo que se
    volcaria a la venta ya no coincide con el monto -- no se puede aprobar, hay que rechazarlo."""

    pago_id: UUID
    venta_id: UUID
    numero: str
    fecha: datetime
    cliente: str
    cliente_email: str
    metodo: Literal["EFECTIVO", "QR"]
    entrega: str
    total: float
    costo_envio: float
    informado_en: datetime | None
    referencia_cliente: str | None
    carrito_modificado: bool
    items: list[ItemPagoPendienteOut]


class RechazarPagoIn(BaseModel):
    motivo: str | None = Field(default=None, max_length=200)


class ResolucionPagoOut(BaseModel):
    pago_id: UUID
    venta_id: UUID
    numero: str
    venta_estado: str
    pago_estado: str
    mensaje: str
