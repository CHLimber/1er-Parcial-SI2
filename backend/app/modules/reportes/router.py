"""CU15 - Consultar Reportes e Indicadores.

Dos familias de reportes, ambas de solo lectura (permiso unico `reportes.leer`, sembrado para
ADMIN y ENCARGADO en db/03_datos_iniciales.sql):

- "Dinamicos" (indicadores, ventas-diarias, ventas-por-sucursal, top-productos): aceptan filtros
  de fecha/sucursal/canal/categoria/vendedor/entrega, calculados sobre
  `venta`/`venta_detalle`/`reserva`. Categoria y vendedor se resuelven con un EXISTS contra
  `venta_detalle`/`reserva_detalle` (no con un JOIN) para no multiplicar las filas de venta/reserva
  que agregan estos endpoints. "Vendedor" es `venta.registrada_por_id` (el cajero/encargado que
  registro la venta; queda NULL en WEB/MOVIL) y, para el lado de reservas, el equivalente es
  `reserva.atendida_por_id`; canal y entrega no existen en `reserva` asi que solo filtran el lado
  de ventas.
- "Estaticos" (stock-por-sucursal, reservas-por-estado, envios-por-estado,
  productos-sin-movimiento, top-clientes, ocupacion-cajas, recepciones-pendientes): una foto del
  estado actual, sin filtro de fecha, calculados sobre `inventario`/`reserva`/`envio`/
  `venta_detalle`/`venta`/`caja`+`sesion_caja`/`recepcion`.

Un ENCARGADO solo ve su propia sucursal (igual que recepciones.py); un ADMIN (el que puede editar
sucursales) ve la cadena completa y puede filtrar por sucursal. No hay motor de consultas
generico: cada endpoint es una consulta SQL fija, en linea con el resto del backend (sin capa de
servicio/ORM, el SQL vive en el router). `/reportes/vendedores` es un endpoint auxiliar de solo
lectura para poblar el filtro de vendedor en la UI (staff de la sucursal visible), no es un
reporte en si mismo.

Cada consulta SQL vive en una funcion interna `_consultar_*(conn, ...)` que devuelve dict/list[dict]
crudos (valores de plata ya convertidos a float, ver `_normalizar`). Los 11 endpoints HTTP de
arriba son wrappers finitos sobre esas funciones; la seccion "IA / VOZ" de mas abajo (POST
/reportes/consulta-ia) las reusa como "herramientas" de un loop de tool-use contra la API de
Claude, para no duplicar el SQL de cada reporte una segunda vez.
"""

from datetime import date, timedelta
from decimal import Decimal
from uuid import UUID

import anthropic
import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.config import settings
from app.core.db import get_connection
from app.core.deps import requiere_permiso
from app.modules.reportes.schemas import (
    CajaOcupacionOut,
    ClienteRankingOut,
    ColumnaOut,
    ConsultaIaIn,
    ConsultaIaOut,
    EnvioEstadoOut,
    IndicadoresOut,
    ProductoRankingOut,
    ProductoSinMovimientoOut,
    RecepcionPendienteProveedorOut,
    ReservaEstadoOut,
    StockSucursalOut,
    VendedorOut,
    VentaDiariaOut,
    VentaPorSucursalOut,
)

router = APIRouter(prefix="/reportes", tags=["reportes"])

puede_ver = requiere_permiso("reportes.leer")

VENTA_ESTADOS_CONTADOS = ("PAGADA", "ENTREGADA")
CANAL_PATTERN = "^(WEB|MOVIL|POS)$"
ENTREGA_PATTERN = "^(RETIRO_SUCURSAL|DOMICILIO)$"


def _sucursal_visible(staff: dict) -> UUID | None:
    """Un ADMIN (el que puede editar sucursales) ve todas; el resto solo la suya."""
    if "sucursales.actualizar" in staff["permisos"]:
        return None
    if staff["sucursal_id"] is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tu usuario no esta asignado a ninguna sucursal",
        )
    return staff["sucursal_id"]


def _resolver_sucursal(staff: dict, solicitado: UUID | None) -> UUID | None:
    """None = sin filtro (cadena completa); solo un ADMIN puede pedir eso o cambiar de sucursal."""
    limite = _sucursal_visible(staff)
    if limite is None:
        return solicitado
    if solicitado is not None and solicitado != limite:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No podes consultar reportes de otra sucursal",
        )
    return limite


def _rango_fechas(desde: date | None, hasta: date | None) -> tuple[date, date]:
    """Sin filtro explicito, los reportes 'dinamicos' muestran los ultimos 30 dias."""
    hasta_final = hasta or date.today()
    desde_final = desde or (hasta_final - timedelta(days=30))
    if desde_final > hasta_final:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="La fecha 'desde' no puede ser posterior a 'hasta'",
        )
    return desde_final, hasta_final


def _normalizar(fila: asyncpg.Record) -> dict:
    """dict(fila) pero con Decimal convertido a float -- Pydantic v2 serializa Decimal como
    string en el JSON (ver PENDIENTES.txt 2.5), y esto alimenta tanto los *Out (que ya lo
    resolvian por coercion automatica) como el campo `tabla` de ConsultaIaOut (dict crudo, sin
    esa coercion)."""
    return {k: (float(v) if isinstance(v, Decimal) else v) for k, v in dict(fila).items()}


# ---------------------------------------------------------------------
#  CONSULTAS: una funcion interna por reporte, reusada por el endpoint HTTP y por las
#  herramientas de IA. Devuelven dict/list[dict] crudos, sin envolver en los *Out de schemas.py.
# ---------------------------------------------------------------------


