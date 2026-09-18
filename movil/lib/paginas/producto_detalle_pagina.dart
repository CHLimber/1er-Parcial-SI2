import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
  VarianteOut? _variante;
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

  /// Reordena las variantes para que el color de catalogo aparezca primero,
  /// preservando el orden relativo del resto. Espejo del reordenamiento que
  /// hace `colores()` en la web.
  List<VarianteOut> _ordenarVariantes(ProductoDetalleOut producto) {
    final colorCatalogo = _colorDeCatalogo(producto);
    if (colorCatalogo == null) return producto.variantes;
    final delCatalogo = producto.variantes.where((v) => v.color == colorCatalogo);
    final resto = producto.variantes.where((v) => v.color != colorCatalogo);
    return [...delCatalogo, ...resto];
  }

  /// Imagen mostrada: la de catalogo mientras no se elija color a mano; si se
  /// elige, la propia de la variante (si tiene) o la de catalogo como
  /// respaldo. Espejo de `imagenActual()` en la web.
  String? _imagenActual(ProductoDetalleOut producto) {
    final preview = _previsualizacionGaleria;
    if (preview != null) return preview.url;
    if (!_colorElegidoManualmente) return producto.imagenUrl;
    return _variante?.imagenUrl ?? producto.imagenUrl;
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
        _variante = producto.variantes.isEmpty
            ? null
            : producto.variantes.firstWhere(
                (v) => v.color == colorCatalogo,
                orElse: () => producto.variantes.first,
              );
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
    final variante = _variante;
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

  /// CU16 nivel 2: lanza Google Scene Viewer con el modelo GLB. Solo Android
  /// por ahora -- Quick Look (iOS) necesita el mismo modelo convertido a
  /// USDZ, y eso requiere Reality Converter (Mac); ver IMAGENES_AR.txt.
  Future<void> _abrirVisor3d(ImagenArOut modelo) async {
    final url = Uri.encodeComponent(modelo.url);
    // mode=ar_preferred y no ar_only: con ar_only, un equipo sin ARCore (o el
    // emulador) no abre NADA. Con ar_preferred siempre se ve el modelo en 3D y
    // el boton de "ver en tu espacio" aparece solo si el equipo lo soporta.
    final intent = Uri.parse(
      'intent://arvr.google.com/scene-viewer/1.0?file=$url&mode=ar_preferred'
      '&title=${Uri.encodeComponent(_producto?.nombre ?? "FashionStore")}'
      '#Intent;scheme=https;package=com.google.ar.core;'
      'action=android.intent.action.VIEW;S.browser_fallback_url=$url;end;',
    );
    final abierto = await launchUrl(intent, mode: LaunchMode.externalApplication);
    if (!abierto && mounted) {
      mostrarAviso(
        context,
        'No se pudo abrir el visor de RA. ¿Tenes instalado "Google Play Services para RA"?',
        esError: true,
      );
    }
  }

  Future<void> _agregarAlCarrito() async {
    final variante = _variante;
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
                    formatearPrecio(_variante?.precio ?? producto.precioBase),
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
                  const SizedBox(height: 22),
                  const EtiquetaDato('Elige talla y color'),
                  const SizedBox(height: 10),
                  if (producto.variantes.isEmpty)
                    const Text(
                      'Esta prenda todavia no tiene variantes cargadas.',
                      style: TextStyle(color: Paleta.inkSuave),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _ordenarVariantes(producto).map(_chipVariante).toList(),
                    ),
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
                  if (_variante != null) _disponibilidad(_variante!),
                  const SizedBox(height: 26),
                  ElevatedButton.icon(
                    onPressed: (_variante == null || _agregando) ? null : _agregarAlCarrito,
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
                    onPressed: _variante == null ? null : _agregarABolsaDeReserva,
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
        if (Platform.isAndroid)
          OutlinedButton.icon(
            onPressed: () => _abrirVisor3d(modelo3d),
            icon: const Icon(Icons.view_in_ar_outlined),
            label: const Text('VER EN 3D / PROBAR EN TU ESPACIO'),
          )
        else
          const Text(
            'El modelo 3D todavia solo esta disponible en Android '
            '(falta convertir el archivo a USDZ para iOS).',
            style: TextStyle(fontSize: 12.5, color: Paleta.inkSuave, height: 1.4),
          ),
    ];
  }

  Widget _chipVariante(VarianteOut variante) {
    final seleccionada = _variante?.id == variante.id;
    final agotada = variante.totalDisponible <= 0;

    return ChoiceChip(
      selected: seleccionada,
      onSelected: (_) => setState(() {
        _variante = variante;
        _colorElegidoManualmente = true;
        _previsualizacionGaleria = null;
      }),
      selectedColor: Paleta.flame.withValues(alpha: 0.18),
      avatar: CircleAvatar(radius: 8, backgroundColor: colorDesdeHex(variante.codigoHex)),
      label: Text(
        '${variante.talla} · ${variante.color}${agotada ? " (agotada)" : ""}',
        style: TextStyle(
          decoration: agotada ? TextDecoration.lineThrough : null,
          fontWeight: seleccionada ? FontWeight.w700 : FontWeight.w500,
        ),
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
