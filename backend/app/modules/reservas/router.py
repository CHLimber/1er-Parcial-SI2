from datetime import date
from uuid import uuid4

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status

from app.core.db import get_connection
from app.core.deps import get_current_usuario
from app.modules.reservas.schemas import (
    ItemRechazadoOut,
    ReservaCrear,
    ReservaItemOut,
    ReservaOut,
)

router = APIRouter(prefix="/reservas", tags=["reservas"])


def _exigir_cliente(usuario: dict) -> None:
    if usuario["tipo"] != "CLIENTE":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo un cliente puede reservar prendas",
        )


@router.post("", response_model=ReservaOut, status_code=status.HTTP_201_CREATED)
async def crear_reserva(
    body: ReservaCrear,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> ReservaOut:
    _exigir_cliente(usuario)

    if body.fecha_visita < date.today():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="La fecha de la reserva no puede ser en el pasado",
        )

    sucursal = await conn.fetchrow(
        "SELECT id, nombre, hora_apertura, hora_cierre FROM sucursal WHERE id = $1 AND activa",
        body.sucursal_id,
    )
    if sucursal is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sucursal no encontrada")

    if sucursal["hora_apertura"] and sucursal["hora_cierre"]:
        if not (sucursal["hora_apertura"] <= body.hora_visita <= sucursal["hora_cierre"]):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=(
                    f"La sucursal atiende de {sucursal['hora_apertura']} a "
                    f"{sucursal['hora_cierre']}"
                ),
            )

    variante_ids = [item.variante_id for item in body.items]
    filas = await conn.fetch(
        """
        SELECT pv.id AS variante_id, pv.sku, pv.activa, p.nombre AS producto,
               t.codigo AS talla, c.nombre AS color,
               COALESCE(i.disponible, 0) AS disponible
        FROM producto_variante pv
        JOIN producto p ON p.id = pv.producto_id
        JOIN talla t    ON t.id = pv.talla_id
        JOIN color c    ON c.id = pv.color_id
        LEFT JOIN inventario i ON i.variante_id = pv.id AND i.sucursal_id = $2
        WHERE pv.id = ANY($1::uuid[])
        """,
        variante_ids,
        body.sucursal_id,
    )
    info_por_variante = {fila["variante_id"]: fila for fila in filas}

    aceptados: list[tuple] = []
    rechazados: list[ItemRechazadoOut] = []
    for item in body.items:
        info = info_por_variante.get(item.variante_id)
        if info is None or not info["activa"]:
            rechazados.append(
                ItemRechazadoOut(
                    variante_id=item.variante_id,
                    sku=info["sku"] if info else "?",
                    motivo="Esa prenda ya no esta disponible en el catalogo",
                )
            )
        elif info["disponible"] < item.cantidad:
            rechazados.append(
                ItemRechazadoOut(
                    variante_id=item.variante_id,
                    sku=info["sku"],
                    motivo=f"Stock insuficiente en esa sucursal ({info['disponible']} disponible(s))",
                )
            )
        else:
            aceptados.append((item, info))

    if not aceptados:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "mensaje": "No hay stock suficiente para ninguna de las prendas seleccionadas",
                "rechazados": [
                    {"variante_id": str(r.variante_id), "sku": r.sku, "motivo": r.motivo}
                    for r in rechazados
                ],
            },
        )

    config = await conn.fetchrow(
        "SELECT valor FROM configuracion WHERE clave = 'reserva_horas_vigencia'"
    )
    horas_vigencia = int(config["valor"]) if config else 4
    codigo = f"RES-{uuid4().hex[:10].upper()}"

    async with conn.transaction():
        reserva = await conn.fetchrow(
            """
            INSERT INTO reserva (usuario_id, sucursal_id, codigo, fecha_visita, hora_visita,
                                  expira_en, observaciones)
            VALUES ($1, $2, $3, $4, $5, now() + make_interval(hours => $6), $7)
            RETURNING id, codigo, sucursal_id, estado, fecha_visita, hora_visita, expira_en,
                      creada_en, observaciones
            """,
            usuario["id"],
            body.sucursal_id,
            codigo,
            body.fecha_visita,
            body.hora_visita,
            horas_vigencia,
            body.observaciones,
        )

        items_confirmados: list[ReservaItemOut] = []
        for item, info in aceptados:
            try:
                async with conn.transaction():
                    detalle = await conn.fetchrow(
                        """
                        INSERT INTO reserva_detalle (reserva_id, variante_id, cantidad)
                        VALUES ($1, $2, $3)
                        RETURNING id, variante_id, cantidad, estado_item
                        """,
                        reserva["id"],
                        item.variante_id,
                        item.cantidad,
                    )
            except asyncpg.PostgresError:
                rechazados.append(
                    ItemRechazadoOut(
                        variante_id=item.variante_id,
                        sku=info["sku"],
                        motivo="Otro cliente reservo esa unidad justo antes",
                    )
                )
                continue

            items_confirmados.append(
                ReservaItemOut(
                    id=detalle["id"],
                    variante_id=detalle["variante_id"],
                    sku=info["sku"],
                    producto=info["producto"],
                    talla=info["talla"],
                    color=info["color"],
                    cantidad=detalle["cantidad"],
                    estado_item=detalle["estado_item"],
                )
            )

        if not items_confirmados:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={
                    "mensaje": "No se pudo reservar ninguna prenda: el stock cambio mientras se confirmaba",
                    "rechazados": [
                        {"variante_id": str(r.variante_id), "sku": r.sku, "motivo": r.motivo}
                        for r in rechazados
                    ],
                },
            )

        empleados = await conn.fetch(
            """
            SELECT usuario_id FROM empleado
            WHERE sucursal_id = $1 AND activo AND cargo = 'ENCARGADO'
            """,
            body.sucursal_id,
        )
        mensaje = (
            f"Nueva reserva {codigo} para el {body.fecha_visita} a las {body.hora_visita}, "
            f"{len(items_confirmados)} prenda(s)."
        )
        for empleado in empleados:
            await conn.execute(
                """
                INSERT INTO notificacion (usuario_id, tipo, titulo, mensaje, entidad_tipo, entidad_id)
                VALUES ($1, 'RESERVA', 'Nueva reserva de vestidor', $2, 'RESERVA', $3)
                """,
                empleado["usuario_id"],
                mensaje,
                reserva["id"],
            )

    return ReservaOut(
        id=reserva["id"],
        codigo=reserva["codigo"],
        sucursal_id=reserva["sucursal_id"],
        sucursal=sucursal["nombre"],
        estado=reserva["estado"],
        fecha_visita=reserva["fecha_visita"],
        hora_visita=reserva["hora_visita"],
        expira_en=reserva["expira_en"],
        creada_en=reserva["creada_en"],
        observaciones=reserva["observaciones"],
        items=items_confirmados,
        items_rechazados=rechazados,
    )


