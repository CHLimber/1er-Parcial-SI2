"""Devoluciones de ventas (objetivo 11 de la consigna, PENDIENTES 2.7).

Flujo en dos pasos, los dos del personal de la sucursal (ENCARGADO o ADMIN):
  1. Registrar (POST /devoluciones): sobre una venta PAGADA o ENTREGADA de la sucursal, se
     eligen lineas de venta_detalle y cantidades. Nace SOLICITADA y NO mueve stock.
  2. Resolver: aprobar (POST /{id}/aprobar) o rechazar (POST /{id}/rechazar, con motivo).
     Aprobar solo cambia devolucion.estado; el trigger tg_devolucion_stock (db/02_logica.sql)
     reingresa cada linea con fn_mover_inventario tipo DEVOLUCION y deja el kardex, mismo
     patron que tg_confirmar_recepcion. Este modulo nunca toca inventario.

Reglas de negocio:
  - Tope por linea: no se devuelve mas de lo vendido. Al REGISTRAR se descuenta lo ya
    APROBADO y tambien lo que esta en tramite (SOLICITADA), para que dos solicitudes
    pendientes no sumen mas de lo vendido; al APROBAR la base vuelve a verificar contra lo
    aprobado, con la venta bloqueada (FOR UPDATE), asi dos aprobaciones simultaneas no se
    pisan. Exceso -> 409.
  - Monto a reintegrar: se prorratea lo que la clienta pago POR LA MERCADERIA
    (venta.total - venta.costo_envio, es decir, ya con el descuento de la promo y el IVA)
    en proporcion al subtotal de lista de cada linea:
        monto = sum(cantidad * subtotal_linea / cantidad_linea) * (total - envio) / sum(subtotales)
    Asi un descuento global de la venta se reparte parejo entre todas las prendas y el IVA
    cobrado se devuelve. El costo de envio NO se devuelve: el servicio de delivery se presto.
    La devolucion que completa la venta (ya no queda ninguna unidad sin devolver) se lleva el
    resto exacto (total - envio - lo ya devuelto) para que los centavos de redondeo cierren.
    El monto se guarda al registrar como estimado y se recalcula al aprobar.
  - Pago: si la devolucion aprobada completa la venta, los pagos APROBADO de la venta pasan a
    REEMBOLSADO. En una devolucion parcial el pago queda APROBADO (el enum no tiene un estado
    "reembolsado en parte") y lo reintegrado queda en devolucion.monto_devuelto. La venta no
    cambia de estado (sigue PAGADA/ENTREGADA: la venta existio). El reintegro real del dinero
    (efectivo en caja, refund en Stripe) se hace fuera del sistema; aca queda registrado.
  - Sucursal: la devolucion se registra y el stock reingresa en la sucursal de la venta.
  - La clienta recibe una notificacion (tipo VENTA, entidad VENTA) al aprobar o rechazar. Las
    ventas POS sin clienta identificada (venta.usuario_id NULL) no notifican a nadie.
"""

from decimal import ROUND_HALF_UP, Decimal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.auditoria import registrar_auditoria
from app.core.db import get_connection
from app.core.deps import requiere_permiso
from app.modules.devoluciones.schemas import (
    DetalleDevolucionOut,
    DevolucionDetalleOut,
    DevolucionIn,
    DevolucionOut,
    LineaVentaOut,
    RechazoIn,
    VentaDevolvibleOut,
)

router = APIRouter(prefix="/devoluciones", tags=["devoluciones"])

puede_ver = requiere_permiso("devoluciones.leer", "devoluciones.crear", "devoluciones.actualizar")
puede_crear = requiere_permiso("devoluciones.crear")
puede_resolver = requiere_permiso("devoluciones.actualizar")

CENTAVO = Decimal("0.01")
ESTADOS_VENTA_DEVOLVIBLE = ("PAGADA", "ENTREGADA")

