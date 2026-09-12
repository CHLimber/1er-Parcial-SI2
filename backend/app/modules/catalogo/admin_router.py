"""CU10 - Gestionar Catalogo.

Contracara administrativa de catalogo/router.py (que es la vitrina publica). Aca se ven tambien
las prendas inactivas y las variantes sin stock, porque el encargado de catalogo necesita
verlas para reactivarlas.

Regla del modelo (ver CLAUDE.md): `producto` es la prenda descriptiva y `producto_variante`
(producto x talla x color) es la unidad fisica. El stock NUNCA se toca desde aca: entra por
recepcion (CU09) o por ajuste, siempre via fn_mover_inventario.
"""

import re
import unicodedata
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.auditoria import registrar_auditoria
from app.core.db import get_connection
from app.core.deps import requiere_permiso
from app.modules.catalogo.admin_schemas import (
    CategoriaAdminOut,
    CategoriaEstadoIn,
    CategoriaIn,
    ColeccionOut,
    ColorOut,
    EstadoIn,
    ImagenIn,
    ImagenOut,
    MarcaAdminOut,
    MarcaIn,
    OpcionOut,
    ProductoAdminDetalleOut,
    ProductoAdminOut,
    ProductoIn,
    ReferenciasOut,
    TallaOut,
    TemporadaAdminOut,
    VarianteAdminOut,
    VarianteIn,
)

router = APIRouter(prefix="/admin/catalogo", tags=["catalogo-admin"])

puede_ver = requiere_permiso("catalogo.ver", "catalogo.gestionar")
puede_gestionar = requiere_permiso("catalogo.gestionar")

GENEROS = ["HOMBRE", "MUJER", "UNISEX", "NINO", "NINA"]
USOS_IMAGEN = {"CATALOGO", "AR_OVERLAY", "AR_MODELO"}
FORMATOS_IMAGEN = {"JPG", "PNG", "GLB", "USDZ"}


def _slugificar(texto: str) -> str:
    sin_tildes = unicodedata.normalize("NFKD", texto).encode("ascii", "ignore").decode("ascii")
    limpio = re.sub(r"[^a-z0-9]+", "-", sin_tildes.lower()).strip("-")
    return limpio or "prenda"


async def _slug_unico(
    conn: asyncpg.Connection, tabla: str, nombre: str, excluir_id: UUID | None = None
) -> str:
    """El slug es UNIQUE en producto y en categoria; si dos prendas se llaman igual se
    desempata con un sufijo numerico."""
    base = _slugificar(nombre)
    candidato = base
    intento = 2
    while True:
        existe = await conn.fetchval(
            f"SELECT 1 FROM {tabla} WHERE slug = $1 AND ($2::uuid IS NULL OR id <> $2)",
            candidato,
            excluir_id,
        )
        if not existe:
            return candidato
        candidato = f"{base}-{intento}"
        intento += 1


SELECT_PRODUCTO = """
SELECT p.id, p.codigo, p.nombre, p.slug, p.descripcion,
       p.categoria_id, c.nombre AS categoria,
       p.marca_id, m.nombre AS marca,
       p.proveedor_id, pr.nombre AS proveedor,
       p.temporada_id, t.nombre AS temporada,
       p.coleccion_id, col.nombre AS coleccion,
       p.material, p.genero, p.precio_base, p.destacado, p.activo,
       (SELECT COUNT(*) FROM producto_variante pv WHERE pv.producto_id = p.id AND pv.activa)
           AS variantes_activas,
       COALESCE((
           SELECT SUM(i.cantidad_fisica)
             FROM producto_variante pv
             JOIN inventario i ON i.variante_id = pv.id
            WHERE pv.producto_id = p.id
       ), 0) AS stock_total
FROM producto p
JOIN categoria c       ON c.id = p.categoria_id
LEFT JOIN marca m      ON m.id = p.marca_id
LEFT JOIN proveedor pr ON pr.id = p.proveedor_id
LEFT JOIN temporada t  ON t.id = p.temporada_id
LEFT JOIN coleccion col ON col.id = p.coleccion_id
"""


async def _obtener_producto(conn: asyncpg.Connection, producto_id: UUID) -> ProductoAdminOut:
    fila = await conn.fetchrow(SELECT_PRODUCTO + "WHERE p.id = $1", producto_id)
    if fila is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Prenda no encontrada")
    return ProductoAdminOut(**dict(fila))


