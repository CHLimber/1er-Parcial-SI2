"""Sincronizacion de operaciones offline (segundo parcial, Modulos D y E).

La PWA (IndexedDB) y la app Flutter (SQLite) registran ventas de contado y reservas sin conexion
con un UUID generado en el dispositivo, y al volver la red las mandan a POST /sync/operaciones.
Cada operacion se procesa sola, en orden de registro, con estas reglas:

  Idempotencia (RN05/RN11). Un candado de transaccion (pg_advisory_xact_lock sobre el id)
  serializa dos reenvios simultaneos del mismo id; si el id ya esta en `operacion_sync` se
  devuelve el resultado guardado (duplicada=True) sin volver a crear la venta ni a descontar
  stock. `venta.operacion_id` / `reserva.operacion_id` UNIQUE es la ultima barrera en la base.

  Rechazo definitivo (RECHAZADA): la operacion nunca va a poder aplicarse tal cual --
  empresa o responsable que no coinciden con el token, sucursal ajena o no asignada, sin
  permiso, prenda de otra empresa, total que no cierra con los precios enviados, forma de pago
  que no es efectivo, suscripcion vencida ANTES de registrar la operacion (RN06, politica del
  equipo: lo que se vendio mientras la suscripcion estaba al dia se acepta aunque se sincronice
  despues de vencer; lo registrado despues del vencimiento no), clienta inexistente o visita ya
  vencida para una reserva.

  Conflicto (CONFLICTO): los datos locales quedaron viejos y alguien tiene que decidir --
  STOCK_INSUFICIENTE, PRECIO_CAMBIADO, PRODUCTO_INACTIVO, SIN_CAJA_ABIERTA. Se resuelve con
  POST /sync/operaciones/{id}/resolver (REINTENTAR, ACEPTAR_PRECIO_ACTUAL o DESCARTAR, CU23).

  Consistencia (RNF04). La venta, su detalle (que mueve el stock via tg_venta_descuenta_stock ->
  fn_mover_inventario), el pago y el comprobante van en un savepoint: o entra todo o nada, y si
  fn_mover_inventario se queda sin stock a mitad de camino la operacion queda en CONFLICTO sin
  dejar media venta. La fila de `operacion_sync` se escribe siempre, pase lo que pase.

  Observabilidad (RNF10). Cada operacion deja una linea de log (id, tipo, empresa, sucursal,
  estado, codigo e intentos; nunca montos de pago ni datos de la clienta) y su fila en
  `operacion_sync`, que es el log consultable desde el panel.
"""

import json
import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Any
from uuid import UUID, uuid4

import asyncpg

from app.core.plan import esta_vigente, plan_de_empresa
from app.modules.operacion_sin_conexion.sincronizacion.schemas import (
    OperacionIn,
    ResultadoOperacionOut,
)

log = logging.getLogger("fashionstore.sync")

IVA_TASA = Decimal("0.13")
CENTAVO = Decimal("0.01")
# el reloj del dispositivo puede adelantar un poco; mas que esto es un dato invalido
TOLERANCIA_RELOJ = timedelta(minutes=10)


class Rechazo(Exception):
    def __init__(self, codigo: str, motivo: str):
        super().__init__(motivo)
        self.codigo = codigo
        self.motivo = motivo


class Conflicto(Rechazo):
    pass


@dataclass
class Aplicado:
    resultado: dict[str, Any]


# ---------------------------------------------------------------------
#  REGLAS PURAS (se prueban sin base, tests/test_sincronizacion.py)
# ---------------------------------------------------------------------


def total_con_iva(lineas: list[tuple[Decimal, int]]) -> tuple[Decimal, Decimal, Decimal]:
    """(subtotal, iva, total) de lineas (precio, cantidad), mismo redondeo que /ventas/pos."""
    subtotal = sum((precio * cantidad for precio, cantidad in lineas), Decimal("0"))
    iva = (subtotal * IVA_TASA).quantize(CENTAVO)
    return subtotal, iva, (subtotal + iva).quantize(CENTAVO)


