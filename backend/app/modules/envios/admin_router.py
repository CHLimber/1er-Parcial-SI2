"""CU20 - panel de despacho: quien lleva cada pedido y en que anda.

Autorizacion por permiso (CU13): envios.leer para mirar, envios.actualizar para asignar y
mover estados. Encima del permiso hay dos recortes de alcance:
  - por sucursal, igual que recepciones/ y reportes/: un ADMIN (el que tiene
    sucursales.actualizar) ve toda la cadena, el resto solo la suya.
  - por repartidor: un STAFF con cargo REPARTIDOR solo ve y toca los envios que tiene
    asignados. Es su hoja de ruta, no el tablero de la sucursal.
"""

from datetime import datetime, timezone
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.auditoria import registrar_auditoria
from app.core.db import get_connection
from app.core.deps import requiere_permiso
from app.modules.envios.admin_schemas import (
    AsignarRepartidorIn,
    CambioEstadoIn,
    EnvioAdminDetalleOut,
    EnvioAdminOut,
    EventoAdminOut,
    ItemEnvioOut,
    RepartidorOut,
    ResumenEnviosOut,
)

router = APIRouter(prefix="/admin/envios", tags=["admin-envios"])

puede_ver = requiere_permiso("envios.leer", "envios.actualizar")
puede_actualizar = requiere_permiso("envios.actualizar")

# de que estado se puede pasar a cual. ENTREGADO no esta: es terminal.
TRANSICIONES: dict[str, set[str]] = {
    "PENDIENTE": {"ASIGNADO", "CANCELADO"},
    "ASIGNADO": {"EN_RUTA", "PENDIENTE", "CANCELADO"},
    "EN_RUTA": {"ENTREGADO", "FALLIDO"},
    "FALLIDO": {"EN_RUTA", "CANCELADO"},
    "ENTREGADO": set(),
    "CANCELADO": set(),
}

ESTADOS_ABIERTOS = ("PENDIENTE", "ASIGNADO", "EN_RUTA", "FALLIDO")

