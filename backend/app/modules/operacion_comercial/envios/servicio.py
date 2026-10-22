"""CU20 - cotizacion del delivery y alta del envio.

Reparto de responsabilidades:
  - app/core/ruteo.py  -> cuantos km y cuantos minutos hay (openrouteservice o el respaldo).
  - fn_cotizar_envio() -> cuanto se cobra por esos km (db/02_logica.sql, parametros en la
                          tabla configuracion).
  - este archivo       -> junta las dos cosas y las deja listas para el checkout, para el
                          endpoint de cotizacion y para el webhook que crea el envio.

Lo usan ventas/router.py (checkout) y pagos/router.py (webhook), ademas del router propio del
modulo. Es la unica excepcion al "cada modulo se basta a si mismo": lo que se comparte son
funciones, no schemas.
"""

from dataclasses import dataclass
from decimal import Decimal
from uuid import UUID

import asyncpg

from app.core.ruteo import calcular_ruta

# el envio nace asi; la sucursal lo mueve a DESPACHADO cuando se lo entrega al servicio de
# delivery externo, y a ENTREGADO/FALLIDO cuando ese servicio confirma el resultado
ESTADO_INICIAL = "PENDIENTE"


@dataclass(frozen=True)
class Cotizacion:
    distancia_km: float
    duracion_min: int
    proveedor: str
    costo: Decimal
    es_gratis: bool
    dentro_cobertura: bool
    radio_km: float
    tarifa_base: float
    precio_km: float
    gratis_desde: float
    # de donde sale el delivery, para dibujar la ruta en el mapa del carrito
    origen_lat: float
    origen_lon: float


class SinCoordenadas(Exception):
    """La sucursal o el domicilio no tienen latitud/longitud cargadas."""


async def cotizar(
    conn: asyncpg.Connection,
    sucursal_id: UUID,
    destino_lat: float | None,
    destino_lon: float | None,
    monto_pedido: Decimal | float = 0,
) -> Cotizacion:
    sucursal = await conn.fetchrow(
        "SELECT latitud, longitud FROM sucursal WHERE id = $1", sucursal_id
    )
    if sucursal is None or sucursal["latitud"] is None or sucursal["longitud"] is None:
        raise SinCoordenadas("La sucursal no tiene ubicacion cargada, no se puede cotizar el envio")
    if destino_lat is None or destino_lon is None:
        raise SinCoordenadas("La direccion no tiene ubicacion en el mapa, no se puede cotizar el envio")

    ruta = await calcular_ruta(
        float(sucursal["latitud"]), float(sucursal["longitud"]), destino_lat, destino_lon
    )

    tarifa = await conn.fetchrow(
        "SELECT * FROM fn_cotizar_envio($1::numeric, $2::numeric)",
        Decimal(str(ruta.distancia_km)),
        Decimal(str(monto_pedido)),
    )

    return Cotizacion(
        distancia_km=ruta.distancia_km,
        duracion_min=ruta.duracion_min,
        proveedor=ruta.proveedor,
        costo=tarifa["costo"],
        es_gratis=tarifa["es_gratis"],
        dentro_cobertura=tarifa["dentro_cobertura"],
        radio_km=float(tarifa["radio_km"]),
        tarifa_base=float(tarifa["tarifa_base"]),
        precio_km=float(tarifa["precio_km"]),
        gratis_desde=float(tarifa["gratis_desde"]),
        origen_lat=float(sucursal["latitud"]),
        origen_lon=float(sucursal["longitud"]),
    )


async def crear_envio_de_venta(conn: asyncpg.Connection, venta_id: UUID) -> UUID | None:
    """Da de alta el envio de una venta a domicilio ya pagada. La llama el webhook del pago
    (CU06), no el checkout: mientras el pago siga PENDIENTE no hay nada que repartir.

    Es idempotente por el UNIQUE de envio.venta_id -- un webhook reintentado no duplica el
    envio. Devuelve None si la venta no es a domicilio o si el envio ya existia.

    La tarifa NO se vuelve a cotizar: se usa venta.costo_envio, que es lo que la clienta pago.
    La distancia se recalcula solo para mostrarla en el seguimiento, y si el proveedor de
    mapas no contesta queda la del respaldo, que no cambia lo cobrado.
    """
    venta = await conn.fetchrow(
        """
        SELECT v.id, v.sucursal_id, v.direccion_id, v.costo_envio, v.entrega,
               d.ciudad, d.direccion, d.referencia, d.latitud, d.longitud
        FROM venta v
        LEFT JOIN direccion d ON d.id = v.direccion_id
        WHERE v.id = $1
        """,
        venta_id,
    )
    if venta is None or venta["entrega"] != "DOMICILIO" or venta["direccion_id"] is None:
        return None

    ya_existe = await conn.fetchval("SELECT id FROM envio WHERE venta_id = $1", venta_id)
    if ya_existe is not None:
        return ya_existe

    distancia_km = Decimal("0")
    duracion_min = 0
    proveedor = "HAVERSINE"
    try:
        cotizacion = await cotizar(
            conn, venta["sucursal_id"], _float(venta["latitud"]), _float(venta["longitud"])
        )
        distancia_km = Decimal(str(cotizacion.distancia_km))
        duracion_min = cotizacion.duracion_min
        proveedor = cotizacion.proveedor
    except SinCoordenadas:
        # una compra vieja, anterior a que la direccion tuviera pin en el mapa: el envio se
        # crea igual (alguien tiene que llevar el paquete), con distancia 0 y a resolver a mano
        pass

    envio_id = await conn.fetchval(
        """
        INSERT INTO envio (venta_id, sucursal_id, direccion_id, estado, proveedor_ruteo,
                           distancia_km, duracion_min, costo, ciudad, direccion_texto,
                           referencia, latitud, longitud)
        VALUES ($1, $2, $3, $4::estado_envio, $5, $6, $7, $8, $9::ciudad_bo, $10, $11, $12, $13)
        RETURNING id
        """,
        venta_id,
        venta["sucursal_id"],
        venta["direccion_id"],
        ESTADO_INICIAL,
        proveedor,
        distancia_km,
        duracion_min,
        venta["costo_envio"],
        venta["ciudad"],
        venta["direccion"],
        venta["referencia"],
        venta["latitud"],
        venta["longitud"],
    )
    return envio_id


def _float(valor) -> float | None:
    return float(valor) if valor is not None else None
