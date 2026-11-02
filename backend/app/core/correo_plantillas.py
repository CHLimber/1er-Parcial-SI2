"""Cuerpo de los correos de FashionStore: HTML (tablas y estilos en linea, que es lo unico que
respetan Gmail/Outlook) y su version de texto plano de respaldo.

La paleta es la de la web (`frontend/src/styles.css`): --ink, --paper, --flame, --gold.
"""

from html import escape

INK = "#2e2530"
INK_SOFT = "#7a6b76"
PAPER = "#faf1ec"
FLAME = "#c1516b"
GOLD = "#c9a15f"
BLANCO = "#ffffff"

_FUENTE = "-apple-system,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif"


def _marco(preencabezado: str, contenido: str) -> str:
    """Estructura comun: franja de marca arriba, tarjeta blanca y pie. `preencabezado` es la
    linea que los clientes muestran junto al asunto en la bandeja de entrada."""
    return f"""<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light">
<title>FashionStore</title>
</head>
<body style="margin:0;padding:0;background:{PAPER};">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:{PAPER};">{escape(preencabezado)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:{PAPER};">
<tr><td align="center" style="padding:32px 16px;">
  <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="width:100%;max-width:560px;">
    <tr><td style="background:{INK};padding:28px 32px;border-radius:14px 14px 0 0;">
      <div style="font-family:{_FUENTE};font-size:22px;font-weight:700;letter-spacing:3px;color:{BLANCO};">FASHIONSTORE</div>
      <div style="font-family:{_FUENTE};font-size:12px;letter-spacing:2px;color:{GOLD};padding-top:4px;">MODA FEMENINA · BOLIVIA</div>
    </td></tr>
    <tr><td style="height:4px;background:{FLAME};line-height:4px;font-size:0;">&nbsp;</td></tr>
    <tr><td style="background:{BLANCO};padding:36px 32px 28px;border-radius:0 0 14px 14px;font-family:{_FUENTE};color:{INK};">
{contenido}
    </td></tr>
    <tr><td style="padding:20px 32px 0;font-family:{_FUENTE};font-size:12px;line-height:18px;color:{INK_SOFT};text-align:center;">
      Recibes este correo porque alguien pidió cambiar la contraseña de una cuenta de FashionStore con esta dirección.<br>
      © FashionStore · Bolivia
    </td></tr>
  </table>
</td></tr>
</table>
</body>
</html>"""


def correo_recuperacion(nombre: str, enlace: str, minutos: int) -> tuple[str, str, str]:
    """(asunto, texto, html) del correo de recuperacion de contrasena."""
    asunto = "Elige una contraseña nueva para tu cuenta de FashionStore"
    nombre_ok = (nombre or "").strip() or "hola"
    saludo = f"Hola, {nombre_ok}" if nombre_ok != "hola" else "Hola"
    enlace_html = escape(enlace, quote=True)

    texto = (
        f"{saludo}.\n\n"
        "Recibimos un pedido para elegir una contraseña nueva en tu cuenta de FashionStore.\n\n"
        f"Entra a este enlace (vence en {minutos} minutos y sirve una sola vez):\n"
        f"{enlace}\n\n"
        "Si no fuiste tú, ignora este correo: tu contraseña actual sigue funcionando y nadie "
        "puede entrar a tu cuenta solo con este mensaje.\n\n"
        "— El equipo de FashionStore"
    )

    contenido = f"""      <h1 style="margin:0 0 16px;font-size:24px;line-height:30px;font-weight:700;color:{INK};">{escape(saludo)} 👋</h1>
      <p style="margin:0 0 12px;font-size:16px;line-height:25px;color:{INK};">
        Recibimos un pedido para elegir una <strong>contraseña nueva</strong> en tu cuenta de FashionStore.
      </p>
      <p style="margin:0 0 28px;font-size:16px;line-height:25px;color:{INK};">
        Toca el botón para continuar. Por seguridad, el enlace <strong>vence en {minutos} minutos</strong>
        y solo sirve una vez.
      </p>
      <table role="presentation" cellpadding="0" cellspacing="0" align="center" style="margin:0 auto 28px;">
        <tr><td align="center" bgcolor="{FLAME}" style="border-radius:999px;">
          <a href="{enlace_html}" target="_blank"
             style="display:inline-block;padding:15px 36px;font-family:{_FUENTE};font-size:16px;font-weight:700;color:{BLANCO};text-decoration:none;border-radius:999px;background:{FLAME};border:1px solid {FLAME};">
            Elegir mi contraseña nueva
          </a>
        </td></tr>
      </table>
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 24px;">
        <tr><td style="background:{PAPER};border-left:3px solid {GOLD};padding:14px 16px;border-radius:6px;font-size:14px;line-height:21px;color:{INK};">
          <strong>¿No fuiste tú?</strong> Ignora este correo: tu contraseña actual sigue funcionando
          y nadie puede entrar a tu cuenta solo con este mensaje.
        </td></tr>
      </table>
      <p style="margin:0 0 6px;font-size:13px;line-height:19px;color:{INK_SOFT};">
        Si el botón no funciona, copia y pega este enlace en tu navegador:
      </p>
      <p style="margin:0;font-size:12px;line-height:18px;word-break:break-all;">
        <a href="{enlace_html}" target="_blank" style="color:{FLAME};text-decoration:underline;">{escape(enlace)}</a>
      </p>"""

    return asunto, texto, _marco(f"Tu enlace vence en {minutos} minutos y sirve una sola vez.", contenido)
