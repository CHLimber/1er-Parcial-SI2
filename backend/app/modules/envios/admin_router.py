"""CU20 - panel de despacho: en que anda cada pedido a domicilio.

El reparto en si lo hace un servicio de delivery externo, no personal de FashionStore: la
sucursal solo marca cuando el paquete SALE hacia ese servicio (DESPACHADO) y cuando el
servicio confirma que LLEGO (ENTREGADO) o que fallo (FALLIDO). No hay asignacion de
repartidor ni tramos intermedios que trackear.

Autorizacion por permiso (CU13): envios.leer para mirar, envios.actualizar para mover
estados. Encima del permiso hay un recorte de alcance por sucursal, igual que recepciones/ y
reportes/: un ADMIN (el que tiene sucursales.actualizar) ve toda la cadena, el resto solo la
suya.
"""

from datetime import datetime, timezone
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.auditoria import registrar_auditoria
from app.core.db import get_connection
from app.core.deps import requiere_permiso
from app.modules.envios.admin_schemas import (
    CambioEstadoIn,
    EnvioAdminDetalleOut,
    EnvioAdminOut,
    EstadoEnvio,
    EventoAdminOut,
    ItemEnvioOut,
    ResumenEnviosOut,
)

router = APIRouter(prefix="/admin/envios", tags=["admin-envios"])

puede_ver = requiere_permiso("envios.leer", "envios.actualizar")
puede_actualizar = requiere_permiso("envios.actualizar")

# de que estado se puede pasar a cual. ENTREGADO no esta: es terminal.
TRANSICIONES: dict[str, set[str]] = {
    "PENDIENTE": {"DESPACHADO", "CANCELADO"},
    "DESPACHADO": {"ENTREGADO", "FALLIDO"},
    "FALLIDO": {"DESPACHADO", "CANCELADO"},
    "ENTREGADO": set(),
    "CANCELADO": set(),
}

ESTADOS_ABIERTOS = ("PENDIENTE", "DESPACHADO", "FALLIDO")

SELECT_ENVIO = """
SELECT e.id, e.venta_id, v.numero AS numero_venta, e.estado,
       e.sucursal_id, s.nombre AS sucursal,
       COALESCE(c.nombre || ' ' || c.apellido, 'Cliente') AS cliente, c.telefono AS cliente_telefono,
       e.ciudad, e.direccion_texto, e.referencia, e.latitud, e.longitud,
       e.distancia_km, e.duracion_min, e.costo, e.proveedor_ruteo, v.total AS total_venta,
       e.observacion, e.creado_en, e.despachado_en, e.cerrado_en
FROM envio e
JOIN venta v        ON v.id = e.venta_id
JOIN sucursal s     ON s.id = e.sucursal_id
LEFT JOIN usuario c ON c.id = v.usuario_id
"""


def _sucursal_visible(staff: dict) -> UUID | None:
    """Un ADMIN (el que puede editar sucursales) ve todas; el resto solo la suya."""
    if "sucursales.actualizar" in staff["permisos"]:
        return None
    if staff["sucursal_id"] is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tu usuario no esta asignado a ninguna sucursal",
        )
    return staff["sucursal_id"]


def _a_salida(fila: asyncpg.Record) -> EnvioAdminOut:
    return EnvioAdminOut(
        id=fila["id"],
        venta_id=fila["venta_id"],
        numero_venta=fila["numero_venta"],
        estado=fila["estado"],
        sucursal_id=fila["sucursal_id"],
        sucursal=fila["sucursal"],
        cliente=fila["cliente"],
        cliente_telefono=fila["cliente_telefono"],
        ciudad=fila["ciudad"],
        direccion=fila["direccion_texto"],
        referencia=fila["referencia"],
        latitud=float(fila["latitud"]) if fila["latitud"] is not None else None,
        longitud=float(fila["longitud"]) if fila["longitud"] is not None else None,
        distancia_km=float(fila["distancia_km"]),
        duracion_min=fila["duracion_min"],
        costo=float(fila["costo"]),
        proveedor_ruteo=fila["proveedor_ruteo"],
        total_venta=float(fila["total_venta"]),
        observacion=fila["observacion"],
        creado_en=fila["creado_en"],
        despachado_en=fila["despachado_en"],
        cerrado_en=fila["cerrado_en"],
    )


