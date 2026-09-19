import asyncio
from decimal import Decimal
from uuid import UUID, uuid4

import asyncpg
import stripe
from fastapi import APIRouter, Depends, HTTPException, status

from app.core.config import settings
from app.core.db import get_connection
from app.core.deps import get_cajero_actual, get_current_usuario
from app.modules.caja.router import obtener_sesion_abierta
from app.modules.envios.servicio import SinCoordenadas, cotizar
from app.modules.pagos.servicio import _alertar_stock_bajo, confirmar_aprobado
from app.modules.ventas.schemas import (
    CheckoutIn,
    CheckoutOut,
    ComprobanteOut,
    ItemRechazadoPosOut,
    PagoOut,
    VentaItemOut,
    VentaOut,
    VentaPosIn,
    VentaPosOut,
    VentaResumenOut,
)

router = APIRouter(prefix="/ventas", tags=["ventas"])

IVA_TASA = Decimal("0.13")

stripe.api_key = settings.stripe_secret_key


async def _crear_sesion_stripe(
    venta_id: UUID, numero: str, total: Decimal, *, canal: str
) -> tuple[str, str | None, str | None]:
    """CU06 paso 1: envia la orden de cobro a la pasarela. Devuelve
    (id_transaccion, url_pago, client_secret).

    canal == "WEB" pide un Checkout Session con `ui_mode="embedded"`: Stripe.js lo monta inline en
    la misma pagina con el client_secret, sin redirigir a checkout.stripe.com, y
    `redirect_on_completion="never"` evita que Stripe intente navegar por su cuenta al terminar.
    canal == "MOVIL" pide en cambio un PaymentIntent: el paquete `flutter_stripe` (Stripe SDK
    nativo para Android/iOS) muestra su propio PaymentSheet DENTRO de la app con ese
    client_secret, sin abrir el navegador del telefono -- ya no hay Checkout hospedado en el
    movil. En ambos casos la confirmacion real sigue llegando por el webhook firmado,
    server-to-server; esto solo arma la UI de cobro."""
    if canal == "MOVIL":
        try:
            intento = await asyncio.to_thread(
                stripe.PaymentIntent.create,
                amount=int(total * 100),
                currency="bob",
                payment_method_types=["card"],
                description=f"Pedido {numero} - FashionStore",
                metadata={"venta_id": str(venta_id), "numero": numero},
            )
        except stripe.error.StripeError as error:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"No se pudo iniciar el pago con Stripe: {error}",
            ) from error
        return intento.id, None, intento.client_secret

    parametros: dict = {
        "mode": "payment",
        "payment_method_types": ["card"],
        "ui_mode": "embedded",
        "redirect_on_completion": "never",
        "line_items": [
            {
                "price_data": {
                    "currency": "bob",
                    "product_data": {"name": f"Pedido {numero} - FashionStore"},
                    "unit_amount": int(total * 100),
                },
                "quantity": 1,
            }
        ],
        "metadata": {"venta_id": str(venta_id), "numero": numero},
    }
    try:
        sesion = await asyncio.to_thread(stripe.checkout.Session.create, **parametros)
    except stripe.error.StripeError as error:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"No se pudo iniciar el pago con Stripe: {error}",
        ) from error
    return sesion.id, None, sesion.client_secret


async def _pago_pendiente_stripe(id_transaccion: str, *, canal: str) -> tuple[str | None, str | None]:
    """Reintento de un checkout que ya se inicio (doble click): recupera el PaymentIntent o la
    Checkout Session en vez de crear uno nuevo. Devuelve (url_pago, client_secret)."""
    try:
        if canal == "MOVIL":
            intento = await asyncio.to_thread(stripe.PaymentIntent.retrieve, id_transaccion)
            return None, intento.client_secret
        sesion = await asyncio.to_thread(stripe.checkout.Session.retrieve, id_transaccion)
        return None, sesion.client_secret
    except stripe.error.StripeError:
        return None, None


