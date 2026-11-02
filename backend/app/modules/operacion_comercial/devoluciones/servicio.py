"""Reglas de devoluciones e intercambios que comparten la caja (router.py) y la clienta
(cliente_router.py): calculo de montos, validaciones de la venta y el registro de la solicitud.

Montos (todo con IVA, en Bs):
  - lo que vale lo devuelto (monto_devuelto): se prorratea lo que la clienta pago POR LA
    MERCADERIA (venta.total - venta.costo_envio, ya con descuento e IVA) en proporcion al
    subtotal de lista de cada linea. La devolucion que completa la venta se lleva el resto exacto.
  - lo que valen las prendas nuevas de un intercambio (monto_cambio): precio de lista de cada
    variante pedida (fijado al registrar, devolucion_detalle.precio_solicitado) + IVA 13%.
  - diferencia = monto_cambio - monto_devuelto: si es positiva la clienta paga eso en caja; si es
    negativa se le devuelve por donde pago la compra original.
"""

from datetime import date, datetime, time, timedelta, timezone
from decimal import ROUND_HALF_UP, Decimal
from uuid import UUID

import asyncpg
from fastapi import HTTPException, status

from app.core.auditoria import registrar_auditoria

CENTAVO = Decimal("0.01")
IVA_TASA = Decimal("0.13")  # mismo valor que ventas/router.py (fijo en la app, no parametrizable)
ESTADOS_VENTA_DEVOLVIBLE = ("PAGADA", "ENTREGADA")
ESTADOS_EN_TRAMITE = ("SOLICITADA", "CONFIRMADA")
ESTADOS_VIGENTES = ("SOLICITADA", "CONFIRMADA", "APROBADA")  # una sola por compra
MOTIVOS_INTERCAMBIO = ("TALLA", "COLOR")
PLAZO_DIAS_POR_DEFECTO = 3  # si falta configuracion.devolucion_plazo_dias
PLAZO_CAMBIO_POR_DEFECTO = 3  # si falta configuracion.cambio_plazo_dias
MAX_UNIDADES_POR_DEFECTO = 3  # si falta configuracion.devolucion_max_unidades
HORAS_VIGENCIA_POR_DEFECTO = 4  # si falta configuracion.reserva_horas_vigencia
HUSO_BOLIVIA = timezone(timedelta(hours=-4))  # sin horario de verano


def tipo_de(motivo_tipo: str) -> str:
    return "INTERCAMBIO" if motivo_tipo in MOTIVOS_INTERCAMBIO else "DEVOLUCION"


def hoy_bolivia() -> date:
    return datetime.now(HUSO_BOLIVIA).date()


# ---------------------------------------------------------------------
#  REGLAS PURAS
# ---------------------------------------------------------------------


def condiciones_faltantes(
    motivo_tipo: str, con_etiqueta: bool, sin_uso: bool, con_comprobante: bool
) -> list[str]:
    """Condiciones que la prenda no cumple para el motivo dado (vacio = se acepta). Por DEFECTO
    solo se exige el comprobante: la prenda pudo usarse hasta notar la falla."""
    faltan = []
    if not con_comprobante:
        faltan.append("el comprobante de compra")
    if motivo_tipo != "DEFECTO":
        if not con_etiqueta:
            faltan.append("la etiqueta original")
        if not sin_uso:
            faltan.append("la prenda sin uso")
    return faltan


def validar_variante_cambio(motivo_tipo: str, original, solicitada) -> str | None:
    """Error de negocio si la variante pedida a cambio no sirve para el motivo, o None.
    original/solicitada son filas (o dicts) con producto_id, talla_id y color_id."""
    if solicitada["producto_id"] != original["producto_id"]:
        return "el cambio tiene que ser por la misma prenda"
    if motivo_tipo == "TALLA" and solicitada["talla_id"] == original["talla_id"]:
        return "un cambio por talla tiene que pedir otra talla"
    if motivo_tipo == "COLOR" and solicitada["color_id"] == original["color_id"]:
        return "un cambio por color tiene que pedir otro color"
    return None


