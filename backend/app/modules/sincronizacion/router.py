"""Sincronizacion offline: descarga del paquete para operar sin red (CU13), envio de operaciones
pendientes (CU19), consulta de resultados (CU20) y resolucion de conflictos (CU21). Las reglas
viven en servicio.py; este router solo autoriza y arma las respuestas."""

import json
from datetime import date, datetime, timezone
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.auditoria import registrar_auditoria
from app.core.db import get_connection
from app.core.deps import get_staff_actual, requiere_permiso
from app.core.plan import requiere_funcion_plan
from app.core.tenant import (
    alcance_sucursal,
    empresa_de,
    es_admin_empresa,
    exigir_sucursal,
    no_encontrado,
)
from app.modules.sincronizacion import servicio
from app.modules.sincronizacion.schemas import (
    ClienteOfflineOut,
    LoteIn,
    LoteOut,
    OperacionIn,
    OperacionServidorOut,
    PaqueteOfflineOut,
    ProductoOfflineOut,
    ResolverIn,
    ResultadoOperacionOut,
    SucursalOfflineOut,
    VarianteOfflineOut,
)

router = APIRouter(prefix="/sync", tags=["sincronizacion"])

puede_descargar = requiere_funcion_plan("operacion_offline", "catalogo.leer")
puede_ver_log = requiere_permiso("sincronizacion.leer", "sincronizacion.actualizar")

# los que el dispositivo baja para elegir clienta al reservar sin red
MAX_CLIENTES_OFFLINE = 500


@router.get("/catalogo", response_model=PaqueteOfflineOut)
async def descargar_paquete(
    sucursal_id: UUID | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_descargar),
) -> PaqueteOfflineOut:
    """El subconjunto del catalogo que necesita una sucursal para vender y reservar sin red:
    prendas activas con precio vigente y existencias de esa sucursal, mas la cartera minima de
    clientas (nombre y email). generado_en le permite al dispositivo avisar cuando lo que
    muestra puede estar desactualizado."""
    empresa_id = empresa_de(staff)
    destino = alcance_sucursal(staff, sucursal_id) or staff["sucursal_id"]
    if destino is None:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Indica la sucursal")
    await exigir_sucursal(conn, destino, empresa_id, activa=True)

    sucursal = await conn.fetchrow(
        "SELECT id, codigo, nombre, hora_apertura, hora_cierre FROM sucursal WHERE id = $1", destino
    )
    empresa = await conn.fetchval("SELECT nombre FROM empresa WHERE id = $1", empresa_id)
    filas = await conn.fetch(
        """
        SELECT p.id AS producto_id, p.codigo, p.nombre, p.slug, c.nombre AS categoria,
               p.precio_base, img.url AS imagen_url,
               pv.id, pv.sku, t.codigo AS talla, co.nombre AS color, co.codigo_hex,
               COALESCE(pv.precio_oferta, pv.precio, p.precio_base) AS precio,
               COALESCE(i.disponible, 0) AS disponible
          FROM producto p
          JOIN categoria c          ON c.id = p.categoria_id
          JOIN producto_variante pv ON pv.producto_id = p.id AND pv.activa
          JOIN talla t              ON t.id = pv.talla_id
          JOIN color co             ON co.id = pv.color_id
          LEFT JOIN inventario i    ON i.variante_id = pv.id AND i.sucursal_id = $2
          LEFT JOIN LATERAL (
              SELECT url FROM producto_imagen pi
               WHERE pi.producto_id = p.id AND pi.uso = 'CATALOGO'
               ORDER BY pi.es_principal DESC, pi.orden LIMIT 1
          ) img ON true
         WHERE p.activo AND p.empresa_id = $1
         ORDER BY p.nombre, t.orden, co.nombre
        """,
        empresa_id,
        destino,
    )
    productos: dict[UUID, ProductoOfflineOut] = {}
    for f in filas:
        producto = productos.get(f["producto_id"])
        if producto is None:
            producto = productos[f["producto_id"]] = ProductoOfflineOut(
                id=f["producto_id"], codigo=f["codigo"], nombre=f["nombre"], slug=f["slug"],
                categoria=f["categoria"], imagen_url=f["imagen_url"],
                precio_base=float(f["precio_base"]), variantes=[],
            )
        producto.variantes.append(
            VarianteOfflineOut(
                id=f["id"], sku=f["sku"], talla=f["talla"], color=f["color"],
                codigo_hex=f["codigo_hex"], precio=float(f["precio"]), disponible=f["disponible"],
            )
        )

    clientes = await conn.fetch(
        """
        SELECT DISTINCT u.id, (u.nombre || ' ' || u.apellido) AS nombre, u.email, u.telefono
          FROM usuario u
         WHERE u.tipo = 'CLIENTE' AND u.activo AND (
               EXISTS (SELECT 1 FROM cliente_perfil_tenant cp WHERE cp.usuario_id = u.id AND cp.empresa_id = $1)
            OR EXISTS (SELECT 1 FROM venta v JOIN sucursal s ON s.id = v.sucursal_id
                        WHERE v.usuario_id = u.id AND s.empresa_id = $1)
            OR EXISTS (SELECT 1 FROM reserva r JOIN sucursal s ON s.id = r.sucursal_id
                        WHERE r.usuario_id = u.id AND s.empresa_id = $1))
         ORDER BY nombre
         LIMIT $2
        """,
        empresa_id,
        MAX_CLIENTES_OFFLINE,
    )
    sesion = await conn.fetchval(
        """
        SELECT sc.id FROM sesion_caja sc JOIN caja c ON c.id = sc.caja_id
         WHERE sc.empleado_id = $1 AND sc.estado = 'ABIERTA' AND c.sucursal_id = $2
         ORDER BY sc.abierta_en DESC LIMIT 1
        """,
        staff["id"],
        destino,
    )
    return PaqueteOfflineOut(
        generado_en=datetime.now(timezone.utc),
        empresa_id=empresa_id,
        empresa=empresa,
        sucursal=SucursalOfflineOut(**dict(sucursal)),
        sesion_caja_id=sesion,
        iva_tasa=float(servicio.IVA_TASA),
        productos=list(productos.values()),
        clientes=[ClienteOfflineOut(**dict(c)) for c in clientes],
    )


