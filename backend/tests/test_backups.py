"""CU30 - Copias de seguridad: que tablas entran en la copia de una empresa, cuando le toca correr
a la automatica, quien puede ver y lanzar cada copia y la retencion. Sin Postgres: la generacion
real del zip se probo contra la base de Docker (ver PENDIENTES 7.1)."""

import re
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4

import asyncpg
import pytest
from fastapi.testclient import TestClient

from app.core.config import settings
from app.core.db import get_connection
from app.core.deps import get_staff_actual
from app.main import app
from app.modules.plataforma_saas.backups import router as router_backups
from app.modules.plataforma_saas.backups import servicio
from app.modules.plataforma_saas.backups.tablas import (
    COLUMNAS_SENSIBLES,
    EXCLUIDAS_EMPRESA,
    TABLAS_EMPRESA,
)
from tests.conexion_falsa import EMPRESA, ConexionFalsa, staff

ESQUEMA = Path(__file__).resolve().parents[2] / "db" / "01_schema.sql"


# --- que tablas lleva cada copia -----------------------------------------------------------------


def _tablas_del_esquema() -> set[str]:
    return set(re.findall(r"^CREATE TABLE (\w+)", ESQUEMA.read_text(encoding="utf-8"), re.MULTILINE))


def test_toda_tabla_del_esquema_esta_clasificada_para_la_copia_de_empresa():
    """Si alguien agrega una tabla y no la pone en tablas.py, este test avisa: sino la copia
    de las empresas la dejaria afuera sin que nadie lo note."""
    clasificadas = {t.nombre for t in TABLAS_EMPRESA} | set(EXCLUIDAS_EMPRESA)
    assert _tablas_del_esquema() - clasificadas == set(), "tablas sin clasificar en tablas.py"
    assert clasificadas - _tablas_del_esquema() == set(), "tablas de tablas.py que ya no existen"


def test_no_hay_tablas_repetidas_ni_a_la_vez_incluidas_y_excluidas():
    nombres = [t.nombre for t in TABLAS_EMPRESA]
    assert len(nombres) == len(set(nombres))
    assert not set(nombres) & set(EXCLUIDAS_EMPRESA)


def test_las_tablas_de_negocio_se_filtran_por_empresa():
    """Solo los catalogos compartidos van sin filtro; todo lo demas cuelga de $1."""
    sin_filtro = {t.nombre for t in TABLAS_EMPRESA if t.donde == "TRUE"}
    assert sin_filtro == {"talla", "color", "permiso", "plan"}
    assert all("$1" in t.donde for t in TABLAS_EMPRESA if t.nombre not in sin_filtro)


def test_la_copia_de_empresa_no_lleva_el_hash_de_contrasena():
    consultas = {nombre: (sql, args) for nombre, sql, args in servicio.consultas_empresa(EMPRESA)}
    sql, args = consultas["usuario"]
    assert "ARRAY['password_hash']::text[]" in sql
    assert args == (EMPRESA,)
    assert COLUMNAS_SENSIBLES["usuario"] == ["password_hash"]


def test_los_parametros_solo_se_pasan_si_la_consulta_los_usa():
    """Postgres rechaza un parametro que la consulta no referencia."""
    for _nombre, sql, args in servicio.consultas_empresa(EMPRESA):
        assert args == ((EMPRESA,) if "$1" in sql else ())


# --- archivos ------------------------------------------------------------------------------------


def test_la_ruta_de_una_copia_no_puede_salir_de_backups_dir():
    assert servicio.ruta_absoluta("general/x.zip").name == "x.zip"
    for mala in ("../x.zip", "general/../../x.zip", "/etc/passwd"):
        with pytest.raises(ValueError):
            servicio.ruta_absoluta(mala)


def test_nombre_de_descarga_usa_la_hora_de_bolivia():
    # 02:00 UTC es la noche anterior en La Paz (UTC-4)
    inicio = datetime(2026, 11, 2, 2, 5, 9, tzinfo=timezone.utc)
    assert servicio.nombre_descarga("andina", inicio) == "fashionstore-andina-20261101-220509.zip"


