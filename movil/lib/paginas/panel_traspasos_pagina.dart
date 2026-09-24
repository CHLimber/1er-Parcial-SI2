import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../compartido/widgets.dart';
import '../core/auth/auth_service.dart';
import '../core/errores.dart';
import '../core/sucursales/sucursales_models.dart';
import '../core/sucursales/sucursales_service.dart';
import '../core/tema.dart';
import '../core/traspasos/traspasos_service.dart';
import 'mis_reservas_pagina.dart' show fechaLegible;

/// Traspasos entre sucursales (PENDIENTES 2.7/2.19.7, espejo de `panel-traspasos` en la
/// web). Las tres tiendas estan en climas distintos y el surtido rota diferente en cada
/// una: el origen solicita y despacha (sale su stock), el destino recibe indicando lo que
/// llego (entra eso). SOLICITADO y EN_TRANSITO se pueden anular; RECIBIDO no.
class PanelTraspasosPagina extends StatefulWidget {
  const PanelTraspasosPagina({super.key});

  @override
  State<PanelTraspasosPagina> createState() => _PanelTraspasosPaginaState();
}

class _PanelTraspasosPaginaState extends State<PanelTraspasosPagina> {
  List<TraspasoOut> _traspasos = [];
  String? _estado;
  String? _direccion;
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
      final traspasos = await traspasosService.listar(estado: _estado, direccion: _direccion);
      if (!mounted) return;
      setState(() {
        _traspasos = traspasos;
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

  Future<void> _abrirDetalle(String traspasoId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (contexto) => DetalleTraspasoPagina(traspasoId: traspasoId),
      ),
    );
    await _cargar();
  }

