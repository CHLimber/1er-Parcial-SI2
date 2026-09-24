import '../api.dart';

/// Espejo de `backend/app/modules/ventas/schemas.py` (CU05, CU06, CU07).
class CheckoutOut {
  CheckoutOut({
    required this.ventaId,
    required this.numero,
    required this.pagoId,
    required this.pasarela,
    required this.idTransaccion,
    required this.urlPago,
    required this.clientSecret,
    required this.subtotal,
    required this.descuento,
    required this.costoEnvio,
    required this.iva,
    required this.total,
    required this.estado,
  });

  final String ventaId;
  final String numero;
  final String pagoId;

  /// STRIPE o QR; null si el metodo fue EFECTIVO (no hay pasarela de por medio).
  final String? pasarela;
  final String? idTransaccion;

  /// STRIPE nunca la manda (se paga inline, con clientSecret); QR devuelve la ruta interna
  /// `/pago-simulado/{venta_id}` (pantalla nativa donde la clienta informa que pago); EFECTIVO
  /// devuelve `/compra/{venta_id}`: queda PENDIENTE hasta que el cajero lo cobra (2.19.1.b).
  final String? urlPago;

  /// Solo STRIPE: el PaymentIntent que `Stripe.instance.initPaymentSheet()` usa para mostrar el
  /// PaymentSheet nativo dentro de la app (CU06, paquete `flutter_stripe`).
  final String? clientSecret;
  final double subtotal;
  final double descuento;

  /// CU20: tarifa del delivery ya cobrada. 0 si se retira en tienda o si el envio fue gratis.
  final double costoEnvio;
  final double iva;
  final double total;
  final String estado;

  bool get esPagoSimulado => urlPago != null && urlPago!.startsWith('/pago-simulado');

  factory CheckoutOut.desdeJson(Map<String, dynamic> j) => CheckoutOut(
        ventaId: j['venta_id'] as String,
        numero: j['numero'] as String,
        pagoId: j['pago_id'] as String,
        pasarela: j['pasarela'] as String?,
        idTransaccion: j['id_transaccion'] as String?,
        urlPago: j['url_pago'] as String?,
        clientSecret: j['client_secret'] as String?,
        subtotal: aDouble(j['subtotal']),
        descuento: aDouble(j['descuento']),
        costoEnvio: aDouble(j['costo_envio']),
        iva: aDouble(j['iva']),
        total: aDouble(j['total']),
        estado: j['estado'] as String,
      );
}

class VentaItemOut {
  VentaItemOut({
    required this.varianteId,
    required this.sku,
    required this.producto,
    required this.talla,
    required this.color,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotal,
  });

  final String varianteId;
  final String sku;
  final String producto;
  final String talla;
  final String color;
  final int cantidad;
  final double precioUnitario;
  final double subtotal;

  factory VentaItemOut.desdeJson(Map<String, dynamic> j) => VentaItemOut(
        varianteId: j['variante_id'] as String,
        sku: j['sku'] as String,
        producto: j['producto'] as String,
        talla: j['talla'] as String,
        color: j['color'] as String,
        cantidad: aEntero(j['cantidad']),
        precioUnitario: aDouble(j['precio_unitario']),
        subtotal: aDouble(j['subtotal']),
      );
}

class PagoOut {
  PagoOut({
    required this.id,
    required this.metodo,
    required this.pasarela,
    required this.monto,
    required this.estado,
    required this.idTransaccion,
    required this.creadoEn,
    required this.confirmadoEn,
    this.informadoEn,
    this.referenciaCliente,
  });

  final String id;
  final String metodo;
  final String? pasarela;
  final double monto;
  final String estado;
  final String? idTransaccion;
  final DateTime? creadoEn;
  final DateTime? confirmadoEn;

  /// 2.19.1.c, solo QR: cuando la clienta aviso "ya pague" y la referencia que dejo.
  final DateTime? informadoEn;
  final String? referenciaCliente;

  factory PagoOut.desdeJson(Map<String, dynamic> j) => PagoOut(
        id: j['id'] as String,
        metodo: j['metodo'] as String,
        pasarela: j['pasarela'] as String?,
        monto: aDouble(j['monto']),
        estado: j['estado'] as String,
        idTransaccion: j['id_transaccion'] as String?,
        creadoEn: aFechaNula(j['creado_en']),
        confirmadoEn: aFechaNula(j['confirmado_en']),
        informadoEn: aFechaNula(j['informado_en']),
        referenciaCliente: j['referencia_cliente'] as String?,
      );
}

class ComprobanteOut {
  ComprobanteOut({required this.numero, required this.tipo, required this.emitidoEn});

  final String numero;
  final String tipo;
  final DateTime? emitidoEn;

  factory ComprobanteOut.desdeJson(Map<String, dynamic> j) => ComprobanteOut(
        numero: j['numero'] as String,
        tipo: j['tipo'] as String,
        emitidoEn: aFechaNula(j['emitido_en']),
      );
}