# --- cuando corre la automatica ------------------------------------------------------------------


@pytest.fixture
def a_las_dos(monkeypatch):
    monkeypatch.setattr(settings, "backup_auto_hora", "02:00")


def test_la_hora_programada_es_la_de_bolivia(a_las_dos):
    # 02:00 en La Paz = 06:00 UTC
    ahora = datetime(2026, 11, 1, 12, 0, tzinfo=timezone.utc)
    assert servicio.ultima_programada(ahora) == datetime(2026, 11, 1, 6, 0, tzinfo=timezone.utc)
    assert servicio.proxima_programada(ahora) == datetime(2026, 11, 2, 6, 0, tzinfo=timezone.utc)


def test_antes_de_la_hora_la_ultima_programada_es_la_de_ayer(a_las_dos):
    ahora = datetime(2026, 11, 1, 5, 59, tzinfo=timezone.utc)
    assert servicio.ultima_programada(ahora) == datetime(2026, 10, 31, 6, 0, tzinfo=timezone.utc)


def test_hora_mal_escrita_cae_en_las_dos(monkeypatch):
    monkeypatch.setattr(settings, "backup_auto_hora", "madrugada")
    assert servicio.hora_programada().strftime("%H:%M") == "02:00"


PROGRAMADA = datetime(2026, 11, 1, 6, 0, tzinfo=timezone.utc)


def _toca(minutos_despues: float, **datos) -> bool:
    base = {"hechas": 0, "fallidas": 0, "ultimo_fallo": None} | datos
    return servicio.debe_correr(PROGRAMADA + timedelta(minutes=minutos_despues), PROGRAMADA, **base)


def test_no_corre_antes_de_la_hora():
    assert _toca(-1) is False


def test_corre_pasada_la_hora_si_hoy_no_se_hizo():
    assert _toca(0) is True
    # backend apagado a la hora: apenas vuelve, recupera la copia del dia
    assert _toca(600) is True


def test_no_corre_dos_veces_el_mismo_dia():
    assert _toca(30, hechas=1) is False


def test_si_fallo_reintenta_a_la_media_hora_y_se_rinde_al_tercero():
    fallo = PROGRAMADA + timedelta(minutes=1)
    assert servicio.debe_correr(
        fallo + timedelta(minutes=5), PROGRAMADA, hechas=0, fallidas=1, ultimo_fallo=fallo
    ) is False
    assert servicio.debe_correr(
        fallo + timedelta(minutes=31), PROGRAMADA, hechas=0, fallidas=1, ultimo_fallo=fallo
    ) is True
    assert servicio.debe_correr(
        fallo + timedelta(hours=3), PROGRAMADA, hechas=0, fallidas=3, ultimo_fallo=fallo
    ) is False


# --- quien puede ver y lanzar que ----------------------------------------------------------------


@pytest.fixture
def cliente():
    yield
    app.dependency_overrides.clear()


def _como(usuario: dict, respuestas: dict | None = None) -> tuple[TestClient, ConexionFalsa]:
    conn = ConexionFalsa(respuestas or {})

    async def _conn():
        yield conn

    app.dependency_overrides[get_connection] = _conn
    app.dependency_overrides[get_staff_actual] = lambda: usuario
    return TestClient(app, raise_server_exceptions=False), conn


ADMIN = staff(permisos=["backups.leer", "backups.crear", "backups.eliminar", "sucursales.actualizar"])
PLATAFORMA = staff(
    empresa_id=None,
    permisos=["backups.leer", "backups.crear", "backups.eliminar", "empresas.leer"],
)
SIN_PERMISO = staff(permisos=["reportes.leer"])