@router.post("/operaciones", response_model=LoteOut)
async def sincronizar(
    body: LoteIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(get_staff_actual),
) -> LoteOut:
    """CU19 - Sincronizar operaciones pendientes. Siempre 200 con un resultado por operacion
    (CONFIRMADA / RECHAZADA / CONFLICTO): un error de una no corta a las demas. Se procesan en
    el orden en que se registraron en el dispositivo."""
    empresa_de(staff)
    resultados = []
    for op in sorted(body.operaciones, key=lambda o: o.registrada_en):
        resultados.append(await servicio.procesar(conn, staff, op))
    return LoteOut(
        resultados=resultados,
        confirmadas=sum(r.estado == "CONFIRMADA" for r in resultados),
        rechazadas=sum(r.estado == "RECHAZADA" for r in resultados),
        en_conflicto=sum(r.estado == "CONFLICTO" for r in resultados),
    )


SELECT_LOG = """
SELECT o.id, o.tipo::text AS tipo, o.estado::text AS estado, o.codigo_motivo, o.motivo,
       o.resultado, o.intentos, o.recibida_en, o.resuelta_en, o.resolucion, o.registrada_en,
       o.payload, o.usuario_id, o.sucursal_id,
       COALESCE(s.nombre, '-') AS sucursal, (u.nombre || ' ' || u.apellido) AS usuario
FROM operacion_sync o
LEFT JOIN sucursal s ON s.id = o.sucursal_id
JOIN usuario u       ON u.id = o.usuario_id
"""


def _log_out(fila: asyncpg.Record) -> OperacionServidorOut:
    base = servicio.a_salida(fila)
    return OperacionServidorOut(
        **base.model_dump(),
        sucursal=fila["sucursal"],
        usuario=fila["usuario"],
        registrada_en=fila["registrada_en"],
        payload=json.loads(fila["payload"]),
    )


@router.get("/operaciones", response_model=list[OperacionServidorOut])
async def listar_operaciones(
    estado: str | None = Query(default=None, pattern="^(CONFIRMADA|RECHAZADA|CONFLICTO)$"),
    sucursal_id: UUID | None = Query(default=None),
    solo_abiertas: bool = Query(default=False, description="Conflictos sin resolver"),
    desde: date | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver_log),
) -> list[OperacionServidorOut]:
    """CU20 - Consultar resultado de sincronizacion (log del servidor). El admin de la empresa
    ve todas sus sucursales; el resto solo la suya."""
    empresa_id = empresa_de(staff)
    sucursal = alcance_sucursal(staff, sucursal_id)
    filas = await conn.fetch(
        SELECT_LOG
        + """
        WHERE o.empresa_id = $1
          AND ($2::uuid IS NULL OR o.sucursal_id = $2)
          AND ($3::text IS NULL OR o.estado::text = $3)
          AND (NOT $4 OR (o.estado = 'CONFLICTO' AND o.resuelta_en IS NULL))
          AND ($5::date IS NULL OR o.recibida_en >= $5::date)
        ORDER BY o.recibida_en DESC
        LIMIT 300
        """,
        empresa_id,
        sucursal,
        estado,
        solo_abiertas,
        desde,
    )
    return [_log_out(f) for f in filas]


