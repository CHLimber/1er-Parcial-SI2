import '../api.dart';
import 'catalogo_admin_models.dart';

/// CU10: Gestionar Catalogo (prendas, variantes, imagenes, categorias y marcas).
class CatalogoAdminService {
  Future<ReferenciasOut> obtenerReferencias() async {
    final respuesta = await api.get('/admin/catalogo/referencias');
    return ReferenciasOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<List<ProductoAdminOut>> listarProductos({
    String? q,
    String? categoriaId,
    bool? activo,
  }) async {
    final respuesta = await api.get('/admin/catalogo/productos', query: {
      'q': q,
      'categoria_id': categoriaId,
      'activo': activo,
    });
    return comoLista(respuesta).map(ProductoAdminOut.desdeJson).toList();
  }

  Future<ProductoAdminDetalleOut> obtenerProducto(String productoId) async {
    final respuesta = await api.get('/admin/catalogo/productos/$productoId');
    return ProductoAdminDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<ProductoAdminDetalleOut> crearProducto(ProductoIn datos) async {
    final respuesta = await api.post('/admin/catalogo/productos', cuerpo: datos.aJson());
    return ProductoAdminDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<ProductoAdminDetalleOut> actualizarProducto(String productoId, ProductoIn datos) async {
    final respuesta =
        await api.put('/admin/catalogo/productos/$productoId', cuerpo: datos.aJson());
    return ProductoAdminDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<ProductoAdminDetalleOut> cambiarEstadoProducto(String productoId, bool activo) async {
    final respuesta = await api
        .patch('/admin/catalogo/productos/$productoId/estado', cuerpo: {'activo': activo});
    return ProductoAdminDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<VarianteAdminOut> crearVariante(String productoId, VarianteIn datos) async {
    final respuesta = await api.post(
      '/admin/catalogo/productos/$productoId/variantes',
      cuerpo: datos.aJson(),
    );
    return VarianteAdminOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<VarianteAdminOut> actualizarVariante(String varianteId, VarianteIn datos) async {
    final respuesta =
        await api.put('/admin/catalogo/variantes/$varianteId', cuerpo: datos.aJson());
    return VarianteAdminOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<VarianteAdminOut> cambiarEstadoVariante(String varianteId, bool activa) async {
    final respuesta = await api
        .patch('/admin/catalogo/variantes/$varianteId/estado', cuerpo: {'activo': activa});
    return VarianteAdminOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<ImagenOut> agregarImagen(
    String productoId, {
    required String url,
    String uso = 'CATALOGO',
    int? colorId,
    bool esPrincipal = false,
    int orden = 0,
  }) async {
    final respuesta = await api.post('/admin/catalogo/productos/$productoId/imagenes', cuerpo: {
      'url': url,
      'uso': uso,
      'color_id': colorId,
      'es_principal': esPrincipal,
      'orden': orden,
    });
    return ImagenOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<void> eliminarImagen(String imagenId) =>
      api.delete('/admin/catalogo/imagenes/$imagenId');

  Future<List<CategoriaAdminOut>> listarCategorias() async {
    final respuesta = await api.get('/admin/catalogo/categorias');
    return comoLista(respuesta).map(CategoriaAdminOut.desdeJson).toList();
  }

  Future<CategoriaAdminOut> crearCategoria({
    required String nombre,
    String? categoriaPadreId,
    String? imagenUrl,
    int orden = 0,
  }) async {
    final respuesta = await api.post('/admin/catalogo/categorias', cuerpo: {
      'nombre': nombre,
      'categoria_padre_id': categoriaPadreId,
      'imagen_url': (imagenUrl?.isEmpty ?? true) ? null : imagenUrl,
      'orden': orden,
    });
    return CategoriaAdminOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<CategoriaAdminOut> actualizarCategoria(
    String categoriaId, {
    required String nombre,
    String? categoriaPadreId,
    String? imagenUrl,
    int orden = 0,
  }) async {
    final respuesta = await api.put('/admin/catalogo/categorias/$categoriaId', cuerpo: {
      'nombre': nombre,
      'categoria_padre_id': categoriaPadreId,
      'imagen_url': (imagenUrl?.isEmpty ?? true) ? null : imagenUrl,
      'orden': orden,
    });
    return CategoriaAdminOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<CategoriaAdminOut> cambiarEstadoCategoria(String categoriaId, bool activa) async {
    final respuesta = await api
        .patch('/admin/catalogo/categorias/$categoriaId/estado', cuerpo: {'activa': activa});
    return CategoriaAdminOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<MarcaAdminOut> crearMarca(String nombre, {String? logoUrl}) async {
    final respuesta = await api.post('/admin/catalogo/marcas', cuerpo: {
      'nombre': nombre,
      'logo_url': (logoUrl?.isEmpty ?? true) ? null : logoUrl,
    });
    return MarcaAdminOut.desdeJson(respuesta as Map<String, dynamic>);
  }
}

final catalogoAdminService = CatalogoAdminService();
