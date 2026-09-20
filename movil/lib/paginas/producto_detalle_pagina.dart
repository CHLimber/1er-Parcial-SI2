import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../compartido/widgets.dart';
import '../core/carrito/carrito_service.dart';
import '../core/catalogo/catalogo_models.dart';
import '../core/catalogo/catalogo_service.dart';
import '../core/config.dart';
import '../core/errores.dart';
import '../core/reservas/reserva_carrito_service.dart';
import '../core/reservas/reservas_models.dart';
import '../core/tema.dart';
import 'tienda_pagina.dart';
import 'vestidor_virtual_pagina.dart';
import 'visor_3d_pagina.dart';

/// CU03 (detalle de prenda) y punto de entrada de CU04 (reservar) y CU05 (comprar).
///
/// El stock nunca vive en `producto`: se elige una variante (producto x talla x color),
/// que es la unidad fisica que se reserva y se vende.
class ProductoDetallePagina extends StatefulWidget {
  const ProductoDetallePagina({super.key, required this.slug});

  final String slug;

  @override
  State<ProductoDetallePagina> createState() => _ProductoDetallePaginaState();
}

class _ProductoDetallePaginaState extends State<ProductoDetallePagina> {
  ProductoDetalleOut? _producto;
  String? _tallaSeleccionada;
  String? _colorSeleccionado;
  bool _cargando = true;
  bool _agregando = false;
  bool _colorElegidoManualmente = false;
  GaleriaImagenOut? _previsualizacionGaleria;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// Color cuya foto de variante coincide con la foto principal del producto
  /// (la que subio el admin en CU10). Espejo de `colorDeCatalogo` en
  /// `producto-detalle.page.ts`.
  String? _colorDeCatalogo(ProductoDetalleOut producto) {
    if (producto.imagenUrl == null) return null;
    for (final v in producto.variantes) {
      if (v.imagenUrl == producto.imagenUrl) return v.color;
    }
    return null;
  }

  /// Tallas unicas entre las variantes, en orden de aparicion. Espejo de
  /// `tallas()` en la web -- separar talla y color en dos selectores evita
  /// mostrar todas las combinaciones (hasta una decena) en una sola lista.
  List<String> _tallas(ProductoDetalleOut producto) {
    final vistas = <String>{};
    final lista = <String>[];
    for (final v in producto.variantes) {
      if (vistas.add(v.talla)) lista.add(v.talla);
    }
    return lista;
  }

  /// Colores unicos (con su hex) reordenados para que el color de catalogo
  /// aparezca primero, preservando el orden relativo del resto. Espejo de
  /// `colores()` en la web.
  List<_ColorOpcion> _colores(ProductoDetalleOut producto) {
    final vistos = <String, String>{};
    for (final v in producto.variantes) {
      vistos.putIfAbsent(v.color, () => v.codigoHex);
    }
    final lista = vistos.entries.map((e) => _ColorOpcion(e.key, e.value)).toList();
    final colorCatalogo = _colorDeCatalogo(producto);
    if (colorCatalogo == null) return lista;
    final indice = lista.indexWhere((c) => c.nombre == colorCatalogo);
    if (indice <= 0) return lista;
    final principal = lista.removeAt(indice);
    return [principal, ...lista];
  }

  /// Variante que corresponde a la talla y color elegidos, o null si esa
  /// combinacion no existe (no todas las tallas vienen en todos los colores).
  VarianteOut? _varianteSeleccionada(ProductoDetalleOut producto) {
    for (final v in producto.variantes) {
      if (v.talla == _tallaSeleccionada && v.color == _colorSeleccionado) return v;
    }
    return null;
  }

  /// Imagen mostrada: la de catalogo mientras no se elija color a mano; si se
  /// elige, la propia de la variante (si tiene) o la de catalogo como
  /// respaldo. Espejo de `imagenActual()` en la web.
  String? _imagenActual(ProductoDetalleOut producto) {
    final preview = _previsualizacionGaleria;
    if (preview != null) return preview.url;
    if (!_colorElegidoManualmente) return producto.imagenUrl;
    for (final v in producto.variantes) {
      if (v.color == _colorSeleccionado && v.imagenUrl != null) return v.imagenUrl;
    }
    return producto.imagenUrl;
  }