async def _operacion_propia(conn: asyncpg.Connection, operacion_id: UUID, staff: dict) -> asyncpg.Record:
    fila = await conn.fetchrow(
        SELECT_LOG + "WHERE o.id = $1 AND o.empresa_id = $2", operacion_id, empresa_de(staff)
    )
    if fila is None:
        raise no_encontrado("Operacion no encontrada")
    es_mia = fila["usuario_id"] == staff["id"]
    puede_ver = any(p in staff["permisos"] for p in ("sincronizacion.leer", "sincronizacion.actualizar"))
    if not es_mia and not puede_ver:
        raise no_encontrado("Operacion no encontrada")
    if not es_mia and not es_admin_empresa(staff) and fila["sucursal_id"] != staff["sucursal_id"]:
        raise no_encontrado("Operacion no encontrada")
    return fila


@router.get("/operaciones/{operacion_id}", response_model=OperacionServidorOut)
async def obtener_operacion(
    operacion_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(get_staff_actual),
) -> OperacionServidorOut:
    """El dispositivo consulta el estado de una operacion que envio (quien la registro siempre
    puede verla, aunque no tenga sincronizacion.leer)."""
    return _log_out(await _operacion_propia(conn, operacion_id, staff))


@router.post("/operaciones/{operacion_id}/resolver", response_model=ResultadoOperacionOut)
async def resolver_conflicto(
    operacion_id: UUID,
    body: ResolverIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(get_staff_actual),
) -> ResultadoOperacionOut:
    """CU21 - Resolver conflicto. Quien registro la operacion puede REINTENTAR (abrio la caja,
    entro stock); aceptar el precio actual o descartar es del encargado
    (sincronizacion.actualizar)."""
    fila = await _operacion_propia(conn, operacion_id, staff)
    if fila["estado"] != "CONFLICTO" or fila["resuelta_en"] is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"La operacion esta {fila['estado'].lower()}: solo se resuelve un conflicto abierto",
        )
    gestiona = "sincronizacion.actualizar" in staff["permisos"]
    if body.accion != "REINTENTAR" and not gestiona:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Aceptar el precio actual o descartar lo decide el encargado",
        )
    if body.accion == "REINTENTAR" and fila["usuario_id"] != staff["id"] and not gestiona:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="Solo quien la registro puede reintentarla"
        )

    if body.accion == "DESCARTAR":
        nota = (body.nota or "").strip() or "Descartada"
        async with conn.transaction():
            actualizada = await conn.fetchrow(
                """
                UPDATE operacion_sync
                   SET estado = 'RECHAZADA', resuelta_en = now(), resuelta_por_id = $2,
                       resolucion = $3
                 WHERE id = $1
                RETURNING id, tipo::text AS tipo, estado::text AS estado, codigo_motivo, motivo,
                          resultado, intentos, recibida_en, resuelta_en, resolucion
                """,
                operacion_id,
                staff["id"],
                f"Descartada: {nota}",
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="operacion_sync",
                entidad_id=operacion_id,
                accion="ACTUALIZAR",
                datos_antes={"estado": "CONFLICTO", "codigo": fila["codigo_motivo"]},
                datos_despues={"estado": "RECHAZADA", "resolucion": nota},
            )
        return servicio.a_salida(actualizada)

    op = OperacionIn.model_validate(json.loads(fila["payload"]))
    # el reintento corre con la identidad de quien registro la operacion (RN10): si lo dispara
    # el encargado, igual queda a nombre del responsable original
    responsable = staff
    if fila["usuario_id"] != staff["id"]:
        responsable = {**staff, "id": fila["usuario_id"], "sucursal_id": op.sucursal_id}
    resultado = await servicio.procesar(
        conn,
        responsable,
        op,
        reprocesar=True,
        aceptar_precio=body.accion == "ACEPTAR_PRECIO_ACTUAL",
    )
    if resultado.estado != "CONFLICTO":
        await conn.execute(
            """
            UPDATE operacion_sync SET resuelta_en = now(), resuelta_por_id = $2, resolucion = $3
             WHERE id = $1
            """,
            operacion_id,
            staff["id"],
            {"REINTENTAR": "Reintentada", "ACEPTAR_PRECIO_ACTUAL": "Aceptada con el precio actual"}[
                body.accion
            ]
            + (f": {body.nota.strip()}" if body.nota else ""),
        )
        resultado.resuelta_en = datetime.now(timezone.utc)
    return resultado
