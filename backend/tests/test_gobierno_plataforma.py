"""Gobierno de la plataforma (SUPERADMIN): cuentas, roles y permisos de todas las empresas.
Sin Postgres: ConexionFalsa y dependency_overrides."""

from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient

from app.core.db import get_connection
from app.core.deps import get_staff_actual
from app.main import app
from app.modules.plataforma_saas.saas.gobierno_router import PERMISOS_MINIMOS_ADMIN
from tests.conexion_falsa import ConexionFalsa, staff

SUPER = UUID(int=1)


@pytest.fixture(autouse=True)
def limpiar():
    yield
    app.dependency_overrides.clear()


def _rol(nombre="CAJERO", empresa_id=None, usuarios=0, permisos=()):
    return {
        "id": 7,
        "nombre": nombre,
        "descripcion": None,
        "es_sistema": empresa_id is None,
        "empresa_id": empresa_id,
        "empresa": None,
        "usuarios": usuarios,
        "permisos": list(permisos),
    }


def _cuenta(**cambios):
    return {
        "id": uuid4(),
        "email": "alguien@ejemplo.bo",
        "nombre": "Ana",
        "apellido": "Rojas",
        "telefono": None,
        "tipo": "CLIENTE",
        "rol_id": None,
        "rol": None,
        "empresa_id": None,
        "empresa": None,
        "activo": True,
        "bloqueado": False,
        "ultimo_acceso": None,
        "creado_en": "2026-11-02T10:00:00Z",
        **cambios,
    }


def _cliente(respuestas, permisos=("empresas.leer", "empresas.actualizar")):
    conn = ConexionFalsa(respuestas)

    async def _conn():
        yield conn

    app.dependency_overrides[get_connection] = _conn
    app.dependency_overrides[get_staff_actual] = lambda: staff(
        id=SUPER, empresa_id=None, rol="SUPERADMIN", permisos=list(permisos)
    )
    return TestClient(app, raise_server_exceptions=False), conn


def _permisos_en_bd(*codigos_por_id):
    """Respuesta de `SELECT id, codigo, modulo FROM permiso WHERE id = ANY(...)`."""
    return {
        "FROM permiso WHERE id = ANY": lambda sql, args: [
            {"id": i, "codigo": c, "modulo": c.split(".")[0]} for i, c in codigos_por_id if i in args[0]
        ]
    }


# --- acceso: solo la plataforma -------------------------------------------------------------------


def test_un_admin_de_empresa_no_toca_roles_ni_cuentas_de_la_plataforma():
    cliente, _ = _cliente({}, permisos=("usuarios.actualizar", "roles.actualizar"))
    assert cliente.get("/saas/cuentas").status_code == 403
    assert cliente.get("/saas/roles").status_code == 403
    assert cliente.put("/saas/roles/7/permisos", json={"permisos": []}).status_code == 403
    assert cliente.post(f"/saas/cuentas/{uuid4()}/password", json={"password": "Nueva123!"}).status_code == 403


def test_quien_solo_consulta_no_modifica():
    cliente, _ = _cliente({}, permisos=("empresas.leer",))
    assert cliente.get("/saas/cuentas").status_code == 200
    assert cliente.put("/saas/roles/7/permisos", json={"permisos": []}).status_code == 403


# --- cuentas ---------------------------------------------------------------------------------------


def test_la_plataforma_no_se_da_de_baja_a_si_misma():
    cliente, conn = _cliente({})
    r = cliente.patch(f"/saas/cuentas/{SUPER}/estado", json={"activo": False})
    assert r.status_code == 409
    assert not conn.ejecuto("UPDATE usuario SET activo")


def test_dar_de_baja_a_una_clienta_la_desactiva_y_deja_rastro():
    clienta = _cuenta()
    cliente, conn = _cliente({"WHERE u.id = $1": clienta})
    r = cliente.patch(f"/saas/cuentas/{clienta['id']}/estado", json={"activo": False})
    assert r.status_code == 200
    assert conn.ejecuto_en_tx("UPDATE usuario SET activo")
    assert conn.ejecuto_en_tx("INSERT INTO auditoria")


def test_no_se_da_de_baja_a_personal_con_caja_abierta():
    personal = _cuenta(tipo="STAFF", rol_id=3, rol="CAJERO", empresa_id=uuid4(), empresa="Moda")
    cliente, conn = _cliente({"WHERE u.id = $1": personal, "FROM sesion_caja": 1})
    r = cliente.patch(f"/saas/cuentas/{personal['id']}/estado", json={"activo": False})
    assert r.status_code == 409
    assert not conn.ejecuto("UPDATE usuario SET activo")


def test_una_clienta_no_cambia_de_rol():
    clienta = _cuenta()
    cliente, conn = _cliente({"WHERE u.id = $1": clienta})
    r = cliente.put(
        f"/saas/cuentas/{clienta['id']}",
        json={"email": "x@ejemplo.bo", "nombre": "A", "apellido": "B", "rol_id": 2},
    )
    assert r.status_code == 422
    assert not conn.ejecuto("UPDATE usuario")


def test_el_personal_solo_toma_un_rol_valido_para_su_empresa():
    personal = _cuenta(tipo="STAFF", rol_id=3, rol="CAJERO", empresa_id=uuid4(), empresa="Moda")
    # el rol pedido no es del sistema (distinto de SUPERADMIN) ni de su empresa
    cliente, conn = _cliente({"WHERE u.id = $1": personal, "FROM rol\n             WHERE id = $1": None})
    r = cliente.put(
        f"/saas/cuentas/{personal['id']}",
        json={"email": "x@ejemplo.bo", "nombre": "A", "apellido": "B", "rol_id": 1},
    )
    assert r.status_code == 422
    assert not conn.ejecuto("UPDATE usuario")


