import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../compartido/widgets.dart';
import '../core/auth/auth_service.dart';
import '../core/config.dart';
import '../core/devoluciones/devoluciones_service.dart';
import '../core/errores.dart';
import '../core/tema.dart';
import 'mis_reservas_pagina.dart' show fechaLegible;

/// Devoluciones de ventas (PENDIENTES 2.7/2.19.7, espejo de `panel-devoluciones` en la
/// web). Registrar es del personal, sobre una venta PAGADA o ENTREGADA de su sucursal:
/// nace SOLICITADA y no mueve stock. Resolver es aprobar (el trigger de la base reingresa
/// el stock y recalcula el reintegro) o rechazar (con motivo).
class PanelDevolucionesPagina extends StatefulWidget {
  const PanelDevolucionesPagina({super.key});

  @override
  State<PanelDevolucionesPagina> createState() => _PanelDevolucionesPaginaState();
}

class _PanelDevolucionesPaginaState extends State<PanelDevolucionesPagina> {
  final _busqueda = TextEditingController();

  List<DevolucionOut> _devoluciones = [];
  String? _estado;
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
      final devoluciones = await devolucionesService.listar(
        estado: _estado,
        venta: _busqueda.text.trim().isEmpty ? null : _busqueda.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _devoluciones = devoluciones;
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

  Future<void> _abrirDetalle(String devolucionId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (contexto) => DetalleDevolucionPagina(devolucionId: devolucionId),
      ),
    );
    await _cargar();
  }

  Future<void> _nuevaDevolucion() async {
    final registrada = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (contexto) => const NuevaDevolucionPagina()),
    );
    if (registrada == true) await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final puedeRegistrar = context.watch<AuthService>().tienePermiso(['devoluciones.crear']);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devoluciones'),
        actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: puedeRegistrar
          ? FloatingActionButton.extended(
              onPressed: _nuevaDevolucion,
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
            child: TextField(
              controller: _busqueda,
              onChanged: _buscarConRetraso,
              decoration: const InputDecoration(
                labelText: 'Buscar por numero de venta',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: Row(
              children: [
                _chip('Todas', null),
                _chip('Pendientes', 'SOLICITADA'),
                _chip('Aprobadas', 'APROBADA'),
                _chip('Rechazadas', 'RECHAZADA'),
              ],
            ),
          ),
          Expanded(
            child: VistaAsincrona(
              cargando: _cargando,
              error: _error,
              alReintentar: _cargar,
              hijo: _devoluciones.isEmpty
                  ? const EstadoVacio(mensaje: 'No hay devoluciones con ese filtro.')
                  : RefreshIndicator(
                      color: Paleta.flame,
                      onRefresh: _cargar,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 90),
                        itemCount: _devoluciones.length,
                        separatorBuilder: (contexto, indice) => const SizedBox(height: 10),
                        itemBuilder: (contexto, indice) {
                          final devolucion = _devoluciones[indice];
                          return TarjetaPanel(
                            alTocar: () => _abrirDetalle(devolucion.id),
                            hijo: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        devolucion.ventaNumero,
                                        style: fuenteMono(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: Paleta.ink,
                                        ),
                                      ),
                                    ),
                                    BadgeEstado(devolucion.estado),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                FilaDato('Sucursal', devolucion.sucursal),
                                if (devolucion.cliente != null)
                                  FilaDato('Clienta', devolucion.cliente!),
                                FilaDato('Motivo', devolucion.motivo),
                                FilaDato(
                                  'Contenido',
                                  '${devolucion.lineas} linea(s) · ${devolucion.unidades} unidad(es)',
                                ),
                                FilaDato('Reintegro', formatearPrecio(devolucion.montoDevuelto)),
                                FilaDato('Fecha', fechaLegible(DateTime.parse(devolucion.fecha))),
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

/// Registro de una devolucion: busca la venta por numero, se elige cuanto se devuelve
/// de cada linea (tope: lo vendido menos lo ya devuelto o en tramite) y el motivo.
class NuevaDevolucionPagina extends StatefulWidget {
  const NuevaDevolucionPagina({super.key});

  @override
  State<NuevaDevolucionPagina> createState() => _NuevaDevolucionPaginaState();
}

class _NuevaDevolucionPaginaState extends State<NuevaDevolucionPagina> {
  final _numero = TextEditingController();
  final _motivo = TextEditingController();

  VentaDevolvibleOut? _venta;
  final Map<String, int> _cantidades = {};
  bool _buscando = false;
  bool _registrando = false;
  String? _error;

  @override
  void dispose() {
    _numero.dispose();
    _motivo.dispose();
    super.dispose();
  }

  double get _estimado => _venta == null
      ? 0
      : _venta!.lineas.fold<double>(
          0,
          (suma, linea) =>
              suma + (_cantidades[linea.ventaDetalleId] ?? 0) * linea.reembolsoUnitario,
        );

  int get _unidadesElegidas => _cantidades.values.fold(0, (suma, c) => suma + c);

  Future<void> _buscar() async {
    final numero = _numero.text.trim();
    if (numero.isEmpty) return;
    setState(() {
      _buscando = true;
      _error = null;
      _venta = null;
      _cantidades.clear();
    });
    try {
      final venta = await devolucionesService.buscarVenta(numero);
      if (!mounted) return;
      setState(() {
        _venta = venta;
        _buscando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = interpretarError(error);
        _buscando = false;
      });
    }
  }

  void _fijarCantidad(String ventaDetalleId, int valor, int maximo) {
    setState(() {
      _cantidades[ventaDetalleId] = valor.clamp(0, maximo);
    });
  }

  Future<void> _registrar() async {
    final venta = _venta;
    if (venta == null) return;
    final lineas = _cantidades.entries.where((e) => e.value > 0).toList();
    if (lineas.isEmpty) {
      mostrarAviso(context, 'Indica al menos una prenda a devolver.', esError: true);
      return;
    }
    if (_motivo.text.trim().length < 3) {
      mostrarAviso(context, 'Escribe el motivo de la devolucion.', esError: true);
      return;
    }
    setState(() => _registrando = true);
    try {
      await devolucionesService.registrar(
        ventaId: venta.ventaId,
        motivo: _motivo.text.trim(),
        lineas: lineas,
      );
      if (!mounted) return;
      mostrarAviso(
        context,
        'Devolucion registrada. Queda pendiente de aprobacion: todavia no volvio al stock.',
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    } finally {
      if (mounted) setState(() => _registrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final venta = _venta;
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva devolucion')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _numero,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _buscar(),
                  decoration: const InputDecoration(
                    labelText: 'Numero de venta',
                    hintText: 'V-...',
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
                    : const Text('BUSCAR'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            MensajeError(_error!),
          ],
          if (venta != null) ...[
            const SizedBox(height: 18),
            TarjetaPanel(
              hijo: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          venta.numero,
                          style: fuenteMono(fontSize: 15, fontWeight: FontWeight.w700, color: Paleta.ink),
                        ),
                      ),
                      BadgeEstado(venta.estado),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilaDato('Sucursal', venta.sucursal),
                  if (venta.cliente != null) FilaDato('Clienta', venta.cliente!),
                  FilaDato('Total', formatearPrecio(venta.total)),
                  if (venta.totalDevuelto > 0)
                    FilaDato('Ya devuelto', formatearPrecio(venta.totalDevuelto)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const EtiquetaDato('Prendas'),
            const SizedBox(height: 8),
            ...venta.lineas.map((linea) {
              final elegida = _cantidades[linea.ventaDetalleId] ?? 0;
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
                        'Vendidas ${linea.cantidadVendida} · devueltas ${linea.devuelta} · '
                        'en tramite ${linea.enTramite} · devolvible ${linea.devolvible}',
                        style: const TextStyle(fontSize: 11.5, color: Paleta.inkSuave),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Reintegro por unidad: ${formatearPrecio(linea.reembolsoUnitario)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      if (linea.devolvible <= 0)
                        const Text(
                          'No queda nada por devolver de esta linea.',
                          style: TextStyle(fontSize: 12, color: Paleta.inkSuave),
                        )
                      else
                        Row(
                          children: [
                            IconButton(
                              onPressed: elegida > 0
                                  ? () => _fijarCantidad(
                                        linea.ventaDetalleId,
                                        elegida - 1,
                                        linea.devolvible,
                                      )
                                  : null,
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text('$elegida', style: const TextStyle(fontWeight: FontWeight.w700)),
                            IconButton(
                              onPressed: elegida < linea.devolvible
                                  ? () => _fijarCantidad(
                                        linea.ventaDetalleId,
                                        elegida + 1,
                                        linea.devolvible,
                                      )
                                  : null,
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                            const Spacer(),
                            Text(
                              'max ${linea.devolvible}',
                              style: const TextStyle(fontSize: 11.5, color: Paleta.inkSuave),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            TextField(
              controller: _motivo,
              maxLength: 250,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Motivo de la devolucion'),
            ),
            const SizedBox(height: 6),
            Text(
              '$_unidadesElegidas unidad(es) elegida(s) · estimado ${formatearPrecio(_estimado)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: (_registrando || _unidadesElegidas == 0) ? null : _registrar,
              child: _registrando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Paleta.blanco),
                    )
                  : const Text('REGISTRAR DEVOLUCION'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Detalle de una devolucion y su resolucion (aprobar/rechazar), solo si esta SOLICITADA.
class DetalleDevolucionPagina extends StatefulWidget {
  const DetalleDevolucionPagina({super.key, required this.devolucionId});

  final String devolucionId;

  @override
  State<DetalleDevolucionPagina> createState() => _DetalleDevolucionPaginaState();
}

class _DetalleDevolucionPaginaState extends State<DetalleDevolucionPagina> {
  DevolucionDetalleOut? _devolucion;
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
      final devolucion = await devolucionesService.obtener(widget.devolucionId);
      if (!mounted) return;
      setState(() {
        _devolucion = devolucion;
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

  Future<void> _aprobar() async {
    final confirmado = await confirmar(
      context,
      titulo: 'Aprobar devolucion',
      mensaje: 'El stock de las prendas vuelve a la sucursal y se calcula lo que hay que '
          'reintegrar a la clienta.',
      textoConfirmar: 'Aprobar',
    );
    if (!confirmado) return;
    setState(() => _trabajando = true);
    try {
      final detalle = await devolucionesService.aprobar(widget.devolucionId);
      if (!mounted) return;
      setState(() {
        _devolucion = detalle;
        _trabajando = false;
      });
      mostrarAviso(
        context,
        'Devolucion aprobada: ${detalle.unidades} unidad(es) volvieron al stock de '
        '${detalle.sucursal}. Reintegrar ${formatearPrecio(detalle.montoDevuelto)}.'
        '${detalle.pagoReembolsado ? " La venta quedo devuelta completa y el pago paso a reembolsado." : ""}',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _trabajando = false);
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  Future<void> _rechazar() async {
    final motivo = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        backgroundColor: Paleta.blanco,
        title: const Text('Rechazar devolucion'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se le avisa a la clienta con este motivo. El stock no se toca.',
              style: TextStyle(fontSize: 13, color: Paleta.inkSuave, height: 1.4),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: motivo,
              maxLength: 250,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Motivo', counterText: ''),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(contexto, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(contexto, true),
            style: ElevatedButton.styleFrom(backgroundColor: Paleta.rojo),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );

    final texto = motivo.text.trim();
    motivo.dispose();
    if (confirmado != true) return;
    if (!mounted) return;
    if (texto.length < 3) {
      mostrarAviso(context, 'Indica el motivo del rechazo.', esError: true);
      return;
    }

    setState(() => _trabajando = true);
    try {
      final detalle = await devolucionesService.rechazar(widget.devolucionId, texto);
      if (!mounted) return;
      setState(() {
        _devolucion = detalle;
        _trabajando = false;
      });
      mostrarAviso(context, 'Devolucion rechazada. Se le aviso a la clienta.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _trabajando = false);
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devolucion = _devolucion;
    final puedeResolver = context.watch<AuthService>().tienePermiso(['devoluciones.actualizar']);

    return Scaffold(
      appBar: AppBar(title: Text(devolucion?.ventaNumero ?? 'Devolucion')),
      body: VistaAsincrona(
        cargando: _cargando,
        error: _error,
        alReintentar: _cargar,
        hijo: devolucion == null
            ? const EstadoVacio(mensaje: 'No se encontro la devolucion.')
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
                                devolucion.ventaNumero,
                                style: fuenteMono(fontSize: 15, fontWeight: FontWeight.w700, color: Paleta.ink),
                              ),
                            ),
                            BadgeEstado(devolucion.estado),
                          ],
                        ),
                        const SizedBox(height: 8),
                        FilaDato('Sucursal', devolucion.sucursal),
                        if (devolucion.cliente != null) FilaDato('Clienta', devolucion.cliente!),
                        FilaDato('Motivo', devolucion.motivo),
                        FilaDato('Venta total', formatearPrecio(devolucion.ventaTotal)),
                        FilaDato('Reintegro', formatearPrecio(devolucion.montoDevuelto)),
                        FilaDato('Fecha', fechaLegible(DateTime.parse(devolucion.fecha))),
                        if (devolucion.registradaPor != null)
                          FilaDato('Registrada por', devolucion.registradaPor!),
                        if (devolucion.resueltaPor != null)
                          FilaDato('Resuelta por', devolucion.resueltaPor!),
                        if (devolucion.motivoRechazo != null)
                          FilaDato('Motivo rechazo', devolucion.motivoRechazo!),
                        if (devolucion.pagoReembolsado)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'La venta quedo devuelta completa: el pago paso a reembolsado.',
                              style: TextStyle(fontSize: 12, color: Paleta.verde),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const EtiquetaDato('Detalle'),
                  const SizedBox(height: 8),
                  ...devolucion.detalle.map(
                    (linea) => Padding(
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
                              '${linea.cantidad} de ${linea.cantidadVendida} vendida(s) x '
                              '${formatearPrecio(linea.precioUnitario)}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (devolucion.solicitada && puedeResolver) ...[
                    const SizedBox(height: 22),
                    ElevatedButton.icon(
                      onPressed: _trabajando ? null : _aprobar,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('APROBAR'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _trabajando ? null : _rechazar,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Paleta.rojo,
                        side: const BorderSide(color: Paleta.rojo),
                      ),
                      child: const Text('RECHAZAR'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
