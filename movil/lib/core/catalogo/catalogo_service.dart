import '../api.dart';
import 'catalogo_models.dart';

/// CU03: Consultar Catalogo (la vitrina publica).
class CatalogoService {
  Future<FiltrosOut> obtenerFiltros() async {
    final respuesta = await api.get('/catalogo/filtros');
    return FiltrosOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<List<ProductoOut>> listarProductos({
    String? categoriaSlug,
    String? q,
    String? temporadaId,
    int? tallaId,
    int? colorId,
    int limit = 20,
    int offset = 0,
  }) async {
    final respuesta = await api.get('/catalogo/productos', query: {
      'categoria_slug': categoriaSlug,
      'q': q,
      'temporada_id': temporadaId,
      'talla_id': tallaId,
      'color_id': colorId,
      'limit': limit,
      'offset': offset,
    });
    return comoLista(respuesta).map(ProductoOut.desdeJson).toList();
  }

  Future<ProductoDetalleOut> obtenerProducto(String slug) async {
    final respuesta = await api.get('/catalogo/productos/$slug');
    return ProductoDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }
}

final catalogoService = CatalogoService();
