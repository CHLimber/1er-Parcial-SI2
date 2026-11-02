"""Cobro con tarjeta (Stripe) de una reserva atendida en el vestidor (PENDIENTES 11). Sin Postgres
ni Stripe real: conexion_falsa y monkeypatch de las llamadas a Stripe."""

from decimal import Decimal
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.core.db import get_connection
from app.core.deps import get_encargado_actual
from app.main import app
from app.modules.operacion_comercial.reservas import router as reservas_router
from tests.conexion_falsa import EMPRESA, ConexionFalsa

RESERVA = uuid4()
SUCURSAL = uuid4()
VARIANTE = uuid4()
VENTA = uuid4()
ENCARGADO = {"usuario_id": uuid4(), "sucursal_id": SUCURSAL, "empresa_id": EMPRESA}


def _reserva(estado="CLIENTE_PRESENTE") -> dict:
    return {"id": RESERVA, "sucursal_id": SUCURSAL, "estado": estado, "usuario_id": uuid4()}


@pytest.fixture
def cliente():
    def usar(conn: ConexionFalsa) -> TestClient:
        async def _conn():
            yield conn

        app.dependency_overrides[get_connection] = _conn
        app.dependency_overrides[get_encargado_actual] = lambda: ENCARGADO
        return TestClient(app, raise_server_exceptions=False)

    yield usar
    app.dependency_overrides.clear()


def _cobro_pendiente(id_transaccion="cs_123") -> dict:
    return {
        "venta_id": VENTA, "numero": "V-1", "total": Decimal("113.00"), "venta_estado": "PENDIENTE",
        "carrito_id": uuid4(), "promocion_id": None, "pago_id": uuid4(), "pago_estado": "PENDIENTE",
        "id_transaccion": id_transaccion, "comprobante_numero": None,
    }


def test_sin_prendas_compradas_no_hay_nada_que_cobrar(cliente):
    conn = ConexionFalsa({
        "FROM reserva r": _reserva(),
        "WHERE rd.reserva_id = $1 AND rd.estado_item = 'PREPARADO'": [
            {"variante_id": VARIANTE, "cantidad": 1, "precio": Decimal("100")}
        ],
    })
    respuesta = cliente(conn).post(
        f"/reservas/{RESERVA}/cobro-stripe",
        json={"decisiones": [{"variante_id": str(VARIANTE), "comprado": False}]},
    )
    assert respuesta.status_code == 422
    assert not conn.ejecuto("INSERT INTO venta")


def test_la_reserva_tiene_que_estar_en_el_vestidor(cliente):
    conn = ConexionFalsa({"FROM reserva r": _reserva("PREPARADA")})
    respuesta = cliente(conn).post(
        f"/reservas/{RESERVA}/cobro-stripe",
        json={"decisiones": [{"variante_id": str(VARIANTE), "comprado": True}]},
    )
    assert respuesta.status_code == 409


def test_iniciar_arma_venta_pendiente_y_devuelve_el_client_secret(cliente, monkeypatch):
    async def _sesion(venta_id, numero, total, *, canal):
        assert total == Decimal("113.00") and canal == "WEB"
        return "cs_nuevo", None, "secreto_cs"

    monkeypatch.setattr(reservas_router, "_crear_sesion_stripe", _sesion)
    conn = ConexionFalsa({
        "FROM reserva r": _reserva(),
        "WHERE rd.reserva_id = $1 AND rd.estado_item = 'PREPARADO'": [
            {"variante_id": VARIANTE, "cantidad": 1, "precio": Decimal("100")}
        ],
        "WHERE v.reserva_id = $1 AND v.canal = 'POS'": None,
        "SELECT EXISTS (SELECT 1 FROM venta WHERE reserva_id": False,
        "INSERT INTO carrito (session_anonima": uuid4(),
        "INSERT INTO venta (sucursal_id, usuario_id, canal": VENTA,
    })
    respuesta = cliente(conn).post(
        f"/reservas/{RESERVA}/cobro-stripe",
        json={"decisiones": [{"variante_id": str(VARIANTE), "comprado": True}]},
    )
    assert respuesta.status_code == 200, respuesta.text
    cuerpo = respuesta.json()
    assert cuerpo["estado"] == "PENDIENTE" and cuerpo["client_secret"] == "secreto_cs"
    assert conn.args_de("INSERT INTO pago")[1:] == (Decimal("113.00"), "cs_nuevo")


def test_si_stripe_ya_cobro_el_estado_lo_aprueba_sin_esperar_el_webhook(cliente, monkeypatch):
    llamadas = []

    async def _ya_cobro(id_transaccion):
        return True

    async def _procesar(conn, **kwargs):
        llamadas.append(kwargs)

    monkeypatch.setattr(reservas_router, "_stripe_ya_cobro", _ya_cobro)
    monkeypatch.setattr(reservas_router, "_procesar_evento", _procesar)
    conn = ConexionFalsa({
        "FROM reserva r": _reserva(),
        "WHERE v.reserva_id = $1 AND v.canal = 'POS'": _cobro_pendiente(),
    })
    respuesta = cliente(conn).get(f"/reservas/{RESERVA}/cobro-stripe")
    assert respuesta.status_code == 200, respuesta.text
    assert llamadas and llamadas[0]["aprobado"] is True
    assert llamadas[0]["id_transaccion"] == "cs_123"


def test_cancelar_sin_cobro_pendiente_no_hace_nada(cliente):
    conn = ConexionFalsa({"FROM reserva r": _reserva(), "WHERE v.reserva_id = $1 AND v.canal = 'POS'": None})
    respuesta = cliente(conn).post(f"/reservas/{RESERVA}/cobro-stripe/cancelar")
    assert respuesta.status_code == 200
    assert respuesta.json()["estado"] == "SIN_COBRO"
    assert not conn.ejecuto("SET estado = 'RECHAZADO'")
