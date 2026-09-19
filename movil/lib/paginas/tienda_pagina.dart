import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../compartido/widgets.dart';
import '../core/auth/auth_service.dart';
import '../core/catalogo/catalogo_models.dart';
import '../core/catalogo/catalogo_service.dart';
import '../core/config.dart';
import '../core/errores.dart';
import '../core/recomendaciones/recomendaciones_models.dart';
import '../core/recomendaciones/recomendaciones_service.dart';
import '../core/tema.dart';

/// CU03: Consultar Catalogo. Busca, filtra y pagina la vitrina publica.
class TiendaPagina extends StatefulWidget {
  const TiendaPagina({super.key});

  @override
  State<TiendaPagina> createState() => _TiendaPaginaState();
}

class _TiendaPaginaState extends State<TiendaPagina> {
  static const int _porPagina = 20;

  final _busqueda = TextEditingController();
  final _scroll = ScrollController();

  FiltrosOut? _filtros;
  List<ProductoOut> _productos = [];

  /// CU17: se llena en silencio (no es critico para la pagina), solo para clientes.
  List<ProductoRecomendadoOut> _recomendaciones = [];

  String? _categoriaSlug;
  int? _tallaId;
  int? _colorId;
  String? _temporadaId;

  bool _cargando = true;
  bool _cargandoMas = false;
  bool _hayMas = true;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_alDesplazar);
    _cargarTodo();
    if (!context.read<AuthService>().esStaff) {
      _cargarRecomendaciones();
    }
  }

  Future<void> _cargarRecomendaciones() async {
    try {
      final recomendaciones = await recomendacionesService.obtener(limite: 8);
      if (!mounted) return;
      setState(() => _recomendaciones = recomendaciones);
    } catch (_) {
      if (mounted) setState(() => _recomendaciones = []);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _busqueda.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _alDesplazar() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
      _cargarMas();
    }
  }

  Future<void> _cargarTodo() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      _filtros ??= await catalogoService.obtenerFiltros();
      final productos = await _pedirProductos(0);
      if (!mounted) return;
      setState(() {
        _productos = productos;
        _hayMas = productos.length == _porPagina;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = interpretarError(error);
        _cargando = false;
      });
    }
  }

  Future<List<ProductoOut>> _pedirProductos(int offset) => catalogoService.listarProductos(
        categoriaSlug: _categoriaSlug,
        q: _busqueda.text.trim().isEmpty ? null : _busqueda.text.trim(),
        temporadaId: _temporadaId,
        tallaId: _tallaId,
        colorId: _colorId,
        limit: _porPagina,
        offset: offset,
      );

  Future<void> _cargarMas() async {
    if (_cargandoMas || !_hayMas || _cargando) return;
    setState(() => _cargandoMas = true);
    try {
      final nuevos = await _pedirProductos(_productos.length);
      if (!mounted) return;
      setState(() {
        _productos = [..._productos, ...nuevos];
        _hayMas = nuevos.length == _porPagina;
      });
    } catch (_) {
      if (mounted) setState(() => _hayMas = false);
    } finally {
      if (mounted) setState(() => _cargandoMas = false);
    }
  }

  void _buscarConRetraso(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _cargarTodo);
  }

  void _limpiarFiltros() {
    setState(() {
      _categoriaSlug = null;
      _tallaId = null;
      _colorId = null;
      _temporadaId = null;
      _busqueda.clear();
    });
    _cargarTodo();
  }

  bool get _hayFiltrosActivos =>
      _categoriaSlug != null || _tallaId != null || _colorId != null || _temporadaId != null;

  Future<void> _abrirFiltros() async {
    final filtros = _filtros;
    if (filtros == null) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Paleta.paper,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (contexto) => StatefulBuilder(
        builder: (contexto, actualizarHoja) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.92,
          builder: (contexto, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Titular('Filtrar', tamano: 24),
                  TextButton(
                    onPressed: () {
                      actualizarHoja(() {
                        _categoriaSlug = null;
                        _tallaId = null;
                        _colorId = null;
                        _temporadaId = null;
                      });
                      setState(() {});
                    },
                    child: const Text('Limpiar'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const EtiquetaDato('Categoria'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: filtros.categorias
                    .map(
                      (categoria) => FilterChip(
                        label: Text(categoria.nombre),
                        selected: _categoriaSlug == categoria.slug,
                        selectedColor: Paleta.flame.withValues(alpha: 0.16),
                        onSelected: (elegido) {
                          actualizarHoja(() =>
                              _categoriaSlug = elegido ? categoria.slug : null);
                          setState(() {});
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
              const EtiquetaDato('Talla'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: filtros.tallas
                    .map(
                      (talla) => FilterChip(
                        label: Text(talla.codigo),
                        selected: _tallaId == talla.id,
                        selectedColor: Paleta.flame.withValues(alpha: 0.16),
                        onSelected: (elegido) {
                          actualizarHoja(() => _tallaId = elegido ? talla.id : null);
                          setState(() {});
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
              const EtiquetaDato('Color'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: filtros.colores
                    .map(
                      (color) => FilterChip(
                        avatar: CircleAvatar(
                          radius: 8,
                          backgroundColor: _desdeHex(color.codigoHex),
                        ),
                        label: Text(color.nombre),
                        selected: _colorId == color.id,
                        selectedColor: Paleta.flame.withValues(alpha: 0.16),
                        onSelected: (elegido) {
                          actualizarHoja(() => _colorId = elegido ? color.id : null);
                          setState(() {});
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
              const EtiquetaDato('Temporada'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: filtros.temporadas
                    .map(
                      (temporada) => FilterChip(
                        label: Text(temporada.nombre),
                        selected: _temporadaId == temporada.id,
                        selectedColor: Paleta.flame.withValues(alpha: 0.16),
                        onSelected: (elegido) {
                          actualizarHoja(() => _temporadaId = elegido ? temporada.id : null);
                          setState(() {});
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(contexto),
                child: const Text('VER RESULTADOS'),
              ),
            ],
          ),
        ),
      ),
    );
    await _cargarTodo();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('FashionStore'),
          actions: [
            IconButton(
              tooltip: 'Filtrar',
              onPressed: _abrirFiltros,
              icon: Badge(
                isLabelVisible: _hayFiltrosActivos,
                backgroundColor: Paleta.flame,
                child: const Icon(Icons.tune),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_recomendaciones.isNotEmpty) _SeccionRecomendaciones(productos: _recomendaciones),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: TextField(
                controller: _busqueda,
                onChanged: _buscarConRetraso,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Buscar prendas...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _busqueda.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _busqueda.clear();
                            _cargarTodo();
                          },
                        ),
                ),
              ),
            ),
            if (_hayFiltrosActivos)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_productos.length} prenda(s) con los filtros activos',
                        style: const TextStyle(color: Paleta.inkSuave, fontSize: 13),
                      ),
                    ),
                    TextButton(onPressed: _limpiarFiltros, child: const Text('Quitar filtros')),
                  ],
                ),
              ),
            Expanded(
              child: VistaAsincrona(
                cargando: _cargando,
                error: _error,
                alReintentar: _cargarTodo,
                hijo: _productos.isEmpty
                    ? const EstadoVacio(
                        mensaje: 'No hay prendas que coincidan con tu busqueda.',
                        icono: Icons.search_off,
                      )
                    : RefreshIndicator(
                        color: Paleta.flame,
                        onRefresh: _cargarTodo,
                        child: GridView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 260,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                            childAspectRatio: 0.6,
                          ),
                          itemCount: _productos.length + (_cargandoMas ? 1 : 0),
                          itemBuilder: (contexto, indice) {
                            if (indice >= _productos.length) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            return TarjetaProducto(producto: _productos[indice]);
                          },
                        ),
                      ),
              ),
            ),
          ],
        ),
      );
}

/// Tarjeta del grid de la vitrina.
class TarjetaProducto extends StatelessWidget {
  const TarjetaProducto({super.key, required this.producto, this.motivo});

  final ProductoOut producto;

  /// CU17: por que se sugiere esta prenda. Ausente en el catalogo comun (CU03).
  final String? motivo;

  @override
  Widget build(BuildContext context) => TarjetaPanel(
        padding: EdgeInsets.zero,
        alTocar: () => context.push('/producto/${producto.slug}'),
        hijo: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ImagenPrenda(url: producto.imagenUrl),
                  // el badge va sobre la foto: necesita fondo opaco para leerse
                  if (producto.agotado)
                    const Positioned(
                      left: 8,
                      top: 8,
                      child: _BadgeSobreFoto('Agotado', color: Paleta.rojo),
                    )
                  else if (producto.destacado)
                    const Positioned(
                      left: 8,
                      top: 8,
                      child: _BadgeSobreFoto('Destacado', color: Paleta.gold),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EtiquetaDato(producto.marca ?? producto.categoria),
                  const SizedBox(height: 4),
                  Text(
                    producto.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, height: 1.2),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatearPrecio(producto.precioBase),
                    style: fuenteDisplay(color: Paleta.flameOscuro, fontSize: 16),
                  ),
                  if (producto.tallas.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      producto.tallas.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: fuenteMono(fontSize: 11, letterSpacing: 0.4, color: Paleta.inkSuave),
                    ),
                  ],
                  if (motivo != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      motivo!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: Paleta.flameOscuro,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}

/// CU17 - Recibir Recomendaciones de IA: carrusel horizontal arriba del catalogo,
/// espejo movil de la seccion "Recomendado para vos" de `tienda.page.html`. Solo se
/// muestra si hay recomendaciones (se pide en silencio y no es critico para la pagina).
class _SeccionRecomendaciones extends StatelessWidget {
  const _SeccionRecomendaciones({required this.productos});

  final List<ProductoRecomendadoOut> productos;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 0, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Titular('Recomendado para vos', tamano: 18, mayusculas: false),
            const SizedBox(height: 10),
            SizedBox(
              height: 236,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 16),
                itemCount: productos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (contexto, indice) {
                  final producto = productos[indice];
                  return SizedBox(
                    width: 170,
                    child: TarjetaProducto(producto: producto, motivo: producto.motivo),
                  );
                },
              ),
            ),
          ],
        ),
      );
}

