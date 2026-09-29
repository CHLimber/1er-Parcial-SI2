from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.db import get_connection
from app.core.deps import get_cajero_actual
from app.modules.caja.schemas import (
    AbrirSesionIn,
    ArqueoOut,
    CajaOut,
    CerrarSesionIn,
    EntregaOut,
    ItemPagoPendienteOut,
    PagoPorVerificarOut,
    PedidoPorRetirarOut,
    RechazarPagoIn,
    ResolucionPagoOut,
    SesionCajaOut,
    SesionCerradaOut,
    VarianteBusquedaOut,
)
from app.modules.pagos.servicio import confirmar_aprobado, confirmar_rechazado

router = APIRouter(prefix="/caja", tags=["caja"])


async def obtener_sesion_abierta(conn: asyncpg.Connection, empleado_id) -> asyncpg.Record | None:
    """La sesion ABIERTA del cajero, en cualquier caja. La usan tanto este router como
    /ventas/pos para exigir CU07 E1 (sesion de caja no abierta)."""
    return await conn.fetchrow(
        """
        SELECT sc.id, sc.caja_id, c.nombre AS caja_nombre, sc.abierta_en, sc.monto_inicial, sc.estado
        FROM sesion_caja sc
        JOIN caja c ON c.id = sc.caja_id
        WHERE sc.empleado_id = $1 AND sc.estado = 'ABIERTA'
        """,
        empleado_id,
    )


def _sesion_out(fila: asyncpg.Record) -> SesionCajaOut:
    return SesionCajaOut(
        id=fila["id"],
        caja_id=fila["caja_id"],
        caja_nombre=fila["caja_nombre"],
        abierta_en=fila["abierta_en"],
        monto_inicial=float(fila["monto_inicial"]),
        estado=fila["estado"],
    )


