"""Comprobante de devolucion o intercambio por correo (PDF adjunto), espejo de comprobante.py.

Lo manda el job de avisos (core/avisos.py) cuando una devolucion pasa a APROBADA, igual que el de
compra: solo ve filas ya confirmadas, reclama cada una con FOR UPDATE SKIP LOCKED y reintenta
hasta MAX_INTENTOS_CORREO. Va a la clienta de la venta; una venta de mostrador sin clienta
identificada no tiene a quien mandarselo.
"""

import logging
from decimal import Decimal
from html import escape
from uuid import UUID

import asyncpg
from fpdf import FPDF

from app.core.comprobante import _bs, _fecha, _l1
from app.core.correo import correo_configurado, enviar_correo

log = logging.getLogger(__name__)

_CONSULTA = """
    SELECT d.id, d.numero, d.tipo, d.origen, d.motivo, d.motivo_tipo::text AS motivo_tipo,
           d.resuelta_en, d.monto_devuelto, d.monto_cambio, d.monto_reintegrado,
           d.diferencia_cobrada, d.diferencia_metodo, d.reintegro_metodo,
           v.numero AS venta_numero, v.fecha AS venta_fecha, vc.numero AS venta_cambio_numero,
           s.nombre AS sucursal, e.nombre AS empresa, e.razon_social, e.nit,
           u.nombre || ' ' || u.apellido AS cliente, u.email AS cliente_email
    FROM devolucion d
    JOIN venta v       ON v.id = d.venta_id
    JOIN sucursal s    ON s.id = d.sucursal_id
    JOIN empresa e     ON e.id = s.empresa_id
    LEFT JOIN usuario u ON u.id = v.usuario_id
    LEFT JOIN venta vc ON vc.id = d.venta_cambio_id
    WHERE d.id = $1
"""

_CONSULTA_LINEAS = """
    SELECT pr.nombre AS producto, t.codigo AS talla, c.nombre AS color, dd.cantidad,
           ts.codigo AS talla_nueva, cs.nombre AS color_nuevo, dd.precio_solicitado
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
    ORDER BY pr.nombre, t.orden
"""

_MEDIO = {
    "STRIPE": "a la tarjeta con la que pagaste (Stripe)",
    "EFECTIVO": "en efectivo en la sucursal",
    "QR": "en efectivo en la sucursal",
    "TARJETA": "a la tarjeta con la que pagaste",
    "TRANSFERENCIA": "por transferencia",
}


async def cargar_datos(conn: asyncpg.Connection, devolucion_id: UUID) -> dict | None:
    fila = await conn.fetchrow(_CONSULTA, devolucion_id)
    if fila is None:
        return None
    datos = dict(fila)
    datos["lineas"] = [dict(f) for f in await conn.fetch(_CONSULTA_LINEAS, devolucion_id)]
    return datos


def _titulo(datos: dict) -> str:
    return "INTERCAMBIO" if datos["tipo"] == "INTERCAMBIO" else "DEVOLUCION"


def _resumen_plata(datos: dict) -> list[tuple[str, Decimal]]:
    filas = [("Valor de lo devuelto", datos["monto_devuelto"])]
    if datos["tipo"] == "INTERCAMBIO":
        filas.append(("Valor de lo nuevo", datos["monto_cambio"]))
        if datos["diferencia_cobrada"]:
            filas.append(("Pagaste de diferencia", datos["diferencia_cobrada"]))
    if datos["monto_reintegrado"]:
        filas.append(("Te devolvimos", datos["monto_reintegrado"]))
    return filas


def _lineas_texto(datos: dict) -> list[str]:
    salida = []
    for linea in datos["lineas"]:
        texto = f"{linea['cantidad']} x {linea['producto']} ({linea['color']}, talla {linea['talla']})"
        if linea["talla_nueva"]:
            texto += f" -> {linea['color_nuevo']}, talla {linea['talla_nueva']}"
        salida.append(texto)
    return salida