async def _variantes(conn: asyncpg.Connection, producto_id: UUID) -> list[VarianteAdminOut]:
    filas = await conn.fetch(
        """
        SELECT pv.id, pv.sku, pv.codigo_barras, pv.talla_id, t.codigo AS talla,
               pv.color_id, c.nombre AS color, c.codigo_hex,
               pv.precio, pv.precio_oferta, pv.activa,
               COALESCE(inv.fisico, 0)     AS stock_fisico,
               COALESCE(inv.disponible, 0) AS stock_disponible
        FROM producto_variante pv
        JOIN talla t ON t.id = pv.talla_id
        JOIN color c ON c.id = pv.color_id
        LEFT JOIN LATERAL (
            SELECT SUM(i.cantidad_fisica) AS fisico, SUM(i.disponible) AS disponible
            FROM inventario i WHERE i.variante_id = pv.id
        ) inv ON true
        WHERE pv.producto_id = $1
        ORDER BY t.orden, c.nombre
        """,
        producto_id,
    )
    return [VarianteAdminOut(**dict(fila)) for fila in filas]


async def _imagenes(conn: asyncpg.Connection, producto_id: UUID) -> list[ImagenOut]:
    filas = await conn.fetch(
        """
        SELECT id, url, uso, formato, color_id, es_principal, orden
        FROM producto_imagen
        WHERE producto_id = $1
        ORDER BY es_principal DESC, orden, id
        """,
        producto_id,
    )
    return [ImagenOut(**dict(fila)) for fila in filas]


def _validar_genero(genero: str | None) -> None:
    if genero is not None and genero not in GENEROS:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Genero invalido. Valores posibles: {', '.join(GENEROS)}",
        )


# ---------------------------------------------------------------------
#  REFERENCIAS PARA LOS FORMULARIOS
# ---------------------------------------------------------------------


@router.get("/referencias", response_model=ReferenciasOut)
async def obtener_referencias(
    conn: asyncpg.Connection = Depends(get_connection),
    _staff: dict = Depends(puede_ver),
) -> ReferenciasOut:
    categorias = await conn.fetch(SELECT_CATEGORIA_ADMIN + "ORDER BY c.orden, c.nombre")
    marcas = await conn.fetch("SELECT id, nombre, logo_url FROM marca ORDER BY nombre")
    proveedores = await conn.fetch("SELECT id, nombre FROM proveedor WHERE activo ORDER BY nombre")
    temporadas = await conn.fetch(
        "SELECT id, nombre, tipo, fecha_inicio, fecha_fin FROM temporada ORDER BY fecha_inicio DESC"
    )
    colecciones = await conn.fetch(
        "SELECT id, nombre, temporada_id FROM coleccion WHERE activa ORDER BY nombre"
    )
    tallas = await conn.fetch("SELECT id, codigo, tipo FROM talla ORDER BY tipo, orden")
    colores = await conn.fetch("SELECT id, nombre, codigo_hex FROM color ORDER BY nombre")

    return ReferenciasOut(
        categorias=[CategoriaAdminOut(**dict(f)) for f in categorias],
        marcas=[MarcaAdminOut(**dict(f)) for f in marcas],
        proveedores=[OpcionOut(**dict(f)) for f in proveedores],
        temporadas=[TemporadaAdminOut(**dict(f)) for f in temporadas],
        colecciones=[ColeccionOut(**dict(f)) for f in colecciones],
        tallas=[TallaOut(**dict(f)) for f in tallas],
        colores=[ColorOut(**dict(f)) for f in colores],
        generos=GENEROS,
    )


# ---------------------------------------------------------------------
#  PRENDAS
# ---------------------------------------------------------------------


@router.get("/productos", response_model=list[ProductoAdminOut])
async def listar_productos_admin(
    q: str | None = Query(default=None, description="Busca por nombre o codigo"),
    categoria_id: UUID | None = Query(default=None),
    activo: bool | None = Query(default=None),
    conn: asyncpg.Connection = Depends(get_connection),
    _staff: dict = Depends(puede_ver),
) -> list[ProductoAdminOut]:
    filas = await conn.fetch(
        SELECT_PRODUCTO
        + """
        WHERE ($1::text IS NULL OR p.nombre ILIKE '%' || $1 || '%' OR p.codigo ILIKE '%' || $1 || '%')
          AND ($2::uuid IS NULL OR p.categoria_id = $2)
          AND ($3::boolean IS NULL OR p.activo = $3)
        ORDER BY p.activo DESC, p.creado_en DESC
        """,
        q,
        categoria_id,
        activo,
    )
    return [ProductoAdminOut(**dict(fila)) for fila in filas]