@router.get("", response_model=list[ReservaOut])
async def listar_mis_reservas(
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> list[ReservaOut]:
    _exigir_cliente(usuario)

    reservas = await conn.fetch(
        """
        SELECT r.id, r.codigo, r.sucursal_id, s.nombre AS sucursal, r.estado,
               r.fecha_visita, r.hora_visita, r.expira_en, r.creada_en, r.observaciones
        FROM reserva r
        JOIN sucursal s ON s.id = r.sucursal_id
        WHERE r.usuario_id = $1
        ORDER BY r.creada_en DESC
        """,
        usuario["id"],
    )
    if not reservas:
        return []

    ids = [fila["id"] for fila in reservas]
    detalles = await conn.fetch(
        """
        SELECT rd.id, rd.reserva_id, rd.variante_id, rd.cantidad, rd.estado_item,
               pv.sku, p.nombre AS producto, t.codigo AS talla, c.nombre AS color
        FROM reserva_detalle rd
        JOIN producto_variante pv ON pv.id = rd.variante_id
        JOIN producto p ON p.id = pv.producto_id
        JOIN talla t    ON t.id = pv.talla_id
        JOIN color c    ON c.id = pv.color_id
        WHERE rd.reserva_id = ANY($1::uuid[])
        """,
        ids,
    )
    detalles_por_reserva: dict = {}
    for detalle in detalles:
        detalles_por_reserva.setdefault(detalle["reserva_id"], []).append(
            ReservaItemOut(
                id=detalle["id"],
                variante_id=detalle["variante_id"],
                sku=detalle["sku"],
                producto=detalle["producto"],
                talla=detalle["talla"],
                color=detalle["color"],
                cantidad=detalle["cantidad"],
                estado_item=detalle["estado_item"],
            )
        )

    return [
        ReservaOut(
            id=fila["id"],
            codigo=fila["codigo"],
            sucursal_id=fila["sucursal_id"],
            sucursal=fila["sucursal"],
            estado=fila["estado"],
            fecha_visita=fila["fecha_visita"],
            hora_visita=fila["hora_visita"],
            expira_en=fila["expira_en"],
            creada_en=fila["creada_en"],
            observaciones=fila["observaciones"],
            items=detalles_por_reserva.get(fila["id"], []),
            items_rechazados=[],
        )
        for fila in reservas
    ]
