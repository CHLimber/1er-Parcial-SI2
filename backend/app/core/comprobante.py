"""Comprobante de compra: datos, PDF y correo al comprador.

Lo usan tres sitios, por eso vive en `core/` y no en un modulo:

  - `core/avisos.py` (job): manda el correo automatico cuando un pago se aprueba.
  - `ventas/router.py`: descarga del PDF y reenvio manual (web y movil), por si la clienta perdio el
    correo o el telefono.

El comprobante es un RECIBO interno (tabla `comprobante`), no una factura fiscal del SIN: no
lleva codigo de control ni CUF. Si la empresa necesita facturacion electronica, es otro CU.

El PDF usa las fuentes base de PDF (Helvetica), que solo cubren latin-1: los textos se pasan por
`_l1` para que un nombre de prenda con un caracter raro no rompa la generacion.
"""

import logging
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from html import escape
from uuid import UUID

import asyncpg
from fpdf import FPDF

from app.core.correo import correo_configurado, enviar_correo

log = logging.getLogger(__name__)

# Bolivia no tiene horario de verano: UTC-4 fijo. Evita depender de tzdata (falta en Windows).
HUSO_BOLIVIA = timezone(timedelta(hours=-4))

MAX_INTENTOS_CORREO = 3

_CONSULTA_VENTA = """
    SELECT v.id, v.numero, v.fecha, v.canal::text AS canal, v.entrega::text AS entrega,
           v.estado::text AS estado, v.subtotal, v.descuento, v.costo_envio, v.iva, v.total,
           s.nombre AS sucursal, e.nombre AS empresa, e.razon_social, e.nit,
           u.nombre || ' ' || u.apellido AS cliente, u.email AS cliente_email,
           c.numero AS comprobante, c.emitido_en, c.nit_cliente, c.razon_social AS razon_cliente
    FROM venta v
    JOIN comprobante c ON c.venta_id = v.id
    JOIN sucursal s    ON s.id = v.sucursal_id
    JOIN empresa e     ON e.id = s.empresa_id
    LEFT JOIN usuario u ON u.id = v.usuario_id
    WHERE v.id = $1
"""

_CONSULTA_ITEMS = """
    SELECT p.nombre AS producto, t.codigo AS talla, col.nombre AS color,
           vd.cantidad, vd.precio_unitario, vd.subtotal
    FROM venta_detalle vd
    JOIN producto_variante pv ON pv.id = vd.variante_id
    JOIN producto p   ON p.id = pv.producto_id
    JOIN talla t      ON t.id = pv.talla_id
    JOIN color col    ON col.id = pv.color_id
    WHERE vd.venta_id = $1
    ORDER BY p.nombre, t.codigo
"""

_CONSULTA_PAGO = """
    SELECT metodo::text AS metodo, pasarela::text AS pasarela, estado::text AS estado
    FROM pago WHERE venta_id = $1 ORDER BY creado_en DESC LIMIT 1
"""


async def cargar_datos(conn: asyncpg.Connection, venta_id: UUID) -> dict | None:
    """Todo lo que lleva el comprobante, o None si la venta no tiene comprobante (todavia no se
    aprobo el pago)."""
    venta = await conn.fetchrow(_CONSULTA_VENTA, venta_id)
    if venta is None:
        return None
    items = await conn.fetch(_CONSULTA_ITEMS, venta_id)
    pago = await conn.fetchrow(_CONSULTA_PAGO, venta_id)
    datos = dict(venta)
    datos["items"] = [dict(item) for item in items]
    datos["pago"] = dict(pago) if pago else None
    return datos


def _l1(texto: object) -> str:
    return str(texto if texto is not None else "").encode("latin-1", "replace").decode("latin-1")


def _bs(monto: Decimal | float | int) -> str:
    return f"Bs {Decimal(monto):,.2f}"


def _fecha(valor: datetime) -> str:
    return valor.astimezone(HUSO_BOLIVIA).strftime("%d/%m/%Y %H:%M")


def _forma_de_pago(pago: dict | None) -> str:
    if not pago:
        return "-"
    if pago["metodo"] == "EFECTIVO":
        return "Efectivo"
    if pago["pasarela"] == "STRIPE":
        return "Tarjeta (Stripe)"
    if pago["pasarela"] == "QR":
        return "QR"
    return pago["metodo"].capitalize()