async def _consultar_indicadores(
    conn: asyncpg.Connection,
    desde: date,
    hasta: date,
    sucursal: UUID | None,
    categoria_id: UUID | None,
    vendedor_id: UUID | None,
    canal: str | None,
    entrega: str | None,
) -> dict:
    fila = await conn.fetchrow(
        """
        WITH filtro_venta AS (
            SELECT total FROM venta v
            WHERE v.fecha::date BETWEEN $1 AND $2
              AND v.estado = ANY($3::estado_venta[])
              AND ($4::uuid IS NULL OR v.sucursal_id = $4)
              AND ($5::uuid IS NULL OR EXISTS (
                  SELECT 1 FROM venta_detalle vd
                  JOIN producto_variante pv ON pv.id = vd.variante_id
                  JOIN producto p           ON p.id = pv.producto_id
                  WHERE vd.venta_id = v.id AND p.categoria_id = $5
              ))
              AND ($6::uuid IS NULL OR v.registrada_por_id = $6)
              AND ($7::text IS NULL OR v.canal::text = $7)
              AND ($8::text IS NULL OR v.entrega::text = $8)
        ),
        filtro_reserva AS (
            SELECT estado FROM reserva r
            WHERE r.creada_en::date BETWEEN $1 AND $2
              AND ($4::uuid IS NULL OR r.sucursal_id = $4)
              AND ($5::uuid IS NULL OR EXISTS (
                  SELECT 1 FROM reserva_detalle rd
                  JOIN producto_variante pv ON pv.id = rd.variante_id
                  JOIN producto p           ON p.id = pv.producto_id
                  WHERE rd.reserva_id = r.id AND p.categoria_id = $5
              ))
              AND ($6::uuid IS NULL OR r.atendida_por_id = $6)
        )
        SELECT
            (SELECT COUNT(*) FROM filtro_venta)                                  AS ventas_cantidad,
            COALESCE((SELECT SUM(total) FROM filtro_venta), 0)                   AS ventas_monto,
            COALESCE((SELECT AVG(total) FROM filtro_venta), 0)                   AS ticket_promedio,
            (SELECT COUNT(*) FROM filtro_reserva)                                AS reservas_creadas,
            (SELECT COUNT(*) FROM filtro_reserva WHERE estado = 'CONVERTIDA')    AS reservas_convertidas,
            (
                SELECT COUNT(*) FROM inventario i
                JOIN sucursal s ON s.id = i.sucursal_id
                WHERE s.activa AND ($4::uuid IS NULL OR i.sucursal_id = $4)
                  AND i.stock_minimo > 0 AND i.disponible > 0 AND i.disponible <= i.stock_minimo
            )                                                                    AS variantes_stock_bajo,
            (
                SELECT COUNT(*) FROM inventario i
                JOIN sucursal s ON s.id = i.sucursal_id
                WHERE s.activa AND ($4::uuid IS NULL OR i.sucursal_id = $4)
                  AND i.disponible = 0
            )                                                                    AS variantes_agotadas
        """,
        desde,
        hasta,
        list(VENTA_ESTADOS_CONTADOS),
        sucursal,
        categoria_id,
        vendedor_id,
        canal,
        entrega,
    )
    datos = _normalizar(fila)
    reservas_creadas: int = datos["reservas_creadas"]
    reservas_convertidas: int = datos["reservas_convertidas"]
    tasa = round(reservas_convertidas / reservas_creadas * 100, 1) if reservas_creadas else 0.0
    return {"desde": desde, "hasta": hasta, **datos, "tasa_conversion_reservas": tasa}


async def _consultar_ventas_diarias(
    conn: asyncpg.Connection,
    desde: date,
    hasta: date,
    sucursal: UUID | None,
    canal: str | None,
    categoria_id: UUID | None,
    vendedor_id: UUID | None,
    entrega: str | None,
) -> list[dict]:
    filas = await conn.fetch(
        """
        SELECT v.fecha::date AS dia, v.sucursal_id, s.nombre AS sucursal, v.canal::text AS canal,
               COUNT(*) AS cantidad_ventas, SUM(v.total) AS monto_total, AVG(v.total) AS ticket_promedio
        FROM venta v
        JOIN sucursal s ON s.id = v.sucursal_id
        WHERE v.estado = ANY($3::estado_venta[])
          AND v.fecha::date BETWEEN $1 AND $2
          AND ($4::uuid IS NULL OR v.sucursal_id = $4)
          AND ($5::text IS NULL OR v.canal::text = $5)
          AND ($6::uuid IS NULL OR EXISTS (
              SELECT 1 FROM venta_detalle vd
              JOIN producto_variante pv ON pv.id = vd.variante_id
              JOIN producto p           ON p.id = pv.producto_id
              WHERE vd.venta_id = v.id AND p.categoria_id = $6
          ))
          AND ($7::uuid IS NULL OR v.registrada_por_id = $7)
          AND ($8::text IS NULL OR v.entrega::text = $8)
        GROUP BY 1, 2, 3, 4
        ORDER BY dia, sucursal, canal
        """,
        desde,
        hasta,
        list(VENTA_ESTADOS_CONTADOS),
        sucursal,
        canal,
        categoria_id,
        vendedor_id,
        entrega,
    )
    return [_normalizar(f) for f in filas]


async def _consultar_ventas_por_sucursal(
    conn: asyncpg.Connection,
    desde: date,
    hasta: date,
    sucursal: UUID | None,
    canal: str | None,
    categoria_id: UUID | None,
    vendedor_id: UUID | None,
    entrega: str | None,
) -> list[dict]:
    filas = await conn.fetch(
        """
        SELECT v.sucursal_id, s.nombre AS sucursal,
               COUNT(*) AS cantidad_ventas, SUM(v.total) AS monto_total, AVG(v.total) AS ticket_promedio
        FROM venta v
        JOIN sucursal s ON s.id = v.sucursal_id
        WHERE v.estado = ANY($3::estado_venta[])
          AND v.fecha::date BETWEEN $1 AND $2
          AND ($4::uuid IS NULL OR v.sucursal_id = $4)
          AND ($5::text IS NULL OR v.canal::text = $5)
          AND ($6::uuid IS NULL OR EXISTS (
              SELECT 1 FROM venta_detalle vd
              JOIN producto_variante pv ON pv.id = vd.variante_id
              JOIN producto p           ON p.id = pv.producto_id
              WHERE vd.venta_id = v.id AND p.categoria_id = $6
          ))
          AND ($7::uuid IS NULL OR v.registrada_por_id = $7)
          AND ($8::text IS NULL OR v.entrega::text = $8)
        GROUP BY 1, 2
        ORDER BY monto_total DESC
        """,
        desde,
        hasta,
        list(VENTA_ESTADOS_CONTADOS),
        sucursal,
        canal,
        categoria_id,
        vendedor_id,
        entrega,
    )
    return [_normalizar(f) for f in filas]