@router.get("/productos/{producto_id}", response_model=ProductoAdminDetalleOut)
async def obtener_producto_admin(
    producto_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    _staff: dict = Depends(puede_ver),
) -> ProductoAdminDetalleOut:
    producto = await _obtener_producto(conn, producto_id)
    return ProductoAdminDetalleOut(
        **producto.model_dump(),
        variantes=await _variantes(conn, producto_id),
        imagenes=await _imagenes(conn, producto_id),
    )


@router.post("/productos", response_model=ProductoAdminDetalleOut, status_code=status.HTTP_201_CREATED)
async def crear_producto(
    body: ProductoIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_gestionar),
) -> ProductoAdminDetalleOut:
    _validar_genero(body.genero)
    try:
        async with conn.transaction():
            slug = await _slug_unico(conn, "producto", body.nombre)
            nuevo_id = await conn.fetchval(
                """
                INSERT INTO producto (categoria_id, marca_id, proveedor_id, temporada_id, coleccion_id,
                                      codigo, nombre, slug, descripcion, material, genero,
                                      precio_base, destacado)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11::genero_prenda, $12, $13)
                RETURNING id
                """,
                body.categoria_id,
                body.marca_id,
                body.proveedor_id,
                body.temporada_id,
                body.coleccion_id,
                body.codigo.upper(),
                body.nombre,
                slug,
                body.descripcion,
                body.material,
                body.genero,
                body.precio_base,
                body.destacado,
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="producto",
                entidad_id=nuevo_id,
                accion="CREAR",
                datos_despues=body.model_dump(mode="json"),
            )
    except asyncpg.UniqueViolationError:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Ese codigo de prenda ya existe")
    except asyncpg.ForeignKeyViolationError:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Categoria, marca, proveedor, temporada o coleccion inexistente",
        )

    return await obtener_producto_admin(nuevo_id, conn, staff)


@router.put("/productos/{producto_id}", response_model=ProductoAdminDetalleOut)
async def actualizar_producto(
    producto_id: UUID,
    body: ProductoIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_gestionar),
) -> ProductoAdminDetalleOut:
    _validar_genero(body.genero)
    antes = await _obtener_producto(conn, producto_id)

    try:
        async with conn.transaction():
            slug = antes.slug
            if body.nombre != antes.nombre:
                slug = await _slug_unico(conn, "producto", body.nombre, excluir_id=producto_id)
            await conn.execute(
                """
                UPDATE producto
                   SET categoria_id = $2, marca_id = $3, proveedor_id = $4, temporada_id = $5,
                       coleccion_id = $6, codigo = $7, nombre = $8, slug = $9, descripcion = $10,
                       material = $11, genero = $12::genero_prenda, precio_base = $13, destacado = $14
                 WHERE id = $1
                """,
                producto_id,
                body.categoria_id,
                body.marca_id,
                body.proveedor_id,
                body.temporada_id,
                body.coleccion_id,
                body.codigo.upper(),
                body.nombre,
                slug,
                body.descripcion,
                body.material,
                body.genero,
                body.precio_base,
                body.destacado,
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="producto",
                entidad_id=producto_id,
                accion="ACTUALIZAR",
                datos_antes=antes.model_dump(mode="json"),
                datos_despues=body.model_dump(mode="json"),
            )
    except asyncpg.UniqueViolationError:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Ese codigo de prenda ya existe")
    except asyncpg.ForeignKeyViolationError:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Categoria, marca, proveedor, temporada o coleccion inexistente",
        )

    return await obtener_producto_admin(producto_id, conn, staff)


@router.patch("/productos/{producto_id}/estado", response_model=ProductoAdminDetalleOut)
async def cambiar_estado_producto(
    producto_id: UUID,
    body: EstadoIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_gestionar),
) -> ProductoAdminDetalleOut:
    """Baja logica: la prenda desaparece de la vitrina pero sigue existiendo en el historial de
    ventas y en el kardex. Se bloquea si hay stock comprometido por reservas en curso."""
    antes = await _obtener_producto(conn, producto_id)

    if not body.activo:
        reservado = await conn.fetchval(
            """
            SELECT COALESCE(SUM(i.cantidad_reservada), 0)
            FROM producto_variante pv
            JOIN inventario i ON i.variante_id = pv.id
            WHERE pv.producto_id = $1
            """,
            producto_id,
        )
        if reservado:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"No se puede desactivar: hay {reservado} unidad(es) reservada(s)",
            )

    async with conn.transaction():
        await conn.execute("UPDATE producto SET activo = $2 WHERE id = $1", producto_id, body.activo)
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="producto",
            entidad_id=producto_id,
            accion="ACTUALIZAR" if body.activo else "ELIMINAR",
            datos_antes={"activo": antes.activo},
            datos_despues={"activo": body.activo},
        )
    return await obtener_producto_admin(producto_id, conn, staff)