def validar_cabecera(
    op: OperacionIn, staff: dict, plan: dict | asyncpg.Record | None, ahora: datetime
) -> None:
    """Lo que hace RECHAZADA una operacion antes de mirar sus prendas."""
    if op.empresa_id != staff["empresa_id"]:
        raise Rechazo("EMPRESA_AJENA", "La operacion es de otra empresa")
    if op.usuario_id != staff["id"]:
        raise Rechazo(
            "RESPONSABLE_DISTINTO",
            "La operacion la registro otro usuario: tiene que sincronizarla quien la hizo",
        )
    if op.registrada_en > ahora + TOLERANCIA_RELOJ:
        raise Rechazo("FECHA_INVALIDA", "La fecha de registro esta en el futuro (revisa el reloj)")
    if plan is None:
        raise Rechazo("SIN_SUSCRIPCION", "La empresa no tiene una suscripcion")
    if not plan["operacion_offline"]:
        raise Rechazo("PLAN_SIN_OFFLINE", f"El plan {plan['plan_nombre']} no incluye la operacion sin conexion")
    if not esta_vigente(plan, ahora) and (
        plan["estado"] == "CANCELADA" or op.registrada_en > plan["vence_en"]
    ):
        raise Rechazo(
            "SUSCRIPCION_VENCIDA",
            "La operacion se registro con la suscripcion de la empresa vencida",
        )
    if op.tipo == "VENTA" and op.venta.metodo_pago != "EFECTIVO":
        raise Rechazo("PAGO_NO_CONTADO", "Sin conexion solo se registran ventas de contado")


def diferencias_de_precio(
    items: list[tuple[str, Decimal, Decimal]],
) -> list[str]:
    """items: (sku, precio_local, precio_actual). Las lineas cuyo precio cambio."""
    return [
        f"{sku}: Bs {local:.2f} en el dispositivo, Bs {actual:.2f} hoy"
        for sku, local, actual in items
        if local.quantize(CENTAVO) != actual.quantize(CENTAVO)
    ]


# ---------------------------------------------------------------------
#  APLICACION CONTRA LA BASE
# ---------------------------------------------------------------------


async def _sucursal_autorizada(conn: asyncpg.Connection, op: OperacionIn, staff: dict) -> asyncpg.Record:
    sucursal = await conn.fetchrow(
        "SELECT id, nombre, activa FROM sucursal WHERE id = $1 AND empresa_id = $2",
        op.sucursal_id,
        staff["empresa_id"],
    )
    if sucursal is None:
        raise Rechazo("SUCURSAL_NO_AUTORIZADA", "La sucursal no es de tu empresa")
    es_admin = "sucursales.actualizar" in staff["permisos"]
    if not es_admin and staff["sucursal_id"] != op.sucursal_id:
        raise Rechazo("SUCURSAL_NO_AUTORIZADA", "No estas asignado a esa sucursal")
    if not sucursal["activa"]:
        raise Rechazo("SUCURSAL_INACTIVA", "La sucursal esta dada de baja")
    return sucursal


async def _prendas(
    conn: asyncpg.Connection, op: OperacionIn, ids: list[UUID]
) -> dict[UUID, asyncpg.Record]:
    filas = await conn.fetch(
        """
        SELECT pv.id, pv.sku, pv.activa AND p.activo AS activa, p.empresa_id, p.nombre,
               COALESCE(pv.precio_oferta, pv.precio, p.precio_base) AS precio,
               COALESCE(i.disponible, 0) AS disponible
          FROM producto_variante pv
          JOIN producto p ON p.id = pv.producto_id
          LEFT JOIN inventario i ON i.variante_id = pv.id AND i.sucursal_id = $2
         WHERE pv.id = ANY($1::uuid[])
        """,
        ids,
        op.sucursal_id,
    )
    prendas = {f["id"]: f for f in filas}
    for variante_id in ids:
        fila = prendas.get(variante_id)
        if fila is None or fila["empresa_id"] != op.empresa_id:
            raise Rechazo("PRENDA_AJENA", "Una de las prendas no existe en el catalogo de la empresa")
    inactivas = [prendas[v]["sku"] for v in ids if not prendas[v]["activa"]]
    if inactivas:
        raise Conflicto("PRODUCTO_INACTIVO", "Prendas dadas de baja: " + ", ".join(inactivas))
    return prendas


def _exigir_stock(prendas: dict, pedidas: dict[UUID, int]) -> None:
    faltan = [
        f"{prendas[v]['sku']} (hay {prendas[v]['disponible']}, se piden {c})"
        for v, c in pedidas.items()
        if prendas[v]["disponible"] < c
    ]
    if faltan:
        raise Conflicto("STOCK_INSUFICIENTE", "Stock insuficiente en la sucursal: " + "; ".join(faltan))


