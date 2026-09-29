"""Reintegro de devoluciones (Stripe parcial por la API, metodo segun el pago) y entrega de pedidos
online en caja. Sin Postgres ni Stripe (tests/conexion_falsa.py y stripe_falso de conftest). El
flujo completo contra Postgres real (efectivo + arqueo, plazo, cambio, reportes netos) se probo
de punta a punta; ver PENDIENTES 4.11."""

from datetime import datetime, timezone
from decimal import Decimal
from uuid import uuid4

import pytest
import stripe
from fastapi.testclient import TestClient

from app.core.db import get_connection
from app.core.deps import get_cajero_actual
from app.main import app
from app.modules.devoluciones import router as devoluciones_router
from app.modules.pagos import servicio
from tests.conexion_falsa import ConexionFalsa

SUCURSAL = uuid4()
DEVOLUCION = uuid4()
VENTA = uuid4()
ADMIN = {"id": uuid4(), "permisos": ["sucursales.actualizar"], "sucursal_id": None}


@pytest.fixture
def cliente():
    def usar(conn: ConexionFalsa, overrides: dict) -> TestClient:
        async def _conn():
            yield conn

        app.dependency_overrides[get_connection] = _conn
        app.dependency_overrides.update(overrides)
        return TestClient(app, raise_server_exceptions=False)

    yield usar
    app.dependency_overrides.clear()


# --- como vuelve la plata ------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("metodo", "pasarela", "esperado"),
    [
        ("PASARELA", "STRIPE", "STRIPE"),
        ("PASARELA", "QR", "QR"),
        ("EFECTIVO", None, "EFECTIVO"),
        ("TARJETA", None, "TARJETA"),
        ("TRANSFERENCIA", None, "TRANSFERENCIA"),
    ],
)
def test_el_reintegro_vuelve_por_donde_entro_la_plata(metodo, pasarela, esperado):
    pago = {"metodo": metodo, "pasarela": pasarela, "id_transaccion": None}
    assert devoluciones_router._metodo_reintegro(pago) == esperado


def test_sin_pago_aprobado_no_hay_metodo_de_reintegro():
    assert devoluciones_router._metodo_reintegro(None) is None


async def test_reembolso_parcial_pide_el_monto_en_centavos_con_clave_idempotente(monkeypatch):
    llamadas = []
    monkeypatch.setattr(
        stripe.checkout.Session, "retrieve", lambda cs: {"payment_intent": "pi_de_" + cs}
    )

    def _crear(**kwargs):
        llamadas.append(kwargs)
        return {"id": "re_123"}

    monkeypatch.setattr(stripe.Refund, "create", _crear)
    referencia = await servicio.reembolsar_parcial_stripe(
        "cs_web", Decimal("372.79"), "devolucion-abc"
    )
    assert referencia == "re_123"
    assert llamadas == [
        {"payment_intent": "pi_de_cs_web", "amount": 37279, "idempotency_key": "devolucion-abc"}
    ]


# --- aprobar una devolucion pagada con Stripe ----------------------------------------------------


def _devolucion_out() -> dict:
    ahora = datetime.now(timezone.utc)
    return {
        "id": DEVOLUCION, "venta_id": VENTA, "venta_numero": "V-TEST",
        "venta_total": Decimal("226.00"), "sucursal_id": SUCURSAL, "sucursal": "Equipetrol",
        "cliente": "Ana Perez", "motivo": "No le quedo", "monto_devuelto": Decimal("113.00"),
        "estado": "APROBADA", "fecha": ahora, "registrada_por": "Admin", "resuelta_por": "Admin",
        "resuelta_en": ahora, "motivo_rechazo": None, "reintegro_metodo": "STRIPE",
        "reintegro_referencia": "re_123", "venta_cambio_id": None, "venta_cambio_numero": None,
        "lineas": 1, "unidades": 1,
    }


def _conn_aprobar(pago: dict) -> ConexionFalsa:
    return ConexionFalsa(
        {
            "FROM devolucion d JOIN venta v": {
                "id": DEVOLUCION, "venta_id": VENTA, "sucursal_id": SUCURSAL,
                "estado": "SOLICITADA", "monto_devuelto": Decimal("113.00"), "venta_numero": "V-TEST",
            },
            # quedan unidades sin devolver: devolucion parcial
            "SELECT (SELECT COALESCE(SUM(cantidad), 0) FROM venta_detalle": 1,
            "v.total - v.costo_envio AS mercaderia": {
                "mercaderia": Decimal("226.00"), "suma_lineas": Decimal("200.00"),
            },
            "SUM(dd.cantidad * vd.subtotal / vd.cantidad)": Decimal("100.00"),
            "FROM pago WHERE venta_id = $1 AND estado = 'APROBADO'": pago,
            "FROM devolucion d\nJOIN venta v": _devolucion_out(),
            "estado = 'REEMBOLSADO')": False,
        }
    )


