"""Copias de seguridad (CU30): como se genera, se programa y se limpia una copia.

Una copia es un zip con `meta.json` y un `datos/<tabla>.ndjson` por tabla (una fila por linea,
tal como la devuelve `to_jsonb`: uuid, numeric, fechas y arreglos ya vienen bien escritos por
Postgres). No se usa pg_dump a proposito: la copia de UNA empresa tiene que filtrar filas por
tenant, cosa que pg_dump no sabe hacer, y ademas pg_dump exige la misma version de Postgres que
el servidor (en Railway cambia). Todo se lee dentro de UNA transaccion REPEATABLE READ de solo
lectura: la copia es una foto consistente aunque se este vendiendo mientras corre, y no bloquea
a nadie.

Dos disparadores, un mismo motor (`ejecutar_backup`):
  - AUTOMATICO: `job_backup_automatico`, una vez al dia a `backup_auto_hora` (hora de Bolivia),
    siempre la copia general de la plataforma.
  - MANUAL: el administrador de una empresa (la suya) o el SUPERADMIN (cualquiera, o la general).
    El endpoint responde enseguida con la copia EN_CURSO y la corrida sigue en segundo plano.
"""

import asyncio
import hashlib
import json
import logging
import re
import zipfile
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from uuid import UUID

import asyncpg

from app.core.config import settings
from app.core.db import get_pool
from app.modules.plataforma_saas.backups.tablas import (
    COLUMNAS_SENSIBLES,
    EXCLUIDAS_GENERAL,
    TABLAS_EMPRESA,
)

logger = logging.getLogger(__name__)

# Bolivia no tiene horario de verano: UTC-4 fijo, sin depender de la base de zonas horarias del
# sistema (que las imagenes slim de Docker y Windows no traen).
ZONA_BOLIVIA = timezone(timedelta(hours=-4))
ZONA_TEXTO = "America/La_Paz (UTC-4)"

LOTE_FILAS = 2000
MAX_REINTENTOS_AUTOMATICA = 3
ESPERA_REINTENTO = timedelta(minutes=30)
# Una copia EN_CURSO mas vieja que esto se da por muerta (el proceso cayo sin avisar)
EN_CURSO_VENCIDA = timedelta(hours=1)
FALLIDAS_CONSERVADAS = timedelta(days=30)

_NOMBRE_TABLA = re.compile(r"^[a-z_][a-z0-9_]*$")

# Referencias a las tareas en segundo plano: asyncio solo guarda referencias debiles y una tarea
# sin dueno puede ser recolectada a mitad de la copia.
_tareas: set[asyncio.Task] = set()


class BackupEnCurso(Exception):
    """Ya hay una copia corriendo para ese alcance."""


# ---------------------------------------------------------------------------
#  Programacion de la copia automatica
# ---------------------------------------------------------------------------


def hora_programada() -> time:
    """`backup_auto_hora` (HH:MM, hora de Bolivia); si esta mal escrita, 02:00 y un aviso."""
    try:
        horas, minutos = settings.backup_auto_hora.strip().split(":")
        return time(int(horas), int(minutos))
    except (ValueError, AttributeError):
        logger.warning("BACKUP_AUTO_HORA invalida (%r): se usa 02:00", settings.backup_auto_hora)
        return time(2, 0)


def _instante(dia: date) -> datetime:
    return datetime.combine(dia, hora_programada(), tzinfo=ZONA_BOLIVIA).astimezone(timezone.utc)


def ultima_programada(ahora: datetime) -> datetime:
    """El instante programado mas reciente que ya paso (en UTC)."""
    hoy = _instante(ahora.astimezone(ZONA_BOLIVIA).date())
    return hoy if hoy <= ahora else _instante(ahora.astimezone(ZONA_BOLIVIA).date() - timedelta(days=1))


def proxima_programada(ahora: datetime) -> datetime:
    """El siguiente instante programado (en UTC), estrictamente en el futuro."""
    return ultima_programada(ahora) + timedelta(days=1)


def debe_correr(
    ahora: datetime,
    programada: datetime,
    *,
    hechas: int,
    fallidas: int,
    ultimo_fallo: datetime | None,
) -> bool:
    """Decide si la copia automatica de la ventana que empezo en `programada` toca ahora.

    `hechas` = copias COMPLETADAS o EN_CURSO desde `programada`; `fallidas` = las FALLIDAS desde
    entonces. Si el backend estuvo apagado a la hora programada, corre apenas vuelve (la
    ventana sigue abierta hasta la siguiente hora programada). Una corrida fallida se reintenta
    hasta MAX_REINTENTOS_AUTOMATICA veces, separadas por ESPERA_REINTENTO, para no martillar
    cada minuto una causa que no se arregla sola."""
    if ahora < programada or hechas > 0:
        return False
    if fallidas >= MAX_REINTENTOS_AUTOMATICA:
        return False
    return ultimo_fallo is None or ahora - ultimo_fallo >= ESPERA_REINTENTO