async def _sesion_de_caja(conn: asyncpg.Connection, op: OperacionIn, staff: dict) -> UUID:
    """La sesion abierta en la que entra el efectivo: la que conocia el dispositivo si sigue
    abierta, si no la que tenga abierta hoy el usuario en esa sucursal."""
    candidatos = [op.venta.sesion_caja_id] if op.venta.sesion_caja_id else []
    for sesion_id in candidatos:
        abierta = await conn.fetchval(
            """
            SELECT sc.id FROM sesion_caja sc JOIN caja c ON c.id = sc.caja_id
             WHERE sc.id = $1 AND sc.estado = 'ABIERTA' AND c.sucursal_id = $2
            """,
            sesion_id,
            op.sucursal_id,
        )
        if abierta:
            return abierta
    actual = await conn.fetchval(
        """
        SELECT sc.id FROM sesion_caja sc JOIN caja c ON c.id = sc.caja_id
         WHERE sc.empleado_id = $1 AND sc.estado = 'ABIERTA' AND c.sucursal_id = $2
         ORDER BY sc.abierta_en DESC LIMIT 1
        """,
        staff["id"],
        op.sucursal_id,
    )
    if actual is None:
        raise Conflicto(
            "SIN_CAJA_ABIERTA",
            "La sesion de caja de la venta ya se cerro: abri la caja y reintenta para que el "
            "efectivo entre al arqueo",
        )
    return actual


async def _aplicar_venta(
    conn: asyncpg.Connection, op: OperacionIn, staff: dict, aceptar_precio: bool
) -> dict[str, Any]:
    if "caja.crear" not in staff["permisos"]:
        raise Rechazo("SIN_PERMISO", "Tu rol no puede registrar ventas")
    await _sucursal_autorizada(conn, op, staff)
    venta = op.venta
    pedidas: dict[UUID, int] = {}
    precio_local: dict[UUID, Decimal] = {}
    for item in venta.items:
        pedidas[item.variante_id] = pedidas.get(item.variante_id, 0) + item.cantidad
        precio_local.setdefault(item.variante_id, item.precio_unitario)
    prendas = await _prendas(conn, op, list(pedidas))

    if not aceptar_precio:
        # el total tiene que cerrar con los precios que el dispositivo dice haber usado
        _, _, total_local = total_con_iva([(i.precio_unitario, i.cantidad) for i in venta.items])
        if abs(total_local - venta.total) > CENTAVO:
            raise Rechazo(
                "TOTAL_INCONSISTENTE",
                f"El total enviado (Bs {venta.total:.2f}) no coincide con sus lineas (Bs {total_local:.2f})",
            )
        cambios = diferencias_de_precio(
            [(prendas[v]["sku"], precio_local[v], prendas[v]["precio"]) for v in pedidas]
        )
        if cambios:
            raise Conflicto("PRECIO_CAMBIADO", "Cambio el precio: " + "; ".join(cambios))
    _exigir_stock(prendas, pedidas)
    sesion_id = await _sesion_de_caja(conn, op, staff)

    precios = {v: (prendas[v]["precio"] if aceptar_precio else precio_local[v]) for v in pedidas}
    subtotal, iva, total = total_con_iva([(precios[v], c) for v, c in pedidas.items()])
    cliente_id = None
    if venta.cliente_email:
        cliente_id = await conn.fetchval(
            "SELECT id FROM usuario WHERE lower(email) = lower($1) AND tipo = 'CLIENTE'",
            venta.cliente_email,
        )
    fecha = min(op.registrada_en, datetime.now(timezone.utc))
    numero = f"V-{uuid4().hex[:10].upper()}"
    venta_id = await conn.fetchval(
        """
        INSERT INTO venta (sucursal_id, usuario_id, canal, entrega, sesion_caja_id, numero, fecha,
                           subtotal, descuento, iva, total, estado, registrada_por_id, operacion_id)
        VALUES ($1, $2, 'POS', 'RETIRO_SUCURSAL', $3, $4, $5, $6, 0, $7, $8, 'ENTREGADA', $9, $10)
        RETURNING id
        """,
        op.sucursal_id,
        cliente_id,
        sesion_id,
        numero,
        fecha,
        subtotal,
        iva,
        total,
        staff["id"],
        op.id,
    )
    try:
        for variante_id, cantidad in pedidas.items():
            await conn.execute(
                """
                INSERT INTO venta_detalle (venta_id, variante_id, cantidad, precio_unitario, subtotal)
                VALUES ($1, $2, $3, $4, $5)
                """,
                venta_id,
                variante_id,
                cantidad,
                precios[variante_id],
                precios[variante_id] * cantidad,
            )
    except asyncpg.RaiseError as error:
        # otra venta se llevo el stock entre la verificacion y el descuento
        raise Conflicto("STOCK_INSUFICIENTE", str(error)) from error
    await conn.execute(
        """
        INSERT INTO pago (venta_id, metodo, monto, estado, creado_en, confirmado_en)
        VALUES ($1, 'EFECTIVO', $2, 'APROBADO', $3, now())
        """,
        venta_id,
        total,
        fecha,
    )
    comprobante = f"C-{uuid4().hex[:10].upper()}"
    await conn.execute(
        "INSERT INTO comprobante (venta_id, numero) VALUES ($1, $2)", venta_id, comprobante
    )
    return {
        "venta_id": str(venta_id),
        "numero": numero,
        "comprobante": comprobante,
        "total": float(total),
        "precio_actualizado": aceptar_precio,
    }