class VentaOut {
  VentaOut({
    required this.id,
    required this.numero,
    required this.canal,
    required this.entrega,
    required this.estado,
    required this.sucursal,
    required this.subtotal,
    required this.descuento,
    required this.costoEnvio,
    required this.iva,
    required this.total,
    required this.fecha,
    required this.items,
    required this.pago,
    required this.comprobante,
  });

  final String id;
  final String numero;
  final String canal;
  final String entrega;
  final String estado;
  final String sucursal;
  final double subtotal;
  final double descuento;

  /// CU20: tarifa del delivery ya cobrada. 0 si se retira en tienda o si el envio fue gratis.
  final double costoEnvio;
  final double iva;
  final double total;
  final DateTime? fecha;
  final List<VentaItemOut> items;
  final PagoOut? pago;
  final ComprobanteOut? comprobante;

  factory VentaOut.desdeJson(Map<String, dynamic> j) => VentaOut(
        id: j['id'] as String,
        numero: j['numero'] as String,
        canal: j['canal'] as String,
        entrega: j['entrega'] as String,
        estado: j['estado'] as String,
        sucursal: j['sucursal'] as String,
        subtotal: aDouble(j['subtotal']),
        descuento: aDouble(j['descuento']),
        costoEnvio: aDouble(j['costo_envio']),
        iva: aDouble(j['iva']),
        total: aDouble(j['total']),
        fecha: aFechaNula(j['fecha']),
        items: comoLista(j['items']).map(VentaItemOut.desdeJson).toList(),
        pago: j['pago'] == null ? null : PagoOut.desdeJson(j['pago'] as Map<String, dynamic>),
        comprobante: j['comprobante'] == null
            ? null
            : ComprobanteOut.desdeJson(j['comprobante'] as Map<String, dynamic>),
      );
}

class VentaResumenOut {
  VentaResumenOut({
    required this.id,
    required this.numero,
    required this.canal,
    required this.estado,
    required this.total,
    required this.fecha,
    required this.sucursal,
  });

  final String id;
  final String numero;
  final String canal;
  final String estado;
  final double total;
  final DateTime? fecha;
  final String sucursal;

  factory VentaResumenOut.desdeJson(Map<String, dynamic> j) => VentaResumenOut(
        id: j['id'] as String,
        numero: j['numero'] as String,
        canal: j['canal'] as String,
        estado: j['estado'] as String,
        total: aDouble(j['total']),
        fecha: aFechaNula(j['fecha']),
        sucursal: j['sucursal'] as String,
      );
}

class ItemRechazadoPosOut {
  ItemRechazadoPosOut({required this.varianteId, required this.sku, required this.motivo});

  final String varianteId;
  final String sku;
  final String motivo;

  factory ItemRechazadoPosOut.desdeJson(Map<String, dynamic> j) => ItemRechazadoPosOut(
        varianteId: j['variante_id'] as String,
        sku: j['sku'] as String,
        motivo: j['motivo'] as String,
      );
}

/// Resultado de una venta presencial (CU07).
class VentaPosOut {
  VentaPosOut({
    required this.ventaId,
    required this.numero,
    required this.comprobanteNumero,
    required this.items,
    required this.rechazados,
    required this.subtotal,
    required this.iva,
    required this.total,
    required this.vuelto,
  });

  final String ventaId;
  final String numero;
  final String comprobanteNumero;
  final List<VentaItemOut> items;
  final List<ItemRechazadoPosOut> rechazados;
  final double subtotal;
  final double iva;
  final double total;
  final double? vuelto;

  factory VentaPosOut.desdeJson(Map<String, dynamic> j) => VentaPosOut(
        ventaId: j['venta_id'] as String,
        numero: j['numero'] as String,
        comprobanteNumero: j['comprobante_numero'] as String,
        items: comoLista(j['items']).map(VentaItemOut.desdeJson).toList(),
        rechazados: comoLista(j['rechazados']).map(ItemRechazadoPosOut.desdeJson).toList(),
        subtotal: aDouble(j['subtotal']),
        iva: aDouble(j['iva']),
        total: aDouble(j['total']),
        vuelto: aDoubleNulo(j['vuelto']),
      );
}

/// 2.19.1.c: respuesta de POST /pagos/qr/{venta_id}/informar. La clienta solo avisa que pago
/// el QR; quien aprueba es el cajero de la sucursal desde caja.
class InformarPagoOut {
  InformarPagoOut({
    required this.ventaId,
    required this.pagoId,
    required this.pagoEstado,
    required this.informadoEn,
    required this.referenciaCliente,
    required this.mensaje,
  });

  final String ventaId;
  final String pagoId;
  final String pagoEstado;
  final DateTime? informadoEn;
  final String? referenciaCliente;
  final String mensaje;

  factory InformarPagoOut.desdeJson(Map<String, dynamic> j) => InformarPagoOut(
        ventaId: j['venta_id'] as String,
        pagoId: j['pago_id'] as String,
        pagoEstado: j['pago_estado'] as String,
        informadoEn: aFechaNula(j['informado_en']),
        referenciaCliente: j['referencia_cliente'] as String?,
        mensaje: j['mensaje'] as String,
      );
}
