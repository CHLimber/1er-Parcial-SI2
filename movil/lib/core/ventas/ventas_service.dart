import 'dart:math';

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

/// CU06. Stripe confirma por webhook firmado desde sus servidores; QR no tiene
/// sandbox real, asi que la pantalla de pago simulado manda el resultado a mano. El
/// backend usa `evento_id` como clave de idempotencia (tabla `evento_pasarela`).
class PagosService {
  Future<WebhookOut> simularWebhook(
    String pasarela,
    String idTransaccion,
    String estado,
  ) async {
    final respuesta = await api.post('/pagos/webhook/$pasarela', cuerpo: {
      'evento_id': generarUuidV4(),
      'id_transaccion': idTransaccion,
      'estado': estado,
    });
    return WebhookOut.desdeJson(respuesta as Map<String, dynamic>);
  }
}

/// UUID v4 aleatorio (el equivalente de `crypto.randomUUID()` del navegador).
String generarUuidV4() {
  final azar = Random.secure();
  final bytes = List<int>.generate(16, (_) => azar.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}'
      '-${hex.substring(16, 20)}-${hex.substring(20)}';
}

final ventasService = VentasService();
final pagosService = PagosService();
