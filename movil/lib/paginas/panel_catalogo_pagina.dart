import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../compartido/widgets.dart';
import '../core/auth/auth_service.dart';
import '../core/catalogo/catalogo_admin_models.dart';
import '../core/catalogo/catalogo_admin_service.dart';
import '../core/config.dart';
import '../core/errores.dart';
import '../core/tema.dart';
import 'tienda_pagina.dart' show ImagenPrenda, colorDesdeHex;

/// CU10: Gestionar Catalogo. Prendas y variantes en una pestana, categorias y marcas en
/// la otra. El stock nunca se toca desde aca: entra por CU09 y sale por las ventas.
class PanelCatalogoPagina extends StatefulWidget {
  const PanelCatalogoPagina({super.key});

  @override
  State<PanelCatalogoPagina> createState() => _PanelCatalogoPaginaState();
}

class _PanelCatalogoPaginaState extends State<PanelCatalogoPagina> {
  ReferenciasOut? _referencias;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarReferencias();
  }

  Future<void> _cargarReferencias() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final referencias = await catalogoAdminService.obtenerReferencias();
      if (!mounted) return;
      setState(() {
        _referencias = referencias;
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

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Catalogo'),
            bottom: const TabBar(
              labelColor: Paleta.paper,
              unselectedLabelColor: Paleta.paperLinea,
              indicatorColor: Paleta.flame,
              tabs: [Tab(text: 'PRENDAS'), Tab(text: 'CATEGORIAS')],
            ),
          ),
          body: VistaAsincrona(
            cargando: _cargando,
            error: _error,
            alReintentar: _cargarReferencias,
            hijo: _referencias == null
                ? const EstadoVacio(mensaje: 'No se pudieron cargar las referencias.')
                : TabBarView(
                    children: [
                      _PestanaPrendas(referencias: _referencias!),
                      _PestanaCategorias(
                        referencias: _referencias!,
                        alCambiar: _cargarReferencias,
                      ),
                    ],
                  ),
          ),
        ),
      );
}

// --- Prendas ---------------------------------------------------------------

class _PestanaPrendas extends StatefulWidget {
  const _PestanaPrendas({required this.referencias});

  final ReferenciasOut referencias;

  @override
  State<_PestanaPrendas> createState() => _PestanaPrendasState();
}

class _PestanaPrendasState extends State<_PestanaPrendas> {
  final _busqueda = TextEditingController();