def metodo_reintegro(pago) -> str | None:
    """Por donde vuelve la plata: por donde entro. Un pago online va por pasarela (STRIPE o QR);
    uno de caja, por su metodo. EFECTIVO y QR se devuelven en efectivo desde el cajon."""
    if pago is None:
        return None
    if pago["pasarela"] in ("STRIPE", "QR"):
        return pago["pasarela"]
    if pago["metodo"] in ("EFECTIVO", "TARJETA", "QR", "TRANSFERENCIA"):
        return pago["metodo"]
    return None


def sale_del_cajon(metodo: str | None) -> bool:
    return metodo in ("EFECTIVO", "QR")


def agrupar_lineas(lineas, es_intercambio: bool) -> tuple[dict, dict]:
    """(unidades por linea de venta, variante pedida por linea). La misma linea dos veces se
    suma. 422 si un intercambio no dice que se lleva o una devolucion pide algo a cambio."""
    pedidas: dict[UUID, int] = {}
    solicitadas: dict[UUID, UUID | None] = {}
    for linea in lineas:
        pedidas[linea.venta_detalle_id] = pedidas.get(linea.venta_detalle_id, 0) + linea.cantidad
        if es_intercambio and linea.variante_solicitada_id is None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="En un intercambio cada prenda tiene que decir que talla o color se lleva a cambio",
            )
        if not es_intercambio and linea.variante_solicitada_id is not None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Solo un intercambio por talla o color lleva una prenda a cambio",
            )
        anterior = solicitadas.get(linea.venta_detalle_id)
        if anterior is not None and anterior != linea.variante_solicitada_id:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="La misma prenda no puede pedir dos variantes distintas a cambio",
            )
        solicitadas[linea.venta_detalle_id] = linea.variante_solicitada_id
    return pedidas, solicitadas


def con_iva(subtotal: Decimal) -> Decimal:
    """Total de una venta de caja a partir del subtotal de lista (mismo calculo que /ventas/pos)."""
    iva = (subtotal * IVA_TASA).quantize(CENTAVO, rounding=ROUND_HALF_UP)
    return (subtotal + iva).quantize(CENTAVO, rounding=ROUND_HALF_UP)


def prorratear(bruto: Decimal, mercaderia: Decimal, suma_lineas: Decimal) -> Decimal:
    if suma_lineas <= 0:
        return Decimal("0.00")
    return (bruto * mercaderia / suma_lineas).quantize(CENTAVO, rounding=ROUND_HALF_UP)


def liquidar(tipo: str, valor_devuelto: Decimal, valor_cambio: Decimal) -> tuple[Decimal, Decimal]:
    """(lo que se reintegra a la clienta, lo que paga de mas). Una devolucion reintegra todo lo
    que vale lo devuelto; un intercambio usa eso como credito para las prendas nuevas."""
    if tipo == "DEVOLUCION":
        return valor_devuelto, Decimal("0.00")
    diferencia = valor_cambio - valor_devuelto
    if diferencia >= 0:
        return Decimal("0.00"), diferencia
    return -diferencia, Decimal("0.00")


# ---------------------------------------------------------------------
#  CONFIGURACION
# ---------------------------------------------------------------------


async def config_int(conn: asyncpg.Connection, clave: str, por_defecto: int) -> int:
    valor = await conn.fetchval("SELECT valor FROM configuracion WHERE clave = $1", clave)
    try:
        return int(valor) if valor is not None else por_defecto
    except ValueError:
        return por_defecto


async def plazo_dias(conn: asyncpg.Connection, tipo: str = "DEVOLUCION") -> int:
    if tipo == "INTERCAMBIO":
        return await config_int(conn, "cambio_plazo_dias", PLAZO_CAMBIO_POR_DEFECTO)
    return await config_int(conn, "devolucion_plazo_dias", PLAZO_DIAS_POR_DEFECTO)


