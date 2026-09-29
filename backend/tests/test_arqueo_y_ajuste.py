"""Efectivo cobrado al atender una reserva (entra al arqueo de caja) y ajuste manual de stock (se
puede contar 0; por debajo de lo reservado es 409, no 500). Sin Postgres: tests/conexion_falsa.py."""

from datetime import date, datetime, time, timezone
from decimal import Decimal
from uuid import uuid4

import asyncpg
import pytest
from fastapi.testclient import TestClient

from app.core.db import get_connection
from app.core.deps import get_encargado_actual
from app.main import app
from app.modules.inventario import router as inventario_router
from tests.conexion_falsa import ConexionFalsa

SUCURSAL = uuid4()
RESERVA = uuid4()
VARIANTE = uuid4()
SESION = uuid4()


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


# --- 6: resolver_reserva y el arqueo -------------------------------------------------------------


def _reserva() -> dict:
    ahora = datetime.now(timezone.utc)
    return {
        "id": RESERVA, "codigo": "R-TEST", "sucursal_id": SUCURSAL, "sucursal": "Equipetrol",
        "estado": "CLIENTE_PRESENTE", "fecha_visita": date.today(), "hora_visita": time(10, 0),
        "expira_en": ahora, "creada_en": ahora, "observaciones": None,
        "vestidor_asignado": None, "atendida_en": ahora, "usuario_id": uuid4(),
        "cliente_nombre": "Ana", "cliente_apellido": "Perez",
        "cliente_email": "ana@example.com", "cliente_telefono": None,
    }


def _conn_resolver(sesion_abierta: bool) -> ConexionFalsa:
    return ConexionFalsa(
        {
            "FROM reserva r": _reserva(),
            "FROM venta WHERE reserva_id": False,
            "rd.estado_item = 'PREPARADO'": [
                {"variante_id": VARIANTE, "cantidad": 1, "sku": "SKU-1", "precio": Decimal("100")}
            ],
            "FROM sesion_caja sc": (
                {"id": SESION, "caja_id": uuid4(), "caja_nombre": "Caja 1"}
                if sesion_abierta else None
            ),
            "INSERT INTO venta (": {"id": uuid4()},
        }
    )


def _resolver(cliente, conn: ConexionFalsa, metodo_pago: str):
    return cliente(
        conn, {get_encargado_actual: lambda: {"usuario_id": uuid4(), "sucursal_id": SUCURSAL}}
    ).post(
        f"/reservas/{RESERVA}/resolver",
        json={
            "decisiones": [{"variante_id": str(VARIANTE), "comprado": True}],
            "metodo_pago": metodo_pago,
        },
    )


def test_resolver_en_efectivo_ata_la_venta_a_la_sesion_de_caja(cliente):
    conn = _conn_resolver(sesion_abierta=True)
    respuesta = _resolver(cliente, conn, "EFECTIVO")
    assert respuesta.status_code == 200, respuesta.text
    # (sucursal, reserva, sesion_caja_id, numero, registrada_por): fn_total_efectivo_sesion la cuenta
    assert conn.args_de("INSERT INTO venta (")[2] == SESION


def test_resolver_en_efectivo_sin_sesion_de_caja_devuelve_409_sin_vender(cliente):
    conn = _conn_resolver(sesion_abierta=False)
    respuesta = _resolver(cliente, conn, "EFECTIVO")
    assert respuesta.status_code == 409
    assert "sesion de caja" in respuesta.json()["detail"]
    assert not conn.ejecuto("INSERT INTO venta")
    assert not conn.ejecuto("ATENDIDA")


def test_resolver_con_tarjeta_no_exige_sesion_de_caja(cliente):
    # no mueve el cajon: un VENDEDOR (sin permiso de caja) puede cobrarlo
    conn = _conn_resolver(sesion_abierta=False)
    respuesta = _resolver(cliente, conn, "TARJETA")
    assert respuesta.status_code == 200, respuesta.text
    assert conn.args_de("INSERT INTO venta (")[2] is None


def test_resolver_con_tarjeta_y_sesion_abierta_tambien_la_ata(cliente):
    conn = _conn_resolver(sesion_abierta=True)
    respuesta = _resolver(cliente, conn, "QR")
    assert respuesta.status_code == 200, respuesta.text
    assert conn.args_de("INSERT INTO venta (")[2] == SESION


# --- 7: ajuste manual de stock -------------------------------------------------------------------

ADMIN = {"id": uuid4(), "permisos": ["sucursales.actualizar"], "sucursal_id": None}


def _ajustar(cliente, conn: ConexionFalsa, cantidad: int):
    return cliente(conn, {inventario_router.puede_ajustar: lambda: ADMIN}).post(
        "/inventario/ajustes",
        json={
            "sucursal_id": str(SUCURSAL),
            "variante_id": str(VARIANTE),
            "cantidad_fisica_nueva": cantidad,
            "motivo": "Recuento fisico",
        },
    )


def test_ajuste_a_cero_se_acepta(cliente):
    conn = ConexionFalsa(
        {
            "fn_mover_inventario": 1,
            "FROM movimiento_inventario": {
                "id": 1, "saldo_anterior": 1, "saldo_nuevo": 0, "motivo": "Recuento fisico",
                "fecha": datetime.now(timezone.utc),
            },
        }
    )
    respuesta = _ajustar(cliente, conn, 0)
    assert respuesta.status_code == 201, respuesta.text
    assert respuesta.json()["saldo_nuevo"] == 0
    assert conn.args_de("fn_mover_inventario")[2] == 0


def test_ajuste_negativo_sigue_siendo_422(cliente):
    assert _ajustar(cliente, ConexionFalsa({}), -1).status_code == 422


def test_ajuste_por_debajo_de_lo_reservado_devuelve_409_y_no_500(cliente):
    def _viola_check(sql):
        raise asyncpg.CheckViolationError(
            'new row for relation "inventario" violates check constraint "ck_inventario_saldos"'
        )

    conn = ConexionFalsa(
        {"fn_mover_inventario": _viola_check, "SELECT cantidad_reservada FROM inventario": 3}
    )
    respuesta = _ajustar(cliente, conn, 1)
    assert respuesta.status_code == 409
    assert "3 comprometida(s)" in respuesta.json()["detail"]
