"""Ajustes manuales de stock (PENDIENTES.txt 2.6).

fn_mover_inventario() ya acepta el tipo AJUSTE desde que se escribio (db/02_logica.sql) y el
permiso inventario.actualizar ya estaba sembrado para ADMIN y ENCARGADO, pero hasta
ahora ningun endpoint lo disparaba: era la unica forma de corregir un kardex (append-only, ver
CLAUDE.md) que la aplicacion no exponia. Este modulo no escribe cantidad_fisica/cantidad_reservada
directamente en ningun momento -- todo pasa por fn_mover_inventario, igual que recepciones.

Multi-tenant: la sucursal y la prenda tienen que ser de la empresa del usuario (404 si no).
"""

from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.auditoria import registrar_auditoria
from app.core.db import get_connection
from app.core.deps import requiere_permiso
from app.core.tenant import empresa_de, exigir_sucursal, exigir_variantes, sucursal_visible
from app.modules.catalogo_e_inventario.inventario.schemas import (
    AjusteIn,
    AjusteOut,
    MovimientoKardexOut,
    ResumenInventarioOut,
    VarianteBuscadaOut,
)

router = APIRouter(prefix="/inventario", tags=["inventario"])

puede_ver = requiere_permiso("inventario.leer", "inventario.actualizar")
puede_ajustar = requiere_permiso("inventario.actualizar")


async def _resolver_sucursal(
    conn: asyncpg.Connection, sucursal_id: UUID | None, staff: dict
) -> UUID:
    limite = sucursal_visible(staff)
    destino = sucursal_id or limite or staff["sucursal_id"]
    if destino is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Indica la sucursal"
        )
    if limite is not None and destino != limite:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="Esa sucursal no es la tuya"
        )
    await exigir_sucursal(conn, destino, empresa_de(staff))
    return destino