async def max_unidades(conn: asyncpg.Connection) -> int:
    return await config_int(conn, "devolucion_max_unidades", MAX_UNIDADES_POR_DEFECTO)


# ---------------------------------------------------------------------
#  LECTURAS COMPARTIDAS
# ---------------------------------------------------------------------


async def pago_de_venta(conn: asyncpg.Connection, venta_id: UUID) -> asyncpg.Record | None:
    return await conn.fetchrow(
        """
        SELECT metodo::text AS metodo, pasarela::text AS pasarela, id_transaccion
        FROM pago WHERE venta_id = $1 AND estado = 'APROBADO'
        ORDER BY creado_en DESC LIMIT 1
        """,
        venta_id,
    )


async def base_venta(conn: asyncpg.Connection, venta_id: UUID) -> tuple[Decimal, Decimal]:
    """(lo pagado por la mercaderia, suma de subtotales de lista de sus lineas)."""
    fila = await conn.fetchrow(
        """
        SELECT v.total - v.costo_envio AS mercaderia,
               (SELECT COALESCE(SUM(vd.subtotal), 0) FROM venta_detalle vd
                 WHERE vd.venta_id = v.id) AS suma_lineas
        FROM venta v WHERE v.id = $1
        """,
        venta_id,
    )
    return fila["mercaderia"], fila["suma_lineas"]


async def monto_devolucion(
    conn: asyncpg.Connection, venta_id: UUID, devolucion_id: UUID, cierra_la_venta: bool
) -> Decimal:
    mercaderia, suma_lineas = await base_venta(conn, venta_id)
    if cierra_la_venta:
        ya_devuelto = await conn.fetchval(
            """
            SELECT COALESCE(SUM(monto_devuelto), 0) FROM devolucion
             WHERE venta_id = $1 AND estado = 'APROBADA' AND id <> $2
            """,
            venta_id,
            devolucion_id,
        )
        return max(mercaderia - ya_devuelto, Decimal("0.00"))

    bruto = await conn.fetchval(
        """
        SELECT COALESCE(SUM(dd.cantidad * vd.subtotal / vd.cantidad), 0)
        FROM devolucion_detalle dd
        JOIN venta_detalle vd ON vd.id = dd.venta_detalle_id
        WHERE dd.devolucion_id = $1
        """,
        devolucion_id,
    )
    return prorratear(bruto, mercaderia, suma_lineas)


async def subtotal_cambio(conn: asyncpg.Connection, devolucion_id: UUID) -> Decimal:
    """Subtotal de lista (sin IVA) de las prendas pedidas a cambio, al precio pactado."""
    return await conn.fetchval(
        """
        SELECT COALESCE(SUM(cantidad * precio_solicitado), 0) FROM devolucion_detalle
        WHERE devolucion_id = $1 AND variante_solicitada_id IS NOT NULL
        """,
        devolucion_id,
    )


async def lineas_de_venta(conn: asyncpg.Connection, venta_id: UUID) -> list[asyncpg.Record]:
    """Cada linea de la venta con lo ya devuelto y lo que esta en tramite."""
    return await conn.fetch(
        """
        SELECT vd.id AS venta_detalle_id, vd.variante_id, pv.sku, pr.nombre AS producto,
               t.codigo AS talla, c.nombre AS color,
               vd.cantidad AS cantidad_vendida, vd.precio_unitario, vd.subtotal,
               COALESCE(SUM(dd.cantidad) FILTER (WHERE dv.estado = 'APROBADA'), 0)::int AS devuelta,
               COALESCE(SUM(dd.cantidad) FILTER (
                   WHERE dv.estado IN ('SOLICITADA', 'CONFIRMADA')), 0)::int AS en_tramite
        FROM venta_detalle vd
        JOIN producto_variante pv ON pv.id = vd.variante_id
        JOIN producto pr          ON pr.id = pv.producto_id
        JOIN talla t              ON t.id = pv.talla_id
        JOIN color c              ON c.id = pv.color_id
        LEFT JOIN devolucion_detalle dd ON dd.venta_detalle_id = vd.id
        LEFT JOIN devolucion dv         ON dv.id = dd.devolucion_id
        WHERE vd.venta_id = $1
        GROUP BY vd.id, pv.sku, pr.nombre, t.codigo, t.orden, c.nombre
        ORDER BY pr.nombre, t.orden, c.nombre
        """,
        venta_id,
    )