  /// Colores con foto de catalogo (`galeria`) que todavia no tienen una
  /// variante comprable -- solo sirven de referencia visual, sin stock.
  /// Espejo de `coloresGaleria` en `producto-detalle.page.ts`.
  List<GaleriaImagenOut> _coloresGaleria(ProductoDetalleOut producto) {
    final colorsConVariante = producto.variantes.map((v) => v.color).toSet();
    final vistos = <String, GaleriaImagenOut>{};
    for (final item in producto.galeria) {
      final color = item.color;
      if (color == null || colorsConVariante.contains(color) || vistos.containsKey(color)) {
        continue;
      }
      vistos[color] = item;
    }
    return vistos.values.toList();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final producto = await catalogoService.obtenerProducto(widget.slug);
      if (!mounted) return;
      setState(() {
        _producto = producto;
        final colorCatalogo = _colorDeCatalogo(producto);
        final varianteInicial = producto.variantes.isEmpty
            ? null
            : producto.variantes.firstWhere(
                (v) => v.color == colorCatalogo,
                orElse: () => producto.variantes.first,
              );
        _tallaSeleccionada = varianteInicial?.talla;
        _colorSeleccionado = varianteInicial?.color;
        _colorElegidoManualmente = false;
        _previsualizacionGaleria = null;
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

  void _agregarABolsaDeReserva() {
    final producto = _producto;
    final variante = producto == null ? null : _varianteSeleccionada(producto);
    if (producto == null || variante == null) return;

    context.read<ReservaCarritoService>().agregar(
          ItemCarritoReserva(
            varianteId: variante.id,
            sku: variante.sku,
            producto: producto.nombre,
            productoSlug: producto.slug,
            talla: variante.talla,
            color: variante.color,
            codigoHex: variante.codigoHex,
            precio: variante.precio,
            imagenUrl: producto.imagenUrl,
            cantidad: 1,
          ),
        );
    mostrarAviso(context, 'Agregado a tu bolsa de reserva (${variante.talla} · ${variante.color})');
  }

  /// CU16 nivel 1: abre la camara con la prenda anclada a los hombros.
  void _abrirVestidorVirtual(ImagenArOut overlay) {
    final producto = _producto;
    if (producto == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VestidorVirtualPagina(nombrePrenda: producto.nombre, overlay: overlay),
      ),
    );
  }

  /// CU16 nivel 2: abre el visor 3D embebido (`<model-viewer>` en un WebView).
  ///
  /// Antes esto lanzaba directamente un intent de Google Scene Viewer, y por eso el
  /// boton "no hacia nada" en cualquier equipo sin servicios de Google (un Huawei sin
  /// GMS, o el emulador sin "Play Services para RA"). El visor propio funciona en
  /// todos lados; la RA sigue disponible desde ahi para quien la soporte.
  void _abrirVisor3d(ImagenArOut modelo) {
    final producto = _producto;
    if (producto == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Visor3dPagina(nombrePrenda: producto.nombre, modelo: modelo),
      ),
    );
  }

  Future<void> _agregarAlCarrito() async {
    final producto = _producto;
    final variante = producto == null ? null : _varianteSeleccionada(producto);
    if (variante == null) return;

    setState(() => _agregando = true);
    try {
      await context.read<CarritoService>().agregarItem(variante.id, 1);
      if (!mounted) return;
      mostrarAviso(context, 'Agregado al carrito de compra');
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    } finally {
      if (mounted) setState(() => _agregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final producto = _producto;
    final variante = producto == null ? null : _varianteSeleccionada(producto);

    return Scaffold(
      appBar: AppBar(title: Text(producto?.nombre ?? 'Prenda')),
      body: VistaAsincrona(
        cargando: _cargando,
        error: _error,
        alReintentar: _cargar,
        hijo: producto == null
            ? const EstadoVacio(mensaje: 'No se encontro la prenda.')
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  AspectRatio(
                    aspectRatio: 3 / 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ImagenPrenda(url: _imagenActual(producto)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  EtiquetaDato('${producto.categoria} · ${producto.marca ?? "Sin marca"}'),
                  const SizedBox(height: 6),
                  Titular(producto.nombre, tamano: 26, mayusculas: false),
                  const SizedBox(height: 10),
                  Text(
                    formatearPrecio(variante?.precio ?? producto.precioBase),
                    style: fuenteDisplay(fontSize: 24, color: Paleta.flameOscuro),
                  ),
                  if (producto.descripcion != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      producto.descripcion!,
                      style: const TextStyle(height: 1.5, color: Paleta.inkSuave),
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (producto.material != null) FilaDato('Material', producto.material!),
                  if (producto.genero != null) FilaDato('Genero', producto.genero!),
                  FilaDato('Codigo', producto.codigo),
                  if (producto.variantes.isEmpty)
                    ...[
                      const SizedBox(height: 22),
                      const EtiquetaDato('Elige talla y color'),
                      const SizedBox(height: 10),
                      const Text(
                        'Esta prenda todavia no tiene variantes cargadas.',
                        style: TextStyle(color: Paleta.inkSuave),
                      ),
                    ]
                  else ...[
                    const SizedBox(height: 22),
                    const EtiquetaDato('Talla'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _tallas(producto).map(_botonTalla).toList(),
                    ),
                    const SizedBox(height: 18),
                    const EtiquetaDato('Color'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _colores(producto).map(_botonColor).toList(),
                    ),
                  ],
                  if (_coloresGaleria(producto).isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const EtiquetaDato('Mas colores (solo referencia, sin stock)'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _coloresGaleria(producto).map(_chipGaleria).toList(),
                    ),
                  ],
                  const SizedBox(height: 22),
                  if (producto.variantes.isNotEmpty)
                    if (variante != null)
                      _disponibilidad(variante)
                    else
                      const Text(
                        'Esa combinacion de talla y color no existe.',
                        style: TextStyle(color: Paleta.inkSuave),
                      ),
                  const SizedBox(height: 26),
                  ElevatedButton.icon(
                    onPressed: (variante == null || _agregando) ? null : _agregarAlCarrito,
                    icon: _agregando
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Paleta.blanco),
                          )
                        : const Icon(Icons.shopping_bag_outlined),
                    label: const Text('AGREGAR AL CARRITO'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: variante == null ? null : _agregarABolsaDeReserva,
                    icon: const Icon(Icons.checkroom_outlined),
                    label: const Text('RESERVAR PARA PROBAR EN TIENDA'),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Reservar aparta la prenda en el vestidor de la sucursal que elijas; '
                    'no la descuenta del stock hasta que la compres.',
                    style: const TextStyle(fontSize: 12.5, color: Paleta.inkSuave, height: 1.4),
                  ),
                  if (producto.overlay != null || producto.modelo3d != null)
                    ..._vestidorVirtual(producto),
                ],
              ),
      ),
    );
  }

  /// CU16: seccion "Vestidor virtual" con los botones de RA que apliquen a
  /// esta prenda (overlay 2D, modelo 3D, o ambos).
  List<Widget> _vestidorVirtual(ProductoDetalleOut producto) {
    final overlay = producto.overlay;
    final modelo3d = producto.modelo3d;
    return [
      const SizedBox(height: 22),
      const EtiquetaDato('Vestidor virtual (RA)'),
      const SizedBox(height: 10),
      if (overlay != null) ...[
        OutlinedButton.icon(
          onPressed: () => _abrirVestidorVirtual(overlay),
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('PROBARTE ESTA PRENDA CON LA CAMARA'),
        ),
        const SizedBox(height: 10),
      ],
      if (modelo3d != null)
        OutlinedButton.icon(
          onPressed: () => _abrirVisor3d(modelo3d),
          icon: const Icon(Icons.view_in_ar_outlined),
          label: const Text('VER EN 3D / PROBAR EN TU ESPACIO'),
        ),
    ];
  }

  Widget _botonTalla(String talla) {
    final seleccionada = _tallaSeleccionada == talla;

    return ChoiceChip(
      selected: seleccionada,
      onSelected: (_) => setState(() => _tallaSeleccionada = talla),
      selectedColor: Paleta.flame.withValues(alpha: 0.18),
      label: Text(
        talla,
        style: TextStyle(fontWeight: seleccionada ? FontWeight.w700 : FontWeight.w500),
      ),
    );
  }

  Widget _botonColor(_ColorOpcion color) {
    final seleccionada = _colorSeleccionado == color.nombre;

    return ChoiceChip(
      selected: seleccionada,
      onSelected: (_) => setState(() {
        _colorSeleccionado = color.nombre;
        _colorElegidoManualmente = true;
        _previsualizacionGaleria = null;
      }),
      selectedColor: Paleta.flame.withValues(alpha: 0.18),
      avatar: CircleAvatar(radius: 8, backgroundColor: colorDesdeHex(color.codigoHex)),
      label: Text(
        color.nombre,
        style: TextStyle(fontWeight: seleccionada ? FontWeight.w700 : FontWeight.w500),
      ),
    );
  }

  Widget _chipGaleria(GaleriaImagenOut item) {
    final seleccionada = _previsualizacionGaleria?.color == item.color;

    return ChoiceChip(
      selected: seleccionada,
      onSelected: (_) => setState(() => _previsualizacionGaleria = item),
      selectedColor: Paleta.flame.withValues(alpha: 0.18),
      avatar: CircleAvatar(
        radius: 8,
        backgroundColor: item.codigoHex != null ? colorDesdeHex(item.codigoHex!) : Paleta.inkSuave,
      ),
      label: Text(
        item.color ?? '',
        style: TextStyle(fontWeight: seleccionada ? FontWeight.w700 : FontWeight.w500),
      ),
    );
  }

  Widget _disponibilidad(VarianteOut variante) => TarjetaPanel(
        hijo: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: EtiquetaDato('Disponibilidad por sucursal')),
                EtiquetaDato(variante.sku),
              ],
            ),
            const SizedBox(height: 10),
            if (variante.disponibilidad.isEmpty)
              const Text(
                'Sin existencias en ninguna sucursal.',
                style: TextStyle(color: Paleta.inkSuave),
              )
            else
              ...variante.disponibilidad.map(
                (fila) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fila.sucursal,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              fila.ciudad,
                              style: const TextStyle(fontSize: 12, color: Paleta.inkSuave),
                            ),
                          ],
                        ),
                      ),
                      BadgeEstado(
                        '${fila.disponible} · ${fila.situacion}',
                        color: fila.disponible > 0 ? Paleta.verde : Paleta.rojo,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}

/// Un color disponible entre las variantes de la prenda, con su hex para el
/// swatch del selector.
class _ColorOpcion {
  const _ColorOpcion(this.nombre, this.codigoHex);

  final String nombre;
  final String codigoHex;
}