async def _consultar_top_productos(
    conn: asyncpg.Connection,
    desde: date,
    hasta: date,
    sucursal: UUID | None,
    canal: str | None,
    categoria_id: UUID | None,
    vendedor_id: UUID | None,
    entrega: str | None,
    limite: int,
) -> list[dict]:
    filas = await conn.fetch(
        """
        SELECT p.id AS producto_id, p.nombre AS producto,
               SUM(vd.cantidad) AS unidades_vendidas, SUM(vd.subtotal) AS monto_vendido
        FROM venta_detalle vd
        JOIN venta v              ON v.id = vd.venta_id
        JOIN producto_variante pv ON pv.id = vd.variante_id
        JOIN producto p           ON p.id = pv.producto_id
        WHERE v.estado = ANY($3::estado_venta[])
          AND v.fecha::date BETWEEN $1 AND $2
          AND ($4::uuid IS NULL OR v.sucursal_id = $4)
          AND ($5::text IS NULL OR v.canal::text = $5)
          AND ($6::uuid IS NULL OR p.categoria_id = $6)
          AND ($7::uuid IS NULL OR v.registrada_por_id = $7)
          AND ($8::text IS NULL OR v.entrega::text = $8)
        GROUP BY p.id, p.nombre
        ORDER BY unidades_vendidas DESC, monto_vendido DESC
        LIMIT $9
        """,
        desde,
        hasta,
        list(VENTA_ESTADOS_CONTADOS),
        sucursal,
        canal,
        categoria_id,
        vendedor_id,
        entrega,
        limite,
    )
    return [_normalizar(f) for f in filas]


async def _consultar_stock_por_sucursal(conn: asyncpg.Connection, sucursal: UUID | None) -> list[dict]:
    filas = await conn.fetch(
        """
        SELECT i.sucursal_id, s.nombre AS sucursal,
               SUM(i.cantidad_fisica)    AS total_fisico,
               SUM(i.cantidad_reservada) AS total_reservado,
               SUM(i.disponible)         AS total_disponible,
               COUNT(*) FILTER (WHERE i.disponible = 0) AS variantes_agotadas,
               COUNT(*) FILTER (
                   WHERE i.stock_minimo > 0 AND i.disponible > 0 AND i.disponible <= i.stock_minimo
               ) AS variantes_stock_bajo
        FROM inventario i
        JOIN sucursal s ON s.id = i.sucursal_id
        WHERE s.activa AND ($1::uuid IS NULL OR i.sucursal_id = $1)
        GROUP BY i.sucursal_id, s.nombre
        ORDER BY s.nombre
        """,
        sucursal,
    )
    return [_normalizar(f) for f in filas]


async def _consultar_reservas_por_estado(conn: asyncpg.Connection, sucursal: UUID | None) -> list[dict]:
    filas = await conn.fetch(
        """
        SELECT r.estado::text AS estado, COUNT(*) AS cantidad
        FROM reserva r
        WHERE ($1::uuid IS NULL OR r.sucursal_id = $1)
        GROUP BY r.estado
        ORDER BY r.estado
        """,
        sucursal,
    )
    return [_normalizar(f) for f in filas]


async def _consultar_envios_por_estado(conn: asyncpg.Connection, sucursal: UUID | None) -> list[dict]:
    filas = await conn.fetch(
        """
        SELECT e.estado::text AS estado, COUNT(*) AS cantidad
        FROM envio e
        WHERE ($1::uuid IS NULL OR e.sucursal_id = $1)
        GROUP BY e.estado
        ORDER BY e.estado
        """,
        sucursal,
    )
    return [_normalizar(f) for f in filas]


async def _consultar_productos_sin_movimiento(
    conn: asyncpg.Connection, sucursal: UUID | None, limite: int
) -> list[dict]:
    filas = await conn.fetch(
        """
        SELECT pv.id AS variante_id, p.nombre AS producto, t.codigo AS talla, c.nombre AS color,
               i.sucursal_id, s.nombre AS sucursal, i.cantidad_fisica
        FROM inventario i
        JOIN sucursal s           ON s.id = i.sucursal_id
        JOIN producto_variante pv ON pv.id = i.variante_id
        JOIN producto p           ON p.id = pv.producto_id
        JOIN talla t              ON t.id = pv.talla_id
        JOIN color c              ON c.id = pv.color_id
        WHERE s.activa AND i.cantidad_fisica > 0
          AND ($1::uuid IS NULL OR i.sucursal_id = $1)
          AND NOT EXISTS (SELECT 1 FROM venta_detalle vd WHERE vd.variante_id = pv.id)
        ORDER BY p.nombre, t.codigo, c.nombre
        LIMIT $2
        """,
        sucursal,
        limite,
    )
    return [_normalizar(f) for f in filas]


async def _consultar_top_clientes(conn: asyncpg.Connection, sucursal: UUID | None, limite: int) -> list[dict]:
    filas = await conn.fetch(
        """
        SELECT v.usuario_id, (u.nombre || ' ' || u.apellido) AS cliente, u.email,
               COUNT(*) AS cantidad_compras, SUM(v.total) AS monto_total
        FROM venta v
        JOIN usuario u ON u.id = v.usuario_id
        WHERE v.estado = ANY($3::estado_venta[])
          AND v.usuario_id IS NOT NULL
          AND ($1::uuid IS NULL OR v.sucursal_id = $1)
        GROUP BY v.usuario_id, u.nombre, u.apellido, u.email
        ORDER BY monto_total DESC
        LIMIT $2
        """,
        sucursal,
        limite,
        list(VENTA_ESTADOS_CONTADOS),
    )
    return [_normalizar(f) for f in filas]


