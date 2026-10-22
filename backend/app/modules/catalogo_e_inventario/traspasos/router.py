"""Traspasos de mercaderia entre sucursales (PENDIENTES 2.7).

Por que existen: las tres sucursales estan en climas distintos (ver README, "Modelo de
negocio") y la misma coleccion rota distinto en cada una; el tapado que se queda parado en
Santa Cruz es el que falta en La Paz. Mover prendas entre tiendas es la operacion natural.

Estados y quien actua (ADMIN puede todo, en cualquier sucursal):
  SOLICITADO  -- lo crea el encargado del ORIGEN con sus lineas (POST /traspasos). No mueve
                 stock; se valida que el origen tenga disponible para avisar temprano.
  EN_TRANSITO -- lo despacha el ORIGEN (POST /{id}/despachar): sale el stock del origen
                 (TRASPASO_SAL por lo solicitado). Si ya no hay disponible -> 409.
  RECIBIDO    -- lo recibe el DESTINO (POST /{id}/recibir) indicando cantidad_recibida por
                 linea (las que no manda se toman completas): entra en el destino
                 TRASPASO_ENT por lo recibido. Si llego de menos, la diferencia ya salio del
                 origen y no entro en ningun lado: queda visible en el detalle (solicitada vs
                 recibida) y se resuelve con un ajuste de inventario (/panel/inventario) en la
                 sucursal que corresponda una vez aclarado; el kardex no se reescribe. Recibir
                 mas de lo despachado -> 422.
  ANULADO     -- POST /{id}/anular. En SOLICITADO lo puede anular el origen o el destino (no
                 se movio nada). En EN_TRANSITO solo el origen (la mercaderia no salio o volvio
                 entera): el stock vuelve al origen con TRASPASO_ENT. RECIBIDO no se anula.

Este modulo nunca escribe inventario: cambia traspaso.estado y el trigger tg_traspaso_stock
(db/02_logica.sql) llama a fn_mover_inventario, firmando el kardex con actualizado_por_id.

Multi-tenant: un traspaso es siempre entre dos sucursales de la MISMA empresa (las dos se
validan contra la empresa del usuario) y las prendas tienen que ser de su catalogo.
"""

from uuid import UUID, uuid4

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.auditoria import registrar_auditoria
from app.core.db import get_connection
from app.core.deps import requiere_permiso
from app.core.plan import requiere_funcion_plan
from app.core.tenant import (
    empresa_de,
    es_admin_empresa,
    exigir_sucursal,
    exigir_variantes,
    no_encontrado,
)
from app.modules.catalogo_e_inventario.traspasos.schemas import (
    DetalleTraspasoOut,
    MovimientoTraspasoOut,
    RecibirIn,
    SugerenciaTraspasoOut,
    TraspasoDetalleOut,
    TraspasoIn,
    TraspasoOut,
    VarianteTraspasoOut,
)

router = APIRouter(prefix="/traspasos", tags=["traspasos"])

puede_ver = requiere_permiso(
    "traspasos.leer", "traspasos.crear", "traspasos.actualizar", "traspasos.eliminar"
)
# SaaS (PENDIENTES 5.6): crear traspasos y ver sugerencias depende del plan de la sucursal
puede_crear = requiere_funcion_plan("traspasos", "traspasos.crear")
puede_ver_sugerencias = requiere_funcion_plan(
    "traspasos", "traspasos.leer", "traspasos.crear", "traspasos.actualizar"
)
puede_actualizar = requiere_permiso("traspasos.actualizar")
puede_anular = requiere_permiso("traspasos.eliminar")

