"""CU20 - libreta de direcciones de la clienta.

Era el agujero del pendiente 2.4: la venta ya aceptaba entrega DOMICILIO y venta.direccion_id,
pero no habia forma de dar de alta una direccion, asi que el envio a domicilio era inalcanzable
desde la web y el movil. Todo lo de aca es del CLIENTE (el STAFF no administra direcciones
ajenas), por eso no usa el sistema de permisos de CU13, igual que carrito/ y reservas/.
"""

from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.db import get_connection
from app.core.deps import get_current_usuario
from app.core.ruteo import buscar_direccion, direccion_de_punto, hay_proveedor_externo
from app.modules.direcciones.schemas import (
    BusquedaDireccionOut,
    DireccionIn,
    DireccionOut,
    SugerenciaDireccionOut,
)

router = APIRouter(prefix="/direcciones", tags=["direcciones"])

SELECT_DIRECCION = """
SELECT id, alias, ciudad, direccion, referencia, latitud, longitud, es_principal
FROM direccion
"""


def _exigir_cliente(usuario: dict) -> None:
    if usuario["tipo"] != "CLIENTE":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo un cliente tiene libreta de direcciones",
        )


def _a_salida(fila: asyncpg.Record) -> DireccionOut:
    return DireccionOut(
        id=fila["id"],
        alias=fila["alias"],
        ciudad=fila["ciudad"],
        direccion=fila["direccion"],
        referencia=fila["referencia"],
        latitud=float(fila["latitud"]) if fila["latitud"] is not None else None,
        longitud=float(fila["longitud"]) if fila["longitud"] is not None else None,
        es_principal=fila["es_principal"],
    )


async def _despriorizar_otras(conn: asyncpg.Connection, usuario_id: UUID, excepto: UUID | None) -> None:
    """ux_direccion_principal es un indice unico parcial: solo puede haber una principal por
    clienta, asi que hay que bajar la anterior antes de subir la nueva."""
    await conn.execute(
        """
        UPDATE direccion SET es_principal = FALSE
        WHERE usuario_id = $1 AND es_principal AND ($2::uuid IS NULL OR id <> $2::uuid)
        """,
        usuario_id,
        excepto,
    )


