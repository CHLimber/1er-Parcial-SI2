import asyncio
from collections.abc import AsyncGenerator

import asyncpg

from app.core.config import settings

_pool: asyncpg.Pool | None = None


async def connect_pool() -> None:
    """Crea el pool global. Reintenta unos segundos: en Railway la red privada
    (postgres.railway.internal) puede tardar en estar lista al arrancar el contenedor."""
    global _pool
    ultimo_error: Exception | None = None
    for intento in range(1, 11):
        try:
            _pool = await asyncpg.create_pool(dsn=settings.database_url, min_size=1, max_size=10)
            return
        except (OSError, asyncpg.PostgresError) as exc:  # connection refused, DNS, auth aun no lista
            ultimo_error = exc
            print(f"connect_pool: intento {intento}/10 fallo ({exc!r}); reintentando en 3s")
            await asyncio.sleep(3)
    raise RuntimeError("No se pudo conectar a Postgres tras 10 intentos") from ultimo_error


async def disconnect_pool() -> None:
    if _pool is not None:
        await _pool.close()


async def get_connection() -> AsyncGenerator[asyncpg.Connection, None]:
    assert _pool is not None, "El pool de conexiones no fue inicializado"
    async with _pool.acquire() as connection:
        yield connection