def _fila(**cambios) -> dict:
    fila = {
        "id": uuid4(), "empresa_id": EMPRESA, "empresa": "Andina", "tipo": "MANUAL",
        "estado": "EN_CURSO", "iniciado_en": datetime(2026, 11, 1, tzinfo=timezone.utc),
        "terminado_en": None, "duracion_segundos": None, "creado_por": "Ana Admin",
        "tamano_bytes": None, "total_tablas": None, "total_filas": None, "sha256": None,
        "archivo": None, "error": None, "detalle": None,
    }
    return fila | cambios


def test_sin_permiso_de_backups_no_se_ve_nada(cliente):
    http, _ = _como(SIN_PERMISO)
    assert http.get("/backups/empresa").status_code == 403
    assert http.post("/backups/empresa").status_code == 403


def test_la_copia_general_y_su_programacion_son_solo_de_la_plataforma(cliente):
    http, _ = _como(ADMIN)
    assert http.get("/backups/programacion").status_code == 403
    assert http.get("/backups/plataforma").status_code == 403
    assert http.post("/backups/plataforma").status_code == 403


def test_la_plataforma_ve_la_programacion_con_hora_y_proxima_ejecucion(cliente, a_las_dos):
    http, _ = _como(PLATAFORMA)
    respuesta = http.get("/backups/programacion")
    assert respuesta.status_code == 200
    cuerpo = respuesta.json()
    assert cuerpo["hora"] == "02:00"
    assert cuerpo["frecuencia"] == "Diaria"
    assert cuerpo["proxima_ejecucion"] is not None
    assert cuerpo["ultima"] is None


def test_el_admin_de_empresa_solo_lista_las_de_su_empresa(cliente):
    pedidos = []

    def _suyas(sql, args):
        pedidos.append(args)
        return [_fila()]

    http, _ = _como(ADMIN, {"WHERE b.empresa_id = $1": _suyas})
    respuesta = http.get("/backups/empresa")
    assert respuesta.status_code == 200
    assert respuesta.json()[0]["empresa"] == "Andina"
    assert pedidos == [(EMPRESA, 50)]


def test_el_admin_no_puede_pedir_las_de_otra_empresa(cliente):
    http, _ = _como(ADMIN)
    assert http.get(f"/backups/empresa?empresa_id={uuid4()}").status_code == 404


def test_la_plataforma_tiene_que_indicar_la_empresa_para_crear(cliente):
    http, _ = _como(PLATAFORMA)
    assert http.post("/backups/empresa").status_code == 422


def test_el_admin_no_puede_lanzar_la_copia_de_otra_empresa(cliente):
    http, _ = _como(ADMIN)
    assert http.post("/backups/empresa", json={"empresa_id": str(uuid4())}).status_code == 404


def test_el_admin_lanza_la_copia_manual_de_su_empresa(cliente, monkeypatch):
    lanzadas = []
    monkeypatch.setattr(servicio, "lanzar_en_segundo_plano", lambda *a: lanzadas.append(a))
    nuevo = uuid4()
    http, conn = _como(
        ADMIN,
        {
            "SELECT 1 FROM empresa": 1,
            "INSERT INTO backup": nuevo,
            "WHERE b.id = $1": _fila(id=nuevo),
        },
    )
    respuesta = http.post("/backups/empresa")
    assert respuesta.status_code == 202
    assert respuesta.json()["estado"] == "EN_CURSO"
    assert lanzadas == [(nuevo, EMPRESA, "MANUAL")]
    assert conn.ejecuto("INSERT INTO auditoria")  # queda en la bitacora


def test_la_plataforma_lanza_la_general_a_mano(cliente, monkeypatch):
    lanzadas = []
    monkeypatch.setattr(servicio, "lanzar_en_segundo_plano", lambda *a: lanzadas.append(a))
    nuevo = uuid4()
    http, _ = _como(
        PLATAFORMA,
        {"INSERT INTO backup": nuevo, "WHERE b.id = $1": _fila(id=nuevo, empresa_id=None, empresa=None)},
    )
    assert http.post("/backups/plataforma").status_code == 202
    assert lanzadas == [(nuevo, None, "MANUAL")]


