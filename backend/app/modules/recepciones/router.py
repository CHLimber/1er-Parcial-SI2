"""CU09 - Registrar Recepcion de Mercaderia.

La recepcion nace en BORRADOR y se puede editar libremente; recien al pasarla a CONFIRMADA el
trigger tg_confirmar_recepcion (db/02_logica.sql) llama a fn_mover_inventario con tipo ENTRADA
por cada linea. Este modulo nunca escribe cantidad_fisica: se limita a mover el estado y deja
que la base haga entrar el stock y escriba el kardex.
"""

from uuid import UUID, uuid4

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.auditoria import registrar_auditoria
from app.core.db import get_connection
from app.core.deps import requiere_permiso
from app.modules.recepciones.schemas import (
    DetalleIn,
    DetalleOut,
    MovimientoOut,
    RecepcionDetalleOut,
    RecepcionIn,
    RecepcionOut,
    VarianteBuscadaOut,
)

router = APIRouter(prefix="/recepciones", tags=["recepciones"])

puede_ver = requiere_permiso("recepciones.ver", "recepciones.registrar", "recepciones.confirmar")
puede_registrar = requiere_permiso("recepciones.registrar")
puede_confirmar = requiere_permiso("recepciones.confirmar")

SELECT_RECEPCION = """
SELECT r.id, r.numero, r.fecha, r.estado, r.total,
       r.sucursal_id, s.nombre AS sucursal,
       r.proveedor_id, p.nombre AS proveedor,
       r.coleccion_id, col.nombre AS coleccion,
       r.usuario_id, (u.nombre || ' ' || u.apellido) AS registrado_por,
       (SELECT COUNT(*)                 FROM recepcion_detalle d WHERE d.recepcion_id = r.id) AS lineas,
       (SELECT COALESCE(SUM(d.cantidad), 0) FROM recepcion_detalle d WHERE d.recepcion_id = r.id) AS unidades
FROM recepcion r
JOIN sucursal s        ON s.id = r.sucursal_id
JOIN proveedor p       ON p.id = r.proveedor_id
LEFT JOIN coleccion col ON col.id = r.coleccion_id
LEFT JOIN usuario u     ON u.id = r.usuario_id
"""


def _sucursal_visible(staff: dict) -> UUID | None:
    """Un ADMIN (el que puede gestionar sucursales) ve todas; el resto solo la suya."""
    if "sucursales.gestionar" in staff["permisos"]:
        return None
    if staff["sucursal_id"] is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Tu usuario no esta asignado a ninguna sucursal",
        )
    return staff["sucursal_id"]


async def _obtener(conn: asyncpg.Connection, recepcion_id: UUID, staff: dict) -> RecepcionOut:
    fila = await conn.fetchrow(SELECT_RECEPCION + "WHERE r.id = $1", recepcion_id)
    if fila is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Recepcion no encontrada")

    limite = _sucursal_visible(staff)
    if limite is not None and fila["sucursal_id"] != limite:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="Esa recepcion es de otra sucursal"
        )
    return RecepcionOut(**dict(fila))


async def _detalle(conn: asyncpg.Connection, recepcion_id: UUID) -> list[DetalleOut]:
    filas = await conn.fetch(
        """
        SELECT d.id, d.variante_id, pv.sku, pr.nombre AS producto,
               t.codigo AS talla, c.nombre AS color,
               d.cantidad, d.costo_unitario,
               (d.cantidad * d.costo_unitario) AS subtotal
        FROM recepcion_detalle d
        JOIN producto_variante pv ON pv.id = d.variante_id
        JOIN producto pr          ON pr.id = pv.producto_id
        JOIN talla t              ON t.id = pv.talla_id
        JOIN color c              ON c.id = pv.color_id
        WHERE d.recepcion_id = $1
        ORDER BY pr.nombre, t.orden, c.nombre
        """,
        recepcion_id,
    )
    return [DetalleOut(**dict(fila)) for fila in filas]


