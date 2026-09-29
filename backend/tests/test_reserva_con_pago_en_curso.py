"""Doble venta / doble liberacion de stock cuando una reserva se atiende en el vestidor mientras
la clienta la esta pagando online (carrito armado desde la reserva, venta PENDIENTE con
venta.reserva_id). Sin Postgres: una conexion falsa responde segun el SQL que recibe y anota
todo lo que se ejecuta, para comprobar que no se toca stock."""

from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.core.db import get_connection
from app.core.deps import get_encargado_actual
from app.main import app
from app.modules.pagos import servicio
from tests.conexion_falsa import ConexionFalsa as _ConexionBase

SUCURSAL = uuid4()
RESERVA = uuid4()
VARIANTE = uuid4()


class ConexionFalsa(_ConexionBase):
    def toco_stock(self) -> bool:
        return self.ejecuto("INSERT INTO venta_detalle") or self.ejecuto("LIBERACION")


def _reserva(estado: str) -> dict:
    return {"id": RESERVA, "sucursal_id": SUCURSAL, "estado": estado, "usuario_id": uuid4()}


@pytest.fixture
def cliente_encargado():
    conexiones: list[ConexionFalsa] = []

    def usar(conn: ConexionFalsa) -> TestClient:
        conexiones.append(conn)

        async def _conn():
            yield conn

        app.dependency_overrides[get_connection] = _conn
        app.dependency_overrides[get_encargado_actual] = lambda: {
            "usuario_id": uuid4(),
            "sucursal_id": SUCURSAL,
        }
        return TestClient(app, raise_server_exceptions=False)

    yield usar
    app.dependency_overrides.pop(get_connection, None)
    app.dependency_overrides.pop(get_encargado_actual, None)


def test_resolver_reserva_con_pago_online_pendiente_devuelve_409_sin_vender(cliente_encargado):
    conn = ConexionFalsa(
        {
            "FROM reserva r": _reserva("CLIENTE_PRESENTE"),
            "FROM venta WHERE reserva_id": True,
        }
    )
    respuesta = cliente_encargado(conn).post(
        f"/reservas/{RESERVA}/resolver",
        json={
            "decisiones": [{"variante_id": str(VARIANTE), "comprado": True}],
            "metodo_pago": "EFECTIVO",
        },
    )
    assert respuesta.status_code == 409
    assert "pago en curso" in respuesta.json()["detail"]
    assert not conn.toco_stock()
    assert not any("UPDATE reserva" in sql for sql in conn.ejecutado)


def test_preparar_reserva_con_pago_online_pendiente_devuelve_409_sin_liberar(cliente_encargado):
    conn = ConexionFalsa(
        {
            "FROM reserva r": _reserva("CONFIRMADA"),
            "FROM venta WHERE reserva_id": True,
        }
    )
    respuesta = cliente_encargado(conn).post(
        f"/reservas/{RESERVA}/preparar",
        json={"items": [{"variante_id": str(VARIANTE), "disponible": False}]},
    )
    assert respuesta.status_code == 409
    assert not conn.toco_stock()


def test_resolver_reserva_sin_pago_en_curso_sigue_validando_las_decisiones(cliente_encargado):
    # sin venta PENDIENTE el guard deja pasar: llega a la validacion de decisiones (422 porque
    # la conexion falsa no devuelve prendas preparadas), no a un 409
    conn = ConexionFalsa(
        {
            "FROM reserva r": _reserva("CLIENTE_PRESENTE"),
            "FROM venta WHERE reserva_id": False,
        }
    )
    respuesta = cliente_encargado(conn).post(
        f"/reservas/{RESERVA}/resolver",
        json={"decisiones": [{"variante_id": str(VARIANTE), "comprado": False}]},
    )
    assert respuesta.status_code == 422


# --- confirmar_aprobado: defensa del lado del pago ---------------------------------------------


def _venta() -> dict:
    return {
        "id": uuid4(),
        "sucursal_id": SUCURSAL,
        "carrito_id": uuid4(),
        "reserva_id": RESERVA,
        "promocion_id": None,
        "numero": "V-TEST",
    }


def _conexion_pago(estado_reserva: str, comprometido: int) -> ConexionFalsa:
    return ConexionFalsa(
        {
            "FROM carrito_item": [
                {"variante_id": VARIANTE, "cantidad": 1, "precio_unitario": 100}
            ],
            "SELECT subtotal FROM venta": 100,
            "FROM reserva WHERE id": estado_reserva,
            "FROM reserva_detalle": (
                [{"variante_id": VARIANTE, "cantidad": comprometido}] if comprometido else []
            ),
            "FROM pago WHERE id": {"metodo": "EFECTIVO", "pasarela": None, "id_transaccion": None},
        }
    )


@pytest.mark.parametrize("estado", ["CONVERTIDA", "CANCELADA", "EXPIRADA", "ATENDIDA"])
async def test_confirmar_aprobado_anula_si_la_reserva_ya_se_resolvio(estado):
    conn = _conexion_pago(estado, comprometido=1)
    resultado = await servicio.confirmar_aprobado(conn, uuid4(), _venta())
    assert resultado["venta_estado"] == "ANULADA"
    assert resultado["pago_estado"] == "RECHAZADO"  # era efectivo: no se cobro nada
    assert not conn.toco_stock()


async def test_confirmar_aprobado_anula_si_la_reserva_ya_no_compromete_la_prenda():
    # la reserva sigue viva pero el item ya se descarto (p.ej. E2 al preparar)
    conn = _conexion_pago("PREPARADA", comprometido=0)
    resultado = await servicio.confirmar_aprobado(conn, uuid4(), _venta())
    assert resultado["venta_estado"] == "ANULADA"
    assert not conn.toco_stock()


@pytest.mark.parametrize("estado", ["PENDIENTE", "CONFIRMADA", "PREPARADA", "CLIENTE_PRESENTE"])
async def test_reserva_viva_que_compromete_la_prenda_respalda_la_venta(estado):
    conn = _conexion_pago(estado, comprometido=1)
    items = [{"variante_id": VARIANTE, "cantidad": 1}]
    assert await servicio._reserva_respalda_items(conn, RESERVA, items)