SELECT_TRASPASO = """
SELECT t.id, t.numero, t.estado,
       t.sucursal_origen_id, so.nombre AS origen,
       t.sucursal_destino_id, sd.nombre AS destino,
       t.fecha_solicitud, t.fecha_despacho, t.fecha_recepcion,
       (us.nombre || ' ' || us.apellido) AS solicitado_por,
       (ur.nombre || ' ' || ur.apellido) AS recibido_por,
       t.observacion,
       (SELECT COUNT(*) FROM traspaso_detalle d WHERE d.traspaso_id = t.id) AS lineas,
       (SELECT COALESCE(SUM(d.cantidad_solicitada), 0) FROM traspaso_detalle d
         WHERE d.traspaso_id = t.id) AS unidades_solicitadas,
       CASE WHEN t.estado = 'RECIBIDO' THEN
            (SELECT COALESCE(SUM(d.cantidad_recibida), 0) FROM traspaso_detalle d
              WHERE d.traspaso_id = t.id)
       END AS unidades_recibidas
FROM traspaso t
JOIN sucursal so     ON so.id = t.sucursal_origen_id
JOIN sucursal sd     ON sd.id = t.sucursal_destino_id
LEFT JOIN usuario us ON us.id = t.usuario_solicita_id
LEFT JOIN usuario ur ON ur.id = t.usuario_recibe_id
"""


def _es_admin(staff: dict) -> bool:
    """Mismo criterio que recepciones: el ADMIN de la empresa ve todas sus sucursales."""
    return es_admin_empresa(staff)


def _mi_sucursal(staff: dict) -> UUID | None:
    if _es_admin(staff):
        return None
    if staff["sucursal_id"] is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tu usuario no esta asignado a ninguna sucursal",
        )
    return staff["sucursal_id"]


def _exigir_lado(staff: dict, traspaso: TraspasoOut, lado: str) -> None:
    """lado: 'origen', 'destino' o 'cualquiera'."""
    mia = _mi_sucursal(staff)
    if mia is None:
        return
    es_origen = traspaso.sucursal_origen_id == mia
    es_destino = traspaso.sucursal_destino_id == mia
    if lado == "origen" and not es_origen:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo la sucursal de origen puede hacer esto con el traspaso",
        )
    if lado == "destino" and not es_destino:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo la sucursal de destino puede recibir el traspaso",
        )
    if lado == "cualquiera" and not (es_origen or es_destino):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="Ese traspaso no involucra a tu sucursal"
        )


def _armar(fila: asyncpg.Record, staff: dict) -> TraspasoOut:
    traspaso = TraspasoOut(**dict(fila))
    mia = _mi_sucursal(staff)
    if mia is not None:
        traspaso.mi_lado = "ORIGEN" if traspaso.sucursal_origen_id == mia else "DESTINO"
    return traspaso


async def _obtener(conn: asyncpg.Connection, traspaso_id: UUID, staff: dict) -> TraspasoOut:
    fila = await conn.fetchrow(
        SELECT_TRASPASO + "WHERE t.id = $1 AND so.empresa_id = $2", traspaso_id, empresa_de(staff)
    )
    if fila is None:
        raise no_encontrado("Traspaso no encontrado")
    traspaso = _armar(fila, staff)
    _exigir_lado(staff, traspaso, "cualquiera")
    return traspaso


async def _con_detalle(conn: asyncpg.Connection, traspaso_id: UUID, staff: dict) -> TraspasoDetalleOut:
    cabecera = await _obtener(conn, traspaso_id, staff)
    filas = await conn.fetch(
        """
        SELECT d.id, d.variante_id, pv.sku, pr.nombre AS producto, ta.codigo AS talla,
               c.nombre AS color, c.codigo_hex, d.cantidad_solicitada, d.cantidad_recibida,
               COALESCE(io.disponible, 0) AS disponible_origen,
               COALESCE(ide.disponible, 0) AS disponible_destino
        FROM traspaso_detalle d
        JOIN traspaso t           ON t.id = d.traspaso_id
        JOIN producto_variante pv ON pv.id = d.variante_id
        JOIN producto pr          ON pr.id = pv.producto_id
        JOIN talla ta             ON ta.id = pv.talla_id
        JOIN color c              ON c.id = pv.color_id
        LEFT JOIN inventario io   ON io.variante_id = d.variante_id AND io.sucursal_id = t.sucursal_origen_id
        LEFT JOIN inventario ide  ON ide.variante_id = d.variante_id AND ide.sucursal_id = t.sucursal_destino_id
        WHERE d.traspaso_id = $1
        ORDER BY pr.nombre, ta.orden, c.nombre
        """,
        traspaso_id,
    )
    return TraspasoDetalleOut(
        **cabecera.model_dump(), detalle=[DetalleTraspasoOut(**dict(f)) for f in filas]
    )


