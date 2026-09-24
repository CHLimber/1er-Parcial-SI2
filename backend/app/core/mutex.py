"""Mutex de aplicacion para serializar reservas sobre la misma prenda.

Complementa, no reemplaza, el `FOR UPDATE` de `fn_mover_inventario` (db/02_logica.sql), que es
el mecanismo que de verdad resuelve la condicion de carrera entre 2 clientes reservando la
ultima unidad: ese lock vive en Postgres y protege a cualquier proceso que se conecte a la base.

Este mutex de Python solo sirve dentro de un mismo proceso de Uvicorn -- si el backend corre con
`--workers > 1` o con varias replicas (Railway, Docker escalado), cada proceso tiene su propio
diccionario de locks y no se enteran entre si. Se agrega como capa didactica adicional sobre el
mismo `variante_id` + `sucursal_id`, no como la garantia de fondo.
"""

import asyncio
from collections import defaultdict
from uuid import UUID

_locks: dict[tuple[UUID, UUID], asyncio.Lock] = defaultdict(asyncio.Lock)


def mutex_variante(sucursal_id: UUID, variante_id: UUID) -> asyncio.Lock:
    """Devuelve (creando si hace falta) el lock de esta prenda en esta sucursal."""
    return _locks[(sucursal_id, variante_id)]