async def _con_detalle(
    conn: asyncpg.Connection, recepcion_id: UUID, staff: dict
) -> RecepcionDetalleOut:
    cabecera = await _obtener(conn, recepcion_id, staff)
    return RecepcionDetalleOut(**cabecera.model_dump(), detalle=await _detalle(conn, recepcion_id))


async def _exigir_borrador(conn: asyncpg.Connection, recepcion_id: UUID, staff: dict) -> RecepcionOut:
    recepcion = await _obtener(conn, recepcion_id, staff)
    if recepcion.estado != "BORRADOR":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"La recepcion esta {recepcion.estado.lower()} y ya no se puede modificar",
        )
    return recepcion


async def _recalcular_total(conn: asyncpg.Connection, recepcion_id: UUID) -> None:
    await conn.execute(
        """
        UPDATE recepcion
           SET total = COALESCE(
                   (SELECT SUM(cantidad * costo_unitario) FROM recepcion_detalle WHERE recepcion_id = $1),
                   0)
         WHERE id = $1
        """,
        recepcion_id,
    )


# ---------------------------------------------------------------------
#  CONSULTA
# ---------------------------------------------------------------------


@router.get("", response_model=list[RecepcionOut])
async def listar_recepciones(
    estado: str | None = Query(default=None, pattern="^(BORRADOR|CONFIRMADA|ANULADA)$"),
    proveedor_id: UUID | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[RecepcionOut]:
    limite = _sucursal_visible(staff)
    filas = await conn.fetch(
        SELECT_RECEPCION
        + """
        WHERE ($1::uuid IS NULL OR r.sucursal_id = $1)
          AND ($2::text IS NULL OR r.estado::text = $2)
          AND ($3::uuid IS NULL OR r.proveedor_id = $3)
        ORDER BY r.fecha DESC, r.numero DESC
        """,
        limite,
        estado,
        proveedor_id,
    )
    return [RecepcionOut(**dict(fila)) for fila in filas]


@router.get("/variantes", response_model=list[VarianteBuscadaOut])
async def buscar_variantes(
    q: str = Query(min_length=1, description="SKU, codigo de barras o nombre de la prenda"),
    sucursal_id: UUID | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[VarianteBuscadaOut]:
    """Buscador para cargar lineas: muestra el stock que la variante tiene hoy en la sucursal
    que va a recibir, para que el encargado sepa contra que esta sumando."""
    limite = _sucursal_visible(staff)
    destino = sucursal_id or limite
    if destino is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Indica la sucursal para consultar el stock actual",
        )

    filas = await conn.fetch(
        """
        SELECT pv.id, pv.sku, pr.nombre AS producto, t.codigo AS talla,
               c.nombre AS color, c.codigo_hex, pr.precio_base,
               COALESCE(i.cantidad_fisica, 0) AS stock_sucursal
        FROM producto_variante pv
        JOIN producto pr ON pr.id = pv.producto_id
        JOIN talla t     ON t.id = pv.talla_id
        JOIN color c     ON c.id = pv.color_id
        LEFT JOIN inventario i ON i.variante_id = pv.id AND i.sucursal_id = $2
        WHERE pv.activa AND pr.activo
          AND (pv.sku ILIKE '%' || $1 || '%'
               OR pv.codigo_barras ILIKE '%' || $1 || '%'
               OR pr.nombre ILIKE '%' || $1 || '%')
        ORDER BY pr.nombre, t.orden, c.nombre
        LIMIT 25
        """,
        q,
        destino,
    )
    return [VarianteBuscadaOut(**dict(fila)) for fila in filas]


@router.get("/{recepcion_id}", response_model=RecepcionDetalleOut)
async def obtener_recepcion(
    recepcion_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> RecepcionDetalleOut:
    return await _con_detalle(conn, recepcion_id, staff)


@router.get("/{recepcion_id}/movimientos", response_model=list[MovimientoOut])
async def movimientos_de_recepcion(
    recepcion_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_ver),
) -> list[MovimientoOut]:
    await _obtener(conn, recepcion_id, staff)
    filas = await conn.fetch(
        """
        SELECT m.variante_id, pv.sku, pr.nombre AS producto, m.cantidad,
               m.saldo_anterior, m.saldo_nuevo, m.fecha
        FROM movimiento_inventario m
        JOIN producto_variante pv ON pv.id = m.variante_id
        JOIN producto pr          ON pr.id = pv.producto_id
        WHERE m.documento_tipo = 'RECEPCION' AND m.documento_id = $1
        ORDER BY m.fecha, m.id
        """,
        recepcion_id,
    )
    return [MovimientoOut(**dict(fila)) for fila in filas]


# ---------------------------------------------------------------------
#  CARGA DEL BORRADOR
# ---------------------------------------------------------------------


@router.post("", response_model=RecepcionDetalleOut, status_code=status.HTTP_201_CREATED)
async def crear_recepcion(
    body: RecepcionIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_registrar),
) -> RecepcionDetalleOut:
    limite = _sucursal_visible(staff)
    sucursal_id = body.sucursal_id or limite or staff["sucursal_id"]
    if sucursal_id is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Indica la sucursal que recibe"
        )
    if limite is not None and sucursal_id != limite:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="Solo podes registrar en tu sucursal"
        )

    proveedor = await conn.fetchrow(
        "SELECT activo FROM proveedor WHERE id = $1", body.proveedor_id
    )
    if proveedor is None:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="El proveedor no existe")
    if not proveedor["activo"]:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Ese proveedor esta dado de baja",
        )

    numero = (body.numero or f"R-{uuid4().hex[:10].upper()}").upper()
    try:
        async with conn.transaction():
            nueva_id = await conn.fetchval(
                """
                INSERT INTO recepcion (sucursal_id, proveedor_id, coleccion_id, numero, fecha,
                                       total, estado, usuario_id)
                VALUES ($1, $2, $3, $4, COALESCE($5, CURRENT_DATE), 0, 'BORRADOR', $6)
                RETURNING id
                """,
                sucursal_id,
                body.proveedor_id,
                body.coleccion_id,
                numero,
                body.fecha,
                staff["id"],
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="recepcion",
                entidad_id=nueva_id,
                accion="CREAR",
                datos_despues={"numero": numero, "sucursal_id": str(sucursal_id)},
            )
    except asyncpg.UniqueViolationError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Ya existe una recepcion con ese numero"
        )
    except asyncpg.ForeignKeyViolationError:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Sucursal o coleccion inexistente"
        )

    return await _con_detalle(conn, nueva_id, staff)


