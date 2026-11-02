"""Devoluciones e intercambios de ventas, lado del personal (ENCARGADO, CAJERO o ADMIN).

Dos tipos, con las mismas reglas (PENDIENTES 10):
  - DEVOLUCION (motivo DEFECTO, NO_GUSTO u OTRO): vuelve la prenda y vuelve la plata.
  - INTERCAMBIO (motivo TALLA o COLOR): vuelve la prenda y la clienta se lleva otra talla/color de
    la misma prenda. Lo devuelto queda como credito; si lo nuevo cuesta mas paga la diferencia en
    caja, si cuesta menos se le devuelve lo que sobra. Antes un cambio se aprobaba como devolucion
    (reintegraba todo, Stripe incluido) y la prenda nueva se cobraba aparte: eso se termino.

Dos origenes:
  - CAJA: la clienta esta en la sucursal. Registrar (POST /devoluciones) -> SOLICITADA, y concretar
    (POST /{id}/aprobar) o rechazar.
  - ONLINE: la clienta la pide desde Mis compras (cliente_router.py) con fecha y hora de visita,
    como una reserva. El personal la acepta (POST /{id}/confirmar -> CONFIRMADA) o la rechaza, y
    cuando la clienta llega se concreta en caja con el mismo POST /{id}/aprobar. Vence en expira_en
    (fn_expirar_devoluciones) y la clienta puede cancelarla.

Reglas (las comunes viven en servicio.py):
  - Plazo: 3 dias desde la venta (configuracion devolucion_plazo_dias / cambio_plazo_dias).
  - Una sola devolucion/intercambio por compra (las rechazadas/canceladas/expiradas no cuentan) y
    hasta configuracion.devolucion_max_unidades prendas (3). La venta que nace de un intercambio no
    se devuelve de nuevo.
  - Condiciones de la prenda: TALLA, COLOR, NO_GUSTO y OTRO exigen etiqueta, sin uso y comprobante;
    DEFECTO solo el comprobante. En una solicitud online se verifican al concretar.
  - Stock: aprobar solo cambia el estado y tg_devolucion_stock reingresa lo devuelto; las prendas
    pedidas a cambio se comprometen al registrar y el trigger libera ese compromiso al cerrar. La
    venta del intercambio (venta_cambio_id) la arma este modulo al aprobar y su venta_detalle
    descuenta el stock como cualquier venta.
  - Reintegro (por donde entro la plata): STRIPE -> reembolso parcial por la API (si Stripe lo
    rechaza se deshace todo, 502); EFECTIVO y QR -> en efectivo desde el cajon de la sesion de caja
    abierta de quien aprueba (fn_total_efectivo_sesion lo resta del arqueo); TARJETA/TRANSFERENCIA
    -> fuera del sistema, queda registrado.
  - La clienta recibe una notificacion en cada paso y, al aprobarse, el comprobante por correo
    (job de avisos, app/core/comprobante_devolucion.py).
  - Multi-tenant: lo de otra empresa responde 404; el personal de sucursal ve solo la suya (403).
"""

from datetime import date
from decimal import Decimal
from uuid import UUID, uuid4

import asyncpg
import stripe
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.auditoria import registrar_auditoria
from app.core.db import get_connection
from app.core.deps import requiere_permiso
from app.core.tenant import (
    empresa_de,
    empresa_de_sucursal,
    exigir_variantes,
    no_encontrado,
    sucursal_visible,
)
from app.modules.operacion_comercial.caja.router import obtener_sesion_abierta
from app.modules.operacion_comercial.devoluciones import servicio
from app.modules.operacion_comercial.devoluciones.schemas import (
    AprobacionIn,
    CambioMesOut,
    CambiosMesOut,
    DetalleDevolucionOut,
    DevolucionDetalleOut,
    DevolucionIn,
    DevolucionOut,
    LineaVentaOut,
    NotaDevolucionOut,
    RechazoIn,
    VarianteCambioOut,
    VentaDevolvibleOut,
)
from app.modules.operacion_comercial.devoluciones.servicio import (  # noqa: F401 (los tests los usan)
    condiciones_faltantes,
    validar_variante_cambio,
)
from app.modules.operacion_comercial.pagos.servicio import reembolsar_parcial_stripe

router = APIRouter(prefix="/devoluciones", tags=["devoluciones"])

puede_ver = requiere_permiso("devoluciones.leer", "devoluciones.crear", "devoluciones.actualizar")
puede_crear = requiere_permiso("devoluciones.crear")
puede_resolver = requiere_permiso("devoluciones.actualizar")

_metodo_reintegro = servicio.metodo_reintegro  # nombre historico, lo usan los tests

# texto de la notificacion a la clienta segun como vuelve la plata
_COMO_SE_REINTEGRA = {
    "STRIPE": " a tu tarjeta (puede tardar unos dias en verse)",
    "EFECTIVO": " en efectivo en la sucursal",
    "QR": " en efectivo en la sucursal",
}

