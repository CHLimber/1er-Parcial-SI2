"""CU30 - Copias de seguridad (plataforma SaaS).

Dos alcances sobre la misma tabla `backup`:

  - GENERAL (todas las empresas): la corre sola `job_backup_automatico` cada dia y el SUPERADMIN
    puede lanzar otra a mano. `/backups/programacion` le dice cuando fue la ultima y cuando es la
    proxima. Solo la plataforma la ve (403 para el resto).
  - De una EMPRESA: la lanza a mano su administrador (la suya) o el SUPERADMIN (cualquiera). La
    copia lleva solo las filas de esa empresa, sin hashes de contrasena.

Las copias NO dependen de que la suscripcion este al dia: una empresa vencida igual puede
llevarse sus datos. Los permisos son `backups.leer/crear/eliminar`; que sea de la plataforma se
decide con `es_plataforma` (sin empresa), no con el rol.
"""

import json
from datetime import datetime, timezone
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import FileResponse

from app.core.auditoria import registrar_auditoria
from app.core.config import settings
from app.core.db import get_connection
from app.core.deps import requiere_permiso
from app.core.tenant import es_plataforma, no_encontrado
from app.modules.plataforma_saas.backups import servicio
from app.modules.plataforma_saas.backups.schemas import BackupEmpresaIn, BackupOut, ProgramacionOut

router = APIRouter(prefix="/backups", tags=["backups"])

puede_ver = requiere_permiso("backups.leer")
puede_crear = requiere_permiso("backups.crear")
puede_eliminar = requiere_permiso("backups.eliminar")

SELECT_BACKUP = """
SELECT b.id, b.empresa_id, e.nombre AS empresa, b.tipo::text AS tipo, b.estado::text AS estado,
       b.iniciado_en, b.terminado_en,
       EXTRACT(EPOCH FROM (b.terminado_en - b.iniciado_en))::float AS duracion_segundos,
       NULLIF(trim(u.nombre || ' ' || u.apellido), '') AS creado_por,
       b.tamano_bytes, b.total_tablas, b.total_filas, b.sha256, b.archivo, b.error, b.detalle
FROM backup b
LEFT JOIN empresa e ON e.id = b.empresa_id
LEFT JOIN usuario u ON u.id = b.creado_por_id
"""


def _out(fila: asyncpg.Record) -> BackupOut:
    datos = dict(fila)
    archivo = datos.pop("archivo")
    detalle = datos.pop("detalle")
    disponible = False
    if datos["estado"] == "COMPLETADO" and archivo:
        try:
            disponible = servicio.ruta_absoluta(archivo).is_file()
        except ValueError:
            disponible = False
    # asyncpg no tiene codec de jsonb configurado: llega como texto
    tablas = json.loads(detalle).get("tablas") if detalle else None
    return BackupOut(**datos, disponible=disponible, tablas=tablas)


def _exigir_plataforma(staff: dict) -> None:
    if not es_plataforma(staff):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="La copia general de la plataforma es solo del administrador de la plataforma",
        )


def _empresa_objetivo(staff: dict, pedida: UUID | None) -> UUID:
    """La empresa sobre la que se opera: la propia; la plataforma elige cualquiera."""
    if es_plataforma(staff):
        if pedida is None:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Indica la empresa")
        return pedida
    if staff["empresa_id"] is None or (pedida is not None and pedida != staff["empresa_id"]):
        raise no_encontrado("Empresa no encontrada")
    return staff["empresa_id"]


async def _backup_visible(conn: asyncpg.Connection, staff: dict, backup_id: UUID) -> asyncpg.Record:
    """La copia si el usuario puede verla: la plataforma ve todas; una empresa solo las suyas.
    Lo demas es 404, para no confirmar que existe."""
    fila = await conn.fetchrow(SELECT_BACKUP + "WHERE b.id = $1", backup_id)
    if fila is None or (not es_plataforma(staff) and fila["empresa_id"] != staff["empresa_id"]):
        raise no_encontrado("Copia de seguridad no encontrada")
    return fila


async def _crear(conn: asyncpg.Connection, staff: dict, empresa_id: UUID | None) -> BackupOut:
    if empresa_id is not None:
        existe = await conn.fetchval("SELECT 1 FROM empresa WHERE id = $1", empresa_id)
        if not existe:
            raise no_encontrado("Empresa no encontrada")
    try:
        backup_id = await servicio.iniciar_backup(
            conn, tipo="MANUAL", empresa_id=empresa_id, usuario_id=staff["id"]
        )
    except servicio.BackupEnCurso:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Ya hay una copia de seguridad en curso: espera a que termine",
        ) from None
    await registrar_auditoria(
        conn,
        usuario_id=staff["id"],
        entidad="backup",
        entidad_id=backup_id,
        accion="CREAR",
        datos_despues={"alcance": "GENERAL" if empresa_id is None else "EMPRESA", "empresa_id": empresa_id},
    )
    servicio.lanzar_en_segundo_plano(backup_id, empresa_id, "MANUAL")
    return _out(await conn.fetchrow(SELECT_BACKUP + "WHERE b.id = $1", backup_id))


