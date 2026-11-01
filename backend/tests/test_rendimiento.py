"""Refactors de eficiencia (PENDIENTES 9.11): lo que antes eran varias consultas por request o por
fila ahora es una, con las mismas respuestas. Sin Postgres: ConexionFalsa y dependency_overrides.
Cada test fija la cantidad de sentencias, para que volver a un N+1 rompa el test."""

import asyncio
from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from starlette.requests import Request

from app.core.db import get_connection
from app.core.deps import (
    MOTIVO_EMPRESA_SUSPENDIDA,
    MOTIVO_SUSCRIPCION_VENCIDA,
    _empleado_con_permiso,
    get_current_usuario,
    get_staff_actual,
)
from app.core.notificaciones.servicio import avisar_personal_de_sucursal
from app.core.tenant import sucursal_visible
from app.main import app
from app.modules.operacion_comercial.pagos.servicio import alertar_stock_bajo
from tests.conexion_falsa import EMPRESA, ConexionFalsa, staff

AHORA = datetime.now(timezone.utc)
USUARIO = UUID(int=11)
SUCURSAL = UUID(int=21)


class ConexionContada(ConexionFalsa):
    """ConexionFalsa que anota TODAS las consultas (el fetch original no se anota)."""

    async def fetch(self, sql, *args):
        self._anotar(sql, args)
        return self._buscar(sql, args) or []

    def cantidad(self) -> int:
        return len(self.ejecutado)


def _request(ruta="/traspasos") -> Request:
    return Request({"type": "http", "path": ruta, "headers": [], "query_string": b""})


def _fila_personal(**cambios) -> dict:
    fila = {
        "id": USUARIO, "empresa_id": EMPRESA, "rol": "ENCARGADO", "sucursal_id": SUCURSAL,
        "cargo": "ENCARGADO", "activa": True, "vigente": True, "permisos": ["traspasos.leer"],
        "suscripcion_id": uuid4(), "estado": "ACTIVA", "vence_en": AHORA + timedelta(days=20),
        "inicio": AHORA, "plan_nombre": "Profesional", "perfiles_clientes": True,
        "traspasos": True, "operacion_offline": True, "reportes": True, "ia_reportes": True,
        "analitica_ml": True,
    }
    return fila | cambios


FRAGMENTO_PERSONAL = "SELECT u.id, u.empresa_id, r.nombre AS rol, e.sucursal_id, e.cargo"


def _staff_actual(fila, request=None, tipo="STAFF"):
    conn = ConexionContada({FRAGMENTO_PERSONAL: fila})
    request = request or _request()
    resultado = asyncio.run(
        get_staff_actual(request, {"id": USUARIO, "tipo": tipo, "empresa_id": EMPRESA}, conn)
    )
    return resultado, conn, request


# --- get_staff_actual: una consulta, no cuatro ---------------------------------------------------


def test_el_personal_se_identifica_con_una_sola_consulta():
    personal, conn, request = _staff_actual(_fila_personal())
    assert conn.cantidad() == 1
    assert personal == {
        "id": USUARIO, "rol": "ENCARGADO", "empresa_id": EMPRESA, "sucursal_id": SUCURSAL,
        "cargo": "ENCARGADO", "permisos": ["traspasos.leer"],
    }
    # el plan viaja en la request para que requiere_funcion_plan no lo vuelva a pedir
    assert request.state.plan_empresa["plan_nombre"] == "Profesional"


def test_un_cliente_no_entra_a_las_pantallas_del_personal_ni_consulta_nada():
    conn = ConexionContada({})
    with pytest.raises(HTTPException) as error:
        asyncio.run(
            get_staff_actual(_request(), {"id": USUARIO, "tipo": "CLIENTE", "empresa_id": None}, conn)
        )
    assert error.value.status_code == 403
    assert conn.cantidad() == 0


def test_sin_rol_asignado_es_403():
    with pytest.raises(HTTPException) as error:
        _staff_actual(_fila_personal(rol=None))
    assert error.value.status_code == 403
    assert "rol asignado" in error.value.detail