async def _consultar_ocupacion_cajas(conn: asyncpg.Connection, sucursal: UUID | None) -> list[dict]:
    filas = await conn.fetch(
        """
        SELECT c.sucursal_id, s.nombre AS sucursal,
               COUNT(*) AS total_cajas,
               COUNT(*) FILTER (WHERE sc.id IS NOT NULL) AS cajas_abiertas
        FROM caja c
        JOIN sucursal s ON s.id = c.sucursal_id
        LEFT JOIN sesion_caja sc ON sc.caja_id = c.id AND sc.estado = 'ABIERTA'
        WHERE c.activa AND s.activa
          AND ($1::uuid IS NULL OR c.sucursal_id = $1)
        GROUP BY c.sucursal_id, s.nombre
        ORDER BY s.nombre
        """,
        sucursal,
    )
    return [_normalizar(f) for f in filas]


async def _consultar_recepciones_pendientes(conn: asyncpg.Connection, sucursal: UUID | None) -> list[dict]:
    filas = await conn.fetch(
        """
        SELECT r.proveedor_id, pr.nombre AS proveedor,
               COUNT(*) AS cantidad, COALESCE(SUM(r.total), 0) AS monto_total
        FROM recepcion r
        JOIN proveedor pr ON pr.id = r.proveedor_id
        WHERE r.estado = 'BORRADOR'
          AND ($1::uuid IS NULL OR r.sucursal_id = $1)
        GROUP BY r.proveedor_id, pr.nombre
        ORDER BY cantidad DESC, pr.nombre
        """,
        sucursal,
    )
    return [_normalizar(f) for f in filas]


# ---------------------------------------------------------------------
#  DINAMICOS: aceptan filtros de fecha / sucursal / canal
# ---------------------------------------------------------------------


