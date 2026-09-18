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
"""

from datetime import date, timedelta
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.db import get_connection
from app.core.deps import requiere_permiso
from app.modules.reportes.schemas import (
    CajaOcupacionOut,
    ClienteRankingOut,
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
        desde_r,
        hasta_r,
        list(VENTA_ESTADOS_CONTADOS),
        sucursal,
        categoria_id,
        vendedor_id,
        canal,
        entrega,
    )

    reservas_creadas: int = fila["reservas_creadas"]
    reservas_convertidas: int = fila["reservas_convertidas"]
    tasa = round(reservas_convertidas / reservas_creadas * 100, 1) if reservas_creadas else 0.0

    return IndicadoresOut(
        desde=desde_r,
        hasta=hasta_r,
        ventas_cantidad=fila["ventas_cantidad"],
        ventas_monto=fila["ventas_monto"],
        ticket_promedio=fila["ticket_promedio"],
        reservas_creadas=reservas_creadas,
        reservas_convertidas=reservas_convertidas,
        tasa_conversion_reservas=tasa,
        variantes_stock_bajo=fila["variantes_stock_bajo"],
        variantes_agotadas=fila["variantes_agotadas"],
    )


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
        desde_r,
        hasta_r,
        list(VENTA_ESTADOS_CONTADOS),
        sucursal,
        canal,
        categoria_id,
        vendedor_id,
        entrega,
    )
    return [VentaDiariaOut(**dict(fila)) for fila in filas]


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
        desde_r,
        hasta_r,
        list(VENTA_ESTADOS_CONTADOS),
        sucursal,
        canal,
        categoria_id,
        vendedor_id,
        entrega,
    )
    return [VentaPorSucursalOut(**dict(fila)) for fila in filas]


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
        desde_r,
        hasta_r,
        list(VENTA_ESTADOS_CONTADOS),
        sucursal,
        canal,
        categoria_id,
        vendedor_id,
        entrega,
        limite,
    )
    return [ProductoRankingOut(**dict(fila)) for fila in filas]


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
    return [StockSucursalOut(**dict(fila)) for fila in filas]


@router.get("/reservas-por-estado", response_model=list[ReservaEstadoOut])
async def listar_reservas_por_estado(
    sucursal_id: UUID | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[ReservaEstadoOut]:
    sucursal = _resolver_sucursal(staff, sucursal_id)

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
    return [ReservaEstadoOut(**dict(fila)) for fila in filas]


@router.get("/envios-por-estado", response_model=list[EnvioEstadoOut])
async def listar_envios_por_estado(
    sucursal_id: UUID | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[EnvioEstadoOut]:
    sucursal = _resolver_sucursal(staff, sucursal_id)

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
    return [EnvioEstadoOut(**dict(fila)) for fila in filas]


@router.get("/productos-sin-movimiento", response_model=list[ProductoSinMovimientoOut])
async def listar_productos_sin_movimiento(
    sucursal_id: UUID | None = Query(default=None),
    limite: int = Query(default=50, ge=1, le=200),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[ProductoSinMovimientoOut]:
    """Variantes con stock fisico en sucursal que nunca tuvieron una linea en venta_detalle."""
    sucursal = _resolver_sucursal(staff, sucursal_id)

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
    return [ProductoSinMovimientoOut(**dict(fila)) for fila in filas]


@router.get("/top-clientes", response_model=list[ClienteRankingOut])
async def listar_top_clientes(
    sucursal_id: UUID | None = Query(default=None),
    limite: int = Query(default=10, ge=1, le=50),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[ClienteRankingOut]:
    """Ranking historico (sin rango de fecha, foto actual) de clientes por monto comprado."""
    sucursal = _resolver_sucursal(staff, sucursal_id)

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
    return [ClienteRankingOut(**dict(fila)) for fila in filas]


@router.get("/ocupacion-cajas", response_model=list[CajaOcupacionOut])
async def listar_ocupacion_cajas(
    sucursal_id: UUID | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[CajaOcupacionOut]:
    """Cajas activas por sucursal vs. cuantas tienen una sesion ABIERTA en este momento."""
    sucursal = _resolver_sucursal(staff, sucursal_id)

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
    return [CajaOcupacionOut(**dict(fila)) for fila in filas]


@router.get("/recepciones-pendientes", response_model=list[RecepcionPendienteProveedorOut])
async def listar_recepciones_pendientes(
    sucursal_id: UUID | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[RecepcionPendienteProveedorOut]:
    """Recepciones en BORRADOR (todavia no confirmadas) agrupadas por proveedor."""
    sucursal = _resolver_sucursal(staff, sucursal_id)

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
    return [RecepcionPendienteProveedorOut(**dict(fila)) for fila in filas]


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
