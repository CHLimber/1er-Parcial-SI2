"""QR de la URL publica para la defensa del Segundo parcial (PENDIENTES 5.15).

Uso:
    pip install "qrcode[pil]"
    python scripts/generar_qr.py https://<url-publica-del-frontend> [salida.png]

Genera un PNG con el QR y la URL escrita abajo (por si la camara no lo lee en el proyector).
"""

import sys

import qrcode
from PIL import Image, ImageDraw, ImageFont

if len(sys.argv) < 2:
    sys.exit(__doc__)

url = sys.argv[1]
salida = sys.argv[2] if len(sys.argv) > 2 else "qr_defensa.png"

qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=12, border=3)
qr.add_data(url)
qr.make(fit=True)
imagen = qr.make_image(fill_color="#2e2530", back_color="white").convert("RGB")

ancho, alto = imagen.size
lienzo = Image.new("RGB", (ancho, alto + 70), "white")
lienzo.paste(imagen, (0, 0))
dibujo = ImageDraw.Draw(lienzo)
try:
    fuente = ImageFont.truetype("arial.ttf", 22)
except OSError:
    fuente = ImageFont.load_default()
caja = dibujo.textbbox((0, 0), url, font=fuente)
dibujo.text(((ancho - (caja[2] - caja[0])) / 2, alto + 20), url, fill="#2e2530", font=fuente)
lienzo.save(salida)
print(f"QR guardado en {salida} -> {url}")