def _intento_sirve_para_canal(
    pasarela: str | None, id_transaccion: str | None, canal: str
) -> bool:
    """Si un checkout STRIPE que quedo PENDIENTE se puede retomar desde este canal.

    Cada canal arma un objeto distinto en Stripe -- la web una Checkout Session (`cs_...`) que
    monta Stripe.js, el movil un PaymentIntent (`pi_...`) que abre el PaymentSheet nativo -- y
    cada SDK solo entiende el client_secret del suyo. Como el reuso de un pendiente se busca por
    carrito, sin esto el mismo pedido empezado en la web y retomado desde el celular (o al reves)
    intentaba recuperar el objeto equivocado: `PaymentIntent.retrieve("cs_...")` tira StripeError,
    el client_secret volvia vacio y la app se quedaba sin forma de cobrar. Tambien ataja los pagos
    que quedaron pendientes con un backend anterior, cuando el movil todavia usaba Checkout
    hospedado. Si no sirve, el checkout abandona ese intento y arma uno nuevo para este canal."""
    if pasarela != "STRIPE":
        return True
    if not id_transaccion:
        return False
    return id_transaccion.startswith("cs_" if canal == "WEB" else "pi_")


def _exigir_cliente(usuario: dict) -> None:
    if usuario["tipo"] != "CLIENTE":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo un cliente puede comprar por web/app",
        )


async def _aplicar_cupon(
    conn: asyncpg.Connection, codigo: str, items: list[asyncpg.Record], subtotal: Decimal
) -> tuple[UUID, Decimal]:
    promo = await conn.fetchrow(
        """
        SELECT id, tipo, valor, alcance, categoria_id, temporada_id, monto_minimo,
               uso_maximo, usos_actuales
        FROM promocion
        WHERE codigo_cupon = $1 AND activa AND CURRENT_DATE BETWEEN fecha_inicio AND fecha_fin
        """,
        codigo.strip().upper(),
    )
    if promo is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Ese cupon no existe, vencio o esta inactivo",
        )
    if promo["uso_maximo"] is not None and promo["usos_actuales"] >= promo["uso_maximo"]:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Ese cupon ya alcanzo su limite de usos",
        )
    if promo["monto_minimo"] is not None and subtotal < promo["monto_minimo"]:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Ese cupon requiere una compra minima de Bs {promo['monto_minimo']}",
        )

    if promo["alcance"] == "TODO":
        base = subtotal
    else:
        columna = "categoria_id" if promo["alcance"] == "CATEGORIA" else "temporada_id"
        objetivo = promo[columna]
        base = sum(
            (Decimal(str(item["precio_unitario"])) * item["cantidad"] for item in items if item[columna] == objetivo),
            Decimal("0"),
        )
    if base <= 0:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Ese cupon no aplica a ninguna prenda de tu carrito",
        )

    if promo["tipo"] == "PORCENTAJE":
        descuento = (base * Decimal(str(promo["valor"])) / Decimal("100")).quantize(Decimal("0.01"))
    else:
        descuento = min(Decimal(str(promo["valor"])), base)

    await conn.execute(
        "UPDATE promocion SET usos_actuales = usos_actuales + 1 WHERE id = $1", promo["id"]
    )
    return promo["id"], descuento