def _exigir_estado(traspaso: TraspasoOut, *estados: str) -> None:
    if traspaso.estado not in estados:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"El traspaso esta {traspaso.estado.lower().replace('_', ' ')}",
        )


async def _cambiar_estado(
    conn: asyncpg.Connection,
    traspaso: TraspasoOut,
    nuevo: str,
    staff: dict,
    extra_sql: str = "",
    extra_args: tuple = (),
    datos_auditoria: dict | None = None,
) -> None:
    """UPDATE del estado (dispara tg_traspaso_stock) + auditoria. Se re-lee con FOR UPDATE para
    que dos personas despachando/recibiendo a la vez no dupliquen el movimiento: la segunda ve
    el estado nuevo y recibe 409."""
    actual = await conn.fetchval(
        "SELECT estado::text FROM traspaso WHERE id = $1 FOR UPDATE", traspaso.id
    )
    if actual != traspaso.estado:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"El traspaso cambio mientras operabas: ahora esta {actual.lower().replace('_', ' ')}",
        )
    await conn.execute(
        f"UPDATE traspaso SET estado = $2, actualizado_por_id = $3{extra_sql} WHERE id = $1",
        traspaso.id,
        nuevo,
        staff["id"],
        *extra_args,
    )
    await registrar_auditoria(
        conn,
        usuario_id=staff["id"],
        entidad="traspaso",
        entidad_id=traspaso.id,
        accion="ELIMINAR" if nuevo == "ANULADO" else "ACTUALIZAR",
        datos_antes={"estado": traspaso.estado},
        datos_despues={"estado": nuevo, **(datos_auditoria or {})},
    )


async def _avisar_encargados(
    conn: asyncpg.Connection, sucursal_id: UUID, traspaso_id: UUID, titulo: str, mensaje: str
) -> None:
    await conn.execute(
        """
        INSERT INTO notificacion (usuario_id, tipo, titulo, mensaje, entidad_tipo, entidad_id)
        SELECT e.usuario_id, 'STOCK', $3, $4, 'TRASPASO', $2
        FROM empleado e
        WHERE e.sucursal_id = $1 AND e.activo AND e.cargo = 'ENCARGADO'
        """,
        sucursal_id,
        traspaso_id,
        titulo,
        mensaje,
    )


# ---------------------------------------------------------------------
#  CONSULTA
# ---------------------------------------------------------------------