def test_empresa_suspendida_corta_con_403_y_motivo():
    with pytest.raises(HTTPException) as error:
        _staff_actual(_fila_personal(activa=False))
    assert error.value.status_code == 403
    assert error.value.headers["X-Motivo"] == MOTIVO_EMPRESA_SUSPENDIDA


def test_suscripcion_vencida_corta_al_personal_pero_no_al_admin_ni_a_sync():
    with pytest.raises(HTTPException) as error:
        _staff_actual(_fila_personal(vigente=False))
    assert error.value.status_code == 402
    assert error.value.headers["X-Motivo"] == MOTIVO_SUSCRIPCION_VENCIDA

    _staff_actual(_fila_personal(vigente=False, rol="ADMIN"))
    _staff_actual(_fila_personal(vigente=False), request=_request("/sync/operaciones"))


def test_la_plataforma_no_tiene_empresa_ni_plan_en_la_request():
    personal, conn, request = _staff_actual(
        _fila_personal(empresa_id=None, rol="SUPERADMIN", suscripcion_id=None, activa=None)
    )
    assert personal["empresa_id"] is None
    assert not hasattr(request.state, "plan_empresa")


def test_una_empresa_sin_suscripcion_deja_el_plan_en_none():
    _, _, request = _staff_actual(_fila_personal(suscripcion_id=None, vigente=False, rol="ADMIN"))
    assert request.state.plan_empresa is None


# --- requiere_funcion_plan reutiliza el plan ya leido --------------------------------------------


def _llamar_traspasos(fila, **extra):
    """GET /traspasos/sugerencias pasando por la cadena REAL de dependencias de personal (solo se
    reemplaza la sesion y la conexion)."""
    conn = ConexionContada({FRAGMENTO_PERSONAL: fila, **extra})

    async def _conn():
        yield conn

    app.dependency_overrides[get_connection] = _conn
    app.dependency_overrides[get_current_usuario] = lambda: {
        "id": USUARIO, "tipo": "STAFF", "empresa_id": EMPRESA,
    }
    try:
        respuesta = TestClient(app, raise_server_exceptions=False).get("/traspasos/sugerencias")
    finally:
        app.dependency_overrides.clear()
    return respuesta, conn


def test_un_endpoint_con_plan_pide_el_plan_una_sola_vez_junto_al_usuario():
    respuesta, conn = _llamar_traspasos(_fila_personal())
    assert respuesta.status_code == 200
    # la consulta del personal (usuario + rol + empresa + permisos + plan) y nada de plan aparte
    assert not conn.ejecuto("FROM suscripcion su\nJOIN plan p")
    assert sum(FRAGMENTO_PERSONAL in sql for sql in conn.ejecutado) == 1


def test_el_plan_leido_junto_al_usuario_sigue_cortando_por_funcion():
    respuesta, conn = _llamar_traspasos(
        _fila_personal(traspasos=False, plan_nombre="Basico"),
        **{"SELECT nombre FROM plan": "Profesional"},
    )
    assert respuesta.status_code == 403
    assert "desde el plan Profesional" in respuesta.json()["detail"]
    assert not conn.ejecuto("FROM suscripcion su\nJOIN plan p")


def test_el_plan_leido_junto_al_usuario_sigue_cortando_por_vencimiento():
    respuesta, _ = _llamar_traspasos(_fila_personal(estado="VENCIDA", vence_en=AHORA - timedelta(days=2), rol="ADMIN", vigente=False))
    assert respuesta.status_code == 402
    assert "vencio el" in respuesta.json()["detail"]


def test_sin_suscripcion_el_endpoint_con_plan_responde_402():
    respuesta, _ = _llamar_traspasos(_fila_personal(suscripcion_id=None, vigente=False, rol="ADMIN"))
    assert respuesta.status_code == 402
    assert "no tiene una suscripcion" in respuesta.json()["detail"]


# --- caja y reservas (CU07/CU08): una consulta ---------------------------------------------------


def _fila_empleado(**cambios) -> dict:
    fila = {
        "empresa_id": EMPRESA, "rol": "CAJERO", "sucursal_id": SUCURSAL, "activa": True,
        "vigente": True, "sucursal_propia": True, "permisos": ["caja.crear"],
    }
    return fila | cambios