@router.get("/resumen", response_model=ResumenInventarioOut)
async def resumen_de_inventario(
    sucursal_id: UUID | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> ResumenInventarioOut:
    """Indicadores de la sucursal: cuanta ropa hay, cuanta esta comprometida y cuantas prendas
    estan agotadas o por debajo de su minimo."""
    destino = await _resolver_sucursal(conn, sucursal_id, staff)
    fila = await conn.fetchrow(
        """
        SELECT s.nombre AS sucursal,
               COUNT(i.id)::int                                            AS variantes,
               COALESCE(SUM(i.cantidad_fisica), 0)::int                    AS unidades_fisicas,
               COALESCE(SUM(i.cantidad_reservada), 0)::int                 AS unidades_reservadas,
               COALESCE(SUM(i.disponible), 0)::int                         AS unidades_disponibles,
               COUNT(i.id) FILTER (WHERE i.disponible <= 0)::int           AS agotadas,
               COUNT(i.id) FILTER (WHERE i.disponible > 0
                                     AND i.disponible <= i.stock_minimo)::int AS stock_bajo
        FROM sucursal s
        LEFT JOIN inventario i ON i.sucursal_id = s.id
             AND EXISTS (SELECT 1 FROM producto_variante pv JOIN producto pr ON pr.id = pv.producto_id
                          WHERE pv.id = i.variante_id AND pv.activa AND pr.activo)
        WHERE s.id = $1
        GROUP BY s.nombre
        """,
        destino,
    )
    return ResumenInventarioOut(sucursal_id=destino, **dict(fila))


@router.get("/variantes", response_model=list[VarianteBuscadaOut])
async def buscar_variantes(
    q: str = Query(default="", max_length=120, description="SKU, codigo de barras o nombre de la prenda"),
    sucursal_id: UUID | None = Query(default=None),
    alerta: str | None = Query(
        default=None,
        pattern="^(agotadas|bajo)$",
        description="Solo prendas agotadas o con stock bajo (por debajo de su minimo)",
    ),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[VarianteBuscadaOut]:
    """Buscador para elegir que ajustar, con el saldo actual de la sucursal destino a la vista
    (mismo patron que recepciones.buscar_variantes). Sin texto lista las prendas con menos
    disponible primero, que es lo que hay que mirar antes que nada; con `alerta` filtra las que
    necesitan reposicion."""
    destino = await _resolver_sucursal(conn, sucursal_id, staff)

    filas = await conn.fetch(
        """
        SELECT pv.id, pv.sku, pr.nombre AS producto, t.codigo AS talla,
               c.nombre AS color, c.codigo_hex,
               s.nombre AS sucursal,
               COALESCE(i.cantidad_fisica, 0)    AS cantidad_fisica,
               COALESCE(i.cantidad_reservada, 0) AS cantidad_reservada,
               COALESCE(i.disponible, 0)         AS disponible,
               COALESCE(i.stock_minimo, 0)       AS stock_minimo
        FROM producto_variante pv
        JOIN producto pr ON pr.id = pv.producto_id
        JOIN talla t     ON t.id = pv.talla_id
        JOIN color c     ON c.id = pv.color_id
        JOIN sucursal s  ON s.id = $2
        LEFT JOIN inventario i ON i.variante_id = pv.id AND i.sucursal_id = $2
        WHERE pv.activa AND pr.activo AND pr.empresa_id = s.empresa_id
          AND ($1 = '' OR pv.sku ILIKE '%' || $1 || '%'
               OR pv.codigo_barras ILIKE '%' || $1 || '%'
               OR pr.nombre ILIKE '%' || $1 || '%')
          AND ($3::text IS NULL
               OR ($3 = 'agotadas' AND COALESCE(i.disponible, 0) <= 0)
               OR ($3 = 'bajo' AND COALESCE(i.disponible, 0) > 0
                               AND COALESCE(i.disponible, 0) <= COALESCE(i.stock_minimo, 0)))
        ORDER BY COALESCE(i.disponible, 0), pr.nombre, t.orden, c.nombre
        LIMIT 40
        """,
        q.strip(),
        destino,
        alerta,
    )
    # sucursal_id no sale del JOIN (la variante puede no tener fila de inventario todavia ahi,
    # ver COALESCE arriba): siempre es la sucursal destino que se resolvio.
    return [VarianteBuscadaOut(**dict(fila), sucursal_id=destino) for fila in filas]


@router.get("/{variante_id}/kardex", response_model=list[MovimientoKardexOut])
async def kardex_de_variante(
    variante_id: UUID,
    sucursal_id: UUID = Query(...),
    limite: int = Query(default=50, ge=1, le=200),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[MovimientoKardexOut]:
    await _resolver_sucursal(conn, sucursal_id, staff)
    await exigir_variantes(conn, [variante_id], empresa_de(staff))

    filas = await conn.fetch(
        """
        SELECT m.id, m.tipo::text AS tipo, m.cantidad, m.saldo_anterior, m.saldo_nuevo,
               m.motivo, m.documento_tipo, m.documento_id,
               (u.nombre || ' ' || u.apellido) AS usuario, m.fecha
        FROM movimiento_inventario m
        LEFT JOIN usuario u ON u.id = m.usuario_id
        WHERE m.variante_id = $1 AND m.sucursal_id = $2
        ORDER BY m.fecha DESC, m.id DESC
        LIMIT $3
        """,
        variante_id,
        sucursal_id,
        limite,
    )
    return [MovimientoKardexOut(**dict(fila)) for fila in filas]


@router.post("/ajustes", response_model=AjusteOut, status_code=status.HTTP_201_CREATED)
async def registrar_ajuste(
    body: AjusteIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ajustar),
) -> AjusteOut:
    """Deja el saldo fisico de la variante en `cantidad_fisica_nueva` (valor absoluto, no un
    delta) y escribe el asiento en el kardex via fn_mover_inventario. Sin documento_tipo/
    documento_id: a diferencia de una venta o una recepcion, un ajuste manual no nace de otro
    registro del sistema, el usuario que lo hizo ya queda en el movimiento.

    fn_mover_inventario (db/02_logica.sql) trata AJUSTE distinto del resto de los tipos: guarda
    saldo_anterior/saldo_nuevo como cantidad_fisica cruda, no como disponible (fisico -
    reservado) -- correcto para este caso, porque el numero que le importa a quien ajusta es el
    fisico que acaba de contar, no uno que reste lo reservado."""
    await _resolver_sucursal(conn, body.sucursal_id, staff)
    await exigir_variantes(conn, [body.variante_id], empresa_de(staff))

    try:
        async with conn.transaction():
            # dos consultas, no una: la fila que fn_mover_inventario inserta no es visible para
            # un FROM movimiento_inventario de la MISMA sentencia (snapshot de Postgres tomado
            # antes de que la funcion corra), asi que "WHERE id = fn_mover_inventario(...)" no
            # encuentra nada -- probado en vivo, no es una suposicion.
            movimiento_id = await conn.fetchval(
                "SELECT fn_mover_inventario($1, $2, 'AJUSTE', $3, $4, NULL, NULL, $5)",
                body.sucursal_id,
                body.variante_id,
                body.cantidad_fisica_nueva,
                body.motivo,
                staff["id"],
            )
            movimiento = await conn.fetchrow(
                "SELECT id, saldo_anterior, saldo_nuevo, motivo, fecha "
                "FROM movimiento_inventario WHERE id = $1",
                movimiento_id,
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="inventario",
                entidad_id=body.variante_id,
                accion="ACTUALIZAR",
                datos_antes={
                    "sucursal_id": str(body.sucursal_id),
                    "cantidad_fisica": movimiento["saldo_anterior"],
                },
                datos_despues={
                    "sucursal_id": str(body.sucursal_id),
                    "cantidad_fisica": movimiento["saldo_nuevo"],
                    "motivo": body.motivo,
                },
            )
    except asyncpg.ForeignKeyViolationError:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="La sucursal o la variante no existen",
        )
    except asyncpg.CheckViolationError:
        # ck_inventario_saldos: el fisico no puede quedar por debajo de lo que comprometen las
        # reservas. Antes llegaba como 500. (La transaccion ya se deshizo, se puede leer.)
        reservada = await conn.fetchval(
            "SELECT cantidad_reservada FROM inventario WHERE sucursal_id = $1 AND variante_id = $2",
            body.sucursal_id,
            body.variante_id,
        )
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                f"No se puede dejar {body.cantidad_fisica_nueva} unidad(es): hay {reservada or 0} "
                "comprometida(s) por reservas. Atende, rechaza o cancela esas reservas primero."
            ),
        )
    except asyncpg.RaiseError as error:
        # defensivo: hoy AJUSTE no dispara ningun RAISE de fn_mover_inventario mas alla del
        # chequeo de cantidad >= 0 (ya validado en el schema), pero SALIDA/RESERVA si lo hacen
        # y comparten la misma funcion.
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(error))

    return AjusteOut(
        movimiento_id=movimiento["id"],
        sucursal_id=body.sucursal_id,
        variante_id=body.variante_id,
        saldo_anterior=movimiento["saldo_anterior"],
        saldo_nuevo=movimiento["saldo_nuevo"],
        motivo=movimiento["motivo"],
        fecha=movimiento["fecha"],
    )