  Future<void> _nuevoTraspaso() async {
    final creado = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (contexto) => const NuevoTraspasoPagina()),
    );
    if (creado == true) await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final puedeCrear = context.watch<AuthService>().tienePermiso(['traspasos.crear']);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Traspasos'),
        actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: puedeCrear
          ? FloatingActionButton.extended(
              onPressed: _nuevoTraspaso,
              backgroundColor: Paleta.flame,
              foregroundColor: Paleta.blanco,
              icon: const Icon(Icons.add),
              label: const Text('NUEVO'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _chipEstado('Todos', null),
                _chipEstado('Solicitados', 'SOLICITADO'),
                _chipEstado('En transito', 'EN_TRANSITO'),
                _chipEstado('Recibidos', 'RECIBIDO'),
                _chipEstado('Anulados', 'ANULADO'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _chipDireccion('Ambas direcciones', null),
                _chipDireccion('Salientes', 'SALIENTES'),
                _chipDireccion('Entrantes', 'ENTRANTES'),
              ],
            ),
          ),
          Expanded(
            child: VistaAsincrona(
              cargando: _cargando,
              error: _error,
              alReintentar: _cargar,
              hijo: _traspasos.isEmpty
                  ? const EstadoVacio(mensaje: 'No hay traspasos con ese filtro.')
                  : RefreshIndicator(
                      color: Paleta.flame,
                      onRefresh: _cargar,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 90),
                        itemCount: _traspasos.length,
                        separatorBuilder: (contexto, indice) => const SizedBox(height: 10),
                        itemBuilder: (contexto, indice) {
                          final traspaso = _traspasos[indice];
                          return TarjetaPanel(
                            alTocar: () => _abrirDetalle(traspaso.id),
                            hijo: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        traspaso.numero,
                                        style: fuenteMono(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: Paleta.ink,
                                        ),
                                      ),
                                    ),
                                    BadgeEstado(traspaso.estado),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                FilaDato('Origen', traspaso.origen),
                                FilaDato('Destino', traspaso.destino),
                                FilaDato(
                                  'Contenido',
                                  '${traspaso.lineas} linea(s) · ${traspaso.unidadesSolicitadas} unidad(es)',
                                ),
                                if (traspaso.unidadesRecibidas != null)
                                  FilaDato('Recibidas', '${traspaso.unidadesRecibidas}'),
                                FilaDato(
                                  'Solicitado',
                                  fechaLegible(DateTime.parse(traspaso.fechaSolicitud)),
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

  Widget _chipEstado(String etiqueta, String? valor) => FilterChip(
        label: Text(etiqueta),
        selected: _estado == valor,
        selectedColor: Paleta.flame.withValues(alpha: 0.16),
        onSelected: (_) {
          setState(() => _estado = valor);
          _cargar();
        },
      );

  Widget _chipDireccion(String etiqueta, String? valor) => FilterChip(
        label: Text(etiqueta),
        selected: _direccion == valor,
        selectedColor: Paleta.gold.withValues(alpha: 0.2),
        onSelected: (_) {
          setState(() => _direccion = valor);
          _cargar();
        },
      );
}

class _LineaNueva {
  _LineaNueva(this.variante, this.cantidad);

  final VarianteTraspasoOut variante;
  int cantidad;
}

/// Alta de un traspaso: se eligen origen/destino (el que no es ADMIN siempre manda desde
/// su sucursal), se buscan variantes y se arma la lista de lineas. No mueve stock: recien
/// se descuenta del origen al despachar.
class NuevoTraspasoPagina extends StatefulWidget {
  const NuevoTraspasoPagina({super.key});

  @override
  State<NuevoTraspasoPagina> createState() => _NuevoTraspasoPaginaState();
}

class _NuevoTraspasoPaginaState extends State<NuevoTraspasoPagina> {
  final _busqueda = TextEditingController();

  List<SucursalOut> _sucursales = [];
  String? _origenId;
  String? _destinoId;
  List<VarianteTraspasoOut> _resultados = [];
  final List<_LineaNueva> _lineas = [];
  bool _cargandoSucursales = true;
  bool _buscando = false;
  bool _creando = false;

  @override
  void initState() {
    super.initState();
    _cargarSucursales();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargarSucursales() async {
    try {
      final sucursales = await sucursalesService.listar();
      if (!mounted) return;
      setState(() {
        _sucursales = sucursales;
        _cargandoSucursales = false;
        if (_eligeOrigen && sucursales.isNotEmpty) _origenId = sucursales.first.id;
        _destinoId = sucursales.firstWhere((s) => s.id != _origenId, orElse: () => sucursales.first).id;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _cargandoSucursales = false);
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  bool get _eligeOrigen =>
      context.read<AuthService>().tienePermiso(['sucursales.actualizar']);

  Future<void> _buscar() async {
    final termino = _busqueda.text.trim();
    if (termino.isEmpty) return;
    setState(() => _buscando = true);
    try {
      final resultados = await traspasosService.buscarVariantes(
        termino,
        origenId: _eligeOrigen ? _origenId : null,
        destinoId: _destinoId,
      );
      if (!mounted) return;
      setState(() {
        _resultados = resultados;
        _buscando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _buscando = false);
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  void _cambioSucursales() {
    setState(() {
      _resultados = [];
      _lineas.clear();
    });
  }

  void _agregar(VarianteTraspasoOut variante) {
    if (variante.disponibleOrigen <= 0) {
      mostrarAviso(context, '${variante.sku} no tiene unidades disponibles en el origen.', esError: true);
      return;
    }
    if (_lineas.any((l) => l.variante.id == variante.id)) return;
    setState(() => _lineas.add(_LineaNueva(variante, 1)));
  }

  void _fijarCantidad(String varianteId, int valor) {
    setState(() {
      final linea = _lineas.firstWhere((l) => l.variante.id == varianteId);
      linea.cantidad = valor.clamp(1, linea.variante.disponibleOrigen);
    });
  }

  void _quitar(String varianteId) {
    setState(() => _lineas.removeWhere((l) => l.variante.id == varianteId));
  }

  Future<void> _crear() async {
    if (_destinoId == null) {
      mostrarAviso(context, 'Elige la sucursal de destino.', esError: true);
      return;
    }
    if (_lineas.isEmpty) {
      mostrarAviso(context, 'Agrega al menos una prenda.', esError: true);
      return;
    }
    setState(() => _creando = true);
    try {
      await traspasosService.crear(
        sucursalOrigenId: _eligeOrigen ? _origenId : null,
        sucursalDestinoId: _destinoId!,
        lineas: _lineas.map((l) => MapEntry(l.variante.id, l.cantidad)).toList(),
      );
      if (!mounted) return;
      mostrarAviso(context, 'Traspaso solicitado. El stock sale del origen recien al despacharlo.');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    } finally {
      if (mounted) setState(() => _creando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unidades = _lineas.fold<int>(0, (suma, l) => suma + l.cantidad);

    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo traspaso')),
      body: _cargandoSucursales
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                if (_eligeOrigen) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _origenId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Sucursal de origen'),
                    items: _sucursales
                        .map((s) => DropdownMenuItem(value: s.id, child: Text(s.nombre)))
                        .toList(),
                    onChanged: (valor) {
                      setState(() => _origenId = valor);
                      _cambioSucursales();
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<String>(
                  initialValue: _destinoId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Sucursal de destino'),
                  items: _sucursales
                      .where((s) => s.id != _origenId)
                      .map((s) => DropdownMenuItem(value: s.id, child: Text(s.nombre)))
                      .toList(),
                  onChanged: (valor) {
                    setState(() => _destinoId = valor);
                    _cambioSucursales();
                  },
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _busqueda,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _buscar(),
                        decoration: const InputDecoration(
                          labelText: 'SKU, codigo de barras o nombre',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _buscando ? null : _buscar,
                      child: _buscando
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Paleta.blanco),
                            )
                          : const Icon(Icons.search),
                    ),
                  ],
                ),
                if (_resultados.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ..._resultados.map(
                    (variante) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TarjetaPanel(
                        padding: const EdgeInsets.all(10),
                        alTocar: () => _agregar(variante),
                        hijo: Row(
                          children: [
                            Icon(
                              _lineas.any((l) => l.variante.id == variante.id)
                                  ? Icons.check_circle
                                  : Icons.add_circle_outline,
                              color: Paleta.flame,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(variante.producto, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text(
                                    '${variante.sku} · ${variante.talla} · ${variante.color} · '
                                    'origen ${variante.disponibleOrigen} · destino ${variante.disponibleDestino}',
                                    style: const TextStyle(fontSize: 11.5, color: Paleta.inkSuave),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                if (_lineas.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const EtiquetaDato('Lineas del traspaso'),
                  const SizedBox(height: 8),
                  ..._lineas.map(
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
                                    linea.variante.producto,
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _quitar(linea.variante.id),
                                  icon: const Icon(Icons.close, size: 18, color: Paleta.rojo),
                                ),
                              ],
                            ),
                            Text(
                              '${linea.variante.sku} · ${linea.variante.talla} · ${linea.variante.color}',
                              style: const TextStyle(fontSize: 12, color: Paleta.inkSuave),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                IconButton(
                                  onPressed: linea.cantidad > 1
                                      ? () => _fijarCantidad(linea.variante.id, linea.cantidad - 1)
                                      : null,
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                                Text('${linea.cantidad}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                IconButton(
                                  onPressed: linea.cantidad < linea.variante.disponibleOrigen
                                      ? () => _fijarCantidad(linea.variante.id, linea.cantidad + 1)
                                      : null,
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                                const Spacer(),
                                Text(
                                  'max ${linea.variante.disponibleOrigen}',
                                  style: const TextStyle(fontSize: 11.5, color: Paleta.inkSuave),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('$unidades unidad(es) en total', style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: (_creando || _lineas.isEmpty) ? null : _crear,
                  child: _creando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Paleta.blanco),
                        )
                      : const Text('SOLICITAR TRASPASO'),
                ),
              ],
            ),
    );
  }
}

/// Detalle de un traspaso y su ciclo de vida: despachar (origen), recibir (destino,
/// informando cantidad recibida por linea) y anular.
class DetalleTraspasoPagina extends StatefulWidget {
  const DetalleTraspasoPagina({super.key, required this.traspasoId});

  final String traspasoId;

  @override
  State<DetalleTraspasoPagina> createState() => _DetalleTraspasoPaginaState();
}

class _DetalleTraspasoPaginaState extends State<DetalleTraspasoPagina> {
  TraspasoDetalleOut? _traspaso;
  List<MovimientoTraspasoOut> _movimientos = [];
  final Map<String, int> _recibidas = {};
  final _observacion = TextEditingController();
  bool _cargando = true;
  bool _trabajando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _observacion.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final traspaso = await traspasosService.obtener(widget.traspasoId);
      final movimientos = traspaso.estado == 'SOLICITADO'
          ? <MovimientoTraspasoOut>[]
          : await traspasosService.movimientos(widget.traspasoId);
      if (!mounted) return;
      setState(() {
        _traspaso = traspaso;
        _movimientos = movimientos;
        _recibidas
          ..clear()
          ..addEntries(traspaso.detalle.map((l) => MapEntry(l.id, l.cantidadSolicitada)));
        _observacion.clear();
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

  int get _faltante {
    final traspaso = _traspaso;
    if (traspaso == null) return 0;
    return traspaso.detalle.fold<int>(
      0,
      (suma, linea) => suma + linea.cantidadSolicitada - (_recibidas[linea.id] ?? linea.cantidadSolicitada),
    );
  }

  Future<void> _despachar() async {
    final confirmado = await confirmar(
      context,
      titulo: 'Despachar traspaso',
      mensaje: 'Sale el stock solicitado del origen. Si ya no hay disponible, se rechaza.',
      textoConfirmar: 'Despachar',
    );
    if (!confirmado) return;
    await _operar(
      () => traspasosService.despachar(widget.traspasoId),
      (t) => 'Despachado: ${t.unidadesSolicitadas} unidad(es) salieron del stock de ${t.origen}.',
    );
  }

  Future<void> _recibir() async {
    final confirmado = await confirmar(
      context,
      titulo: 'Recibir traspaso',
      mensaje: 'Entra al stock del destino lo que se informe recibido en cada linea.',
      textoConfirmar: 'Recibir',
    );
    if (!confirmado) return;
    await _operar(
      () => traspasosService.recibir(
        widget.traspasoId,
        recibidas: _recibidas.entries.toList(),
        observacion: _observacion.text.trim(),
      ),
      (t) {
        final faltan = t.unidadesSolicitadas - (t.unidadesRecibidas ?? 0);
        return 'Recibido: ${t.unidadesRecibidas} unidad(es) entraron al stock de ${t.destino}.'
            '${faltan > 0 ? " Faltaron $faltan: ya salieron del origen, corregilo con un ajuste en Inventario cuando se aclare." : ""}';
      },
    );
  }

  Future<void> _anular() async {
    final enTransito = _traspaso?.estado == 'EN_TRANSITO';
    final confirmado = await confirmar(
      context,
      titulo: 'Anular traspaso',
      mensaje: enTransito
          ? 'La mercaderia no llego a irse o volvio entera: el stock regresa al origen.'
          : 'No se habia movido stock.',
      textoConfirmar: 'Anular',
      destructivo: true,
    );
    if (!confirmado) return;
    await _operar(
      () => traspasosService.anular(widget.traspasoId),
      (t) => enTransito
          ? 'Traspaso anulado: las ${t.unidadesSolicitadas} unidad(es) volvieron al stock de ${t.origen}.'
          : 'Traspaso anulado. No se habia movido stock.',
    );
  }

  Future<void> _operar(
    Future<TraspasoDetalleOut> Function() accion,
    String Function(TraspasoDetalleOut) mensaje,
  ) async {
    setState(() => _trabajando = true);
    try {
      final detalle = await accion();
      if (!mounted) return;
      await _cargar();
      if (!mounted) return;
      mostrarAviso(context, mensaje(detalle));
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final traspaso = _traspaso;
    final auth = context.watch<AuthService>();
    final puedeMover = auth.tienePermiso(['traspasos.actualizar']);
    final puedeAnular = auth.tienePermiso(['traspasos.eliminar']);

    final puedeDespachar =
        puedeMover && traspaso != null && traspaso.estado == 'SOLICITADO' && traspaso.miLado != 'DESTINO';
    final puedeRecibir =
        puedeMover && traspaso != null && traspaso.estado == 'EN_TRANSITO' && traspaso.miLado != 'ORIGEN';
    final puedeAnularlo = traspaso != null &&
        puedeAnular &&
        (traspaso.estado == 'SOLICITADO' ||
            (traspaso.estado == 'EN_TRANSITO' && traspaso.miLado != 'DESTINO'));

    return Scaffold(
      appBar: AppBar(title: Text(traspaso?.numero ?? 'Traspaso')),
      body: VistaAsincrona(
        cargando: _cargando,
        error: _error,
        alReintentar: _cargar,
        hijo: traspaso == null
            ? const EstadoVacio(mensaje: 'No se encontro el traspaso.')
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  TarjetaPanel(
                    hijo: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                traspaso.numero,
                                style: fuenteMono(fontSize: 15, fontWeight: FontWeight.w700, color: Paleta.ink),
                              ),
                            ),
                            BadgeEstado(traspaso.estado),
                          ],
                        ),
                        const SizedBox(height: 8),
                        FilaDato('Origen', traspaso.origen),
                        FilaDato('Destino', traspaso.destino),
                        if (traspaso.solicitadoPor != null)
                          FilaDato('Solicitado por', traspaso.solicitadoPor!),
                        if (traspaso.recibidoPor != null)
                          FilaDato('Recibido por', traspaso.recibidoPor!),
                        FilaDato(
                          'Solicitud',
                          fechaLegible(DateTime.parse(traspaso.fechaSolicitud)),
                        ),
                        if (traspaso.fechaDespacho != null)
                          FilaDato('Despacho', fechaLegible(DateTime.parse(traspaso.fechaDespacho!))),
                        if (traspaso.fechaRecepcion != null)
                          FilaDato('Recepcion', fechaLegible(DateTime.parse(traspaso.fechaRecepcion!))),
                        if (traspaso.observacion != null)
                          FilaDato('Observacion', traspaso.observacion!),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const EtiquetaDato('Detalle'),
                  const SizedBox(height: 8),
                  ...traspaso.detalle.map((linea) {
                    final recibida = _recibidas[linea.id] ?? linea.cantidadSolicitada;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TarjetaPanel(
                        padding: const EdgeInsets.all(12),
                        hijo: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(linea.producto, style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(
                              '${linea.sku} · ${linea.talla} · ${linea.color}',
                              style: const TextStyle(fontSize: 12, color: Paleta.inkSuave),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Solicitado ${linea.cantidadSolicitada}'
                              '${linea.cantidadRecibida != null ? " · recibido ${linea.cantidadRecibida}" : ""}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                            if (puedeRecibir) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: recibida > 0
                                        ? () => setState(() => _recibidas[linea.id] = recibida - 1)
                                        : null,
                                    icon: const Icon(Icons.remove_circle_outline),
                                  ),
                                  Text('$recibida', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  IconButton(
                                    onPressed: recibida < linea.cantidadSolicitada
                                        ? () => setState(() => _recibidas[linea.id] = recibida + 1)
                                        : null,
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                  const Spacer(),
                                  Text(
                                    'solicitado ${linea.cantidadSolicitada}',
                                    style: const TextStyle(fontSize: 11.5, color: Paleta.inkSuave),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                  if (puedeRecibir) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _observacion,
                      maxLength: 250,
                      decoration: const InputDecoration(labelText: 'Observacion (opcional)'),
                    ),
                    if (_faltante > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Faltan $_faltante unidad(es): ya salieron del origen y se resuelve con un '
                          'ajuste de inventario despues.',
                          style: const TextStyle(fontSize: 12, color: Paleta.gold),
                        ),
                      ),
                  ],
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
                              Text(movimiento.producto, style: const TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 3),
                              Text(
                                '${movimiento.sucursal} · ${movimiento.tipo == "TRASPASO_SAL" ? "Salida" : "Entrada"} '
                                '· ${movimiento.cantidad} · saldo ${movimiento.saldoAnterior} -> ${movimiento.saldoNuevo}',
                                style: fuenteMono(fontSize: 11.5, fontWeight: FontWeight.w500, color: Paleta.inkSuave),
                              ),
                              Text(
                                fechaLegible(DateTime.parse(movimiento.fecha)),
                                style: const TextStyle(fontSize: 11, color: Paleta.inkSuave),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (puedeDespachar || puedeRecibir || puedeAnularlo) ...[
                    const SizedBox(height: 22),
                    if (puedeDespachar)
                      ElevatedButton.icon(
                        onPressed: _trabajando ? null : _despachar,
                        icon: const Icon(Icons.local_shipping_outlined),
                        label: const Text('DESPACHAR'),
                      ),
                    if (puedeRecibir)
                      ElevatedButton.icon(
                        onPressed: _trabajando ? null : _recibir,
                        icon: const Icon(Icons.move_to_inbox_outlined),
                        label: const Text('RECIBIR'),
                      ),
                    if (puedeAnularlo) ...[
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: _trabajando ? null : _anular,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Paleta.rojo,
                          side: const BorderSide(color: Paleta.rojo),
                        ),
                        child: const Text('ANULAR'),
                      ),
                    ],
                  ],
                ],
              ),
      ),
    );
  }
}