# ---------------------------------------------------------------------------
#  Archivos
# ---------------------------------------------------------------------------


def _raiz() -> Path:
    return Path(settings.backups_dir).resolve()


def ruta_absoluta(relativa: str) -> Path:
    """Resuelve la ruta guardada en la base y se niega a salir de BACKUPS_DIR (la ruta la arma
    este modulo, pero la base es una entrada mas)."""
    raiz = _raiz()
    ruta = (raiz / relativa).resolve()
    if raiz not in ruta.parents:
        raise ValueError("Ruta de copia fuera de BACKUPS_DIR")
    return ruta


def _ruta_relativa(backup_id: UUID, empresa_id: UUID | None) -> str:
    carpeta = "general" if empresa_id is None else f"empresas/{empresa_id}"
    return f"{carpeta}/{backup_id}.zip"


def borrar_archivo(relativa: str | None) -> None:
    if not relativa:
        return
    try:
        ruta_absoluta(relativa).unlink(missing_ok=True)
    except (OSError, ValueError):
        logger.warning("No se pudo borrar el archivo de copia %s", relativa)


def nombre_descarga(tipo_alcance: str, iniciado_en: datetime) -> str:
    """`tipo_alcance` es el slug de la empresa o 'plataforma'. La fecha va en hora de Bolivia."""
    sello = iniciado_en.astimezone(ZONA_BOLIVIA).strftime("%Y%m%d-%H%M%S")
    return f"fashionstore-{tipo_alcance}-{sello}.zip"


def _sha256(ruta: Path) -> str:
    resumen = hashlib.sha256()
    with ruta.open("rb") as archivo:
        for bloque in iter(lambda: archivo.read(1024 * 1024), b""):
            resumen.update(bloque)
    return resumen.hexdigest()


# ---------------------------------------------------------------------------
#  Generacion
# ---------------------------------------------------------------------------


async def _consultas_general(conn: asyncpg.Connection) -> list[tuple[str, str, tuple]]:
    filas = await conn.fetch("SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY 1")
    consultas = []
    for fila in filas:
        nombre = fila["tablename"]
        if nombre in EXCLUIDAS_GENERAL:
            continue
        assert _NOMBRE_TABLA.match(nombre), nombre
        consultas.append((nombre, f'SELECT to_jsonb(t)::text FROM "{nombre}" t', ()))
    return consultas


def consultas_empresa(empresa_id: UUID) -> list[tuple[str, str, tuple]]:
    consultas = []
    for tabla in TABLAS_EMPRESA:
        sensibles = COLUMNAS_SENSIBLES.get(tabla.nombre)
        # las columnas sensibles son constantes de tablas.py, por eso van como literal: un
        # parametro que la consulta no usa lo rechaza Postgres
        quitar = f" - ARRAY[{', '.join(repr(c) for c in sensibles)}]::text[]" if sensibles else ""
        sql = f'SELECT (to_jsonb(t){quitar})::text FROM "{tabla.nombre}" t WHERE {tabla.donde}'
        consultas.append((tabla.nombre, sql, (empresa_id,) if "$1" in sql else ()))
    return consultas


async def _escribir_zip(
    conn: asyncpg.Connection,
    destino: Path,
    consultas: list[tuple[str, str, tuple]],
    meta: dict,
) -> dict[str, int]:
    """Vuelca las consultas al zip, de a lotes y sin cargar una tabla entera en memoria. Los
    bloques se escriben en un hilo para no frenar el resto de la API durante una copia grande."""
    conteos: dict[str, int] = {}
    destino.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destino, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        async with conn.transaction(isolation="repeatable_read", readonly=True):
            for nombre, sql, args in consultas:
                filas = 0
                with zf.open(f"datos/{nombre}.ndjson", "w", force_zip64=True) as salida:
                    cursor = await conn.cursor(sql, *args)
                    while lote := await cursor.fetch(LOTE_FILAS):
                        texto = "\n".join(fila[0] for fila in lote) + "\n"
                        await asyncio.to_thread(salida.write, texto.encode("utf-8"))
                        filas += len(lote)
                conteos[nombre] = filas
        meta = {**meta, "tablas": conteos, "total_filas": sum(conteos.values())}
        zf.writestr("meta.json", json.dumps(meta, ensure_ascii=False, indent=2))
    return conteos


