import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../compartido/widgets.dart';
import '../../core/acceso_y_organizacion/auth/auth_service.dart';
import '../../core/config.dart';
import '../../core/errores.dart';
import '../../core/operacion_sin_conexion/offline/conexion_service.dart';
import '../../core/operacion_sin_conexion/sincronizacion/sincronizacion_models.dart';
import '../../core/operacion_sin_conexion/sincronizacion/sincronizacion_service.dart';
import '../../core/tema.dart';

/// a partir de cuantas horas se avisa que las existencias pueden haber cambiado
const _horasDesactualizado = 2;

class _Linea {
  _Linea(this.producto, this.variante, this.cantidad);

  final ProductoLocal producto;
  final VarianteLocal variante;
  int cantidad;
}

/// Operacion sin conexion del personal en el movil (Modulos C y D: CU17 a CU23). Espejo de
/// `pages/venta-offline` de la web, con SQLite: se baja el catalogo de la sucursal, se vende de
/// contado y se registran reservas sin red; cada operacion queda en el telefono con su UUID y se
/// sincroniza sola al volver la conexion. Sobrevive a cerrar y reabrir la app.
class VentaOfflinePagina extends StatefulWidget {
  const VentaOfflinePagina({super.key});

  @override
  State<VentaOfflinePagina> createState() => _VentaOfflinePaginaState();
}