@router.post("/{recepcion_id}/detalle", response_model=RecepcionDetalleOut)
async def agregar_linea(
    recepcion_id: UUID,
    body: DetalleIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_registrar),
) -> RecepcionDetalleOut:
    """Si la variante ya esta en el borrador se suma la cantidad en lugar de duplicar la linea:
    es lo que espera quien va contando bultos."""
    await _exigir_borrador(conn, recepcion_id, staff)

    variante = await conn.fetchval(
        "SELECT 1 FROM producto_variante WHERE id = $1 AND activa", body.variante_id
    )
    if not variante:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="La variante no existe o esta inactiva",
        )

    async with conn.transaction():
        existente = await conn.fetchrow(
            "SELECT id, cantidad FROM recepcion_detalle WHERE recepcion_id = $1 AND variante_id = $2",
            recepcion_id,
            body.variante_id,
        )
        if existente is None:
            await conn.execute(
                """
                INSERT INTO recepcion_detalle (recepcion_id, variante_id, cantidad, costo_unitario)
                VALUES ($1, $2, $3, $4)
                """,
                recepcion_id,
                body.variante_id,
                body.cantidad,
                body.costo_unitario,
            )
        else:
            await conn.execute(
                "UPDATE recepcion_detalle SET cantidad = cantidad + $2, costo_unitario = $3 WHERE id = $1",
                existente["id"],
                body.cantidad,
                body.costo_unitario,
            )
        await _recalcular_total(conn, recepcion_id)

    return await _con_detalle(conn, recepcion_id, staff)