async def _obtener(conn: asyncpg.Connection, envio_id: UUID, staff: dict) -> asyncpg.Record:
    fila = await conn.fetchrow(SELECT_ENVIO + " WHERE e.id = $1", envio_id)
    if fila is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Envio no encontrado")

    limite = _sucursal_visible(staff)
    if limite is not None and fila["sucursal_id"] != limite:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="Ese envio es de otra sucursal"
        )
    return fila


@router.get("", response_model=list[EnvioAdminOut])
async def listar_envios(
    estado: EstadoEnvio | None = Query(default=None),
    sucursal_id: UUID | None = Query(default=None),
    solo_abiertos: bool = Query(default=False),
    limite: int = Query(default=100, ge=1, le=300),
    staff: dict = Depends(puede_ver),
    conn: asyncpg.Connection = Depends(get_connection),
) -> list[EnvioAdminOut]:
    limite_sucursal = _sucursal_visible(staff)
    if limite_sucursal is not None and sucursal_id is not None and sucursal_id != limite_sucursal:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="Solo podes ver los envios de tu sucursal"
        )
    sucursal_filtro = limite_sucursal if limite_sucursal is not None else sucursal_id

    condiciones = []
    parametros: list = []

    if sucursal_filtro is not None:
        parametros.append(sucursal_filtro)
        condiciones.append(f"e.sucursal_id = ${len(parametros)}")
    if estado:
        parametros.append(estado)
        condiciones.append(f"e.estado = ${len(parametros)}::estado_envio")
    if solo_abiertos:
        parametros.append(list(ESTADOS_ABIERTOS))
        condiciones.append(f"e.estado = ANY(${len(parametros)}::estado_envio[])")

    where = (" WHERE " + " AND ".join(condiciones)) if condiciones else ""
    parametros.append(limite)
    consulta = (
        SELECT_ENVIO
        + where
        # los que todavia no salieron primero, y dentro de eso el mas viejo arriba
        + " ORDER BY (e.estado IN ('ENTREGADO','CANCELADO')), e.creado_en"
        + f" LIMIT ${len(parametros)}"
    )
    filas = await conn.fetch(consulta, *parametros)
    return [_a_salida(fila) for fila in filas]


@router.get("/resumen", response_model=ResumenEnviosOut)
async def resumen(
    sucursal_id: UUID | None = Query(default=None),
    staff: dict = Depends(puede_ver),
    conn: asyncpg.Connection = Depends(get_connection),
) -> ResumenEnviosOut:
    limite_sucursal = _sucursal_visible(staff)
    if limite_sucursal is not None and sucursal_id is not None and sucursal_id != limite_sucursal:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="Solo podes ver los envios de tu sucursal"
        )
    sucursal_filtro = limite_sucursal if limite_sucursal is not None else sucursal_id

    fila = await conn.fetchrow(
        """
        SELECT
            count(*) FILTER (WHERE estado = 'PENDIENTE')                            AS pendientes,
            count(*) FILTER (WHERE estado = 'DESPACHADO')                           AS despachados,
            count(*) FILTER (WHERE estado = 'ENTREGADO'
                             AND cerrado_en >= date_trunc('day', now()))            AS entregados_hoy,
            count(*) FILTER (WHERE estado = 'FALLIDO')                              AS fallidos
        FROM envio
        WHERE ($1::uuid IS NULL OR sucursal_id = $1::uuid)
        """,
        sucursal_filtro,
    )
    return ResumenEnviosOut(
        pendientes=fila["pendientes"],
        despachados=fila["despachados"],
        entregados_hoy=fila["entregados_hoy"],
        fallidos=fila["fallidos"],
    )


