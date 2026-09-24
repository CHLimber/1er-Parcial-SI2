import '../api.dart';
import '../config.dart';

/// Espejo de `backend/app/modules/catalogo/admin_schemas.py` (CU10).
class ImagenOut {
  ImagenOut({
    required this.id,
    required this.url,
    required this.uso,
    required this.formato,
    required this.colorId,
    required this.esPrincipal,
    required this.orden,
  });

  final String id;
  final String url;
  final String uso;
  final String? formato;
  final int? colorId;
  final bool esPrincipal;
  final int orden;

  factory ImagenOut.desdeJson(Map<String, dynamic> j) => ImagenOut(
        id: j['id'] as String,
        url: resolverUrlMedia(j['url'] as String)!,
        uso: j['uso'] as String,
        formato: j['formato'] as String?,
        colorId: j['color_id'] == null ? null : aEntero(j['color_id']),
        esPrincipal: j['es_principal'] as bool? ?? false,
        orden: aEntero(j['orden']),
      );
}

class VarianteAdminOut {
  VarianteAdminOut({
    required this.id,
    required this.sku,
    required this.codigoBarras,
    required this.tallaId,
    required this.talla,
    required this.colorId,
    required this.color,
    required this.codigoHex,
    required this.precio,
    required this.precioOferta,
    required this.activa,
    required this.stockFisico,
    required this.stockDisponible,
  });

  final String id;
  final String sku;
  final String? codigoBarras;
  final int tallaId;
  final String talla;
  final int colorId;
  final String color;
  final String codigoHex;
  final double? precio;
  final double? precioOferta;
  final bool activa;
  final int stockFisico;
  final int stockDisponible;

  factory VarianteAdminOut.desdeJson(Map<String, dynamic> j) => VarianteAdminOut(
        id: j['id'] as String,
        sku: j['sku'] as String,
        codigoBarras: j['codigo_barras'] as String?,
        tallaId: aEntero(j['talla_id']),
        talla: j['talla'] as String,
        colorId: aEntero(j['color_id']),
        color: j['color'] as String,
        codigoHex: j['codigo_hex'] as String,
        precio: aDoubleNulo(j['precio']),
        precioOferta: aDoubleNulo(j['precio_oferta']),
        activa: j['activa'] as bool? ?? true,
        stockFisico: aEntero(j['stock_fisico']),
        stockDisponible: aEntero(j['stock_disponible']),
      );
}

class ProductoAdminOut {
  ProductoAdminOut({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.slug,
    required this.descripcion,
    required this.categoriaId,
    required this.categoria,
    required this.marcaId,
    required this.marca,
    required this.proveedorId,
    required this.proveedor,
    required this.temporadaId,
    required this.temporada,
    required this.coleccionId,
    required this.coleccion,
    required this.material,
    required this.genero,
    required this.precioBase,
    required this.destacado,
    required this.activo,
    required this.variantesActivas,
    required this.stockTotal,
  });

  final String id;
  final String codigo;
  final String nombre;
  final String slug;
  final String? descripcion;
  final String categoriaId;
  final String categoria;
  final String? marcaId;
  final String? marca;
  final String? proveedorId;
  final String? proveedor;
  final String? temporadaId;
  final String? temporada;
  final String? coleccionId;
  final String? coleccion;
  final String? material;
  final String? genero;
  final double precioBase;
  final bool destacado;
  final bool activo;
  final int variantesActivas;
  final int stockTotal;

  factory ProductoAdminOut.desdeJson(Map<String, dynamic> j) => ProductoAdminOut(
        id: j['id'] as String,
        codigo: j['codigo'] as String,
        nombre: j['nombre'] as String,
        slug: j['slug'] as String,
        descripcion: j['descripcion'] as String?,
        categoriaId: j['categoria_id'] as String,
        categoria: j['categoria'] as String,
        marcaId: j['marca_id'] as String?,
        marca: j['marca'] as String?,
        proveedorId: j['proveedor_id'] as String?,
        proveedor: j['proveedor'] as String?,
        temporadaId: j['temporada_id'] as String?,
        temporada: j['temporada'] as String?,
        coleccionId: j['coleccion_id'] as String?,
        coleccion: j['coleccion'] as String?,
        material: j['material'] as String?,
        genero: j['genero'] as String?,
        precioBase: aDouble(j['precio_base']),
        destacado: j['destacado'] as bool? ?? false,
        activo: j['activo'] as bool? ?? true,
        variantesActivas: aEntero(j['variantes_activas']),
        stockTotal: aEntero(j['stock_total']),
      );
}

