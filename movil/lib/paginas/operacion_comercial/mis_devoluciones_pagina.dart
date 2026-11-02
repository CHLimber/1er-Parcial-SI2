import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../compartido/widgets.dart';
import '../../core/config.dart';
import '../../core/errores.dart';
import '../../core/operacion_comercial/devoluciones/devoluciones_service.dart';
import '../../core/tema.dart';
import 'mis_reservas_pagina.dart' show fechaLegible;

/// Devoluciones e intercambios de la clienta (PENDIENTES 10, espejo de `mis-devoluciones` en la
/// web): sus solicitudes y su estado. Con [ventaId] abre primero la solicitud de esa compra.
class MisDevolucionesPagina extends StatefulWidget {
  const MisDevolucionesPagina({super.key, this.ventaId});

  final String? ventaId;

  @override
  State<MisDevolucionesPagina> createState() => _MisDevolucionesPaginaState();
}

class _MisDevolucionesPaginaState extends State<MisDevolucionesPagina> {
  List<DevolucionDetalleOut> _solicitudes = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
    final venta = widget.ventaId;
    if (venta != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pedir(venta));
    }
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final lista = await misDevolucionesService.listar();
      if (!mounted) return;
      setState(() {
        _solicitudes = lista;
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

  Future<void> _pedir(String ventaId) async {
    final enviada = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => SolicitarDevolucionPagina(ventaId: ventaId)),
    );
    if (enviada == true) await _cargar();
  }

  Future<void> _cancelar(DevolucionDetalleOut s) async {
    final ok = await confirmar(
      context,
      titulo: 'Cancelar solicitud',
      mensaje: 'Se cancela la ${s.numero}. Despues podes pedir otra si sigues en plazo.',
      textoConfirmar: 'Cancelar solicitud',
    );
    if (!ok) return;
    try {
      await misDevolucionesService.cancelar(s.id);
      if (!mounted) return;
      mostrarAviso(context, 'Cancelaste la solicitud ${s.numero}.');
      await _cargar();
    } catch (error) {
      if (mounted) mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  String _estadoTexto(DevolucionDetalleOut d) {
    if (d.estado == 'SOLICITADA' && d.origen == 'ONLINE') return 'Esperando que la sucursal la acepte';
    if (d.estado == 'CONFIRMADA') return 'Aceptada: te esperamos';
    return estadosDevolucion[d.estado] ?? d.estado;
  }

  String _plata(DevolucionDetalleOut d) {
    if (d.estado == 'APROBADA') {
      final partes = <String>[
        if (d.diferenciaCobrada > 0) 'Pagaste ${formatearPrecio(d.diferenciaCobrada)} de diferencia.',
        if (d.montoReintegrado > 0) 'Te devolvimos ${formatearPrecio(d.montoReintegrado)}.',
        'Te mandamos el comprobante por correo.',
      ];
      return partes.join(' ');
    }
    if (!d.enTramite) return '';
    if (d.esIntercambio) {
      if (d.diferencia > 0.004) return 'Pagas ${formatearPrecio(d.diferencia)} de diferencia en caja.';
      if (d.diferencia < -0.004) return 'Te devolvemos ${formatearPrecio(-d.diferencia)}.';
      return 'Sin diferencia de precio.';
    }
    return 'Te devolvemos ${formatearPrecio(d.montoDevuelto)} al concretarla.';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Devoluciones y cambios')),
        body: VistaAsincrona(
          cargando: _cargando,
          error: _error,
          alReintentar: _cargar,
          hijo: RefreshIndicator(
            color: Paleta.flame,
            onRefresh: _cargar,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                const Text(
                  'Tenes 3 dias desde la compra, una sola solicitud por compra y hasta 3 prendas. '
                  'En la sucursal revisamos la prenda (con etiqueta, sin uso y con el comprobante) y te '
                  'devolvemos la plata o pagas la diferencia del cambio.',
                  style: TextStyle(fontSize: 13, color: Paleta.inkSuave, height: 1.4),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => context.push('/mis-compras'),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('ELEGIR UNA COMPRA'),
                ),
                const SizedBox(height: 16),
                if (_solicitudes.isEmpty)
                  const EstadoVacio(
                    mensaje: 'Todavia no pediste ninguna devolucion ni cambio.',
                    icono: Icons.assignment_return_outlined,
                  ),
                ..._solicitudes.map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TarjetaPanel(
                      hijo: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${s.numero} · ${s.esIntercambio ? 'Cambio' : 'Devolucion'}',
                                  style: fuenteMono(fontSize: 14, fontWeight: FontWeight.w700, color: Paleta.ink),
                                ),
                              ),
                              BadgeEstado(estadosDevolucion[s.estado] ?? s.estado,
                                  color: BadgeEstado.colorDeEstado(s.estado)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(_estadoTexto(s), style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('Compra ${s.ventaNumero} · ${s.sucursal} · ${fechaLegible(DateTime.parse(s.fecha))}',
                              style: const TextStyle(fontSize: 12.5, color: Paleta.inkSuave)),
                          const SizedBox(height: 6),
                          ...s.detalle.map((l) => Text(
                                '${l.cantidad} x ${l.producto} (${l.talla} · ${l.color})'
                                '${l.tallaSolicitada != null ? '  →  ${l.tallaSolicitada} · ${l.colorSolicitado}' : ''}',
                                style: const TextStyle(fontSize: 13),
                              )),
                          if (s.fechaVisita != null && s.enTramite)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('Visita: ${s.visita}', style: const TextStyle(fontSize: 13)),
                            ),
                          if (_plata(s).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(_plata(s), style: const TextStyle(fontSize: 13, color: Paleta.ink)),
                            ),
                          if (s.motivoRechazo != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('Motivo: ${s.motivoRechazo}',
                                  style: const TextStyle(fontSize: 13, color: Paleta.rojo)),
                            ),
                          if (s.enTramite && s.origen == 'ONLINE')
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: () => _cancelar(s),
                                child: const Text('Cancelar solicitud'),
                              ),
                            ),
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

/// Formulario de la solicitud (como una reserva): devolver o cambiar, prendas (hasta el tope),
/// motivo, talla/color nueva con su precio y dia/hora de la visita a la sucursal.
class SolicitarDevolucionPagina extends StatefulWidget {
  const SolicitarDevolucionPagina({super.key, required this.ventaId});

  final String ventaId;

  @override
  State<SolicitarDevolucionPagina> createState() => _SolicitarDevolucionPaginaState();
}

class _SolicitarDevolucionPaginaState extends State<SolicitarDevolucionPagina> {
  final _motivo = TextEditingController();
  OpcionesDevolucionOut? _op;
  String? _error;
  bool _enviando = false;
  String _tipo = 'DEVOLUCION';
  String _motivoTipo = 'NO_GUSTO';
  final Map<String, int> _cantidades = {};
  final Map<String, String> _solicitadas = {};
  DateTime _fecha = DateTime.now();
  TimeOfDay _hora = const TimeOfDay(hour: 10, minute: 0);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final op = await misDevolucionesService.opciones(widget.ventaId);
      if (!mounted) return;
      setState(() {
        _op = op;
        final apertura = _horaDe(op.horaApertura);
        if (apertura != null) _hora = apertura;
      });
    } catch (error) {
      if (mounted) setState(() => _error = interpretarError(error));
    }
  }

  TimeOfDay? _horaDe(String? texto) {
    if (texto == null || texto.length < 5) return null;
    return TimeOfDay(hour: int.parse(texto.substring(0, 2)), minute: int.parse(texto.substring(3, 5)));
  }

  int get _unidades => _cantidades.values.fold(0, (s, c) => s + c);

  double get _valorDevuelto {
    final op = _op;
    if (op == null) return 0;
    return op.lineas.fold(0.0, (s, l) => s + (_cantidades[l.ventaDetalleId] ?? 0) * l.reembolsoUnitario);
  }

  double get _valorNuevo {
    final op = _op;
    if (op == null || _tipo != 'INTERCAMBIO') return 0;
    var subtotal = 0.0;
    for (final linea in op.lineas) {
      final opcion = linea.variantesCambio.where((v) => v.varianteId == _solicitadas[linea.ventaDetalleId]);
      if (opcion.isNotEmpty) subtotal += (_cantidades[linea.ventaDetalleId] ?? 0) * opcion.first.precio;
    }
    return (subtotal * (1 + op.ivaTasa) * 100).roundToDouble() / 100;
  }

  void _elegirTipo(String tipo) => setState(() {
        _tipo = tipo;
        _motivoTipo = tipo == 'INTERCAMBIO' ? 'TALLA' : 'NO_GUSTO';
        _solicitadas.clear();
      });

  List<VarianteCambioOut> _opcionesPara(LineaClienteOut linea) => _motivoTipo == 'TALLA'
      ? linea.variantesCambio.where((v) => v.talla != linea.talla && v.color == linea.color).toList()
      : linea.variantesCambio.where((v) => v.color != linea.color && v.talla == linea.talla).toList();

  void _cambiarCantidad(LineaClienteOut linea, int delta) {
    final op = _op!;
    final actual = _cantidades[linea.ventaDetalleId] ?? 0;
    final resto = op.maxUnidades - _unidades + actual;
    final tope = linea.devolvible < resto ? linea.devolvible : resto;
    setState(() => _cantidades[linea.ventaDetalleId] = (actual + delta).clamp(0, tope));
  }

  Future<void> _elegirFecha() async {
    final op = _op!;
    final hoy = DateTime.now();
    final ultimo = op.plazoVenceEn.isBefore(hoy) ? hoy : op.plazoVenceEn;
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha.isAfter(ultimo) ? ultimo : _fecha,
      firstDate: DateTime(hoy.year, hoy.month, hoy.day),
      lastDate: ultimo,
    );
    if (elegida != null) setState(() => _fecha = elegida);
  }

  Future<void> _elegirHora() async {
    final elegida = await showTimePicker(context: context, initialTime: _hora);
    if (elegida != null) setState(() => _hora = elegida);
  }

  String _dos(int n) => n.toString().padLeft(2, '0');

  Future<void> _enviar() async {
    final op = _op!;
    final lineas = _cantidades.entries.where((e) => e.value > 0).toList();
    if (lineas.isEmpty) {
      mostrarAviso(context, 'Elegi al menos una prenda.', esError: true);
      return;
    }
    if (_tipo == 'INTERCAMBIO' && lineas.any((l) => _solicitadas[l.key] == null)) {
      mostrarAviso(context, 'Elegi que talla o color te llevas por cada prenda.', esError: true);
      return;
    }
    if (_motivo.text.trim().length < 3) {
      mostrarAviso(context, 'Contanos brevemente el motivo.', esError: true);
      return;
    }
    setState(() => _enviando = true);
    try {
      final solicitud = await misDevolucionesService.solicitar(
        ventaId: op.ventaId,
        motivoTipo: _motivoTipo,
        motivo: _motivo.text.trim(),
        fechaVisita: '${_fecha.year}-${_dos(_fecha.month)}-${_dos(_fecha.day)}',
        horaVisita: '${_dos(_hora.hour)}:${_dos(_hora.minute)}',
        lineas: lineas,
        solicitadas: _tipo == 'INTERCAMBIO' ? _solicitadas : const {},
      );
      if (!mounted) return;
      mostrarAviso(context,
          'Enviamos tu solicitud ${solicitud.numero}. Te avisamos cuando la sucursal la acepte.');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final op = _op;
    return Scaffold(
      appBar: AppBar(title: Text(op == null ? 'Devolver o cambiar' : 'Compra ${op.numero}')),
      body: op == null
          ? (_error != null
              ? Padding(padding: const EdgeInsets.all(16), child: MensajeError(_error!))
              : const Center(child: CircularProgressIndicator()))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text('${op.sucursal}${op.sucursalDireccion != null ? ' · ${op.sucursalDireccion}' : ''}',
                    style: const TextStyle(color: Paleta.inkSuave)),
                const SizedBox(height: 12),
                if (!op.puedeSolicitar)
                  MensajeError(op.motivoNo ?? 'Esta compra no admite devolucion.')
                else ...[
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'DEVOLUCION', label: Text('Devolver'), icon: Icon(Icons.undo)),
                      ButtonSegment(value: 'INTERCAMBIO', label: Text('Cambiar'), icon: Icon(Icons.swap_horiz)),
                    ],
                    selected: {_tipo},
                    onSelectionChanged: (v) => _elegirTipo(v.first),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(_tipo),
                    initialValue: _motivoTipo,
                    decoration: const InputDecoration(labelText: 'Motivo'),
                    items: motivosDe(_tipo)
                        .entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _motivoTipo = v;
                          _solicitadas.clear();
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  ...op.lineas.map((linea) {
                    final cantidad = _cantidades[linea.ventaDetalleId] ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TarjetaPanel(
                        padding: const EdgeInsets.all(12),
                        hijo: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(linea.producto, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text('${linea.talla} · ${linea.color} · vale ${formatearPrecio(linea.reembolsoUnitario)}',
                                style: const TextStyle(fontSize: 12.5, color: Paleta.inkSuave)),
                            if (linea.devolvible <= 0)
                              const Text('Ya devuelta', style: TextStyle(fontSize: 12, color: Paleta.inkSuave))
                            else
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: cantidad > 0 ? () => _cambiarCantidad(linea, -1) : null,
                                    icon: const Icon(Icons.remove_circle_outline),
                                  ),
                                  Text('$cantidad', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  IconButton(
                                    onPressed: () => _cambiarCantidad(linea, 1),
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                ],
                              ),
                            if (_tipo == 'INTERCAMBIO' && cantidad > 0)
                              DropdownButtonFormField<String>(
                                key: ValueKey('${linea.ventaDetalleId}-$_motivoTipo'),
                                initialValue: _solicitadas[linea.ventaDetalleId],
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'Te llevas'),
                                items: _opcionesPara(linea)
                                    .map((v) => DropdownMenuItem(
                                          value: v.varianteId,
                                          enabled: v.disponible >= cantidad,
                                          child: Text(
                                              'Talla ${v.talla} · ${v.color} · ${formatearPrecio(v.precio)}'
                                              '${v.disponible < 1 ? ' (sin stock)' : ''}'),
                                        ))
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) setState(() => _solicitadas[linea.ventaDetalleId] = v);
                                },
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                  Text('$_unidades de ${op.maxUnidades} prendas como maximo.',
                      style: const TextStyle(fontSize: 12.5, color: Paleta.inkSuave)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _motivo,
                    maxLength: 250,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Contanos que paso'),
                  ),
                  const EtiquetaDato('Cuando pasas por la sucursal'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _elegirFecha,
                          icon: const Icon(Icons.event),
                          label: Text('${_dos(_fecha.day)}/${_dos(_fecha.month)}'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _elegirHora,
                          icon: const Icon(Icons.schedule),
                          label: Text('${_dos(_hora.hour)}:${_dos(_hora.minute)}'),
                        ),
                      ),
                    ],
                  ),
                  if (op.horaApertura != null && op.horaCierre != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'La sucursal atiende de ${op.horaApertura!.substring(0, 5)} a ${op.horaCierre!.substring(0, 5)}.',
                        style: const TextStyle(fontSize: 12, color: Paleta.inkSuave),
                      ),
                    ),
                  if (_unidades > 0) ...[
                    const SizedBox(height: 14),
                    TarjetaPanel(
                      padding: const EdgeInsets.all(12),
                      hijo: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_tipo == 'DEVOLUCION')
                            Text(
                              'Te devolvemos ${formatearPrecio(_valorDevuelto)} '
                              '${(comoSeReintegra[op.reintegroMetodo] ?? 'en la sucursal').replaceAll(', desde la caja', ' en la sucursal')}.',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            )
                          else ...[
                            Text('Lo que devolves vale ${formatearPrecio(_valorDevuelto)} y lo nuevo ${formatearPrecio(_valorNuevo)}.'),
                            if (_valorNuevo > 0)
                              Text(
                                _valorNuevo - _valorDevuelto > 0.004
                                    ? 'Pagas ${formatearPrecio(_valorNuevo - _valorDevuelto)} de diferencia en caja.'
                                    : _valorNuevo - _valorDevuelto < -0.004
                                        ? 'Te devolvemos ${formatearPrecio(_valorDevuelto - _valorNuevo)}.'
                                        : 'No hay diferencia de precio.',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                          ],
                          const SizedBox(height: 4),
                          const Text('Montos con IVA. Se confirman en la sucursal al revisar la prenda.',
                              style: TextStyle(fontSize: 12, color: Paleta.inkSuave)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _enviando || _unidades == 0 ? null : _enviar,
                    child: _enviando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Paleta.blanco),
                          )
                        : Text(_tipo == 'INTERCAMBIO' ? 'PEDIR EL CAMBIO' : 'PEDIR LA DEVOLUCION'),
                  ),
                ],
              ],
            ),
    );
  }
}