def generar_pdf(datos: dict) -> bytes:
    """Recibo de una pagina A4 con el detalle de la compra."""
    pdf = FPDF(format="A4", unit="mm")
    pdf.set_auto_page_break(auto=True, margin=15)
    pdf.add_page()
    ancho = pdf.w - pdf.l_margin - pdf.r_margin

    pdf.set_font("Helvetica", "B", 18)
    pdf.cell(ancho, 9, _l1(datos["empresa"]), new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 9)
    pdf.set_text_color(90, 90, 90)
    pdf.cell(
        ancho,
        5,
        _l1(f"{datos['razon_social']}  -  NIT {datos['nit']}"),
        new_x="LMARGIN",
        new_y="NEXT",
    )
    pdf.cell(ancho, 5, _l1(f"Sucursal {datos['sucursal']}"), new_x="LMARGIN", new_y="NEXT")
    pdf.set_text_color(0, 0, 0)
    pdf.ln(4)

    pdf.set_font("Helvetica", "B", 13)
    pdf.cell(ancho, 7, "COMPROBANTE DE COMPRA", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 10)
    filas = [
        ("Comprobante", datos["comprobante"]),
        ("Pedido", datos["numero"]),
        ("Fecha", _fecha(datos["emitido_en"])),
        ("Cliente", datos["cliente"] or "Consumidor final"),
        ("Forma de pago", _forma_de_pago(datos["pago"])),
        ("Entrega", "A domicilio" if datos["entrega"] == "DOMICILIO" else "Retiro en sucursal"),
    ]
    if datos["nit_cliente"]:
        filas.append(("NIT / CI", datos["nit_cliente"]))
    if datos["razon_cliente"]:
        filas.append(("Razon social", datos["razon_cliente"]))
    for etiqueta, valor in filas:
        pdf.set_font("Helvetica", "B", 10)
        pdf.cell(35, 6, _l1(etiqueta))
        pdf.set_font("Helvetica", "", 10)
        pdf.cell(ancho - 35, 6, _l1(valor), new_x="LMARGIN", new_y="NEXT")
    pdf.ln(4)

    columnas = (("Prenda", ancho - 88), ("Talla", 18), ("Cant.", 15), ("P. unit.", 27), ("Subtotal", 28))
    pdf.set_fill_color(30, 30, 30)
    pdf.set_text_color(255, 255, 255)
    pdf.set_font("Helvetica", "B", 9)
    for nombre, largo in columnas:
        pdf.cell(largo, 7, nombre, border=0, fill=True, align="L" if nombre == "Prenda" else "R")
    pdf.ln()
    pdf.set_text_color(0, 0, 0)
    pdf.set_font("Helvetica", "", 9)
    for item in datos["items"]:
        descripcion = f"{item['producto']} ({item['color']})"
        pdf.cell(columnas[0][1], 7, _l1(descripcion)[:60], border="B")
        pdf.cell(columnas[1][1], 7, _l1(item["talla"]), border="B", align="R")
        pdf.cell(columnas[2][1], 7, str(item["cantidad"]), border="B", align="R")
        pdf.cell(columnas[3][1], 7, _bs(item["precio_unitario"]), border="B", align="R")
        pdf.cell(columnas[4][1], 7, _bs(item["subtotal"]), border="B", align="R")
        pdf.ln()
    pdf.ln(3)

    def total(etiqueta: str, monto: Decimal, negrita: bool = False) -> None:
        pdf.set_font("Helvetica", "B" if negrita else "", 11 if negrita else 10)
        pdf.cell(ancho - 45, 6, etiqueta, align="R")
        pdf.cell(45, 6, _bs(monto), align="R", new_x="LMARGIN", new_y="NEXT")

    total("Subtotal", datos["subtotal"])
    if datos["descuento"]:
        total("Descuento", -datos["descuento"])
    total("IVA (13%)", datos["iva"])
    if datos["costo_envio"]:
        total("Envio (sin IVA)", datos["costo_envio"])
    total("TOTAL", datos["total"], negrita=True)

    pdf.ln(8)
    pdf.set_font("Helvetica", "I", 8)
    pdf.set_text_color(110, 110, 110)
    pdf.multi_cell(
        ancho,
        4,
        _l1(
            "Este comprobante respalda tu compra en la tienda y sirve para cambios y devoluciones. "
            "Guardalo: si lo perdes, podes pedirlo de nuevo desde Mis compras."
        ),
    )
    return bytes(pdf.output())


