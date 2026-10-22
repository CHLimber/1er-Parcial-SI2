"""Modulo G - Analitica inteligente con Machine Learning (etapas 6 a 9: integracion, reportes
inteligentes y dashboard).

Los modelos se entrenan con datos SINTETICOS (sinteticos.py, modelos.py) y se APLICAN a los
datos reales de la empresa del usuario:

  - Pronostico de demanda (supervisado) de los proximos `horizonte` dias por sucursal y tipo de
    prenda (verano / invierno / atemporal / accesorio). Las ventas reales de un tenant son mucho
    mas chicas que las sinteticas, asi que los rezagos se llevan a la escala de entrenamiento con
    la media sintetica de su combinacion clima x tipo, se predice y se vuelve a la escala real.
  - Segmentacion de la cartera de clientas (no supervisado, KMeans) con las mismas variables
    que los datos sinteticos, calculadas sobre las ventas reales de la empresa.
  - Deteccion de dias atipicos (no supervisado, IsolationForest) en las ventas diarias reales
    de cada sucursal.

Todo se recorta a la empresa del usuario (como el resto del sistema); los modelos no ven datos
de ningun tenant al entrenarse. Plan: la funcion `analitica_ml` (Profesional).
"""

import csv
import io
from datetime import date, timedelta
from typing import Any
from uuid import UUID

import asyncpg
import numpy as np
from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool

from app.core.auditoria import registrar_auditoria
from app.core.db import get_connection
from app.core.plan import exigir_funcion_empresa, requiere_funcion_plan
from app.core.tenant import alcance_sucursal, es_plataforma, exigir_sucursal, no_encontrado
from app.modules.inteligencia_de_negocio.analitica import modelos, sinteticos

router = APIRouter(prefix="/analitica", tags=["analitica"])

puede_ver = requiere_funcion_plan("analitica_ml", "analitica.leer")
puede_entrenar = requiere_funcion_plan(None, "analitica.actualizar")

CLIMA_CIUDAD = {
    "SANTA_CRUZ": "CALIDO", "TRINIDAD": "CALIDO", "COBIJA": "CALIDO",
    "LA_PAZ": "FRIO", "EL_ALTO": "FRIO", "ORURO": "FRIO", "POTOSI": "FRIO",
}  # el resto TEMPLADO, mismo criterio que el reparto de stock del seed


class EntrenarIn(BaseModel):
    dias: int = Field(default=540, ge=120, le=1500)
    clientes: int = Field(default=1500, ge=200, le=10000)
    semilla: int = Field(default=42, ge=0, le=10_000)


def _empresa(staff: dict, pedida: UUID | None) -> UUID:
    if staff.get("empresa_id") is not None:
        return staff["empresa_id"]
    if es_plataforma(staff) and pedida is not None:
        return pedida
    raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Indica la empresa")


# ---------------------------------------------------------------------
#  MODELO
# ---------------------------------------------------------------------


@router.get("/modelo")
async def ver_modelo(staff: dict = Depends(puede_ver)) -> dict[str, Any]:
    """Metricas de evaluacion de los modelos entrenados (etapa 5)."""
    return modelos.resumen_publico(await run_in_threadpool(modelos.cargar))


@router.post("/entrenar")
async def reentrenar(
    body: EntrenarIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_entrenar),
) -> dict[str, Any]:
    """CU29 - Entrenar / actualizar modelos: regenera los datos sinteticos con la semilla dada y
    vuelve a entrenar y evaluar. Solo datos sinteticos: no mezcla informacion de ningun tenant."""
    paquete = await run_in_threadpool(modelos.entrenar, body.dias, body.clientes, body.semilla)
    await registrar_auditoria(
        conn, usuario_id=staff["id"], entidad="modelo_ml", entidad_id="fashionstore",
        accion="ACTUALIZAR", datos_despues=body.model_dump(),
    )
    return modelos.resumen_publico(paquete)


