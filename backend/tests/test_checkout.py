"""POST /ventas/checkout sin Postgres ni Stripe (base falsa de tests/conexion_falsa.py y el
fixture stripe_falso de conftest.py):
  - al abandonar un intento Stripe viejo se lo cierra en Stripe, pero solo si el checkout nuevo
    se confirmo (si falla, el viejo tiene que seguir pagable);
  - abandonar el intento viejo y consumir el cupon van dentro de la transaccion, asi un checkout
    que falla despues (fuera de cobertura, total 0, ...) no se los lleva puestos;
  - un cupon que deja el pedido en Bs 0 da 422 y no un 500 del CHECK pago.monto > 0."""

from dataclasses import dataclass
from decimal import Decimal
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.core.db import get_connection
from app.core.deps import get_current_usuario
from app.main import app
from app.modules.ventas import router as ventas_router
from tests.conexion_falsa import ConexionFalsa

SUBTOTAL = Decimal("200.00")


def _promo(valor: str, tipo: str = "MONTO_FIJO") -> dict:
    return {
        "id": uuid4(), "tipo": tipo, "valor": Decimal(valor), "alcance": "TODO",
        "categoria_id": None, "temporada_id": None, "monto_minimo": None,
        "uso_maximo": 10, "usos_actuales": 0,
    }


def _conn_checkout(
    pasarela_pendiente: str | None = "STRIPE",
    id_transaccion: str | None = "cs_viejo",
    *,
    promo: dict | None = None,
    promo_pendiente: bool = False,
) -> ConexionFalsa:
    carrito, variante = uuid4(), uuid4()
    item = {
        "id": uuid4(), "variante_id": variante, "cantidad": 1,
        "precio_unitario": SUBTOTAL, "categoria_id": None, "temporada_id": None,
    }
    respuestas = {
        "FROM carrito WHERE usuario_id": {"id": carrito, "reserva_id": None},
        "FROM carrito_item ci": [item],
        "FROM carrito_item WHERE carrito_id": [item],
        "FROM sucursal WHERE id": {"id": uuid4()},
        "FROM direccion WHERE usuario_id": {"id": uuid4(), "latitud": -17.78, "longitud": -63.18},
        "FROM inventario": [{"variante_id": variante, "disponible": 5}],
        # intento viejo por otro monto (el carrito cambio): no se reusa, se abandona
        "LEFT JOIN promocion pr": {
            "venta_id": uuid4(), "numero": "V-VIEJA", "subtotal": Decimal("100.00"),
            "descuento": Decimal("0"), "costo_envio": Decimal("0"), "iva": Decimal("13.00"),
            "total": Decimal("113.00"), "estado": "PENDIENTE",
            "promocion_id": uuid4() if promo_pendiente else None,
            "sucursal_id": None, "entrega": "RETIRO_SUCURSAL", "direccion_id": None,
            "pago_id": uuid4(), "metodo": "PASARELA" if pasarela_pendiente else "EFECTIVO",
            "pasarela": pasarela_pendiente, "id_transaccion": id_transaccion,
            "informado_en": None, "codigo_cupon": None,
        },
        "UPDATE pago SET estado = 'RECHAZADO'": uuid4(),
        "FROM promocion": promo,
        "INSERT INTO venta": {
            "id": uuid4(), "numero": "V-NUEVA", "subtotal": SUBTOTAL,
            "descuento": Decimal("0"), "costo_envio": Decimal("0"), "iva": Decimal("26.00"),
            "total": Decimal("226.00"), "estado": "PENDIENTE",
        },
        "INSERT INTO pago": {"id": uuid4(), "pasarela": "STRIPE", "id_transaccion": "cs_nuevo"},
    }
    return ConexionFalsa(respuestas)


@dataclass
class _Cotizacion:
    dentro_cobertura: bool
    costo: Decimal = Decimal("15.00")
    distancia_km: float = 30.0
    radio_km: float = 12.0


@pytest.fixture
def checkout(monkeypatch):
    async def _sesion_nueva(venta_id, numero, total, *, canal):
        return "cs_nuevo", None, "secreto"

    monkeypatch.setattr(ventas_router, "_crear_sesion_stripe", _sesion_nueva)

    def enviar(conn: ConexionFalsa, **body):
        async def _conn():
            yield conn

        app.dependency_overrides[get_connection] = _conn
        app.dependency_overrides[get_current_usuario] = lambda: {"id": uuid4(), "tipo": "CLIENTE"}
        return TestClient(app, raise_server_exceptions=False).post(
            "/ventas/checkout",
            json={"sucursal_id": str(uuid4()), "metodo_pago": "STRIPE", **body},
        )

    yield enviar
    app.dependency_overrides.pop(get_connection, None)
    app.dependency_overrides.pop(get_current_usuario, None)