def _empleado(fila, ruta="/caja/abrir"):
    conn = ConexionContada({"SELECT u.empresa_id, r.nombre AS rol, e.sucursal_id": fila})
    usuario = {"id": USUARIO, "tipo": "STAFF", "empresa_id": EMPRESA}
    return asyncio.run(_empleado_con_permiso(conn, usuario, "caja.crear", "solo caja", ruta)), conn


def test_el_cajero_se_resuelve_con_una_sola_consulta():
    empleado, conn = _empleado(_fila_empleado())
    assert conn.cantidad() == 1
    assert empleado == {"usuario_id": USUARIO, "sucursal_id": SUCURSAL, "empresa_id": EMPRESA}


@pytest.mark.parametrize(
    ("cambios", "codigo", "texto", "motivo"),
    [
        ({"permisos": []}, 403, "no tiene permiso", None),
        ({"activa": False}, 403, "suspendida", MOTIVO_EMPRESA_SUSPENDIDA),
        ({"vigente": False}, 402, "vencio", MOTIVO_SUSCRIPCION_VENCIDA),
        ({"sucursal_propia": False}, 403, "no esta asignado a una sucursal", None),
    ],
)
def test_el_empleado_sin_permiso_empresa_o_sucursal_es_rechazado_igual_que_antes(
    cambios, codigo, texto, motivo
):
    with pytest.raises(HTTPException) as error:
        _empleado(_fila_empleado(**cambios))
    assert error.value.status_code == codigo
    assert texto in error.value.detail
    if motivo:
        assert error.value.headers["X-Motivo"] == motivo


def test_el_permiso_se_chequea_antes_que_el_estado_de_la_empresa():
    with pytest.raises(HTTPException) as error:
        _empleado(_fila_empleado(permisos=[], activa=False))
    assert "no tiene permiso" in error.value.detail


def test_un_usuario_que_no_es_personal_recibe_el_detalle_de_la_pantalla():
    conn = ConexionContada({})
    with pytest.raises(HTTPException) as error:
        asyncio.run(
            _empleado_con_permiso(
                conn, {"id": USUARIO, "tipo": "CLIENTE", "empresa_id": None}, "caja.crear", "solo caja"
            )
        )
    assert error.value.detail == "solo caja"
    assert conn.cantidad() == 0


# --- /saas/empresas y /saas/suscripciones: sin N+1 -----------------------------------------------


def _plataforma(conn):
    async def _conn():
        yield conn

    app.dependency_overrides[get_connection] = _conn
    app.dependency_overrides[get_staff_actual] = lambda: staff(
        empresa_id=None, permisos=["empresas.leer", "suscripciones.leer"]
    )


def _empresa(n):
    return {
        "id": UUID(int=100 + n), "nombre": f"Empresa {n}", "razon_social": f"Empresa {n} SRL",
        "nit": f"10{n}", "slug": f"empresa-{n}", "activa": True, "creada_en": AHORA,
        "telefono": None, "email": None, "ciudad": None,
    }


def _suscripcion(n):
    return {
        "empresa_id": UUID(int=100 + n), "empresa": f"Empresa {n}", "empresa_slug": f"empresa-{n}",
        "empresa_activa": True, "estado": "ACTIVA", "inicio": AHORA,
        "vence_en": AHORA + timedelta(days=30), "plan_id": 1, "codigo": "BASICO",
        "nombre": "Basico", "descripcion": None, "precio_mensual": 100, "max_sucursales": 2,
        "max_empleados": 5, "max_cajas": 2, "perfiles_clientes": False, "traspasos": False,
        "operacion_offline": True, "reportes": True, "ia_reportes": False, "analitica_ml": False,
    }


def _uso(n, sucursales):
    return {"empresa_id": UUID(int=100 + n), "sucursales": sucursales, "empleados": n, "cajas": 1}


@pytest.fixture
def limpiar():
    yield
    app.dependency_overrides.clear()


