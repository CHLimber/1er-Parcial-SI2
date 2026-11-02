"""Intercambios y reglas nuevas de devoluciones (PENDIENTES 10): la diferencia de precio se cobra o
se devuelve (lo devuelto es credito, no un reembolso entero), QR se reintegra desde el cajon, tope
de prendas por compra y la solicitud online solo para clientas. Sin Postgres (conexion_falsa)."""

from datetime import datetime, timezone
from decimal import Decimal
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.core.db import get_connection
from app.core.deps import get_current_usuario
from app.main import app
from app.modules.operacion_comercial.devoluciones import router as devoluciones_router
from app.modules.operacion_comercial.devoluciones import servicio
from tests.conexion_falsa import ConexionFalsa, staff

SUCURSAL = uuid4()
DEVOLUCION = uuid4()
VENTA = uuid4()
VENTA_CAMBIO = uuid4()
SESION = uuid4()
ADMIN = staff(permisos=["sucursales.actualizar"])


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


# --- reglas puras --------------------------------------------------------------------------------


def test_una_devolucion_reintegra_todo_lo_que_vale_lo_devuelto():
    assert servicio.liquidar("DEVOLUCION", Decimal("113.00"), Decimal("0")) == (Decimal("113.00"), Decimal("0.00"))


def test_intercambio_mas_caro_cobra_solo_la_diferencia():
    assert servicio.liquidar("INTERCAMBIO", Decimal("113.00"), Decimal("124.30")) == (
        Decimal("0.00"),
        Decimal("11.30"),
    )


def test_intercambio_mas_barato_devuelve_lo_que_sobra():
    assert servicio.liquidar("INTERCAMBIO", Decimal("124.30"), Decimal("113.00")) == (
        Decimal("11.30"),
        Decimal("0.00"),
    )


def test_intercambio_al_mismo_precio_no_mueve_plata():
    assert servicio.liquidar("INTERCAMBIO", Decimal("113.00"), Decimal("113.00")) == (
        Decimal("0.00"),
        Decimal("0"),
    )


def test_las_prendas_nuevas_llevan_iva_como_en_caja():
    assert servicio.con_iva(Decimal("110.00")) == Decimal("124.30")


@pytest.mark.parametrize(("motivo", "tipo"), [("TALLA", "INTERCAMBIO"), ("COLOR", "INTERCAMBIO"),
                                              ("DEFECTO", "DEVOLUCION"), ("NO_GUSTO", "DEVOLUCION")])
def test_el_motivo_decide_si_es_devolucion_o_intercambio(motivo, tipo):
    assert servicio.tipo_de(motivo) == tipo


def test_efectivo_y_qr_se_devuelven_desde_el_cajon():
    assert servicio.sale_del_cajon("EFECTIVO")
    assert servicio.sale_del_cajon("QR")
    assert not servicio.sale_del_cajon("STRIPE")
    assert not servicio.sale_del_cajon("TARJETA")


# --- aprobar -------------------------------------------------------------------------------------


def _bloqueada(**extra) -> dict:
    return {
        "id": DEVOLUCION, "venta_id": VENTA, "sucursal_id": SUCURSAL, "estado": "CONFIRMADA",
        "tipo": "INTERCAMBIO", "origen": "ONLINE", "motivo_tipo": "TALLA", "con_etiqueta": True,
        "sin_uso": True, "con_comprobante": True, "monto_devuelto": Decimal("113.00"),
        "monto_cambio": Decimal("124.30"), "numero": "NDV-000009", "fecha_visita": None,
        "hora_visita": None, "venta_numero": "V-TEST", "cliente_id": uuid4(), "sucursal": "Equipetrol",
        **extra,
    }


def _devolucion_out(**extra) -> dict:
    ahora = datetime.now(timezone.utc)
    return {
        "id": DEVOLUCION, "numero": "NDV-000009", "tipo": "INTERCAMBIO", "origen": "ONLINE",
        "venta_id": VENTA, "venta_numero": "V-TEST", "venta_total": Decimal("226.00"),
        "sucursal_id": SUCURSAL, "sucursal": "Equipetrol", "cliente": "Ana Perez",
        "motivo_tipo": "TALLA", "motivo": "Le quedo chica", "con_etiqueta": True, "sin_uso": True,
        "con_comprobante": True, "monto_devuelto": Decimal("113.00"), "estado": "APROBADA",
        "fecha": ahora, "registrada_por": "Ana Perez", "resuelta_por": "Admin", "resuelta_en": ahora,
        "motivo_rechazo": None, "lineas": 1, "unidades": 1, **extra,
    }