@router.post("/checkout", response_model=CheckoutOut, status_code=status.HTTP_201_CREATED)
async def iniciar_checkout(
    body: CheckoutIn,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> CheckoutOut:
    _exigir_cliente(usuario)

    carrito = await conn.fetchrow(
        "SELECT id, reserva_id FROM carrito WHERE usuario_id = $1 AND estado = 'ACTIVO'",
        usuario["id"],
    )
    if carrito is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="No tenes un carrito activo"
        )

    items = await conn.fetch(
        """
        SELECT ci.id, ci.variante_id, ci.cantidad, ci.precio_unitario,
               p.categoria_id, p.temporada_id
        FROM carrito_item ci
        JOIN producto_variante pv ON pv.id = ci.variante_id
        JOIN producto p ON p.id = pv.producto_id
        WHERE ci.carrito_id = $1
        """,
        carrito["id"],
    )
    if not items:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Tu carrito esta vacio"
        )

    destino_envio: tuple[float | None, float | None] | None = None

    if carrito["reserva_id"] is not None:
        # una compra nacida de una reserva se retira en la misma sucursal donde se comprometio el stock
        reserva = await conn.fetchrow(
            "SELECT sucursal_id FROM reserva WHERE id = $1", carrito["reserva_id"]
        )
        sucursal_id = reserva["sucursal_id"]
        entrega = "RETIRO_SUCURSAL"
        direccion_id = None
    else:
        if body.sucursal_id is None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Elegi la sucursal desde la que se despacha tu pedido",
            )
        sucursal = await conn.fetchrow(
            "SELECT id FROM sucursal WHERE id = $1 AND activa", body.sucursal_id
        )
        if sucursal is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sucursal no encontrada")
        sucursal_id = body.sucursal_id
        entrega = body.entrega
        direccion_id = body.direccion_id

        if entrega == "DOMICILIO":
            if direccion_id is None:
                direccion = await conn.fetchrow(
                    "SELECT id, latitud, longitud FROM direccion WHERE usuario_id = $1 AND es_principal",
                    usuario["id"],
                )
                if direccion is None:
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail="No tenes una direccion registrada para el envio a domicilio",
                    )
                direccion_id = direccion["id"]
            else:
                direccion = await conn.fetchrow(
                    "SELECT id, latitud, longitud FROM direccion WHERE id = $1 AND usuario_id = $2",
                    direccion_id,
                    usuario["id"],
                )
                if direccion is None:
                    raise HTTPException(
                        status_code=status.HTTP_404_NOT_FOUND, detail="Esa direccion no te pertenece"
                    )
            # CU20: la tarifa se cotiza mas abajo, cuando ya se sabe cuanto suma el pedido
            # (de ese monto depende que el envio salga gratis)
            destino_envio = (
                float(direccion["latitud"]) if direccion["latitud"] is not None else None,
                float(direccion["longitud"]) if direccion["longitud"] is not None else None,
            )

    variante_ids = [item["variante_id"] for item in items]
    if carrito["reserva_id"] is not None:
        # Estas unidades ya estan comprometidas por fn_reserva_compromete_stock: inventario.disponible
        # (cantidad_fisica - cantidad_reservada) las excluye a proposito, asi que exigirles
        # disponibilidad libre las rechaza aunque sean del propio cliente (p.ej. si eran la ultima
        # unidad de la sucursal). Se valida en cambio que la reserva siga sosteniendo el compromiso.
        comprometido = await conn.fetch(
            """
            SELECT variante_id, cantidad
            FROM reserva_detalle
            WHERE reserva_id = $1 AND estado_item IN ('RESERVADO', 'PREPARADO', 'PROBADO')
            """,
            carrito["reserva_id"],
        )
        cantidad_comprometida = {fila["variante_id"]: fila["cantidad"] for fila in comprometido}
        sin_stock = [
            str(item["variante_id"])
            for item in items
            if cantidad_comprometida.get(item["variante_id"], 0) < item["cantidad"]
        ]
        if sin_stock:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={
                    "mensaje": "Tu reserva ya no respalda estas prendas (se atendio, expiro o cambio)",
                    "variantes_sin_stock": sin_stock,
                },
            )
    else:
        disponibilidad = await conn.fetch(
            """
            SELECT variante_id, COALESCE(disponible, 0) AS disponible
            FROM inventario
            WHERE sucursal_id = $1 AND variante_id = ANY($2::uuid[])
            """,
            sucursal_id,
            variante_ids,
        )
        disponible_por_variante = {fila["variante_id"]: fila["disponible"] for fila in disponibilidad}
        sin_stock = [
            str(item["variante_id"])
            for item in items
            if disponible_por_variante.get(item["variante_id"], 0) < item["cantidad"]
        ]
        if sin_stock:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={
                    "mensaje": "Algunas prendas ya no tienen stock suficiente en esa sucursal",
                    "variantes_sin_stock": sin_stock,
                },
            )

    subtotal = sum(
        (Decimal(str(item["precio_unitario"])) * item["cantidad"] for item in items), Decimal("0")
    )

    # Reintento de un checkout ya iniciado (doble click): se reusan la venta y el pago pendientes
    # en vez de crear otros. Pero SOLO si el pedido sigue siendo identico: a una Checkout Session
    # de Stripe no se le puede cambiar el importe una vez creada, y _pago_pendiente_stripe la
    # recupera tal cual, asi que reusarla despues de que la clienta sumo una prenda o paso a envio
    # a domicilio le dejaba el monto viejo en el formulario embebido aunque el resto de la pantalla
    # ya mostrara el nuevo. Si cambio algo que mueve el total (metodo de pago, sucursal, entrega,
    # direccion, cupon o el contenido del carrito), el intento anterior se abandona aca abajo y el
    # resto de la funcion arma una venta y una sesion nuevas con el importe correcto.
    #
    # Ademas de esos campos, se recalcula con la formula ACTUAL de IVA_TASA lo que el iva/total
    # deberian dar a partir del subtotal/descuento/costo_envio ya guardados en la venta pendiente,
    # y se compara contra lo que quedo grabado: si no coincide es que la formula de impuestos
    # cambio (como paso al sacarle IVA al envio) desde que se creo esa venta, y reusarla devolveria
    # -via Stripe Session.retrieve- un monto calculado con la regla vieja. Sin este chequeo, una
    # venta pendiente de antes del cambio quedaba "atascada" con el monto incorrecto para siempre,
    # porque los demas campos (sucursal, entrega, subtotal...) seguian siendo identicos.
    codigo_cupon = body.codigo_cupon.strip().upper() if body.codigo_cupon else None
    pendiente = await conn.fetchrow(
        """
        SELECT v.id AS venta_id, v.numero, v.subtotal, v.descuento, v.costo_envio, v.iva,
               v.total, v.estado, v.promocion_id, v.sucursal_id, v.entrega, v.direccion_id,
               p.id AS pago_id, p.pasarela, p.id_transaccion, pr.codigo_cupon
        FROM venta v
        JOIN pago p ON p.venta_id = v.id
        LEFT JOIN promocion pr ON pr.id = v.promocion_id
        WHERE v.carrito_id = $1 AND v.estado = 'PENDIENTE' AND p.estado = 'PENDIENTE'
        ORDER BY v.fecha DESC
        LIMIT 1
        """,
        carrito["id"],
    )
    formula_vigente = False
    if pendiente is not None:
        base_esperada = pendiente["subtotal"] - pendiente["descuento"]
        iva_esperado = (base_esperada * IVA_TASA).quantize(Decimal("0.01"))
        total_esperado = (base_esperada + iva_esperado + pendiente["costo_envio"]).quantize(
            Decimal("0.01")
        )
        formula_vigente = pendiente["iva"] == iva_esperado and pendiente["total"] == total_esperado
    reusar = pendiente is not None and (
        formula_vigente
        and pendiente["pasarela"] == body.metodo_pago
        and pendiente["sucursal_id"] == sucursal_id
        and pendiente["entrega"] == entrega
        and pendiente["direccion_id"] == direccion_id
        and pendiente["subtotal"] == subtotal
        and pendiente["codigo_cupon"] == codigo_cupon
        and _intento_sirve_para_canal(
            pendiente["pasarela"], pendiente["id_transaccion"], body.canal
        )
    )
    url_pago = None
    client_secret = None
    if reusar and pendiente["pasarela"] == "STRIPE":
        url_pago, client_secret = await _pago_pendiente_stripe(
            pendiente["id_transaccion"], canal=body.canal
        )
        # Stripe ya no lo reconoce (la sesion expiro, o quedo de otra cuenta/clave): no hay nada
        # que retomar, asi que se abandona igual que si el pedido hubiera cambiado y se arma uno
        # nuevo. Devolverlo sin client_secret dejaba a la clienta sin forma de pagar ese carrito.
        reusar = client_secret is not None
    if reusar:
        if pendiente["pasarela"] != "STRIPE":
            url_pago = f"/pago-simulado/{pendiente['venta_id']}"
        return CheckoutOut(
            venta_id=pendiente["venta_id"],
            numero=pendiente["numero"],
            pago_id=pendiente["pago_id"],
            pasarela=pendiente["pasarela"],
            id_transaccion=pendiente["id_transaccion"],
            url_pago=url_pago,
            client_secret=client_secret,
            subtotal=float(pendiente["subtotal"]),
            descuento=float(pendiente["descuento"]),
            costo_envio=float(pendiente["costo_envio"]),
            iva=float(pendiente["iva"]),
            total=float(pendiente["total"]),
            estado=pendiente["estado"],
        )
    if pendiente is not None:
        # el intento anterior ya no corresponde al pedido actual: se abandona (sin notificar a la
        # clienta, no es un rechazo real) y se libera el uso del cupon que habia consumido, para
        # que _aplicar_cupon lo pueda volver a tomar aca abajo
        await conn.execute(
            "UPDATE pago SET estado = 'RECHAZADO', confirmado_en = now() WHERE id = $1",
            pendiente["pago_id"],
        )
        await conn.execute(
            "UPDATE venta SET estado = 'ANULADA' WHERE id = $1", pendiente["venta_id"]
        )
        if pendiente["promocion_id"] is not None:
            await conn.execute(
                "UPDATE promocion SET usos_actuales = GREATEST(usos_actuales - 1, 0) WHERE id = $1",
                pendiente["promocion_id"],
            )

    descuento = Decimal("0")
    promocion_id = None
    if body.codigo_cupon:
        promocion_id, descuento = await _aplicar_cupon(conn, body.codigo_cupon, items, subtotal)

    # CU20: el delivery se vuelve a cotizar aca, del lado del servidor. Lo que la clienta vio
    # en /envios/cotizar es informativo; lo que se cobra es esto.
    costo_envio = Decimal("0")
    if entrega == "DOMICILIO" and destino_envio is not None:
        try:
            cotizacion = await cotizar(
                conn, sucursal_id, destino_envio[0], destino_envio[1], subtotal - descuento
            )
        except SinCoordenadas as error:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(error)
            ) from error
        if not cotizacion.dentro_cobertura:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=(
                    f"Tu direccion esta a {cotizacion.distancia_km:.1f} km de la sucursal y el "
                    f"reparto llega hasta {cotizacion.radio_km:.0f} km. Elegi otra sucursal o "
                    "retira tu pedido en tienda."
                ),
            )
        costo_envio = cotizacion.costo

    # El IVA se calcula solo sobre las prendas (subtotal - descuento): el flete no lleva impuesto,
    # se suma aparte tal cual lo cotizo fn_cotizar_envio().
    base_imponible = subtotal - descuento
    iva = (base_imponible * IVA_TASA).quantize(Decimal("0.01"))
    total = (base_imponible + iva + costo_envio).quantize(Decimal("0.01"))

    numero = f"V-{uuid4().hex[:10].upper()}"
    async with conn.transaction():
        venta = await conn.fetchrow(
            """
            INSERT INTO venta (sucursal_id, usuario_id, canal, entrega, direccion_id, reserva_id,
                                carrito_id, promocion_id, numero, subtotal, descuento, costo_envio,
                                iva, total)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
            RETURNING id, numero, subtotal, descuento, costo_envio, iva, total, estado
            """,
            sucursal_id,
            usuario["id"],
            body.canal,
            entrega,
            direccion_id,
            carrito["reserva_id"],
            carrito["id"],
            promocion_id,
            numero,
            subtotal,
            descuento,
            costo_envio,
            iva,
            total,
        )
        client_secret = None
        if body.metodo_pago == "STRIPE":
            pasarela_val = "STRIPE"
            id_transaccion, url_pago, client_secret = await _crear_sesion_stripe(
                venta["id"], venta["numero"], total, canal=body.canal
            )
        elif body.metodo_pago == "QR":
            pasarela_val = "QR"
            id_transaccion = f"SIM-{uuid4().hex}"
            url_pago = f"/pago-simulado/{venta['id']}"
        else:
            # EFECTIVO: no hay pasarela, se aprueba al toque mas abajo (retiro lo cobra la
            # sucursal, domicilio queda a cargo del servicio de delivery)
            pasarela_val = None
            id_transaccion = None
            url_pago = f"/compra/{venta['id']}"

        metodo = "PASARELA" if pasarela_val is not None else "EFECTIVO"
        pago = await conn.fetchrow(
            """
            INSERT INTO pago (venta_id, metodo, pasarela, monto, id_transaccion)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING id, pasarela, id_transaccion
            """,
            venta["id"],
            metodo,
            pasarela_val,
            total,
            id_transaccion,
        )

    estado_final = venta["estado"]
    if body.metodo_pago == "EFECTIVO":
        venta_para_confirmar = {
            "id": venta["id"],
            "carrito_id": carrito["id"],
            "reserva_id": carrito["reserva_id"],
            "sucursal_id": sucursal_id,
        }
        resultado = await confirmar_aprobado(conn, pago["id"], venta_para_confirmar)
        estado_final = resultado["venta_estado"]

    return CheckoutOut(
        venta_id=venta["id"],
        numero=venta["numero"],
        pago_id=pago["id"],
        pasarela=pago["pasarela"],
        id_transaccion=pago["id_transaccion"],
        url_pago=url_pago,
        client_secret=client_secret,
        subtotal=float(venta["subtotal"]),
        descuento=float(venta["descuento"]),
        costo_envio=float(venta["costo_envio"]),
        iva=float(venta["iva"]),
        total=float(venta["total"]),
        estado=estado_final,
    )


