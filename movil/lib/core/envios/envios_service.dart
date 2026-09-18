import '../api.dart';
import 'envios_models.dart';

/// CU20 - delivery. La cara de la clienta (`/envios`) y el panel de despacho
/// (`/admin/envios`), con la misma division que en el backend.
class EnviosService {
  // --- cliente ---

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

  // --- panel de despacho ---

  Future<List<EnvioAdminOut>> listar({
    String? estado,
    String? sucursalId,
    bool soloAbiertos = false,
  }) async {
    final respuesta = await api.get('/admin/envios', query: {
      'estado': estado,
      'sucursal_id': sucursalId,
      'solo_abiertos': soloAbiertos ? true : null,
    });
    return comoLista(respuesta).map(EnvioAdminOut.desdeJson).toList();
  }

  Future<ResumenEnvios> resumen({String? sucursalId}) async {
    final respuesta = await api.get('/admin/envios/resumen', query: {'sucursal_id': sucursalId});
    return ResumenEnvios.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<EnvioAdminDetalle> detalle(String envioId) async {
    final respuesta = await api.get('/admin/envios/$envioId');
    return EnvioAdminDetalle.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<EnvioAdminOut> cambiarEstado(String envioId, String estado, {String? observacion}) async {
    final respuesta = await api.post(
      '/admin/envios/$envioId/estado',
      cuerpo: {'estado': estado, 'observacion': observacion},
    );
    return EnvioAdminOut.desdeJson(respuesta as Map<String, dynamic>);
  }
}

final enviosService = EnviosService();