SELECT_DEVOLUCION = """
SELECT d.id, d.venta_id, v.numero AS venta_numero, v.total AS venta_total,
       d.sucursal_id, s.nombre AS sucursal,
       (cli.nombre || ' ' || cli.apellido) AS cliente,
       d.motivo, d.monto_devuelto, d.estado, d.fecha,
       (reg.nombre || ' ' || reg.apellido) AS registrada_por,
       (res.nombre || ' ' || res.apellido) AS resuelta_por,
       d.resuelta_en, d.motivo_rechazo,
       (SELECT COUNT(*) FROM devolucion_detalle dd WHERE dd.devolucion_id = d.id) AS lineas,
       (SELECT COALESCE(SUM(dd.cantidad), 0) FROM devolucion_detalle dd
         WHERE dd.devolucion_id = d.id) AS unidades
FROM devolucion d
JOIN venta v          ON v.id = d.venta_id
JOIN sucursal s       ON s.id = d.sucursal_id
LEFT JOIN usuario cli ON cli.id = v.usuario_id
LEFT JOIN usuario reg ON reg.id = d.usuario_id
LEFT JOIN usuario res ON res.id = d.resuelta_por_id
"""


def _sucursal_visible(staff: dict) -> UUID | None:
    """Mismo criterio que recepciones: un ADMIN (el que puede editar sucursales) ve todas; el
    resto solo la suya."""
    if "sucursales.actualizar" in staff["permisos"]:
        return None
    if staff["sucursal_id"] is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tu usuario no esta asignado a ninguna sucursal",
        )
    return staff["sucursal_id"]


def _exigir_alcance(staff: dict, sucursal_id: UUID, que: str) -> None:
    limite = _sucursal_visible(staff)
    if limite is not None and sucursal_id != limite:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=f"{que} es de otra sucursal")


# ---------------------------------------------------------------------
#  CALCULO DEL MONTO
# ---------------------------------------------------------------------


async def _base_venta(conn: asyncpg.Connection, venta_id: UUID) -> tuple[Decimal, Decimal]:
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


def _prorratear(bruto: Decimal, mercaderia: Decimal, suma_lineas: Decimal) -> Decimal:
    if suma_lineas <= 0:
        return Decimal("0.00")
    return (bruto * mercaderia / suma_lineas).quantize(CENTAVO, rounding=ROUND_HALF_UP)


async def _monto_devolucion(
    conn: asyncpg.Connection, venta_id: UUID, devolucion_id: UUID, cierra_la_venta: bool
) -> Decimal:
    mercaderia, suma_lineas = await _base_venta(conn, venta_id)
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
    return _prorratear(bruto, mercaderia, suma_lineas)


# ---------------------------------------------------------------------
#  LECTURA
# ---------------------------------------------------------------------


