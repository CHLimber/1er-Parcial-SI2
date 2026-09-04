from collections.abc import AsyncGenerator

import asyncpg

from app.core.config import settings

_pool: asyncpg.Pool | None = None


async def connect_pool() -> None:
    global _pool
    _pool = await asyncpg.create_pool(dsn=settings.database_url, min_size=1, max_size=10)


async def disconnect_pool() -> None:
    if _pool is not None:
        await _pool.close()


async def get_connection() -> AsyncGenerator[asyncpg.Connection, None]:
    assert _pool is not None, "El pool de conexiones no fue inicializado"
    async with _pool.acquire() as connection:
        yield connection