async def variantes_de_cambio(
    conn: asyncpg.Connection, variante_id: UUID, sucursal_id: UUID
) -> list[asyncpg.Record]:
    """Las otras tallas/colores de la misma prenda con su precio y disponible en la sucursal."""
    return await conn.fetch(
        """
        SELECT pv.id AS variante_id, pv.sku, t.codigo AS talla, c.nombre AS color,
               COALESCE(pv.precio_oferta, pv.precio, p.precio_base) AS precio,
               COALESCE(i.disponible, 0) AS disponible
        FROM producto_variante pv
        JOIN producto_variante orig ON orig.id = $1 AND orig.producto_id = pv.producto_id
        JOIN producto p ON p.id = pv.producto_id
        JOIN talla t ON t.id = pv.talla_id
        JOIN color c ON c.id = pv.color_id
        LEFT JOIN inventario i ON i.variante_id = pv.id AND i.sucursal_id = $2
        WHERE pv.activa AND pv.id <> $1
        ORDER BY t.orden, c.nombre
        """,
        variante_id,
        sucursal_id,
    )


async def solicitud_vigente(conn: asyncpg.Connection, venta_id: UUID) -> str | None:
    """Numero de la devolucion/intercambio en tramite o aprobada de la venta, si la hay."""
    return await conn.fetchval(
        """
        SELECT numero FROM devolucion
        WHERE venta_id = $1 AND estado IN ('SOLICITADA', 'CONFIRMADA', 'APROBADA')
        LIMIT 1
        """,
        venta_id,
    )


async def es_venta_de_cambio(conn: asyncpg.Connection, venta_id: UUID) -> bool:
    return bool(
        await conn.fetchval(
            "SELECT EXISTS (SELECT 1 FROM devolucion WHERE venta_cambio_id = $1)", venta_id
        )
    )


# ---------------------------------------------------------------------
#  REGISTRO (caja y online)
# ---------------------------------------------------------------------


async def _validar_cambio_linea(
    conn: asyncpg.Connection,
    motivo_tipo: str,
    sucursal_id: UUID,
    linea: asyncpg.Record,
    variante_solicitada_id: UUID,
) -> asyncpg.Record:
    """La variante pedida a cambio: misma prenda, otra talla/color. Devuelve la fila con su
    precio de lista (el stock lo valida fn_mover_inventario al comprometerlo)."""
    variantes = {
        f["id"]: f
        for f in await conn.fetch(
            """
            SELECT pv.id, pv.producto_id, pv.talla_id, pv.color_id, pv.activa,
                   t.codigo AS talla, c.nombre AS color,
                   COALESCE(pv.precio_oferta, pv.precio, p.precio_base) AS precio
            FROM producto_variante pv
            JOIN producto p ON p.id = pv.producto_id
            JOIN talla t ON t.id = pv.talla_id
            JOIN color c ON c.id = pv.color_id
            WHERE pv.id IN ($1, $2)
            """,
            linea["variante_id"],
            variante_solicitada_id,
        )
    }
    solicitada = variantes.get(variante_solicitada_id)
    if solicitada is None or not solicitada["activa"]:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="La prenda pedida a cambio no existe o esta dada de baja",
        )
    error = validar_variante_cambio(motivo_tipo, variantes[linea["variante_id"]], solicitada)
    if error:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"{linea['producto']}: {error}",
        )
    return solicitada