SELECT_ENVIO = """
SELECT e.id, e.venta_id, v.numero AS numero_venta, e.estado,
       e.sucursal_id, s.nombre AS sucursal,
       COALESCE(c.nombre || ' ' || c.apellido, 'Cliente') AS cliente, c.telefono AS cliente_telefono,
       e.ciudad, e.direccion_texto, e.referencia, e.latitud, e.longitud,
       e.distancia_km, e.duracion_min, e.costo, e.proveedor_ruteo, v.total AS total_venta,
       e.repartidor_id,
       CASE WHEN r.id IS NULL THEN NULL ELSE r.nombre || ' ' || r.apellido END AS repartidor,
       e.observacion, e.creado_en, e.asignado_en, e.despachado_en, e.cerrado_en
FROM envio e
JOIN venta v        ON v.id = e.venta_id
JOIN sucursal s     ON s.id = e.sucursal_id
LEFT JOIN usuario c ON c.id = v.usuario_id
LEFT JOIN usuario r ON r.id = e.repartidor_id
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


def _es_repartidor(staff: dict) -> bool:
    return staff["cargo"] == "REPARTIDOR"


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
        repartidor_id=fila["repartidor_id"],
        repartidor=fila["repartidor"],
        observacion=fila["observacion"],
        creado_en=fila["creado_en"],
        asignado_en=fila["asignado_en"],
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
    if _es_repartidor(staff) and fila["repartidor_id"] != staff["id"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="Ese envio no esta asignado a vos"
        )
    return fila


@router.get("", response_model=list[EnvioAdminOut])
async def listar_envios(
    estado: str | None = Query(default=None),
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
    if _es_repartidor(staff):
        parametros.append(staff["id"])
        condiciones.append(f"e.repartidor_id = ${len(parametros)}")

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
    repartidor_filtro = staff["id"] if _es_repartidor(staff) else None

    fila = await conn.fetchrow(
        """
        SELECT
            count(*) FILTER (WHERE estado = 'PENDIENTE')                            AS pendientes,
            count(*) FILTER (WHERE estado = 'ASIGNADO')                             AS asignados,
            count(*) FILTER (WHERE estado = 'EN_RUTA')                              AS en_ruta,
            count(*) FILTER (WHERE estado = 'ENTREGADO'
                             AND cerrado_en >= date_trunc('day', now()))            AS entregados_hoy,
            count(*) FILTER (WHERE estado = 'FALLIDO')                              AS fallidos
        FROM envio
        WHERE ($1::uuid IS NULL OR sucursal_id = $1::uuid)
          AND ($2::uuid IS NULL OR repartidor_id = $2::uuid)
        """,
        sucursal_filtro,
        repartidor_filtro,
    )
    return ResumenEnviosOut(
        pendientes=fila["pendientes"],
        asignados=fila["asignados"],
        en_ruta=fila["en_ruta"],
        entregados_hoy=fila["entregados_hoy"],
        fallidos=fila["fallidos"],
    )


@router.get("/repartidores", response_model=list[RepartidorOut])
async def listar_repartidores(
    sucursal_id: UUID | None = Query(default=None),
    staff: dict = Depends(puede_ver),
    conn: asyncpg.Connection = Depends(get_connection),
) -> list[RepartidorOut]:
    """Para el combo de asignacion. Trae la carga de trabajo de cada uno para no mandarle
    cinco paquetes al mismo mientras otro esta libre."""
    limite_sucursal = _sucursal_visible(staff)
    sucursal_filtro = limite_sucursal if limite_sucursal is not None else sucursal_id

    filas = await conn.fetch(
        """
        SELECT u.id, (u.nombre || ' ' || u.apellido) AS nombre, e.sucursal_id, s.nombre AS sucursal,
               (SELECT count(*) FROM envio en
                 WHERE en.repartidor_id = u.id AND en.estado IN ('ASIGNADO','EN_RUTA')) AS envios_activos
        FROM usuario u
        JOIN empleado e ON e.usuario_id = u.id AND e.activo
        JOIN sucursal s ON s.id = e.sucursal_id
        WHERE u.activo AND e.cargo = 'REPARTIDOR'
          AND ($1::uuid IS NULL OR e.sucursal_id = $1::uuid)
        ORDER BY envios_activos, nombre
        """,
        sucursal_filtro,
    )
    return [
        RepartidorOut(
            id=fila["id"],
            nombre=fila["nombre"],
            sucursal_id=fila["sucursal_id"],
            sucursal=fila["sucursal"],
            envios_activos=fila["envios_activos"],
        )
        for fila in filas
    ]


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


@router.post("/{envio_id}/asignar", response_model=EnvioAdminOut)
async def asignar_repartidor(
    envio_id: UUID,
    body: AsignarRepartidorIn,
    staff: dict = Depends(puede_actualizar),
    conn: asyncpg.Connection = Depends(get_connection),
) -> EnvioAdminOut:
    if _es_repartidor(staff):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Un repartidor no asigna envios, solo los lleva",
        )

    envio = await _obtener(conn, envio_id, staff)
    if envio["estado"] not in ("PENDIENTE", "ASIGNADO"):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Un envio {envio['estado']} ya no se puede reasignar",
        )

    repartidor = await conn.fetchrow(
        """
        SELECT u.id, e.sucursal_id FROM usuario u
        JOIN empleado e ON e.usuario_id = u.id AND e.activo
        WHERE u.id = $1 AND u.activo AND e.cargo = 'REPARTIDOR'
        """,
        body.repartidor_id,
    )
    if repartidor is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Ese usuario no es un repartidor activo"
        )
    if repartidor["sucursal_id"] != envio["sucursal_id"]:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="El repartidor es de otra sucursal",
        )

    await conn.execute(
        """
        UPDATE envio
           SET repartidor_id = $2, estado = 'ASIGNADO', asignado_en = now(),
               observacion = $3, actualizado_por_id = $4
         WHERE id = $1
        """,
        envio_id,
        body.repartidor_id,
        body.observacion,
        staff["id"],
    )
    await registrar_auditoria(
        conn,
        usuario_id=staff["id"],
        entidad="envio",
        entidad_id=str(envio_id),
        accion="ACTUALIZAR",
        datos_antes={"estado": envio["estado"], "repartidor_id": str(envio["repartidor_id"] or "")},
        datos_despues={"estado": "ASIGNADO", "repartidor_id": str(body.repartidor_id)},
    )

    return _a_salida(await _obtener(conn, envio_id, staff))


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
    if body.estado == "EN_RUTA" and envio["repartidor_id"] is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Asigna un repartidor antes de despachar el envio",
        )
    if body.estado == "FALLIDO" and not body.observacion:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Un envio fallido necesita un motivo",
        )

    ahora = datetime.now(timezone.utc)
    despachado_en = ahora if body.estado == "EN_RUTA" else envio["despachado_en"]
    cerrado_en = ahora if body.estado in ("ENTREGADO", "FALLIDO", "CANCELADO") else None
    # volver a PENDIENTE es soltar al repartidor para que el encargado reasigne
    repartidor_id = None if body.estado == "PENDIENTE" else envio["repartidor_id"]
    asignado_en = None if body.estado == "PENDIENTE" else envio["asignado_en"]

    async with conn.transaction():
        await conn.execute(
            """
            UPDATE envio
               SET estado = $2::estado_envio, observacion = $3, actualizado_por_id = $4,
                   repartidor_id = $5, asignado_en = $6, despachado_en = $7, cerrado_en = $8
             WHERE id = $1
            """,
            envio_id,
            body.estado,
            body.observacion,
            staff["id"],
            repartidor_id,
            asignado_en,
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