@router.get("", response_model=list[DireccionOut])
async def listar_direcciones(
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> list[DireccionOut]:
    _exigir_cliente(usuario)
    filas = await conn.fetch(
        SELECT_DIRECCION + " WHERE usuario_id = $1 ORDER BY es_principal DESC, alias",
        usuario["id"],
    )
    return [_a_salida(fila) for fila in filas]


@router.post("", response_model=DireccionOut, status_code=status.HTTP_201_CREATED)
async def crear_direccion(
    body: DireccionIn,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> DireccionOut:
    _exigir_cliente(usuario)

    cuantas = await conn.fetchval("SELECT count(*) FROM direccion WHERE usuario_id = $1", usuario["id"])
    # la primera direccion es la principal si o si: asi el checkout siempre tiene a donde mandar
    es_principal = body.es_principal or cuantas == 0

    async with conn.transaction():
        if es_principal:
            await _despriorizar_otras(conn, usuario["id"], None)
        fila = await conn.fetchrow(
            """
            INSERT INTO direccion (usuario_id, alias, ciudad, direccion, referencia,
                                   latitud, longitud, es_principal)
            VALUES ($1, $2, $3::ciudad_bo, $4, $5, $6, $7, $8)
            RETURNING id, alias, ciudad, direccion, referencia, latitud, longitud, es_principal
            """,
            usuario["id"],
            body.alias,
            body.ciudad,
            body.direccion,
            body.referencia,
            body.latitud,
            body.longitud,
            es_principal,
        )
    return _a_salida(fila)


@router.put("/{direccion_id}", response_model=DireccionOut)
async def actualizar_direccion(
    direccion_id: UUID,
    body: DireccionIn,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> DireccionOut:
    _exigir_cliente(usuario)

    actual = await conn.fetchrow(
        "SELECT id, es_principal FROM direccion WHERE id = $1 AND usuario_id = $2",
        direccion_id,
        usuario["id"],
    )
    if actual is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Esa direccion no te pertenece")

    # no se puede dejar a la clienta sin ninguna principal desmarcando la unica que tiene
    es_principal = body.es_principal or actual["es_principal"]

    async with conn.transaction():
        if es_principal:
            await _despriorizar_otras(conn, usuario["id"], direccion_id)
        fila = await conn.fetchrow(
            """
            UPDATE direccion
               SET alias = $3, ciudad = $4::ciudad_bo, direccion = $5, referencia = $6,
                   latitud = $7, longitud = $8, es_principal = $9
             WHERE id = $1 AND usuario_id = $2
            RETURNING id, alias, ciudad, direccion, referencia, latitud, longitud, es_principal
            """,
            direccion_id,
            usuario["id"],
            body.alias,
            body.ciudad,
            body.direccion,
            body.referencia,
            body.latitud,
            body.longitud,
            es_principal,
        )
    return _a_salida(fila)


@router.post("/{direccion_id}/principal", response_model=DireccionOut)
async def marcar_principal(
    direccion_id: UUID,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> DireccionOut:
    _exigir_cliente(usuario)

    async with conn.transaction():
        await _despriorizar_otras(conn, usuario["id"], direccion_id)
        fila = await conn.fetchrow(
            """
            UPDATE direccion SET es_principal = TRUE
             WHERE id = $1 AND usuario_id = $2
            RETURNING id, alias, ciudad, direccion, referencia, latitud, longitud, es_principal
            """,
            direccion_id,
            usuario["id"],
        )
    if fila is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Esa direccion no te pertenece")
    return _a_salida(fila)


@router.delete("/{direccion_id}", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar_direccion(
    direccion_id: UUID,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> None:
    _exigir_cliente(usuario)

    fila = await conn.fetchrow(
        "SELECT id, es_principal FROM direccion WHERE id = $1 AND usuario_id = $2",
        direccion_id,
        usuario["id"],
    )
    if fila is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Esa direccion no te pertenece")

    # venta.direccion_id la referencia: si ya se uso en una compra no se borra, se esconde
    # de la libreta seria mentir sobre el historial, asi que se bloquea el borrado.
    usada = await conn.fetchval("SELECT count(*) FROM venta WHERE direccion_id = $1", direccion_id)
    if usada:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Esa direccion ya tiene compras asociadas, no se puede borrar (podes editarla)",
        )

    async with conn.transaction():
        await conn.execute("DELETE FROM direccion WHERE id = $1", direccion_id)
        if fila["es_principal"]:
            # la libreta no puede quedar sin principal mientras haya alguna direccion
            await conn.execute(
                """
                UPDATE direccion SET es_principal = TRUE
                 WHERE id = (SELECT id FROM direccion WHERE usuario_id = $1 ORDER BY alias LIMIT 1)
                """,
                usuario["id"],
            )


@router.get("/buscar", response_model=BusquedaDireccionOut)
async def buscar(
    texto: str = Query(min_length=3, max_length=120),
    usuario: dict = Depends(get_current_usuario),
) -> BusquedaDireccionOut:
    """Geocodificacion directa: de texto a coordenadas, para el buscador del mapa."""
    _exigir_cliente(usuario)
    lugares = await buscar_direccion(texto)
    return BusquedaDireccionOut(
        geocodificador_disponible=hay_proveedor_externo(),
        resultados=[
            SugerenciaDireccionOut(
                etiqueta=lugar.etiqueta,
                latitud=lugar.latitud,
                longitud=lugar.longitud,
                ciudad=lugar.ciudad,
            )
            for lugar in lugares
        ],
    )


@router.get("/inversa", response_model=BusquedaDireccionOut)
async def inversa(
    latitud: float = Query(ge=-90, le=90),
    longitud: float = Query(ge=-180, le=180),
    usuario: dict = Depends(get_current_usuario),
) -> BusquedaDireccionOut:
    """Geocodificacion inversa: que direccion hay donde la clienta solto el pin."""
    _exigir_cliente(usuario)
    lugar = await direccion_de_punto(latitud, longitud)
    return BusquedaDireccionOut(
        geocodificador_disponible=hay_proveedor_externo(),
        resultados=(
            [
                SugerenciaDireccionOut(
                    etiqueta=lugar.etiqueta,
                    latitud=lugar.latitud,
                    longitud=lugar.longitud,
                    ciudad=lugar.ciudad,
                )
            ]
            if lugar is not None
            else []
        ),
    )
