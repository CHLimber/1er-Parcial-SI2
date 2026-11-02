"""Devoluciones e intercambios, lado de la clienta (Mis compras -> Mis devoluciones).

La clienta pide la devolucion o el intercambio de una compra suya desde la web o la app, como una
reserva: elige las prendas (hasta 3), el motivo y, si es intercambio, la talla/color que se lleva,
mas el dia y la hora en que va a pasar por la sucursal de la compra. La solicitud nace SOLICITADA
(origen ONLINE) y avisa al personal; en un intercambio la prenda pedida queda comprometida. El
personal la acepta o la rechaza (router.py) y se concreta EN CAJA cuando la clienta llega: ahi se
revisa la prenda, se le devuelve la plata o paga la diferencia. Nada se paga ni se devuelve online.

No usa el sistema de permisos (no es una pantalla de gestion): basta con ser CLIENTE y que la
compra sea suya. Una compra ajena responde 404.
"""

from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status

from app.core.auditoria import registrar_auditoria
from app.core.db import get_connection
from app.core.deps import get_current_usuario
from app.core.notificaciones.servicio import avisar_personal_de_sucursal
from app.modules.operacion_comercial.devoluciones import servicio
from app.modules.operacion_comercial.devoluciones.router import armar_detalle
from app.modules.operacion_comercial.devoluciones.schemas import (
    DevolucionDetalleOut,
    LineaClienteOut,
    OpcionesDevolucionOut,
    SolicitudClienteIn,
    VarianteCambioOut,
)

router = APIRouter(prefix="/mis-devoluciones", tags=["devoluciones"])


def _exigir_cliente(usuario: dict) -> None:
    if usuario["tipo"] != "CLIENTE":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Las devoluciones online las pide la clienta desde Mis compras",
        )


async def _venta_de_la_clienta(conn: asyncpg.Connection, venta_id: UUID, usuario_id: UUID):
    venta = await conn.fetchrow(
        """
        SELECT v.id, v.numero, v.fecha, v.estado::text AS estado, v.sucursal_id, v.usuario_id,
               s.nombre AS sucursal, s.direccion AS sucursal_direccion,
               s.hora_apertura, s.hora_cierre
        FROM venta v JOIN sucursal s ON s.id = v.sucursal_id
        WHERE v.id = $1
        """,
        venta_id,
    )
    if venta is None or venta["usuario_id"] != usuario_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Compra no encontrada")
    return venta


