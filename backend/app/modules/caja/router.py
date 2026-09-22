import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.db import get_connection
from app.core.deps import get_cajero_actual
from app.modules.caja.schemas import (
    AbrirSesionIn,
    ArqueoOut,
    CajaOut,
    CerrarSesionIn,
    SesionCajaOut,
    SesionCerradaOut,
    VarianteBusquedaOut,
)

router = APIRouter(prefix="/caja", tags=["caja"])


async def obtener_sesion_abierta(conn: asyncpg.Connection, empleado_id) -> asyncpg.Record | None:
    """La sesion ABIERTA del cajero, en cualquier caja. La usan tanto este router como
    /ventas/pos para exigir CU07 E1 (sesion de caja no abierta)."""
    return await conn.fetchrow(
        """
        SELECT sc.id, sc.caja_id, c.nombre AS caja_nombre, sc.abierta_en, sc.monto_inicial, sc.estado
        FROM sesion_caja sc
        JOIN caja c ON c.id = sc.caja_id
        WHERE sc.empleado_id = $1 AND sc.estado = 'ABIERTA'
        """,
        empleado_id,
    )


def _sesion_out(fila: asyncpg.Record) -> SesionCajaOut:
    return SesionCajaOut(
        id=fila["id"],
        caja_id=fila["caja_id"],
        caja_nombre=fila["caja_nombre"],
        abierta_en=fila["abierta_en"],
        monto_inicial=float(fila["monto_inicial"]),
        estado=fila["estado"],
    )