def test_una_segunda_copia_mientras_corre_la_primera_da_409(cliente, monkeypatch):
    monkeypatch.setattr(servicio, "lanzar_en_segundo_plano", lambda *a: pytest.fail("no debia lanzar"))

    def _ya_hay_una(sql):
        raise asyncpg.UniqueViolationError("ux_backup_en_curso")

    http, _ = _como(ADMIN, {"SELECT 1 FROM empresa": 1, "INSERT INTO backup": _ya_hay_una})
    respuesta = http.post("/backups/empresa")
    assert respuesta.status_code == 409
    assert "en curso" in respuesta.json()["detail"]


def test_no_se_descarga_ni_se_borra_la_copia_de_otra_empresa(cliente):
    ajena = _fila(empresa_id=uuid4(), estado="COMPLETADO", archivo="x.zip")
    http, conn = _como(ADMIN, {"WHERE b.id = $1": ajena})
    assert http.get(f"/backups/{ajena['id']}/descargar").status_code == 404
    assert http.delete(f"/backups/{ajena['id']}").status_code == 404
    assert not conn.ejecuto("DELETE FROM backup")


def test_la_plataforma_si_puede_descargar_la_de_cualquier_empresa(cliente, tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "backups_dir", str(tmp_path))
    (tmp_path / "empresas").mkdir()
    (tmp_path / "empresas" / "a.zip").write_bytes(b"PK")
    fila = _fila(empresa_id=uuid4(), estado="COMPLETADO", archivo="empresas/a.zip")
    http, _ = _como(PLATAFORMA, {"WHERE b.id = $1": fila, "SELECT slug FROM empresa": "andina"})
    respuesta = http.get(f"/backups/{fila['id']}/descargar")
    assert respuesta.status_code == 200
    assert respuesta.content == b"PK"
    assert "fashionstore-andina-" in respuesta.headers["content-disposition"]


def test_una_copia_que_aun_corre_no_se_descarga_ni_se_borra(cliente):
    en_curso = _fila()
    http, conn = _como(ADMIN, {"WHERE b.id = $1": en_curso})
    assert http.get(f"/backups/{en_curso['id']}/descargar").status_code == 409
    assert http.delete(f"/backups/{en_curso['id']}").status_code == 409
    assert not conn.ejecuto("DELETE FROM backup")


def test_si_el_archivo_se_perdio_la_descarga_da_410(cliente, tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "backups_dir", str(tmp_path))
    fila = _fila(estado="COMPLETADO", archivo="empresas/no-esta.zip")
    http, _ = _como(ADMIN, {"WHERE b.id = $1": fila})
    assert http.get(f"/backups/{fila['id']}/descargar").status_code == 410
    assert router_backups._out(fila).disponible is False


def test_eliminar_borra_la_fila_el_archivo_y_deja_auditoria(cliente, monkeypatch):
    borrados = []
    monkeypatch.setattr(servicio, "borrar_archivo", borrados.append)
    fila = _fila(estado="COMPLETADO", archivo="empresas/a.zip")
    http, conn = _como(ADMIN, {"WHERE b.id = $1": fila})
    assert http.delete(f"/backups/{fila['id']}").status_code == 204
    assert conn.ejecuto("DELETE FROM backup")
    assert conn.ejecuto("INSERT INTO auditoria")
    assert borrados == ["empresas/a.zip"]


# --- retencion -----------------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_la_retencion_borra_los_archivos_que_sobran(monkeypatch):
    borrados = []
    monkeypatch.setattr(servicio, "borrar_archivo", borrados.append)
    viejas = [{"id": uuid4(), "archivo": "general/1.zip"}, {"id": uuid4(), "archivo": "general/2.zip"}]
    conn = ConexionFalsa({"OFFSET $3": viejas, "RETURNING id": []})
    cantidad = await servicio.aplicar_retencion(conn, None, "AUTOMATICO")
    assert cantidad == 2
    assert borrados == ["general/1.zip", "general/2.zip"]
    assert conn.ejecuto("DELETE FROM backup WHERE id = ANY")