@router.get("", response_model=list[VentaResumenOut])
async def listar_mis_ventas(
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> list[VentaResumenOut]:
    _exigir_cliente(usuario)
    filas = await conn.fetch(
        """
        SELECT v.id, v.numero, v.canal, v.estado, v.total, v.fecha, s.nombre AS sucursal
        FROM venta v
        JOIN sucursal s ON s.id = v.sucursal_id
        WHERE v.usuario_id = $1
        ORDER BY v.fecha DESC
        """,
        usuario["id"],
    )
    return [
        VentaResumenOut(
            id=fila["id"],
            numero=fila["numero"],
            canal=fila["canal"],
            estado=fila["estado"],
            total=float(fila["total"]),
            fecha=fila["fecha"],
            sucursal=fila["sucursal"],
        )
        for fila in filas
    ]


@router.get("/{venta_id}", response_model=VentaOut)
async def obtener_venta(
    venta_id: UUID,
    usuario: dict = Depends(get_current_usuario),
    conn: asyncpg.Connection = Depends(get_connection),
) -> VentaOut:
    _exigir_cliente(usuario)

    venta = await conn.fetchrow(
        """
        SELECT v.id, v.numero, v.canal, v.entrega, v.estado, v.subtotal, v.descuento,
               v.costo_envio, v.iva, v.total, v.fecha, v.carrito_id, s.nombre AS sucursal
        FROM venta v
        JOIN sucursal s ON s.id = v.sucursal_id
        WHERE v.id = $1 AND v.usuario_id = $2
        """,
        venta_id,
        usuario["id"],
    )
    if venta is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Venta no encontrada")

    if venta["estado"] in ("PAGADA", "ENTREGADA"):
        filas_items = await conn.fetch(
            """
            SELECT vd.variante_id, vd.cantidad, vd.precio_unitario, vd.subtotal,
                   pv.sku, p.nombre AS producto, t.codigo AS talla, c.nombre AS color
            FROM venta_detalle vd
            JOIN producto_variante pv ON pv.id = vd.variante_id
            JOIN producto p ON p.id = pv.producto_id
            JOIN talla t    ON t.id = pv.talla_id
            JOIN color c    ON c.id = pv.color_id
            WHERE vd.venta_id = $1
            """,
            venta_id,
        )
    else:
        # todavia no hay venta_detalle (se inserta recien cuando el webhook confirma el pago):
        # mostramos lo que habia en el carrito al momento del checkout
        filas_items = await conn.fetch(
            """
            SELECT ci.variante_id, ci.cantidad, ci.precio_unitario,
                   ci.precio_unitario * ci.cantidad AS subtotal,
                   pv.sku, p.nombre AS producto, t.codigo AS talla, c.nombre AS color
            FROM carrito_item ci
            JOIN producto_variante pv ON pv.id = ci.variante_id
            JOIN producto p ON p.id = pv.producto_id
            JOIN talla t    ON t.id = pv.talla_id
            JOIN color c    ON c.id = pv.color_id
            WHERE ci.carrito_id = $1
            """,
            venta["carrito_id"],
        )

    items = [
        VentaItemOut(
            variante_id=fila["variante_id"],
            sku=fila["sku"],
            producto=fila["producto"],
            talla=fila["talla"],
            color=fila["color"],
            cantidad=fila["cantidad"],
            precio_unitario=float(fila["precio_unitario"]),
            subtotal=float(fila["subtotal"]),
        )
        for fila in filas_items
    ]

    pago = await conn.fetchrow(
        """
        SELECT id, metodo, pasarela, monto, estado, id_transaccion, creado_en, confirmado_en
        FROM pago WHERE venta_id = $1
        ORDER BY creado_en DESC LIMIT 1
        """,
        venta_id,
    )
    comprobante = await conn.fetchrow(
        "SELECT numero, tipo, emitido_en FROM comprobante WHERE venta_id = $1", venta_id
    )

    return VentaOut(
        id=venta["id"],
        numero=venta["numero"],
        canal=venta["canal"],
        entrega=venta["entrega"],
        estado=venta["estado"],
        sucursal=venta["sucursal"],
        subtotal=float(venta["subtotal"]),
        descuento=float(venta["descuento"]),
        costo_envio=float(venta["costo_envio"]),
        iva=float(venta["iva"]),
        total=float(venta["total"]),
        fecha=venta["fecha"],
        items=items,
        pago=(
            PagoOut(
                id=pago["id"],
                metodo=pago["metodo"],
                pasarela=pago["pasarela"],
                monto=float(pago["monto"]),
                estado=pago["estado"],
                id_transaccion=pago["id_transaccion"],
                creado_en=pago["creado_en"],
                confirmado_en=pago["confirmado_en"],
            )
            if pago
            else None
        ),
        comprobante=(
            ComprobanteOut(
                numero=comprobante["numero"],
                tipo=comprobante["tipo"],
                emitido_en=comprobante["emitido_en"],
            )
            if comprobante
            else None
        ),
    )


@router.post("/pos", response_model=VentaPosOut, status_code=status.HTTP_201_CREATED)
async def registrar_venta_pos(
    body: VentaPosIn,
    cajero: dict = Depends(get_cajero_actual),
    conn: asyncpg.Connection = Depends(get_connection),
) -> VentaPosOut:
    """CU07: el Cajero cobra en el mostrador. A diferencia del checkout web (CU05/CU06) el cobro
    ya se confirmo en persona -- no hay pasarela ni webhook, la venta se marca PAGADA de una."""
    sesion = await obtener_sesion_abierta(conn, cajero["usuario_id"])
    if sesion is None:
        # E1: sesion de caja no abierta -- el cajero debe abrirla antes de vender
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Abri una sesion de caja antes de registrar una venta",
        )

    variante_ids = [item.variante_id for item in body.items]
    filas = await conn.fetch(
        """
        SELECT pv.id AS variante_id, pv.sku, pv.activa, p.nombre AS producto,
               t.codigo AS talla, c.nombre AS color,
               COALESCE(pv.precio_oferta, pv.precio, p.precio_base) AS precio,
               COALESCE(i.disponible, 0) AS disponible
        FROM producto_variante pv
        JOIN producto p ON p.id = pv.producto_id
        JOIN talla t    ON t.id = pv.talla_id
        JOIN color c    ON c.id = pv.color_id
        LEFT JOIN inventario i ON i.variante_id = pv.id AND i.sucursal_id = $2
        WHERE pv.id = ANY($1::uuid[])
        """,
        variante_ids,
        cajero["sucursal_id"],
    )
    info_por_variante = {fila["variante_id"]: fila for fila in filas}

    numero = f"V-{uuid4().hex[:10].upper()}"
    aceptados: list[tuple] = []
    rechazados: list[ItemRechazadoPosOut] = []

    async with conn.transaction():
        venta = await conn.fetchrow(
            """
            INSERT INTO venta (sucursal_id, canal, entrega, sesion_caja_id, numero,
                                subtotal, descuento, iva, total, registrada_por_id)
            VALUES ($1, 'POS', 'RETIRO_SUCURSAL', $2, $3, 0, 0, 0, 0, $4)
            RETURNING id
            """,
            cajero["sucursal_id"],
            sesion["id"],
            numero,
            cajero["usuario_id"],
        )

        for item in body.items:
            info = info_por_variante.get(item.variante_id)
            if info is None or not info["activa"]:
                rechazados.append(
                    ItemRechazadoPosOut(
                        variante_id=item.variante_id,
                        sku=info["sku"] if info else "?",
                        motivo="Esa prenda ya no esta disponible en el catalogo",
                    )
                )
                continue
            if info["disponible"] < item.cantidad:
                rechazados.append(
                    ItemRechazadoPosOut(
                        variante_id=item.variante_id,
                        sku=info["sku"],
                        motivo=f"Stock insuficiente en esta sucursal ({info['disponible']} disponible(s))",
                    )
                )
                continue

            precio = Decimal(str(info["precio"]))
            subtotal_item = precio * item.cantidad
            try:
                async with conn.transaction():
                    await conn.execute(
                        """
                        INSERT INTO venta_detalle (venta_id, variante_id, cantidad, precio_unitario, subtotal)
                        VALUES ($1, $2, $3, $4, $5)
                        """,
                        venta["id"],
                        item.variante_id,
                        item.cantidad,
                        precio,
                        subtotal_item,
                    )
            except asyncpg.PostgresError:
                # E2: stock insuficiente detectado recien al descontar (venta concurrente en otra caja)
                rechazados.append(
                    ItemRechazadoPosOut(
                        variante_id=item.variante_id,
                        sku=info["sku"],
                        motivo="Otra venta se llevo el stock justo antes",
                    )
                )
                continue

            aceptados.append((item, info, subtotal_item))

        if not aceptados:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={
                    "mensaje": "No se pudo vender ninguna prenda: sin stock en esta sucursal",
                    "rechazados": [
                        {"variante_id": str(r.variante_id), "sku": r.sku, "motivo": r.motivo}
                        for r in rechazados
                    ],
                },
            )

        subtotal = sum((x[2] for x in aceptados), Decimal("0"))
        iva = (subtotal * IVA_TASA).quantize(Decimal("0.01"))
        total = (subtotal + iva).quantize(Decimal("0.01"))

        await conn.execute(
            "UPDATE venta SET subtotal = $1, iva = $2, total = $3, estado = 'PAGADA' WHERE id = $4",
            subtotal,
            iva,
            total,
            venta["id"],
        )
        await conn.execute(
            """
            INSERT INTO pago (venta_id, metodo, monto, estado, confirmado_en)
            VALUES ($1, $2, $3, 'APROBADO', now())
            """,
            venta["id"],
            body.metodo_pago,
            total,
        )
        numero_comprobante = f"C-{uuid4().hex[:10].upper()}"
        await conn.execute(
            "INSERT INTO comprobante (venta_id, numero) VALUES ($1, $2)",
            venta["id"],
            numero_comprobante,
        )

    await _alertar_stock_bajo(conn, cajero["sucursal_id"], venta["id"])

    vuelto = None
    if body.metodo_pago == "EFECTIVO" and body.monto_recibido is not None:
        vuelto = float(Decimal(str(body.monto_recibido)) - total)

    return VentaPosOut(
        venta_id=venta["id"],
        numero=numero,
        comprobante_numero=numero_comprobante,
        items=[
            VentaItemOut(
                variante_id=item.variante_id,
                sku=info["sku"],
                producto=info["producto"],
                talla=info["talla"],
                color=info["color"],
                cantidad=item.cantidad,
                precio_unitario=float(info["precio"]),
                subtotal=float(subtotal_item),
            )
            for item, info, subtotal_item in aceptados
        ],
        rechazados=rechazados,
        subtotal=float(subtotal),
        iva=float(iva),
        total=float(total),
        vuelto=vuelto,
    )