@router.get("/datos-sinteticos")
async def datos_sinteticos(
    tipo: str = Query(default="demanda", pattern="^(demanda|clientes)$"),
    formato: str = Query(default="json", pattern="^(json|csv)$"),
    limite: int = Query(default=50, ge=1, le=20000),
    semilla: int = Query(default=42, ge=0, le=10_000),
    staff: dict = Depends(puede_ver),
):
    """Etapa 1 a la vista: una muestra (o el CSV completo) de los datos con que se entrena."""
    if tipo == "demanda":
        X, y, fechas = await run_in_threadpool(sinteticos.generar_demanda, 540, semilla)
        columnas = ["fecha", *sinteticos.COLUMNAS_DEMANDA, "unidades"]
        filas = [[f.isoformat(), *map(lambda v: round(float(v), 4), x), int(u)]
                 for f, x, u in zip(fechas, X, y)]
    else:
        X, perfiles = await run_in_threadpool(sinteticos.generar_clientes, 1500, semilla)
        columnas = [*sinteticos.COLUMNAS_CLIENTES, "perfil_generador"]
        filas = [[*map(lambda v: round(float(v), 3), x), p] for x, p in zip(X, perfiles)]
    filas = filas[:limite]
    if formato == "csv":
        salida = io.StringIO()
        escritor = csv.writer(salida)
        escritor.writerow(columnas)
        escritor.writerows(filas)
        return StreamingResponse(
            iter([salida.getvalue()]),
            media_type="text/csv",
            headers={"Content-Disposition": f'attachment; filename="sinteticos_{tipo}.csv"'},
        )
    return {"columnas": columnas, "filas": filas, "total_generado": len(filas)}


# ---------------------------------------------------------------------
#  DASHBOARD (aplicado a la empresa)
# ---------------------------------------------------------------------

SQL_UNIDADES = """
SELECT v.sucursal_id, v.fecha::date AS dia,
       CASE WHEN c.slug = 'accesorios' OR padre.slug = 'accesorios' THEN 'ACCESORIO'
            WHEN t.tipo = 'PRIMAVERA_VERANO' THEN 'VERANO'
            WHEN t.tipo = 'OTONO_INVIERNO' THEN 'INVIERNO'
            ELSE 'ATEMPORAL' END AS tipo,
       SUM(vd.cantidad)::int AS unidades
FROM venta v
JOIN sucursal s           ON s.id = v.sucursal_id
JOIN venta_detalle vd     ON vd.venta_id = v.id
JOIN producto_variante pv ON pv.id = vd.variante_id
JOIN producto p           ON p.id = pv.producto_id
JOIN categoria c          ON c.id = p.categoria_id
LEFT JOIN categoria padre ON padre.id = c.categoria_padre_id
LEFT JOIN temporada t     ON t.id = p.temporada_id
WHERE s.empresa_id = $1 AND v.sucursal_id = ANY($2::uuid[])
  AND v.estado IN ('PAGADA', 'ENTREGADA') AND v.fecha >= CURRENT_DATE - $3::int
GROUP BY 1, 2, 3
"""


def _pronosticar(paquete: dict, sucursales: list[dict], unidades: dict, horizonte: int) -> dict:
    """unidades[(sucursal, tipo)][dia] = real. Devuelve el pronostico diario por sucursal/tipo.
    Recursivo (cada dia predicho alimenta los rezagos del siguiente) pero vectorizado: todas las
    combinaciones sucursal x tipo se predicen juntas, una llamada al modelo por dia."""
    bosque = paquete["demanda"]["modelo"]
    medias = paquete["demanda"]["medias_sinteticas"]
    hoy = date.today()
    combos = []
    for s in sucursales:
        clima = CLIMA_CIUDAD.get(s["ciudad"], "TEMPLADO")
        for tipo in sinteticos.TIPOS:
            reales = unidades.get((s["id"], tipo), {})
            historia = [float(reales.get(hoy - timedelta(days=d), 0)) for d in range(28, 0, -1)]
            escala = medias[f"{clima}|{tipo}"] / max(float(np.mean(historia)), 0.05)
            combos.append({
                "clave": (s["id"], tipo), "clima": clima, "tipo": tipo, "escala": escala,
                "serie": [h * escala for h in historia],  # en escala sintetica
                "real_ultimos": sum(historia[-horizonte:]), "pronostico": [],
            })
    for n in range(horizonte):
        dia = hoy + timedelta(days=n)
        X = np.array([
            sinteticos.fila_demanda(dia, c["clima"], c["tipo"], 0, 1.0, c["serie"][-7],
                                    float(np.mean(c["serie"][-7:])))
            for c in combos
        ])
        for c, pred in zip(combos, bosque.predict(X)):
            pred = max(float(pred), 0.0)
            c["serie"].append(pred)
            c["pronostico"].append(pred / c["escala"])
    return {c["clave"]: {"pronostico": c["pronostico"], "real_ultimos": c["real_ultimos"]} for c in combos}


