import asyncio

from app.core.db import get_pool


async def job_expirar_reservas(intervalo_segundos: int) -> None:
    """CU04 E2: corre en loop mientras el backend esta arriba y llama a
    fn_expirar_reservas() para liberar el stock comprometido por reservas vencidas.
    Antes de esto, la unica forma de liberarlas era que un Encargado marcara la
    reserva "no se presento" a mano desde CU08 (ver PENDIENTES.txt 2.3)."""
    while True:
        try:
            pool = get_pool()
            async with pool.acquire() as conn:
                expiradas = await conn.fetchval("SELECT fn_expirar_reservas()")
            if expiradas:
                print(f"job_expirar_reservas: {expiradas} reserva(s) liberada(s) por vencimiento")
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # nunca debe tumbar el backend por un fallo transitorio de la BD
            print(f"job_expirar_reservas: fallo un ciclo ({exc!r}), reintenta en el proximo")
        await asyncio.sleep(intervalo_segundos)