@router.get("/cajas", response_model=list[CajaOut])
async def listar_cajas(
    cajero: dict = Depends(get_cajero_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> list[CajaOut]:
    filas = await conn.fetch(
        """
        SELECT c.id, c.codigo, c.nombre,
               EXISTS(
                   SELECT 1 FROM sesion_caja sc WHERE sc.caja_id = c.id AND sc.estado = 'ABIERTA'
               ) AS tiene_sesion_abierta
        FROM caja c
        WHERE c.sucursal_id = $1 AND c.activa
        ORDER BY c.codigo
        """,
        cajero["sucursal_id"],
    )
    return [CajaOut(**dict(fila)) for fila in filas]


@router.get("/sesion-actual", response_model=SesionCajaOut | None)
async def sesion_actual(
    cajero: dict = Depends(get_cajero_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> SesionCajaOut | None:
    fila = await obtener_sesion_abierta(conn, cajero["usuario_id"])
    return _sesion_out(fila) if fila else None


@router.post("/abrir", response_model=SesionCajaOut, status_code=status.HTTP_201_CREATED)
async def abrir_sesion(
    body: AbrirSesionIn,
    cajero: dict = Depends(get_cajero_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> SesionCajaOut:
    existente = await obtener_sesion_abierta(conn, cajero["usuario_id"])
    if existente is not None:
        # idempotente: doble click o refresh no debe abrir una segunda sesion
        return _sesion_out(existente)

    caja = await conn.fetchrow(
        "SELECT id FROM caja WHERE id = $1 AND sucursal_id = $2 AND activa",
        body.caja_id,
        cajero["sucursal_id"],
    )
    if caja is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Caja no encontrada")

    try:
        fila = await conn.fetchrow(
            """
            INSERT INTO sesion_caja (caja_id, empleado_id, monto_inicial)
            VALUES ($1, $2, $3)
            RETURNING id, caja_id, abierta_en, monto_inicial, estado
            """,
            body.caja_id,
            cajero["usuario_id"],
            body.monto_inicial,
        )
    except asyncpg.UniqueViolationError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Esa caja ya tiene una sesion abierta por otro cajero",
        )

    return SesionCajaOut(
        id=fila["id"],
        caja_id=fila["caja_id"],
        caja_nombre=(await conn.fetchval("SELECT nombre FROM caja WHERE id = $1", fila["caja_id"])),
        abierta_en=fila["abierta_en"],
        monto_inicial=float(fila["monto_inicial"]),
        estado=fila["estado"],
    )


async def _calcular_arqueo(conn: asyncpg.Connection, sesion: asyncpg.Record) -> ArqueoOut:
    """Suma los pagos APROBADOS de las ventas atadas a esta sesion, agrupados por metodo. Solo
    para la vista previa (GET /arqueo): el cierre (POST /cerrar) ya no llama a esto, calcula
    monto_sistema con fn_total_efectivo_sesion() dentro del propio UPDATE para no dejar una
    ventana entre "leer" y "escribir" donde una venta nueva quede afuera del cierre.
    cantidad_ventas usa el mismo filtro (sesion + pago APROBADO) que por_metodo/total_ventas en
    una sola consulta -- contar TODAS las ventas de la sesion sin ese filtro las desalineaba."""
    filas = await conn.fetch(
        """
        SELECT p.metodo::text AS metodo, COALESCE(SUM(p.monto), 0) AS total,
               (SELECT COUNT(DISTINCT p2.venta_id)
                  FROM pago p2 JOIN venta v2 ON v2.id = p2.venta_id
                 WHERE v2.sesion_caja_id = $1 AND p2.estado = 'APROBADO') AS cantidad_ventas
        FROM pago p
        JOIN venta v ON v.id = p.venta_id
        WHERE v.sesion_caja_id = $1 AND p.estado = 'APROBADO'
        GROUP BY p.metodo
        """,
        sesion["id"],
    )
    por_metodo = {fila["metodo"]: float(fila["total"]) for fila in filas}
    cantidad_ventas = filas[0]["cantidad_ventas"] if filas else 0
    monto_inicial = float(sesion["monto_inicial"])
    total_efectivo = por_metodo.get("EFECTIVO", 0.0)

    return ArqueoOut(
        sesion_id=sesion["id"],
        monto_inicial=monto_inicial,
        monto_sistema=monto_inicial + total_efectivo,
        cantidad_ventas=cantidad_ventas,
        total_ventas=sum(por_metodo.values()),
        por_metodo=por_metodo,
    )


@router.get("/arqueo", response_model=ArqueoOut)
async def arqueo_actual(
    cajero: dict = Depends(get_cajero_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> ArqueoOut:
    sesion = await obtener_sesion_abierta(conn, cajero["usuario_id"])
    if sesion is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="No tenes una sesion de caja abierta"
        )
    return await _calcular_arqueo(conn, sesion)


@router.post("/cerrar", response_model=SesionCerradaOut)
async def cerrar_sesion(
    body: CerrarSesionIn,
    cajero: dict = Depends(get_cajero_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> SesionCerradaOut:
    """CU07 (pendiente cerrado): una sesion ABIERTA quedaba abierta para siempre, bloqueando esa
    caja para otro cajero. El cierre deja monto_sistema (lo calculado) y monto_declarado (lo que
    el cajero conto), y `diferencia` sale sola porque es una columna GENERATED del esquema.
    monto_sistema llama a fn_total_efectivo_sesion() DENTRO del propio UPDATE (no con una
    lectura previa como GET /arqueo) para que no quede una venta de POS afuera del cierre si se
    registra justo entre "leer" el arqueo y "escribir" el cierre."""
    sesion = await obtener_sesion_abierta(conn, cajero["usuario_id"])
    if sesion is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="No tenes una sesion de caja abierta"
        )

    fila = await conn.fetchrow(
        """
        UPDATE sesion_caja sc
           SET estado = 'CERRADA',
               cerrada_en = now(),
               monto_sistema = sc.monto_inicial + fn_total_efectivo_sesion(sc.id),
               monto_declarado = $2
         WHERE sc.id = $1 AND sc.estado = 'ABIERTA'
        RETURNING id, caja_id, abierta_en, cerrada_en, monto_inicial,
                  monto_sistema, monto_declarado, diferencia, estado
        """,
        sesion["id"],
        body.monto_declarado,
    )
    if fila is None:
        # se cerro entre el chequeo y el UPDATE (doble click, dos pestanias)
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="La sesion ya esta cerrada")

    return SesionCerradaOut(**dict(fila), caja_nombre=sesion["caja_nombre"])


@router.get("/buscar-variante", response_model=VarianteBusquedaOut)
async def buscar_variante(
    codigo: str = Query(..., min_length=1, description="SKU o codigo de barras, match exacto"),
    cajero: dict = Depends(get_cajero_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> VarianteBusquedaOut:
    fila = await conn.fetchrow(
        """
        SELECT pv.id AS variante_id, pv.sku, p.nombre AS producto, t.codigo AS talla, c.nombre AS color,
               COALESCE(pv.precio_oferta, pv.precio, p.precio_base) AS precio,
               COALESCE(i.disponible, 0) AS disponible
        FROM producto_variante pv
        JOIN producto p ON p.id = pv.producto_id
        JOIN talla t    ON t.id = pv.talla_id
        JOIN color c    ON c.id = pv.color_id
        LEFT JOIN inventario i ON i.variante_id = pv.id AND i.sucursal_id = $2
        WHERE pv.activa AND (pv.sku ILIKE $1 OR pv.codigo_barras ILIKE $1)
        LIMIT 1
        """,
        codigo.strip(),
        cajero["sucursal_id"],
    )
    if fila is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No se encontro esa prenda")

    return VarianteBusquedaOut(
        variante_id=fila["variante_id"],
        sku=fila["sku"],
        producto=fila["producto"],
        talla=fila["talla"],
        color=fila["color"],
        precio=float(fila["precio"]),
        disponible=fila["disponible"],
    )
