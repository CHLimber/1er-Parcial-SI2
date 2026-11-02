import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../../compartido/widgets.dart';
import '../../core/config.dart';
import '../../core/errores.dart';
import '../../core/operacion_comercial/reservas/reservas_models.dart';
import '../../core/operacion_comercial/reservas/reservas_service.dart';
import '../../core/operacion_comercial/ventas/ventas_service.dart' show asegurarStripeInicializado;
import '../../core/tema.dart';
import 'mis_reservas_pagina.dart' show fechaLegible;
import '../nucleo/notificaciones_pagina.dart' show BotonNotificaciones;

/// CU08: Atender Reserva. El Encargado de sucursal recorre la cola del dia:
/// PENDIENTE -> confirmar (o rechazar, 2.19.1.a) -> CONFIRMADA -> preparar -> PREPARADA -> cliente presente -> CLIENTE_PRESENTE ->
/// resolver (lo comprado se vende, el resto libera el compromiso de stock).
class AtenderReservasPagina extends StatefulWidget {
  const AtenderReservasPagina({super.key});

  @override
  State<AtenderReservasPagina> createState() => _AtenderReservasPaginaState();
}

class _AtenderReservasPaginaState extends State<AtenderReservasPagina> {
  static const List<String> _estados = [
    'PENDIENTE',
    'CONFIRMADA',
    'PREPARADA',
    'CLIENTE_PRESENTE',
    'ATENDIDA',
    'CONVERTIDA',
    'CANCELADA',
    'EXPIRADA',
  ];