@router.get("", response_model=list[TraspasoOut])
async def listar_traspasos(
    estado: str | None = Query(default=None, pattern="^(SOLICITADO|EN_TRANSITO|RECIBIDO|ANULADO)$"),
    direccion: str | None = Query(default=None, pattern="^(SALIENTES|ENTRANTES)$"),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[TraspasoOut]:
    """Un encargado ve los que salen de o llegan a su sucursal (direccion filtra uno de los
    dos lados); un ADMIN ve todos."""
    mia = _mi_sucursal(staff)
    filas = await conn.fetch(
        SELECT_TRASPASO
        + """
        WHERE ($1::uuid IS NULL
               OR ($3::text IS DISTINCT FROM 'ENTRANTES' AND t.sucursal_origen_id = $1)
               OR ($3::text IS DISTINCT FROM 'SALIENTES' AND t.sucursal_destino_id = $1))
          AND ($2::text IS NULL OR t.estado::text = $2)
          AND so.empresa_id = $4
        ORDER BY t.fecha_solicitud DESC
        LIMIT 200
        """,
        mia,
        estado,
        direccion,
        empresa_de(staff),
    )
    return [_armar(fila, staff) for fila in filas]


@router.get("/variantes", response_model=list[VarianteTraspasoOut])
async def buscar_variantes(
    q: str = Query(min_length=1, description="SKU, codigo de barras o nombre de la prenda"),
    origen_id: UUID | None = Query(default=None),
    destino_id: UUID | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[VarianteTraspasoOut]:
    """Buscador para armar el traspaso: muestra lo disponible en el origen (lo que se puede
    mandar) y en el destino (cuanto le falta a la otra tienda)."""
    origen = origen_id or _mi_sucursal(staff)
    if origen is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Indica la sucursal de origen"
        )
    empresa_id = empresa_de(staff)
    await exigir_sucursal(conn, origen, empresa_id)
    await exigir_sucursal(conn, destino_id, empresa_id)
    filas = await conn.fetch(
        """
        SELECT pv.id, pv.sku, pr.nombre AS producto, ta.codigo AS talla,
               c.nombre AS color, c.codigo_hex,
               COALESCE(io.disponible, 0) AS disponible_origen,
               COALESCE(ide.disponible, 0) AS disponible_destino
        FROM producto_variante pv
        JOIN producto pr ON pr.id = pv.producto_id
        JOIN talla ta    ON ta.id = pv.talla_id
        JOIN color c     ON c.id = pv.color_id
        LEFT JOIN inventario io  ON io.variante_id = pv.id AND io.sucursal_id = $2
        LEFT JOIN inventario ide ON ide.variante_id = pv.id AND ide.sucursal_id = $3
        WHERE pv.activa AND pr.activo AND pr.empresa_id = $4
          AND (pv.sku ILIKE '%' || $1 || '%'
               OR pv.codigo_barras ILIKE '%' || $1 || '%'
               OR pr.nombre ILIKE '%' || $1 || '%')
        ORDER BY COALESCE(io.disponible, 0) DESC, pr.nombre, ta.orden, c.nombre
        LIMIT 25
        """,
        q.strip(),
        origen,
        destino_id,
        empresa_id,
    )
    return [VarianteTraspasoOut(**dict(fila)) for fila in filas]


SQL_SUGERENCIAS = """
WITH ventas AS (
    SELECT v.sucursal_id, vd.variante_id,
           COALESCE(SUM(vd.cantidad) FILTER (
               WHERE v.fecha >= now() - make_interval(days => $1)), 0) AS recientes,
           COALESCE(SUM(vd.cantidad) FILTER (
               WHERE v.fecha <  now() - make_interval(days => $1)), 0) AS anteriores
    FROM venta v
    JOIN venta_detalle vd ON vd.venta_id = v.id
    WHERE v.estado IN ('PAGADA','ENTREGADA')
      AND v.fecha >= now() - make_interval(days => 2 * $1)
    GROUP BY v.sucursal_id, vd.variante_id
),
demanda AS (
    SELECT i.sucursal_id, i.variante_id, i.disponible, i.stock_minimo,
           COALESCE(ve.recientes, 0)::int AS recientes,
           COALESCE(ve.anteriores, 0)::int AS anteriores,
           COALESCE(ve.recientes, 0)::numeric / $1 AS ritmo
    FROM inventario i
    JOIN sucursal s ON s.id = i.sucursal_id AND s.activa AND s.empresa_id = $5
    LEFT JOIN ventas ve ON ve.sucursal_id = i.sucursal_id AND ve.variante_id = i.variante_id
),
necesidad AS (
    SELECT d.*, CEIL(d.ritmo * $2)::int - d.disponible AS falta
    FROM demanda d
    WHERE d.recientes >= 2
      AND d.recientes > d.anteriores
      AND CEIL(d.ritmo * $2) > d.disponible
      AND NOT EXISTS (
          SELECT 1 FROM traspaso t JOIN traspaso_detalle td ON td.traspaso_id = t.id
           WHERE t.sucursal_destino_id = d.sucursal_id AND td.variante_id = d.variante_id
             AND t.estado IN ('SOLICITADO','EN_TRANSITO'))
),
excedente AS (
    SELECT d.sucursal_id, d.variante_id, d.disponible,
           d.disponible - GREATEST(d.stock_minimo, CEIL(d.ritmo * $2)::int) AS sobra
    FROM demanda d
),
mejor AS (
    SELECT DISTINCT ON (n.sucursal_id, n.variante_id)
           n.sucursal_id AS destino_id, n.variante_id, n.recientes, n.anteriores,
           n.disponible AS disponible_destino, n.ritmo, n.falta,
           e.sucursal_id AS origen_id, e.disponible AS disponible_origen, e.sobra
    FROM necesidad n
    JOIN excedente e ON e.variante_id = n.variante_id
                    AND e.sucursal_id <> n.sucursal_id
                    AND e.sobra > 0
    ORDER BY n.sucursal_id, n.variante_id, e.sobra DESC
)
SELECT m.variante_id, pv.sku, pr.nombre AS producto, ta.codigo AS talla,
       c.nombre AS color, c.codigo_hex,
       m.destino_id AS sucursal_destino_id, sd.nombre AS destino,
       m.origen_id AS sucursal_origen_id, so.nombre AS origen,
       m.recientes AS vendidas_recientes, m.anteriores AS vendidas_anteriores,
       CASE WHEN m.anteriores > 0
            THEN round((m.recientes - m.anteriores) * 100.0 / m.anteriores, 1)::float END
           AS crecimiento_pct,
       m.disponible_destino,
       CASE WHEN m.ritmo > 0 THEN round(m.disponible_destino / m.ritmo, 1)::float END
           AS cobertura_destino_dias,
       m.disponible_origen,
       m.sobra AS excedente_origen,
       LEAST(m.falta, m.sobra) AS cantidad_sugerida
FROM mejor m
JOIN producto_variante pv ON pv.id = m.variante_id AND pv.activa
JOIN producto pr          ON pr.id = pv.producto_id AND pr.activo
JOIN talla ta             ON ta.id = pv.talla_id
JOIN color c              ON c.id = pv.color_id
JOIN sucursal sd          ON sd.id = m.destino_id
JOIN sucursal so          ON so.id = m.origen_id
WHERE ($3::uuid IS NULL OR m.destino_id = $3 OR m.origen_id = $3)
ORDER BY (m.recientes - m.anteriores) DESC, m.falta DESC, pr.nombre, ta.orden
LIMIT $4
"""


@router.get("/sugerencias", response_model=list[SugerenciaTraspasoOut])
async def sugerir_traspasos(
    dias: int = Query(default=14, ge=7, le=60, description="Ventana de demanda reciente"),
    horizonte: int = Query(
        default=21, ge=7, le=90, description="Dias de venta que el destino deberia poder cubrir"
    ),
    limite: int = Query(default=50, ge=1, le=200),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver_sugerencias),
) -> list[SugerenciaTraspasoOut]:
    """Traspasos hacia donde la demanda crece (PENDIENTES 5.12).

    Para cada prenda y sucursal compara lo vendido en los ultimos `dias` contra los `dias`
    anteriores. Si crece (y se vendieron al menos 2) y el disponible no alcanza para `horizonte`
    dias al ritmo actual, busca la sucursal a la que mas le sobra -- lo que tiene por encima de
    su stock minimo y de su propia demanda para el mismo horizonte -- y sugiere mover lo que
    falta (sin pasarse de lo que sobra). No sugiere lo que ya viaja en un traspaso abierto hacia
    ese destino. Un ENCARGADO ve las sugerencias donde su sucursal es origen o destino.
    """
    filas = await conn.fetch(
        SQL_SUGERENCIAS, dias, horizonte, _mi_sucursal(staff), limite, empresa_de(staff)
    )
    return [SugerenciaTraspasoOut(**dict(fila)) for fila in filas]


