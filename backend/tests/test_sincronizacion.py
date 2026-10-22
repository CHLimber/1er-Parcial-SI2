"""Reglas de la sincronizacion offline (Modulos D y E): que se rechaza, que queda en conflicto y
que un reenvio no duplica. Sin Postgres. El recorrido real (idempotencia con reenvios
simultaneos, stock descontado una vez, resolucion de conflictos, suscripcion vencida) esta en
scripts/e2e_sincronizacion.py."""

import json
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from uuid import uuid4

import pytest

from app.modules.operacion_sin_conexion.sincronizacion import servicio
from app.modules.operacion_sin_conexion.sincronizacion.schemas import OperacionIn
from tests.conexion_falsa import EMPRESA, ConexionFalsa, staff

AHORA = datetime(2026, 10, 18, 15, 0, tzinfo=timezone.utc)
CAJERA = staff(permisos=["caja.crear"], sucursal_id=uuid4())


def _op(**cambios) -> OperacionIn:
    datos = {
        "id": str(uuid4()), "tipo": "VENTA", "empresa_id": str(EMPRESA),
        "sucursal_id": str(CAJERA["sucursal_id"]), "usuario_id": str(CAJERA["id"]),
        "registrada_en": (AHORA - timedelta(hours=1)).isoformat(),
        "venta": {"items": [{"variante_id": str(uuid4()), "cantidad": 2, "precio_unitario": "100"}],
                  "total": "226.00"},
    }
    datos.update(cambios)
    return OperacionIn.model_validate(datos)


def _plan(**cambios):
    plan = {"estado": "ACTIVA", "vence_en": AHORA + timedelta(days=3), "plan_nombre": "Basico",
            "operacion_offline": True}
    plan.update(cambios)
    return plan


def test_total_con_iva_redondea_como_el_pos():
    assert servicio.total_con_iva([(Decimal("99.90"), 1)]) == (
        Decimal("99.90"), Decimal("12.99"), Decimal("112.89"))


def test_operacion_valida_pasa_la_cabecera():
    servicio.validar_cabecera(_op(), CAJERA, _plan(), AHORA)


@pytest.mark.parametrize(
    ("cambios", "codigo"),
    [
        ({"empresa_id": str(uuid4())}, "EMPRESA_AJENA"),
        ({"usuario_id": str(uuid4())}, "RESPONSABLE_DISTINTO"),
        ({"registrada_en": (AHORA + timedelta(hours=2)).isoformat()}, "FECHA_INVALIDA"),
    ],
)
def test_cabecera_invalida_se_rechaza(cambios, codigo):
    with pytest.raises(servicio.Rechazo) as error:
        servicio.validar_cabecera(_op(**cambios), CAJERA, _plan(), AHORA)
    assert error.value.codigo == codigo
    assert not isinstance(error.value, servicio.Conflicto)


def test_plan_sin_offline_se_rechaza():
    with pytest.raises(servicio.Rechazo) as error:
        servicio.validar_cabecera(_op(), CAJERA, _plan(operacion_offline=False), AHORA)
    assert error.value.codigo == "PLAN_SIN_OFFLINE"


def test_vendida_antes_del_vencimiento_se_acepta_aunque_hoy_este_vencida():
    plan = _plan(vence_en=AHORA - timedelta(minutes=30))  # vencio despues de la venta (-1h)
    servicio.validar_cabecera(_op(), CAJERA, plan, AHORA)


def test_registrada_despues_del_vencimiento_se_rechaza():
    plan = _plan(vence_en=AHORA - timedelta(hours=2))
    with pytest.raises(servicio.Rechazo) as error:
        servicio.validar_cabecera(_op(), CAJERA, plan, AHORA)
    assert error.value.codigo == "SUSCRIPCION_VENCIDA"


def test_suscripcion_cancelada_se_rechaza_siempre():
    with pytest.raises(servicio.Rechazo):
        servicio.validar_cabecera(_op(), CAJERA, _plan(estado="CANCELADA", vence_en=AHORA - timedelta(minutes=1)), AHORA)


def test_diferencias_de_precio():
    assert servicio.diferencias_de_precio([("A", Decimal("10"), Decimal("10.00"))]) == []
    assert servicio.diferencias_de_precio([("A", Decimal("10"), Decimal("12"))]) == [
        "A: Bs 10.00 en el dispositivo, Bs 12.00 hoy"]


def test_venta_offline_solo_de_contado():
    with pytest.raises(ValueError):
        _op(venta={"items": [{"variante_id": str(uuid4()), "cantidad": 1, "precio_unitario": "1"}],
                   "total": "1.13", "metodo_pago": "TARJETA"})


def test_venta_sin_cuerpo_no_valida():
    with pytest.raises(ValueError):
        _op(venta=None)


# --- idempotencia: un id ya recibido no se vuelve a procesar ---------------------------------------


@pytest.mark.asyncio
async def test_reenvio_de_una_operacion_confirmada_devuelve_lo_guardado():
    op = _op()
    guardada = {
        "id": op.id, "tipo": "VENTA", "estado": "CONFIRMADA", "codigo_motivo": None,
        "motivo": None, "resultado": json.dumps({"venta_id": "v1", "numero": "V-1"}),
        "intentos": 2, "recibida_en": AHORA, "resuelta_en": None, "resolucion": None,
        "empresa_id": EMPRESA,
    }
    conn = ConexionFalsa({"FROM operacion_sync": guardada, "UPDATE operacion_sync": guardada})
    resultado = await servicio.procesar(conn, CAJERA, op)
    assert resultado.duplicada and resultado.estado == "CONFIRMADA"
    assert resultado.resultado["venta_id"] == "v1"
    assert not conn.ejecuto("INSERT INTO venta")
    assert not conn.ejecuto("INSERT INTO operacion_sync")


@pytest.mark.asyncio
async def test_el_reenvio_toma_el_candado_del_id_antes_de_mirar():
    op = _op()
    conn = ConexionFalsa({"FROM operacion_sync": None, "FROM suscripcion su": None,
                          "RETURNING id, tipo": {
                              "id": op.id, "tipo": "VENTA", "estado": "RECHAZADA",
                              "codigo_motivo": "SIN_SUSCRIPCION", "motivo": "x", "resultado": None,
                              "intentos": 1, "recibida_en": AHORA, "resuelta_en": None,
                              "resolucion": None}})
    resultado = await servicio.procesar(conn, CAJERA, op)
    assert conn.ejecutado[0].startswith("SELECT pg_advisory_xact_lock")
    assert resultado.estado == "RECHAZADA"
    # aun rechazada, la operacion queda registrada (RN12: nunca se pierde)
    assert conn.ejecuto("INSERT INTO operacion_sync")


@pytest.mark.asyncio
async def test_mismo_id_desde_otra_empresa_no_revela_la_operacion():
    op = _op()
    ajena = {"id": op.id, "empresa_id": uuid4(), "estado": "CONFIRMADA"}
    resultado = await servicio.procesar(ConexionFalsa({"FROM operacion_sync": ajena}), CAJERA, op)
    assert resultado.codigo_motivo == "ID_REPETIDO" and resultado.resultado is None