# ---------------------------------------------------------------------
#  VARIANTES (talla x color)
# ---------------------------------------------------------------------


@router.post(
    "/productos/{producto_id}/variantes",
    response_model=VarianteAdminOut,
    status_code=status.HTTP_201_CREATED,
)
async def crear_variante(
    producto_id: UUID,
    body: VarianteIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_gestionar),
) -> VarianteAdminOut:
    await _obtener_producto(conn, producto_id)
    _validar_precios(body)

    try:
        async with conn.transaction():
            nueva_id = await conn.fetchval(
                """
                INSERT INTO producto_variante (producto_id, talla_id, color_id, sku, codigo_barras,
                                               precio, precio_oferta)
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                RETURNING id
                """,
                producto_id,
                body.talla_id,
                body.color_id,
                body.sku.upper(),
                body.codigo_barras,
                body.precio,
                body.precio_oferta,
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="producto_variante",
                entidad_id=nueva_id,
                accion="CREAR",
                datos_despues={"producto_id": str(producto_id), **body.model_dump(mode="json")},
            )
    except asyncpg.UniqueViolationError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Ya existe esa combinacion de talla y color, o el SKU esta repetido",
        )
    except asyncpg.ForeignKeyViolationError:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Talla o color inexistente"
        )

    return await _obtener_variante(conn, nueva_id)


@router.put("/variantes/{variante_id}", response_model=VarianteAdminOut)
async def actualizar_variante(
    variante_id: UUID,
    body: VarianteIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_gestionar),
) -> VarianteAdminOut:
    antes = await _obtener_variante(conn, variante_id)
    _validar_precios(body)

    try:
        async with conn.transaction():
            await conn.execute(
                """
                UPDATE producto_variante
                   SET talla_id = $2, color_id = $3, sku = $4, codigo_barras = $5,
                       precio = $6, precio_oferta = $7
                 WHERE id = $1
                """,
                variante_id,
                body.talla_id,
                body.color_id,
                body.sku.upper(),
                body.codigo_barras,
                body.precio,
                body.precio_oferta,
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="producto_variante",
                entidad_id=variante_id,
                accion="ACTUALIZAR",
                datos_antes=antes.model_dump(mode="json"),
                datos_despues=body.model_dump(mode="json"),
            )
    except asyncpg.UniqueViolationError:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Ya existe esa combinacion de talla y color, o el SKU esta repetido",
        )
    except asyncpg.ForeignKeyViolationError:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Talla o color inexistente"
        )

    return await _obtener_variante(conn, variante_id)


@router.patch("/variantes/{variante_id}/estado", response_model=VarianteAdminOut)
async def cambiar_estado_variante(
    variante_id: UUID,
    body: EstadoIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_gestionar),
) -> VarianteAdminOut:
    antes = await _obtener_variante(conn, variante_id)

    if not body.activo:
        reservado = await conn.fetchval(
            "SELECT COALESCE(SUM(cantidad_reservada), 0) FROM inventario WHERE variante_id = $1",
            variante_id,
        )
        if reservado:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"No se puede desactivar: hay {reservado} unidad(es) reservada(s)",
            )

    async with conn.transaction():
        await conn.execute(
            "UPDATE producto_variante SET activa = $2 WHERE id = $1", variante_id, body.activo
        )
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="producto_variante",
            entidad_id=variante_id,
            accion="ACTUALIZAR" if body.activo else "ELIMINAR",
            datos_antes={"activa": antes.activa},
            datos_despues={"activa": body.activo},
        )
    return await _obtener_variante(conn, variante_id)


# ---------------------------------------------------------------------
#  IMAGENES
# ---------------------------------------------------------------------