SELECT_DEVOLUCION = """
SELECT d.id, d.numero, d.tipo, d.origen, d.venta_id, v.numero AS venta_numero,
       v.total AS venta_total, d.sucursal_id, s.nombre AS sucursal,
       (cli.nombre || ' ' || cli.apellido) AS cliente,
       d.motivo_tipo::text AS motivo_tipo, d.motivo,
       d.con_etiqueta, d.sin_uso, d.con_comprobante,
       d.monto_devuelto, d.monto_cambio,
       CASE WHEN d.tipo = 'INTERCAMBIO' THEN d.monto_cambio - d.monto_devuelto ELSE 0 END AS diferencia,
       d.monto_reintegrado, d.diferencia_cobrada, d.diferencia_metodo,
       d.estado::text AS estado, d.fecha, d.fecha_visita, d.hora_visita, d.expira_en,
       (reg.nombre || ' ' || reg.apellido) AS registrada_por,
       (res.nombre || ' ' || res.apellido) AS resuelta_por,
       d.resuelta_en, d.motivo_rechazo,
       d.reintegro_metodo, d.reintegro_referencia,
       d.venta_cambio_id, vc.numero AS venta_cambio_numero,
       (SELECT COUNT(*) FROM devolucion_detalle dd WHERE dd.devolucion_id = d.id) AS lineas,
       (SELECT COALESCE(SUM(dd.cantidad), 0) FROM devolucion_detalle dd
         WHERE dd.devolucion_id = d.id) AS unidades
FROM devolucion d
JOIN venta v          ON v.id = d.venta_id
JOIN sucursal s       ON s.id = d.sucursal_id
LEFT JOIN usuario cli ON cli.id = v.usuario_id
LEFT JOIN usuario reg ON reg.id = d.usuario_id
LEFT JOIN usuario res ON res.id = d.resuelta_por_id
LEFT JOIN venta vc    ON vc.id = d.venta_cambio_id
"""

SELECT_DETALLE = """
SELECT dd.id, dd.venta_detalle_id, vd.variante_id, pv.sku, pr.nombre AS producto,
       t.codigo AS talla, c.nombre AS color, dd.cantidad,
       vd.cantidad AS cantidad_vendida, vd.precio_unitario,
       dd.variante_solicitada_id, ts.codigo AS talla_solicitada,
       cs.nombre AS color_solicitado, ps.sku AS sku_solicitado, dd.precio_solicitado
FROM devolucion_detalle dd
JOIN venta_detalle vd     ON vd.id = dd.venta_detalle_id
JOIN producto_variante pv ON pv.id = vd.variante_id
JOIN producto pr          ON pr.id = pv.producto_id
JOIN talla t              ON t.id = pv.talla_id
JOIN color c              ON c.id = pv.color_id
LEFT JOIN producto_variante ps ON ps.id = dd.variante_solicitada_id
LEFT JOIN talla ts             ON ts.id = ps.talla_id
LEFT JOIN color cs             ON cs.id = ps.color_id
WHERE dd.devolucion_id = $1
ORDER BY pr.nombre, t.orden, c.nombre
"""


async def _exigir_alcance(
    conn: asyncpg.Connection, staff: dict, sucursal_id: UUID, que: str
) -> None:
    """404 si la sucursal es de otra empresa; 403 si es de la empresa pero no la del usuario."""
    if await empresa_de_sucursal(conn, sucursal_id) != empresa_de(staff):
        raise no_encontrado(f"{que} no existe")
    limite = sucursal_visible(staff)
    if limite is not None and sucursal_id != limite:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=f"{que} es de otra sucursal")


async def armar_detalle(conn: asyncpg.Connection, devolucion_id: UUID) -> DevolucionDetalleOut | None:
    """La devolucion con su detalle, sin chequeo de alcance (lo hace quien llama)."""
    cabecera = await conn.fetchrow(SELECT_DEVOLUCION + "WHERE d.id = $1", devolucion_id)
    if cabecera is None:
        return None
    filas = await conn.fetch(SELECT_DETALLE, devolucion_id)
    reembolsado = await conn.fetchval(
        "SELECT EXISTS (SELECT 1 FROM pago WHERE venta_id = $1 AND estado = 'REEMBOLSADO')",
        cabecera["venta_id"],
    )
    return DevolucionDetalleOut(
        **dict(cabecera),
        detalle=[DetalleDevolucionOut(**dict(f)) for f in filas],
        pago_reembolsado=bool(reembolsado),
    )


async def _con_detalle(
    conn: asyncpg.Connection, devolucion_id: UUID, staff: dict
) -> DevolucionDetalleOut:
    devolucion = await armar_detalle(conn, devolucion_id)
    if devolucion is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Devolucion no encontrada")
    await _exigir_alcance(conn, staff, devolucion.sucursal_id, "Esa devolucion")
    return devolucion