@router.get("/indicadores", response_model=IndicadoresOut)
async def obtener_indicadores(
    desde: date | None = Query(default=None),
    hasta: date | None = Query(default=None),
    sucursal_id: UUID | None = Query(default=None),
    categoria_id: UUID | None = Query(default=None),
    vendedor_id: UUID | None = Query(default=None),
    canal: str | None = Query(default=None, pattern=CANAL_PATTERN),
    entrega: str | None = Query(default=None, pattern=ENTREGA_PATTERN),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> IndicadoresOut:
    desde_r, hasta_r = _rango_fechas(desde, hasta)
    sucursal = _resolver_sucursal(staff, sucursal_id)
    datos = await _consultar_indicadores(conn, desde_r, hasta_r, sucursal, categoria_id, vendedor_id, canal, entrega)
    return IndicadoresOut(**datos)


@router.get("/ventas-diarias", response_model=list[VentaDiariaOut])
async def listar_ventas_diarias(
    desde: date | None = Query(default=None),
    hasta: date | None = Query(default=None),
    sucursal_id: UUID | None = Query(default=None),
    canal: str | None = Query(default=None, pattern=CANAL_PATTERN),
    categoria_id: UUID | None = Query(default=None),
    vendedor_id: UUID | None = Query(default=None),
    entrega: str | None = Query(default=None, pattern=ENTREGA_PATTERN),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[VentaDiariaOut]:
    desde_r, hasta_r = _rango_fechas(desde, hasta)
    sucursal = _resolver_sucursal(staff, sucursal_id)
    filas = await _consultar_ventas_diarias(conn, desde_r, hasta_r, sucursal, canal, categoria_id, vendedor_id, entrega)
    return [VentaDiariaOut(**f) for f in filas]


@router.get("/ventas-por-sucursal", response_model=list[VentaPorSucursalOut])
async def listar_ventas_por_sucursal(
    desde: date | None = Query(default=None),
    hasta: date | None = Query(default=None),
    sucursal_id: UUID | None = Query(default=None),
    canal: str | None = Query(default=None, pattern=CANAL_PATTERN),
    categoria_id: UUID | None = Query(default=None),
    vendedor_id: UUID | None = Query(default=None),
    entrega: str | None = Query(default=None, pattern=ENTREGA_PATTERN),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[VentaPorSucursalOut]:
    desde_r, hasta_r = _rango_fechas(desde, hasta)
    sucursal = _resolver_sucursal(staff, sucursal_id)
    filas = await _consultar_ventas_por_sucursal(
        conn, desde_r, hasta_r, sucursal, canal, categoria_id, vendedor_id, entrega
    )
    return [VentaPorSucursalOut(**f) for f in filas]


@router.get("/top-productos", response_model=list[ProductoRankingOut])
async def listar_top_productos(
    desde: date | None = Query(default=None),
    hasta: date | None = Query(default=None),
    sucursal_id: UUID | None = Query(default=None),
    canal: str | None = Query(default=None, pattern=CANAL_PATTERN),
    categoria_id: UUID | None = Query(default=None),
    vendedor_id: UUID | None = Query(default=None),
    entrega: str | None = Query(default=None, pattern=ENTREGA_PATTERN),
    limite: int = Query(default=10, ge=1, le=50),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[ProductoRankingOut]:
    desde_r, hasta_r = _rango_fechas(desde, hasta)
    sucursal = _resolver_sucursal(staff, sucursal_id)
    filas = await _consultar_top_productos(
        conn, desde_r, hasta_r, sucursal, canal, categoria_id, vendedor_id, entrega, limite
    )
    return [ProductoRankingOut(**f) for f in filas]


# ---------------------------------------------------------------------
#  ESTATICOS: foto del estado actual, sin filtro de fecha
# ---------------------------------------------------------------------


@router.get("/stock-por-sucursal", response_model=list[StockSucursalOut])
async def listar_stock_por_sucursal(
    sucursal_id: UUID | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[StockSucursalOut]:
    sucursal = _resolver_sucursal(staff, sucursal_id)
    filas = await _consultar_stock_por_sucursal(conn, sucursal)
    return [StockSucursalOut(**f) for f in filas]


@router.get("/reservas-por-estado", response_model=list[ReservaEstadoOut])
async def listar_reservas_por_estado(
    sucursal_id: UUID | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[ReservaEstadoOut]:
    sucursal = _resolver_sucursal(staff, sucursal_id)
    filas = await _consultar_reservas_por_estado(conn, sucursal)
    return [ReservaEstadoOut(**f) for f in filas]


@router.get("/envios-por-estado", response_model=list[EnvioEstadoOut])
async def listar_envios_por_estado(
    sucursal_id: UUID | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[EnvioEstadoOut]:
    sucursal = _resolver_sucursal(staff, sucursal_id)
    filas = await _consultar_envios_por_estado(conn, sucursal)
    return [EnvioEstadoOut(**f) for f in filas]


@router.get("/productos-sin-movimiento", response_model=list[ProductoSinMovimientoOut])
async def listar_productos_sin_movimiento(
    sucursal_id: UUID | None = Query(default=None),
    limite: int = Query(default=50, ge=1, le=200),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[ProductoSinMovimientoOut]:
    """Variantes con stock fisico en sucursal que nunca tuvieron una linea en venta_detalle."""
    sucursal = _resolver_sucursal(staff, sucursal_id)
    filas = await _consultar_productos_sin_movimiento(conn, sucursal, limite)
    return [ProductoSinMovimientoOut(**f) for f in filas]


@router.get("/top-clientes", response_model=list[ClienteRankingOut])
async def listar_top_clientes(
    sucursal_id: UUID | None = Query(default=None),
    limite: int = Query(default=10, ge=1, le=50),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[ClienteRankingOut]:
    """Ranking historico (sin rango de fecha, foto actual) de clientes por monto comprado."""
    sucursal = _resolver_sucursal(staff, sucursal_id)
    filas = await _consultar_top_clientes(conn, sucursal, limite)
    return [ClienteRankingOut(**f) for f in filas]


@router.get("/ocupacion-cajas", response_model=list[CajaOcupacionOut])
async def listar_ocupacion_cajas(
    sucursal_id: UUID | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[CajaOcupacionOut]:
    """Cajas activas por sucursal vs. cuantas tienen una sesion ABIERTA en este momento."""
    sucursal = _resolver_sucursal(staff, sucursal_id)
    filas = await _consultar_ocupacion_cajas(conn, sucursal)
    return [CajaOcupacionOut(**f) for f in filas]


@router.get("/recepciones-pendientes", response_model=list[RecepcionPendienteProveedorOut])
async def listar_recepciones_pendientes(
    sucursal_id: UUID | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[RecepcionPendienteProveedorOut]:
    """Recepciones en BORRADOR (todavia no confirmadas) agrupadas por proveedor."""
    sucursal = _resolver_sucursal(staff, sucursal_id)
    filas = await _consultar_recepciones_pendientes(conn, sucursal)
    return [RecepcionPendienteProveedorOut(**f) for f in filas]


@router.get("/vendedores", response_model=list[VendedorOut])
async def listar_vendedores(
    sucursal_id: UUID | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[VendedorOut]:
    """Staff de la sucursal visible, para poblar el filtro 'vendedor' de los reportes dinamicos."""
    sucursal = _resolver_sucursal(staff, sucursal_id)

    filas = await conn.fetch(
        """
        SELECT u.id, (u.nombre || ' ' || u.apellido) AS nombre
        FROM empleado e
        JOIN usuario u ON u.id = e.usuario_id
        WHERE e.activo AND u.activo
          AND ($1::uuid IS NULL OR e.sucursal_id = $1)
        ORDER BY nombre
        """,
        sucursal,
    )
    return [VendedorOut(**dict(fila)) for fila in filas]


# ---------------------------------------------------------------------
#  IA / VOZ: "Reporte con IA" -- consultas en lenguaje natural (texto o voz transcripta en el
#  navegador con la Web Speech API, sin backend propio para eso) sobre los mismos 11 reportes de
#  arriba. Mismo patron de tool-use que asistente/router.py (CU18): un loop contra la API de
#  Claude con una herramienta por reporte, todas de solo lectura contra Postgres -- el modelo
#  nunca inventa una cifra, solo puede citar lo que una herramienta devolvio en esta conversacion.
#
#  Autorizacion: el endpoint exige el mismo permiso `reportes.leer` que el resto de CU15 (no es
#  una pantalla nueva, es otra forma de pedir los mismos datos). El alcance por sucursal tambien
#  se respeta: las herramientas reciben un nombre de sucursal en lenguaje natural
#  (`sucursal_nombre`, resuelto por ILIKE contra `sucursal.nombre`) y ese id pasa por
#  `_resolver_sucursal` igual que en los endpoints HTTP -- un ENCARGADO que pida la sucursal de
#  otro no obtiene los datos, la herramienta devuelve un aviso en texto y Claude se lo explica al
#  usuario en vez de tirar un 403 que cortaria toda la conversacion.
# ---------------------------------------------------------------------

MAX_ITERACIONES_IA = 4
MAX_TOKENS_IA = 700
MAX_FILAS_EN_TEXTO = 30

_TOOLS_DINAMICOS = {
    "consultar_indicadores",
    "consultar_ventas_diarias",
    "consultar_ventas_por_sucursal",
    "consultar_top_productos",
}

ETIQUETAS_TOOL: dict[str, str] = {
    "consultar_indicadores": "Indicadores del período",
    "consultar_ventas_diarias": "Ventas diarias",
    "consultar_ventas_por_sucursal": "Ventas por sucursal",
    "consultar_top_productos": "Top productos más vendidos",
    "consultar_stock_por_sucursal": "Stock disponible por sucursal",
    "consultar_reservas_por_estado": "Reservas por estado",
    "consultar_envios_por_estado": "Envíos por estado",
    "consultar_productos_sin_movimiento": "Productos sin movimiento",
    "consultar_top_clientes": "Top clientes",
    "consultar_ocupacion_cajas": "Ocupación de cajas",
    "consultar_recepciones_pendientes": "Recepciones pendientes por proveedor",
}

ETIQUETAS_CAMPO: dict[str, str] = {
    "desde": "Desde",
    "hasta": "Hasta",
    "ventas_cantidad": "Ventas",
    "ventas_monto": "Monto vendido (Bs)",
    "ticket_promedio": "Ticket promedio (Bs)",
    "reservas_creadas": "Reservas creadas",
    "reservas_convertidas": "Reservas convertidas",
    "tasa_conversion_reservas": "Conversión (%)",
    "variantes_stock_bajo": "Stock bajo",
    "variantes_agotadas": "Agotadas",
    "dia": "Día",
    "sucursal": "Sucursal",
    "canal": "Canal",
    "cantidad_ventas": "Ventas",
    "monto_total": "Monto total (Bs)",
    "producto": "Producto",
    "unidades_vendidas": "Unidades vendidas",
    "monto_vendido": "Monto vendido (Bs)",
    "total_fisico": "Físico",
    "total_reservado": "Reservado",
    "total_disponible": "Disponible",
    "estado": "Estado",
    "cantidad": "Cantidad",
    "talla": "Talla",
    "color": "Color",
    "cantidad_fisica": "Stock físico",
    "cliente": "Cliente",
    "email": "Email",
    "cantidad_compras": "Compras",
    "total_cajas": "Cajas totales",
    "cajas_abiertas": "Cajas abiertas",
    "proveedor": "Proveedor",
}

_SYSTEM_PROMPT_IA = """\
Sos el analista de datos de FashionStore, una cadena de moda femenina con sucursales en Santa \
Cruz, La Paz y Cochabamba (Bolivia). Atendes al personal de gestion (encargados y administradores) \
que te consulta reportes de ventas, stock, reservas, envios, cajas y recepciones -- por texto o \
por voz transcripta en el navegador.

Reglas estrictas:
- Nunca inventes una cifra. Toda cifra que menciones tiene que venir de una llamada a una de tus \
herramientas de consulta en esta misma conversacion. Si todavia no llamaste ninguna, no des numeros.
- Elegi la herramienta que mejor responda la pregunta. Si falta un dato importante (que periodo, \
que sucursal) y la pregunta es ambigua, pregunta 1-2 cosas cortas antes de consultar; si la \
pregunta ya alcanza para acotar, usa los valores por omision (ultimos 30 dias, todas las \
sucursales que el usuario puede ver) sin preguntar de mas.
- Si te mencionan una sucursal, categoria o vendedor, pasa el nombre tal cual te lo dijeron en el \
parametro correspondiente (sucursal_nombre, categoria_nombre, vendedor_nombre) -- la herramienta \
lo resuelve contra la base, vos no adivines ningun identificador.
- Si una herramienta devuelve un aviso de permiso o de que no encontro algo, contaselo al usuario \
con naturalidad en vez de insistir con la misma consulta.
- Leete bien el resultado de la herramienta antes de resumirlo: contá cuantas filas trae la tabla \
(la primera linea es el encabezado) antes de decir que "no hay resultados" -- si la tabla tiene \
filas, describi lo que encontraste, no lo contrario.
- Respondes en espanol, tono profesional y directo, 2-4 oraciones con las cifras clave nomas -- \
esto se puede leer en voz alta, asi que evita markdown pesado (tablas, negritas, listas): la \
tabla completa con el detalle ya se muestra aparte en la pantalla.
- Solo hablas de reportes e indicadores de FashionStore. Si te preguntan algo sin relacion, \
respondes amablemente que no podes ayudar con eso.
"""

_PROP_SUCURSAL = {
    "type": "string",
    "description": (
        "Ciudad o nombre de la sucursal (ej. 'Santa Cruz', 'La Paz', 'Cochabamba' o "
        "'FashionStore Equipetrol'). Omitilo para no filtrar."
    ),
}
_PROP_FILTROS_DINAMICOS = {
    "desde": {
        "type": "string",
        "description": "Fecha inicial en formato YYYY-MM-DD. Omitilo para el valor por omision (hace 30 dias).",
    },
    "hasta": {
        "type": "string",
        "description": "Fecha final en formato YYYY-MM-DD. Omitilo para el valor por omision (hoy).",
    },
    "sucursal_nombre": _PROP_SUCURSAL,
    "categoria_nombre": {
        "type": "string",
        "description": "Nombre (o parte del nombre) de la categoria de producto, ej. 'Vestidos'. Omitilo para no filtrar.",
    },
    "vendedor_nombre": {
        "type": "string",
        "description": "Nombre del vendedor o cajero que registro la venta. Omitilo para no filtrar.",
    },
    "canal": {"type": "string", "enum": ["WEB", "MOVIL", "POS"], "description": "Canal de venta. Omitilo para todos."},
    "entrega": {
        "type": "string",
        "enum": ["RETIRO_SUCURSAL", "DOMICILIO"],
        "description": "Modo de entrega. Omitilo para todos.",
    },
}


def _tool_dinamico(nombre: str, descripcion: str, con_limite: bool = False) -> dict:
    # Sin "strict" y con propiedades opcionales (no union types con null): ese patron es de
    # OpenAI, no de Claude -- con 11 herramientas x hasta 7 filtros nullable cada una, Claude
    # rechaza el schema completo con 400 ("Schemas contains too many parameters with union
    # types... limit: 16"). El clamp de limite y el default de fecha ya viven en
    # _ejecutar_herramienta_reporte, asi que el modelo solo necesita mandar lo que quiera filtrar.
    props = dict(_PROP_FILTROS_DINAMICOS)
    if con_limite:
        props = {
            **props,
            "limite": {
                "type": "integer",
                "description": "Cuantos resultados traer como mucho (entre 1 y 50, sugerido 10).",
            },
        }
    return {
        "name": nombre,
        "description": descripcion,
        "input_schema": {"type": "object", "properties": props, "additionalProperties": False},
    }


def _tool_estatico(nombre: str, descripcion: str, con_limite: bool = False, limite_max: int = 50) -> dict:
    props: dict = {"sucursal_nombre": _PROP_SUCURSAL}
    if con_limite:
        props["limite"] = {
            "type": "integer",
            "description": f"Cuantos resultados traer como mucho (entre 1 y {limite_max}).",
        }
    return {
        "name": nombre,
        "description": descripcion,
        "input_schema": {"type": "object", "properties": props, "additionalProperties": False},
    }


HERRAMIENTAS_REPORTES = [
    _tool_dinamico(
        "consultar_indicadores",
        "KPIs del periodo: cantidad y monto de ventas, ticket promedio, reservas creadas y "
        "convertidas, variantes con stock bajo y agotadas.",
    ),
    _tool_dinamico("consultar_ventas_diarias", "Ventas agrupadas por dia, sucursal y canal en el periodo."),
    _tool_dinamico("consultar_ventas_por_sucursal", "Ventas totales agrupadas por sucursal en el periodo."),
    _tool_dinamico(
        "consultar_top_productos",
        "Ranking de productos mas vendidos por unidades en el periodo.",
        con_limite=True,
    ),
    _tool_estatico(
        "consultar_stock_por_sucursal",
        "Foto actual del stock fisico, reservado y disponible por sucursal.",
    ),
    _tool_estatico("consultar_reservas_por_estado", "Foto actual de la cantidad de reservas agrupadas por estado."),
    _tool_estatico(
        "consultar_envios_por_estado",
        "Foto actual de la cantidad de envios a domicilio (CU20) agrupados por estado.",
    ),
    _tool_estatico(
        "consultar_productos_sin_movimiento",
        "Variantes con stock fisico que nunca se vendieron.",
        con_limite=True,
        limite_max=200,
    ),
    _tool_estatico(
        "consultar_top_clientes",
        "Ranking historico de clientes por monto comprado.",
        con_limite=True,
    ),
    _tool_estatico(
        "consultar_ocupacion_cajas",
        "Cajas activas por sucursal vs. cuantas tienen una sesion abierta ahora mismo.",
    ),
    _tool_estatico(
        "consultar_recepciones_pendientes",
        "Recepciones de mercaderia en borrador (no confirmadas) agrupadas por proveedor.",
    ),
]


def _parsear_fecha(valor: object) -> date | None:
    if not valor or not isinstance(valor, str):
        return None
    try:
        return date.fromisoformat(valor)
    except ValueError:
        return None


async def _resolver_sucursal_nombre(
    conn: asyncpg.Connection, staff: dict, nombre: str | None
) -> tuple[UUID | None, str | None]:
    """Nombre en lenguaje natural -> uuid, aplicando el mismo alcance por sucursal que los
    endpoints HTTP. Si el nombre no matchea o el usuario no tiene permiso para verla, devuelve el
    alcance por defecto del usuario y un aviso en texto (no un 403 que corte la conversacion)."""
    if not nombre:
        return _resolver_sucursal(staff, None), None
    # `sucursal.nombre` es el nombre comercial ("FashionStore Equipetrol"), no la ciudad -- la
    # gente pregunta por ciudad ("Santa Cruz", "La Paz"), que vive en `ciudad` (ENUM ciudad_bo,
    # ej. 'SANTA_CRUZ'). Se matchea contra ambos.
    fila = await conn.fetchrow(
        """
        SELECT id FROM sucursal
        WHERE activa AND (
            nombre ILIKE '%' || $1 || '%'
            OR replace(ciudad::text, '_', ' ') ILIKE '%' || $1 || '%'
        )
        ORDER BY nombre
        LIMIT 1
        """,
        nombre,
    )
    if fila is None:
        return (
            _resolver_sucursal(staff, None),
            f"No se encontro una sucursal activa llamada '{nombre}'; se uso tu alcance por defecto.",
        )
    try:
        return _resolver_sucursal(staff, fila["id"]), None
    except HTTPException as exc:
        return _resolver_sucursal(staff, None), str(exc.detail)


async def _resolver_categoria_nombre(conn: asyncpg.Connection, nombre: str | None) -> tuple[UUID | None, str | None]:
    if not nombre:
        return None, None
    fila = await conn.fetchrow("SELECT id FROM categoria WHERE nombre ILIKE '%' || $1 || '%' LIMIT 1", nombre)
    if fila is None:
        return None, f"No se encontro una categoria llamada '{nombre}'; se muestra sin ese filtro."
    return fila["id"], None


async def _resolver_vendedor_nombre(
    conn: asyncpg.Connection, sucursal: UUID | None, nombre: str | None
) -> tuple[UUID | None, str | None]:
    if not nombre:
        return None, None
    fila = await conn.fetchrow(
        """
        SELECT u.id FROM empleado e JOIN usuario u ON u.id = e.usuario_id
        WHERE e.activo AND u.activo AND (u.nombre || ' ' || u.apellido) ILIKE '%' || $1 || '%'
          AND ($2::uuid IS NULL OR e.sucursal_id = $2)
        LIMIT 1
        """,
        nombre,
        sucursal,
    )
    if fila is None:
        return None, f"No se encontro un vendedor llamado '{nombre}' en tu alcance; se muestra sin ese filtro."
    return fila["id"], None


def _filas_a_texto(filas: list[dict]) -> str:
    if not filas:
        return "Sin resultados para esos filtros."
    claves = list(filas[0].keys())
    lineas = [" | ".join(claves)]
    for fila in filas[:MAX_FILAS_EN_TEXTO]:
        valores = []
        for clave in claves:
            valor = fila[clave]
            valores.append(f"{valor:.2f}" if isinstance(valor, float) else str(valor))
        lineas.append(" | ".join(valores))
    if len(filas) > MAX_FILAS_EN_TEXTO:
        lineas.append(f"... y {len(filas) - MAX_FILAS_EN_TEXTO} fila(s) mas (no listadas para no gastar de mas).")
    return "\n".join(lineas)


async def _ejecutar_herramienta_reporte(
    conn: asyncpg.Connection, staff: dict, nombre_tool: str, entrada: dict
) -> tuple[str, list[dict], str, list[str]]:
    """Devuelve (texto para Claude, filas crudas, titulo, columnas) de la herramienta pedida."""
    avisos: list[str] = []
    titulo = ETIQUETAS_TOOL.get(nombre_tool, nombre_tool)

    desde_r = hasta_r = None
    if nombre_tool in _TOOLS_DINAMICOS:
        desde_r, hasta_r = _rango_fechas(_parsear_fecha(entrada.get("desde")), _parsear_fecha(entrada.get("hasta")))

    sucursal, aviso = await _resolver_sucursal_nombre(conn, staff, entrada.get("sucursal_nombre"))
    if aviso:
        avisos.append(aviso)

    categoria_id = vendedor_id = None
    if nombre_tool in _TOOLS_DINAMICOS:
        categoria_id, aviso = await _resolver_categoria_nombre(conn, entrada.get("categoria_nombre"))
        if aviso:
            avisos.append(aviso)
        vendedor_id, aviso = await _resolver_vendedor_nombre(conn, sucursal, entrada.get("vendedor_nombre"))
        if aviso:
            avisos.append(aviso)

    canal = entrada.get("canal")
    entrega = entrada.get("entrega")
    limite_crudo = entrada.get("limite")

    if nombre_tool == "consultar_indicadores":
        filas = [await _consultar_indicadores(conn, desde_r, hasta_r, sucursal, categoria_id, vendedor_id, canal, entrega)]
    elif nombre_tool == "consultar_ventas_diarias":
        filas = await _consultar_ventas_diarias(conn, desde_r, hasta_r, sucursal, canal, categoria_id, vendedor_id, entrega)
    elif nombre_tool == "consultar_ventas_por_sucursal":
        filas = await _consultar_ventas_por_sucursal(conn, desde_r, hasta_r, sucursal, canal, categoria_id, vendedor_id, entrega)
    elif nombre_tool == "consultar_top_productos":
        limite = min(max(int(limite_crudo), 1), 50) if isinstance(limite_crudo, int) else 10
        filas = await _consultar_top_productos(
            conn, desde_r, hasta_r, sucursal, canal, categoria_id, vendedor_id, entrega, limite
        )
    elif nombre_tool == "consultar_stock_por_sucursal":
        filas = await _consultar_stock_por_sucursal(conn, sucursal)
    elif nombre_tool == "consultar_reservas_por_estado":
        filas = await _consultar_reservas_por_estado(conn, sucursal)
    elif nombre_tool == "consultar_envios_por_estado":
        filas = await _consultar_envios_por_estado(conn, sucursal)
    elif nombre_tool == "consultar_productos_sin_movimiento":
        limite = min(max(int(limite_crudo), 1), 200) if isinstance(limite_crudo, int) else 50
        filas = await _consultar_productos_sin_movimiento(conn, sucursal, limite)
    elif nombre_tool == "consultar_top_clientes":
        limite = min(max(int(limite_crudo), 1), 50) if isinstance(limite_crudo, int) else 10
        filas = await _consultar_top_clientes(conn, sucursal, limite)
    elif nombre_tool == "consultar_ocupacion_cajas":
        filas = await _consultar_ocupacion_cajas(conn, sucursal)
    elif nombre_tool == "consultar_recepciones_pendientes":
        filas = await _consultar_recepciones_pendientes(conn, sucursal)
    else:
        return f"Herramienta desconocida: {nombre_tool}", [], titulo, []

    texto = _filas_a_texto(filas)
    if avisos:
        texto = "\n".join(avisos) + "\n" + texto
    columnas = [c for c in filas[0].keys() if not c.endswith("_id")] if filas else []
    return texto, filas, titulo, columnas


def _cliente_ia() -> anthropic.Anthropic:
    if not settings.anthropic_api_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Las consultas con IA no estan configuradas todavia (falta ANTHROPIC_API_KEY)",
        )
    return anthropic.Anthropic(api_key=settings.anthropic_api_key)


@router.post("/consulta-ia", response_model=ConsultaIaOut)
async def consulta_ia(
    body: ConsultaIaIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> ConsultaIaOut:
    cliente_ia = _cliente_ia()
    # Claude no sabe la fecha real "de hoy" (entrena con un corte de conocimiento pasado): sin
    # esto, "este mes" o "hoy" salian con el anio/mes del entrenamiento, no el actual.
    system = f"{_SYSTEM_PROMPT_IA}\n\nHoy es {date.today().isoformat()}."
    mensajes: list[dict] = [{"role": m.rol, "content": m.texto} for m in body.mensajes]

    titulo: str | None = None
    columnas: list[str] = []
    tabla: list[dict] = []

    for _ in range(MAX_ITERACIONES_IA):
        try:
            respuesta = cliente_ia.messages.create(
                model=settings.anthropic_model,
                max_tokens=MAX_TOKENS_IA,
                system=system,
                tools=HERRAMIENTAS_REPORTES,
                messages=mensajes,
            )
        except anthropic.AuthenticationError as exc:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Las consultas con IA no estan disponibles (clave de IA invalida)",
            ) from exc
        except anthropic.APIStatusError as exc:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Las consultas con IA no estan disponibles en este momento, intenta de nuevo",
            ) from exc

        if respuesta.stop_reason != "tool_use":
            texto = next((b.text for b in respuesta.content if b.type == "text"), "")
            return ConsultaIaOut(
                respuesta=texto or "No tengo una respuesta para eso, proba reformular tu consulta.",
                titulo=titulo,
                columnas=[ColumnaOut(clave=c, etiqueta=ETIQUETAS_CAMPO.get(c, c)) for c in columnas],
                tabla=tabla,
            )

        mensajes.append({"role": "assistant", "content": respuesta.content})
        resultados_tool = []
        for bloque in respuesta.content:
            if bloque.type != "tool_use":
                continue
            texto_resultado, filas, titulo_tool, columnas_tool = await _ejecutar_herramienta_reporte(
                conn, staff, bloque.name, bloque.input
            )
            titulo, tabla, columnas = titulo_tool, filas, columnas_tool
            resultados_tool.append({"type": "tool_result", "tool_use_id": bloque.id, "content": texto_resultado})
        mensajes.append({"role": "user", "content": resultados_tool})

    return ConsultaIaOut(
        respuesta="Perdon, no pude terminar de armar la respuesta. Proba reformular tu consulta.",
        titulo=None,
        columnas=[],
        tabla=[],
    )