class ProductoAdminDetalleOut extends ProductoAdminOut {
  ProductoAdminDetalleOut({
    required super.id,
    required super.codigo,
    required super.nombre,
    required super.slug,
    required super.descripcion,
    required super.categoriaId,
    required super.categoria,
    required super.marcaId,
    required super.marca,
    required super.proveedorId,
    required super.proveedor,
    required super.temporadaId,
    required super.temporada,
    required super.coleccionId,
    required super.coleccion,
    required super.material,
    required super.genero,
    required super.precioBase,
    required super.destacado,
    required super.activo,
    required super.variantesActivas,
    required super.stockTotal,
    required this.variantes,
    required this.imagenes,
  });

  final List<VarianteAdminOut> variantes;
  final List<ImagenOut> imagenes;

  factory ProductoAdminDetalleOut.desdeJson(Map<String, dynamic> j) {
    final base = ProductoAdminOut.desdeJson(j);
    return ProductoAdminDetalleOut(
      id: base.id,
      codigo: base.codigo,
      nombre: base.nombre,
      slug: base.slug,
      descripcion: base.descripcion,
      categoriaId: base.categoriaId,
      categoria: base.categoria,
      marcaId: base.marcaId,
      marca: base.marca,
      proveedorId: base.proveedorId,
      proveedor: base.proveedor,
      temporadaId: base.temporadaId,
      temporada: base.temporada,
      coleccionId: base.coleccionId,
      coleccion: base.coleccion,
      material: base.material,
      genero: base.genero,
      precioBase: base.precioBase,
      destacado: base.destacado,
      activo: base.activo,
      variantesActivas: base.variantesActivas,
      stockTotal: base.stockTotal,
      variantes: comoLista(j['variantes']).map(VarianteAdminOut.desdeJson).toList(),
      imagenes: comoLista(j['imagenes']).map(ImagenOut.desdeJson).toList(),
    );
  }
}

class CategoriaAdminOut {
  CategoriaAdminOut({
    required this.id,
    required this.nombre,
    required this.slug,
    required this.categoriaPadreId,
    required this.categoriaPadre,
    required this.imagenUrl,
    required this.orden,
    required this.activa,
    required this.productos,
  });

  final String id;
  final String nombre;
  final String slug;
  final String? categoriaPadreId;
  final String? categoriaPadre;
  final String? imagenUrl;
  final int orden;
  final bool activa;
  final int productos;

  factory CategoriaAdminOut.desdeJson(Map<String, dynamic> j) => CategoriaAdminOut(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        slug: j['slug'] as String,
        categoriaPadreId: j['categoria_padre_id'] as String?,
        categoriaPadre: j['categoria_padre'] as String?,
        imagenUrl: resolverUrlMedia(j['imagen_url'] as String?),
        orden: aEntero(j['orden']),
        activa: j['activa'] as bool? ?? true,
        productos: aEntero(j['productos']),
      );
}

class MarcaAdminOut {
  MarcaAdminOut({required this.id, required this.nombre, required this.logoUrl});

  final String id;
  final String nombre;
  final String? logoUrl;

  factory MarcaAdminOut.desdeJson(Map<String, dynamic> j) => MarcaAdminOut(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        logoUrl: j['logo_url'] as String?,
      );
}

class OpcionOut {
  OpcionOut({required this.id, required this.nombre});

  final String id;
  final String nombre;

  factory OpcionOut.desdeJson(Map<String, dynamic> j) =>
      OpcionOut(id: j['id'] as String, nombre: j['nombre'] as String);
}

class TemporadaAdminOut {
  TemporadaAdminOut({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.fechaInicio,
    required this.fechaFin,
  });