def _cotizar_con(monkeypatch, cotizacion: _Cotizacion) -> None:
    async def _cotizar(*args):
        return cotizacion

    monkeypatch.setattr(ventas_router, "cotizar", _cotizar)


# --- intento Stripe abandonado --------------------------------------------------------------------


@pytest.mark.parametrize(
    ("id_transaccion", "llamada"), [("cs_viejo", "expire"), ("pi_viejo", "cancel")]
)
def test_checkout_que_abandona_un_intento_stripe_lo_cierra_en_stripe(
    checkout, stripe_falso, id_transaccion, llamada
):
    conn = _conn_checkout("STRIPE", id_transaccion)
    respuesta = checkout(conn)
    assert respuesta.status_code == 201, respuesta.text
    assert conn.ejecuto("UPDATE pago SET estado = 'RECHAZADO'")
    assert stripe_falso[llamada] == [id_transaccion]


def test_checkout_que_abandona_un_pedido_en_efectivo_no_llama_a_stripe(checkout, stripe_falso):
    respuesta = checkout(_conn_checkout(None, None))
    assert respuesta.status_code == 201, respuesta.text
    assert stripe_falso["expire"] == [] and stripe_falso["cancel"] == []


# --- 4: todo dentro de la transaccion -----------------------------------------------------------


def test_abandono_y_cupon_corren_dentro_de_la_transaccion(checkout, stripe_falso):
    conn = _conn_checkout(promo=_promo("50.00"), promo_pendiente=True)
    respuesta = checkout(conn, codigo_cupon="VERANO")
    assert respuesta.status_code == 201, respuesta.text
    # si algo de esto quedara afuera, un checkout que falla despues no lo desharia
    assert conn.ejecuto_en_tx("UPDATE pago SET estado = 'RECHAZADO'")
    assert conn.ejecuto_en_tx("UPDATE venta SET estado = 'ANULADA'")
    assert conn.ejecuto_en_tx("usos_actuales - 1")  # devuelve el uso del intento viejo
    assert conn.ejecuto_en_tx("usos_actuales + 1")  # consume el uso del nuevo


def test_cupon_se_lee_con_for_update(checkout, stripe_falso):
    # sin el lock, dos checkouts simultaneos leian usos_actuales < uso_maximo y pasaban los dos
    conn = _conn_checkout(promo=_promo("50.00"))
    checkout(conn, codigo_cupon="VERANO")
    lecturas = [sql for sql in conn.ejecutado_en_tx if "FROM promocion" in sql]
    assert lecturas and all("FOR UPDATE" in sql for sql in lecturas)


def test_fuera_de_cobertura_no_cierra_el_intento_viejo(checkout, stripe_falso, monkeypatch):
    # el checkout nuevo falla: la transaccion se deshace (el intento viejo vuelve a PENDIENTE y
    # el cupon a su uso anterior) y el intento viejo tiene que seguir pagable en Stripe
    _cotizar_con(monkeypatch, _Cotizacion(dentro_cobertura=False))
    conn = _conn_checkout(promo=_promo("50.00"))
    respuesta = checkout(conn, entrega="DOMICILIO", codigo_cupon="VERANO")
    assert respuesta.status_code == 422
    assert "reparto llega hasta" in respuesta.json()["detail"]
    assert conn.ejecuto_en_tx("UPDATE pago SET estado = 'RECHAZADO'")
    assert conn.ejecuto_en_tx("usos_actuales + 1")
    assert stripe_falso["expire"] == [] and stripe_falso["cancel"] == []
    assert not conn.ejecuto("INSERT INTO venta")


# --- 5: cupon que cubre todo el pedido ------------------------------------------------------------


@pytest.mark.parametrize("promo", [_promo("500.00"), _promo("100", tipo="PORCENTAJE")])
def test_cupon_que_deja_el_pedido_en_cero_devuelve_422(checkout, stripe_falso, promo):
    conn = _conn_checkout(promo=promo)
    respuesta = checkout(conn, codigo_cupon="GRATIS")
    assert respuesta.status_code == 422
    assert "Bs 0" in respuesta.json()["detail"]
    assert not conn.ejecuto("INSERT INTO venta")
    assert not conn.ejecuto("INSERT INTO pago")
    assert stripe_falso["expire"] == []  # el intento viejo sigue pagable


def test_cupon_total_con_envio_a_domicilio_cobra_solo_el_envio(checkout, stripe_falso, monkeypatch):
    # las prendas quedan gratis pero el flete no: hay algo que cobrar, el checkout sigue
    _cotizar_con(monkeypatch, _Cotizacion(dentro_cobertura=True, costo=Decimal("15.00")))
    conn = _conn_checkout(promo=_promo("500.00"))
    respuesta = checkout(conn, entrega="DOMICILIO", codigo_cupon="GRATIS")
    assert respuesta.status_code == 201, respuesta.text
    assert conn.ejecuto("INSERT INTO pago")