@router.post(
    "/productos/{producto_id}/imagenes", response_model=ImagenOut, status_code=status.HTTP_201_CREATED
)
async def agregar_imagen(
    producto_id: UUID,
    body: ImagenIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_gestionar),
) -> ImagenOut:
    await _obtener_producto(conn, producto_id)
    if body.uso not in USOS_IMAGEN:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Uso de imagen invalido")
    if body.formato is not None and body.formato not in FORMATOS_IMAGEN:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Formato invalido")

    async with conn.transaction():
        if body.es_principal:
            await conn.execute(
                "UPDATE producto_imagen SET es_principal = FALSE WHERE producto_id = $1 AND uso = $2::uso_imagen",
                producto_id,
                body.uso,
            )
        fila = await conn.fetchrow(
            """
            INSERT INTO producto_imagen (producto_id, color_id, uso, url, formato, es_principal, orden)
            VALUES ($1, $2, $3::uso_imagen, $4, $5::formato_imagen, $6, $7)
            RETURNING id, url, uso, formato, color_id, es_principal, orden
            """,
            producto_id,
            body.color_id,
            body.uso,
            body.url,
            body.formato,
            body.es_principal,
            body.orden,
        )
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="producto_imagen",
            entidad_id=fila["id"],
            accion="CREAR",
            datos_despues={"producto_id": str(producto_id), **body.model_dump(mode="json")},
        )
    return ImagenOut(**dict(fila))


@router.delete("/imagenes/{imagen_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar_imagen(
    imagen_id: UUID,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_gestionar),
) -> None:
    fila = await conn.fetchrow(
        "SELECT id, producto_id, url, uso FROM producto_imagen WHERE id = $1", imagen_id
    )
    if fila is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Imagen no encontrada")

    async with conn.transaction():
        await conn.execute("DELETE FROM producto_imagen WHERE id = $1", imagen_id)
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="producto_imagen",
            entidad_id=imagen_id,
            accion="ELIMINAR",
            datos_antes={"producto_id": str(fila["producto_id"]), "url": fila["url"]},
        )


# ---------------------------------------------------------------------
#  CATEGORIAS Y MARCAS
# ---------------------------------------------------------------------

SELECT_CATEGORIA_ADMIN = """
SELECT c.id, c.nombre, c.slug, c.categoria_padre_id, padre.nombre AS categoria_padre,
       c.imagen_url, c.orden, c.activa,
       (SELECT COUNT(*) FROM producto p WHERE p.categoria_id = c.id) AS productos
FROM categoria c
LEFT JOIN categoria padre ON padre.id = c.categoria_padre_id
"""


async def _obtener_categoria(conn: asyncpg.Connection, categoria_id: UUID) -> CategoriaAdminOut:
    fila = await conn.fetchrow(SELECT_CATEGORIA_ADMIN + "WHERE c.id = $1", categoria_id)
    if fila is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Categoria no encontrada")
    return CategoriaAdminOut(**dict(fila))


@router.get("/categorias", response_model=list[CategoriaAdminOut])
async def listar_categorias(
    conn: asyncpg.Connection = Depends(get_connection),
    _staff: dict = Depends(puede_ver),
) -> list[CategoriaAdminOut]:
    filas = await conn.fetch(SELECT_CATEGORIA_ADMIN + "ORDER BY c.orden, c.nombre")
    return [CategoriaAdminOut(**dict(fila)) for fila in filas]


@router.post("/categorias", response_model=CategoriaAdminOut, status_code=status.HTTP_201_CREATED)
async def crear_categoria(
    body: CategoriaIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_gestionar),
) -> CategoriaAdminOut:
    async with conn.transaction():
        slug = await _slug_unico(conn, "categoria", body.nombre)
        try:
            nueva_id = await conn.fetchval(
                """
                INSERT INTO categoria (categoria_padre_id, nombre, slug, imagen_url, orden)
                VALUES ($1, $2, $3, $4, $5)
                RETURNING id
                """,
                body.categoria_padre_id,
                body.nombre,
                slug,
                body.imagen_url,
                body.orden,
            )
        except asyncpg.ForeignKeyViolationError:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="La categoria padre no existe"
            )
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="categoria",
            entidad_id=nueva_id,
            accion="CREAR",
            datos_despues=body.model_dump(mode="json"),
        )
    return await _obtener_categoria(conn, nueva_id)


