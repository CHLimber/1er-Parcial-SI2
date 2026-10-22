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
    cambia de estado (sigue PAGADA/ENTREGADA: la venta existio).
  - Reintegro (al aprobar, segun como se pago la venta; queda en devolucion.reintegro_*):
      STRIPE -> reembolso parcial real por la API (idempotente por devolucion); si Stripe lo
                rechaza la aprobacion se deshace (502).
      EFECTIVO -> sale del cajon: exige una sesion de caja abierta de quien aprueba y la
                devolucion queda atada a ella (fn_total_efectivo_sesion la resta del arqueo).
      TARJETA/QR/TRANSFERENCIA -> se devuelve fuera del sistema (el QR es simulado); queda
                registrado el metodo, quien aprobo y cuando.
  - Plazo: configuracion.devolucion_plazo_dias (30 por defecto) desde la fecha de la venta. El
    cambio por talla/color (motivo_tipo TALLA/COLOR) corre su propio plazo, mas corto:
    configuracion.cambio_plazo_dias (15 por defecto). PENDIENTES 5.8.
  - Condiciones de la prenda (las verifica el personal al recibirla): para TALLA, COLOR,
    NO_GUSTO y OTRO tiene que volver con etiqueta, sin uso y con el comprobante de compra; por
    DEFECTO alcanza con el comprobante (la falla es de la tienda). Si falta alguna -> 409.
  - Cambio por talla/color: cada linea dice que variante se lleva la clienta a cambio
    (variante_solicitada_id): la misma prenda, otra talla (TALLA) u otro color (COLOR), con stock
    disponible en la sucursal. En los otros motivos no se acepta una variante solicitada.
  - Cambio de prenda = devolucion + venta nueva cobrada en caja; POST /{id}/cambio vincula esa
    venta a la devolucion (venta_cambio_id) para que quede la trazabilidad.
  - Nota de devolucion: cada devolucion tiene un numero correlativo NDV-xxxxxx (secuencia de la
    base) y GET /{id}/nota devuelve los datos del comprobante imprimible (PENDIENTES 5.9).
  - GET /cambios-mes responde "que prendas solicitaron cambio en el mes" (PENDIENTES 5.10).
  - Sucursal: la devolucion se registra y el stock reingresa en la sucursal de la venta.
  - La clienta recibe una notificacion (tipo VENTA, entidad VENTA) al aprobar o rechazar. Las
    ventas POS sin clienta identificada (venta.usuario_id NULL) no notifican a nadie.
  - Multi-tenant: la venta, la devolucion y la sucursal tienen que ser de la empresa del
    usuario; lo de otra empresa responde 404 (ni siquiera se confirma que el numero existe). La
    nota de devolucion sale con la razon social y el NIT de la empresa (tabla empresa).
"""

from datetime import date
from decimal import ROUND_HALF_UP, Decimal
from uuid import UUID

import asyncpg
import stripe
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.auditoria import registrar_auditoria
from app.core.db import get_connection
from app.core.deps import requiere_permiso
from app.core.tenant import (
    empresa_de,
    empresa_de_sucursal,
    es_admin_empresa,
    exigir_variantes,
    no_encontrado,
)
from app.modules.operacion_comercial.caja.router import obtener_sesion_abierta
from app.modules.operacion_comercial.devoluciones.schemas import (
    CambioIn,
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
from app.modules.operacion_comercial.pagos.servicio import reembolsar_parcial_stripe

router = APIRouter(prefix="/devoluciones", tags=["devoluciones"])

puede_ver = requiere_permiso("devoluciones.leer", "devoluciones.crear", "devoluciones.actualizar")
puede_crear = requiere_permiso("devoluciones.crear")
puede_resolver = requiere_permiso("devoluciones.actualizar")

CENTAVO = Decimal("0.01")
ESTADOS_VENTA_DEVOLVIBLE = ("PAGADA", "ENTREGADA")
PLAZO_DIAS_POR_DEFECTO = 30  # si falta configuracion.devolucion_plazo_dias
PLAZO_CAMBIO_POR_DEFECTO = 15  # si falta configuracion.cambio_plazo_dias
MOTIVOS_CAMBIO = ("TALLA", "COLOR")

# texto de la notificacion a la clienta segun como vuelve la plata
_COMO_SE_REINTEGRA = {
    "STRIPE": " a tu tarjeta (puede tardar unos dias en verse)",
    "EFECTIVO": " en efectivo en la sucursal",
}

SELECT_DEVOLUCION = """
SELECT d.id, d.numero, d.venta_id, v.numero AS venta_numero, v.total AS venta_total,
       d.sucursal_id, s.nombre AS sucursal,
       (cli.nombre || ' ' || cli.apellido) AS cliente,
       d.motivo_tipo::text AS motivo_tipo, d.motivo,
       d.con_etiqueta, d.sin_uso, d.con_comprobante,
       d.monto_devuelto, d.estado, d.fecha,
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