def _conn(bloqueada: dict, pago: dict, sesion: dict | None = None) -> ConexionFalsa:
    return ConexionFalsa(
        {
            "d.monto_cambio, d.numero, d.fecha_visita": bloqueada,
            "SELECT (SELECT COALESCE(SUM(cantidad), 0) FROM venta_detalle": 1,
            "v.total - v.costo_envio AS mercaderia": {
                "mercaderia": Decimal("226.00"), "suma_lineas": Decimal("200.00"),
            },
            "SUM(dd.cantidad * vd.subtotal / vd.cantidad)": Decimal("100.00"),
            "FROM pago WHERE venta_id = $1 AND estado = 'APROBADO'": pago,
            "FROM sesion_caja sc": sesion,
            "SELECT variante_solicitada_id AS variante_id": [
                {"variante_id": uuid4(), "cantidad": 1, "precio": Decimal("110.00")}
            ],
            "INSERT INTO venta (sucursal_id, usuario_id, canal": VENTA_CAMBIO,
            "FROM devolucion d\nJOIN venta v": _devolucion_out(),
            "estado = 'REEMBOLSADO')": False,
        }
    )


def _aprobar(cliente, conn: ConexionFalsa, body: dict | None = None):
    return cliente(conn, {devoluciones_router.puede_resolver: lambda: ADMIN}).post(
        f"/devoluciones/{DEVOLUCION}/aprobar", json=body
    )


def test_intercambio_mas_caro_sin_decir_como_paga_es_422(cliente):
    conn = _conn(_bloqueada(), {"metodo": "EFECTIVO", "pasarela": None, "id_transaccion": None},
                 {"id": SESION})
    respuesta = _aprobar(cliente, conn)
    assert respuesta.status_code == 422
    assert "11.30" in respuesta.json()["detail"]
    assert not conn.ejecuto("SET estado = 'APROBADA'")


def test_intercambio_mas_caro_cobra_la_diferencia_y_arma_la_venta_del_cambio(cliente, monkeypatch):
    async def _no_reembolsa(*args):
        raise AssertionError("un intercambio que sale mas caro no reembolsa nada")

    monkeypatch.setattr(devoluciones_router, "reembolsar_parcial_stripe", _no_reembolsa)
    conn = _conn(_bloqueada(), {"metodo": "PASARELA", "pasarela": "STRIPE", "id_transaccion": "pi_1"},
                 {"id": SESION})
    respuesta = _aprobar(cliente, conn, {"diferencia_metodo": "EFECTIVO"})
    assert respuesta.status_code == 200, respuesta.text
    args = conn.args_de("SET estado = 'APROBADA'")
    # (id, valor devuelto, reintegrado, diferencia cobrada, metodo de la diferencia, ...)
    assert args[1:5] == (Decimal("113.00"), Decimal("0.00"), Decimal("11.30"), "EFECTIVO")
    assert args[6] is None  # no vuelve plata: no hay metodo de reintegro
    assert args[7] == SESION
    # la venta nueva vale lo nuevo con IVA y el pago es solo la diferencia
    venta = conn.args_de("INSERT INTO venta (sucursal_id, usuario_id, canal")
    assert (venta[4], venta[5], venta[6]) == (Decimal("110.00"), Decimal("14.30"), Decimal("124.30"))
    assert conn.args_de("INSERT INTO pago")[1:3] == ("EFECTIVO", Decimal("11.30"))
    assert conn.args_de("SET venta_cambio_id") == (DEVOLUCION, VENTA_CAMBIO)
    # el pago original NO pasa a REEMBOLSADO en un intercambio
    assert not conn.ejecuto("SET estado = 'REEMBOLSADO'")


