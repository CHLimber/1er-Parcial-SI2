from datetime import date
from decimal import Decimal
from uuid import UUID, uuid4

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.db import get_connection
from app.core.deps import get_current_usuario, get_encargado_actual
from app.modules.reservas.schemas import (
    ClienteBreveOut,
    ItemRechazadoOut,
    MarcarPresenteIn,
    PrepararReservaIn,
    ReservaCrear,
    ReservaItemOut,
    ReservaOut,
    ReservaStaffOut,
    ResolverReservaIn,
    ResolverReservaOut,
)
from app.modules.ventas.router import IVA_TASA, _alertar_stock_bajo

router = APIRouter(prefix="/reservas", tags=["reservas"])

ESTADOS_COLA_ENCARGADO = ("CONFIRMADA", "PREPARADA", "CLIENTE_PRESENTE")


def _exigir_cliente(usuario: dict) -> None:
    if usuario["tipo"] != "CLIENTE":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo un cliente puede reservar prendas",
        )


async def _cargar_items_por_reserva(
    conn: asyncpg.Connection, reserva_ids: list[UUID]
) -> dict[UUID, list[ReservaItemOut]]:
    if not reserva_ids:
        return {}
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
        reserva_ids,
    )
    items_por_reserva: dict[UUID, list[ReservaItemOut]] = {}
    for detalle in detalles:
        items_por_reserva.setdefault(detalle["reserva_id"], []).append(
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
    return items_por_reserva


async def _obtener_reserva_staff(
    conn: asyncpg.Connection, reserva_id: UUID, sucursal_id: UUID, *, para_actualizar: bool = False
) -> asyncpg.Record:
    consulta = """
        SELECT r.id, r.codigo, r.sucursal_id, s.nombre AS sucursal, r.estado,
               r.fecha_visita, r.hora_visita, r.expira_en, r.creada_en, r.observaciones,
               r.vestidor_asignado, r.atendida_en, r.usuario_id,
               u.nombre AS cliente_nombre, u.apellido AS cliente_apellido,
               u.email AS cliente_email, u.telefono AS cliente_telefono
        FROM reserva r
        JOIN sucursal s ON s.id = r.sucursal_id
        JOIN usuario u ON u.id = r.usuario_id
        WHERE r.id = $1 AND r.sucursal_id = $2
    """
    if para_actualizar:
        consulta += " FOR UPDATE OF r"
    reserva = await conn.fetchrow(consulta, reserva_id, sucursal_id)
    if reserva is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Reserva no encontrada")
    return reserva


async def _reserva_staff_out(conn: asyncpg.Connection, reserva: asyncpg.Record) -> ReservaStaffOut:
    items = (await _cargar_items_por_reserva(conn, [reserva["id"]])).get(reserva["id"], [])
    return ReservaStaffOut(
        id=reserva["id"],
        codigo=reserva["codigo"],
        cliente=ClienteBreveOut(
            nombre=reserva["cliente_nombre"],
            apellido=reserva["cliente_apellido"],
            email=reserva["cliente_email"],
            telefono=reserva["cliente_telefono"],
        ),
        sucursal_id=reserva["sucursal_id"],
        sucursal=reserva["sucursal"],
        estado=reserva["estado"],
        fecha_visita=reserva["fecha_visita"],
        hora_visita=reserva["hora_visita"],
        expira_en=reserva["expira_en"],
        creada_en=reserva["creada_en"],
        observaciones=reserva["observaciones"],
        vestidor_asignado=reserva["vestidor_asignado"],
        atendida_en=reserva["atendida_en"],
        items=items,
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
                                  expira_en, observaciones, estado)
            VALUES ($1, $2, $3, $4, $5, now() + make_interval(hours => $6), $7, 'CONFIRMADA')
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
    detalles_por_reserva = await _cargar_items_por_reserva(conn, ids)

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


# --- CU08: Atender Reserva ---------------------------------------------------

_CONSULTA_STAFF = """
    SELECT r.id, r.codigo, r.sucursal_id, s.nombre AS sucursal, r.estado,
           r.fecha_visita, r.hora_visita, r.expira_en, r.creada_en, r.observaciones,
           r.vestidor_asignado, r.atendida_en, r.usuario_id,
           u.nombre AS cliente_nombre, u.apellido AS cliente_apellido,
           u.email AS cliente_email, u.telefono AS cliente_telefono
    FROM reserva r
    JOIN sucursal s ON s.id = r.sucursal_id
    JOIN usuario u ON u.id = r.usuario_id
"""


@router.get("/sucursal", response_model=list[ReservaStaffOut])
async def listar_reservas_sucursal(
    estado: str | None = Query(
        default=None, description="Filtra por un estado exacto de reserva"
    ),
    encargado: dict = Depends(get_encargado_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> list[ReservaStaffOut]:
    if estado is not None:
        if estado not in (
            "PENDIENTE", "CONFIRMADA", "PREPARADA", "CLIENTE_PRESENTE",
            "ATENDIDA", "CONVERTIDA", "CANCELADA", "EXPIRADA",
        ):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Estado de reserva invalido"
            )
        filas = await conn.fetch(
            _CONSULTA_STAFF + " WHERE r.sucursal_id = $1 AND r.estado = $2::estado_reserva"
            " ORDER BY r.fecha_visita, r.hora_visita",
            encargado["sucursal_id"],
            estado,
        )
    else:
        filas = await conn.fetch(
            _CONSULTA_STAFF + " WHERE r.sucursal_id = $1 AND r.estado = ANY($2::estado_reserva[])"
            " ORDER BY r.fecha_visita, r.hora_visita",
            encargado["sucursal_id"],
            list(ESTADOS_COLA_ENCARGADO),
        )

    ids = [fila["id"] for fila in filas]
    items_por_reserva = await _cargar_items_por_reserva(conn, ids)
    return [
        ReservaStaffOut(
            id=fila["id"],
            codigo=fila["codigo"],
            cliente=ClienteBreveOut(
                nombre=fila["cliente_nombre"],
                apellido=fila["cliente_apellido"],
                email=fila["cliente_email"],
                telefono=fila["cliente_telefono"],
            ),
            sucursal_id=fila["sucursal_id"],
            sucursal=fila["sucursal"],
            estado=fila["estado"],
            fecha_visita=fila["fecha_visita"],
            hora_visita=fila["hora_visita"],
            expira_en=fila["expira_en"],
            creada_en=fila["creada_en"],
            observaciones=fila["observaciones"],
            vestidor_asignado=fila["vestidor_asignado"],
            atendida_en=fila["atendida_en"],
            items=items_por_reserva.get(fila["id"], []),
        )
        for fila in filas
    ]


@router.get("/sucursal/{reserva_id}", response_model=ReservaStaffOut)
async def obtener_reserva_sucursal(
    reserva_id: UUID,
    encargado: dict = Depends(get_encargado_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> ReservaStaffOut:
    reserva = await _obtener_reserva_staff(conn, reserva_id, encargado["sucursal_id"])
    return await _reserva_staff_out(conn, reserva)


@router.post("/{reserva_id}/preparar", response_model=ReservaStaffOut)
async def preparar_reserva(
    reserva_id: UUID,
    body: PrepararReservaIn,
    encargado: dict = Depends(get_encargado_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> ReservaStaffOut:
    """CU08 paso 2: el Encargado prepara fisicamente las prendas reservadas. E2: si alguna ya no
    esta disponible por error de preparacion, se libera su compromiso y se informa al cliente."""
    async with conn.transaction():
        reserva = await _obtener_reserva_staff(
            conn, reserva_id, encargado["sucursal_id"], para_actualizar=True
        )
        if reserva["estado"] != "CONFIRMADA":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="La reserva no esta en estado CONFIRMADA",
            )

        pendientes = await conn.fetch(
            "SELECT variante_id, cantidad FROM reserva_detalle "
            "WHERE reserva_id = $1 AND estado_item = 'RESERVADO'",
            reserva_id,
        )
        cantidad_por_variante = {fila["variante_id"]: fila["cantidad"] for fila in pendientes}

        recibidos = {item.variante_id for item in body.items}
        if recibidos != set(cantidad_por_variante.keys()):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Los items enviados no coinciden con las prendas pendientes de preparar",
            )

        for item in body.items:
            if item.disponible:
                await conn.execute(
                    "UPDATE reserva_detalle SET estado_item = 'PREPARADO' "
                    "WHERE reserva_id = $1 AND variante_id = $2",
                    reserva_id,
                    item.variante_id,
                )
                continue

            # E2: la prenda ya no esta disponible -- se libera el compromiso y se avisa
            motivo = item.motivo or "Prenda no disponible al momento de prepararla"
            await conn.execute(
                "SELECT fn_mover_inventario($1, $2, 'LIBERACION', $3, $4, 'RESERVA', $5, $6)",
                reserva["sucursal_id"],
                item.variante_id,
                cantidad_por_variante[item.variante_id],
                motivo,
                reserva_id,
                encargado["usuario_id"],
            )
            await conn.execute(
                "UPDATE reserva_detalle SET estado_item = 'DESCARTADO' "
                "WHERE reserva_id = $1 AND variante_id = $2",
                reserva_id,
                item.variante_id,
            )
            await conn.execute(
                """
                INSERT INTO notificacion (usuario_id, tipo, titulo, mensaje, entidad_tipo, entidad_id)
                VALUES ($1, 'RESERVA', 'Ajuste en tu reserva', $2, 'RESERVA', $3)
                """,
                reserva["usuario_id"],
                f"En tu reserva {reserva['codigo']}, una prenda ya no estaba disponible: {motivo}",
                reserva_id,
            )

        quedan_preparadas = await conn.fetchval(
            "SELECT COUNT(*) FROM reserva_detalle WHERE reserva_id = $1 AND estado_item = 'PREPARADO'",
            reserva_id,
        )
        nuevo_estado = "PREPARADA" if quedan_preparadas > 0 else "CANCELADA"
        await conn.execute("UPDATE reserva SET estado = $1 WHERE id = $2", nuevo_estado, reserva_id)

        reserva = await _obtener_reserva_staff(conn, reserva_id, encargado["sucursal_id"])
        return await _reserva_staff_out(conn, reserva)


@router.post("/{reserva_id}/presente", response_model=ReservaStaffOut)
async def marcar_cliente_presente(
    reserva_id: UUID,
    body: MarcarPresenteIn,
    encargado: dict = Depends(get_encargado_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> ReservaStaffOut:
    """CU08 pasos 3-4: el cliente se presenta y el Encargado confirma su llegada."""
    async with conn.transaction():
        reserva = await _obtener_reserva_staff(
            conn, reserva_id, encargado["sucursal_id"], para_actualizar=True
        )
        if reserva["estado"] != "PREPARADA":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="La reserva no esta en estado PREPARADA",
            )

        await conn.execute(
            """
            UPDATE reserva
               SET estado = 'CLIENTE_PRESENTE', atendida_por_id = $1, atendida_en = now(),
                   vestidor_asignado = COALESCE($2, vestidor_asignado)
             WHERE id = $3
            """,
            encargado["usuario_id"],
            body.vestidor_asignado,
            reserva_id,
        )

        reserva = await _obtener_reserva_staff(conn, reserva_id, encargado["sucursal_id"])
        return await _reserva_staff_out(conn, reserva)


@router.post("/{reserva_id}/resolver", response_model=ResolverReservaOut)
async def resolver_reserva(
    reserva_id: UUID,
    body: ResolverReservaIn,
    encargado: dict = Depends(get_encargado_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> ResolverReservaOut:
    """CU08 pasos 5-7: el cliente se prueba las prendas y el Encargado registra la decision final
    (total, parcial o ninguna). Las unidades compradas pasan a venta (CU07); el resto libera su
    compromiso de stock."""
    async with conn.transaction():
        reserva = await _obtener_reserva_staff(
            conn, reserva_id, encargado["sucursal_id"], para_actualizar=True
        )
        if reserva["estado"] != "CLIENTE_PRESENTE":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="La reserva no esta en estado CLIENTE_PRESENTE",
            )

        candidatos = await conn.fetch(
            """
            SELECT rd.variante_id, rd.cantidad, pv.sku,
                   COALESCE(pv.precio_oferta, pv.precio, p.precio_base) AS precio
            FROM reserva_detalle rd
            JOIN producto_variante pv ON pv.id = rd.variante_id
            JOIN producto p ON p.id = pv.producto_id
            WHERE rd.reserva_id = $1 AND rd.estado_item = 'PREPARADO'
            """,
            reserva_id,
        )
        info_por_variante = {fila["variante_id"]: fila for fila in candidatos}

        if {d.variante_id for d in body.decisiones} != set(info_por_variante.keys()):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Las decisiones deben cubrir exactamente las prendas que el cliente se probo",
            )

        comprados = [d for d in body.decisiones if d.comprado]
        descartados = [d for d in body.decisiones if not d.comprado]

        if comprados and body.metodo_pago is None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Indica el metodo de pago para las prendas que el cliente compra",
            )

        await conn.execute("UPDATE reserva SET estado = 'ATENDIDA' WHERE id = $1", reserva_id)

        venta_id = None
        venta_numero = None
        comprobante_numero = None
        total_cobrado: Decimal | None = None

        if comprados:
            numero = f"V-{uuid4().hex[:10].upper()}"
            venta = await conn.fetchrow(
                """
                INSERT INTO venta (sucursal_id, canal, entrega, reserva_id, numero,
                                    subtotal, descuento, iva, total, registrada_por_id)
                VALUES ($1, 'POS', 'RETIRO_SUCURSAL', $2, $3, 0, 0, 0, 0, $4)
                RETURNING id
                """,
                reserva["sucursal_id"],
                reserva_id,
                numero,
                encargado["usuario_id"],
            )
            venta_id = venta["id"]
            venta_numero = numero

            subtotal = Decimal("0")
            for decision in comprados:
                info = info_por_variante[decision.variante_id]
                precio = Decimal(str(info["precio"]))
                subtotal_item = precio * info["cantidad"]
                subtotal += subtotal_item
                # el trigger tg_venta_descuenta_stock ve venta.reserva_id y libera el compromiso
                # de la reserva antes de descontar el stock fisico
                await conn.execute(
                    """
                    INSERT INTO venta_detalle (venta_id, variante_id, cantidad, precio_unitario, subtotal)
                    VALUES ($1, $2, $3, $4, $5)
                    """,
                    venta_id,
                    decision.variante_id,
                    info["cantidad"],
                    precio,
                    subtotal_item,
                )
                await conn.execute(
                    "UPDATE reserva_detalle SET estado_item = 'COMPRADO' "
                    "WHERE reserva_id = $1 AND variante_id = $2",
                    reserva_id,
                    decision.variante_id,
                )

            iva = (subtotal * IVA_TASA).quantize(Decimal("0.01"))
            total_cobrado = (subtotal + iva).quantize(Decimal("0.01"))
            await conn.execute(
                "UPDATE venta SET subtotal = $1, iva = $2, total = $3, estado = 'PAGADA' WHERE id = $4",
                subtotal,
                iva,
                total_cobrado,
                venta_id,
            )
            await conn.execute(
                """
                INSERT INTO pago (venta_id, metodo, monto, estado, confirmado_en)
                VALUES ($1, $2, $3, 'APROBADO', now())
                """,
                venta_id,
                body.metodo_pago,
                total_cobrado,
            )
            comprobante_numero = f"C-{uuid4().hex[:10].upper()}"
            await conn.execute(
                "INSERT INTO comprobante (venta_id, numero) VALUES ($1, $2)",
                venta_id,
                comprobante_numero,
            )

        for decision in descartados:
            info = info_por_variante[decision.variante_id]
            await conn.execute(
                "SELECT fn_mover_inventario($1, $2, 'LIBERACION', $3, $4, 'RESERVA', $5, $6)",
                reserva["sucursal_id"],
                decision.variante_id,
                info["cantidad"],
                "Prenda probada y no comprada",
                reserva_id,
                encargado["usuario_id"],
            )
            await conn.execute(
                "UPDATE reserva_detalle SET estado_item = 'DESCARTADO' "
                "WHERE reserva_id = $1 AND variante_id = $2",
                reserva_id,
                decision.variante_id,
            )

        estado_final = "CONVERTIDA" if comprados else "CANCELADA"
        await conn.execute("UPDATE reserva SET estado = $1 WHERE id = $2", estado_final, reserva_id)

        reserva_final = await _obtener_reserva_staff(conn, reserva_id, encargado["sucursal_id"])

    if venta_id is not None:
        await _alertar_stock_bajo(conn, reserva["sucursal_id"], venta_id)

    return ResolverReservaOut(
        reserva=await _reserva_staff_out(conn, reserva_final),
        venta_id=venta_id,
        venta_numero=venta_numero,
        comprobante_numero=comprobante_numero,
        total_cobrado=float(total_cobrado) if total_cobrado is not None else None,
    )


@router.post("/{reserva_id}/no-presentado", response_model=ReservaStaffOut)
async def marcar_no_presentado(
    reserva_id: UUID,
    encargado: dict = Depends(get_encargado_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> ReservaStaffOut:
    """E1: el cliente no se presento dentro del horario -- la reserva expira y libera todo el
    stock comprometido (tanto lo reservado como lo ya preparado)."""
    async with conn.transaction():
        reserva = await _obtener_reserva_staff(
            conn, reserva_id, encargado["sucursal_id"], para_actualizar=True
        )
        if reserva["estado"] not in ("CONFIRMADA", "PREPARADA"):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Solo se puede expirar una reserva CONFIRMADA o PREPARADA",
            )

        pendientes = await conn.fetch(
            "SELECT variante_id, cantidad FROM reserva_detalle "
            "WHERE reserva_id = $1 AND estado_item IN ('RESERVADO', 'PREPARADO')",
            reserva_id,
        )
        for item in pendientes:
            await conn.execute(
                "SELECT fn_mover_inventario($1, $2, 'LIBERACION', $3, $4, 'RESERVA', $5, $6)",
                reserva["sucursal_id"],
                item["variante_id"],
                item["cantidad"],
                "Reserva expirada sin presentacion del cliente",
                reserva_id,
                encargado["usuario_id"],
            )

        await conn.execute("UPDATE reserva SET estado = 'EXPIRADA' WHERE id = $1", reserva_id)

        reserva = await _obtener_reserva_staff(conn, reserva_id, encargado["sucursal_id"])
        return await _reserva_staff_out(conn, reserva)