async def iniciar_backup(
    conn: asyncpg.Connection, *, tipo: str, empresa_id: UUID | None, usuario_id: UUID | None
) -> UUID:
    """Registra la copia EN_CURSO. Lanza BackupEnCurso si ese alcance ya tiene una corriendo."""
    # una EN_CURSO vieja es de un proceso que murio: no debe bloquear para siempre
    await conn.execute(
        """
        UPDATE backup SET estado = 'FALLIDO', terminado_en = now(),
               error = 'Se interrumpio: el proceso se detuvo antes de terminar'
        WHERE estado = 'EN_CURSO' AND empresa_id IS NOT DISTINCT FROM $1
          AND iniciado_en < now() - $2::interval
        """,
        empresa_id,
        EN_CURSO_VENCIDA,
    )
    try:
        return await conn.fetchval(
            """
            INSERT INTO backup (empresa_id, tipo, creado_por_id)
            VALUES ($1, $2::tipo_backup, $3) RETURNING id
            """,
            empresa_id,
            tipo,
            usuario_id,
        )
    except asyncpg.UniqueViolationError as exc:
        raise BackupEnCurso from exc


async def ejecutar_backup(
    pool: asyncpg.Pool, backup_id: UUID, empresa_id: UUID | None, tipo: str
) -> None:
    """Corre la copia ya registrada y deja la fila COMPLETADA o FALLIDA. Nunca lanza (salvo la
    cancelacion del apagado): una falla se anota en la fila, que es lo que ve el administrador."""
    relativa = _ruta_relativa(backup_id, empresa_id)
    destino = ruta_absoluta(relativa)
    try:
        async with pool.acquire() as conn:
            empresa = None
            if empresa_id is None:
                consultas = await _consultas_general(conn)
            else:
                empresa = await conn.fetchrow(
                    "SELECT id, slug, nombre FROM empresa WHERE id = $1", empresa_id
                )
                if empresa is None:
                    raise RuntimeError("La empresa ya no existe")
                consultas = consultas_empresa(empresa_id)
            meta = {
                "version": 1,
                "alcance": "GENERAL" if empresa is None else "EMPRESA",
                "empresa": None if empresa is None else {
                    "id": str(empresa["id"]), "slug": empresa["slug"], "nombre": empresa["nombre"]
                },
                "generado_en": datetime.now(timezone.utc).isoformat(),
                "formato": "zip con datos/<tabla>.ndjson: una fila JSON por linea (to_jsonb)",
                "nota": (
                    "Copia de datos (no incluye las imagenes de /media). "
                    + ("" if empresa is None else "Sin hashes de contrasena.")
                ).strip(),
            }
            conteos = await _escribir_zip(conn, destino, consultas, meta)
            tamano = destino.stat().st_size
            sha = await asyncio.to_thread(_sha256, destino)
            await conn.execute(
                """
                UPDATE backup SET estado = 'COMPLETADO', terminado_en = now(), archivo = $2,
                       tamano_bytes = $3, total_tablas = $4, total_filas = $5, sha256 = $6,
                       detalle = $7::jsonb
                WHERE id = $1
                """,
                backup_id,
                relativa,
                tamano,
                len(conteos),
                sum(conteos.values()),
                sha,
                json.dumps({"tablas": conteos}),
            )
            await aplicar_retencion(conn, empresa_id, tipo)
    except asyncio.CancelledError:
        borrar_archivo(relativa)
        raise
    except Exception as exc:  # noqa: BLE001 - se informa en la fila, no se propaga
        logger.exception("Fallo la copia de seguridad %s", backup_id)
        borrar_archivo(relativa)
        try:
            async with pool.acquire() as conn:
                await conn.execute(
                    "UPDATE backup SET estado = 'FALLIDO', terminado_en = now(), error = $2 "
                    "WHERE id = $1",
                    backup_id,
                    f"{type(exc).__name__}: {exc}"[:500],
                )
        except Exception:  # noqa: BLE001
            logger.exception("Tampoco se pudo registrar la falla de la copia %s", backup_id)


def lanzar_en_segundo_plano(backup_id: UUID, empresa_id: UUID | None, tipo: str) -> None:
    tarea = asyncio.create_task(ejecutar_backup(get_pool(), backup_id, empresa_id, tipo))
    _tareas.add(tarea)
    tarea.add_done_callback(_tareas.discard)