  List<ProductoAdminOut> _productos = [];
  String? _categoriaId;
  bool? _activo;
  bool _cargando = true;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final productos = await catalogoAdminService.listarProductos(
        q: _busqueda.text.trim().isEmpty ? null : _busqueda.text.trim(),
        categoriaId: _categoriaId,
        activo: _activo,
      );
      if (!mounted) return;
      setState(() {
        _productos = productos;
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

  void _buscarConRetraso(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _cargar);
  }

  Future<void> _nuevoProducto() async {
    final datos = await mostrarFormularioProducto(context, widget.referencias);
    if (datos == null) return;
    try {
      final creado = await catalogoAdminService.crearProducto(datos);
      if (!mounted) return;
      await _abrirDetalle(creado.id);
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  Future<void> _abrirDetalle(String productoId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (contexto) => DetalleProductoPagina(
          productoId: productoId,
          referencias: widget.referencias,
        ),
      ),
    );
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final puedeGestionar = context.watch<AuthService>().tienePermiso(['catalogo.gestionar']);

    return Scaffold(
      backgroundColor: Paleta.paper,
      floatingActionButton: puedeGestionar
          ? FloatingActionButton.extended(
              onPressed: _nuevoProducto,
              backgroundColor: Paleta.flame,
              foregroundColor: Paleta.blanco,
              icon: const Icon(Icons.add),
              label: const Text('PRENDA'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              controller: _busqueda,
              onChanged: _buscarConRetraso,
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre o codigo',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _chip('Todas', _activo == null && _categoriaId == null, () {
                  setState(() {
                    _activo = null;
                    _categoriaId = null;
                  });
                  _cargar();
                }),
                _chip('Activas', _activo == true, () {
                  setState(() => _activo = _activo == true ? null : true);
                  _cargar();
                }),
                _chip('Inactivas', _activo == false, () {
                  setState(() => _activo = _activo == false ? null : false);
                  _cargar();
                }),
                ...widget.referencias.categorias.map(
                  (categoria) => _chip(categoria.nombre, _categoriaId == categoria.id, () {
                    setState(() =>
                        _categoriaId = _categoriaId == categoria.id ? null : categoria.id);
                    _cargar();
                  }),
                ),
              ],
            ),
          ),
          Expanded(
            child: VistaAsincrona(
              cargando: _cargando,
              error: _error,
              alReintentar: _cargar,
              hijo: _productos.isEmpty
                  ? const EstadoVacio(mensaje: 'No hay prendas con ese criterio.')
                  : RefreshIndicator(
                      color: Paleta.flame,
                      onRefresh: _cargar,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                        itemCount: _productos.length,
                        separatorBuilder: (contexto, indice) => const SizedBox(height: 10),
                        itemBuilder: (contexto, indice) {
                          final producto = _productos[indice];
                          return TarjetaPanel(
                            alTocar: () => _abrirDetalle(producto.id),
                            hijo: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        producto.nombre,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    if (producto.destacado)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 6),
                                        child: BadgeEstado('DESTACADA', color: Paleta.gold),
                                      ),
                                    BadgeEstado(producto.activo ? 'ACTIVA' : 'INACTIVA'),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                EtiquetaDato(
                                  '${producto.codigo} · ${producto.categoria}'
                                  '${producto.marca == null ? "" : " · ${producto.marca}"}',
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        formatearPrecio(producto.precioBase),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Paleta.flameOscuro,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${producto.variantesActivas} variante(s) · '
                                      'stock ${producto.stockTotal}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Paleta.inkSuave,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String etiqueta, bool elegido, VoidCallback alTocar) => Padding(
        padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
        child: FilterChip(
          label: Text(etiqueta),
          selected: elegido,
          selectedColor: Paleta.flame.withValues(alpha: 0.16),
          onSelected: (_) => alTocar(),
        ),
      );
}

/// Formulario de alta/edicion de prenda. Devuelve null si se cancela.
Future<ProductoIn?> mostrarFormularioProducto(
  BuildContext context,
  ReferenciasOut referencias, {
  ProductoAdminDetalleOut? producto,
}) async {
  final codigo = TextEditingController(text: producto?.codigo ?? '');
  final nombre = TextEditingController(text: producto?.nombre ?? '');
  final descripcion = TextEditingController(text: producto?.descripcion ?? '');
  final material = TextEditingController(text: producto?.material ?? '');
  final precio = TextEditingController(
    text: producto == null ? '' : producto.precioBase.toStringAsFixed(2),
  );
  final formulario = GlobalKey<FormState>();

  String? categoriaId = producto?.categoriaId ??
      (referencias.categorias.isEmpty ? null : referencias.categorias.first.id);
  String? marcaId = producto?.marcaId;
  String? proveedorId = producto?.proveedorId;
  String? temporadaId = producto?.temporadaId;
  String? coleccionId = producto?.coleccionId;
  String? genero = producto?.genero;
  bool destacado = producto?.destacado ?? false;

  final guardado = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Paleta.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (contexto) => StatefulBuilder(
      builder: (contexto, actualizar) {
        final coleccionesFiltradas = temporadaId == null
            ? referencias.colecciones
            : referencias.colecciones.where((c) => c.temporadaId == temporadaId).toList();

        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(contexto).viewInsets.bottom),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.9,
            maxChildSize: 0.95,
            builder: (contexto, scroll) => Form(
              key: formulario,
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                children: [
                  Titular(producto == null ? 'Nueva prenda' : 'Editar prenda', tamano: 24),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: codigo,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Codigo interno'),
                    validator: (v) =>
                        (v?.trim().length ?? 0) < 2 ? 'Codigo de al menos 2 caracteres' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nombre,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    validator: (v) =>
                        (v?.trim().length ?? 0) < 2 ? 'Escribe el nombre' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descripcion,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Descripcion (opcional)',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: categoriaId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Categoria'),
                    items: referencias.categorias
                        .map((c) => DropdownMenuItem(value: c.id, child: Text(c.nombre)))
                        .toList(),
                    onChanged: (valor) => actualizar(() => categoriaId = valor),
                    validator: (v) => v == null ? 'Elige una categoria' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: marcaId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Marca (opcional)'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Sin marca')),
                      ...referencias.marcas
                          .map((m) => DropdownMenuItem(value: m.id, child: Text(m.nombre))),
                    ],
                    onChanged: (valor) => actualizar(() => marcaId = valor),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: proveedorId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Proveedor (opcional)'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Sin proveedor')),
                      ...referencias.proveedores.map(
                        (p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(p.nombre, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (valor) => actualizar(() => proveedorId = valor),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: temporadaId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Temporada (opcional)'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Sin temporada')),
                      ...referencias.temporadas
                          .map((t) => DropdownMenuItem(value: t.id, child: Text(t.nombre))),
                    ],
                    onChanged: (valor) => actualizar(() {
                      temporadaId = valor;
                      coleccionId = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: coleccionId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Coleccion (opcional)'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Sin coleccion')),
                      ...coleccionesFiltradas
                          .map((c) => DropdownMenuItem(value: c.id, child: Text(c.nombre))),
                    ],
                    onChanged: (valor) => actualizar(() => coleccionId = valor),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: genero,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Genero (opcional)'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Sin especificar')),
                      ...referencias.generos
                          .map((g) => DropdownMenuItem(value: g, child: Text(g))),
                    ],
                    onChanged: (valor) => actualizar(() => genero = valor),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: material,
                    decoration: const InputDecoration(labelText: 'Material (opcional)'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: precio,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Precio base',
                      prefixText: 'Bs ',
                    ),
                    validator: (v) {
                      final valor = double.tryParse((v ?? '').replaceAll(',', '.'));
                      if (valor == null || valor < 0) return 'Escribe un precio valido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 6),
                  CheckboxListTile(
                    value: destacado,
                    onChanged: (valor) => actualizar(() => destacado = valor ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: Paleta.flame,
                    title: const Text('Destacar en la vitrina'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      if (formulario.currentState!.validate()) Navigator.pop(contexto, true);
                    },
                    child: const Text('GUARDAR'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  final datos = ProductoIn(
    codigo: codigo.text.trim(),
    nombre: nombre.text.trim(),
    descripcion: descripcion.text.trim(),
    categoriaId: categoriaId ?? '',
    marcaId: marcaId,
    proveedorId: proveedorId,
    temporadaId: temporadaId,
    coleccionId: coleccionId,
    material: material.text.trim(),
    genero: genero,
    precioBase: double.tryParse(precio.text.replaceAll(',', '.')) ?? 0,
    destacado: destacado,
  );
  for (final control in [codigo, nombre, descripcion, material, precio]) {
    control.dispose();
  }
  return guardado == true ? datos : null;
}

/// Detalle de una prenda: sus variantes (la unidad que se vende) y sus imagenes.
class DetalleProductoPagina extends StatefulWidget {
  const DetalleProductoPagina({
    super.key,
    required this.productoId,
    required this.referencias,
  });

  final String productoId;
  final ReferenciasOut referencias;

  @override
  State<DetalleProductoPagina> createState() => _DetalleProductoPaginaState();
}

class _DetalleProductoPaginaState extends State<DetalleProductoPagina> {
  ProductoAdminDetalleOut? _producto;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final producto = await catalogoAdminService.obtenerProducto(widget.productoId);
      if (!mounted) return;
      setState(() {
        _producto = producto;
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

  Future<void> _editar() async {
    final producto = _producto;
    if (producto == null) return;
    final datos = await mostrarFormularioProducto(
      context,
      widget.referencias,
      producto: producto,
    );
    if (datos == null) return;
    await _ejecutar(() => catalogoAdminService.actualizarProducto(producto.id, datos));
  }

  Future<void> _cambiarEstado() async {
    final producto = _producto;
    if (producto == null) return;
    await _ejecutar(
      () => catalogoAdminService.cambiarEstadoProducto(producto.id, !producto.activo),
    );
  }

  Future<void> _editarVariante({VarianteAdminOut? variante}) async {
    final producto = _producto;
    if (producto == null) return;

    final sku = TextEditingController(text: variante?.sku ?? '');
    final codigoBarras = TextEditingController(text: variante?.codigoBarras ?? '');
    final precio = TextEditingController(
      text: variante?.precio?.toStringAsFixed(2) ?? '',
    );
    final precioOferta = TextEditingController(
      text: variante?.precioOferta?.toStringAsFixed(2) ?? '',
    );
    int? tallaId = variante?.tallaId ??
        (widget.referencias.tallas.isEmpty ? null : widget.referencias.tallas.first.id);
    int? colorId = variante?.colorId ??
        (widget.referencias.colores.isEmpty ? null : widget.referencias.colores.first.id);

    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Paleta.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (contexto) => StatefulBuilder(
        builder: (contexto, actualizar) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(contexto).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Titular(variante == null ? 'Nueva variante' : 'Editar variante', tamano: 24),
                const SizedBox(height: 6),
                const Text(
                  'La variante (talla x color) es la unidad fisica que se reserva y se '
                  'vende. Si dejas el precio vacio, hereda el precio base de la prenda.',
                  style: TextStyle(fontSize: 13, color: Paleta.inkSuave, height: 1.4),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<int>(
                  initialValue: tallaId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Talla'),
                  items: widget.referencias.tallas
                      .map(
                        (t) => DropdownMenuItem(
                          value: t.id,
                          child: Text('${t.codigo} (${t.tipo})'),
                        ),
                      )
                      .toList(),
                  onChanged: (valor) => actualizar(() => tallaId = valor),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: colorId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Color'),
                  items: widget.referencias.colores
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 8,
                                backgroundColor: colorDesdeHex(c.codigoHex),
                              ),
                              const SizedBox(width: 8),
                              Text(c.nombre),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (valor) => actualizar(() => colorId = valor),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sku,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'SKU'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: codigoBarras,
                  decoration: const InputDecoration(labelText: 'Codigo de barras (opcional)'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: precio,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Precio',
                          prefixText: 'Bs ',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: precioOferta,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Oferta',
                          prefixText: 'Bs ',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                ElevatedButton(
                  onPressed: () => Navigator.pop(contexto, true),
                  child: const Text('GUARDAR VARIANTE'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final datos = VarianteIn(
      tallaId: tallaId ?? 0,
      colorId: colorId ?? 0,
      sku: sku.text.trim(),
      codigoBarras: codigoBarras.text.trim(),
      precio: double.tryParse(precio.text.replaceAll(',', '.')),
      precioOferta: double.tryParse(precioOferta.text.replaceAll(',', '.')),
    );
    for (final control in [sku, codigoBarras, precio, precioOferta]) {
      control.dispose();
    }
    if (guardado != true) return;
    if (datos.sku.length < 2) {
      if (!mounted) return;
      mostrarAviso(context, 'El SKU debe tener al menos 2 caracteres.', esError: true);
      return;
    }

    await _ejecutar(
      () => variante == null
          ? catalogoAdminService.crearVariante(producto.id, datos)
          : catalogoAdminService.actualizarVariante(variante.id, datos),
    );
  }

  Future<void> _agregarImagen() async {
    final producto = _producto;
    if (producto == null) return;

    final url = TextEditingController();
    bool principal = producto.imagenes.isEmpty;

    final guardado = await showDialog<bool>(
      context: context,
      builder: (contexto) => StatefulBuilder(
        builder: (contexto, actualizar) => AlertDialog(
          backgroundColor: Paleta.blanco,
          title: const Text('Agregar imagen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: url,
                decoration: const InputDecoration(
                  labelText: 'URL de la imagen',
                  hintText: 'https://...',
                ),
              ),
              CheckboxListTile(
                value: principal,
                onChanged: (valor) => actualizar(() => principal = valor ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Paleta.flame,
                title: const Text('Es la principal', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(contexto, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(contexto, true),
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );

    final texto = url.text.trim();
    url.dispose();
    if (guardado != true || texto.length < 4) return;

    await _ejecutar(
      () => catalogoAdminService.agregarImagen(
        producto.id,
        url: texto,
        esPrincipal: principal,
        orden: producto.imagenes.length,
      ),
    );
  }

  Future<void> _ejecutar(Future<void> Function() accion) async {
    try {
      await accion();
      if (!mounted) return;
      mostrarAviso(context, 'Cambios guardados');
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final producto = _producto;
    final puedeGestionar = context.watch<AuthService>().tienePermiso(['catalogo.gestionar']);

    return Scaffold(
      appBar: AppBar(
        title: Text(producto?.nombre ?? 'Prenda'),
        actions: [
          if (puedeGestionar && producto != null)
            IconButton(onPressed: _editar, icon: const Icon(Icons.edit_outlined)),
        ],
      ),
      body: VistaAsincrona(
        cargando: _cargando,
        error: _error,
        alReintentar: _cargar,
        hijo: producto == null
            ? const EstadoVacio(mensaje: 'No se encontro la prenda.')
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  TarjetaPanel(
                    hijo: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: EtiquetaDato(producto.codigo)),
                            BadgeEstado(producto.activo ? 'ACTIVA' : 'INACTIVA'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        FilaDato('Categoria', producto.categoria),
                        if (producto.marca != null) FilaDato('Marca', producto.marca!),
                        if (producto.proveedor != null)
                          FilaDato('Proveedor', producto.proveedor!),
                        if (producto.temporada != null)
                          FilaDato('Temporada', producto.temporada!),
                        if (producto.coleccion != null)
                          FilaDato('Coleccion', producto.coleccion!),
                        if (producto.material != null) FilaDato('Material', producto.material!),
                        if (producto.genero != null) FilaDato('Genero', producto.genero!),
                        FilaDato('Precio base', formatearPrecio(producto.precioBase)),
                        FilaDato('Stock total', '${producto.stockTotal}'),
                        if (puedeGestionar) ...[
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: _cambiarEstado,
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  producto.activo ? Paleta.rojo : Paleta.verde,
                              side: BorderSide(
                                color: producto.activo ? Paleta.rojo : Paleta.verde,
                              ),
                            ),
                            child: Text(
                              producto.activo ? 'RETIRAR DE LA VITRINA' : 'PUBLICAR',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(child: EtiquetaDato('Variantes (talla x color)')),
                      if (puedeGestionar)
                        TextButton.icon(
                          onPressed: () => _editarVariante(),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Agregar'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (producto.variantes.isEmpty)
                    const Text(
                      'Sin variantes: la prenda no se puede vender ni reservar todavia.',
                      style: TextStyle(fontSize: 13, color: Paleta.inkSuave),
                    )
                  else
                    ...producto.variantes.map(
                      (variante) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TarjetaPanel(
                          padding: const EdgeInsets.all(12),
                          hijo: Row(
                            children: [
                              CircleAvatar(
                                radius: 10,
                                backgroundColor: colorDesdeHex(variante.codigoHex),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${variante.talla} · ${variante.color}',
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    Text(
                                      variante.sku,
                                      style: fuenteMono(fontSize: 11.5, fontWeight: FontWeight.w500, color: Paleta.inkSuave),
                                    ),
                                    Text(
                                      'Fisico ${variante.stockFisico} · '
                                      'disponible ${variante.stockDisponible}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    formatearPrecio(
                                      variante.precioOferta ??
                                          variante.precio ??
                                          producto.precioBase,
                                    ),
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  if (puedeGestionar)
                                    Row(
                                      children: [
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => _editarVariante(variante: variante),
                                          icon: const Icon(Icons.edit_outlined, size: 18),
                                        ),
                                        Switch(
                                          value: variante.activa,
                                          activeThumbColor: Paleta.flame,
                                          onChanged: (valor) => _ejecutar(
                                            () => catalogoAdminService
                                                .cambiarEstadoVariante(variante.id, valor),
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    BadgeEstado(variante.activa ? 'ACTIVA' : 'INACTIVA'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(child: EtiquetaDato('Imagenes')),
                      if (puedeGestionar)
                        TextButton.icon(
                          onPressed: _agregarImagen,
                          icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                          label: const Text('Agregar'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (producto.imagenes.isEmpty)
                    const Text(
                      'Sin imagenes cargadas.',
                      style: TextStyle(fontSize: 13, color: Paleta.inkSuave),
                    )
                  else
                    SizedBox(
                      height: 150,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: producto.imagenes.length,
                        separatorBuilder: (contexto, indice) => const SizedBox(width: 10),
                        itemBuilder: (contexto, indice) {
                          final imagen = producto.imagenes[indice];
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 110,
                                  height: 150,
                                  child: ImagenPrenda(url: imagen.url),
                                ),
                              ),
                              if (imagen.esPrincipal)
                                const Positioned(
                                  left: 6,
                                  top: 6,
                                  child: BadgeEstado('PRINCIPAL', color: Paleta.gold),
                                ),
                              if (puedeGestionar)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18),
                                    color: Paleta.rojo,
                                    onPressed: () => _ejecutar(
                                      () => catalogoAdminService.eliminarImagen(imagen.id),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

// --- Categorias y marcas ---------------------------------------------------

class _PestanaCategorias extends StatefulWidget {
  const _PestanaCategorias({required this.referencias, required this.alCambiar});

  final ReferenciasOut referencias;
  final VoidCallback alCambiar;

  @override
  State<_PestanaCategorias> createState() => _PestanaCategoriasState();
}

class _PestanaCategoriasState extends State<_PestanaCategorias> {
  List<CategoriaAdminOut> _categorias = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final categorias = await catalogoAdminService.listarCategorias();
      if (!mounted) return;
      setState(() {
        _categorias = categorias;
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

  Future<void> _editarCategoria({CategoriaAdminOut? categoria}) async {
    final nombre = TextEditingController(text: categoria?.nombre ?? '');
    final imagen = TextEditingController(text: categoria?.imagenUrl ?? '');
    final orden = TextEditingController(text: '${categoria?.orden ?? 0}');
    String? padreId = categoria?.categoriaPadreId;

    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Paleta.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (contexto) => StatefulBuilder(
        builder: (contexto, actualizar) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(contexto).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Titular(categoria == null ? 'Nueva categoria' : 'Editar categoria', tamano: 24),
                const SizedBox(height: 18),
                TextField(
                  controller: nombre,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: padreId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Categoria padre (opcional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Sin padre')),
                    ..._categorias
                        .where((c) => c.id != categoria?.id)
                        .map((c) => DropdownMenuItem(value: c.id, child: Text(c.nombre))),
                  ],
                  onChanged: (valor) => actualizar(() => padreId = valor),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: imagen,
                  decoration: const InputDecoration(labelText: 'Imagen (URL, opcional)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: orden,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Orden en el menu'),
                ),
                const SizedBox(height: 22),
                ElevatedButton(
                  onPressed: () => Navigator.pop(contexto, true),
                  child: const Text('GUARDAR'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final textoNombre = nombre.text.trim();
    final textoImagen = imagen.text.trim();
    final numeroOrden = int.tryParse(orden.text) ?? 0;
    for (final control in [nombre, imagen, orden]) {
      control.dispose();
    }
    if (guardado != true || textoNombre.length < 2) return;

    try {
      if (categoria == null) {
        await catalogoAdminService.crearCategoria(
          nombre: textoNombre,
          categoriaPadreId: padreId,
          imagenUrl: textoImagen,
          orden: numeroOrden,
        );
      } else {
        await catalogoAdminService.actualizarCategoria(
          categoria.id,
          nombre: textoNombre,
          categoriaPadreId: padreId,
          imagenUrl: textoImagen,
          orden: numeroOrden,
        );
      }
      if (!mounted) return;
      await _cargar();
      widget.alCambiar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  Future<void> _cambiarEstadoCategoria(CategoriaAdminOut categoria, bool activa) async {
    try {
      await catalogoAdminService.cambiarEstadoCategoria(categoria.id, activa);
      if (!mounted) return;
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  Future<void> _nuevaMarca() async {
    final nombre = TextEditingController();
    final logo = TextEditingController();

    final guardado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        backgroundColor: Paleta.blanco,
        title: const Text('Nueva marca'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombre,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: logo,
              decoration: const InputDecoration(labelText: 'Logo (URL, opcional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contexto, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(contexto, true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    final textoNombre = nombre.text.trim();
    final textoLogo = logo.text.trim();
    nombre.dispose();
    logo.dispose();
    if (guardado != true || textoNombre.isEmpty) return;

    try {
      await catalogoAdminService.crearMarca(textoNombre, logoUrl: textoLogo);
      if (!mounted) return;
      mostrarAviso(context, 'Marca creada');
      widget.alCambiar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final puedeGestionar = context.watch<AuthService>().tienePermiso(['catalogo.gestionar']);

    return Scaffold(
      backgroundColor: Paleta.paper,
      floatingActionButton: puedeGestionar
          ? FloatingActionButton.extended(
              onPressed: () => _editarCategoria(),
              backgroundColor: Paleta.flame,
              foregroundColor: Paleta.blanco,
              icon: const Icon(Icons.add),
              label: const Text('CATEGORIA'),
            )
          : null,
      body: VistaAsincrona(
        cargando: _cargando,
        error: _error,
        alReintentar: _cargar,
        hijo: RefreshIndicator(
          color: Paleta.flame,
          onRefresh: _cargar,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            children: [
              Row(
                children: [
                  const Expanded(child: EtiquetaDato('Marcas')),
                  if (puedeGestionar)
                    TextButton.icon(
                      onPressed: _nuevaMarca,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Nueva marca'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.referencias.marcas.isEmpty
                    ? [
                        const Text(
                          'Sin marcas cargadas.',
                          style: TextStyle(fontSize: 13, color: Paleta.inkSuave),
                        ),
                      ]
                    : widget.referencias.marcas
                        .map((m) => Chip(label: Text(m.nombre)))
                        .toList(),
              ),
              const SizedBox(height: 24),
              const EtiquetaDato('Categorias'),
              const SizedBox(height: 8),
              if (_categorias.isEmpty)
                const EstadoVacio(mensaje: 'No hay categorias cargadas.')
              else
                ..._categorias.map(
                  (categoria) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TarjetaPanel(
                      hijo: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  categoria.nombre,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${categoria.productos} producto(s)'
                                  '${categoria.categoriaPadre == null ? "" : " · dentro de ${categoria.categoriaPadre}"}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Paleta.inkSuave,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          BadgeEstado(categoria.activa ? 'ACTIVA' : 'OCULTA'),
                          if (puedeGestionar) ...[
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _editarCategoria(categoria: categoria),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                            ),
                            Switch(
                              value: categoria.activa,
                              activeThumbColor: Paleta.flame,
                              onChanged: (valor) =>
                                  _cambiarEstadoCategoria(categoria, valor),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