@router.get("/{envio_id}", response_model=EnvioAdminDetalleOut)
async def detalle(
    envio_id: UUID,
    staff: dict = Depends(puede_ver),
    conn: asyncpg.Connection = Depends(get_connection),
) -> EnvioAdminDetalleOut:
    fila = await _obtener(conn, envio_id, staff)

    items = await conn.fetch(
        """
        SELECT p.nombre AS producto, pv.sku, t.codigo AS talla, c.nombre AS color, vd.cantidad
        FROM venta_detalle vd
        JOIN producto_variante pv ON pv.id = vd.variante_id
        JOIN producto p           ON p.id = pv.producto_id
        JOIN talla t              ON t.id = pv.talla_id
        JOIN color c              ON c.id = pv.color_id
        WHERE vd.venta_id = $1
        ORDER BY p.nombre, t.codigo
        """,
        fila["venta_id"],
    )
    eventos = await conn.fetch(
        """
        SELECT ev.estado, ev.nota, ev.fecha,
               CASE WHEN u.id IS NULL THEN NULL ELSE u.nombre || ' ' || u.apellido END AS usuario
        FROM envio_evento ev
        LEFT JOIN usuario u ON u.id = ev.usuario_id
        WHERE ev.envio_id = $1
        ORDER BY ev.fecha, ev.id
        """,
        envio_id,
    )

    base = _a_salida(fila)
    return EnvioAdminDetalleOut(
        **base.model_dump(),
        items=[
            ItemEnvioOut(
                producto=item["producto"],
                sku=item["sku"],
                talla=item["talla"],
                color=item["color"],
                cantidad=item["cantidad"],
            )
            for item in items
        ],
        eventos=[
            EventoAdminOut(
                estado=evento["estado"],
                nota=evento["nota"],
                usuario=evento["usuario"],
                fecha=evento["fecha"],
            )
            for evento in eventos
        ],
    )


@router.post("/{envio_id}/estado", response_model=EnvioAdminOut)
async def cambiar_estado(
    envio_id: UUID,
    body: CambioEstadoIn,
    staff: dict = Depends(puede_actualizar),
    conn: asyncpg.Connection = Depends(get_connection),
) -> EnvioAdminOut:
    envio = await _obtener(conn, envio_id, staff)
    actual = envio["estado"]

    if body.estado not in TRANSICIONES[actual]:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Un envio {actual} no puede pasar a {body.estado}",
        )
    if body.estado == "FALLIDO" and not body.observacion:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Un envio fallido necesita un motivo",
        )

    ahora = datetime.now(timezone.utc)
    despachado_en = ahora if body.estado == "DESPACHADO" else envio["despachado_en"]
    cerrado_en = ahora if body.estado in ("ENTREGADO", "FALLIDO", "CANCELADO") else None

    async with conn.transaction():
        await conn.execute(
            """
            UPDATE envio
               SET estado = $2::estado_envio, observacion = $3, actualizado_por_id = $4,
                   despachado_en = $5, cerrado_en = $6
             WHERE id = $1
            """,
            envio_id,
            body.estado,
            body.observacion,
            staff["id"],
            despachado_en,
            cerrado_en,
        )
        if body.estado == "ENTREGADO":
            # el pedido llego a manos de la clienta: la venta queda cerrada
            await conn.execute(
                "UPDATE venta SET estado = 'ENTREGADA' WHERE id = $1 AND estado = 'PAGADA'",
                envio["venta_id"],
            )

    await registrar_auditoria(
        conn,
        usuario_id=staff["id"],
        entidad="envio",
        entidad_id=str(envio_id),
        accion="ACTUALIZAR",
        datos_antes={"estado": actual},
        datos_despues={"estado": body.estado, "observacion": body.observacion},
    )

    return _a_salida(await _obtener(conn, envio_id, staff))
