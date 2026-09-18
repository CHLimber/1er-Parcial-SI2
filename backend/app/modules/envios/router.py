"""CU20 - cara de la clienta del delivery: cotizar la tarifa y seguir el pedido.

La gestion (marcar despachado/entregado/fallido) esta en admin_router.py, con prefijo /admin
y permisos de CU13, igual que catalogo/ y sucursales/.
"""

from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status

from app.core.db import get_connection
from app.core.deps import get_current_usuario
from app.modules.envios.schemas import CotizacionIn, CotizacionOut, EnvioEventoOut, EnvioOut
from app.modules.envios.servicio import SinCoordenadas, cotizar

router = APIRouter(prefix="/envios", tags=["envios"])


def _exigir_cliente(usuario: dict) -> None:
    if usuario["tipo"] != "CLIENTE":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Esta seccion es para clientes; el personal usa el panel de envios",
        )


@router.post("/cotizar", response_model=CotizacionOut)
async def cotizar_envio(
    body: CotizacionIn,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> CotizacionOut:
    """Cuanto sale que le lleven el pedido a casa. No crea nada: el checkout vuelve a cotizar
    del lado del servidor antes de cobrar, asi que esto es solo para mostrar el precio."""
    _exigir_cliente(usuario)

    sucursal = await conn.fetchrow("SELECT id FROM sucursal WHERE id = $1 AND activa", body.sucursal_id)
    if sucursal is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sucursal no encontrada")

    latitud, longitud = body.latitud, body.longitud
    if body.direccion_id is not None:
        direccion = await conn.fetchrow(
            "SELECT latitud, longitud FROM direccion WHERE id = $1 AND usuario_id = $2",
            body.direccion_id,
            usuario["id"],
        )
        if direccion is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND, detail="Esa direccion no te pertenece"
            )
        latitud = float(direccion["latitud"]) if direccion["latitud"] is not None else None
        longitud = float(direccion["longitud"]) if direccion["longitud"] is not None else None

    try:
        cotizacion = await cotizar(conn, body.sucursal_id, latitud, longitud, body.monto_pedido)
    except SinCoordenadas as error:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(error)
        ) from error

    return CotizacionOut(
        distancia_km=cotizacion.distancia_km,
        duracion_min=cotizacion.duracion_min,
        proveedor=cotizacion.proveedor,
        costo=float(cotizacion.costo),
        es_gratis=cotizacion.es_gratis,
        dentro_cobertura=cotizacion.dentro_cobertura,
        radio_km=cotizacion.radio_km,
        tarifa_base=cotizacion.tarifa_base,
        precio_km=cotizacion.precio_km,
        gratis_desde=cotizacion.gratis_desde,
    )


SELECT_ENVIO = """
SELECT e.id, e.venta_id, v.numero AS numero_venta, e.estado, s.nombre AS sucursal,
       e.ciudad, e.direccion_texto, e.referencia, e.latitud, e.longitud,
       e.distancia_km, e.duracion_min, e.costo, e.observacion,
       e.creado_en, e.despachado_en, e.cerrado_en
FROM envio e
JOIN venta v       ON v.id = e.venta_id
JOIN sucursal s    ON s.id = e.sucursal_id
"""


async def armar_envio_out(conn: asyncpg.Connection, fila: asyncpg.Record) -> EnvioOut:
    eventos = await conn.fetch(
        "SELECT estado, nota, fecha FROM envio_evento WHERE envio_id = $1 ORDER BY fecha, id",
        fila["id"],
    )
    return EnvioOut(
        id=fila["id"],
        venta_id=fila["venta_id"],
        numero_venta=fila["numero_venta"],
        estado=fila["estado"],
        sucursal=fila["sucursal"],
        ciudad=fila["ciudad"],
        direccion=fila["direccion_texto"],
        referencia=fila["referencia"],
        latitud=float(fila["latitud"]) if fila["latitud"] is not None else None,
        longitud=float(fila["longitud"]) if fila["longitud"] is not None else None,
        distancia_km=float(fila["distancia_km"]),
        duracion_min=fila["duracion_min"],
        costo=float(fila["costo"]),
        observacion=fila["observacion"],
        creado_en=fila["creado_en"],
        despachado_en=fila["despachado_en"],
        cerrado_en=fila["cerrado_en"],
        eventos=[
            EnvioEventoOut(estado=evento["estado"], nota=evento["nota"], fecha=evento["fecha"])
            for evento in eventos
        ],
    )


@router.get("/mis", response_model=list[EnvioOut])
async def mis_envios(
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> list[EnvioOut]:
    _exigir_cliente(usuario)
    filas = await conn.fetch(
        SELECT_ENVIO + " WHERE v.usuario_id = $1 ORDER BY e.creado_en DESC LIMIT 50",
        usuario["id"],
    )
    return [await armar_envio_out(conn, fila) for fila in filas]


@router.get("/venta/{venta_id}", response_model=EnvioOut)
async def envio_de_venta(
    venta_id: UUID,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> EnvioOut:
    """Seguimiento desde la pantalla de la compra. Existe recien cuando el pago fue aprobado."""
    _exigir_cliente(usuario)
    fila = await conn.fetchrow(
        SELECT_ENVIO + " WHERE e.venta_id = $1 AND v.usuario_id = $2", venta_id, usuario["id"]
    )
    if fila is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Esa compra todavia no tiene un envio en curso",
        )
    return await armar_envio_out(conn, fila)