  final String id;
  final String nombre;
  final String tipo;
  final String fechaInicio;
  final String fechaFin;

  factory TemporadaAdminOut.desdeJson(Map<String, dynamic> j) => TemporadaAdminOut(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        tipo: j['tipo'] as String,
        fechaInicio: j['fecha_inicio'] as String,
        fechaFin: j['fecha_fin'] as String,
      );
}

class ColeccionOut {
  ColeccionOut({required this.id, required this.nombre, required this.temporadaId});

  final String id;
  final String nombre;
  final String temporadaId;

  factory ColeccionOut.desdeJson(Map<String, dynamic> j) => ColeccionOut(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        temporadaId: j['temporada_id'] as String,
      );
}

class TallaAdminOut {
  TallaAdminOut({required this.id, required this.codigo, required this.tipo});

  final int id;
  final String codigo;
  final String tipo;

  factory TallaAdminOut.desdeJson(Map<String, dynamic> j) => TallaAdminOut(
        id: aEntero(j['id']),
        codigo: j['codigo'] as String,
        tipo: j['tipo'] as String,
      );
}

class ColorAdminOut {
  ColorAdminOut({required this.id, required this.nombre, required this.codigoHex});

  final int id;
  final String nombre;
  final String codigoHex;

  factory ColorAdminOut.desdeJson(Map<String, dynamic> j) => ColorAdminOut(
        id: aEntero(j['id']),
        nombre: j['nombre'] as String,
        codigoHex: j['codigo_hex'] as String,
      );
}

/// Todo lo que el formulario de alta de prenda necesita en un solo viaje.
class ReferenciasOut {
  ReferenciasOut({
    required this.categorias,
    required this.marcas,
    required this.proveedores,
    required this.temporadas,
    required this.colecciones,
    required this.tallas,
    required this.colores,
    required this.generos,
  });

  final List<CategoriaAdminOut> categorias;
  final List<MarcaAdminOut> marcas;
  final List<OpcionOut> proveedores;
  final List<TemporadaAdminOut> temporadas;
  final List<ColeccionOut> colecciones;
  final List<TallaAdminOut> tallas;
  final List<ColorAdminOut> colores;
  final List<String> generos;

  factory ReferenciasOut.desdeJson(Map<String, dynamic> j) => ReferenciasOut(
        categorias: comoLista(j['categorias']).map(CategoriaAdminOut.desdeJson).toList(),
        marcas: comoLista(j['marcas']).map(MarcaAdminOut.desdeJson).toList(),
        proveedores: comoLista(j['proveedores']).map(OpcionOut.desdeJson).toList(),
        temporadas: comoLista(j['temporadas']).map(TemporadaAdminOut.desdeJson).toList(),
        colecciones: comoLista(j['colecciones']).map(ColeccionOut.desdeJson).toList(),
        tallas: comoLista(j['tallas']).map(TallaAdminOut.desdeJson).toList(),
        colores: comoLista(j['colores']).map(ColorAdminOut.desdeJson).toList(),
        generos: (j['generos'] as List? ?? const []).map((g) => g.toString()).toList(),
      );
}

/// Cuerpo de alta/edicion de prenda.
class ProductoIn {
  ProductoIn({
    required this.codigo,
    required this.nombre,
    this.descripcion,
    required this.categoriaId,
    this.marcaId,
    this.proveedorId,
    this.temporadaId,
    this.coleccionId,
    this.material,
    this.genero,
    required this.precioBase,
    this.destacado = false,
  });

  final String codigo;
  final String nombre;
  final String? descripcion;
  final String categoriaId;
  final String? marcaId;
  final String? proveedorId;
  final String? temporadaId;
  final String? coleccionId;
  final String? material;
  final String? genero;
  final double precioBase;
  final bool destacado;

  String? _oNulo(String? v) => (v == null || v.isEmpty) ? null : v;

  Map<String, dynamic> aJson() => {
        'codigo': codigo,
        'nombre': nombre,
        'descripcion': _oNulo(descripcion),
        'categoria_id': categoriaId,
        'marca_id': marcaId,
        'proveedor_id': proveedorId,
        'temporada_id': temporadaId,
        'coleccion_id': coleccionId,
        'material': _oNulo(material),
        'genero': genero,
        'precio_base': precioBase.toStringAsFixed(2),
        'destacado': destacado,
      };
}