@router.put("/categorias/{categoria_id}", response_model=CategoriaAdminOut)
async def actualizar_categoria(
    categoria_id: UUID,
    body: CategoriaIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_gestionar),
) -> CategoriaAdminOut:
    antes = await _obtener_categoria(conn, categoria_id)
    if body.categoria_padre_id == categoria_id:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Una categoria no puede ser su propia padre",
        )

    async with conn.transaction():
        slug = antes.slug
        if body.nombre != antes.nombre:
            slug = await _slug_unico(conn, "categoria", body.nombre, excluir_id=categoria_id)
        try:
            await conn.execute(
                """
                UPDATE categoria
                   SET categoria_padre_id = $2, nombre = $3, slug = $4, imagen_url = $5, orden = $6
                 WHERE id = $1
                """,
                categoria_id,
                body.categoria_padre_id,
                body.nombre,
                slug,
                body.imagen_url,
                body.orden,
            )
        except asyncpg.ForeignKeyViolationError:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="La categoria padre no existe"
            )
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="categoria",
            entidad_id=categoria_id,
            accion="ACTUALIZAR",
            datos_antes=antes.model_dump(mode="json"),
            datos_despues=body.model_dump(mode="json"),
        )
    return await _obtener_categoria(conn, categoria_id)


@router.patch("/categorias/{categoria_id}/estado", response_model=CategoriaAdminOut)
async def cambiar_estado_categoria(
    categoria_id: UUID,
    body: CategoriaEstadoIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_gestionar),
) -> CategoriaAdminOut:
    antes = await _obtener_categoria(conn, categoria_id)

    if not body.activa:
        activos = await conn.fetchval(
            "SELECT COUNT(*) FROM producto WHERE categoria_id = $1 AND activo", categoria_id
        )
        if activos:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"No se puede desactivar: tiene {activos} prenda(s) activa(s)",
            )

    async with conn.transaction():
        await conn.execute("UPDATE categoria SET activa = $2 WHERE id = $1", categoria_id, body.activa)
        await registrar_auditoria(
            conn,
            usuario_id=staff["id"],
            entidad="categoria",
            entidad_id=categoria_id,
            accion="ACTUALIZAR" if body.activa else "ELIMINAR",
            datos_antes={"activa": antes.activa},
            datos_despues={"activa": body.activa},
        )
    return await _obtener_categoria(conn, categoria_id)


@router.post("/marcas", response_model=MarcaAdminOut, status_code=status.HTTP_201_CREATED)
async def crear_marca(
    body: MarcaIn,
    conn: asyncpg.Connection = Depends(get_connection),
    staff: dict = Depends(puede_gestionar),
) -> MarcaAdminOut:
    try:
        async with conn.transaction():
            fila = await conn.fetchrow(
                "INSERT INTO marca (nombre, logo_url) VALUES ($1, $2) RETURNING id, nombre, logo_url",
                body.nombre,
                body.logo_url,
            )
            await registrar_auditoria(
                conn,
                usuario_id=staff["id"],
                entidad="marca",
                entidad_id=fila["id"],
                accion="CREAR",
                datos_despues=body.model_dump(mode="json"),
            )
    except asyncpg.UniqueViolationError:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Ya existe una marca con ese nombre")
    return MarcaAdminOut(**dict(fila))


# ---------------------------------------------------------------------
#  AUXILIARES
# ---------------------------------------------------------------------


async def _obtener_variante(conn: asyncpg.Connection, variante_id: UUID) -> VarianteAdminOut:
    fila = await conn.fetchrow(
        """
        SELECT pv.id, pv.sku, pv.codigo_barras, pv.talla_id, t.codigo AS talla,
               pv.color_id, c.nombre AS color, c.codigo_hex,
               pv.precio, pv.precio_oferta, pv.activa,
               COALESCE(inv.fisico, 0)     AS stock_fisico,
               COALESCE(inv.disponible, 0) AS stock_disponible
        FROM producto_variante pv
        JOIN talla t ON t.id = pv.talla_id
        JOIN color c ON c.id = pv.color_id
        LEFT JOIN LATERAL (
            SELECT SUM(i.cantidad_fisica) AS fisico, SUM(i.disponible) AS disponible
            FROM inventario i WHERE i.variante_id = pv.id
        ) inv ON true
        WHERE pv.id = $1
        """,
        variante_id,
    )
    if fila is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Variante no encontrada")
    return VarianteAdminOut(**dict(fila))


def _validar_precios(body: VarianteIn) -> None:
    if body.precio_oferta is not None and body.precio is not None and body.precio_oferta > body.precio:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="El precio de oferta no puede superar al precio de lista",
        )