def _sucursal_visible(staff: dict) -> UUID | None:
    """Mismo criterio que recepciones: el ADMIN de la empresa ve todas las de su empresa; el
    resto solo la suya."""
    if es_admin_empresa(staff):
        return None
    if staff["sucursal_id"] is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tu usuario no esta asignado a ninguna sucursal",
        )
    return staff["sucursal_id"]


async def _exigir_alcance(
    conn: asyncpg.Connection, staff: dict, sucursal_id: UUID, que: str
) -> None:
    """404 si la sucursal es de otra empresa; 403 si es de la empresa pero no la del usuario."""
    if await empresa_de_sucursal(conn, sucursal_id) != empresa_de(staff):
        raise no_encontrado(f"{que} no existe")
    limite = _sucursal_visible(staff)
    if limite is not None and sucursal_id != limite:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=f"{que} es de otra sucursal")


async def _config_dias(conn: asyncpg.Connection, clave: str, por_defecto: int) -> int:
    valor = await conn.fetchval("SELECT valor FROM configuracion WHERE clave = $1", clave)
    try:
        return int(valor) if valor is not None else por_defecto
    except ValueError:
        return por_defecto


async def _plazo_dias(conn: asyncpg.Connection) -> int:
    return await _config_dias(conn, "devolucion_plazo_dias", PLAZO_DIAS_POR_DEFECTO)


async def _plazo_cambio_dias(conn: asyncpg.Connection) -> int:
    return await _config_dias(conn, "cambio_plazo_dias", PLAZO_CAMBIO_POR_DEFECTO)


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


async def _pago_de_venta(conn: asyncpg.Connection, venta_id: UUID) -> asyncpg.Record | None:
    return await conn.fetchrow(
        """
        SELECT metodo::text AS metodo, pasarela::text AS pasarela, id_transaccion
        FROM pago WHERE venta_id = $1 AND estado = 'APROBADO'
        ORDER BY creado_en DESC LIMIT 1
        """,
        venta_id,
    )


def _metodo_reintegro(pago: asyncpg.Record | None) -> str | None:
    """Por donde vuelve la plata: por donde entro. Un pago online va por pasarela (STRIPE o el QR
    simulado); uno de caja, por su metodo."""
    if pago is None:
        return None
    if pago["pasarela"] in ("STRIPE", "QR"):
        return pago["pasarela"]
    if pago["metodo"] in ("EFECTIVO", "TARJETA", "QR", "TRANSFERENCIA"):
        return pago["metodo"]
    return None


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
    await _exigir_alcance(conn, staff, fila["sucursal_id"], "Esa devolucion")
    return DevolucionOut(**dict(fila))


