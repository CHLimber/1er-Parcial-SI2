import '../api.dart';
import 'recomendaciones_models.dart';

/// CU17 - Recibir Recomendaciones de IA. "IA" es un algoritmo sobre el historial del
/// cliente (compras y reservas por categoria), no un modelo de lenguaje -- mismo
/// endpoint `GET /recomendaciones` que consume la web, solo para CLIENTE.
class RecomendacionesService {
  Future<List<ProductoRecomendadoOut>> obtener({int limite = 8}) async {
    final respuesta = await api.get('/recomendaciones', query: {'limite': limite});
    return comoLista(respuesta).map(ProductoRecomendadoOut.desdeJson).toList();
  }
}

final recomendacionesService = RecomendacionesService();