def test_listar_empresas_son_cuatro_consultas_sin_importar_cuantas_haya(limpiar):
    from app.modules.plataforma_saas.saas import router as saas_router

    n = 6
    conn = ConexionContada(
        {
            "SELECT * FROM empresa ORDER BY": [_empresa(i) for i in range(n)],
            "r.nombre = 'ADMIN'": [
                {"empresa_id": UUID(int=100), "email": "a@x.bo"},
                {"empresa_id": UUID(int=100), "email": "b@x.bo"},
                {"empresa_id": UUID(int=103), "email": "c@x.bo"},
            ],
            "WHERE su.empresa_id = ANY": [_suscripcion(i) for i in range(n) if i != 4],
            "FROM unnest($1::uuid[])": [_uso(i, i + 1) for i in range(n)],
        }
    )
    _plataforma(conn)
    respuesta = TestClient(app, raise_server_exceptions=False).get("/saas/empresas")
    assert respuesta.status_code == 200, respuesta.text
    assert conn.cantidad() == 4
    datos = respuesta.json()
    assert [d["nombre"] for d in datos] == [f"Empresa {i}" for i in range(n)]
    assert datos[0]["administradores"] == ["a@x.bo", "b@x.bo"]
    assert datos[3]["administradores"] == ["c@x.bo"]
    assert datos[1]["administradores"] == []
    assert datos[4]["suscripcion"] is None  # empresa sin suscripcion
    assert datos[2]["suscripcion"]["uso"] == {"sucursales": 3, "empleados": 2, "cajas": 1}
    assert datos[5]["suscripcion"]["uso"]["sucursales"] == 6
    assert saas_router  # el router sigue siendo el de siempre


def test_listar_empresas_vacio_no_consulta_de_mas(limpiar):
    conn = ConexionContada({"SELECT * FROM empresa ORDER BY": []})
    _plataforma(conn)
    respuesta = TestClient(app, raise_server_exceptions=False).get("/saas/empresas")
    assert respuesta.status_code == 200
    assert respuesta.json() == []
    assert conn.cantidad() == 1


def test_listar_suscripciones_trae_el_uso_de_todas_en_una_consulta(limpiar):
    conn = ConexionContada(
        {
            "FROM suscripcion su": [_suscripcion(i) for i in range(5)],
            "FROM unnest($1::uuid[])": [_uso(i, 1) for i in range(5)],
        }
    )
    _plataforma(conn)
    respuesta = TestClient(app, raise_server_exceptions=False).get("/saas/suscripciones")
    assert respuesta.status_code == 200, respuesta.text
    assert conn.cantidad() == 2
    assert [s["empresa"] for s in respuesta.json()] == [f"Empresa {i}" for i in range(5)]
    assert respuesta.json()[3]["uso"]["empleados"] == 3


# --- /envios/mis: los eventos de todos los envios en una consulta --------------------------------


def _envio(n):
    return {
        "id": UUID(int=200 + n), "venta_id": UUID(int=300 + n), "numero_venta": f"V-{n}",
        "estado": "DESPACHADO", "sucursal": "Equipetrol", "ciudad": "SANTA_CRUZ",
        "direccion_texto": "Av. 1", "referencia": None, "latitud": -17.7, "longitud": -63.1,
        "distancia_km": 3, "duracion_min": 12, "costo": 15, "observacion": None,
        "creado_en": AHORA, "despachado_en": None, "cerrado_en": None,
    }


def test_mis_envios_trae_los_eventos_de_todos_en_una_consulta(limpiar):
    conn = ConexionContada(
        {
            "FROM envio e": [_envio(i) for i in range(4)],
            "FROM envio_evento": [
                {"envio_id": UUID(int=200 + 2), "estado": "PENDIENTE", "nota": "a", "fecha": AHORA},
                {"envio_id": UUID(int=200 + 0), "estado": "PENDIENTE", "nota": "b", "fecha": AHORA},
                {"envio_id": UUID(int=200 + 2), "estado": "DESPACHADO", "nota": "c", "fecha": AHORA},
            ],
        }
    )

    async def _conn():
        yield conn

    app.dependency_overrides[get_connection] = _conn
    app.dependency_overrides[get_current_usuario] = lambda: {
        "id": USUARIO, "tipo": "CLIENTE", "empresa_id": None,
    }
    respuesta = TestClient(app, raise_server_exceptions=False).get("/envios/mis")
    assert respuesta.status_code == 200, respuesta.text
    assert conn.cantidad() == 2  # los envios + todos sus eventos (antes 1 + 4)
    datos = respuesta.json()
    assert [d["numero_venta"] for d in datos] == ["V-0", "V-1", "V-2", "V-3"]
    assert [len(d["eventos"]) for d in datos] == [1, 0, 2, 0]
    assert [e["nota"] for e in datos[2]["eventos"]] == ["a", "c"]