async def validar_venta(
    conn: asyncpg.Connection, venta: asyncpg.Record, tipo: str
) -> None:
    """Reglas de la compra: pagada o entregada, dentro del plazo, no nacida de otro intercambio
    y sin otra devolucion/intercambio vigente. 409 con el motivo."""
    if venta["estado"] not in ESTADOS_VENTA_DEVOLVIBLE:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"La compra esta {venta['estado'].lower()}: solo se devuelve una compra pagada o entregada",
        )
    if await es_venta_de_cambio(conn, venta["id"]):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"La compra {venta['numero']} salio de un intercambio: ya uso su devolucion",
        )
    dias = await plazo_dias(conn, tipo)
    vencida = await conn.fetchval(
        "SELECT now() > fecha + make_interval(days => $2) FROM venta WHERE id = $1",
        venta["id"],
        dias,
    )
    if vencida:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                f"La compra {venta['numero']} tiene mas de {dias} dias: ya paso el plazo para "
                + ("cambiar la prenda" if tipo == "INTERCAMBIO" else "devolverla")
            ),
        )
    vigente = await solicitud_vigente(conn, venta["id"])
    if vigente:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                f"La compra {venta['numero']} ya tiene la devolucion/intercambio {vigente}: "
                "se permite una sola por compra"
            ),
        )