/// Badge apoyado sobre la imagen de la prenda. El [BadgeEstado] comun usa un fondo
/// translucido que se pierde contra una foto clara, asi que aca el fondo es opaco.
class _BadgeSobreFoto extends StatelessWidget {
  const _BadgeSobreFoto(this.texto, {required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          texto.toUpperCase(),
          style: fuenteMono(fontSize: 10.5, letterSpacing: 0.8, color: Paleta.blanco),
        ),
      );
}

/// Imagen de catalogo con marcador de posicion (las URLs del seed son externas).
class ImagenPrenda extends StatelessWidget {
  const ImagenPrenda({super.key, required this.url, this.ajuste = BoxFit.cover});

  final String? url;
  final BoxFit ajuste;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return const _SinImagen();
    return Image.network(
      url!,
      fit: ajuste,
      errorBuilder: (contexto, error, pila) => const _SinImagen(),
      loadingBuilder: (contexto, hijo, progreso) => progreso == null
          ? hijo
          : const ColoredBox(
              color: Paleta.paper,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
    );
  }
}

class _SinImagen extends StatelessWidget {
  const _SinImagen();

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Paleta.paper,
        child: Center(child: Icon(Icons.checkroom, size: 42, color: Paleta.paperLinea)),
      );
}

/// Convierte el `codigo_hex` de la tabla `color` a un Color de Flutter.
Color _desdeHex(String hex) {
  final limpio = hex.replaceFirst('#', '');
  final valor = int.tryParse(limpio, radix: 16);
  if (valor == null) return Paleta.paperLinea;
  return Color(limpio.length == 6 ? 0xFF000000 | valor : valor);
}

Color colorDesdeHex(String hex) => _desdeHex(hex);
