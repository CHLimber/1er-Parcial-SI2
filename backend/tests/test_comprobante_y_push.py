"""Comprobante en PDF, correo de compra y mensaje push: piezas puras, sin Postgres ni red."""

from datetime import datetime, timezone
from decimal import Decimal

from app.core import push
from app.core.comprobante import (
    armar_correo,
    correo_enmascarado,
    generar_pdf,
    nombre_archivo,
)


def _datos(**cambios) -> dict:
    datos = {
        "numero": "V-ABC123",
        "comprobante": "C-0123456789",
        "emitido_en": datetime(2026, 11, 2, 17, 30, tzinfo=timezone.utc),
        "empresa": "FashionStore",
        "razon_social": "FashionStore S.R.L.",
        "nit": "1023456022",
        "sucursal": "FashionStore Equipetrol",
        "cliente": "Ana Perez",
        "cliente_email": "ana.perez@gmail.com",
        "entrega": "RETIRO_SUCURSAL",
        "nit_cliente": None,
        "razon_cliente": None,
        "subtotal": Decimal("120.00"),
        "descuento": Decimal("0"),
        "costo_envio": Decimal("0"),
        "iva": Decimal("15.60"),
        "total": Decimal("135.60"),
        "pago": {"metodo": "TARJETA", "pasarela": "STRIPE", "estado": "APROBADO"},
        "items": [
            {
                "producto": "Vestido <floral>",
                "talla": "M",
                "color": "Rojo",
                "cantidad": 2,
                "precio_unitario": Decimal("60.00"),
                "subtotal": Decimal("120.00"),
            }
        ],
    }
    datos.update(cambios)
    return datos


def test_pdf_es_un_pdf_valido():
    contenido = generar_pdf(_datos())
    assert contenido.startswith(b"%PDF")
    assert len(contenido) > 1000


def test_pdf_no_se_rompe_con_caracteres_fuera_de_latin1():
    # emoji y alfabeto no latino: las fuentes base de PDF no los tienen
    datos = _datos()
    datos["items"][0]["producto"] = "Vestido \U0001F457 \u4e2d\u6587"
    assert generar_pdf(datos).startswith(b"%PDF")


def test_pdf_con_envio_descuento_y_consumidor_final():
    datos = _datos(
        cliente=None,
        descuento=Decimal("10.00"),
        costo_envio=Decimal("20.00"),
        entrega="DOMICILIO",
        nit_cliente="123",
        razon_cliente="Mi Empresa",
    )
    assert generar_pdf(datos).startswith(b"%PDF")


def test_nombre_del_archivo_lleva_el_numero_de_comprobante():
    assert nombre_archivo(_datos()) == "comprobante-C-0123456789.pdf"


def test_correo_resume_la_compra():
    asunto, texto, html = armar_correo(_datos())
    assert "C-0123456789" in asunto
    assert "Hola Ana" in texto
    assert "Bs 135.60" in texto
    # la hora se muestra en Bolivia (UTC-4): 17:30 UTC -> 13:30
    assert "02/11/2026 13:30" in texto


def test_correo_html_escapa_el_contenido():
    _, _, html = armar_correo(_datos())
    assert "<floral>" not in html
    assert "&lt;floral&gt;" in html


def test_correo_enmascarado():
    assert correo_enmascarado("ana.perez@gmail.com") == "an***@gmail.com"


def test_mensaje_fcm_lleva_canal_y_datos_como_texto():
    mensaje = push.armar_mensaje(
        "tok", "Pago aprobado", "Tu pedido", {"entidad_id": 5, "nada": None, "tipo": "VENTA"}
    )["message"]
    assert mensaje["token"] == "tok"
    assert mensaje["notification"] == {"title": "Pago aprobado", "body": "Tu pedido"}
    assert mensaje["data"] == {"entidad_id": "5", "tipo": "VENTA"}
    assert mensaje["android"]["notification"]["channel_id"] == push.CANAL_ANDROID


def test_push_apagado_sin_credenciales():
    push._credenciales.cache_clear()
    assert push.push_configurado() is False