async def registrar(
    conn: asyncpg.Connection,
    *,
    venta_id: UUID,
    motivo_tipo: str,
    motivo: str,
    lineas,
    usuario_id: UUID,
    origen: str,
    con_etiqueta: bool = True,
    sin_uso: bool = True,
    con_comprobante: bool = True,
    visita: tuple[date, time] | None = None,
    validar_venta_extra=None,
) -> UUID:
    """Registra la devolucion/intercambio en SOLICITADA y devuelve su id. Debe correr dentro de
    una transaccion. En un intercambio compromete ya las prendas pedidas a cambio (como una
    reserva) para que la tienda no las venda mientras tanto.

    validar_venta_extra(venta): chequeo propio de quien llama (alcance de sucursal del personal,
    o que la compra sea de la clienta), con la venta ya bloqueada."""
    tipo = tipo_de(motivo_tipo)
    pedidas, solicitadas = agrupar_lineas(lineas, tipo == "INTERCAMBIO")
    tope = await max_unidades(conn)
    total_unidades = sum(pedidas.values())
    if total_unidades > tope:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Se pueden devolver o cambiar hasta {tope} prendas por compra (se pidieron {total_unidades})",
        )

    # Se bloquea la venta: dos registros simultaneos sobre la misma venta se serializan y el
    # segundo ve lo que el primero dejo en tramite (ademas del indice unico parcial).
    venta = await conn.fetchrow(
        "SELECT id, sucursal_id, estado::text AS estado, numero, usuario_id, fecha "
        "FROM venta WHERE id = $1 FOR UPDATE",
        venta_id,
    )
    if venta is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Compra no encontrada")
    if validar_venta_extra is not None:
        await validar_venta_extra(venta)
    await validar_venta(conn, venta, tipo)

    lineas_venta = {f["venta_detalle_id"]: f for f in await lineas_de_venta(conn, venta["id"])}
    precios: dict[UUID, Decimal] = {}
    for venta_detalle_id, cantidad in pedidas.items():
        linea = lineas_venta.get(venta_detalle_id)
        if linea is None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Una de las prendas no pertenece a esta compra",
            )
        disponible = linea["cantidad_vendida"] - linea["devuelta"] - linea["en_tramite"]
        if cantidad > disponible:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    f"{linea['producto']} ({linea['talla']} · {linea['color']}): se compraron "
                    f"{linea['cantidad_vendida']} y se pueden devolver {max(disponible, 0)}"
                ),
            )
        if tipo == "INTERCAMBIO":
            solicitada = await _validar_cambio_linea(
                conn, motivo_tipo, venta["sucursal_id"], linea, solicitadas[venta_detalle_id]
            )
            precios[venta_detalle_id] = solicitada["precio"]

    fecha_visita, hora_visita = visita if visita else (None, None)
    horas = await config_int(conn, "reserva_horas_vigencia", HORAS_VIGENCIA_POR_DEFECTO)
    try:
        devolucion_id = await conn.fetchval(
            """
            INSERT INTO devolucion (venta_id, sucursal_id, motivo, monto_devuelto, usuario_id,
                                    motivo_tipo, con_etiqueta, sin_uso, con_comprobante,
                                    tipo, origen, fecha_visita, hora_visita, expira_en)
            VALUES ($1, $2, $3, 0, $4, $5::motivo_devolucion, $6, $7, $8, $9, $10, $11, $12,
                    -- como una reserva: la vigencia corre desde la VISITA (hora de Bolivia)
                    CASE WHEN $11::date IS NULL THEN NULL
                         ELSE GREATEST(now(), ($11::date + $12::time) AT TIME ZONE 'America/La_Paz')
                              + make_interval(hours => $13) END)
            RETURNING id
            """,
            venta["id"],
            venta["sucursal_id"],
            motivo.strip(),
            usuario_id,
            motivo_tipo,
            con_etiqueta,
            sin_uso,
            con_comprobante,
            tipo,
            origen,
            fecha_visita,
            hora_visita,
            horas,
        )
    except asyncpg.UniqueViolationError as error:  # ux_devolucion_una_por_venta
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Esa compra ya tiene una devolucion o intercambio: se permite una sola por compra",
        ) from error

    await conn.executemany(
        """
        INSERT INTO devolucion_detalle (devolucion_id, venta_detalle_id, cantidad,
                                        variante_solicitada_id, precio_solicitado)
        VALUES ($1, $2, $3, $4, $5)
        """,
        [
            (devolucion_id, vd_id, cantidad, solicitadas[vd_id], precios.get(vd_id))
            for vd_id, cantidad in pedidas.items()
        ],
    )

    if tipo == "INTERCAMBIO":
        for vd_id, cantidad in pedidas.items():
            linea = lineas_venta[vd_id]
            try:
                await conn.execute(
                    "SELECT fn_mover_inventario($1, $2, 'RESERVA', $3, $4, 'DEVOLUCION', $5, $6)",
                    venta["sucursal_id"],
                    solicitadas[vd_id],
                    cantidad,
                    "Intercambio: prenda pedida a cambio",
                    devolucion_id,
                    usuario_id,
                )
            except asyncpg.RaiseError as error:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        f"No hay stock en la sucursal de la talla/color pedida para {linea['producto']} "
                        f"({error}). Se puede pedir por traspaso o elegir otra."
                    ),
                ) from error
        await conn.execute(
            "UPDATE devolucion SET stock_comprometido = TRUE WHERE id = $1", devolucion_id
        )

    # estimados: el definitivo se recalcula al aprobar (puede cerrar la venta y absorber centavos)
    valor = await monto_devolucion(conn, venta["id"], devolucion_id, cierra_la_venta=False)
    cambio = con_iva(await subtotal_cambio(conn, devolucion_id)) if tipo == "INTERCAMBIO" else Decimal("0")
    await conn.execute(
        "UPDATE devolucion SET monto_devuelto = $2, monto_cambio = $3 WHERE id = $1",
        devolucion_id,
        valor,
        cambio,
    )
    await registrar_auditoria(
        conn,
        usuario_id=usuario_id,
        entidad="devolucion",
        entidad_id=devolucion_id,
        accion="CREAR",
        datos_despues={
            "venta": venta["numero"],
            "tipo": tipo,
            "origen": origen,
            "motivo_tipo": motivo_tipo,
            "motivo": motivo.strip(),
            "lineas": {str(k): v for k, v in pedidas.items()},
            "monto_estimado": valor,
            "monto_cambio": cambio,
        },
    )
    return devolucion_id


def texto_diferencia(diferencia: Decimal) -> str:
    if diferencia > 0:
        return f"Pagas la diferencia de Bs {diferencia:.2f} en caja."
    if diferencia < 0:
        return f"Te devolvemos Bs {-diferencia:.2f} de diferencia."
    return "No hay diferencia de precio."