@router.get("/{traspaso_id}", response_model=TraspasoDetalleOut)
async def obtener_traspaso(
    traspaso_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> TraspasoDetalleOut:
    return await _con_detalle(conn, traspaso_id, staff)


@router.get("/{traspaso_id}/movimientos", response_model=list[MovimientoTraspasoOut])
async def movimientos_de_traspaso(
    traspaso_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[MovimientoTraspasoOut]:
    """Asientos de kardex que genero el traspaso, en las dos sucursales."""
    await _obtener(conn, traspaso_id, staff)
    filas = await conn.fetch(
        """
        SELECT s.nombre AS sucursal, m.tipo::text AS tipo, pv.sku, pr.nombre AS producto,
               m.cantidad, m.saldo_anterior, m.saldo_nuevo, m.fecha
        FROM movimiento_inventario m
        JOIN sucursal s           ON s.id = m.sucursal_id
        JOIN producto_variante pv ON pv.id = m.variante_id
        JOIN producto pr          ON pr.id = pv.producto_id
        WHERE m.documento_tipo = 'TRASPASO' AND m.documento_id = $1
        ORDER BY m.fecha, m.id
        """,
        traspaso_id,
    )
    return [MovimientoTraspasoOut(**dict(fila)) for fila in filas]


# ---------------------------------------------------------------------
#  ALTA
# ---------------------------------------------------------------------


@router.post("", response_model=TraspasoDetalleOut, status_code=status.HTTP_201_CREATED)
async def crear_traspaso(
    body: TraspasoIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_crear),
) -> TraspasoDetalleOut:
    mia = _mi_sucursal(staff)
    origen = body.sucursal_origen_id or mia or staff["sucursal_id"]
    if origen is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Indica la sucursal de origen"
        )
    if mia is not None and origen != mia:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo podes mandar mercaderia desde tu sucursal",
        )
    if origen == body.sucursal_destino_id:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="El origen y el destino tienen que ser sucursales distintas",
        )
    empresa_id = empresa_de(staff)
    activas = await conn.fetchval(
        "SELECT COUNT(*) FROM sucursal WHERE id = ANY($1::uuid[]) AND activa AND empresa_id = $2",
        [origen, body.sucursal_destino_id],
        empresa_id,
    )
    if activas != 2:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="La sucursal de origen o de destino no existe o esta dada de baja",
        )

    pedidas: dict[UUID, int] = {}
    for linea in body.lineas:
        pedidas[linea.variante_id] = pedidas.get(linea.variante_id, 0) + linea.cantidad
    await exigir_variantes(conn, list(pedidas), empresa_id)

    filas = await conn.fetch(
        """
        SELECT pv.id, pv.sku, COALESCE(i.disponible, 0) AS disponible
        FROM producto_variante pv
        LEFT JOIN inventario i ON i.variante_id = pv.id AND i.sucursal_id = $2
        WHERE pv.id = ANY($1::uuid[]) AND pv.activa
        """,
        list(pedidas),
        origen,
    )
    info = {f["id"]: f for f in filas}
    for variante_id, cantidad in pedidas.items():
        fila = info.get(variante_id)
        if fila is None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Una de las prendas no existe o esta inactiva",
            )
        # aviso temprano: la verificacion que manda es la de fn_mover_inventario al despachar
        if cantidad > fila["disponible"]:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"{fila['sku']}: el origen tiene {fila['disponible']} disponible(s), se piden {cantidad}",
            )

    numero = f"T-{uuid4().hex[:10].upper()}"
    async with conn.transaction():
        traspaso_id = await conn.fetchval(
            """
            INSERT INTO traspaso (sucursal_origen_id, sucursal_destino_id, numero,
                                  usuario_solicita_id, actualizado_por_id)
            VALUES ($1, $2, $3, $4, $4)
            RETURNING id
            """,
            origen,
            body.sucursal_destino_id,
            numero,
            staff["id"],
        )
        await conn.executemany(
            "INSERT INTO traspaso_detalle (traspaso_id, variante_id, cantidad_solicitada) VALUES ($1, $2, $3)",
            [(traspaso_id, variante_id, cantidad) for variante_id, cantidad in pedidas.items()],
        )
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="traspaso",
            entidad_id=traspaso_id,
            accion="CREAR",
            datos_despues={
                "numero": numero,
                "origen": str(origen),
                "destino": str(body.sucursal_destino_id),
                "unidades": sum(pedidas.values()),
            },
        )

    return await _con_detalle(conn, traspaso_id, staff)


