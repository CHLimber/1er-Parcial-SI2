import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../compartido/widgets.dart';
import '../core/auth/auth_service.dart';
import '../core/config.dart';
import '../core/errores.dart';
import '../core/proveedores/proveedores_service.dart';
import '../core/recepciones/recepciones_service.dart';
import '../core/tema.dart';
import 'mis_reservas_pagina.dart' show fechaLegible;

/// CU09: Registrar Recepcion de Mercaderia. Es el unico camino por el que entra stock
/// nuevo: confirmar dispara `tg_confirmar_recepcion`, que llama a `fn_mover_inventario`
/// con tipo ENTRADA por cada linea y deja el asiento en el kardex.
class PanelRecepcionesPagina extends StatefulWidget {
  const PanelRecepcionesPagina({super.key});

  @override
  State<PanelRecepcionesPagina> createState() => _PanelRecepcionesPaginaState();
}

class _PanelRecepcionesPaginaState extends State<PanelRecepcionesPagina> {
  List<RecepcionOut> _recepciones = [];
  String? _estado;
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
      final recepciones = await recepcionesService.listar(estado: _estado);
      if (!mounted) return;
      setState(() {
        _recepciones = recepciones;
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

  Future<void> _nuevaRecepcion() async {
    List<ProveedorOut> proveedores;
    try {
      proveedores = await proveedoresService.listar(activo: true);
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
      return;
    }
    if (!mounted) return;
    if (proveedores.isEmpty) {
      mostrarAviso(context, 'Primero da de alta un proveedor (CU11).', esError: true);
      return;
    }

    final numero = TextEditingController();
    String proveedorId = proveedores.first.id;
    DateTime fecha = DateTime.now();

    final creado = await showModalBottomSheet<bool>(
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
                const Titular('Nueva recepcion', tamano: 24),
                const SizedBox(height: 6),
                const Text(
                  'Se crea en BORRADOR: podras cargar las lineas y recien al confirmar '
                  'entra el stock.',
                  style: TextStyle(fontSize: 13, color: Paleta.inkSuave, height: 1.4),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: proveedorId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Proveedor'),
                  items: proveedores
                      .map(
                        (p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(p.nombre, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (valor) => actualizar(() => proveedorId = valor ?? proveedorId),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: numero,
                  decoration: const InputDecoration(
                    labelText: 'Numero de guia (opcional)',
                    hintText: 'Se genera solo si lo dejas vacio',
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final elegida = await showDatePicker(
                      context: contexto,
                      initialDate: fecha,
                      firstDate: DateTime(fecha.year - 1),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (elegida != null) actualizar(() => fecha = elegida);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Fecha'),
                    child: Text(fecha.toIso8601String().split('T').first),
                  ),
                ),
                const SizedBox(height: 22),
                ElevatedButton(
                  onPressed: () => Navigator.pop(contexto, true),
                  child: const Text('CREAR BORRADOR'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final textoNumero = numero.text.trim();
    numero.dispose();
    if (creado != true) return;

    try {
      final recepcion = await recepcionesService.crear(
        proveedorId: proveedorId,
        numero: textoNumero,
        fecha: fecha,
      );
      if (!mounted) return;
      await _abrirDetalle(recepcion.id);
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  Future<void> _abrirDetalle(String recepcionId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (contexto) => DetalleRecepcionPagina(recepcionId: recepcionId),
      ),
    );
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final puedeRegistrar = context.watch<AuthService>().tienePermiso(['recepciones.registrar']);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recepciones'),
        actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: puedeRegistrar
          ? FloatingActionButton.extended(
              onPressed: _nuevaRecepcion,
              backgroundColor: Paleta.flame,
              foregroundColor: Paleta.blanco,
              icon: const Icon(Icons.add),
              label: const Text('NUEVA'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
            child: Row(
              children: [
                _chip('Todas', null),
                _chip('Borrador', 'BORRADOR'),
                _chip('Confirmadas', 'CONFIRMADA'),
                _chip('Anuladas', 'ANULADA'),
              ],
            ),
          ),
          Expanded(
            child: VistaAsincrona(
              cargando: _cargando,
              error: _error,
              alReintentar: _cargar,
              hijo: _recepciones.isEmpty
                  ? const EstadoVacio(mensaje: 'No hay recepciones con ese estado.')
                  : RefreshIndicator(
                      color: Paleta.flame,
                      onRefresh: _cargar,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 90),
                        itemCount: _recepciones.length,
                        separatorBuilder: (contexto, indice) => const SizedBox(height: 10),
                        itemBuilder: (contexto, indice) {
                          final recepcion = _recepciones[indice];
                          return TarjetaPanel(
                            alTocar: () => _abrirDetalle(recepcion.id),
                            hijo: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        recepcion.numero,
                                        style: fuenteMono(fontSize: 14, fontWeight: FontWeight.w700, color: Paleta.ink),
                                      ),
                                    ),
                                    BadgeEstado(recepcion.estado),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                FilaDato('Proveedor', recepcion.proveedor),
                                FilaDato('Sucursal', recepcion.sucursal),
                                FilaDato('Fecha', recepcion.fecha),
                                FilaDato(
                                  'Contenido',
                                  '${recepcion.lineas} linea(s) · ${recepcion.unidades} unidad(es)',
                                ),
                                if (recepcion.total != null)
                                  FilaDato('Costo total', formatearPrecio(recepcion.total!)),
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

  Widget _chip(String etiqueta, String? valor) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          label: Text(etiqueta),
          selected: _estado == valor,
          selectedColor: Paleta.flame.withValues(alpha: 0.16),
          onSelected: (_) {
            setState(() => _estado = valor);
            _cargar();
          },
        ),
      );
}

/// Detalle de una recepcion: carga de lineas y confirmacion.
class DetalleRecepcionPagina extends StatefulWidget {
  const DetalleRecepcionPagina({super.key, required this.recepcionId});

  final String recepcionId;

  @override
  State<DetalleRecepcionPagina> createState() => _DetalleRecepcionPaginaState();
}

class _DetalleRecepcionPaginaState extends State<DetalleRecepcionPagina> {
  RecepcionDetalleOut? _recepcion;
  List<MovimientoOut> _movimientos = [];
  bool _cargando = true;
  bool _trabajando = false;
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
      final recepcion = await recepcionesService.obtener(widget.recepcionId);
      final movimientos = recepcion.estado == 'CONFIRMADA'
          ? await recepcionesService.movimientos(widget.recepcionId)
          : <MovimientoOut>[];
      if (!mounted) return;
      setState(() {
        _recepcion = recepcion;
        _movimientos = movimientos;
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

  Future<void> _agregarLinea({DetalleOut? linea}) async {
    final recepcion = _recepcion;
    if (recepcion == null) return;

    final resultado = await showModalBottomSheet<_LineaEditada>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Paleta.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (contexto) => _HojaLinea(sucursalId: recepcion.sucursalId, linea: linea),
    );
    if (resultado == null) return;

    setState(() => _trabajando = true);
    try {
      if (linea == null) {
        await recepcionesService.agregarLinea(
          recepcion.id,
          varianteId: resultado.varianteId,
          cantidad: resultado.cantidad,
          costoUnitario: resultado.costoUnitario,
        );
      } else {
        await recepcionesService.editarLinea(
          recepcion.id,
          linea.id,
          varianteId: resultado.varianteId,
          cantidad: resultado.cantidad,
          costoUnitario: resultado.costoUnitario,
        );
      }
      if (!mounted) return;
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _quitarLinea(DetalleOut linea) async {
    final confirmado = await confirmar(
      context,
      titulo: 'Quitar linea',
      mensaje: 'Se elimina ${linea.sku} del borrador.',
      textoConfirmar: 'Quitar',
      destructivo: true,
    );
    if (!confirmado) return;
    try {
      await recepcionesService.quitarLinea(widget.recepcionId, linea.id);
      if (!mounted) return;
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  Future<void> _confirmarRecepcion() async {
    final recepcion = _recepcion;
    if (recepcion == null) return;

    final confirmado = await confirmar(
      context,
      titulo: 'Confirmar recepcion',
      mensaje: 'Entran ${recepcion.unidades} unidad(es) al inventario de '
          '${recepcion.sucursal}. Una recepcion confirmada no se edita ni se anula '
          'despues: el kardex es append-only y se corrige con un ajuste.',
      textoConfirmar: 'Confirmar',
    );
    if (!confirmado) return;

    setState(() => _trabajando = true);
    try {
      await recepcionesService.confirmar(recepcion.id);
      if (!mounted) return;
      mostrarAviso(context, 'Recepcion confirmada: el stock ya entro');
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _anular() async {
    final confirmado = await confirmar(
      context,
      titulo: 'Anular borrador',
      mensaje: 'La recepcion queda ANULADA y no podra confirmarse.',
      textoConfirmar: 'Anular',
      destructivo: true,
    );
    if (!confirmado) return;
    try {
      await recepcionesService.anular(widget.recepcionId);
      if (!mounted) return;
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recepcion = _recepcion;
    final auth = context.watch<AuthService>();
    final puedeRegistrar = auth.tienePermiso(['recepciones.registrar']);
    final puedeConfirmar = auth.tienePermiso(['recepciones.confirmar']);
    final esBorrador = recepcion?.esBorrador ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(recepcion?.numero ?? 'Recepcion')),
      floatingActionButton: (esBorrador && puedeRegistrar)
          ? FloatingActionButton.extended(
              onPressed: _trabajando ? null : () => _agregarLinea(),
              backgroundColor: Paleta.flame,
              foregroundColor: Paleta.blanco,
              icon: const Icon(Icons.add),
              label: const Text('LINEA'),
            )
          : null,
      body: VistaAsincrona(
        cargando: _cargando,
        error: _error,
        alReintentar: _cargar,
        hijo: recepcion == null
            ? const EstadoVacio(mensaje: 'No se encontro la recepcion.')
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                children: [
                  TarjetaPanel(
                    hijo: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                recepcion.numero,
                                style: fuenteMono(fontSize: 15, fontWeight: FontWeight.w700, color: Paleta.ink),
                              ),
                            ),
                            BadgeEstado(recepcion.estado),
                          ],
                        ),
                        const SizedBox(height: 8),
                        FilaDato('Proveedor', recepcion.proveedor),
                        FilaDato('Sucursal', recepcion.sucursal),
                        FilaDato('Fecha', recepcion.fecha),
                        if (recepcion.coleccion != null)
                          FilaDato('Coleccion', recepcion.coleccion!),
                        if (recepcion.registradoPor != null)
                          FilaDato('Registro', recepcion.registradoPor!),
                        FilaDato(
                          'Contenido',
                          '${recepcion.lineas} linea(s) · ${recepcion.unidades} unidad(es)',
                        ),
                        if (recepcion.total != null)
                          FilaDato('Costo total', formatearPrecio(recepcion.total!)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const EtiquetaDato('Detalle'),
                  const SizedBox(height: 8),
                  if (recepcion.detalle.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: EstadoVacio(
                        mensaje: 'El borrador todavia no tiene lineas cargadas.',
                        icono: Icons.playlist_add,
                      ),
                    )
                  else
                    ...recepcion.detalle.map(
                      (linea) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TarjetaPanel(
                          padding: const EdgeInsets.all(12),
                          hijo: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      linea.producto,
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  Text(
                                    formatearPrecio(linea.subtotal),
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${linea.sku} · ${linea.talla} · ${linea.color}',
                                style: const TextStyle(fontSize: 12, color: Paleta.inkSuave),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${linea.cantidad} unidad(es) x '
                                '${formatearPrecio(linea.costoUnitario)}',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                              if (esBorrador && puedeRegistrar) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: () => _agregarLinea(linea: linea),
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      child: const Text('Editar'),
                                    ),
                                    TextButton(
                                      onPressed: () => _quitarLinea(linea),
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        foregroundColor: Paleta.rojo,
                                      ),
                                      child: const Text('Quitar'),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_movimientos.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const EtiquetaDato('Asientos del kardex'),
                    const SizedBox(height: 8),
                    ..._movimientos.map(
                      (movimiento) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TarjetaPanel(
                          padding: const EdgeInsets.all(12),
                          hijo: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                movimiento.producto,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${movimiento.sku} · +${movimiento.cantidad} · '
                                'saldo ${movimiento.saldoAnterior} -> ${movimiento.saldoNuevo}',
                                style: fuenteMono(fontSize: 12, fontWeight: FontWeight.w500, color: Paleta.inkSuave),
                              ),
                              if (movimiento.fecha != null)
                                Text(
                                  fechaLegible(movimiento.fecha!),
                                  style: const TextStyle(fontSize: 11, color: Paleta.inkSuave),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (esBorrador) ...[
                    const SizedBox(height: 22),
                    if (puedeConfirmar)
                      ElevatedButton.icon(
                        onPressed: (_trabajando || recepcion.detalle.isEmpty)
                            ? null
                            : _confirmarRecepcion,
                        icon: const Icon(Icons.inventory_outlined),
                        label: const Text('CONFIRMAR Y CARGAR STOCK'),
                      ),
                    if (puedeConfirmar) const SizedBox(height: 10),
                    if (puedeConfirmar)
                      OutlinedButton(
                        onPressed: _trabajando ? null : _anular,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Paleta.rojo,
                          side: const BorderSide(color: Paleta.rojo),
                        ),
                        child: const Text('ANULAR BORRADOR'),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _LineaEditada {
  const _LineaEditada({
    required this.varianteId,
    required this.cantidad,
    required this.costoUnitario,
  });

  final String varianteId;
  final int cantidad;
  final double costoUnitario;
}

/// Buscador de variante + cantidad + costo para una linea de la recepcion.
class _HojaLinea extends StatefulWidget {
  const _HojaLinea({required this.sucursalId, this.linea});

  final String sucursalId;
  final DetalleOut? linea;

  @override
  State<_HojaLinea> createState() => _HojaLineaState();
}

class _HojaLineaState extends State<_HojaLinea> {
  final _busqueda = TextEditingController();
  final _cantidad = TextEditingController(text: '1');
  final _costo = TextEditingController();

  List<VarianteBuscadaOut> _resultados = [];
  VarianteBuscadaOut? _elegida;
  String? _varianteIdInicial;
  bool _buscando = false;

  @override
  void initState() {
    super.initState();
    final linea = widget.linea;
    if (linea != null) {
      _varianteIdInicial = linea.varianteId;
      _busqueda.text = linea.sku;
      _cantidad.text = '${linea.cantidad}';
      _costo.text = linea.costoUnitario.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _busqueda.dispose();
    _cantidad.dispose();
    _costo.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final q = _busqueda.text.trim();
    if (q.isEmpty) return;
    setState(() => _buscando = true);
    try {
      final resultados = await recepcionesService.buscarVariantes(
        q,
        sucursalId: widget.sucursalId,
      );
      if (!mounted) return;
      setState(() => _resultados = resultados);
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  void _guardar() {
    final varianteId = _elegida?.id ?? _varianteIdInicial;
    final cantidad = int.tryParse(_cantidad.text.trim());
    final costo = double.tryParse(_costo.text.trim().replaceAll(',', '.'));

    if (varianteId == null) {
      mostrarAviso(context, 'Elige la prenda que estas recibiendo.', esError: true);
      return;
    }
    if (cantidad == null || cantidad <= 0) {
      mostrarAviso(context, 'La cantidad debe ser mayor a cero.', esError: true);
      return;
    }
    if (costo == null || costo < 0) {
      mostrarAviso(context, 'Escribe el costo unitario.', esError: true);
      return;
    }

    Navigator.pop(
      context,
      _LineaEditada(varianteId: varianteId, cantidad: cantidad, costoUnitario: costo),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          maxChildSize: 0.92,
          builder: (contexto, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            children: [
              Titular(widget.linea == null ? 'Agregar linea' : 'Editar linea', tamano: 24),
              const SizedBox(height: 16),
              TextField(
                controller: _busqueda,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _buscar(),
                decoration: InputDecoration(
                  labelText: 'SKU, codigo de barras o nombre',
                  suffixIcon: IconButton(
                    icon: _buscando
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    onPressed: _buscando ? null : _buscar,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_resultados.isNotEmpty)
                ..._resultados.map(
                  (variante) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TarjetaPanel(
                      padding: const EdgeInsets.all(10),
                      alTocar: () => setState(() {
                        _elegida = variante;
                        if (_costo.text.isEmpty) {
                          _costo.text = variante.precioBase.toStringAsFixed(2);
                        }
                      }),
                      hijo: Row(
                        children: [
                          Icon(
                            _elegida?.id == variante.id
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: Paleta.flame,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  variante.producto,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '${variante.sku} · ${variante.talla} · ${variante.color} · '
                                  'stock ${variante.stockSucursal}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Paleta.inkSuave,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cantidad,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Cantidad'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _costo,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Costo unitario',
                        prefixText: 'Bs ',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              ElevatedButton(onPressed: _guardar, child: const Text('GUARDAR LINEA')),
            ],
          ),
        ),
      );
}