def _aprobar(cliente, conn: ConexionFalsa):
    return cliente(conn, {devoluciones_router.puede_resolver: lambda: ADMIN}).post(
        f"/devoluciones/{DEVOLUCION}/aprobar"
    )


def test_aprobar_devolucion_pagada_con_stripe_reembolsa_por_la_api(cliente, monkeypatch):
    llamadas = []

    async def _reembolsar(id_transaccion, monto, clave):
        llamadas.append((id_transaccion, monto, clave))
        return "re_123"

    monkeypatch.setattr(devoluciones_router, "reembolsar_parcial_stripe", _reembolsar)
    conn = _conn_aprobar({"metodo": "PASARELA", "pasarela": "STRIPE", "id_transaccion": "pi_1"})
    respuesta = _aprobar(cliente, conn)
    assert respuesta.status_code == 200, respuesta.text
    # 100 de lista sobre 200 -> la mitad de lo que se pago por la mercaderia (226)
    assert llamadas == [("pi_1", Decimal("113.00"), f"devolucion-{DEVOLUCION}")]
    assert conn.args_de("SET estado = 'APROBADA'")[3] == "STRIPE"
    assert conn.args_de("SET reintegro_referencia") == (DEVOLUCION, "re_123")


def test_si_stripe_rechaza_el_reembolso_la_aprobacion_da_502(cliente, monkeypatch):
    async def _falla(*args):
        raise stripe.error.InvalidRequestError("charge ya reembolsado", None)

    monkeypatch.setattr(devoluciones_router, "reembolsar_parcial_stripe", _falla)
    conn = _conn_aprobar({"metodo": "PASARELA", "pasarela": "STRIPE", "id_transaccion": "pi_1"})
    respuesta = _aprobar(cliente, conn)
    assert respuesta.status_code == 502
    assert "sigue pendiente" in respuesta.json()["detail"]
    # la HTTPException sale de adentro de la transaccion: en Postgres se deshace todo
    assert conn.ejecuto_en_tx("SET estado = 'APROBADA'")
    assert not conn.ejecuto("SET reintegro_referencia")


def test_aprobar_devolucion_con_tarjeta_de_caja_no_llama_a_stripe(cliente, monkeypatch):
    async def _no_deberia(*args):
        raise AssertionError("no se tiene que llamar a Stripe")

    monkeypatch.setattr(devoluciones_router, "reembolsar_parcial_stripe", _no_deberia)
    conn = _conn_aprobar({"metodo": "TARJETA", "pasarela": None, "id_transaccion": None})
    respuesta = _aprobar(cliente, conn)
    assert respuesta.status_code == 200, respuesta.text
    assert conn.args_de("SET estado = 'APROBADA'")[3] == "TARJETA"


# --- entregar pedidos online en caja ------------------------------------------------------------


def _entregar(cliente, venta: dict | None):
    conn = ConexionFalsa({"FROM venta\n            WHERE id = $1 AND sucursal_id = $2": venta})
    respuesta = cliente(
        conn, {get_cajero_actual: lambda: {"usuario_id": uuid4(), "sucursal_id": SUCURSAL}}
    ).post(f"/caja/pedidos/{VENTA}/entregar")
    return respuesta, conn


def test_entregar_pedido_online_pagado_lo_pasa_a_entregada(cliente):
    respuesta, conn = _entregar(
        cliente,
        {"id": VENTA, "numero": "V-1", "estado": "PAGADA", "entrega": "RETIRO_SUCURSAL", "canal": "WEB"},
    )
    assert respuesta.status_code == 200, respuesta.text
    assert respuesta.json()["venta_estado"] == "ENTREGADA"
    assert conn.ejecuto_en_tx("SET estado = 'ENTREGADA'")


@pytest.mark.parametrize(
    "venta",
    [
        {"estado": "ENTREGADA", "entrega": "RETIRO_SUCURSAL", "canal": "WEB"},  # doble click
        {"estado": "PENDIENTE", "entrega": "RETIRO_SUCURSAL", "canal": "MOVIL"},  # sin pagar
        {"estado": "PAGADA", "entrega": "DOMICILIO", "canal": "WEB"},  # lo lleva el delivery
        {"estado": "ENTREGADA", "entrega": "RETIRO_SUCURSAL", "canal": "POS"},  # mostrador
    ],
)
def test_entregar_rechaza_lo_que_no_es_un_pedido_online_pagado_con_retiro(cliente, venta):
    respuesta, conn = _entregar(cliente, {"id": VENTA, "numero": "V-1", **venta})
    assert respuesta.status_code == 409
    assert not conn.ejecuto("SET estado = 'ENTREGADA'")


def test_entregar_pedido_de_otra_sucursal_es_404(cliente):
    respuesta, _ = _entregar(cliente, None)
    assert respuesta.status_code == 404