# ---------------------------------------------------------------------
#  LECTURA
# ---------------------------------------------------------------------


@router.get("", response_model=list[DevolucionOut])
async def listar_devoluciones(
    tipo: str | None = Query(default=None, pattern="^(DEVOLUCION|INTERCAMBIO)$"),
    origen: str | None = Query(default=None, pattern="^(CAJA|ONLINE)$"),
    estado: str | None = Query(
        default=None, pattern="^(SOLICITADA|CONFIRMADA|APROBADA|RECHAZADA|CANCELADA|EXPIRADA)$"
    ),
    venta: str | None = Query(
        default=None, max_length=40, description="Numero de venta o de nota (parcial)"
    ),
    motivo_tipo: str | None = Query(default=None, pattern="^(TALLA|COLOR|DEFECTO|NO_GUSTO|OTRO)$"),
    desde: date | None = Query(default=None, description="Fecha de la devolucion, desde (inclusive)"),
    hasta: date | None = Query(default=None, description="Fecha de la devolucion, hasta (inclusive)"),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[DevolucionOut]:
    limite = sucursal_visible(staff)
    filas = await conn.fetch(
        SELECT_DEVOLUCION
        + """
        WHERE s.empresa_id = $7
          AND ($1::uuid IS NULL OR d.sucursal_id = $1)
          AND ($2::text IS NULL OR d.estado::text = $2)
          AND ($3::text IS NULL OR v.numero ILIKE '%' || $3 || '%' OR d.numero ILIKE '%' || $3 || '%')
          AND ($4::text IS NULL OR d.motivo_tipo::text = $4)
          AND ($5::date IS NULL OR d.fecha >= $5::date)
          AND ($6::date IS NULL OR d.fecha < $6::date + 1)
          AND ($8::text IS NULL OR d.tipo = $8)
          AND ($9::text IS NULL OR d.origen = $9)
        -- lo que espera al personal primero (solicitudes online por aceptar o por concretar)
        ORDER BY (d.estado IN ('SOLICITADA', 'CONFIRMADA')) DESC, d.fecha DESC
        LIMIT 200
        """,
        limite,
        estado,
        venta.strip() if venta else None,
        motivo_tipo,
        desde,
        hasta,
        empresa_de(staff),
        tipo,
        origen,
    )
    return [DevolucionOut(**dict(fila)) for fila in filas]


@router.get("/pendientes", response_model=dict)
async def contar_pendientes(
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> dict:
    """Cuantas solicitudes esperan al personal en su sucursal: por aceptar (SOLICITADA online) y
    por concretar en caja (CONFIRMADA). Lo muestra la pantalla de Caja."""
    fila = await conn.fetchrow(
        """
        SELECT COUNT(*) FILTER (WHERE d.estado = 'SOLICITADA' AND d.origen = 'ONLINE') AS por_aceptar,
               COUNT(*) FILTER (WHERE d.estado = 'CONFIRMADA') AS por_concretar
        FROM devolucion d JOIN sucursal s ON s.id = d.sucursal_id
        WHERE s.empresa_id = $1 AND ($2::uuid IS NULL OR d.sucursal_id = $2)
          AND d.estado IN ('SOLICITADA', 'CONFIRMADA')
        """,
        empresa_de(staff),
        sucursal_visible(staff),
    )
    return {"por_aceptar": fila["por_aceptar"] or 0, "por_concretar": fila["por_concretar"] or 0}


@router.get("/venta", response_model=VentaDevolvibleOut)
async def buscar_venta(
    numero: str = Query(min_length=3, max_length=40, description="Numero de la venta (V-...)"),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> VentaDevolvibleOut:
    """La venta sobre la que se va a registrar la devolucion, con lo que queda por devolver
    de cada linea y cuanto vale cada unidad."""
    venta = await conn.fetchrow(
        """
        SELECT v.id AS venta_id, v.numero, v.fecha, v.estado::text AS estado, v.canal::text AS canal,
               v.sucursal_id, s.nombre AS sucursal, (cli.nombre || ' ' || cli.apellido) AS cliente,
               v.subtotal, v.descuento, v.costo_envio, v.total,
               (SELECT COALESCE(SUM(monto_devuelto), 0) FROM devolucion
                 WHERE venta_id = v.id AND estado = 'APROBADA') AS total_devuelto,
               v.fecha + make_interval(days => $2) AS plazo_vence_en,
               now() > v.fecha + make_interval(days => $2) AS fuera_de_plazo,
               v.fecha + make_interval(days => $3) AS cambio_vence_en,
               now() > v.fecha + make_interval(days => $3) AS fuera_de_plazo_cambio
        FROM venta v
        JOIN sucursal s       ON s.id = v.sucursal_id
        LEFT JOIN usuario cli ON cli.id = v.usuario_id
        WHERE upper(v.numero) = upper($1) AND s.empresa_id = $4
        """,
        numero.strip(),
        await servicio.plazo_dias(conn, "DEVOLUCION"),
        await servicio.plazo_dias(conn, "INTERCAMBIO"),
        empresa_de(staff),
    )
    if venta is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No existe una venta con ese numero")
    await _exigir_alcance(conn, staff, venta["sucursal_id"], "Esa venta")
    if venta["estado"] not in servicio.ESTADOS_VENTA_DEVOLVIBLE:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"La venta esta {venta['estado'].lower()}: solo se devuelve una venta pagada o entregada",
        )

    mercaderia, suma_lineas = await servicio.base_venta(conn, venta["venta_id"])
    lineas = []
    for fila in await servicio.lineas_de_venta(conn, venta["venta_id"]):
        datos = dict(fila)
        datos["devolvible"] = max(datos["cantidad_vendida"] - datos["devuelta"] - datos["en_tramite"], 0)
        datos["reembolso_unitario"] = servicio.prorratear(
            datos["subtotal"] / datos["cantidad_vendida"], mercaderia, suma_lineas
        )
        lineas.append(LineaVentaOut(**datos))
    return VentaDevolvibleOut(
        **dict(venta),
        reintegro_metodo=servicio.metodo_reintegro(await servicio.pago_de_venta(conn, venta["venta_id"])),
        max_unidades=await servicio.max_unidades(conn),
        solicitud_vigente=await servicio.solicitud_vigente(conn, venta["venta_id"]),
        es_venta_de_cambio=await servicio.es_venta_de_cambio(conn, venta["venta_id"]),
        lineas=lineas,
    )


def rango_del_mes(anio: int, mes: int) -> tuple[date, date]:
    """[primer dia del mes, primer dia del mes siguiente)."""
    siguiente = date(anio + 1, 1, 1) if mes == 12 else date(anio, mes + 1, 1)
    return date(anio, mes, 1), siguiente


@router.get("/variantes-cambio", response_model=list[VarianteCambioOut])
async def variantes_para_cambio(
    variante_id: UUID,
    sucursal_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[VarianteCambioOut]:
    """Las otras tallas/colores de la misma prenda con su precio y disponible en la sucursal, para
    elegir que se lleva la clienta en un intercambio."""
    await _exigir_alcance(conn, staff, sucursal_id, "Esa sucursal")
    await exigir_variantes(conn, [variante_id], empresa_de(staff))
    filas = await servicio.variantes_de_cambio(conn, variante_id, sucursal_id)
    return [VarianteCambioOut(**dict(f)) for f in filas]


@router.get("/cambios-mes", response_model=CambiosMesOut)
async def cambios_del_mes(
    anio: int | None = Query(default=None, ge=2020, le=2100),
    mes: int | None = Query(default=None, ge=1, le=12),
    incluir_otros_motivos: bool = Query(
        default=False, description="False: solo intercambios (TALLA/COLOR). True: toda devolucion"
    ),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> CambiosMesOut:
    """Que prendas solicitaron cambio en el mes (PENDIENTES 5.10). Agrupa por prenda, talla/
    color original y lo que se pidio a cambio; por defecto el mes en curso. El personal de
    sucursal ve la suya, el ADMIN toda la cadena."""
    hoy = date.today()
    anio = anio or hoy.year
    mes = mes or hoy.month
    desde, hasta = rango_del_mes(anio, mes)
    limite = sucursal_visible(staff)
    filas = await conn.fetch(
        """
        SELECT pr.id AS producto_id, pr.nombre AS producto, d.motivo_tipo::text AS motivo_tipo,
               t.codigo AS talla_original, c.nombre AS color_original,
               ts.codigo AS talla_solicitada, cs.nombre AS color_solicitado,
               COUNT(DISTINCT d.id)::int AS solicitudes,
               SUM(dd.cantidad)::int AS unidades,
               COUNT(DISTINCT d.id) FILTER (WHERE d.estado = 'APROBADA')::int AS aprobadas,
               COUNT(DISTINCT d.id) FILTER (
                   WHERE d.estado IN ('RECHAZADA', 'CANCELADA', 'EXPIRADA'))::int AS rechazadas,
               COUNT(DISTINCT d.id) FILTER (
                   WHERE d.estado IN ('SOLICITADA', 'CONFIRMADA'))::int AS pendientes,
               array_agg(DISTINCT s.nombre) AS sucursales
        FROM devolucion d
        JOIN devolucion_detalle dd ON dd.devolucion_id = d.id
        JOIN venta_detalle vd      ON vd.id = dd.venta_detalle_id
        JOIN producto_variante pv  ON pv.id = vd.variante_id
        JOIN producto pr           ON pr.id = pv.producto_id
        JOIN talla t               ON t.id = pv.talla_id
        JOIN color c               ON c.id = pv.color_id
        JOIN sucursal s            ON s.id = d.sucursal_id
        LEFT JOIN producto_variante ps ON ps.id = dd.variante_solicitada_id
        LEFT JOIN talla ts             ON ts.id = ps.talla_id
        LEFT JOIN color cs             ON cs.id = ps.color_id
        WHERE d.fecha >= $1 AND d.fecha < $2 AND s.empresa_id = $5
          AND ($3::uuid IS NULL OR d.sucursal_id = $3)
          AND ($4 OR d.tipo = 'INTERCAMBIO')
        GROUP BY pr.id, pr.nombre, d.motivo_tipo, t.codigo, t.orden, c.nombre, ts.codigo, cs.nombre
        ORDER BY SUM(dd.cantidad) DESC, pr.nombre, t.orden
        """,
        desde,
        hasta,
        limite,
        incluir_otros_motivos,
        empresa_de(staff),
    )
    resultado = [CambioMesOut(**dict(f)) for f in filas]
    return CambiosMesOut(
        anio=anio,
        mes=mes,
        desde=desde,
        hasta=hasta,
        total_solicitudes=sum(f.solicitudes for f in resultado),
        total_unidades=sum(f.unidades for f in resultado),
        filas=resultado,
    )


@router.get("/{devolucion_id}/nota", response_model=NotaDevolucionOut)
async def nota_de_devolucion(
    devolucion_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> NotaDevolucionOut:
    """Datos de la nota imprimible (PENDIENTES 5.9): la devolucion con su detalle mas los datos de
    la empresa y de la sucursal. El front la arma y la imprime."""
    devolucion = await _con_detalle(conn, devolucion_id, staff)
    extra = await conn.fetchrow(
        """
        SELECT s.direccion AS sucursal_direccion, s.ciudad::text AS sucursal_ciudad,
               v.fecha AS venta_fecha, e.razon_social AS razon, e.nit
        FROM devolucion d
        JOIN sucursal s ON s.id = d.sucursal_id
        JOIN empresa e  ON e.id = s.empresa_id
        JOIN venta v    ON v.id = d.venta_id
        WHERE d.id = $1
        """,
        devolucion_id,
    )
    return NotaDevolucionOut(
        empresa_razon_social=extra["razon"],
        empresa_nit=extra["nit"] or "-",
        sucursal_direccion=extra["sucursal_direccion"],
        sucursal_ciudad=extra["sucursal_ciudad"],
        venta_fecha=extra["venta_fecha"],
        plazo_dias=await servicio.plazo_dias(conn, devolucion.tipo),
        devolucion=devolucion,
    )


@router.get("/{devolucion_id}", response_model=DevolucionDetalleOut)
async def obtener_devolucion(
    devolucion_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> DevolucionDetalleOut:
    return await _con_detalle(conn, devolucion_id, staff)


# ---------------------------------------------------------------------
#  REGISTRO EN CAJA
# ---------------------------------------------------------------------


@router.post("", response_model=DevolucionDetalleOut, status_code=status.HTTP_201_CREATED)
async def registrar_devolucion(
    body: DevolucionIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_crear),
) -> DevolucionDetalleOut:
    faltan = condiciones_faltantes(
        body.motivo_tipo, body.con_etiqueta, body.sin_uso, body.con_comprobante
    )
    if faltan:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="No se acepta la devolucion: falta " + ", ".join(faltan),
        )
    # rechazos tempranos sin tocar la base (el registro los vuelve a chequear)
    servicio.agrupar_lineas(body.lineas, servicio.tipo_de(body.motivo_tipo) == "INTERCAMBIO")

    async def _alcance(venta) -> None:
        await _exigir_alcance(conn, staff, venta["sucursal_id"], "Esa venta")

    async with conn.transaction():
        devolucion_id = await servicio.registrar(
            conn,
            venta_id=body.venta_id,
            motivo_tipo=body.motivo_tipo,
            motivo=body.motivo,
            lineas=body.lineas,
            usuario_id=staff["id"],
            origen="CAJA",
            con_etiqueta=body.con_etiqueta,
            sin_uso=body.sin_uso,
            con_comprobante=body.con_comprobante,
            validar_venta_extra=_alcance,
        )
    return await _con_detalle(conn, devolucion_id, staff)


# ---------------------------------------------------------------------
#  RESOLUCION
# ---------------------------------------------------------------------


async def _bloquear_en_tramite(
    conn: asyncpg.Connection, devolucion_id: UUID, staff: dict, estados=servicio.ESTADOS_EN_TRAMITE
) -> asyncpg.Record:
    fila = await conn.fetchrow(
        """
        SELECT d.id, d.venta_id, d.sucursal_id, d.estado::text AS estado, d.tipo, d.origen,
               d.motivo_tipo::text AS motivo_tipo, d.con_etiqueta, d.sin_uso, d.con_comprobante,
               d.monto_devuelto, d.monto_cambio, d.numero, d.fecha_visita, d.hora_visita,
               v.numero AS venta_numero, v.usuario_id AS cliente_id, s.nombre AS sucursal
        FROM devolucion d
        JOIN venta v    ON v.id = d.venta_id
        JOIN sucursal s ON s.id = d.sucursal_id
        WHERE d.id = $1
        FOR UPDATE OF d
        """,
        devolucion_id,
    )
    if fila is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Devolucion no encontrada")
    await _exigir_alcance(conn, staff, fila["sucursal_id"], "Esa devolucion")
    if fila["estado"] not in estados:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"La devolucion ya esta {fila['estado'].lower()}",
        )
    return fila


async def _notificar_cliente(
    conn: asyncpg.Connection, devolucion: asyncpg.Record, titulo: str, mensaje: str
) -> None:
    """Aviso en la campana (y push/correo segun el job). entidad DEVOLUCION: la campana de la
    clienta abre Mis devoluciones."""
    if devolucion["cliente_id"] is None:  # venta de mostrador sin clienta identificada
        return
    await conn.execute(
        """
        INSERT INTO notificacion (usuario_id, tipo, titulo, mensaje, entidad_tipo, entidad_id)
        VALUES ($1, 'VENTA', $2, $3, 'DEVOLUCION', $4)
        """,
        devolucion["cliente_id"],
        titulo,
        mensaje,
        devolucion["id"],
    )


def _nombre(devolucion) -> str:
    return "intercambio" if devolucion["tipo"] == "INTERCAMBIO" else "devolucion"


@router.post("/{devolucion_id}/confirmar", response_model=DevolucionDetalleOut)
async def confirmar_solicitud(
    devolucion_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_resolver),
) -> DevolucionDetalleOut:
    """Acepta una solicitud online: la sucursal espera a la clienta en la fecha y hora que eligio.
    No mueve stock ni plata (eso pasa al concretarla en caja)."""
    async with conn.transaction():
        devolucion = await _bloquear_en_tramite(conn, devolucion_id, staff, ("SOLICITADA",))
        if devolucion["origen"] != "ONLINE":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Solo se confirma una solicitud online: la registrada en caja se concreta directo",
            )
        await conn.execute(
            "UPDATE devolucion SET estado = 'CONFIRMADA' WHERE id = $1", devolucion_id
        )
        extra = ""
        if devolucion["tipo"] == "INTERCAMBIO":
            extra = " " + servicio.texto_diferencia(
                devolucion["monto_cambio"] - devolucion["monto_devuelto"]
            )
        await _notificar_cliente(
            conn,
            devolucion,
            "Intercambio aceptado" if devolucion["tipo"] == "INTERCAMBIO" else "Devolucion aceptada",
            f"Aceptamos tu solicitud {devolucion['numero']} de la compra {devolucion['venta_numero']}. "
            f"Te esperamos en {devolucion['sucursal']} el {devolucion['fecha_visita']:%d/%m} a las "
            f"{devolucion['hora_visita']:%H:%M} con la prenda y su etiqueta.{extra}",
        )
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="devolucion",
            entidad_id=devolucion_id,
            accion="ACTUALIZAR",
            datos_antes={"estado": "SOLICITADA"},
            datos_despues={"estado": "CONFIRMADA"},
        )
    return await _con_detalle(conn, devolucion_id, staff)


