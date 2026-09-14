import '../api.dart';
import '../config.dart';

/// Espejo de `backend/app/modules/catalogo/schemas.py` (CU03).
class ProductoOut {
  ProductoOut({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.slug,
    required this.descripcion,
    required this.precioBase,
    required this.genero,
    required this.categoria,
    required this.categoriaSlug,
    required this.marca,
    required this.destacado,
    required this.imagenUrl,
    required this.tallas,
    required this.agotado,
  });

  final String id;
  final String codigo;
  final String nombre;
  final String slug;
  final String? descripcion;
  final double precioBase;
  final String? genero;
  final String categoria;
  final String categoriaSlug;
  final String? marca;
  final bool destacado;
  final String? imagenUrl;
  final List<String> tallas;
  final bool agotado;

  factory ProductoOut.desdeJson(Map<String, dynamic> j) => ProductoOut(
        id: j['id'] as String,
        codigo: j['codigo'] as String,
        nombre: j['nombre'] as String,
        slug: j['slug'] as String,
        descripcion: j['descripcion'] as String?,
        precioBase: aDouble(j['precio_base']),
        genero: j['genero'] as String?,
        categoria: j['categoria'] as String,
        categoriaSlug: j['categoria_slug'] as String,
        marca: j['marca'] as String?,
        destacado: j['destacado'] as bool? ?? false,
        imagenUrl: resolverUrlMedia(j['imagen_url'] as String?),
        tallas: (j['tallas'] as List? ?? const []).map((t) => t.toString()).toList(),
        agotado: j['agotado'] as bool? ?? false,
      );
}

class DisponibilidadSucursalOut {
  DisponibilidadSucursalOut({
    required this.sucursalId,
    required this.sucursal,
    required this.ciudad,
    required this.disponible,
    required this.situacion,
  });

  final String sucursalId;
  final String sucursal;
  final String ciudad;
  final int disponible;
  final String situacion;

  factory DisponibilidadSucursalOut.desdeJson(Map<String, dynamic> j) =>
      DisponibilidadSucursalOut(
        sucursalId: j['sucursal_id'] as String,
        sucursal: j['sucursal'] as String,
        ciudad: j['ciudad'] as String,
        disponible: aEntero(j['disponible']),
        situacion: j['situacion'] as String,
      );
}

class VarianteOut {
  VarianteOut({
    required this.id,
    required this.sku,
    required this.talla,
    required this.color,
    required this.codigoHex,
    required this.precio,
    required this.disponibilidad,
    required this.imagenUrl,
  });

  final String id;
  final String sku;
  final String talla;
  final String color;
  final String codigoHex;
  final double precio;
  final List<DisponibilidadSucursalOut> disponibilidad;
  final String? imagenUrl;

  int get totalDisponible =>
      disponibilidad.fold(0, (suma, sucursal) => suma + sucursal.disponible);

  int disponibleEn(String sucursalId) {
    for (final fila in disponibilidad) {
      if (fila.sucursalId == sucursalId) return fila.disponible;
    }
    return 0;
  }

  factory VarianteOut.desdeJson(Map<String, dynamic> j) => VarianteOut(
        id: j['id'] as String,
        sku: j['sku'] as String,
        talla: j['talla'] as String,
        color: j['color'] as String,
        codigoHex: j['codigo_hex'] as String,
        precio: aDouble(j['precio']),
        disponibilidad:
            comoLista(j['disponibilidad']).map(DisponibilidadSucursalOut.desdeJson).toList(),
        imagenUrl: resolverUrlMedia(j['imagen_url'] as String?),
      );
}

class ProductoDetalleOut extends ProductoOut {
  ProductoDetalleOut({
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
    required this.material,
    required this.variantes,
  });

  final String? material;
  final List<VarianteOut> variantes;

  factory ProductoDetalleOut.desdeJson(Map<String, dynamic> j) {
    final base = ProductoOut.desdeJson(j);
    return ProductoDetalleOut(
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
      material: j['material'] as String?,
      variantes: comoLista(j['variantes']).map(VarianteOut.desdeJson).toList(),
    );
  }
}

class CategoriaOut {
  CategoriaOut({
    required this.id,
    required this.nombre,
    required this.slug,
    this.categoriaPadreId,
  });

  final String id;
  final String nombre;
  final String slug;
  final String? categoriaPadreId;

  factory CategoriaOut.desdeJson(Map<String, dynamic> j) => CategoriaOut(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        slug: j['slug'] as String,
        categoriaPadreId: j['categoria_padre_id'] as String?,
      );
}

class TallaOut {
  TallaOut({required this.id, required this.codigo, required this.tipo});

  final int id;
  final String codigo;
  final String tipo;

  factory TallaOut.desdeJson(Map<String, dynamic> j) => TallaOut(
        id: aEntero(j['id']),
        codigo: j['codigo'] as String,
        tipo: j['tipo'] as String,
      );
}

class ColorOut {
  ColorOut({required this.id, required this.nombre, required this.codigoHex});

  final int id;
  final String nombre;
  final String codigoHex;

  factory ColorOut.desdeJson(Map<String, dynamic> j) => ColorOut(
        id: aEntero(j['id']),
        nombre: j['nombre'] as String,
        codigoHex: j['codigo_hex'] as String,
      );
}

class TemporadaOut {
  TemporadaOut({required this.id, required this.nombre, required this.tipo});

  final String id;
  final String nombre;
  final String tipo;

  factory TemporadaOut.desdeJson(Map<String, dynamic> j) => TemporadaOut(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        tipo: j['tipo'] as String,
      );
}

class FiltrosOut {
  FiltrosOut({
    required this.categorias,
    required this.tallas,
    required this.colores,
    required this.temporadas,
  });

  final List<CategoriaOut> categorias;
  final List<TallaOut> tallas;
  final List<ColorOut> colores;
  final List<TemporadaOut> temporadas;

  factory FiltrosOut.desdeJson(Map<String, dynamic> j) => FiltrosOut(
        categorias: comoLista(j['categorias']).map(CategoriaOut.desdeJson).toList(),
        tallas: comoLista(j['tallas']).map(TallaOut.desdeJson).toList(),
        colores: comoLista(j['colores']).map(ColorOut.desdeJson).toList(),
        temporadas: comoLista(j['temporadas']).map(TemporadaOut.desdeJson).toList(),
      );
}
