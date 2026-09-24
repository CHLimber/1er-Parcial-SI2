import 'package:flutter_stripe/flutter_stripe.dart';

import '../api.dart';
import 'ventas_models.dart';

/// CU05 (compra web/app), CU06 (pago electronico) y CU07 (venta presencial).
class VentasService {
  /// Crea la venta y el pago en PENDIENTE. `canal: MOVIL` deja el rastro de que la
  /// compra nacio en la app (el ENUM canal_venta ya contempla WEB y MOVIL).
  Future<CheckoutOut> checkout({
    String? sucursalId,
    String entrega = 'RETIRO_SUCURSAL',
    String? direccionId,
    required String metodoPago,
    String? codigoCupon,
  }) async {
    final respuesta = await api.post('/ventas/checkout', cuerpo: {
      'sucursal_id': sucursalId,
      'entrega': entrega,
      'direccion_id': direccionId,
      'metodo_pago': metodoPago,
      'codigo_cupon': (codigoCupon?.isEmpty ?? true) ? null : codigoCupon,
      'canal': 'MOVIL',
    });
    return CheckoutOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<VentaOut> obtenerVenta(String ventaId) async {
    final respuesta = await api.get('/ventas/$ventaId');
    return VentaOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<List<VentaResumenOut>> listarMisCompras() async {
    final respuesta = await api.get('/ventas');
    return comoLista(respuesta).map(VentaResumenOut.desdeJson).toList();
  }

  /// CU07: venta presencial en caja.
  Future<VentaPosOut> registrarVentaPos({
    required List<Map<String, dynamic>> items,
    required String metodoPago,
    double? montoRecibido,
  }) async {
    final respuesta = await api.post('/ventas/pos', cuerpo: {
      'items': items,
      'metodo_pago': metodoPago,
      'monto_recibido': montoRecibido,
    });
    return VentaPosOut.desdeJson(respuesta as Map<String, dynamic>);
  }
}

/// Espejo de `ConfigPagoOut` (backend). La publishable key de Stripe no es secreta -- esta
/// pensada para viajar al cliente -- asi que se pide por un endpoint publico en vez de
/// hornearla en el build de la app, y asi cambia por entorno (local/Railway) sin recompilar.
class ConfigPagoOut {
  ConfigPagoOut({required this.stripePublishableKey});

  final String stripePublishableKey;

  factory ConfigPagoOut.desdeJson(Map<String, dynamic> j) =>
      ConfigPagoOut(stripePublishableKey: j['stripe_publishable_key'] as String);
}

/// CU06. Stripe confirma por webhook firmado desde sus servidores. QR ya no tiene un webhook
/// que la app pueda disparar (antes la propia clienta "aprobaba" su pago): ahora solo informa
/// que pago y el cajero de la sucursal lo verifica desde caja (2.19.1.c).
class PagosService {
  Future<InformarPagoOut> informarPagoQr(String ventaId, {String? referencia}) async {
    final respuesta = await api.post('/pagos/qr/$ventaId/informar', cuerpo: {
      'referencia': (referencia?.trim().isEmpty ?? true) ? null : referencia!.trim(),
    });
    return InformarPagoOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<ConfigPagoOut> obtenerConfig() async {
    final respuesta = await api.get('/pagos/config');
    return ConfigPagoOut.desdeJson(respuesta as Map<String, dynamic>);
  }
}

bool _stripeInicializado = false;

/// CU06 canal MOVIL: el SDK nativo de Stripe (paquete `flutter_stripe`) necesita la publishable
/// key antes de poder mostrar el PaymentSheet. Se pide una sola vez (perezoso, recien cuando la
/// clienta elige pagar con Stripe) y se cachea en este flag -- no hace falta bloquear el arranque
/// de la app ni repetir el pedido en cada compra.
Future<void> asegurarStripeInicializado() async {
  if (_stripeInicializado) return;
  final config = await pagosService.obtenerConfig();
  Stripe.publishableKey = config.stripePublishableKey;
  await Stripe.instance.applySettings();
  _stripeInicializado = true;
}


final ventasService = VentasService();
final pagosService = PagosService();
