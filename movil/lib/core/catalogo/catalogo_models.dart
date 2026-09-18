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

class GaleriaImagenOut {
  GaleriaImagenOut({required this.color, required this.codigoHex, required this.url});

  final String? color;
  final String? codigoHex;
  final String url;

  factory GaleriaImagenOut.desdeJson(Map<String, dynamic> j) => GaleriaImagenOut(
        color: j['color'] as String?,
        codigoHex: j['codigo_hex'] as String?,
        url: resolverUrlMedia(j['url'] as String)!,
      );
}

/// Un anclaje normalizado (0-1) sobre el PNG de un overlay AR. Ver
/// `IMAGENES_AR.txt` punto 4 para el formato completo.
class AnclajePunto {
  AnclajePunto({required this.x, required this.y});

  final double x;
  final double y;

  factory AnclajePunto.desdeJson(Map<String, dynamic> j) =>
      AnclajePunto(x: aDouble(j['x']), y: aDouble(j['y']));
}

/// CU16: asset de realidad aumentada de una prenda. Espejo de `ImagenArOut`
/// en `backend/app/modules/catalogo/schemas.py`.
class ImagenArOut {
  ImagenArOut({
    required this.uso,
    required this.formato,
    required this.url,
    required this.color,
    required this.codigoHex,
    required this.hombroIzq,
    required this.hombroDer,
    required this.cintura,
    required this.escalaBase,
  });

  final String uso;
  final String? formato;
  final String url;
  final String? color;
  final String? codigoHex;
  final AnclajePunto? hombroIzq;
  final AnclajePunto? hombroDer;
  final AnclajePunto? cintura;
  final double? escalaBase;

  bool get esOverlay => uso == 'AR_OVERLAY';
  bool get esModelo3d => uso == 'AR_MODELO';
  bool get tieneAnclajes => hombroIzq != null && hombroDer != null && cintura != null;

  factory ImagenArOut.desdeJson(Map<String, dynamic> j) {
    final anclajes = j['anclajes'] as Map<String, dynamic>?;
    AnclajePunto? punto(String clave) {
      final valor = anclajes?[clave] as Map<String, dynamic>?;
      return valor == null ? null : AnclajePunto.desdeJson(valor);
    }

    return ImagenArOut(
      uso: j['uso'] as String,
      formato: j['formato'] as String?,
      url: resolverUrlMedia(j['url'] as String)!,
      color: j['color'] as String?,
      codigoHex: j['codigo_hex'] as String?,
      hombroIzq: punto('hombro_izq'),
      hombroDer: punto('hombro_der'),
      cintura: punto('cintura'),
      escalaBase: j['escala_base'] == null ? null : aDouble(j['escala_base']),
    );
  }
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
    required this.galeria,
    required this.ar,
  });

  final String? material;
  final List<VarianteOut> variantes;
  final List<GaleriaImagenOut> galeria;
  final List<ImagenArOut> ar;

  /// CU16: el asset de nivel 2 (modelo 3D) de esta prenda, si existe.
  ImagenArOut? get modelo3d {
    for (final item in ar) {
      if (item.esModelo3d) return item;
    }
    return null;
  }

  /// CU16: el overlay de nivel 1 (2D, anclado a hombros) de esta prenda, si existe.
  ImagenArOut? get overlay {
    for (final item in ar) {
      if (item.esOverlay && item.tieneAnclajes) return item;
    }
    return null;
  }

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
      galeria: comoLista(j['galeria']).map(GaleriaImagenOut.desdeJson).toList(),
      ar: comoLista(j['ar']).map(ImagenArOut.desdeJson).toList(),
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