def _features_clientes(filas: list[asyncpg.Record]) -> np.ndarray:
    return np.array([[f["compras_90d"], float(f["monto_total"]), float(f["recencia_dias"]),
                      float(f["ticket_promedio"]), float(f["pct_promo"]), float(f["pct_online"])]
                     for f in filas])


@router.get("/dashboard")
async def dashboard(
    sucursal_id: UUID | None = Query(default=None),
    horizonte: int = Query(default=14, ge=7, le=30),
    empresa_id: UUID | None = Query(default=None, description="Solo la plataforma la elige"),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> dict[str, Any]:
    """CU28 - Dashboard analitico: indicadores, pronostico, segmentos, anomalias y las metricas de
    los modelos, con una lista de hallazgos en lenguaje natural (reporte inteligente)."""
    empresa = _empresa(staff, empresa_id)
    if staff.get("empresa_id") is None:
        await exigir_funcion_empresa(conn, empresa, "analitica_ml")
    pedida = alcance_sucursal(staff, sucursal_id) if staff.get("empresa_id") else sucursal_id
    await exigir_sucursal(conn, pedida, empresa)
    sucursales = [dict(f) for f in await conn.fetch(
        """SELECT id, nombre, ciudad::text AS ciudad FROM sucursal
            WHERE empresa_id = $1 AND activa AND ($2::uuid IS NULL OR id = $2) ORDER BY nombre""",
        empresa, pedida,
    )]
    if not sucursales:
        raise no_encontrado("La empresa no tiene sucursales activas")
    ids = [s["id"] for s in sucursales]
    paquete = await run_in_threadpool(modelos.cargar)

    # --- pronostico de demanda
    unidades: dict = {}
    for f in await conn.fetch(SQL_UNIDADES, empresa, ids, 60):
        unidades.setdefault((f["sucursal_id"], f["tipo"]), {})[f["dia"]] = f["unidades"]
    pron = await run_in_threadpool(_pronosticar, paquete, sucursales, unidades, horizonte)
    hoy = date.today()
    por_dia = [
        {"dia": (hoy + timedelta(days=n)).isoformat(),
         **{t.lower(): round(sum(pron[(s["id"], t)]["pronostico"][n] for s in sucursales), 1)
            for t in sinteticos.TIPOS}}
        for n in range(horizonte)
    ]
    for fila in por_dia:
        fila["total"] = round(sum(fila[t.lower()] for t in sinteticos.TIPOS), 1)
    por_sucursal = []
    for s in sucursales:
        for t in sinteticos.TIPOS:
            p = pron[(s["id"], t)]
            futuro = sum(p["pronostico"])
            pasado = p["real_ultimos"]
            por_sucursal.append({
                "sucursal": s["nombre"], "tipo": t, "real_ultimos_dias": round(pasado, 1),
                "pronostico": round(futuro, 1),
                "variacion_pct": round((futuro - pasado) / pasado * 100, 1) if pasado >= 1 else None,
            })

    # --- segmentacion de clientas
    clientes = await conn.fetch(
        """
        SELECT u.id, (u.nombre || ' ' || u.apellido) AS nombre, u.email,
               COUNT(*) FILTER (WHERE v.fecha >= now() - interval '90 days')::int AS compras_90d,
               COALESCE(SUM(v.total) FILTER (WHERE v.fecha >= now() - interval '90 days'), 0) AS monto_total,
               EXTRACT(EPOCH FROM now() - MAX(v.fecha)) / 86400 AS recencia_dias,
               AVG(v.total) AS ticket_promedio,
               AVG((v.promocion_id IS NOT NULL)::int) AS pct_promo,
               AVG((v.canal IN ('WEB','MOVIL'))::int) AS pct_online
        FROM venta v
        JOIN sucursal s ON s.id = v.sucursal_id
        JOIN usuario u  ON u.id = v.usuario_id
        WHERE s.empresa_id = $1 AND v.sucursal_id = ANY($2::uuid[])
          AND v.estado IN ('PAGADA','ENTREGADA')
        GROUP BY u.id
        """,
        empresa, ids,
    )
    seg = paquete["clientes"]
    segmentos = []
    if clientes:
        X = _features_clientes(clientes)
        etiquetas = seg["modelo"].predict(seg["escalador"].transform(X))
        for k, nombre in enumerate(seg["nombres"]):
            miembros = [c for c, e in zip(clientes, etiquetas) if e == k]
            if not miembros:
                continue
            Xm = _features_clientes(miembros)
            segmentos.append({
                "segmento": nombre, "clientas": len(miembros),
                "monto_promedio": round(float(Xm[:, 1].mean()), 2),
                "compras_promedio": round(float(Xm[:, 0].mean()), 2),
                "recencia_promedio": round(float(Xm[:, 2].mean()), 1),
                "ejemplos": [{"nombre": m["nombre"], "email": m["email"]} for m in miembros[:5]],
            })

    # --- anomalias en ventas diarias
    diarias = await conn.fetch(
        """
        SELECT v.sucursal_id, v.fecha::date AS dia, SUM(v.total) AS total, COUNT(*)::int AS tickets
        FROM venta v
        WHERE v.sucursal_id = ANY($1::uuid[]) AND v.estado IN ('PAGADA','ENTREGADA')
          AND v.fecha >= CURRENT_DATE - 90
        GROUP BY 1, 2 ORDER BY 2
        """,
        ids,
    )
    nombres = {s["id"]: s["nombre"] for s in sucursales}
    anomalias = []
    for s in sucursales:
        serie = [{"dia": f["dia"], "total": float(f["total"]), "tickets": f["tickets"],
                  "dia_semana": f["dia"].weekday()} for f in diarias if f["sucursal_id"] == s["id"]]
        if not serie:
            continue
        mediana = float(np.median([x["total"] for x in serie]))
        for i in await run_in_threadpool(modelos.anomalias, serie):
            x = serie[i]
            anomalias.append({
                "sucursal": nombres[s["id"]], "dia": x["dia"].isoformat(), "total": round(x["total"], 2),
                "tickets": x["tickets"], "mediana_sucursal": round(mediana, 2),
                "tipo": "PICO" if x["total"] > mediana else "CAIDA",
            })
    anomalias.sort(key=lambda a: a["dia"], reverse=True)

    # --- reporte inteligente: hallazgos en texto
    hallazgos = []
    con_variacion = [p for p in por_sucursal if p["variacion_pct"] is not None and p["real_ultimos_dias"] >= 3]
    if con_variacion:
        sube = max(con_variacion, key=lambda p: p["variacion_pct"])
        baja = min(con_variacion, key=lambda p: p["variacion_pct"])
        if sube["variacion_pct"] > 5:
            hallazgos.append(
                f"Se espera que la demanda de prendas de {sube['tipo'].lower()} en {sube['sucursal']} "
                f"suba {sube['variacion_pct']:.0f}% en los proximos {horizonte} dias: revisa el stock."
            )
        if baja["variacion_pct"] < -5:
            hallazgos.append(
                f"La demanda de {baja['tipo'].lower()} en {baja['sucursal']} bajaria "
                f"{abs(baja['variacion_pct']):.0f}%: candidata a promocion o traspaso."
            )
    if segmentos:
        mayor = max(segmentos, key=lambda s: s["clientas"])
        hallazgos.append(f"El segmento mas grande de la cartera es '{mayor['segmento']}' ({mayor['clientas']} clientas).")
        inactivas = next((s for s in segmentos if s["segmento"] == "Inactivas"), None)
        if inactivas:
            hallazgos.append(f"Hay {inactivas['clientas']} clientas inactivas: una campania de reactivacion podria recuperarlas.")
    if anomalias:
        a = anomalias[0]
        hallazgos.append(
            f"Dia atipico mas reciente: {a['dia']} en {a['sucursal']} "
            f"({'pico' if a['tipo'] == 'PICO' else 'caida'} de Bs {a['total']:.0f} contra una mediana de Bs {a['mediana_sucursal']:.0f})."
        )
    total_futuro = sum(f["total"] for f in por_dia)
    total_pasado = sum(p["real_ultimos_dias"] for p in por_sucursal)
    return {
        "empresa_id": str(empresa),
        "sucursales": [s["nombre"] for s in sucursales],
        "horizonte": horizonte,
        "indicadores": {
            "unidades_pronosticadas": round(total_futuro, 1),
            "unidades_ultimos_dias": round(total_pasado, 1),
            "variacion_pct": round((total_futuro - total_pasado) / total_pasado * 100, 1) if total_pasado else None,
            "clientas_segmentadas": len(clientes),
            "dias_atipicos": len(anomalias),
        },
        "pronostico_diario": por_dia,
        "pronostico_por_sucursal": por_sucursal,
        "segmentos": segmentos,
        "anomalias": anomalias[:30],
        "hallazgos": hallazgos,
        "modelo": modelos.resumen_publico(paquete),
    }