def test_mis_envios_sin_envios_no_pide_eventos(limpiar):
    conn = ConexionContada({"FROM envio e": []})

    async def _conn():
        yield conn

    app.dependency_overrides[get_connection] = _conn
    app.dependency_overrides[get_current_usuario] = lambda: {
        "id": USUARIO, "tipo": "CLIENTE", "empresa_id": None,
    }
    assert TestClient(app).get("/envios/mis").json() == []
    assert conn.cantidad() == 1


# --- notificaciones: total y no leidas en una consulta -------------------------------------------


def test_listar_notificaciones_cuenta_total_y_no_leidas_juntas(limpiar):
    conn = ConexionContada({"COUNT(*) AS total": {"total": 7, "no_leidas": 3}, "FROM notificacion n": []})

    async def _conn():
        yield conn

    app.dependency_overrides[get_connection] = _conn
    app.dependency_overrides[get_current_usuario] = lambda: {
        "id": USUARIO, "tipo": "CLIENTE", "empresa_id": None,
    }
    respuesta = TestClient(app, raise_server_exceptions=False).get("/notificaciones?tamanio_pagina=5")
    assert respuesta.status_code == 200, respuesta.text
    assert respuesta.json() == {"total": 7, "no_leidas": 3, "pagina": 1, "tamanio_pagina": 5, "items": []}
    assert conn.cantidad() == 2  # conteo + pagina (antes 3)


# --- avisos al personal de una sucursal ----------------------------------------------------------


def test_avisar_al_personal_es_una_sola_sentencia_para_todos_los_destinatarios():
    conn = ConexionContada({})
    asyncio.run(
        avisar_personal_de_sucursal(
            conn, SUCURSAL, "ENCARGADO", "RESERVA", "Titulo", "Mensaje", "RESERVA", USUARIO
        )
    )
    assert conn.cantidad() == 1
    assert "INSERT INTO notificacion" in conn.ejecutado[0]
    assert "SELECT e.usuario_id" in conn.ejecutado[0]
    assert conn.llamadas[0][1] == (
        SUCURSAL, "ENCARGADO", "RESERVA", "Titulo", "Mensaje", "RESERVA", USUARIO,
    )


def test_la_alerta_de_stock_bajo_es_una_sola_sentencia():
    conn = ConexionContada({})
    asyncio.run(alertar_stock_bajo(conn, SUCURSAL, USUARIO))
    assert conn.cantidad() == 1  # antes: ids de la venta + prendas bajas + encargados + 1 INSERT por encargado
    sql = conn.ejecutado[0]
    assert "INSERT INTO notificacion" in sql
    assert "i.disponible <= i.stock_minimo" in sql
    assert "aviso.nombres IS NOT NULL" in sql  # sin prendas bajas no inserta nada
    assert conn.llamadas[0][1] == (SUCURSAL, USUARIO)


# --- sucursal_visible: el alcance por sucursal vive en un solo lugar -----------------------------


def test_el_admin_de_empresa_ve_todas_las_sucursales():
    assert sucursal_visible(staff(permisos=["sucursales.actualizar"])) is None


def test_el_resto_ve_solo_la_suya_y_sin_sucursal_es_403():
    assert sucursal_visible(staff(sucursal_id=SUCURSAL)) == SUCURSAL
    with pytest.raises(HTTPException) as error:
        sucursal_visible(staff(sucursal_id=None))
    assert error.value.status_code == 403
    assert error.value.detail == "Tu usuario no esta asignado a ninguna sucursal"