@router.get("", response_model=list[DevolucionDetalleOut])
async def listar_mis_devoluciones(
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> list[DevolucionDetalleOut]:
    """Todas las devoluciones/intercambios de compras de la clienta (pedidas online o hechas en
    caja), lo mas reciente primero."""
    _exigir_cliente(usuario)
    ids = await conn.fetch(
        """
        SELECT d.id FROM devolucion d JOIN venta v ON v.id = d.venta_id
        WHERE v.usuario_id = $1
        ORDER BY d.fecha DESC
        LIMIT 50
        """,
        usuario["id"],
    )
    resultado = []
    for fila in ids:
        devolucion = await armar_detalle(conn, fila["id"])
        if devolucion is not None:
            resultado.append(devolucion)
    return resultado


@router.get("/venta/{venta_id}", response_model=OpcionesDevolucionOut)
async def opciones_de_compra(
    venta_id: UUID,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> OpcionesDevolucionOut:
    """Que se puede devolver o cambiar de una compra: prendas, tallas/colores disponibles con su
    precio, hasta cuando y por que no, si no se puede."""
    _exigir_cliente(usuario)
    venta = await _venta_de_la_clienta(conn, venta_id, usuario["id"])
    dias = await servicio.plazo_dias(conn, "DEVOLUCION")
    plazo = await conn.fetchrow(
        "SELECT fecha + make_interval(days => $2) AS vence, now() > fecha + make_interval(days => $2) AS fuera "
        "FROM venta WHERE id = $1",
        venta_id,
        dias,
    )

    motivo_no = None
    if venta["estado"] not in servicio.ESTADOS_VENTA_DEVOLVIBLE:
        motivo_no = "La compra todavia no esta pagada" if venta["estado"] == "PENDIENTE" else "La compra fue anulada"
    elif await servicio.es_venta_de_cambio(conn, venta_id):
        motivo_no = "Esta compra salio de un intercambio: ya uso su devolucion"
    elif plazo["fuera"]:
        motivo_no = f"Ya pasaron los {dias} dias para devolver o cambiar esta compra"
    else:
        vigente = await servicio.solicitud_vigente(conn, venta_id)
        if vigente:
            motivo_no = f"Ya tenes la solicitud {vigente} para esta compra (se permite una sola)"

    lineas = []
    if venta["estado"] in servicio.ESTADOS_VENTA_DEVOLVIBLE:
        mercaderia, suma_lineas = await servicio.base_venta(conn, venta_id)
        for fila in await servicio.lineas_de_venta(conn, venta_id):
            devolvible = max(fila["cantidad_vendida"] - fila["devuelta"] - fila["en_tramite"], 0)
            variantes = await servicio.variantes_de_cambio(conn, fila["variante_id"], venta["sucursal_id"])
            lineas.append(
                LineaClienteOut(
                    venta_detalle_id=fila["venta_detalle_id"],
                    variante_id=fila["variante_id"],
                    producto=fila["producto"],
                    talla=fila["talla"],
                    color=fila["color"],
                    cantidad_vendida=fila["cantidad_vendida"],
                    devolvible=devolvible,
                    precio_unitario=fila["precio_unitario"],
                    reembolso_unitario=servicio.prorratear(
                        fila["subtotal"] / fila["cantidad_vendida"], mercaderia, suma_lineas
                    ),
                    variantes_cambio=[VarianteCambioOut(**dict(v)) for v in variantes],
                )
            )

    return OpcionesDevolucionOut(
        venta_id=venta_id,
        numero=venta["numero"],
        fecha=venta["fecha"],
        sucursal_id=venta["sucursal_id"],
        sucursal=venta["sucursal"],
        sucursal_direccion=venta["sucursal_direccion"],
        hora_apertura=venta["hora_apertura"],
        hora_cierre=venta["hora_cierre"],
        plazo_vence_en=plazo["vence"],
        max_unidades=await servicio.max_unidades(conn),
        iva_tasa=servicio.IVA_TASA,
        reintegro_metodo=servicio.metodo_reintegro(await servicio.pago_de_venta(conn, venta_id)),
        puede_solicitar=motivo_no is None,
        motivo_no=motivo_no,
        lineas=lineas,
    )


@router.post("", response_model=DevolucionDetalleOut, status_code=status.HTTP_201_CREATED)
async def solicitar(
    body: SolicitudClienteIn,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> DevolucionDetalleOut:
    _exigir_cliente(usuario)
    tipo = servicio.tipo_de(body.motivo_tipo)
    servicio.agrupar_lineas(body.lineas, tipo == "INTERCAMBIO")  # rechazos tempranos
    if body.fecha_visita < servicio.hoy_bolivia():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="La fecha de visita no puede ser anterior a hoy",
        )

    async def _validar(venta) -> None:
        if venta["usuario_id"] != usuario["id"]:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Compra no encontrada")
        sucursal = await conn.fetchrow(
            "SELECT hora_apertura, hora_cierre FROM sucursal WHERE id = $1", venta["sucursal_id"]
        )
        if sucursal["hora_apertura"] and sucursal["hora_cierre"] and not (
            sucursal["hora_apertura"] <= body.hora_visita <= sucursal["hora_cierre"]
        ):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=(
                    f"La sucursal atiende de {sucursal['hora_apertura']:%H:%M} a "
                    f"{sucursal['hora_cierre']:%H:%M}: elegi una hora en ese horario"
                ),
            )
        dias = await servicio.plazo_dias(conn, tipo)
        fuera = await conn.fetchval(
            "SELECT $2::date > ((fecha AT TIME ZONE 'America/La_Paz') + make_interval(days => $3))::date "
            "FROM venta WHERE id = $1",
            venta["id"],
            body.fecha_visita,
            dias,
        )
        if fuera:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Tenes que pasar por la sucursal dentro de los {dias} dias de la compra",
            )

    async with conn.transaction():
        devolucion_id = await servicio.registrar(
            conn,
            venta_id=body.venta_id,
            motivo_tipo=body.motivo_tipo,
            motivo=body.motivo,
            lineas=body.lineas,
            usuario_id=usuario["id"],
            origen="ONLINE",
            visita=(body.fecha_visita, body.hora_visita),
            validar_venta_extra=_validar,
        )
        fila = await conn.fetchrow(
            "SELECT d.numero, d.sucursal_id, v.numero AS venta_numero FROM devolucion d "
            "JOIN venta v ON v.id = d.venta_id WHERE d.id = $1",
            devolucion_id,
        )
        que = "Nuevo intercambio" if tipo == "INTERCAMBIO" else "Nueva devolucion"
        for cargo in ("ENCARGADO", "CAJERO"):
            await avisar_personal_de_sucursal(
                conn,
                fila["sucursal_id"],
                cargo,
                "VENTA",
                f"{que} para aceptar",
                f"{fila['numero']} de la compra {fila['venta_numero']}: la clienta pasa el "
                f"{body.fecha_visita:%d/%m} a las {body.hora_visita:%H:%M}. Pendiente de tu confirmacion.",
                "DEVOLUCION",
                devolucion_id,
            )

    return await armar_detalle(conn, devolucion_id)


@router.post("/{devolucion_id}/cancelar", response_model=DevolucionDetalleOut)
async def cancelar(
    devolucion_id: UUID,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> DevolucionDetalleOut:
    """La clienta se arrepiente antes de ir a la sucursal: libera la prenda pedida a cambio."""
    _exigir_cliente(usuario)
    async with conn.transaction():
        fila = await conn.fetchrow(
            """
            SELECT d.id, d.estado::text AS estado, v.usuario_id
            FROM devolucion d JOIN venta v ON v.id = d.venta_id
            WHERE d.id = $1
            FOR UPDATE OF d
            """,
            devolucion_id,
        )
        if fila is None or fila["usuario_id"] != usuario["id"]:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Solicitud no encontrada")
        if fila["estado"] not in servicio.ESTADOS_EN_TRAMITE:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"La solicitud ya esta {fila['estado'].lower()}: no se puede cancelar",
            )
        await conn.execute(
            "UPDATE devolucion SET estado = 'CANCELADA', resuelta_en = now() WHERE id = $1",
            devolucion_id,
        )
        await registrar_auditoria(
            conn,
            usuario_id=usuario["id"],
            entidad="devolucion",
            entidad_id=devolucion_id,
            accion="ACTUALIZAR",
            datos_antes={"estado": fila["estado"]},
            datos_despues={"estado": "CANCELADA"},
        )
    return await armar_detalle(conn, devolucion_id)