@router.put("/{recepcion_id}/detalle/{detalle_id}", response_model=RecepcionDetalleOut)
async def editar_linea(
    recepcion_id: UUID,
    detalle_id: UUID,
    body: DetalleIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_registrar),
) -> RecepcionDetalleOut:
    await _exigir_borrador(conn, recepcion_id, staff)

    async with conn.transaction():
        actualizadas = await conn.execute(
            """
            UPDATE recepcion_detalle
               SET cantidad = $3, costo_unitario = $4
             WHERE id = $1 AND recepcion_id = $2
            """,
            detalle_id,
            recepcion_id,
            body.cantidad,
            body.costo_unitario,
        )
        if actualizadas.endswith(" 0"):
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Linea no encontrada")
        await _recalcular_total(conn, recepcion_id)

    return await _con_detalle(conn, recepcion_id, staff)


@router.delete("/{recepcion_id}/detalle/{detalle_id}", response_model=RecepcionDetalleOut)
async def quitar_linea(
    recepcion_id: UUID,
    detalle_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_registrar),
) -> RecepcionDetalleOut:
    await _exigir_borrador(conn, recepcion_id, staff)

    async with conn.transaction():
        borradas = await conn.execute(
            "DELETE FROM recepcion_detalle WHERE id = $1 AND recepcion_id = $2", detalle_id, recepcion_id
        )
        if borradas.endswith(" 0"):
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Linea no encontrada")
        await _recalcular_total(conn, recepcion_id)

    return await _con_detalle(conn, recepcion_id, staff)


# ---------------------------------------------------------------------
#  CIERRE
# ---------------------------------------------------------------------


@router.post("/{recepcion_id}/confirmar", response_model=RecepcionDetalleOut)
async def confirmar_recepcion(
    recepcion_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_confirmar),
) -> RecepcionDetalleOut:
    """Punto sin retorno: el UPDATE del estado dispara tg_confirmar_recepcion, que da entrada al
    stock de cada linea y deja el asiento en el kardex. Por eso se valida antes que haya lineas."""
    await _exigir_borrador(conn, recepcion_id, staff)

    lineas = await conn.fetchval(
        "SELECT COUNT(*) FROM recepcion_detalle WHERE recepcion_id = $1", recepcion_id
    )
    if not lineas:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="La recepcion no tiene prendas cargadas",
        )

    try:
        async with conn.transaction():
            await _recalcular_total(conn, recepcion_id)
            # el usuario que confirma queda como responsable del movimiento de kardex
            await conn.execute(
                "UPDATE recepcion SET usuario_id = $2, estado = 'CONFIRMADA' WHERE id = $1",
                recepcion_id,
                staff["id"],
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="recepcion",
                entidad_id=recepcion_id,
                accion="ACTUALIZAR",
                datos_antes={"estado": "BORRADOR"},
                datos_despues={"estado": "CONFIRMADA", "lineas": lineas},
            )
    except asyncpg.RaiseError as error:
        # cualquier excepcion levantada por fn_mover_inventario llega aca
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(error))

    return await _con_detalle(conn, recepcion_id, staff)


@router.post("/{recepcion_id}/anular", response_model=RecepcionDetalleOut)
async def anular_recepcion(
    recepcion_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_confirmar),
) -> RecepcionDetalleOut:
    """Solo se anula un borrador. Una recepcion confirmada ya movio el stock y el kardex es
    append-only: para revertirla hay que registrar un ajuste, no borrar el asiento."""
    recepcion = await _obtener(conn, recepcion_id, staff)
    if recepcion.estado == "CONFIRMADA":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="La recepcion ya ingreso stock: corregila con un ajuste de inventario",
        )
    if recepcion.estado == "ANULADA":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="La recepcion ya esta anulada")

    async with conn.transaction():
        await conn.execute("UPDATE recepcion SET estado = 'ANULADA' WHERE id = $1", recepcion_id)
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="recepcion",
            entidad_id=recepcion_id,
            accion="ELIMINAR",
            datos_antes={"estado": recepcion.estado},
            datos_despues={"estado": "ANULADA"},
        )

    return await _con_detalle(conn, recepcion_id, staff)