def test_intercambio_mas_barato_pagado_con_stripe_reembolsa_solo_lo_que_sobra(cliente, monkeypatch):
    llamadas = []

    async def _reembolsar(id_transaccion, monto, clave):
        llamadas.append(monto)
        return "re_9"

    monkeypatch.setattr(devoluciones_router, "reembolsar_parcial_stripe", _reembolsar)
    conn = _conn(
        _bloqueada(monto_cambio=Decimal("101.70")),
        {"metodo": "PASARELA", "pasarela": "STRIPE", "id_transaccion": "pi_1"},
        {"id": SESION},
    )
    respuesta = _aprobar(cliente, conn)
    assert respuesta.status_code == 200, respuesta.text
    assert llamadas == [Decimal("11.30")]
    assert not conn.ejecuto("INSERT INTO pago")  # no paga nada de mas


def test_intercambio_exige_caja_abierta(cliente):
    conn = _conn(_bloqueada(monto_cambio=Decimal("113.00")),
                 {"metodo": "TARJETA", "pasarela": None, "id_transaccion": None}, None)
    respuesta = _aprobar(cliente, conn)
    assert respuesta.status_code == 409
    assert "sesion de caja" in respuesta.json()["detail"]


def test_devolucion_pagada_con_qr_sale_del_cajon(cliente):
    bloqueada = _bloqueada(tipo="DEVOLUCION", motivo_tipo="NO_GUSTO", monto_cambio=Decimal("0"))
    sin_caja = _conn(bloqueada, {"metodo": "PASARELA", "pasarela": "QR", "id_transaccion": None}, None)
    assert _aprobar(cliente, sin_caja).status_code == 409

    con_caja = _conn(bloqueada, {"metodo": "PASARELA", "pasarela": "QR", "id_transaccion": None},
                     {"id": SESION})
    respuesta = _aprobar(cliente, con_caja)
    assert respuesta.status_code == 200, respuesta.text
    args = con_caja.args_de("SET estado = 'APROBADA'")
    assert args[2] == Decimal("113.00")  # reintegrado entero
    assert (args[6], args[7]) == ("QR", SESION)


def test_condiciones_que_faltan_al_llegar_la_prenda_no_se_aprueban(cliente):
    conn = _conn(_bloqueada(), {"metodo": "EFECTIVO", "pasarela": None, "id_transaccion": None},
                 {"id": SESION})
    respuesta = _aprobar(cliente, conn, {"sin_uso": False, "diferencia_metodo": "QR"})
    assert respuesta.status_code == 409
    assert "la prenda sin uso" in respuesta.json()["detail"]


# --- tope y solicitudes online -------------------------------------------------------------------


def test_no_se_devuelven_mas_de_3_prendas_por_compra(cliente):
    conn = ConexionFalsa({})
    respuesta = cliente(conn, {devoluciones_router.puede_crear: lambda: ADMIN}).post(
        "/devoluciones",
        json={"venta_id": str(uuid4()), "motivo_tipo": "NO_GUSTO", "motivo": "No le gusto",
              "lineas": [{"venta_detalle_id": str(uuid4()), "cantidad": 4}]},
    )
    assert respuesta.status_code == 409
    assert "hasta 3 prendas" in respuesta.json()["detail"]
    assert not conn.ejecuto("FOR UPDATE")  # ni siquiera bloquea la venta


def test_la_solicitud_online_es_solo_para_clientas(cliente):
    conn = ConexionFalsa({})
    respuesta = cliente(conn, {get_current_usuario: lambda: {"id": uuid4(), "tipo": "STAFF"}}).post(
        "/mis-devoluciones",
        json={"venta_id": str(uuid4()), "motivo_tipo": "NO_GUSTO", "motivo": "No me gusto",
              "fecha_visita": "2099-01-01", "hora_visita": "10:00",
              "lineas": [{"venta_detalle_id": str(uuid4()), "cantidad": 1}]},
    )
    assert respuesta.status_code == 403


def test_la_visita_no_puede_ser_en_el_pasado(cliente):
    conn = ConexionFalsa({})
    respuesta = cliente(conn, {get_current_usuario: lambda: {"id": uuid4(), "tipo": "CLIENTE"}}).post(
        "/mis-devoluciones",
        json={"venta_id": str(uuid4()), "motivo_tipo": "NO_GUSTO", "motivo": "No me gusto",
              "fecha_visita": "2020-01-01", "hora_visita": "10:00",
              "lineas": [{"venta_detalle_id": str(uuid4()), "cantidad": 1}]},
    )
    assert respuesta.status_code == 422
    assert "anterior a hoy" in respuesta.json()["detail"]