async def _crear_venta_cambio(
    conn: asyncpg.Connection,
    devolucion,
    sesion_id: UUID,
    staff: dict,
    diferencia: Decimal,
    diferencia_metodo: str | None,
) -> UUID:
    """La venta de las prendas nuevas del intercambio, a su precio pactado + IVA. Lo devuelto es
    credito: solo se registra como pago lo que la clienta pone de mas. Su venta_detalle descuenta
    el stock (tg_venta_descuenta_stock); el compromiso ya lo libero tg_devolucion_stock."""
    lineas = await conn.fetch(
        """
        SELECT variante_solicitada_id AS variante_id, cantidad, precio_solicitado AS precio
        FROM devolucion_detalle
        WHERE devolucion_id = $1 AND variante_solicitada_id IS NOT NULL
        """,
        devolucion["id"],
    )
    subtotal = sum((f["precio"] * f["cantidad"] for f in lineas), Decimal("0"))
    total = servicio.con_iva(subtotal)
    venta_id = await conn.fetchval(
        """
        INSERT INTO venta (sucursal_id, usuario_id, canal, entrega, sesion_caja_id, numero,
                           subtotal, descuento, iva, total, estado, registrada_por_id)
        VALUES ($1, $2, 'POS', 'RETIRO_SUCURSAL', $3, $4, $5, 0, $6, $7, 'ENTREGADA', $8)
        RETURNING id
        """,
        devolucion["sucursal_id"],
        devolucion["cliente_id"],
        sesion_id,
        f"V-{uuid4().hex[:10].upper()}",
        subtotal,
        total - subtotal,
        total,
        staff["id"],
    )
    for linea in lineas:
        await conn.execute(
            """
            INSERT INTO venta_detalle (venta_id, variante_id, cantidad, precio_unitario, subtotal)
            VALUES ($1, $2, $3, $4, $5)
            """,
            venta_id,
            linea["variante_id"],
            linea["cantidad"],
            linea["precio"],
            linea["precio"] * linea["cantidad"],
        )
    if diferencia > 0:
        await conn.execute(
            """
            INSERT INTO pago (venta_id, metodo, monto, estado, confirmado_en, verificado_por_id)
            VALUES ($1, $2::metodo_pago, $3, 'APROBADO', now(), $4)
            """,
            venta_id,
            diferencia_metodo,
            diferencia,
            staff["id"],
        )
    # el comprobante de la venta queda para Mis compras; el correo lo cubre el del intercambio
    await conn.execute(
        "INSERT INTO comprobante (venta_id, numero, correo_enviado_en) VALUES ($1, $2, now())",
        venta_id,
        f"C-{uuid4().hex[:10].upper()}",
    )
    return venta_id


