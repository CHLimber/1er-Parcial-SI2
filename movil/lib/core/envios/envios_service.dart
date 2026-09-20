import '../api.dart';
import 'envios_models.dart';

/// CU20 - delivery. Solo la cara de la clienta (`/envios`): cotizar y seguir su propio
/// pedido. El reparto lo hace un servicio externo, no hay panel de despacho en la app.
class EnviosService {
  Future<CotizacionEnvio> cotizar({
    required String sucursalId,
    String? direccionId,
    double? latitud,
    double? longitud,
    double montoPedido = 0,
  }) async {
    final respuesta = await api.post('/envios/cotizar', cuerpo: {
      'sucursal_id': sucursalId,
      'direccion_id': direccionId,
      'latitud': latitud,
      'longitud': longitud,
      'monto_pedido': montoPedido,
    });
    return CotizacionEnvio.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<EnvioOut> envioDeVenta(String ventaId) async {
    final respuesta = await api.get('/envios/venta/$ventaId');
    return EnvioOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<List<EnvioOut>> misEnvios() async {
    final respuesta = await api.get('/envios/mis');
    return comoLista(respuesta).map(EnvioOut.desdeJson).toList();
  }
}

final enviosService = EnviosService();
