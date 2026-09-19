import '../catalogo/catalogo_models.dart';

/// Espejo de `backend/app/modules/recomendaciones/schemas.py` (CU17). El campo
/// [motivo] explica por que se sugiere la prenda (categoria favorita, destacado o
/// tendencia); no existe en el `ProductoOut` comun de CU03.
class ProductoRecomendadoOut extends ProductoOut {
  ProductoRecomendadoOut({
    required super.id,
    required super.codigo,
    required super.nombre,
    required super.slug,
    required super.descripcion,
    required super.precioBase,
    required super.genero,
    required super.categoria,
    required super.categoriaSlug,
    required super.marca,
    required super.destacado,
    required super.imagenUrl,
    required super.tallas,
    required super.agotado,
    required this.motivo,
  });

  final String motivo;

  factory ProductoRecomendadoOut.desdeJson(Map<String, dynamic> j) {
    final base = ProductoOut.desdeJson(j);
    return ProductoRecomendadoOut(
      id: base.id,
      codigo: base.codigo,
      nombre: base.nombre,
      slug: base.slug,
      descripcion: base.descripcion,
      precioBase: base.precioBase,
      genero: base.genero,
      categoria: base.categoria,
      categoriaSlug: base.categoriaSlug,
      marca: base.marca,
      destacado: base.destacado,
      imagenUrl: base.imagenUrl,
      tallas: base.tallas,
      agotado: base.agotado,
      motivo: j['motivo'] as String,
    );
  }
}