@router.post("/{devolucion_id}/aprobar", response_model=DevolucionDetalleOut)
async def aprobar_devolucion(
    devolucion_id: UUID,
    body: AprobacionIn | None = None,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_resolver),
) -> DevolucionDetalleOut:
    """Concreta la devolucion o el intercambio en caja (punto sin retorno). El UPDATE del estado
    dispara tg_devolucion_stock: reingresa lo devuelto y libera lo comprometido para el cambio."""
    body = body or AprobacionIn()
    try:
        async with conn.transaction():
            # una solicitud online SOLICITADA tambien se puede concretar directo: se acepta y se
            # concreta a la vez porque la clienta ya esta en la caja
            devolucion = await _bloquear_en_tramite(conn, devolucion_id, staff)
            con_etiqueta = devolucion["con_etiqueta"] if body.con_etiqueta is None else body.con_etiqueta
            sin_uso = devolucion["sin_uso"] if body.sin_uso is None else body.sin_uso
            con_comprobante = (
                devolucion["con_comprobante"] if body.con_comprobante is None else body.con_comprobante
            )
            faltan = condiciones_faltantes(devolucion["motivo_tipo"], con_etiqueta, sin_uso, con_comprobante)
            if faltan:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail=f"No se acepta la {_nombre(devolucion)}: falta " + ", ".join(faltan)
                    + ". Rechazala con ese motivo.",
                )

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
            valor = await servicio.monto_devolucion(conn, devolucion["venta_id"], devolucion_id, cierra)
            es_intercambio = devolucion["tipo"] == "INTERCAMBIO"
            valor_cambio = devolucion["monto_cambio"] if es_intercambio else Decimal("0")
            reintegro, cobrar = servicio.liquidar(devolucion["tipo"], valor, valor_cambio)
            if cobrar > 0 and body.diferencia_metodo is None:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"La clienta paga Bs {cobrar:.2f} de diferencia: elegi como paga (efectivo, tarjeta o QR)",
                )

            pago = await servicio.pago_de_venta(conn, devolucion["venta_id"])
            metodo = servicio.metodo_reintegro(pago) if reintegro > 0 else None
            sesion_caja_id = None
            necesita_caja = (
                es_intercambio
                or (reintegro > 0 and servicio.sale_del_cajon(metodo))
                or (cobrar > 0 and body.diferencia_metodo == "EFECTIVO")
            )
            if necesita_caja:
                # la plata sale (o entra) por el cajon y la venta del cambio es de caja: tiene
                # que haber una sesion abierta para que el arqueo la cuente
                sesion = await obtener_sesion_abierta(conn, staff["id"])
                if sesion is None:
                    raise HTTPException(
                        status_code=status.HTTP_409_CONFLICT,
                        detail="Abri una sesion de caja para concretar la "
                        + _nombre(devolucion)
                        + " (la plata sale o entra por el cajon)",
                    )
                sesion_caja_id = sesion["id"]

            await conn.execute(
                """
                UPDATE devolucion
                   SET estado = 'APROBADA', monto_devuelto = $2, monto_reintegrado = $3,
                       diferencia_cobrada = $4, diferencia_metodo = $5,
                       resuelta_por_id = $6, resuelta_en = now(),
                       reintegro_metodo = $7, sesion_caja_id = $8,
                       con_etiqueta = $9, sin_uso = $10, con_comprobante = $11
                 WHERE id = $1
                """,
                devolucion_id,
                valor,
                reintegro,
                cobrar,
                body.diferencia_metodo if cobrar > 0 else None,
                staff["id"],
                metodo,
                sesion_caja_id,
                con_etiqueta,
                sin_uso,
                con_comprobante,
            )
            if cierra and not es_intercambio:
                await conn.execute(
                    "UPDATE pago SET estado = 'REEMBOLSADO' WHERE venta_id = $1 AND estado = 'APROBADO'",
                    devolucion["venta_id"],
                )
            venta_cambio_id = None
            if es_intercambio:
                venta_cambio_id = await _crear_venta_cambio(
                    conn, devolucion, sesion_caja_id, staff, cobrar, body.diferencia_metodo
                )
                await conn.execute(
                    "UPDATE devolucion SET venta_cambio_id = $2 WHERE id = $1", devolucion_id, venta_cambio_id
                )

            if es_intercambio:
                if cobrar > 0:
                    plata = f" Pagaste Bs {cobrar:.2f} de diferencia."
                elif reintegro > 0:
                    plata = f" Te devolvimos Bs {reintegro:.2f} de diferencia{_COMO_SE_REINTEGRA.get(metodo, '')}."
                else:
                    plata = ""
                await _notificar_cliente(
                    conn,
                    devolucion,
                    "Intercambio realizado",
                    f"Listo el intercambio de tu compra {devolucion['venta_numero']}.{plata} "
                    "Te mandamos el comprobante por correo.",
                )
            else:
                await _notificar_cliente(
                    conn,
                    devolucion,
                    "Devolucion aprobada",
                    f"Aprobamos la devolucion de tu compra {devolucion['venta_numero']}. Se te reintegran "
                    f"Bs {reintegro:.2f}{_COMO_SE_REINTEGRA.get(metodo, '')}. Te mandamos el comprobante por correo.",
                )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="devolucion",
                entidad_id=devolucion_id,
                accion="ACTUALIZAR",
                datos_antes={"estado": devolucion["estado"], "monto_devuelto": devolucion["monto_devuelto"]},
                datos_despues={
                    "estado": "APROBADA",
                    "tipo": devolucion["tipo"],
                    "monto_devuelto": valor,
                    "monto_reintegrado": reintegro,
                    "diferencia_cobrada": cobrar,
                    "venta_completa": cierra,
                    "reintegro_metodo": metodo,
                    "venta_cambio": str(venta_cambio_id) if venta_cambio_id else None,
                },
            )

            if metodo == "STRIPE" and reintegro > 0 and pago["id_transaccion"]:
                # ultimo paso antes del commit: si Stripe no devuelve la plata, la HTTPException
                # deshace toda la aprobacion (estado, stock, venta del cambio) y se puede reintentar
                try:
                    referencia = await reembolsar_parcial_stripe(
                        pago["id_transaccion"], reintegro, f"devolucion-{devolucion_id}"
                    )
                except stripe.error.StripeError as error:
                    raise HTTPException(
                        status_code=status.HTTP_502_BAD_GATEWAY,
                        detail=f"Stripe no acepto el reembolso, la devolucion sigue pendiente: {error}",
                    ) from error
                await conn.execute(
                    "UPDATE devolucion SET reintegro_referencia = $2 WHERE id = $1",
                    devolucion_id,
                    referencia,
                )
    except asyncpg.RaiseError as error:
        # tope de lo vendido (tg_devolucion_stock) o cualquier error de fn_mover_inventario
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(error)) from error

    return await _con_detalle(conn, devolucion_id, staff)


@router.post("/{devolucion_id}/rechazar", response_model=DevolucionDetalleOut)
async def rechazar_devolucion(
    devolucion_id: UUID,
    body: RechazoIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_resolver),
) -> DevolucionDetalleOut:
    """Rechaza una devolucion/intercambio en tramite (registrada en caja, solicitud online o una
    ya confirmada cuya prenda no cumple las condiciones). Libera lo comprometido para el cambio."""
    motivo = body.motivo.strip()
    async with conn.transaction():
        devolucion = await _bloquear_en_tramite(conn, devolucion_id, staff)
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
        await _notificar_cliente(
            conn,
            devolucion,
            "Intercambio rechazado" if devolucion["tipo"] == "INTERCAMBIO" else "Devolucion rechazada",
            f"No pudimos aceptar la {_nombre(devolucion)} de tu compra {devolucion['venta_numero']}: {motivo}",
        )
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="devolucion",
            entidad_id=devolucion_id,
            accion="ACTUALIZAR",
            datos_antes={"estado": devolucion["estado"]},
            datos_despues={"estado": "RECHAZADA", "motivo_rechazo": motivo},
        )
    return await _con_detalle(conn, devolucion_id, staff)