/// CU10 - Promociones (PENDIENTES.txt 2.1).
class PromocionAdminOut {
  PromocionAdminOut({
    required this.id,
    required this.nombre,
    required this.codigoCupon,
    required this.tipo,
    required this.valor,
    required this.alcance,
    required this.categoriaId,
    required this.categoria,
    required this.temporadaId,
    required this.temporada,
    required this.montoMinimo,
    required this.fechaInicio,
    required this.fechaFin,
    required this.usoMaximo,
    required this.usosActuales,
    required this.activa,
  });

  final String id;
  final String nombre;
  final String codigoCupon;
  final String tipo;
  final double valor;
  final String alcance;
  final String? categoriaId;
  final String? categoria;
  final String? temporadaId;
  final String? temporada;
  final double? montoMinimo;
  final String fechaInicio;
  final String fechaFin;
  final int? usoMaximo;
  final int usosActuales;
  final bool activa;

  factory PromocionAdminOut.desdeJson(Map<String, dynamic> j) => PromocionAdminOut(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        codigoCupon: j['codigo_cupon'] as String,
        tipo: j['tipo'] as String,
        valor: aDouble(j['valor']),
        alcance: j['alcance'] as String,
        categoriaId: j['categoria_id'] as String?,
        categoria: j['categoria'] as String?,
        temporadaId: j['temporada_id'] as String?,
        temporada: j['temporada'] as String?,
        montoMinimo: aDoubleNulo(j['monto_minimo']),
        fechaInicio: j['fecha_inicio'] as String,
        fechaFin: j['fecha_fin'] as String,
        usoMaximo: j['uso_maximo'] == null ? null : aEntero(j['uso_maximo']),
        usosActuales: aEntero(j['usos_actuales']),
        activa: j['activa'] as bool? ?? true,
      );
}

/// Cuerpo de alta/edicion de promocion.
class PromocionIn {
  PromocionIn({
    required this.nombre,
    required this.codigoCupon,
    required this.tipo,
    required this.valor,
    this.alcance = 'TODO',
    this.categoriaId,
    this.temporadaId,
    this.montoMinimo,
    required this.fechaInicio,
    required this.fechaFin,
    this.usoMaximo,
  });

  final String nombre;
  final String codigoCupon;
  final String tipo;
  final double valor;
  final String alcance;
  final String? categoriaId;
  final String? temporadaId;
  final double? montoMinimo;
  final String fechaInicio;
  final String fechaFin;
  final int? usoMaximo;

  Map<String, dynamic> aJson() => {
        'nombre': nombre,
        'codigo_cupon': codigoCupon,
        'tipo': tipo,
        'valor': valor.toStringAsFixed(2),
        'alcance': alcance,
        'categoria_id': alcance == 'CATEGORIA' ? categoriaId : null,
        'temporada_id': alcance == 'TEMPORADA' ? temporadaId : null,
        'monto_minimo': montoMinimo?.toStringAsFixed(2),
        'fecha_inicio': fechaInicio,
        'fecha_fin': fechaFin,
        'uso_maximo': usoMaximo,
      };
}

/// Cuerpo de alta/edicion de variante. Si precio va vacio, hereda `producto.precio_base`.
class VarianteIn {
  VarianteIn({
    required this.tallaId,
    required this.colorId,
    required this.sku,
    this.codigoBarras,
    this.precio,
    this.precioOferta,
  });

  final int tallaId;
  final int colorId;
  final String sku;
  final String? codigoBarras;
  final double? precio;
  final double? precioOferta;

  Map<String, dynamic> aJson() => {
        'talla_id': tallaId,
        'color_id': colorId,
        'sku': sku,
        'codigo_barras': (codigoBarras?.isEmpty ?? true) ? null : codigoBarras,
        'precio': precio?.toStringAsFixed(2),
        'precio_oferta': precioOferta?.toStringAsFixed(2),
      };
}