async def aplicar_retencion(conn: asyncpg.Connection, empresa_id: UUID | None, tipo: str) -> int:
    """Conserva las ultimas N copias COMPLETADAS de cada alcance (empresa o general) y tipo, y
    borra el resto con su archivo; las FALLIDAS se limpian a los 30 dias."""
    conservar = (
        settings.backup_auto_retencion if tipo == "AUTOMATICO" else settings.backup_manual_retencion
    )
    sobrantes = await conn.fetch(
        """
        SELECT id, archivo FROM backup
        WHERE estado = 'COMPLETADO' AND tipo = $2::tipo_backup
          AND empresa_id IS NOT DISTINCT FROM $1
        ORDER BY iniciado_en DESC OFFSET $3
        """,
        empresa_id,
        tipo,
        max(conservar, 1),
    )
    viejas = await conn.fetch(
        "DELETE FROM backup WHERE estado = 'FALLIDO' AND iniciado_en < now() - $1::interval "
        "RETURNING id",
        FALLIDAS_CONSERVADAS,
    )
    for fila in sobrantes:
        borrar_archivo(fila["archivo"])
    if sobrantes:
        await conn.execute("DELETE FROM backup WHERE id = ANY($1::uuid[])", [f["id"] for f in sobrantes])
    return len(sobrantes) + len(viejas)


# ---------------------------------------------------------------------------
#  Job de la copia automatica
# ---------------------------------------------------------------------------


async def marcar_interrumpidas(conn: asyncpg.Connection) -> int:
    """Al arrancar, toda copia EN_CURSO es de un proceso anterior que murio a mitad de camino."""
    resultado = await conn.execute(
        """
        UPDATE backup SET estado = 'FALLIDO', terminado_en = now(),
               error = 'Se interrumpio: el servidor se reinicio mientras corria'
        WHERE estado = 'EN_CURSO'
        """
    )
    return int(resultado.split()[-1])


async def _corrida_automatica(conn: asyncpg.Connection, ahora: datetime) -> bool:
    programada = ultima_programada(ahora)
    fila = await conn.fetchrow(
        """
        SELECT count(*) FILTER (WHERE estado IN ('COMPLETADO', 'EN_CURSO')) AS hechas,
               count(*) FILTER (WHERE estado = 'FALLIDO') AS fallidas,
               max(iniciado_en) FILTER (WHERE estado = 'FALLIDO') AS ultimo_fallo
        FROM backup WHERE tipo = 'AUTOMATICO' AND iniciado_en >= $1
        """,
        programada,
    )
    if not debe_correr(
        ahora,
        programada,
        hechas=fila["hechas"],
        fallidas=fila["fallidas"],
        ultimo_fallo=fila["ultimo_fallo"],
    ):
        return False
    try:
        backup_id = await iniciar_backup(conn, tipo="AUTOMATICO", empresa_id=None, usuario_id=None)
    except BackupEnCurso:
        return False
    print("job_backup_automatico: copia general iniciada")
    await ejecutar_backup(get_pool(), backup_id, None, "AUTOMATICO")
    return True


async def job_backup_automatico(intervalo_segundos: int = 60) -> None:
    """Loop del `lifespan`: cada minuto mira si ya paso la hora programada del dia sin copia
    automatica hecha. Mirar el reloj cada minuto (y no dormir hasta la hora exacta) hace que
    sobreviva a reinicios y cambios de la hora programada, y recupera la copia del dia si el
    backend estaba apagado a esa hora. Si hay mas de una instancia, el indice unico
    ux_backup_en_curso deja correr solo a una."""
    if not settings.backup_auto_activo:
        print("job_backup_automatico: desactivado (BACKUP_AUTO_ACTIVO=false)")
        return
    try:
        async with get_pool().acquire() as conn:
            if interrumpidas := await marcar_interrumpidas(conn):
                print(f"job_backup_automatico: {interrumpidas} copia(s) quedaron a medias por un reinicio")
    except Exception as exc:  # noqa: BLE001
        print(f"job_backup_automatico: no se pudo limpiar copias interrumpidas ({exc!r})")
    while True:
        try:
            async with get_pool().acquire() as conn:
                await _corrida_automatica(conn, datetime.now(timezone.utc))
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001 - nunca debe tumbar el backend
            print(f"job_backup_automatico: fallo un ciclo ({exc!r}), reintenta en el proximo")
        await asyncio.sleep(intervalo_segundos)