async def _aplicar_reserva(conn: asyncpg.Connection, op: OperacionIn, staff: dict) -> dict[str, Any]:
    if "reservas.actualizar" not in staff["permisos"]:
        raise Rechazo("SIN_PERMISO", "Tu rol no puede registrar reservas")
    await _sucursal_autorizada(conn, op, staff)
    reserva = op.reserva
    cliente_id = await conn.fetchval(
        "SELECT id FROM usuario WHERE lower(email) = lower($1) AND tipo = 'CLIENTE' AND activo",
        reserva.cliente_email.strip(),
    )
    if cliente_id is None:
        raise Rechazo("CLIENTE_INEXISTENTE", "No hay una clienta registrada con ese email")
    horas = int(
        await conn.fetchval(
            "SELECT valor FROM configuracion WHERE clave = 'reserva_horas_vigencia'"
        )
        or 4
    )
    vencida = await conn.fetchval(
        """
        SELECT (($1::date + $2::time) AT TIME ZONE 'America/La_Paz')
               + make_interval(hours => $3) < now()
        """,
        reserva.fecha_visita,
        reserva.hora_visita,
        horas,
    )
    if vencida:
        raise Rechazo("VISITA_VENCIDA", "La hora de visita de la reserva ya paso")

    pedidas: dict[UUID, int] = {}
    for item in reserva.items:
        pedidas[item.variante_id] = pedidas.get(item.variante_id, 0) + item.cantidad
    prendas = await _prendas(conn, op, list(pedidas))
    _exigir_stock(prendas, pedidas)

    codigo = f"RES-{uuid4().hex[:10].upper()}"
    # la registro el personal en la tienda: nace CONFIRMADA (no espera la aprobacion que si
    # necesita una reserva hecha por la clienta desde la app)
    fila = await conn.fetchrow(
        """
        INSERT INTO reserva (usuario_id, sucursal_id, codigo, fecha_visita, hora_visita, expira_en,
                             observaciones, estado, atendida_por_id, operacion_id)
        VALUES ($1, $2, $3, $4, $5,
                GREATEST(now(), ($4::date + $5::time) AT TIME ZONE 'America/La_Paz')
                    + make_interval(hours => $6),
                $7, 'CONFIRMADA', $8, $9)
        RETURNING id, expira_en
        """,
        cliente_id,
        op.sucursal_id,
        codigo,
        reserva.fecha_visita,
        reserva.hora_visita,
        horas,
        reserva.observaciones,
        staff["id"],
        op.id,
    )
    try:
        for variante_id, cantidad in pedidas.items():
            await conn.execute(
                "INSERT INTO reserva_detalle (reserva_id, variante_id, cantidad) VALUES ($1, $2, $3)",
                fila["id"],
                variante_id,
                cantidad,
            )
    except asyncpg.RaiseError as error:
        raise Conflicto("STOCK_INSUFICIENTE", str(error)) from error
    await conn.execute(
        """
        INSERT INTO notificacion (usuario_id, tipo, titulo, mensaje, entidad_tipo, entidad_id)
        VALUES ($1, 'RESERVA', 'Reserva confirmada', $2, 'RESERVA', $3)
        """,
        cliente_id,
        f"Te reservamos {sum(pedidas.values())} prenda(s) para el {reserva.fecha_visita} "
        f"a las {reserva.hora_visita.strftime('%H:%M')} (codigo {codigo}).",
        fila["id"],
    )
    return {"reserva_id": str(fila["id"]), "codigo": codigo, "expira_en": fila["expira_en"].isoformat()}


# ---------------------------------------------------------------------
#  ORQUESTACION
# ---------------------------------------------------------------------

SELECT_OPERACION = """
SELECT id, tipo::text AS tipo, estado::text AS estado, codigo_motivo, motivo, resultado,
       intentos, recibida_en, resuelta_en, resolucion, empresa_id, usuario_id, payload,
       registrada_en
FROM operacion_sync
"""