class _VentaOfflinePaginaState extends State<VentaOfflinePagina> {
  final _busqueda = TextEditingController();
  final _montoRecibido = TextEditingController();
  final _clienteVenta = TextEditingController();
  final _observaciones = TextEditingController();
  final List<_Linea> _ticket = [];
  String? _clienteReserva;
  DateTime _fechaVisita = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _horaVisita = const TimeOfDay(hour: 11, minute: 0);
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final sync = context.read<SincronizacionService>();
      await sync.cargarLocal();
      if (sync.paquete == null && mounted && context.read<ConexionService>().enLinea) {
        await _descargar();
      }
    });
  }

  @override
  void dispose() {
    _busqueda.dispose();
    _montoRecibido.dispose();
    _clienteVenta.dispose();
    _observaciones.dispose();
    super.dispose();
  }

  Future<void> _correr(Future<void> Function() accion) async {
    setState(() => _ocupado = true);
    try {
      await accion();
    } on ApiException catch (e) {
      if (mounted) mostrarAviso(context, e.mensaje, esError: true);
    } catch (e) {
      if (mounted) mostrarAviso(context, e.toString(), esError: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _descargar() => _correr(() async {
        final p = await context.read<SincronizacionService>().descargarPaquete();
        if (mounted) {
          mostrarAviso(context,
              'Catalogo de ${p.sucursal} descargado: ${p.productos.length} prendas y ${p.clientes.length} clientas.');
        }
      });

  void _agregar(ProductoLocal producto, VarianteLocal variante) {
    final ya = _ticket.where((l) => l.variante.id == variante.id).firstOrNull;
    final cantidad = (ya?.cantidad ?? 0) + 1;
    if (cantidad > variante.disponible) {
      mostrarAviso(context, 'De ${variante.sku} hay ${variante.disponible} unidad(es) conocidas.', esError: true);
      return;
    }
    setState(() {
      if (ya != null) {
        ya.cantidad = cantidad;
      } else {
        _ticket.add(_Linea(producto, variante, 1));
      }
    });
  }

  double _total(PaqueteLocal p) =>
      totalConIva(_ticket.map((l) => (l.variante.precio, l.cantidad)), p.ivaTasa);

  List<LineaNueva> get _lineas => [for (final l in _ticket) LineaNueva(l.variante.id, l.cantidad)];

  void _limpiar() {
    _ticket.clear();
    _montoRecibido.clear();
    _clienteVenta.clear();
    _observaciones.clear();
    _clienteReserva = null;
  }

  Future<void> _registrarVenta(PaqueteLocal p) async {
    final monto = double.tryParse(_montoRecibido.text.replaceAll(',', '.'));
    final total = _total(p);
    if (monto != null && monto < total) {
      mostrarAviso(context, 'El efectivo recibido no alcanza para el total.', esError: true);
      return;
    }
    await _correr(() async {
      final sync = context.read<SincronizacionService>();
      final enLinea = context.read<ConexionService>().enLinea;
      final op = await sync.registrarVenta(
        _lineas,
        montoRecibido: monto,
        clienteEmail: _clienteVenta.text.trim().isEmpty ? null : _clienteVenta.text.trim(),
      );
      setState(_limpiar);
      if (mounted) {
        mostrarAviso(
          context,
          'Venta de ${formatearPrecio(op.total)} registrada'
          '${enLinea ? ' y enviada.' : ' en el telefono: se sincroniza al volver la red.'}',
        );
      }
    });
  }

  Future<void> _registrarReserva() async {
    if (_clienteReserva == null) {
      mostrarAviso(context, 'Elegi la clienta de la reserva.', esError: true);
      return;
    }
    await _correr(() async {
      final f = _fechaVisita;
      await context.read<SincronizacionService>().registrarReserva(
            _lineas,
            clienteEmail: _clienteReserva!,
            fechaVisita: '${f.year}-${_dos(f.month)}-${_dos(f.day)}',
            horaVisita: '${_dos(_horaVisita.hour)}:${_dos(_horaVisita.minute)}',
            observaciones: _observaciones.text.trim().isEmpty ? null : _observaciones.text.trim(),
          );
      setState(_limpiar);
      if (mounted) {
        mostrarAviso(context, 'Reserva registrada: compromete las prendas cuando el servidor la confirme.');
      }
    });
  }

  static String _dos(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final sync = context.watch<SincronizacionService>();
    final conexion = context.watch<ConexionService>();
    final puedeVender = auth.tienePermiso([permisoCaja]);
    final puedeReservar = auth.tienePermiso([permisoAtenderReservas]);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Vender sin conexion'),
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Catalogo'),
              Tab(text: _ticket.isEmpty ? 'Ticket' : 'Ticket (${_ticket.length})'),
              Tab(text: sync.pendientes > 0 ? 'Operaciones (${sync.pendientes})' : 'Operaciones'),
            ],
          ),
        ),
        body: Column(
          children: [
            _BarraEstado(conexion: conexion, sync: sync, alSincronizar: () => _correr(sync.sincronizar)),
            if (!auth.tieneFuncion('operacion_offline'))
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: MensajeError(
                  'El plan de tu empresa no incluye la operacion offline (o la suscripcion vencio): '
                  'el servidor va a rechazar lo que registres.',
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _catalogo(sync, conexion),
                  _ticketVista(sync.paquete, puedeVender, puedeReservar),
                  _operaciones(sync, auth),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catalogo(SincronizacionService sync, ConexionService conexion) {
    final p = sync.paquete;
    final q = _busqueda.text.trim().toLowerCase();
    final productos = p == null
        ? const <ProductoLocal>[]
        : p.productos
            .where((x) =>
                q.isEmpty ||
                '${x.nombre} ${x.codigo} ${x.categoria} ${x.variantes.map((v) => v.sku).join(' ')}'
                    .toLowerCase()
                    .contains(q))
            .take(40)
            .toList();
    final viejo = p != null &&
        (!conexion.enLinea ||
            DateTime.now().difference(p.generadoEn).inHours >= _horasDesactualizado);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (p == null)
          EstadoVacio(
            mensaje: conexion.enLinea
                ? 'Todavia no descargaste el catalogo de tu sucursal.'
                : 'Sin conexion y sin catalogo descargado: conectate una vez para bajarlo.',
            icono: Icons.cloud_download_outlined,
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  '${p.empresa} · ${p.sucursal}\nDescargado ${_fecha(p.generadoEn)}',
                  style: const TextStyle(fontSize: 12.5, color: Paleta.inkSuave),
                ),
              ),
            ],
          ),
          if (viejo)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              color: Paleta.gold.withValues(alpha: 0.15),
              child: const Text(
                'Las existencias y precios pueden estar desactualizados: son los del momento de la '
                'descarga, menos lo que vendiste o reservaste en este telefono.',
                style: TextStyle(fontSize: 12.5),
              ),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: _busqueda,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Buscar prenda, codigo o SKU'),
          ),
          const SizedBox(height: 10),
          ...productos.map(
            (prod) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TarjetaPanel(
                padding: const EdgeInsets.all(12),
                hijo: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(prod.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${prod.codigo} · ${prod.categoria}',
                        style: const TextStyle(fontSize: 12, color: Paleta.inkSuave)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: prod.variantes
                          .map((v) => ActionChip(
                                label: Text(
                                  '${v.talla}/${v.color} · ${formatearPrecio(v.precio)} · ${v.disponible}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onPressed: v.disponible > 0 ? () => _agregar(prod, v) : null,
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _ocupado || !conexion.enLinea ? null : _descargar,
          icon: const Icon(Icons.cloud_download_outlined),
          label: Text(p == null ? 'Descargar catalogo' : 'Actualizar catalogo'),
        ),
      ],
    );
  }

  Widget _ticketVista(PaqueteLocal? p, bool puedeVender, bool puedeReservar) {
    if (p == null || _ticket.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: EstadoVacio(mensaje: 'Toca una talla/color en el catalogo para agregarla al ticket.'),
      );
    }
    final total = _total(p);
    final monto = double.tryParse(_montoRecibido.text.replaceAll(',', '.'));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        ..._ticket.map(
          (l) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${l.producto.nombre} ${l.variante.talla}/${l.variante.color}'),
            subtitle: Text('${formatearPrecio(l.variante.precio)} c/u'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => setState(() {
                    l.cantidad--;
                    if (l.cantidad <= 0) _ticket.remove(l);
                  }),
                ),
                Text('${l.cantidad}'),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: l.cantidad < l.variante.disponible ? () => setState(() => l.cantidad++) : null,
                ),
              ],
            ),
          ),
        ),
        const Divider(),
        FilaDato('Total con IVA', formatearPrecio(total)),
        if (puedeVender) ...[
          const SizedBox(height: 16),
          const EtiquetaDato('Venta de contado (efectivo)'),
          const SizedBox(height: 8),
          TextField(
            controller: _montoRecibido,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Efectivo recibido (opcional)'),
          ),
          if (monto != null && monto >= total)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Vuelto: ${formatearPrecio(monto - total)}'),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _clienteVenta,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email de la clienta (opcional)'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _ocupado ? null : () => _registrarVenta(p),
            icon: const Icon(Icons.point_of_sale_outlined),
            label: const Text('Registrar venta'),
          ),
          const Text(
            'Cobrar el efectivo no confirma la venta: queda pendiente hasta que el servidor la acepte.',
            style: TextStyle(fontSize: 12, color: Paleta.inkSuave),
          ),
        ],
        if (puedeReservar) ...[
          const SizedBox(height: 22),
          const EtiquetaDato('Reserva para una clienta'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _clienteReserva,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Clienta'),
            items: p.clientes
                .map((c) => DropdownMenuItem(value: c.email, child: Text('${c.nombre} · ${c.email}')))
                .toList(),
            onChanged: (v) => setState(() => _clienteReserva = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final f = await showDatePicker(
                      context: context,
                      initialDate: _fechaVisita,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 60)),
                    );
                    if (f != null) setState(() => _fechaVisita = f);
                  },
                  child: Text('Visita ${_fechaVisita.day}/${_fechaVisita.month}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final h = await showTimePicker(context: context, initialTime: _horaVisita);
                    if (h != null) setState(() => _horaVisita = h);
                  },
                  child: Text('${_dos(_horaVisita.hour)}:${_dos(_horaVisita.minute)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _observaciones,
            decoration: const InputDecoration(labelText: 'Observaciones (opcional)'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _ocupado ? null : _registrarReserva,
            icon: const Icon(Icons.checkroom_outlined),
            label: const Text('Registrar reserva'),
          ),
        ],
      ],
    );
  }

  Widget _operaciones(SincronizacionService sync, AuthService auth) {
    final gestiona = auth.tienePermiso(['sincronizacion.actualizar']);
    return RefreshIndicator(
      onRefresh: sync.cargarLocal,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (sync.operaciones.isEmpty)
            const EstadoVacio(mensaje: 'Todavia no registraste operaciones en este telefono.'),
          ...sync.operaciones.map((o) => _tarjetaOperacion(o, sync, gestiona)),
          if (sync.operaciones.any((o) => !o.estado.pendiente && o.estado != EstadoLocal.conflicto))
            TextButton(
              onPressed: () async {
                final n = await sync.archivarCerradas();
                if (mounted) {
                  mostrarAviso(context, '$n operacion(es) cerradas se quitaron del telefono (siguen en el servidor).');
                }
              },
              child: const Text('Quitar del telefono las confirmadas y rechazadas'),
            ),
        ],
      ),
    );
  }

  Widget _tarjetaOperacion(OperacionLocal o, SincronizacionService sync, bool gestiona) {
    final color = switch (o.estado) {
      EstadoLocal.confirmada => Paleta.verde,
      EstadoLocal.rechazada => Paleta.rojo,
      EstadoLocal.conflicto => Paleta.gold,
      _ => Paleta.inkSuave,
    };
    return Padding(
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
                    '${o.esVenta ? 'Venta' : 'Reserva'} · ${_fecha(o.registradaEn)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                BadgeEstado(o.estado.etiqueta, color: color),
              ],
            ),
            const SizedBox(height: 4),
            Text(o.descripcion, style: const TextStyle(fontSize: 12.5)),
            if (o.esVenta) Text('Total ${formatearPrecio(o.total)} en efectivo', style: const TextStyle(fontSize: 12.5)),
            if (o.numero != null)
              Text('Servidor: ${o.numero}${o.duplicada ? ' (ya se habia recibido)' : ''}',
                  style: const TextStyle(fontSize: 12, color: Paleta.verde)),
            if (o.motivo != null)
              Text('${o.codigoMotivo}: ${o.motivo}', style: TextStyle(fontSize: 12, color: color)),
            if (o.errorRed != null && o.estado.pendiente)
              Text(o.errorRed!, style: const TextStyle(fontSize: 12, color: Paleta.inkSuave)),
            if (o.resolucion != null)
              Text('Resolucion: ${o.resolucion}', style: const TextStyle(fontSize: 12, color: Paleta.inkSuave)),
            Text(
              'Id ${o.id.substring(0, 8)} · ${o.intentosEnvio} envio(s)',
              style: const TextStyle(fontSize: 11, color: Paleta.inkSuave),
            ),
            if (o.estado == EstadoLocal.conflicto || o.estado == EstadoLocal.enviada)
              Wrap(
                spacing: 6,
                children: [
                  TextButton(
                    onPressed: _ocupado ? null : () => _correr(() => sync.refrescar(o.id)),
                    child: const Text('Consultar'),
                  ),
                  if (o.estado == EstadoLocal.conflicto) ...[
                    TextButton(
                      onPressed: _ocupado ? null : () => _correr(() => sync.resolver(o.id, 'REINTENTAR')),
                      child: const Text('Reintentar'),
                    ),
                    if (gestiona && o.codigoMotivo == 'PRECIO_CAMBIADO')
                      TextButton(
                        onPressed: _ocupado
                            ? null
                            : () => _correr(() => sync.resolver(o.id, 'ACEPTAR_PRECIO_ACTUAL')),
                        child: const Text('Aceptar precio actual'),
                      ),
                    if (gestiona)
                      TextButton(
                        onPressed: _ocupado
                            ? null
                            : () async {
                                final ok = await confirmar(
                                  context,
                                  titulo: 'Descartar operacion',
                                  mensaje: 'Queda rechazada y no se vuelve a procesar. '
                                      'La plata cobrada se devuelve fuera del sistema.',
                                  textoConfirmar: 'Descartar',
                                  destructivo: true,
                                );
                                if (ok) await _correr(() => sync.resolver(o.id, 'DESCARTAR'));
                              },
                        child: const Text('Descartar', style: TextStyle(color: Paleta.rojo)),
                      ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  static String _fecha(DateTime f) {
    final l = f.toLocal();
    return '${_dos(l.day)}/${_dos(l.month)} ${_dos(l.hour)}:${_dos(l.minute)}';
  }
}

class _BarraEstado extends StatelessWidget {
  const _BarraEstado({required this.conexion, required this.sync, required this.alSincronizar});

  final ConexionService conexion;
  final SincronizacionService sync;
  final VoidCallback alSincronizar;

  @override
  Widget build(BuildContext context) {
    final texto = !conexion.enLinea
        ? 'Sin conexion · ${sync.pendientes} por sincronizar'
        : sync.sincronizando
            ? 'Sincronizando…'
            : sync.ultimoResultado ?? '${sync.pendientes} por sincronizar';
    return Container(
      width: double.infinity,
      color: conexion.enLinea ? Paleta.paper : Paleta.gold.withValues(alpha: 0.2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(conexion.enLinea ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 12.5))),
          if (sync.enConflicto > 0) BadgeEstado('${sync.enConflicto} en conflicto', color: Paleta.gold),
          TextButton(
            onPressed: conexion.enLinea && !sync.sincronizando && sync.pendientes > 0 ? alSincronizar : null,
            child: const Text('Sincronizar'),
          ),
        ],
      ),
    );
  }
}