def nombre_archivo(datos: dict) -> str:
    return f"comprobante-{datos['comprobante']}.pdf"


def armar_correo(datos: dict) -> tuple[str, str, str]:
    """(asunto, texto plano, html) del correo con el resumen de la compra."""
    nombre = (datos["cliente"] or "").split(" ")[0] or "hola"
    asunto = f"Tu comprobante {datos['comprobante']} - {datos['empresa']}"

    lineas_texto = [
        f"Hola {nombre}, gracias por tu compra en {datos['empresa']}.",
        "",
        f"Pedido: {datos['numero']}",
        f"Comprobante: {datos['comprobante']}",
        f"Fecha: {_fecha(datos['emitido_en'])}",
        f"Sucursal: {datos['sucursal']}",
        "",
    ]
    filas_html = []
    for item in datos["items"]:
        detalle = f"{item['cantidad']} x {item['producto']} ({item['color']}, talla {item['talla']})"
        lineas_texto.append(f"- {detalle}: {_bs(item['subtotal'])}")
        filas_html.append(
            f"<tr><td style='padding:6px 0;border-bottom:1px solid #eee'>{escape(detalle)}</td>"
            f"<td style='padding:6px 0;border-bottom:1px solid #eee;text-align:right'>"
            f"{_bs(item['subtotal'])}</td></tr>"
        )
    lineas_texto += ["", f"TOTAL: {_bs(datos['total'])}", ""]
    lineas_texto.append(
        "Adjuntamos el comprobante en PDF. Si lo perdes, podes pedirlo de nuevo desde Mis "
        "compras, en la web o en la app."
    )

    html = f"""\
<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:auto;color:#1c1c1c">
  <h2 style="margin:0 0 4px">{escape(datos['empresa'])}</h2>
  <p style="margin:0 0 16px;color:#666">Gracias por tu compra, {escape(nombre)}.</p>
  <table style="width:100%;font-size:14px;margin-bottom:12px">
    <tr><td style="color:#666">Pedido</td><td style="text-align:right">{escape(datos['numero'])}</td></tr>
    <tr><td style="color:#666">Comprobante</td><td style="text-align:right"><b>{escape(datos['comprobante'])}</b></td></tr>
    <tr><td style="color:#666">Fecha</td><td style="text-align:right">{_fecha(datos['emitido_en'])}</td></tr>
    <tr><td style="color:#666">Sucursal</td><td style="text-align:right">{escape(datos['sucursal'])}</td></tr>
  </table>
  <table style="width:100%;font-size:14px;border-collapse:collapse">
    {''.join(filas_html)}
    <tr><td style="padding-top:10px"><b>Total (IVA 13% y envio incluidos)</b></td>
        <td style="padding-top:10px;text-align:right"><b>{_bs(datos['total'])}</b></td></tr>
  </table>
  <p style="font-size:13px;color:#555;margin-top:20px">
    Adjuntamos el comprobante en PDF. Si lo perdes, podes pedirlo de nuevo desde
    <b>Mis compras</b>, en la web o en la app.
  </p>
</div>"""
    return asunto, "\n".join(lineas_texto), html


async def enviar_comprobante(conn: asyncpg.Connection, venta_id: UUID) -> bool:
    """Manda el correo con el PDF adjunto al comprador. True si salio; en ese caso deja
    `correo_enviado_en`. False si falta el correo de la clienta, no hay proveedor de correo
    configurado o el proveedor fallo (ya queda en el log)."""
    datos = await cargar_datos(conn, venta_id)
    if datos is None or not datos["cliente_email"] or not correo_configurado():
        return False
    asunto, texto, html = armar_correo(datos)
    salio = await enviar_correo(
        datos["cliente_email"],
        asunto,
        texto,
        html,
        adjuntos=[(nombre_archivo(datos), generar_pdf(datos), "application/pdf")],
    )
    if salio:
        await conn.execute(
            "UPDATE comprobante SET correo_enviado_en = now() WHERE venta_id = $1", venta_id
        )
    else:
        log.warning("Comprobante %s: el correo a %s no salio", datos["comprobante"], datos["cliente_email"])
    return salio


def correo_enmascarado(correo: str) -> str:
    """`ana.perez@gmail.com` -> `an***@gmail.com`: confirma a donde fue sin exponer el correo
    completo en la respuesta."""
    usuario, _, dominio = correo.partition("@")
    return f"{usuario[:2]}***@{dominio}"