def a_salida(fila: asyncpg.Record, duplicada: bool = False) -> ResultadoOperacionOut:
    return ResultadoOperacionOut(
        id=fila["id"],
        tipo=fila["tipo"],
        estado=fila["estado"],
        codigo_motivo=fila["codigo_motivo"],
        motivo=fila["motivo"],
        resultado=json.loads(fila["resultado"]) if fila["resultado"] else None,
        duplicada=duplicada,
        intentos=fila["intentos"],
        recibida_en=fila["recibida_en"],
        resuelta_en=fila["resuelta_en"],
        resolucion=fila["resolucion"],
    )


async def procesar(
    conn: asyncpg.Connection,
    staff: dict,
    op: OperacionIn,
    *,
    reprocesar: bool = False,
    aceptar_precio: bool = False,
) -> ResultadoOperacionOut:
    """Procesa UNA operacion y siempre deja su fila en operacion_sync. Con reprocesar=False un
    id ya recibido devuelve lo guardado (idempotencia); reprocesar=True es el camino de CU23."""
    ahora = datetime.now(timezone.utc)
    async with conn.transaction():
        await conn.execute("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", str(op.id))
        previa = await conn.fetchrow(SELECT_OPERACION + "WHERE id = $1", op.id)
        if previa is not None and not reprocesar:
            if previa["empresa_id"] != staff["empresa_id"]:
                # mismo UUID desde otra empresa: no se revela nada de la operacion ajena
                return ResultadoOperacionOut(
                    id=op.id, tipo=op.tipo, estado="RECHAZADA", codigo_motivo="ID_REPETIDO",
                    motivo="Ese identificador de operacion ya fue usado",
                )
            fila = await conn.fetchrow(
                """
                UPDATE operacion_sync SET intentos = intentos + 1, ultimo_intento = now()
                 WHERE id = $1
                RETURNING id, tipo::text AS tipo, estado::text AS estado, codigo_motivo, motivo,
                          resultado, intentos, recibida_en, resuelta_en, resolucion
                """,
                op.id,
            )
            log.info(
                "sync duplicada id=%s tipo=%s estado=%s intentos=%s",
                op.id, op.tipo, fila["estado"], fila["intentos"],
            )
            return a_salida(fila, duplicada=True)

        estado, codigo, motivo, resultado = "CONFIRMADA", None, None, None
        try:
            async with conn.transaction():  # savepoint: la venta entra entera o no entra
                validar_cabecera(op, staff, await plan_de_empresa(conn, staff["empresa_id"]), ahora)
                if op.tipo == "VENTA":
                    resultado = await _aplicar_venta(conn, op, staff, aceptar_precio)
                else:
                    resultado = await _aplicar_reserva(conn, op, staff)
        except Conflicto as error:
            estado, codigo, motivo = "CONFLICTO", error.codigo, error.motivo
        except Rechazo as error:
            estado, codigo, motivo = "RECHAZADA", error.codigo, error.motivo

        # la sucursal se guarda solo si es de la empresa (una ajena no se puede referenciar)
        sucursal_valida = await conn.fetchval(
            "SELECT id FROM sucursal WHERE id = $1 AND empresa_id = $2",
            op.sucursal_id,
            staff["empresa_id"],
        )
        fila = await conn.fetchrow(
            """
            INSERT INTO operacion_sync (id, empresa_id, sucursal_id, usuario_id, tipo, estado,
                                        codigo_motivo, motivo, payload, resultado, registrada_en)
            VALUES ($1, $2, $3, $4, $5::tipo_operacion_sync, $6::estado_operacion_sync, $7, $8,
                    $9::jsonb, $10::jsonb, $11)
            ON CONFLICT (id) DO UPDATE
               SET estado = EXCLUDED.estado, codigo_motivo = EXCLUDED.codigo_motivo,
                   motivo = EXCLUDED.motivo, resultado = EXCLUDED.resultado,
                   intentos = operacion_sync.intentos + 1, ultimo_intento = now()
            RETURNING id, tipo::text AS tipo, estado::text AS estado, codigo_motivo, motivo,
                      resultado, intentos, recibida_en, resuelta_en, resolucion
            """,
            op.id,
            staff["empresa_id"],
            sucursal_valida,
            staff["id"],
            op.tipo,
            estado,
            codigo,
            motivo,
            op.model_dump_json(),
            json.dumps(resultado) if resultado else None,
            op.registrada_en,
        )
    log.info(
        "sync id=%s tipo=%s empresa=%s sucursal=%s estado=%s codigo=%s intentos=%s",
        op.id, op.tipo, staff["empresa_id"], op.sucursal_id, estado, codigo, fila["intentos"],
    )
    return a_salida(fila)