@router.get("/programacion", response_model=ProgramacionOut)
async def programacion(
    staff: dict = Depends(puede_ver), conn: asyncpg.Connection = Depends(get_connection)
) -> ProgramacionOut:
    """Cuando corre la copia automatica: hora, proxima ejecucion y la ultima que se hizo."""
    _exigir_plataforma(staff)
    ahora = datetime.now(timezone.utc)
    ultima = await conn.fetchrow(
        SELECT_BACKUP + "WHERE b.tipo = 'AUTOMATICO' ORDER BY b.iniciado_en DESC LIMIT 1"
    )
    ultima_ok = await conn.fetchrow(
        SELECT_BACKUP
        + "WHERE b.tipo = 'AUTOMATICO' AND b.estado = 'COMPLETADO' ORDER BY b.iniciado_en DESC LIMIT 1"
    )
    activa = settings.backup_auto_activo
    return ProgramacionOut(
        activa=activa,
        frecuencia="Diaria",
        hora=servicio.hora_programada().strftime("%H:%M"),
        zona=servicio.ZONA_TEXTO,
        proxima_ejecucion=servicio.proxima_programada(ahora) if activa else None,
        retencion_automaticas=settings.backup_auto_retencion,
        retencion_manuales=settings.backup_manual_retencion,
        ultima=_out(ultima) if ultima else None,
        ultima_exitosa=_out(ultima_ok) if ultima_ok else None,
    )


@router.get("/plataforma", response_model=list[BackupOut])
async def listar_generales(
    limite: int = Query(50, ge=1, le=200),
    staff: dict = Depends(puede_ver),
    conn: asyncpg.Connection = Depends(get_connection),
) -> list[BackupOut]:
    """Las copias generales (todas las empresas), automaticas y manuales."""
    _exigir_plataforma(staff)
    filas = await conn.fetch(
        SELECT_BACKUP + "WHERE b.empresa_id IS NULL ORDER BY b.iniciado_en DESC LIMIT $1", limite
    )
    return [_out(f) for f in filas]


@router.post("/plataforma", response_model=BackupOut, status_code=status.HTTP_202_ACCEPTED)
async def crear_general(
    staff: dict = Depends(puede_crear), conn: asyncpg.Connection = Depends(get_connection)
) -> BackupOut:
    """Lanza ahora una copia general. Responde EN_CURSO y sigue en segundo plano."""
    _exigir_plataforma(staff)
    return await _crear(conn, staff, None)


@router.get("/empresa", response_model=list[BackupOut])
async def listar_de_empresa(
    empresa_id: UUID | None = Query(None),
    limite: int = Query(50, ge=1, le=200),
    staff: dict = Depends(puede_ver),
    conn: asyncpg.Connection = Depends(get_connection),
) -> list[BackupOut]:
    """Las copias de una empresa. La empresa ve solo las suyas; la plataforma, las de todas
    (o las de `empresa_id`)."""
    if es_plataforma(staff):
        filas = await conn.fetch(
            SELECT_BACKUP
            + "WHERE b.empresa_id IS NOT NULL AND ($1::uuid IS NULL OR b.empresa_id = $1) "
            "ORDER BY b.iniciado_en DESC LIMIT $2",
            empresa_id,
            limite,
        )
    else:
        propia = _empresa_objetivo(staff, empresa_id)
        filas = await conn.fetch(
            SELECT_BACKUP + "WHERE b.empresa_id = $1 ORDER BY b.iniciado_en DESC LIMIT $2",
            propia,
            limite,
        )
    return [_out(f) for f in filas]


@router.post("/empresa", response_model=BackupOut, status_code=status.HTTP_202_ACCEPTED)
async def crear_de_empresa(
    datos: BackupEmpresaIn | None = None,
    staff: dict = Depends(puede_crear),
    conn: asyncpg.Connection = Depends(get_connection),
) -> BackupOut:
    """Lanza ahora la copia manual de una empresa (la propia, o la que elija la plataforma)."""
    empresa_id = _empresa_objetivo(staff, datos.empresa_id if datos else None)
    return await _crear(conn, staff, empresa_id)


@router.get("/{backup_id}/descargar")
async def descargar(
    backup_id: UUID,
    staff: dict = Depends(puede_ver),
    conn: asyncpg.Connection = Depends(get_connection),
) -> FileResponse:
    fila = await _backup_visible(conn, staff, backup_id)
    salida = _out(fila)
    if salida.estado != "COMPLETADO":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="La copia todavia no esta lista")
    if not salida.disponible:
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail="El archivo de esta copia ya no esta en el servidor",
        )
    alcance = "plataforma"
    if fila["empresa_id"] is not None:
        alcance = await conn.fetchval("SELECT slug FROM empresa WHERE id = $1", fila["empresa_id"])
    return FileResponse(
        servicio.ruta_absoluta(fila["archivo"]),
        media_type="application/zip",
        filename=servicio.nombre_descarga(alcance, fila["iniciado_en"]),
    )


@router.delete("/{backup_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar(
    backup_id: UUID,
    staff: dict = Depends(puede_eliminar),
    conn: asyncpg.Connection = Depends(get_connection),
) -> None:
    fila = await _backup_visible(conn, staff, backup_id)
    if fila["estado"] == "EN_CURSO":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="La copia esta en curso: espera a que termine"
        )
    await conn.execute("DELETE FROM backup WHERE id = $1", backup_id)
    servicio.borrar_archivo(fila["archivo"])
    await registrar_auditoria(
        conn,
        usuario_id=staff["id"],
        entidad="backup",
        entidad_id=backup_id,
        accion="ELIMINAR",
        datos_antes={"tipo": fila["tipo"], "empresa_id": fila["empresa_id"], "estado": fila["estado"]},
    )