async def _lineas_de_venta(conn: asyncpg.Connection, venta_id: UUID) -> list[asyncpg.Record]:
    return await conn.fetch(
        """
        SELECT vd.id AS venta_detalle_id, vd.variante_id, pv.sku, pr.nombre AS producto,
               t.codigo AS talla, c.nombre AS color,
               vd.cantidad AS cantidad_vendida, vd.precio_unitario, vd.subtotal,
               COALESCE(SUM(dd.cantidad) FILTER (WHERE dv.estado = 'APROBADA'), 0)::int AS devuelta,
               COALESCE(SUM(dd.cantidad) FILTER (WHERE dv.estado = 'SOLICITADA'), 0)::int AS en_tramite
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


async def _obtener(conn: asyncpg.Connection, devolucion_id: UUID, staff: dict) -> DevolucionOut:
    fila = await conn.fetchrow(SELECT_DEVOLUCION + "WHERE d.id = $1", devolucion_id)
    if fila is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Devolucion no encontrada")
    _exigir_alcance(staff, fila["sucursal_id"], "Esa devolucion")
    return DevolucionOut(**dict(fila))


async def _con_detalle(
    conn: asyncpg.Connection, devolucion_id: UUID, staff: dict
) -> DevolucionDetalleOut:
    cabecera = await _obtener(conn, devolucion_id, staff)
    filas = await conn.fetch(
        """
        SELECT dd.id, dd.venta_detalle_id, vd.variante_id, pv.sku, pr.nombre AS producto,
               t.codigo AS talla, c.nombre AS color, dd.cantidad,
               vd.cantidad AS cantidad_vendida, vd.precio_unitario
        FROM devolucion_detalle dd
        JOIN venta_detalle vd     ON vd.id = dd.venta_detalle_id
        JOIN producto_variante pv ON pv.id = vd.variante_id
        JOIN producto pr          ON pr.id = pv.producto_id
        JOIN talla t              ON t.id = pv.talla_id
        JOIN color c              ON c.id = pv.color_id
        WHERE dd.devolucion_id = $1
        ORDER BY pr.nombre, t.orden, c.nombre
        """,
        devolucion_id,
    )
    reembolsado = await conn.fetchval(
        "SELECT EXISTS (SELECT 1 FROM pago WHERE venta_id = $1 AND estado = 'REEMBOLSADO')",
        cabecera.venta_id,
    )
    return DevolucionDetalleOut(
        **cabecera.model_dump(),
        detalle=[DetalleDevolucionOut(**dict(f)) for f in filas],
        pago_reembolsado=reembolsado,
    )


@router.get("", response_model=list[DevolucionOut])
async def listar_devoluciones(
    estado: str | None = Query(default=None, pattern="^(SOLICITADA|APROBADA|RECHAZADA)$"),
    venta: str | None = Query(default=None, max_length=40, description="Numero de venta (parcial)"),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[DevolucionOut]:
    limite = _sucursal_visible(staff)
    filas = await conn.fetch(
        SELECT_DEVOLUCION
        + """
        WHERE ($1::uuid IS NULL OR d.sucursal_id = $1)
          AND ($2::text IS NULL OR d.estado::text = $2)
          AND ($3::text IS NULL OR v.numero ILIKE '%' || $3 || '%')
        ORDER BY d.fecha DESC
        LIMIT 200
        """,
        limite,
        estado,
        venta.strip() if venta else None,
    )
    return [DevolucionOut(**dict(fila)) for fila in filas]


@router.get("/venta", response_model=VentaDevolvibleOut)
async def buscar_venta(
    numero: str = Query(min_length=3, max_length=40, description="Numero de la venta (V-...)"),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> VentaDevolvibleOut:
    """La venta sobre la que se va a registrar la devolucion, con lo que queda por devolver
    de cada linea y cuanto se reintegra por unidad."""
    venta = await conn.fetchrow(
        """
        SELECT v.id AS venta_id, v.numero, v.fecha, v.estado, v.canal, v.sucursal_id,
               s.nombre AS sucursal, (cli.nombre || ' ' || cli.apellido) AS cliente,
               v.subtotal, v.descuento, v.costo_envio, v.total,
               (SELECT COALESCE(SUM(monto_devuelto), 0) FROM devolucion
                 WHERE venta_id = v.id AND estado = 'APROBADA') AS total_devuelto
        FROM venta v
        JOIN sucursal s       ON s.id = v.sucursal_id
        LEFT JOIN usuario cli ON cli.id = v.usuario_id
        WHERE upper(v.numero) = upper($1)
        """,
        numero.strip(),
    )
    if venta is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No existe una venta con ese numero")
    _exigir_alcance(staff, venta["sucursal_id"], "Esa venta")
    if venta["estado"] not in ESTADOS_VENTA_DEVOLVIBLE:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"La venta esta {venta['estado'].lower()}: solo se devuelve una venta pagada o entregada",
        )

    mercaderia, suma_lineas = await _base_venta(conn, venta["venta_id"])
    lineas = []
    for fila in await _lineas_de_venta(conn, venta["venta_id"]):
        datos = dict(fila)
        datos["devolvible"] = max(datos["cantidad_vendida"] - datos["devuelta"] - datos["en_tramite"], 0)
        datos["reembolso_unitario"] = _prorratear(
            datos["subtotal"] / datos["cantidad_vendida"], mercaderia, suma_lineas
        )
        lineas.append(LineaVentaOut(**datos))
    return VentaDevolvibleOut(**dict(venta), lineas=lineas)


@router.get("/{devolucion_id}", response_model=DevolucionDetalleOut)
async def obtener_devolucion(
    devolucion_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> DevolucionDetalleOut:
    return await _con_detalle(conn, devolucion_id, staff)


# ---------------------------------------------------------------------
#  REGISTRO
# ---------------------------------------------------------------------


@router.post("", response_model=DevolucionDetalleOut, status_code=status.HTTP_201_CREATED)
async def registrar_devolucion(
    body: DevolucionIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_crear),
) -> DevolucionDetalleOut:
    # la misma linea dos veces en el pedido se suma, como en recepciones
    pedidas: dict[UUID, int] = {}
    for linea in body.lineas:
        pedidas[linea.venta_detalle_id] = pedidas.get(linea.venta_detalle_id, 0) + linea.cantidad

    async with conn.transaction():
        # Se bloquea la venta: dos registros simultaneos sobre la misma venta se serializan y
        # el segundo ve lo que el primero dejo en tramite.
        venta = await conn.fetchrow(
            "SELECT id, sucursal_id, estado, numero FROM venta WHERE id = $1 FOR UPDATE",
            body.venta_id,
        )
        if venta is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Venta no encontrada")
        _exigir_alcance(staff, venta["sucursal_id"], "Esa venta")
        if venta["estado"] not in ESTADOS_VENTA_DEVOLVIBLE:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"La venta esta {venta['estado'].lower()}: solo se devuelve una venta pagada o entregada",
            )

        lineas = {f["venta_detalle_id"]: f for f in await _lineas_de_venta(conn, venta["id"])}
        for venta_detalle_id, cantidad in pedidas.items():
            linea = lineas.get(venta_detalle_id)
            if linea is None:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail="Una de las lineas no pertenece a esta venta",
                )
            disponible = linea["cantidad_vendida"] - linea["devuelta"] - linea["en_tramite"]
            if cantidad > disponible:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=(
                        f"{linea['producto']} ({linea['talla']} · {linea['color']}): se vendieron "
                        f"{linea['cantidad_vendida']}, ya se devolvieron {linea['devuelta']} y hay "
                        f"{linea['en_tramite']} en tramite; se pueden devolver {max(disponible, 0)}"
                    ),
                )

        devolucion_id = await conn.fetchval(
            """
            INSERT INTO devolucion (venta_id, sucursal_id, motivo, monto_devuelto, usuario_id)
            VALUES ($1, $2, $3, 0, $4)
            RETURNING id
            """,
            venta["id"],
            venta["sucursal_id"],
            body.motivo.strip(),
            staff["id"],
        )
        await conn.executemany(
            "INSERT INTO devolucion_detalle (devolucion_id, venta_detalle_id, cantidad) VALUES ($1, $2, $3)",
            [(devolucion_id, vd_id, cantidad) for vd_id, cantidad in pedidas.items()],
        )
        # estimado: el definitivo se recalcula al aprobar (puede cerrar la venta y absorber centavos)
        monto = await _monto_devolucion(conn, venta["id"], devolucion_id, cierra_la_venta=False)
        await conn.execute("UPDATE devolucion SET monto_devuelto = $2 WHERE id = $1", devolucion_id, monto)

        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="devolucion",
            entidad_id=devolucion_id,
            accion="CREAR",
            datos_despues={
                "venta": venta["numero"],
                "motivo": body.motivo.strip(),
                "lineas": {str(k): v for k, v in pedidas.items()},
                "monto_estimado": monto,
            },
        )

    return await _con_detalle(conn, devolucion_id, staff)


# ---------------------------------------------------------------------
#  RESOLUCION
# ---------------------------------------------------------------------


async def _bloquear_solicitada(conn: asyncpg.Connection, devolucion_id: UUID, staff: dict) -> asyncpg.Record:
    fila = await conn.fetchrow(
        """
        SELECT d.id, d.venta_id, d.sucursal_id, d.estado, d.monto_devuelto, v.numero AS venta_numero
        FROM devolucion d JOIN venta v ON v.id = d.venta_id
        WHERE d.id = $1
        FOR UPDATE OF d
        """,
        devolucion_id,
    )
    if fila is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Devolucion no encontrada")
    _exigir_alcance(staff, fila["sucursal_id"], "Esa devolucion")
    if fila["estado"] != "SOLICITADA":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"La devolucion ya esta {fila['estado'].lower()}",
        )
    return fila


@router.post("/{devolucion_id}/aprobar", response_model=DevolucionDetalleOut)
async def aprobar_devolucion(
    devolucion_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_resolver),
) -> DevolucionDetalleOut:
    """Punto sin retorno: el UPDATE del estado dispara tg_devolucion_stock, que reingresa el
    stock de cada linea (tipo DEVOLUCION) y vuelve a verificar el tope contra lo vendido."""
    try:
        async with conn.transaction():
            devolucion = await _bloquear_solicitada(conn, devolucion_id, staff)
            await conn.execute("SELECT 1 FROM venta WHERE id = $1 FOR UPDATE", devolucion["venta_id"])

            pendientes_despues = await conn.fetchval(
                """
                SELECT (SELECT COALESCE(SUM(cantidad), 0) FROM venta_detalle WHERE venta_id = $1)
                     - (SELECT COALESCE(SUM(dd.cantidad), 0)
                          FROM devolucion_detalle dd JOIN devolucion d ON d.id = dd.devolucion_id
                         WHERE d.venta_id = $1 AND (d.estado = 'APROBADA' OR d.id = $2))
                """,
                devolucion["venta_id"],
                devolucion_id,
            )
            cierra = pendientes_despues <= 0
            monto = await _monto_devolucion(conn, devolucion["venta_id"], devolucion_id, cierra)

            await conn.execute(
                """
                UPDATE devolucion
                   SET estado = 'APROBADA', monto_devuelto = $2,
                       resuelta_por_id = $3, resuelta_en = now()
                 WHERE id = $1
                """,
                devolucion_id,
                monto,
                staff["id"],
            )
            if cierra:
                await conn.execute(
                    "UPDATE pago SET estado = 'REEMBOLSADO' WHERE venta_id = $1 AND estado = 'APROBADO'",
                    devolucion["venta_id"],
                )

            await conn.execute(
                """
                INSERT INTO notificacion (usuario_id, tipo, titulo, mensaje, entidad_tipo, entidad_id)
                SELECT usuario_id, 'VENTA', 'Devolucion aprobada',
                       'Aprobamos la devolucion de tu compra ' || numero || '. Se te reintegran Bs '
                       || to_char($2::numeric, 'FM999999990.00') || '.',
                       'VENTA', id
                FROM venta WHERE id = $1 AND usuario_id IS NOT NULL
                """,
                devolucion["venta_id"],
                monto,
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="devolucion",
                entidad_id=devolucion_id,
                accion="ACTUALIZAR",
                datos_antes={"estado": "SOLICITADA", "monto_devuelto": devolucion["monto_devuelto"]},
                datos_despues={
                    "estado": "APROBADA",
                    "monto_devuelto": monto,
                    "venta_completa": cierra,
                },
            )
    except asyncpg.RaiseError as error:
        # tope de lo vendido (tg_devolucion_stock) o cualquier error de fn_mover_inventario
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(error))

    return await _con_detalle(conn, devolucion_id, staff)


@router.post("/{devolucion_id}/rechazar", response_model=DevolucionDetalleOut)
async def rechazar_devolucion(
    devolucion_id: UUID,
    body: RechazoIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_resolver),
) -> DevolucionDetalleOut:
    motivo = body.motivo.strip()
    async with conn.transaction():
        devolucion = await _bloquear_solicitada(conn, devolucion_id, staff)
        await conn.execute(
            """
            UPDATE devolucion
               SET estado = 'RECHAZADA', motivo_rechazo = $2,
                   resuelta_por_id = $3, resuelta_en = now()
             WHERE id = $1
            """,
            devolucion_id,
            motivo,
            staff["id"],
        )
        await conn.execute(
            """
            INSERT INTO notificacion (usuario_id, tipo, titulo, mensaje, entidad_tipo, entidad_id)
            SELECT usuario_id, 'VENTA', 'Devolucion rechazada',
                   'No pudimos aceptar la devolucion de tu compra ' || numero || ': ' || $2,
                   'VENTA', id
            FROM venta WHERE id = $1 AND usuario_id IS NOT NULL
            """,
            devolucion["venta_id"],
            motivo,
        )
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="devolucion",
            entidad_id=devolucion_id,
            accion="ACTUALIZAR",
            datos_antes={"estado": "SOLICITADA"},
            datos_despues={"estado": "RECHAZADA", "motivo_rechazo": motivo},
        )

    return await _con_detalle(conn, devolucion_id, staff)
