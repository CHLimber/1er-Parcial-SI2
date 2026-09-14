import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../compartido/widgets.dart';
import '../core/config.dart';
import '../core/errores.dart';
import '../core/reservas/reserva_carrito_service.dart';
import '../core/reservas/reservas_models.dart';
import '../core/reservas/reservas_service.dart';
import '../core/sucursales/sucursales_models.dart';
import '../core/sucursales/sucursales_service.dart';
import '../core/tema.dart';
import 'tienda_pagina.dart';

/// CU04: Reservar Prendas. La bolsa vive en el dispositivo; al confirmar, el backend
/// compromete el stock (`cantidad_reservada` sube, `cantidad_fisica` no se toca).
class ReservarPagina extends StatefulWidget {
  const ReservarPagina({super.key});

  @override
  State<ReservarPagina> createState() => _ReservarPaginaState();
}

class _ReservarPaginaState extends State<ReservarPagina> {
  final _observaciones = TextEditingController();

  List<SucursalOut> _sucursales = [];
  SucursalOut? _sucursal;
  DateTime _fecha = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _hora = const TimeOfDay(hour: 16, minute: 0);

  bool _cargando = true;
  bool _confirmando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarSucursales();
  }

  @override
  void dispose() {
    _observaciones.dispose();
    super.dispose();
  }

  Future<void> _cargarSucursales() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final sucursales = await sucursalesService.listar();
      if (!mounted) return;
      setState(() {
        _sucursales = sucursales;
        _sucursal = sucursales.isEmpty ? null : sucursales.first;
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

  Future<void> _elegirFecha() async {
    final hoy = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(hoy.year, hoy.month, hoy.day),
      lastDate: hoy.add(const Duration(days: 60)),
      helpText: 'Dia de la visita',
    );
    if (elegida != null) setState(() => _fecha = elegida);
  }

  Future<void> _elegirHora() async {
    final elegida = await showTimePicker(context: context, initialTime: _hora);
    if (elegida != null) setState(() => _hora = elegida);
  }

  String get _horaTexto =>
      '${_hora.hour.toString().padLeft(2, '0')}:${_hora.minute.toString().padLeft(2, '0')}:00';

  Future<void> _confirmar() async {
    final bolsa = context.read<ReservaCarritoService>();
    final sucursal = _sucursal;
    if (sucursal == null || bolsa.estaVacio) return;

    setState(() => _confirmando = true);
    try {
      final reserva = await reservasService.crear(
        sucursalId: sucursal.id,
        fechaVisita: _fecha,
        horaVisita: _horaTexto,
        observaciones: _observaciones.text.trim(),
        items: bolsa.items,
      );
      bolsa.limpiar();
      if (!mounted) return;
      await _mostrarResultado(reserva);
      if (!mounted) return;
      context.go('/mis-reservas');
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    } finally {
      if (mounted) setState(() => _confirmando = false);
    }
  }

  /// El backend puede aceptar la reserva y rechazar algunos items (sin stock al momento
  /// de comprometer): hay que decirselo al cliente antes de mandarlo a la sucursal.
  Future<void> _mostrarResultado(ReservaOut reserva) => showDialog<void>(
        context: context,
        builder: (contexto) => AlertDialog(
          backgroundColor: Paleta.blanco,
          title: Text('Reserva ${reserva.codigo}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Te esperamos en ${reserva.sucursal} el ${reserva.fechaVisita} '
                  'a las ${reserva.horaVisita.substring(0, 5)}.'),
              const SizedBox(height: 10),
              Text(
                '${reserva.items.length} prenda(s) apartada(s).',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (reserva.itemsRechazados.isNotEmpty) ...[
                const SizedBox(height: 14),
                const EtiquetaDato('No se pudieron apartar'),
                const SizedBox(height: 6),
                ...reserva.itemsRechazados.map(
                  (item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      '${item.sku}: ${item.motivo}',
                      style: const TextStyle(fontSize: 13, color: Paleta.rojo),
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(contexto),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bolsa = context.watch<ReservaCarritoService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Reservar en tienda')),
      body: VistaAsincrona(
        cargando: _cargando,
        error: _error,
        alReintentar: _cargarSucursales,
        hijo: bolsa.estaVacio
            ? EstadoVacio(
                mensaje: 'Tu bolsa de reserva esta vacia.\nElige prendas del catalogo para '
                    'probartelas en la sucursal.',
                icono: Icons.checkroom_outlined,
                accion: ElevatedButton(
                  onPressed: () => context.go('/tienda'),
                  child: const Text('VER CATALOGO'),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  const EtiquetaDato('Prendas a probar'),
                  const SizedBox(height: 10),
                  ...bolsa.items.map((item) => _filaItem(bolsa, item)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Valor estimado', style: TextStyle(color: Paleta.inkSuave)),
                      Text(
                        formatearPrecio(bolsa.subtotal),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  const EtiquetaDato('Sucursal'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<SucursalOut>(
                    initialValue: _sucursal,
                    isExpanded: true,
                    items: _sucursales
                        .map(
                          (sucursal) => DropdownMenuItem(
                            value: sucursal,
                            child: Text(
                              '${sucursal.nombre} · ${sucursal.ciudad}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (valor) => setState(() => _sucursal = valor),
                  ),
                  if (_sucursal != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${_sucursal!.direccion} · Atiende de ${_sucursal!.horario} · '
                        '${_sucursal!.cantidadVestidores} vestidores',
                        style: const TextStyle(fontSize: 12.5, color: Paleta.inkSuave, height: 1.4),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _elegirFecha,
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Dia de la visita'),
                            child: Text(_fecha.toIso8601String().split('T').first),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: _elegirHora,
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Hora'),
                            child: Text(_horaTexto.substring(0, 5)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _observaciones,
                    maxLines: 3,
                    maxLength: 250,
                    decoration: const InputDecoration(
                      labelText: 'Observaciones (opcional)',
                      hintText: 'Algo que el encargado deba saber',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: (_confirmando || _sucursal == null) ? null : _confirmar,
                    child: _confirmando
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Paleta.blanco),
                          )
                        : const Text('CONFIRMAR RESERVA'),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'La reserva vence si no te presentas: el sistema libera las prendas '
                    'para que otro cliente pueda comprarlas.',
                    style: TextStyle(fontSize: 12.5, color: Paleta.inkSuave, height: 1.4),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _filaItem(ReservaCarritoService bolsa, ItemCarritoReserva item) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TarjetaPanel(
          padding: const EdgeInsets.all(10),
          hijo: Row(
            children: [
              SizedBox(
                width: 56,
                height: 72,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ImagenPrenda(url: item.imagenUrl),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.producto,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.talla} · ${item.color}',
                      style: const TextStyle(fontSize: 12.5, color: Paleta.inkSuave),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatearPrecio(item.precio),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: item.cantidad <= 1
                            ? null
                            : () => bolsa.actualizarCantidad(item.varianteId, item.cantidad - 1),
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                      ),
                      Text('${item.cantidad}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: item.cantidad >= 20
                            ? null
                            : () => bolsa.actualizarCantidad(item.varianteId, item.cantidad + 1),
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => bolsa.quitar(item.varianteId),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: Paleta.rojo,
                    ),
                    child: const Text('Quitar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}