@router.get("/cajas", response_model=list[CajaOut])
async def listar_cajas(
    cajero: dict = Depends(get_cajero_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> list[CajaOut]:
    filas = await conn.fetch(
        """
        SELECT c.id, c.codigo, c.nombre,
               EXISTS(
                   SELECT 1 FROM sesion_caja sc WHERE sc.caja_id = c.id AND sc.estado = 'ABIERTA'
               ) AS tiene_sesion_abierta
        FROM caja c
        WHERE c.sucursal_id = $1 AND c.activa
        ORDER BY c.codigo
        """,
        cajero["sucursal_id"],
    )
    return [CajaOut(**dict(fila)) for fila in filas]


@router.get("/sesion-actual", response_model=SesionCajaOut | None)
async def sesion_actual(
    cajero: dict = Depends(get_cajero_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> SesionCajaOut | None:
    fila = await obtener_sesion_abierta(conn, cajero["usuario_id"])
    return _sesion_out(fila) if fila else None


@router.post("/abrir", response_model=SesionCajaOut, status_code=status.HTTP_201_CREATED)
async def abrir_sesion(
    body: AbrirSesionIn,
    cajero: dict = Depends(get_cajero_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> SesionCajaOut:
    existente = await obtener_sesion_abierta(conn, cajero["usuario_id"])
    if existente is not None:
        # idempotente: doble click o refresh no debe abrir una segunda sesion
        return _sesion_out(existente)

    caja = await conn.fetchrow(
        "SELECT id FROM caja WHERE id = $1 AND sucursal_id = $2 AND activa",
        body.caja_id,
        cajero["sucursal_id"],
    )
    if caja is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Caja no encontrada")

    try:
        fila = await conn.fetchrow(
            """
            INSERT INTO sesion_caja (caja_id, empleado_id, monto_inicial)
            VALUES ($1, $2, $3)
            RETURNING id, caja_id, abierta_en, monto_inicial, estado
            """,
            body.caja_id,
            cajero["usuario_id"],
            body.monto_inicial,
        )
    except asyncpg.UniqueViolationError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Esa caja ya tiene una sesion abierta por otro cajero",
        )

    return SesionCajaOut(
        id=fila["id"],
        caja_id=fila["caja_id"],
        caja_nombre=(await conn.fetchval("SELECT nombre FROM caja WHERE id = $1", fila["caja_id"])),
        abierta_en=fila["abierta_en"],
        monto_inicial=float(fila["monto_inicial"]),
        estado=fila["estado"],
    )


async def _calcular_arqueo(conn: asyncpg.Connection, sesion: asyncpg.Record) -> ArqueoOut:
    """Suma los pagos APROBADOS de las ventas atadas a esta sesion, agrupados por metodo. Solo
    para la vista previa (GET /arqueo): el cierre (POST /cerrar) ya no llama a esto, calcula
    monto_sistema con fn_total_efectivo_sesion() dentro del propio UPDATE para no dejar una
    ventana entre "leer" y "escribir" donde una venta nueva quede afuera del cierre.
    cantidad_ventas usa el mismo filtro (sesion + pago APROBADO) que por_metodo/total_ventas en
    una sola consulta -- contar TODAS las ventas de la sesion sin ese filtro las desalineaba.
    Un pago REEMBOLSADO por una devolucion tambien cuenta: se cobro en esta sesion; lo que se
    devolvio del cajon va aparte en devoluciones_efectivo. monto_sistema sale de la misma
    fn_total_efectivo_sesion que usa el cierre, para que la vista previa y el cierre coincidan."""
    filas = await conn.fetch(
        """
        SELECT p.metodo::text AS metodo, COALESCE(SUM(p.monto), 0) AS total,
               (SELECT COUNT(DISTINCT p2.venta_id)
                  FROM pago p2 JOIN venta v2 ON v2.id = p2.venta_id
                 WHERE v2.sesion_caja_id = $1
                   AND p2.estado IN ('APROBADO', 'REEMBOLSADO')) AS cantidad_ventas
        FROM pago p
        JOIN venta v ON v.id = p.venta_id
        WHERE v.sesion_caja_id = $1 AND p.estado IN ('APROBADO', 'REEMBOLSADO')
        GROUP BY p.metodo
        """,
        sesion["id"],
    )
    efectivo = await conn.fetchrow(
        """
        SELECT fn_total_efectivo_sesion($1) AS neto,
               (SELECT COALESCE(SUM(monto_devuelto), 0) FROM devolucion
                 WHERE sesion_caja_id = $1 AND estado = 'APROBADA'
                   AND reintegro_metodo = 'EFECTIVO') AS devuelto
        """,
        sesion["id"],
    )
    por_metodo = {fila["metodo"]: float(fila["total"]) for fila in filas}
    cantidad_ventas = filas[0]["cantidad_ventas"] if filas else 0
    monto_inicial = float(sesion["monto_inicial"])

    return ArqueoOut(
        sesion_id=sesion["id"],
        monto_inicial=monto_inicial,
        monto_sistema=monto_inicial + float(efectivo["neto"]),
        cantidad_ventas=cantidad_ventas,
        total_ventas=sum(por_metodo.values()),
        por_metodo=por_metodo,
        devoluciones_efectivo=float(efectivo["devuelto"]),
    )


@router.get("/arqueo", response_model=ArqueoOut)
async def arqueo_actual(
    cajero: dict = Depends(get_cajero_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> ArqueoOut:
    sesion = await obtener_sesion_abierta(conn, cajero["usuario_id"])
    if sesion is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="No tenes una sesion de caja abierta"
        )
    return await _calcular_arqueo(conn, sesion)


@router.post("/cerrar", response_model=SesionCerradaOut)
async def cerrar_sesion(
    body: CerrarSesionIn,
    cajero: dict = Depends(get_cajero_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> SesionCerradaOut:
    """CU07 (pendiente cerrado): una sesion ABIERTA quedaba abierta para siempre, bloqueando esa
    caja para otro cajero. El cierre deja monto_sistema (lo calculado) y monto_declarado (lo que
    el cajero conto), y `diferencia` sale sola porque es una columna GENERATED del esquema.
    monto_sistema llama a fn_total_efectivo_sesion() DENTRO del propio UPDATE (no con una
    lectura previa como GET /arqueo) para que no quede una venta de POS afuera del cierre si se
    registra justo entre "leer" el arqueo y "escribir" el cierre."""
    sesion = await obtener_sesion_abierta(conn, cajero["usuario_id"])
    if sesion is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="No tenes una sesion de caja abierta"
        )

    fila = await conn.fetchrow(
        """
        UPDATE sesion_caja sc
           SET estado = 'CERRADA',
               cerrada_en = now(),
               monto_sistema = sc.monto_inicial + fn_total_efectivo_sesion(sc.id),
               monto_declarado = $2
         WHERE sc.id = $1 AND sc.estado = 'ABIERTA'
        RETURNING id, caja_id, abierta_en, cerrada_en, monto_inicial,
                  monto_sistema, monto_declarado, diferencia, estado
        """,
        sesion["id"],
        body.monto_declarado,
    )
    if fila is None:
        # se cerro entre el chequeo y el UPDATE (doble click, dos pestanias)
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="La sesion ya esta cerrada")

    return SesionCerradaOut(**dict(fila), caja_nombre=sesion["caja_nombre"])


@router.get("/buscar-variante", response_model=VarianteBusquedaOut)
async def buscar_variante(
    codigo: str = Query(..., min_length=1, description="SKU o codigo de barras, match exacto"),
    cajero: dict = Depends(get_cajero_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> VarianteBusquedaOut:
    fila = await conn.fetchrow(
        """
        SELECT pv.id AS variante_id, pv.sku, p.nombre AS producto, t.codigo AS talla, c.nombre AS color,
               COALESCE(pv.precio_oferta, pv.precio, p.precio_base) AS precio,
               COALESCE(i.disponible, 0) AS disponible
        FROM producto_variante pv
        JOIN producto p ON p.id = pv.producto_id
        JOIN talla t    ON t.id = pv.talla_id
        JOIN color c    ON c.id = pv.color_id
        LEFT JOIN inventario i ON i.variante_id = pv.id AND i.sucursal_id = $2
        WHERE pv.activa AND (pv.sku ILIKE $1 OR pv.codigo_barras ILIKE $1)
        LIMIT 1
        """,
        codigo.strip(),
        cajero["sucursal_id"],
    )
    if fila is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No se encontro esa prenda")

    return VarianteBusquedaOut(
        variante_id=fila["variante_id"],
        sku=fila["sku"],
        producto=fila["producto"],
        talla=fila["talla"],
        color=fila["color"],
        precio=float(fila["precio"]),
        disponible=fila["disponible"],
    )


# ---------------------------------------------------------------------------------------------
# 2.19.1.b/c: pagos online que pasan por el cajero en vez de aprobarse solos.
#   - EFECTIVO en el checkout web/movil: queda PENDIENTE hasta que el cajero cobra (retiro en
#     tienda) o recibe lo que rinde el delivery externo (domicilio). Entra en el arqueo porque al
#     aprobarlo la venta se ata a la sesion de caja abierta (fn_total_efectivo_sesion).
#   - QR: la clienta solo informa "ya pague" (POST /pagos/qr/{venta_id}/informar); el cajero
#     verifica el deposito y aprueba o rechaza. No suma al cajon: no es efectivo.
# Stripe no pasa por aca: lo confirma su webhook firmado.
# ---------------------------------------------------------------------------------------------

# pago online que le toca verificar a la caja: EFECTIVO sin pasarela o pasarela QR
_FILTRO_VERIFICABLE = """
    v.canal IN ('WEB', 'MOVIL')
    AND (p.metodo = 'EFECTIVO' OR p.pasarela = 'QR')
"""


@router.get("/pagos-pendientes", response_model=list[PagoPorVerificarOut])
async def listar_pagos_pendientes(
    cajero: dict = Depends(get_cajero_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> list[PagoPorVerificarOut]:
    """Pedidos online de la sucursal del cajero con el pago PENDIENTE de verificacion. Primero
    los QR que la clienta ya informo (hay plata depositada esperando), despues por antiguedad."""
    filas = await conn.fetch(
        f"""
        SELECT p.id AS pago_id, v.id AS venta_id, v.numero, v.fecha, v.entrega::text AS entrega,
               v.total, v.costo_envio, v.subtotal, v.carrito_id,
               u.nombre || ' ' || u.apellido AS cliente, u.email AS cliente_email,
               CASE WHEN p.metodo = 'EFECTIVO' THEN 'EFECTIVO' ELSE 'QR' END AS metodo,
               p.informado_en, p.referencia_cliente,
               COALESCE((SELECT SUM(ci.precio_unitario * ci.cantidad)
                           FROM carrito_item ci WHERE ci.carrito_id = v.carrito_id), 0)
                   AS subtotal_carrito
        FROM pago p
        JOIN venta v   ON v.id = p.venta_id
        JOIN usuario u ON u.id = v.usuario_id
        WHERE v.sucursal_id = $1 AND v.estado = 'PENDIENTE' AND p.estado = 'PENDIENTE'
          AND {_FILTRO_VERIFICABLE}
        ORDER BY (p.informado_en IS NULL), v.fecha
        """,
        cajero["sucursal_id"],
    )
    if not filas:
        return []

    items = await conn.fetch(
        """
        SELECT ci.carrito_id, pv.sku, p.nombre AS producto, t.codigo AS talla,
               c.nombre AS color, ci.cantidad
        FROM carrito_item ci
        JOIN producto_variante pv ON pv.id = ci.variante_id
        JOIN producto p ON p.id = pv.producto_id
        JOIN talla t    ON t.id = pv.talla_id
        JOIN color c    ON c.id = pv.color_id
        WHERE ci.carrito_id = ANY($1::uuid[])
        ORDER BY p.nombre, t.codigo
        """,
        [fila["carrito_id"] for fila in filas],
    )
    items_por_carrito: dict = {}
    for item in items:
        items_por_carrito.setdefault(item["carrito_id"], []).append(
            ItemPagoPendienteOut(
                sku=item["sku"],
                producto=item["producto"],
                talla=item["talla"],
                color=item["color"],
                cantidad=item["cantidad"],
            )
        )

    return [
        PagoPorVerificarOut(
            pago_id=fila["pago_id"],
            venta_id=fila["venta_id"],
            numero=fila["numero"],
            fecha=fila["fecha"],
            cliente=fila["cliente"],
            cliente_email=fila["cliente_email"],
            metodo=fila["metodo"],
            entrega=fila["entrega"],
            total=float(fila["total"]),
            costo_envio=float(fila["costo_envio"]),
            informado_en=fila["informado_en"],
            referencia_cliente=fila["referencia_cliente"],
            carrito_modificado=fila["subtotal_carrito"] != fila["subtotal"],
            items=items_por_carrito.get(fila["carrito_id"], []),
        )
        for fila in filas
    ]


async def _bloquear_pago_verificable(
    conn: asyncpg.Connection, pago_id: UUID, sucursal_id: UUID
) -> tuple[asyncpg.Record, asyncpg.Record]:
    """Bloquea pago y venta (mismo orden que pagos/router.py::_procesar_evento, para no cruzarse
    en un deadlock con el webhook) y valida que sea un pago de esta sucursal que todavia espera
    al cajero. Debe llamarse dentro de una transaccion."""
    pago = await conn.fetchrow(
        f"""
        SELECT p.id, p.estado, p.metodo::text AS metodo, p.venta_id
        FROM pago p
        JOIN venta v ON v.id = p.venta_id
        WHERE p.id = $1 AND v.sucursal_id = $2 AND {_FILTRO_VERIFICABLE}
        FOR UPDATE OF p
        """,
        pago_id,
        sucursal_id,
    )
    if pago is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No hay un pago online de tu sucursal con ese id",
        )
    if pago["estado"] != "PENDIENTE":
        # idempotencia: doble click, dos cajeros a la vez, o la clienta abandono ese intento
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Ese pago ya fue resuelto ({pago['estado']})",
        )

    venta = await conn.fetchrow(
        """
        SELECT id, sucursal_id, carrito_id, reserva_id, promocion_id, numero, estado, subtotal
        FROM venta WHERE id = $1 FOR UPDATE
        """,
        pago["venta_id"],
    )
    if venta["estado"] != "PENDIENTE":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Ese pedido ya no esta pendiente ({venta['estado']})",
        )
    return pago, venta


@router.post("/pagos/{pago_id}/aprobar", response_model=ResolucionPagoOut)
async def aprobar_pago(
    pago_id: UUID,
    cajero: dict = Depends(get_cajero_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> ResolucionPagoOut:
    """El cajero confirma que cobro el efectivo o que el deposito QR esta en la cuenta. Recien
    aca se descuenta el stock y se emite el comprobante (confirmar_aprobado). Si el stock ya no
    alcanza, confirmar_aprobado anula la venta: el pago queda RECHAZADO si era efectivo (no se
    cobro) o REEMBOLSADO si era QR (la clienta ya deposito) -- la respuesta lo informa con 200,
    no es un error del cajero."""
    async with conn.transaction():
        pago, venta = await _bloquear_pago_verificable(conn, pago_id, cajero["sucursal_id"])

        carrito_actual = await conn.fetchval(
            """
            SELECT COALESCE(SUM(precio_unitario * cantidad), 0)
            FROM carrito_item WHERE carrito_id = $1
            """,
            venta["carrito_id"],
        )
        if carrito_actual != venta["subtotal"]:
            # confirmar_aprobado vuelca el carrito TAL COMO ESTA HOY: si la clienta lo cambio
            # despues del checkout se venderian otras prendas por el monto viejo
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    "La clienta modifico su carrito despues de hacer el pedido: el monto ya no "
                    "coincide. Rechazalo y pedile que vuelva a hacer el checkout."
                ),
            )

        if pago["metodo"] == "EFECTIVO":
            # la plata entra al cajon: la venta se ata a la sesion abierta para que la cuente
            # el arqueo y el cierre (fn_total_efectivo_sesion), igual que una venta de POS
            sesion = await obtener_sesion_abierta(conn, cajero["usuario_id"])
            if sesion is None:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Abri una sesion de caja antes de cobrar un pedido en efectivo",
                )
            await conn.execute(
                "UPDATE venta SET sesion_caja_id = $2 WHERE id = $1", venta["id"], sesion["id"]
            )

        resultado = await confirmar_aprobado(conn, pago["id"], dict(venta))
        await conn.execute(
            "UPDATE pago SET verificado_por_id = $2 WHERE id = $1",
            pago["id"],
            cajero["usuario_id"],
        )

    return ResolucionPagoOut(
        pago_id=pago["id"], venta_id=venta["id"], numero=venta["numero"], **resultado
    )


@router.post("/pagos/{pago_id}/rechazar", response_model=ResolucionPagoOut)
async def rechazar_pago(
    pago_id: UUID,
    body: RechazarPagoIn,
    cajero: dict = Depends(get_cajero_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> ResolucionPagoOut:
    """QR: el deposito no aparece. EFECTIVO: la clienta no se presento a pagar, o el delivery
    no pudo cobrar. La venta se anula sin tocar stock (nunca se desconto) y la clienta recibe
    una notificacion con el motivo."""
    motivo = body.motivo.strip() if body.motivo and body.motivo.strip() else None
    async with conn.transaction():
        pago, venta = await _bloquear_pago_verificable(conn, pago_id, cajero["sucursal_id"])

        if pago["metodo"] == "EFECTIVO":
            texto = "Anulamos tu pedido {numero}: no se concreto el cobro en efectivo."
        else:
            texto = (
                "No pudimos verificar el deposito QR del pedido {numero}, asi que lo anulamos. "
                "Si ya pagaste, acercate a la sucursal con tu comprobante."
            )
        if motivo:
            texto += f" Motivo: {motivo}."
        texto += " Tu carrito sigue disponible para volver a intentarlo."

        resultado = await confirmar_rechazado(conn, pago["id"], dict(venta), mensaje_cliente=texto)
        await conn.execute(
            "UPDATE pago SET verificado_por_id = $2 WHERE id = $1",
            pago["id"],
            cajero["usuario_id"],
        )

    return ResolucionPagoOut(
        pago_id=pago["id"], venta_id=venta["id"], numero=venta["numero"], **resultado
    )


# ---------------------------------------------------------------------------------------------
# Pedidos online con retiro en tienda: quedan PAGADA hasta que la clienta los pasa a buscar y
# el personal de caja los entrega (-> ENTREGADA). Las ventas de mostrador (POS y reservas
# atendidas en el vestidor) ya nacen ENTREGADA: la clienta se lleva la prenda en el momento.
# Los de DOMICILIO no pasan por aca: los lleva el delivery externo (PENDIENTES 2.17).
# ---------------------------------------------------------------------------------------------


@router.get("/pedidos-por-retirar", response_model=list[PedidoPorRetirarOut])
async def listar_pedidos_por_retirar(
    cajero: dict = Depends(get_cajero_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> list[PedidoPorRetirarOut]:
    filas = await conn.fetch(
        """
        SELECT v.id AS venta_id, v.numero, v.fecha, v.total,
               u.nombre || ' ' || u.apellido AS cliente, u.email AS cliente_email
        FROM venta v
        JOIN usuario u ON u.id = v.usuario_id
        WHERE v.sucursal_id = $1 AND v.estado = 'PAGADA'
          AND v.canal IN ('WEB', 'MOVIL') AND v.entrega = 'RETIRO_SUCURSAL'
        ORDER BY v.fecha
        """,
        cajero["sucursal_id"],
    )
    if not filas:
        return []

    items = await conn.fetch(
        """
        SELECT vd.venta_id, pv.sku, p.nombre AS producto, t.codigo AS talla,
               c.nombre AS color, vd.cantidad
        FROM venta_detalle vd
        JOIN producto_variante pv ON pv.id = vd.variante_id
        JOIN producto p ON p.id = pv.producto_id
        JOIN talla t    ON t.id = pv.talla_id
        JOIN color c    ON c.id = pv.color_id
        WHERE vd.venta_id = ANY($1::uuid[])
        ORDER BY p.nombre, t.codigo
        """,
        [fila["venta_id"] for fila in filas],
    )
    items_por_venta: dict = {}
    for item in items:
        items_por_venta.setdefault(item["venta_id"], []).append(
            ItemPagoPendienteOut(
                sku=item["sku"],
                producto=item["producto"],
                talla=item["talla"],
                color=item["color"],
                cantidad=item["cantidad"],
            )
        )

    return [
        PedidoPorRetirarOut(
            venta_id=fila["venta_id"],
            numero=fila["numero"],
            fecha=fila["fecha"],
            cliente=fila["cliente"],
            cliente_email=fila["cliente_email"],
            total=float(fila["total"]),
            items=items_por_venta.get(fila["venta_id"], []),
        )
        for fila in filas
    ]


@router.post("/pedidos/{venta_id}/entregar", response_model=EntregaOut)
async def entregar_pedido(
    venta_id: UUID,
    cajero: dict = Depends(get_cajero_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> EntregaOut:
    """La clienta paso a retirar su pedido online: PAGADA -> ENTREGADA."""
    async with conn.transaction():
        venta = await conn.fetchrow(
            """
            SELECT id, numero, estado::text AS estado, entrega::text AS entrega,
                   canal::text AS canal
            FROM venta
            WHERE id = $1 AND sucursal_id = $2
            FOR UPDATE
            """,
            venta_id,
            cajero["sucursal_id"],
        )
        if venta is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="No hay un pedido de tu sucursal con ese id",
            )
        if venta["entrega"] != "RETIRO_SUCURSAL" or venta["canal"] not in ("WEB", "MOVIL"):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Solo se entregan en caja los pedidos online con retiro en tienda",
            )
        if venta["estado"] != "PAGADA":
            # idempotencia: doble click (ENTREGADA), o todavia sin pagar / anulado
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"El pedido {venta['numero']} esta {venta['estado'].lower()}: "
                "solo se entrega un pedido pagado",
            )

        await conn.execute("UPDATE venta SET estado = 'ENTREGADA' WHERE id = $1", venta_id)
        await conn.execute(
            """
            INSERT INTO notificacion (usuario_id, tipo, titulo, mensaje, entidad_tipo, entidad_id)
            SELECT usuario_id, 'VENTA', 'Pedido entregado',
                   'Retiraste tu pedido ' || numero || '. Gracias por comprar en FashionStore.',
                   'VENTA', id
            FROM venta WHERE id = $1 AND usuario_id IS NOT NULL
            """,
            venta_id,
        )

    return EntregaOut(
        venta_id=venta_id,
        numero=venta["numero"],
        venta_estado="ENTREGADA",
        mensaje=f"Pedido {venta['numero']} entregado",
    )