  List<ReservaStaffOut> _reservas = [];
  String? _estadoFiltro;
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
      final reservas = await reservasService.listarDeSucursal(estado: _estadoFiltro);
      if (!mounted) return;
      setState(() {
        _reservas = reservas;
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

  /// Paso 2: marcar que prendas estan realmente en el perchero. El backend exige que la
  /// lista cubra exactamente las que siguen en estado RESERVADO.
  Future<void> _preparar(ReservaStaffOut reserva) async {
    final pendientes = reserva.items.where((i) => i.estadoItem == 'RESERVADO').toList();
    if (pendientes.isEmpty) {
      mostrarAviso(context, 'No hay prendas pendientes de preparar.', esError: true);
      return;
    }

    final disponibles = {for (final item in pendientes) item.varianteId: true};
    final motivos = <String, TextEditingController>{
      for (final item in pendientes) item.varianteId: TextEditingController(),
    };

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => StatefulBuilder(
        builder: (contexto, actualizar) => AlertDialog(
          backgroundColor: Paleta.blanco,
          title: const Text('Preparar prendas'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Marca las prendas que encontraste. Las que desmarques liberan su '
                  'compromiso de stock y se le informa al cliente.',
                  style: TextStyle(fontSize: 13, color: Paleta.inkSuave, height: 1.4),
                ),
                const SizedBox(height: 12),
                ...pendientes.map(
                  (item) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CheckboxListTile(
                        value: disponibles[item.varianteId],
                        onChanged: (valor) =>
                            actualizar(() => disponibles[item.varianteId] = valor ?? false),
                        contentPadding: EdgeInsets.zero,
                        activeColor: Paleta.flame,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          '${item.cantidad} x ${item.producto}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${item.talla} · ${item.color} · ${item.sku}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      if (disponibles[item.varianteId] == false)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TextField(
                            controller: motivos[item.varianteId],
                            maxLength: 250,
                            decoration: const InputDecoration(
                              labelText: 'Motivo',
                              hintText: 'No estaba en percha, danada, etc.',
                              isDense: true,
                              counterText: '',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(contexto, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(contexto, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (confirmado != true) {
      for (final control in motivos.values) {
        control.dispose();
      }
      return;
    }

    final items = pendientes
        .map((item) => {
              'variante_id': item.varianteId,
              'disponible': disponibles[item.varianteId] ?? true,
              'motivo': motivos[item.varianteId]!.text.trim().isEmpty
                  ? null
                  : motivos[item.varianteId]!.text.trim(),
            })
        .toList();
    for (final control in motivos.values) {
      control.dispose();
    }

    await _ejecutar(() => reservasService.preparar(reserva.id, items), 'Reserva preparada');
  }

  /// Pasos 3-4: el cliente llega y se le asigna un vestidor.
  Future<void> _marcarPresente(ReservaStaffOut reserva) async {
    final vestidor = TextEditingController(text: reserva.vestidorAsignado ?? '');
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        backgroundColor: Paleta.blanco,
        title: const Text('Cliente presente'),
        content: TextField(
          controller: vestidor,
          maxLength: 20,
          decoration: const InputDecoration(
            labelText: 'Vestidor asignado (opcional)',
            hintText: 'V-03',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contexto, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(contexto, true),
            child: const Text('Confirmar llegada'),
          ),
        ],
      ),
    );

    final texto = vestidor.text.trim();
    vestidor.dispose();
    if (confirmado != true) return;

    await _ejecutar(
      () => reservasService.marcarPresente(reserva.id, texto),
      'Cliente en el vestidor',
    );
  }

  double _totalConIva(List<ReservaItemOut> probadas, Map<String, bool> comprados) {
    final subtotal = probadas
        .where((i) => comprados[i.varianteId] ?? false)
        .fold<double>(0, (s, i) => s + (i.precio ?? 0) * i.cantidad);
    return (subtotal * 1.13 * 100).roundToDouble() / 100;
  }

  /// Cobro con tarjeta en el vestidor (PENDIENTES 11): arma la venta pendiente, abre el
  /// PaymentSheet de Stripe para que la clienta pague en este telefono y, cuando Stripe confirma,
  /// la venta y la reserva se cierran solas (el backend verifica el pago si el webhook no llega).
  Future<void> _cobrarConStripe(ReservaStaffOut reserva, List<Map<String, dynamic>> decisiones) async {
    try {
      final cobro = await reservasService.iniciarCobroStripe(reserva.id, decisiones: decisiones);
      final secreto = cobro.clientSecret;
      if (secreto == null) throw Exception('Stripe no devolvio el formulario de pago');
      await asegurarStripeInicializado();
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: secreto,
          merchantDisplayName: 'FashionStore',
          appearance: PaymentSheetAppearance(
            colors: PaymentSheetAppearanceColors(primary: Paleta.flame),
          ),
        ),
      );
      await Stripe.instance.presentPaymentSheet();
    } on StripeException catch (error) {
      // la clienta cerro el formulario o la tarjeta fue rechazada: se cierra el intento para
      // poder cobrar de otra forma
      await _cancelarCobroSilencioso(reserva.id);
      if (!mounted) return;
      final cancelado = error.error.code == FailureCode.Canceled;
      mostrarAviso(
        context,
        cancelado
            ? 'Cobro con tarjeta cancelado. Podes cobrar con otro metodo.'
            : (error.error.localizedMessage ?? 'Stripe rechazo el pago.'),
        esError: !cancelado,
      );
      return;
    } catch (error) {
      if (mounted) mostrarAviso(context, interpretarError(error), esError: true);
      return;
    }

    // pagado en el PaymentSheet: se espera la confirmacion (webhook o verificacion)
    CobroStripeOut? cobro;
    for (var intento = 0; intento < 10; intento++) {
      try {
        cobro = await reservasService.estadoCobroStripe(reserva.id);
        if (cobro.cobrado || cobro.estado == 'ANULADA') break;
      } catch (_) {
        // reintenta
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    await _cargar();
    if (!mounted) return;
    if (cobro != null && cobro.cobrado) {
      await showDialog<void>(
        context: context,
        builder: (contexto) => AlertDialog(
          backgroundColor: Paleta.blanco,
          title: Text('Reserva ${reserva.codigo}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FilaDato('Pago', 'Tarjeta (Stripe)'),
              if (cobro!.ventaNumero != null) FilaDato('Venta', cobro.ventaNumero!),
              if (cobro.comprobanteNumero != null) FilaDato('Comprobante', cobro.comprobanteNumero!),
              if (cobro.total != null) FilaDato('Cobrado', formatearPrecio(cobro.total!)),
            ],
          ),
          actions: [
            ElevatedButton(onPressed: () => Navigator.pop(contexto), child: const Text('Listo')),
          ],
        ),
      );
    } else {
      mostrarAviso(
        context,
        'Stripe todavia no confirmo el pago. Volve a abrir la reserva en unos segundos.',
        esError: true,
      );
    }
  }

  Future<void> _cancelarCobroSilencioso(String reservaId) async {
    try {
      await reservasService.cancelarCobroStripe(reservaId);
    } catch (_) {
      // si ya no habia cobro pendiente no hay nada que cerrar
    }
  }

  /// Pasos 5-7: decision final. Lo comprado se factura como venta POS (CU07).
  Future<void> _resolver(ReservaStaffOut reserva) async {
    final probadas = reserva.items.where((i) => i.estadoItem == 'PREPARADO').toList();
    if (probadas.isEmpty) {
      mostrarAviso(context, 'No hay prendas preparadas para resolver.', esError: true);
      return;
    }

    final comprados = {for (final item in probadas) item.varianteId: false};
    String metodoPago = 'EFECTIVO';
    final montoRecibido = TextEditingController();

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => StatefulBuilder(
        builder: (contexto, actualizar) {
          final hayCompras = comprados.values.any((v) => v);
          final total = _totalConIva(probadas, comprados);
          return AlertDialog(
            backgroundColor: Paleta.blanco,
            title: const Text('Cerrar reserva'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Marca lo que el cliente se lleva. Lo que quede sin marcar libera su '
                    'compromiso y vuelve a estar disponible.',
                    style: TextStyle(fontSize: 13, color: Paleta.inkSuave, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  ...probadas.map(
                    (item) => CheckboxListTile(
                      value: comprados[item.varianteId],
                      onChanged: (valor) =>
                          actualizar(() => comprados[item.varianteId] = valor ?? false),
                      contentPadding: EdgeInsets.zero,
                      activeColor: Paleta.flame,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        '${item.cantidad} x ${item.producto}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${item.talla} · ${item.color} · ${item.sku}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  if (hayCompras) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Total a cobrar (IVA incluido): ${formatearPrecio(total)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    const EtiquetaDato('Metodo de pago'),
                    const SizedBox(height: 8),
                    // cuatro metodos: en dos filas para que entren en un telefono angosto
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final m in const [
                          ('EFECTIVO', 'Efectivo'),
                          ('TARJETA', 'Tarjeta POS'),
                          ('QR', 'QR'),
                          ('STRIPE', 'Stripe'),
                        ])
                          ChoiceChip(
                            label: Text(m.$2),
                            selected: metodoPago == m.$1,
                            selectedColor: Paleta.flame.withValues(alpha: 0.18),
                            onSelected: (_) => actualizar(() => metodoPago = m.$1),
                          ),
                      ],
                    ),
                    if (metodoPago == 'QR') ...[
                      const SizedBox(height: 12),
                      Center(
                        child: Image.asset('assets/images/pago-qr.jpeg', width: 220, fit: BoxFit.contain),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Mostrale el QR a la clienta para que pague ${formatearPrecio(total)} desde su banco. '
                        'Confirma recien cuando veas el pago acreditado.',
                        style: const TextStyle(fontSize: 12.5, color: Paleta.inkSuave, height: 1.35),
                      ),
                    ],
                    if (metodoPago == 'STRIPE') ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Se abre el formulario de tarjeta de Stripe en este telefono para que la clienta '
                        'pague. La venta se registra sola cuando Stripe confirma.',
                        style: TextStyle(fontSize: 12.5, color: Paleta.inkSuave, height: 1.35),
                      ),
                    ],
                    if (metodoPago == 'EFECTIVO') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: montoRecibido,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Monto recibido',
                          prefixText: 'Bs ',
                          isDense: true,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(contexto, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(contexto, true),
                child: Text(!hayCompras
                    ? 'Cerrar sin compra'
                    : metodoPago == 'QR'
                        ? 'Pago QR recibido'
                        : metodoPago == 'STRIPE'
                            ? 'Cobrar con Stripe'
                            : 'Cobrar y cerrar'),
              ),
            ],
          );
        },
      ),
    );

    final recibido = double.tryParse(montoRecibido.text.replaceAll(',', '.'));
    montoRecibido.dispose();
    if (confirmado != true) return;

    final hayCompras = comprados.values.any((v) => v);
    final decisiones = probadas
        .map((item) => {
              'variante_id': item.varianteId,
              'comprado': comprados[item.varianteId] ?? false,
            })
        .toList();

    if (hayCompras && metodoPago == 'STRIPE') {
      await _cobrarConStripe(reserva, decisiones);
      return;
    }

    try {
      final resultado = await reservasService.resolver(
        reserva.id,
        decisiones: decisiones,
        metodoPago: hayCompras ? metodoPago : null,
        montoRecibido: hayCompras && metodoPago == 'EFECTIVO' ? recibido : null,
      );
      if (!mounted) return;
      await _cargar();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (contexto) => AlertDialog(
          backgroundColor: Paleta.blanco,
          title: Text('Reserva ${resultado.reserva.codigo}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilaDato('Estado', '', valorWidget: BadgeEstado(resultado.reserva.estado)),
              if (resultado.ventaNumero != null) FilaDato('Venta', resultado.ventaNumero!),
              if (resultado.comprobanteNumero != null)
                FilaDato('Comprobante', resultado.comprobanteNumero!),
              if (resultado.totalCobrado != null)
                FilaDato('Cobrado', formatearPrecio(resultado.totalCobrado!)),
              if (resultado.ventaNumero == null)
                const Text(
                  'El cliente no se llevo ninguna prenda; el stock quedo liberado.',
                  style: TextStyle(fontSize: 13, color: Paleta.inkSuave),
                ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(contexto),
              child: const Text('Listo'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  /// 2.19.1.a: la sucursal acepta la reserva; el stock ya estaba apartado.
  Future<void> _confirmarReserva(ReservaStaffOut reserva) async {
    await _ejecutar(
      () => reservasService.confirmar(reserva.id),
      'Reserva confirmada, se le aviso al cliente',
    );
  }

  /// 2.19.1.a: la sucursal no puede atenderla. El motivo le llega al cliente.
  Future<void> _rechazarReserva(ReservaStaffOut reserva) async {
    final motivo = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        backgroundColor: Paleta.blanco,
        title: Text('Rechazar ${reserva.codigo}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se libera el stock apartado y se le avisa al cliente con este motivo.',
              style: TextStyle(fontSize: 13, color: Paleta.inkSuave, height: 1.4),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: motivo,
              maxLength: 150,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Motivo',
                hintText: 'Sin vestidores libres ese dia, etc.',
                counterText: '',
              ),
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

    await _ejecutar(
      () => reservasService.rechazar(reserva.id, texto),
      'Reserva rechazada y stock liberado',
    );
  }

  Future<void> _noPresentado(ReservaStaffOut reserva) async {
    final confirmado = await confirmar(
      context,
      titulo: 'Marcar no presentado',
      mensaje: 'La reserva ${reserva.codigo} expira y se libera todo el stock comprometido.',
      textoConfirmar: 'Expirar reserva',
      destructivo: true,
    );
    if (!confirmado) return;
    await _ejecutar(
      () => reservasService.marcarNoPresentado(reserva.id),
      'Reserva expirada y stock liberado',
    );
  }

  Future<void> _ejecutar(Future<void> Function() accion, String aviso) async {
    try {
      await accion();
      if (!mounted) return;
      mostrarAviso(context, aviso);
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Atender reservas'),
          actions: [
            const BotonNotificaciones(),
            IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: Column(
          children: [
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: const Text('Todas'),
                      selected: _estadoFiltro == null,
                      selectedColor: Paleta.flame.withValues(alpha: 0.16),
                      onSelected: (_) {
                        setState(() => _estadoFiltro = null);
                        _cargar();
                      },
                    ),
                  ),
                  ..._estados.map(
                    (estado) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(estado.replaceAll('_', ' ')),
                        selected: _estadoFiltro == estado,
                        selectedColor: Paleta.flame.withValues(alpha: 0.16),
                        onSelected: (elegido) {
                          setState(() => _estadoFiltro = elegido ? estado : null);
                          _cargar();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: VistaAsincrona(
                cargando: _cargando,
                error: _error,
                alReintentar: _cargar,
                hijo: _reservas.isEmpty
                    ? const EstadoVacio(
                        mensaje: 'No hay reservas con ese estado en tu sucursal.',
                        icono: Icons.event_busy_outlined,
                      )
                    : RefreshIndicator(
                        color: Paleta.flame,
                        onRefresh: _cargar,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                          itemCount: _reservas.length,
                          separatorBuilder: (contexto, indice) => const SizedBox(height: 12),
                          itemBuilder: (contexto, indice) => _tarjeta(_reservas[indice]),
                        ),
                      ),
              ),
            ),
          ],
        ),
      );

  Widget _tarjeta(ReservaStaffOut reserva) => TarjetaPanel(
        hijo: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    reserva.codigo,
                    style: fuenteMono(fontSize: 15, fontWeight: FontWeight.w700, color: Paleta.ink),
                  ),
                ),
                BadgeEstado(reserva.estado),
              ],
            ),
            const SizedBox(height: 10),
            FilaDato('Cliente', reserva.cliente.nombreCompleto),
            FilaDato('Contacto', reserva.cliente.telefono ?? reserva.cliente.email),
            FilaDato('Visita', '${reserva.fechaVisita} a las ${reserva.horaVisita.substring(0, 5)}'),
            if (reserva.vestidorAsignado != null)
              FilaDato('Vestidor', reserva.vestidorAsignado!),
            if (reserva.expiraEn != null) FilaDato('Vence', fechaLegible(reserva.expiraEn!)),
            if (reserva.observaciones != null && reserva.observaciones!.isNotEmpty)
              FilaDato('Nota', reserva.observaciones!),
            const SizedBox(height: 10),
            const EtiquetaDato('Prendas'),
            const SizedBox(height: 6),
            ...reserva.items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item.cantidad} x ${item.producto} · ${item.talla} · ${item.color}',
                        style: const TextStyle(fontSize: 13, height: 1.3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    BadgeEstado(item.estadoItem),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _acciones(reserva),
            ),
          ],
        ),
      );

  List<Widget> _acciones(ReservaStaffOut reserva) {
    switch (reserva.estado) {
      case 'PENDIENTE':
        return [
          ElevatedButton.icon(
            onPressed: () => _confirmarReserva(reserva),
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('CONFIRMAR'),
          ),
          OutlinedButton(
            onPressed: () => _rechazarReserva(reserva),
            child: const Text('RECHAZAR'),
          ),
        ];
      case 'CONFIRMADA':
        return [
          ElevatedButton.icon(
            onPressed: () => _preparar(reserva),
            icon: const Icon(Icons.inventory_2_outlined, size: 18),
            label: const Text('PREPARAR'),
          ),
          OutlinedButton(
            onPressed: () => _noPresentado(reserva),
            child: const Text('NO SE PRESENTO'),
          ),
        ];
      case 'PREPARADA':
        return [
          ElevatedButton.icon(
            onPressed: () => _marcarPresente(reserva),
            icon: const Icon(Icons.how_to_reg_outlined, size: 18),
            label: const Text('CLIENTE PRESENTE'),
          ),
          OutlinedButton(
            onPressed: () => _noPresentado(reserva),
            child: const Text('NO SE PRESENTO'),
          ),
        ];
      case 'CLIENTE_PRESENTE':
        return [
          ElevatedButton.icon(
            onPressed: () => _resolver(reserva),
            icon: const Icon(Icons.point_of_sale_outlined, size: 18),
            label: const Text('CERRAR RESERVA'),
          ),
        ];
      default:
        return [
          Text(
            reserva.atendidaEn == null
                ? 'Sin acciones pendientes.'
                : 'Atendida el ${fechaLegible(reserva.atendidaEn!)}.',
            style: const TextStyle(fontSize: 12.5, color: Paleta.inkSuave),
          ),
        ];
    }
  }
}
