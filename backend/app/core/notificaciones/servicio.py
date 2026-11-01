"""Escritura de notificaciones que comparten varios casos de uso.

El modulo `notificaciones/router.py` solo lee. Los avisos a un grupo de personal ("los
encargados / cajeros de la sucursal") se repetian en reservas, pagos y traspasos, y en tres de
esos sitios se resolvian en dos pasos (traer a los encargados y hacer un INSERT por cada uno):
aca es una sola sentencia INSERT ... SELECT, sin importar cuantas personas haya.
"""

from uuid import UUID

import asyncpg


async def avisar_personal_de_sucursal(
    conn: asyncpg.Connection,
    sucursal_id: UUID,
    cargo: str,
    tipo: str,
    titulo: str,
    mensaje: str,
    entidad_tipo: str,
    entidad_id: UUID,
) -> None:
    """Notifica a todo el personal activo de `cargo` (ENCARGADO, CAJERO, ...) de la sucursal.
    `tipo` es un valor de tipo_notificacion (RESERVA, VENTA, STOCK, ...)."""
    await conn.execute(
        """
        INSERT INTO notificacion (usuario_id, tipo, titulo, mensaje, entidad_tipo, entidad_id)
        SELECT e.usuario_id, $3::tipo_notificacion, $4, $5, $6, $7
        FROM empleado e
        WHERE e.sucursal_id = $1 AND e.activo AND e.cargo = $2::cargo_empleado
        """,
        sucursal_id,
        cargo,
        tipo,
        titulo,
        mensaje,
        entidad_tipo,
        entidad_id,
    )