async def _con_detalle(
    conn: asyncpg.Connection, devolucion_id: UUID, staff: dict
) -> DevolucionDetalleOut:
    cabecera = await _obtener(conn, devolucion_id, staff)
    filas = await conn.fetch(
        """
        SELECT dd.id, dd.venta_detalle_id, vd.variante_id, pv.sku, pr.nombre AS producto,
               t.codigo AS talla, c.nombre AS color, dd.cantidad,
               vd.cantidad AS cantidad_vendida, vd.precio_unitario,
               dd.variante_solicitada_id, ts.codigo AS talla_solicitada,
               cs.nombre AS color_solicitado, ps.sku AS sku_solicitado
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
    venta: str | None = Query(
        default=None, max_length=40, description="Numero de venta o de nota (parcial)"
    ),
    motivo_tipo: str | None = Query(default=None, pattern="^(TALLA|COLOR|DEFECTO|NO_GUSTO|OTRO)$"),
    desde: date | None = Query(default=None, description="Fecha de la devolucion, desde (inclusive)"),
    hasta: date | None = Query(default=None, description="Fecha de la devolucion, hasta (inclusive)"),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[DevolucionOut]:
    limite = _sucursal_visible(staff)
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
        ORDER BY d.fecha DESC
        LIMIT 200
        """,
        limite,
        estado,
        venta.strip() if venta else None,
        motivo_tipo,
        desde,
        hasta,
        empresa_de(staff),
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
        await _plazo_dias(conn),
        await _plazo_cambio_dias(conn),
        empresa_de(staff),
    )
    if venta is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No existe una venta con ese numero")
    await _exigir_alcance(conn, staff, venta["sucursal_id"], "Esa venta")
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
    return VentaDevolvibleOut(
        **dict(venta),
        reintegro_metodo=_metodo_reintegro(await _pago_de_venta(conn, venta["venta_id"])),
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
    """Las otras tallas/colores de la misma prenda con su disponible en la sucursal, para elegir
    que se lleva la clienta en un cambio."""
    await _exigir_alcance(conn, staff, sucursal_id, "Esa sucursal")
    await exigir_variantes(conn, [variante_id], empresa_de(staff))
    filas = await conn.fetch(
        """
        SELECT pv.id AS variante_id, pv.sku, t.codigo AS talla, c.nombre AS color,
               COALESCE(i.disponible, 0) AS disponible
        FROM producto_variante pv
        JOIN producto_variante orig ON orig.id = $1 AND orig.producto_id = pv.producto_id
        JOIN talla t ON t.id = pv.talla_id
        JOIN color c ON c.id = pv.color_id
        LEFT JOIN inventario i ON i.variante_id = pv.id AND i.sucursal_id = $2
        WHERE pv.activa AND pv.id <> $1
        ORDER BY t.orden, c.nombre
        """,
        variante_id,
        sucursal_id,
    )
    return [VarianteCambioOut(**dict(f)) for f in filas]


@router.get("/cambios-mes", response_model=CambiosMesOut)
async def cambios_del_mes(
    anio: int | None = Query(default=None, ge=2020, le=2100),
    mes: int | None = Query(default=None, ge=1, le=12),
    incluir_otros_motivos: bool = Query(
        default=False, description="False: solo TALLA/COLOR (cambios). True: toda devolucion"
    ),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> CambiosMesOut:
    """Que prendas solicitaron cambio en el mes (PENDIENTES 5.10). Agrupa por prenda, talla/
    color original y lo que se pidio a cambio; por defecto el mes en curso. Un ENCARGADO ve su
    sucursal, el ADMIN toda la cadena."""
    hoy = date.today()
    anio = anio or hoy.year
    mes = mes or hoy.month
    desde, hasta = rango_del_mes(anio, mes)
    limite = _sucursal_visible(staff)
    filas = await conn.fetch(
        """
        SELECT pr.id AS producto_id, pr.nombre AS producto, d.motivo_tipo::text AS motivo_tipo,
               t.codigo AS talla_original, c.nombre AS color_original,
               ts.codigo AS talla_solicitada, cs.nombre AS color_solicitado,
               COUNT(DISTINCT d.id)::int AS solicitudes,
               SUM(dd.cantidad)::int AS unidades,
               COUNT(DISTINCT d.id) FILTER (WHERE d.estado = 'APROBADA')::int AS aprobadas,
               COUNT(DISTINCT d.id) FILTER (WHERE d.estado = 'RECHAZADA')::int AS rechazadas,
               COUNT(DISTINCT d.id) FILTER (WHERE d.estado = 'SOLICITADA')::int AS pendientes,
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
          AND ($4 OR d.motivo_tipo IN ('TALLA','COLOR'))
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
    """Datos de la nota de devolucion imprimible (PENDIENTES 5.9): la devolucion con su detalle
    mas los datos de la empresa y de la sucursal. El front la arma y la imprime."""
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
    plazo = await (
        _plazo_cambio_dias(conn) if devolucion.motivo_tipo in MOTIVOS_CAMBIO else _plazo_dias(conn)
    )
    return NotaDevolucionOut(
        empresa_razon_social=extra["razon"],
        empresa_nit=extra["nit"] or "-",
        sucursal_direccion=extra["sucursal_direccion"],
        sucursal_ciudad=extra["sucursal_ciudad"],
        venta_fecha=extra["venta_fecha"],
        plazo_dias=plazo,
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
#  REGISTRO
# ---------------------------------------------------------------------


async def _validar_cambio_linea(
    conn: asyncpg.Connection,
    motivo_tipo: str,
    sucursal_id: UUID,
    linea: asyncpg.Record,
    variante_solicitada_id: UUID,
    cantidad: int,
) -> None:
    """La variante pedida a cambio: misma prenda, otra talla/color y con stock en la sucursal.
    No compromete el stock (eso lo hace la venta del cambio en caja); solo evita aceptar un
    cambio que la tienda no puede cumplir."""
    variantes = {
        f["id"]: f
        for f in await conn.fetch(
            """
            SELECT pv.id, pv.producto_id, pv.talla_id, pv.color_id, pv.activa,
                   t.codigo AS talla, c.nombre AS color,
                   COALESCE((SELECT disponible FROM inventario
                              WHERE sucursal_id = $3 AND variante_id = pv.id), 0) AS disponible
            FROM producto_variante pv
            JOIN talla t ON t.id = pv.talla_id
            JOIN color c ON c.id = pv.color_id
            WHERE pv.id IN ($1, $2)
            """,
            linea["variante_id"],
            variante_solicitada_id,
            sucursal_id,
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
    if solicitada["disponible"] < cantidad:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                f"No hay stock para el cambio: {linea['producto']} talla {solicitada['talla']} "
                f"color {solicitada['color']} tiene {max(solicitada['disponible'], 0)} disponibles "
                "en la sucursal (se puede pedir por traspaso)"
            ),
        )


@router.post("", response_model=DevolucionDetalleOut, status_code=status.HTTP_201_CREATED)
async def registrar_devolucion(
    body: DevolucionIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_crear),
) -> DevolucionDetalleOut:
    es_cambio = body.motivo_tipo in MOTIVOS_CAMBIO
    faltan = condiciones_faltantes(
        body.motivo_tipo, body.con_etiqueta, body.sin_uso, body.con_comprobante
    )
    if faltan:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="No se acepta la devolucion: falta " + ", ".join(faltan),
        )

    # la misma linea dos veces en el pedido se suma, como en recepciones
    pedidas: dict[UUID, int] = {}
    solicitadas: dict[UUID, UUID | None] = {}
    for linea in body.lineas:
        pedidas[linea.venta_detalle_id] = pedidas.get(linea.venta_detalle_id, 0) + linea.cantidad
        if es_cambio and linea.variante_solicitada_id is None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="En un cambio por talla o color cada prenda tiene que decir que se lleva a cambio",
            )
        if not es_cambio and linea.variante_solicitada_id is not None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Solo un cambio por talla o color lleva una prenda a cambio",
            )
        anterior = solicitadas.get(linea.venta_detalle_id)
        if anterior is not None and anterior != linea.variante_solicitada_id:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="La misma prenda no puede pedir dos variantes distintas a cambio",
            )
        solicitadas[linea.venta_detalle_id] = linea.variante_solicitada_id

    async with conn.transaction():
        # Se bloquea la venta: dos registros simultaneos sobre la misma venta se serializan y
        # el segundo ve lo que el primero dejo en tramite.
        venta = await conn.fetchrow(
            "SELECT id, sucursal_id, estado, numero FROM venta WHERE id = $1 FOR UPDATE",
            body.venta_id,
        )
        if venta is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Venta no encontrada")
        await _exigir_alcance(conn, staff, venta["sucursal_id"], "Esa venta")
        if venta["estado"] not in ESTADOS_VENTA_DEVOLVIBLE:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"La venta esta {venta['estado'].lower()}: solo se devuelve una venta pagada o entregada",
            )
        dias = await (_plazo_cambio_dias(conn) if es_cambio else _plazo_dias(conn))
        vencida = await conn.fetchval(
            "SELECT now() > fecha + make_interval(days => $2) FROM venta WHERE id = $1",
            venta["id"],
            dias,
        )
        if vencida:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    f"La venta {venta['numero']} tiene mas de {dias} dias: ya paso el plazo para "
                    + ("cambiar la prenda" if es_cambio else "devolverla")
                ),
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
            if es_cambio:
                await _validar_cambio_linea(
                    conn,
                    body.motivo_tipo,
                    venta["sucursal_id"],
                    linea,
                    solicitadas[venta_detalle_id],
                    cantidad,
                )

        devolucion_id = await conn.fetchval(
            """
            INSERT INTO devolucion (venta_id, sucursal_id, motivo, monto_devuelto, usuario_id,
                                    motivo_tipo, con_etiqueta, sin_uso, con_comprobante)
            VALUES ($1, $2, $3, 0, $4, $5::motivo_devolucion, $6, $7, $8)
            RETURNING id
            """,
            venta["id"],
            venta["sucursal_id"],
            body.motivo.strip(),
            staff["id"],
            body.motivo_tipo,
            body.con_etiqueta,
            body.sin_uso,
            body.con_comprobante,
        )
        await conn.executemany(
            """
            INSERT INTO devolucion_detalle (devolucion_id, venta_detalle_id, cantidad,
                                            variante_solicitada_id)
            VALUES ($1, $2, $3, $4)
            """,
            [(devolucion_id, vd_id, cantidad, solicitadas[vd_id]) for vd_id, cantidad in pedidas.items()],
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
                "motivo_tipo": body.motivo_tipo,
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
    await _exigir_alcance(conn, staff, fila["sucursal_id"], "Esa devolucion")
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

            pago = await _pago_de_venta(conn, devolucion["venta_id"])
            metodo = _metodo_reintegro(pago)
            sesion_caja_id = None
            if metodo == "EFECTIVO" and monto > 0:
                # la plata sale del cajon: tiene que salir de una sesion abierta para que el
                # arqueo la descuente (fn_total_efectivo_sesion), si no el cierre da faltante
                sesion = await obtener_sesion_abierta(conn, staff["id"])
                if sesion is None:
                    raise HTTPException(
                        status_code=status.HTTP_409_CONFLICT,
                        detail=(
                            "La venta se pago en efectivo: abri una sesion de caja para devolver "
                            "la plata desde el cajon"
                        ),
                    )
                sesion_caja_id = sesion["id"]

            await conn.execute(
                """
                UPDATE devolucion
                   SET estado = 'APROBADA', monto_devuelto = $2,
                       resuelta_por_id = $3, resuelta_en = now(),
                       reintegro_metodo = $4, sesion_caja_id = $5
                 WHERE id = $1
                """,
                devolucion_id,
                monto,
                staff["id"],
                metodo,
                sesion_caja_id,
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
                       || to_char($2::numeric, 'FM999999990.00') || $3 || '.',
                       'VENTA', id
                FROM venta WHERE id = $1 AND usuario_id IS NOT NULL
                """,
                devolucion["venta_id"],
                monto,
                _COMO_SE_REINTEGRA.get(metodo, ""),
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
                    "reintegro_metodo": metodo,
                },
            )

            if metodo == "STRIPE" and monto > 0 and pago["id_transaccion"]:
                # ultimo paso antes del commit: si Stripe no devuelve la plata, la HTTPException
                # deshace toda la aprobacion (estado, stock, notificacion) y se puede reintentar
                try:
                    referencia = await reembolsar_parcial_stripe(
                        pago["id_transaccion"], monto, f"devolucion-{devolucion_id}"
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


@router.post("/{devolucion_id}/cambio", response_model=DevolucionDetalleOut)
async def vincular_cambio(
    devolucion_id: UUID,
    body: CambioIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_crear),
) -> DevolucionDetalleOut:
    """Cambio de prenda: la clienta devolvio algo y se llevo otra talla/color. No hay flujo propio:
    se aprueba la devolucion (reintegra) y la prenda nueva se cobra en caja como cualquier venta;
    esto vincula esa venta nueva a la devolucion para que quede la trazabilidad."""
    async with conn.transaction():
        devolucion = await conn.fetchrow(
            "SELECT id, venta_id, sucursal_id, estado, fecha, venta_cambio_id "
            "FROM devolucion WHERE id = $1 FOR UPDATE",
            devolucion_id,
        )
        if devolucion is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Devolucion no encontrada")
        await _exigir_alcance(conn, staff, devolucion["sucursal_id"], "Esa devolucion")
        if devolucion["estado"] != "APROBADA":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Solo se vincula un cambio a una devolucion aprobada",
            )
        if devolucion["venta_cambio_id"] is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Esta devolucion ya tiene una venta de cambio vinculada",
            )

        venta = await conn.fetchrow(
            "SELECT v.id, v.numero, v.sucursal_id, v.estado::text AS estado, v.fecha "
            "FROM venta v JOIN sucursal s ON s.id = v.sucursal_id "
            "WHERE upper(v.numero) = upper($1) AND s.empresa_id = $2",
            body.venta_numero.strip(),
            empresa_de(staff),
        )
        if venta is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No existe una venta con ese numero")
        if venta["id"] == devolucion["venta_id"]:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="La venta del cambio no puede ser la misma venta que se devolvio",
            )
        if venta["sucursal_id"] != devolucion["sucursal_id"]:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="La venta del cambio es de otra sucursal",
            )
        if venta["estado"] not in ESTADOS_VENTA_DEVOLVIBLE:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"La venta del cambio esta {venta['estado'].lower()}: tiene que estar cobrada",
            )
        if venta["fecha"] < devolucion["fecha"]:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="La venta del cambio es anterior a la devolucion",
            )
        otra = await conn.fetchval(
            "SELECT id FROM devolucion WHERE venta_cambio_id = $1 AND id <> $2",
            venta["id"],
            devolucion_id,
        )
        if otra is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Esa venta ya esta vinculada como cambio de otra devolucion",
            )

        await conn.execute(
            "UPDATE devolucion SET venta_cambio_id = $2 WHERE id = $1", devolucion_id, venta["id"]
        )
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="devolucion",
            entidad_id=devolucion_id,
            accion="ACTUALIZAR",
            datos_antes={"venta_cambio": None},
            datos_despues={"venta_cambio": venta["numero"]},
        )

    return await _con_detalle(conn, devolucion_id, staff)