def generar_pdf(datos: dict) -> bytes:
    pdf = FPDF(format="A4", unit="mm")
    pdf.set_auto_page_break(auto=True, margin=15)
    pdf.add_page()
    ancho = pdf.w - pdf.l_margin - pdf.r_margin

    pdf.set_font("Helvetica", "B", 18)
    pdf.cell(ancho, 9, _l1(datos["empresa"]), new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 9)
    pdf.set_text_color(90, 90, 90)
    pdf.cell(ancho, 5, _l1(f"{datos['razon_social']}  -  NIT {datos['nit']}"), new_x="LMARGIN", new_y="NEXT")
    pdf.cell(ancho, 5, _l1(f"Sucursal {datos['sucursal']}"), new_x="LMARGIN", new_y="NEXT")
    pdf.set_text_color(0, 0, 0)
    pdf.ln(4)

    pdf.set_font("Helvetica", "B", 13)
    pdf.cell(ancho, 7, f"COMPROBANTE DE {_titulo(datos)}", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 10)
    filas = [
        ("Nota", datos["numero"]),
        ("Fecha", _fecha(datos["resuelta_en"])),
        ("Compra original", f"{datos['venta_numero']} ({_fecha(datos['venta_fecha'])})"),
        ("Cliente", datos["cliente"] or "-"),
        ("Motivo", datos["motivo"]),
    ]
    if datos["venta_cambio_numero"]:
        filas.append(("Compra del cambio", datos["venta_cambio_numero"]))
    for etiqueta, valor in filas:
        pdf.set_font("Helvetica", "B", 10)
        pdf.cell(40, 6, _l1(etiqueta))
        pdf.set_font("Helvetica", "", 10)
        pdf.cell(ancho - 40, 6, _l1(valor), new_x="LMARGIN", new_y="NEXT")
    pdf.ln(4)

    pdf.set_fill_color(30, 30, 30)
    pdf.set_text_color(255, 255, 255)
    pdf.set_font("Helvetica", "B", 9)
    pdf.cell(ancho, 7, "Prendas" + (" (devuelta -> nueva)" if datos["tipo"] == "INTERCAMBIO" else ""), fill=True)
    pdf.ln()
    pdf.set_text_color(0, 0, 0)
    pdf.set_font("Helvetica", "", 9)
    for texto in _lineas_texto(datos):
        pdf.cell(ancho, 7, _l1(texto)[:110], border="B", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(3)

    for etiqueta, monto in _resumen_plata(datos):
        pdf.set_font("Helvetica", "", 10)
        pdf.cell(ancho - 45, 6, etiqueta, align="R")
        pdf.cell(45, 6, _bs(monto), align="R", new_x="LMARGIN", new_y="NEXT")
    if datos["monto_reintegrado"] and datos["reintegro_metodo"]:
        pdf.set_font("Helvetica", "I", 9)
        pdf.cell(ancho, 6, _l1(f"Reintegro {_MEDIO.get(datos['reintegro_metodo'], '')}"), align="R",
                 new_x="LMARGIN", new_y="NEXT")

    pdf.ln(8)
    pdf.set_font("Helvetica", "I", 8)
    pdf.set_text_color(110, 110, 110)
    pdf.multi_cell(ancho, 4, _l1("Montos con IVA (13%) incluido. Cada compra admite una sola devolucion o intercambio."))
    return bytes(pdf.output())


def armar_correo(datos: dict) -> tuple[str, str, str]:
    nombre = (datos["cliente"] or "").split(" ")[0] or "hola"
    que = "intercambio" if datos["tipo"] == "INTERCAMBIO" else "devolucion"
    asunto = f"Comprobante de {que} {datos['numero']} - {datos['empresa']}"
    plata = [f"{etiqueta}: {_bs(monto)}" for etiqueta, monto in _resumen_plata(datos)]
    if datos["monto_reintegrado"] and datos["reintegro_metodo"]:
        plata.append(f"El reintegro va {_MEDIO.get(datos['reintegro_metodo'], '')}.")
    texto = "\n".join(
        [
            f"Hola {nombre}, registramos el {que} de tu compra {datos['venta_numero']}.",
            "",
            f"Nota: {datos['numero']}",
            f"Fecha: {_fecha(datos['resuelta_en'])}",
            f"Sucursal: {datos['sucursal']}",
            "",
            *[f"- {linea}" for linea in _lineas_texto(datos)],
            "",
            *plata,
            "",
            "Adjuntamos el comprobante en PDF.",
        ]
    )
    filas_lineas = "".join(
        f"<li style='margin:4px 0'>{escape(linea)}</li>" for linea in _lineas_texto(datos)
    )
    filas_plata = "".join(
        f"<tr><td style='color:#666'>{escape(etiqueta)}</td>"
        f"<td style='text-align:right'><b>{_bs(monto)}</b></td></tr>"
        for etiqueta, monto in _resumen_plata(datos)
    )
    nota_medio = ""
    if datos["monto_reintegrado"] and datos["reintegro_metodo"]:
        nota_medio = f"<p style='font-size:13px;color:#555'>El reintegro va {escape(_MEDIO.get(datos['reintegro_metodo'], ''))}.</p>"
    html = f"""\
<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:auto;color:#1c1c1c">
  <h2 style="margin:0 0 4px">{escape(datos['empresa'])}</h2>
  <p style="margin:0 0 16px;color:#666">Hola {escape(nombre)}, registramos el {que} de tu compra
     <b>{escape(datos['venta_numero'])}</b>.</p>
  <table style="width:100%;font-size:14px;margin-bottom:12px">
    <tr><td style="color:#666">Nota</td><td style="text-align:right"><b>{escape(datos['numero'])}</b></td></tr>
    <tr><td style="color:#666">Fecha</td><td style="text-align:right">{_fecha(datos['resuelta_en'])}</td></tr>
    <tr><td style="color:#666">Sucursal</td><td style="text-align:right">{escape(datos['sucursal'])}</td></tr>
  </table>
  <ul style="font-size:14px;padding-left:18px">{filas_lineas}</ul>
  <table style="width:100%;font-size:14px;border-top:1px solid #eee;padding-top:8px">{filas_plata}</table>
  {nota_medio}
  <p style="font-size:13px;color:#555;margin-top:20px">Adjuntamos el comprobante en PDF.</p>
</div>"""
    return asunto, texto, html


async def enviar_comprobante_devolucion(conn: asyncpg.Connection, devolucion_id: UUID) -> bool:
    """True si el correo salio (y deja correo_enviado_en)."""
    datos = await cargar_datos(conn, devolucion_id)
    if datos is None or not datos["cliente_email"] or not correo_configurado():
        return False
    asunto, texto, html = armar_correo(datos)
    salio = await enviar_correo(
        datos["cliente_email"],
        asunto,
        texto,
        html,
        adjuntos=[(f"{datos['numero']}.pdf", generar_pdf(datos), "application/pdf")],
    )
    if salio:
        await conn.execute("UPDATE devolucion SET correo_enviado_en = now() WHERE id = $1", devolucion_id)
    else:
        log.warning("Devolucion %s: el correo no salio", datos["numero"])
    return salio