def test_alta_de_otro_integrante_del_equipo():
    nuevo = _cuenta(tipo="STAFF", rol_id=1, rol="SUPERADMIN")
    cliente, conn = _cliente({"INSERT INTO usuario": nuevo["id"], "WHERE u.id = $1": nuevo})
    r = cliente.post(
        "/saas/equipo",
        json={"email": "otro@fashionstore.bo", "nombre": "Otro", "apellido": "Equipo", "password": "Segura123!"},
    )
    assert r.status_code == 201
    assert r.json()["rol"] == "SUPERADMIN"
    assert conn.ejecuto_en_tx("INSERT INTO usuario")


# --- roles y permisos -----------------------------------------------------------------------------


def test_superadmin_no_cambia_sus_permisos():
    cliente, conn = _cliente({"WHERE r.id = $1": _rol("SUPERADMIN")})
    r = cliente.put("/saas/roles/7/permisos", json={"permisos": []})
    assert r.status_code == 409
    assert not conn.ejecuto("DELETE FROM rol_permiso")


def test_los_permisos_de_la_plataforma_no_se_asignan_a_otros_roles():
    cliente, conn = _cliente({"WHERE r.id = $1": _rol("CAJERO"), **_permisos_en_bd((9, "empresas.actualizar"))})
    r = cliente.put("/saas/roles/7/permisos", json={"permisos": [9]})
    assert r.status_code == 422
    assert not conn.ejecuto("DELETE FROM rol_permiso")


def test_un_permiso_inexistente_se_rechaza():
    cliente, _ = _cliente({"WHERE r.id = $1": _rol("CAJERO"), **_permisos_en_bd()})
    assert cliente.put("/saas/roles/7/permisos", json={"permisos": [999]}).status_code == 422


def test_el_admin_conserva_usuarios_roles_y_suscripcion():
    en_bd = _permisos_en_bd((1, "usuarios.leer"), (2, "catalogo.leer"))
    cliente, conn = _cliente({"WHERE r.id = $1": _rol("ADMIN"), **en_bd})
    r = cliente.put("/saas/roles/7/permisos", json={"permisos": [1, 2]})
    assert r.status_code == 409
    assert "roles.actualizar" in r.json()["detail"]
    assert not conn.ejecuto("DELETE FROM rol_permiso")


def test_el_admin_con_lo_minimo_si_se_guarda():
    en_bd = _permisos_en_bd(*[(i + 1, c) for i, c in enumerate(PERMISOS_MINIMOS_ADMIN)])
    cliente, conn = _cliente({"WHERE r.id = $1": _rol("ADMIN"), **en_bd})
    ids = list(range(1, len(PERMISOS_MINIMOS_ADMIN) + 1))
    r = cliente.put("/saas/roles/7/permisos", json={"permisos": ids})
    assert r.status_code == 200
    assert conn.ejecuto_en_tx("DELETE FROM rol_permiso")
    assert conn.ejecuto_en_tx("INSERT INTO rol_permiso")
    assert len(conn.args_de("INSERT INTO rol_permiso")) == len(ids)
    assert conn.ejecuto_en_tx("INSERT INTO auditoria")


def test_se_puede_vaciar_un_rol_comun():
    cliente, conn = _cliente({"WHERE r.id = $1": _rol("CAJERO", permisos=[1, 2])})
    r = cliente.put("/saas/roles/7/permisos", json={"permisos": []})
    assert r.status_code == 200
    assert conn.ejecuto_en_tx("DELETE FROM rol_permiso")


def test_los_roles_que_nombra_el_codigo_no_se_renombran_ni_se_eliminan():
    cliente, conn = _cliente({"WHERE r.id = $1": _rol("ADMIN")})
    assert cliente.put("/saas/roles/7", json={"nombre": "JEFE"}).status_code == 409
    assert cliente.delete("/saas/roles/7").status_code == 409
    assert not conn.ejecuto("DELETE FROM rol WHERE")


def test_un_rol_con_usuarios_no_se_elimina():
    cliente, conn = _cliente({"WHERE r.id = $1": _rol("SUPERVISOR", empresa_id=uuid4(), usuarios=2)})
    assert cliente.delete("/saas/roles/7").status_code == 409
    assert not conn.ejecuto("DELETE FROM rol WHERE")


def test_un_rol_propio_sin_usuarios_se_elimina():
    cliente, conn = _cliente({"WHERE r.id = $1": _rol("SUPERVISOR", empresa_id=uuid4())})
    assert cliente.delete("/saas/roles/7").status_code == 204
    assert conn.ejecuto_en_tx("DELETE FROM rol WHERE")


def test_un_rol_del_sistema_nuevo_no_puede_chocar_con_otro_nombre():
    cliente, conn = _cliente({"SELECT 1 FROM rol WHERE nombre = $1": 1})
    r = cliente.post("/saas/roles", json={"nombre": "supervisor"})
    assert r.status_code == 409
    assert not conn.ejecuto("INSERT INTO rol")


def test_crear_un_rol_del_sistema_lo_marca_compartido():
    nuevo = _rol("SUPERVISOR")
    cliente, conn = _cliente({"INSERT INTO rol": 7, "WHERE r.id = $1": nuevo})
    r = cliente.post("/saas/roles", json={"nombre": "supervisor"})
    assert r.status_code == 201
    empresa_id, nombre, _, es_sistema = conn.args_de("INSERT INTO rol (")
    assert (empresa_id, nombre, es_sistema) == (None, "SUPERVISOR", True)
