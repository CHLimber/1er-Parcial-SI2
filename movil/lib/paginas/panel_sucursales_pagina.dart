import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../compartido/widgets.dart';
import '../core/auth/auth_service.dart';
import '../core/errores.dart';
import '../core/sucursales/sucursales_models.dart';
import '../core/sucursales/sucursales_service.dart';
import '../core/tema.dart';

/// CU12: Gestionar Sucursales (y las cajas de cada una, que CU07 necesita).
class PanelSucursalesPagina extends StatefulWidget {
  const PanelSucursalesPagina({super.key});

  @override
  State<PanelSucursalesPagina> createState() => _PanelSucursalesPaginaState();
}

class _PanelSucursalesPaginaState extends State<PanelSucursalesPagina> {
  List<SucursalAdminOut> _sucursales = [];
  List<String> _ciudades = [];
  bool? _activa;
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
      final sucursales = await sucursalesAdminService.listar(activa: _activa);
      final ciudades =
          _ciudades.isEmpty ? await sucursalesAdminService.listarCiudades() : _ciudades;
      if (!mounted) return;
      setState(() {
        _sucursales = sucursales;
        _ciudades = ciudades;
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

  Future<void> _abrirFormulario({SucursalAdminOut? sucursal}) async {
    final codigo = TextEditingController(text: sucursal?.codigo ?? '');
    final nombre = TextEditingController(text: sucursal?.nombre ?? '');
    final direccion = TextEditingController(text: sucursal?.direccion ?? '');
    final telefono = TextEditingController(text: sucursal?.telefono ?? '');
    final vestidores =
        TextEditingController(text: '${sucursal?.cantidadVestidores ?? 0}');
    final formulario = GlobalKey<FormState>();

    String ciudad = sucursal?.ciudad ?? (_ciudades.isEmpty ? '' : _ciudades.first);
    TimeOfDay? apertura = _aHora(sucursal?.horaApertura);
    TimeOfDay? cierre = _aHora(sucursal?.horaCierre);

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
            child: Form(
              key: formulario,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Titular(sucursal == null ? 'Nueva sucursal' : 'Editar sucursal', tamano: 24),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: codigo,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Codigo'),
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
                  DropdownButtonFormField<String>(
                    initialValue: ciudad.isEmpty ? null : ciudad,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Ciudad'),
                    items: _ciudades
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (valor) => actualizar(() => ciudad = valor ?? ''),
                    validator: (v) => (v == null || v.isEmpty) ? 'Elige la ciudad' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: direccion,
                    decoration: const InputDecoration(labelText: 'Direccion'),
                    validator: (v) =>
                        (v?.trim().length ?? 0) < 3 ? 'Escribe la direccion' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: telefono,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Telefono (opcional)'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final elegida = await showTimePicker(
                              context: contexto,
                              initialTime: apertura ?? const TimeOfDay(hour: 9, minute: 0),
                            );
                            if (elegida != null) actualizar(() => apertura = elegida);
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Apertura'),
                            child: Text(_textoHora(apertura) ?? 'Sin definir'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final elegida = await showTimePicker(
                              context: contexto,
                              initialTime: cierre ?? const TimeOfDay(hour: 21, minute: 0),
                            );
                            if (elegida != null) actualizar(() => cierre = elegida);
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Cierre'),
                            child: Text(_textoHora(cierre) ?? 'Sin definir'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: vestidores,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Cantidad de vestidores'),
                    validator: (v) {
                      final numero = int.tryParse(v ?? '');
                      if (numero == null || numero < 0 || numero > 50) {
                        return 'Un numero entre 0 y 50';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 22),
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
        ),
      ),
    );

    final datos = SucursalIn(
      codigo: codigo.text.trim(),
      nombre: nombre.text.trim(),
      ciudad: ciudad,
      direccion: direccion.text.trim(),
      telefono: telefono.text.trim(),
      horaApertura: _textoHoraCompleta(apertura),
      horaCierre: _textoHoraCompleta(cierre),
      cantidadVestidores: int.tryParse(vestidores.text) ?? 0,
    );
    for (final control in [codigo, nombre, direccion, telefono, vestidores]) {
      control.dispose();
    }
    if (guardado != true) return;

    try {
      if (sucursal == null) {
        await sucursalesAdminService.crear(datos);
      } else {
        await sucursalesAdminService.actualizar(sucursal.id, datos);
      }
      if (!mounted) return;
      mostrarAviso(context, 'Sucursal guardada');
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  Future<void> _cambiarEstado(SucursalAdminOut sucursal) async {
    final activar = !sucursal.activa;
    if (!activar) {
      final confirmado = await confirmar(
        context,
        titulo: 'Cerrar sucursal',
        mensaje: '${sucursal.nombre} tiene ${sucursal.empleados} empleado(s) y '
            '${sucursal.cajas} caja(s). Dejara de aparecer para reservas y compras.',
        textoConfirmar: 'Cerrar',
        destructivo: true,
      );
      if (!confirmado) return;
    }
    try {
      await sucursalesAdminService.cambiarEstado(sucursal.id, activar);
      if (!mounted) return;
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  Future<void> _abrirCajas(SucursalAdminOut sucursal, bool puedeGestionar) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Paleta.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (contexto) => _HojaCajas(sucursal: sucursal, puedeGestionar: puedeGestionar),
    );
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final puedeGestionar = context.watch<AuthService>().tienePermiso(['sucursales.gestionar']);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sucursales'),
        actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: puedeGestionar
          ? FloatingActionButton.extended(
              onPressed: () => _abrirFormulario(),
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
                _chipEstado('Todas', null),
                _chipEstado('Abiertas', true),
                _chipEstado('Cerradas', false),
              ],
            ),
          ),
          Expanded(
            child: VistaAsincrona(
              cargando: _cargando,
              error: _error,
              alReintentar: _cargar,
              hijo: _sucursales.isEmpty
                  ? const EstadoVacio(mensaje: 'No hay sucursales cargadas.')
                  : RefreshIndicator(
                      color: Paleta.flame,
                      onRefresh: _cargar,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 90),
                        itemCount: _sucursales.length,
                        separatorBuilder: (contexto, indice) => const SizedBox(height: 10),
                        itemBuilder: (contexto, indice) =>
                            _tarjeta(_sucursales[indice], puedeGestionar),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipEstado(String etiqueta, bool? valor) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          label: Text(etiqueta),
          selected: _activa == valor,
          selectedColor: Paleta.flame.withValues(alpha: 0.16),
          onSelected: (_) {
            setState(() => _activa = valor);
            _cargar();
          },
        ),
      );

  Widget _tarjeta(SucursalAdminOut sucursal, bool puedeGestionar) => TarjetaPanel(
        hijo: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sucursal.nombre,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      EtiquetaDato('${sucursal.codigo} · ${sucursal.ciudad}'),
                    ],
                  ),
                ),
                BadgeEstado(sucursal.activa ? 'ACTIVA' : 'CERRADA'),
              ],
            ),
            const SizedBox(height: 10),
            FilaDato('Direccion', sucursal.direccion),
            if (sucursal.telefono != null) FilaDato('Telefono', sucursal.telefono!),
            FilaDato(
              'Horario',
              sucursal.horaApertura == null || sucursal.horaCierre == null
                  ? 'Sin definir'
                  : '${sucursal.horaApertura!.substring(0, 5)} a '
                      '${sucursal.horaCierre!.substring(0, 5)}',
            ),
            FilaDato('Vestidores', '${sucursal.cantidadVestidores}'),
            FilaDato('Equipo', '${sucursal.empleados} empleado(s) · ${sucursal.cajas} caja(s)'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _abrirCajas(sucursal, puedeGestionar),
                  icon: const Icon(Icons.point_of_sale_outlined, size: 18),
                  label: const Text('CAJAS'),
                ),
                if (puedeGestionar) ...[
                  OutlinedButton.icon(
                    onPressed: () => _abrirFormulario(sucursal: sucursal),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('EDITAR'),
                  ),
                  TextButton(
                    onPressed: () => _cambiarEstado(sucursal),
                    style: TextButton.styleFrom(
                      foregroundColor: sucursal.activa ? Paleta.rojo : Paleta.verde,
                    ),
                    child: Text(sucursal.activa ? 'CERRAR' : 'REABRIR'),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
}

/// Cajas de una sucursal: lo que CU07 necesita para abrir sesion.
class _HojaCajas extends StatefulWidget {
  const _HojaCajas({required this.sucursal, required this.puedeGestionar});

  final SucursalAdminOut sucursal;
  final bool puedeGestionar;

  @override
  State<_HojaCajas> createState() => _HojaCajasState();
}

class _HojaCajasState extends State<_HojaCajas> {
  List<CajaAdminOut> _cajas = [];
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
      final cajas = await sucursalesAdminService.listarCajas(widget.sucursal.id);
      if (!mounted) return;
      setState(() {
        _cajas = cajas;
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

  Future<void> _nuevaCaja() async {
    final codigo = TextEditingController();
    final nombre = TextEditingController();

    final creado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        backgroundColor: Paleta.blanco,
        title: const Text('Nueva caja'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codigo,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Codigo'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nombre,
              decoration: const InputDecoration(labelText: 'Nombre'),
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

    final textoCodigo = codigo.text.trim();
    final textoNombre = nombre.text.trim();
    codigo.dispose();
    nombre.dispose();
    if (creado != true || textoCodigo.isEmpty || textoNombre.isEmpty) return;

    try {
      await sucursalesAdminService.crearCaja(widget.sucursal.id, textoCodigo, textoNombre);
      if (!mounted) return;
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  Future<void> _cambiarEstadoCaja(CajaAdminOut caja) async {
    try {
      await sucursalesAdminService.cambiarEstadoCaja(caja.id, !caja.activa);
      if (!mounted) return;
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (contexto, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
              child: Row(
                children: [
                  Expanded(child: Titular('Cajas · ${widget.sucursal.codigo}', tamano: 22)),
                  if (widget.puedeGestionar)
                    IconButton(onPressed: _nuevaCaja, icon: const Icon(Icons.add)),
                ],
              ),
            ),
            Expanded(
              child: VistaAsincrona(
                cargando: _cargando,
                error: _error,
                alReintentar: _cargar,
                hijo: _cajas.isEmpty
                    ? const EstadoVacio(mensaje: 'Esta sucursal no tiene cajas.')
                    : ListView.separated(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                        itemCount: _cajas.length,
                        separatorBuilder: (contexto, indice) => const SizedBox(height: 10),
                        itemBuilder: (contexto, indice) {
                          final caja = _cajas[indice];
                          return TarjetaPanel(
                            hijo: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        caja.nombre,
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 2),
                                      EtiquetaDato(caja.codigo),
                                    ],
                                  ),
                                ),
                                if (caja.sesionAbierta)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 8),
                                    child: BadgeEstado('EN USO', color: Paleta.gold),
                                  ),
                                BadgeEstado(caja.activa ? 'ACTIVA' : 'INACTIVA'),
                                if (widget.puedeGestionar)
                                  Switch(
                                    value: caja.activa,
                                    activeThumbColor: Paleta.flame,
                                    onChanged: (_) => _cambiarEstadoCaja(caja),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      );
}

TimeOfDay? _aHora(String? texto) {
  if (texto == null || texto.length < 5) return null;
  final partes = texto.split(':');
  final hora = int.tryParse(partes[0]);
  final minuto = int.tryParse(partes[1]);
  if (hora == null || minuto == null) return null;
  return TimeOfDay(hour: hora, minute: minuto);
}

String? _textoHora(TimeOfDay? hora) => hora == null
    ? null
    : '${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}';

String? _textoHoraCompleta(TimeOfDay? hora) {
  final texto = _textoHora(hora);
  return texto == null ? null : '$texto:00';
}