# ---------------------------------------------------------------------
#  CICLO DE VIDA
# ---------------------------------------------------------------------


@router.post("/{traspaso_id}/despachar", response_model=TraspasoDetalleOut)
async def despachar_traspaso(
    traspaso_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_actualizar),
) -> TraspasoDetalleOut:
    traspaso = await _obtener(conn, traspaso_id, staff)
    _exigir_lado(staff, traspaso, "origen")
    _exigir_estado(traspaso, "SOLICITADO")

    try:
        async with conn.transaction():
            await _cambiar_estado(
                conn, traspaso, "EN_TRANSITO", staff, extra_sql=", fecha_despacho = now()"
            )
            await _avisar_encargados(
                conn,
                traspaso.sucursal_destino_id,
                traspaso.id,
                "Traspaso en camino",
                f"{traspaso.origen} despacho el traspaso {traspaso.numero} "
                f"({traspaso.unidades_solicitadas} unidad(es)). Registralo al recibirlo.",
            )
    except asyncpg.RaiseError as error:
        # sin disponible en el origen (fn_mover_inventario)
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(error))

    return await _con_detalle(conn, traspaso_id, staff)


@router.post("/{traspaso_id}/recibir", response_model=TraspasoDetalleOut)
async def recibir_traspaso(
    traspaso_id: UUID,
    body: RecibirIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_actualizar),
) -> TraspasoDetalleOut:
    traspaso = await _obtener(conn, traspaso_id, staff)
    _exigir_lado(staff, traspaso, "destino")
    _exigir_estado(traspaso, "EN_TRANSITO")

    lineas = {
        f["id"]: f["cantidad_solicitada"]
        for f in await conn.fetch(
            "SELECT id, cantidad_solicitada FROM traspaso_detalle WHERE traspaso_id = $1", traspaso_id
        )
    }
    recibidas = dict(lineas)  # lo no informado se toma como recibido completo
    for linea in body.lineas:
        if linea.detalle_id not in lineas:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Una de las lineas no pertenece a este traspaso",
            )
        if linea.cantidad_recibida > lineas[linea.detalle_id]:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=(
                    f"Se informan {linea.cantidad_recibida} unidad(es) recibidas de una linea "
                    f"que despacho {lineas[linea.detalle_id]}"
                ),
            )
        recibidas[linea.detalle_id] = linea.cantidad_recibida

    faltante = sum(lineas.values()) - sum(recibidas.values())
    observacion = (body.observacion or "").strip() or None

    try:
        async with conn.transaction():
            await conn.executemany(
                "UPDATE traspaso_detalle SET cantidad_recibida = $2 WHERE id = $1",
                list(recibidas.items()),
            )
            await _cambiar_estado(
                conn,
                traspaso,
                "RECIBIDO",
                staff,
                extra_sql=", fecha_recepcion = now(), usuario_recibe_id = $3, observacion = $4",
                extra_args=(observacion,),
                datos_auditoria={"faltante": faltante, "observacion": observacion},
            )
            if faltante > 0:
                await _avisar_encargados(
                    conn,
                    traspaso.sucursal_origen_id,
                    traspaso.id,
                    "Traspaso recibido con faltante",
                    f"{traspaso.destino} recibio el traspaso {traspaso.numero} con {faltante} "
                    "unidad(es) de menos. Revisalo y corregilo con un ajuste de inventario.",
                )
    except asyncpg.RaiseError as error:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(error))

    return await _con_detalle(conn, traspaso_id, staff)


@router.post("/{traspaso_id}/anular", response_model=TraspasoDetalleOut)
async def anular_traspaso(
    traspaso_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_anular),
) -> TraspasoDetalleOut:
    traspaso = await _obtener(conn, traspaso_id, staff)
    _exigir_estado(traspaso, "SOLICITADO", "EN_TRANSITO")
    if traspaso.estado == "EN_TRANSITO":
        # la mercaderia ya salio: solo el origen puede decir que no llego a irse o que volvio
        _exigir_lado(staff, traspaso, "origen")

    try:
        async with conn.transaction():
            await _cambiar_estado(conn, traspaso, "ANULADO", staff)
    except asyncpg.RaiseError as error:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(error))

    return await _con_detalle(conn, traspaso_id, staff)
