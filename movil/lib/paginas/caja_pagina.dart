import 'package:flutter/material.dart';

import '../compartido/widgets.dart';
import '../core/caja/caja_service.dart';
import '../core/config.dart';
import '../core/errores.dart';
import '../core/tema.dart';
import '../core/ventas/ventas_models.dart';
import '../core/ventas/ventas_service.dart';
import 'notificaciones_pagina.dart' show BotonNotificaciones;

/// Linea del ticket que se esta armando en el mostrador.
class _LineaTicket {
  _LineaTicket(this.variante);

  final VarianteBusquedaOut variante;
  int cantidad = 1;

  double get subtotal => variante.precio * cantidad;
}

/// CU07: Registrar Venta Presencial. El backend exige una sesion de caja ABIERTA
/// (E1) y valida el cargo CAJERO con `get_cajero_actual`.
///
/// 2.19.1.b/c: abajo de todo, "Pagos online por verificar": pedidos web/app en EFECTIVO
/// (se cobran en caja o al rendir el delivery, y entran al arqueo de la sesion abierta) y en QR
/// (la clienta informa que pago y el cajero verifica el deposito). Nada de eso se aprueba solo.
class CajaPagina extends StatefulWidget {
  const CajaPagina({super.key});

  @override
  State<CajaPagina> createState() => _CajaPaginaState();
}

class _CajaPaginaState extends State<CajaPagina> {
  final _codigo = TextEditingController();
  final _codigoFoco = FocusNode();
  final _montoInicial = TextEditingController(text: '0');
  final _montoRecibido = TextEditingController();

  SesionCajaOut? _sesion;
  List<CajaOut> _cajas = [];
  String? _cajaId;
  final List<_LineaTicket> _ticket = [];
  String _metodoPago = 'EFECTIVO';

  bool _cargando = true;
  bool _buscando = false;
  bool _cobrando = false;
  bool _abriendo = false;
  String? _error;

  List<PagoPorVerificarOut> _pagosPendientes = [];
  bool _cargandoPagos = false;
  String? _pagoEnProceso;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _codigo.dispose();
    _codigoFoco.dispose();
    _montoInicial.dispose();
    _montoRecibido.dispose();
    super.dispose();
  }

  double get _subtotal => _ticket.fold(0, (suma, linea) => suma + linea.subtotal);

  Future<void> _cargarPagosPendientes() async {
    setState(() => _cargandoPagos = true);
    try {
      final pagos = await cajaService.listarPagosPendientes();
      if (!mounted) return;
      setState(() => _pagosPendientes = pagos);
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    } finally {
      if (mounted) setState(() => _cargandoPagos = false);
    }
  }

  Future<void> _aprobarPago(PagoPorVerificarOut pago) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        backgroundColor: Paleta.blanco,
        title: Text('Aprobar ${pago.numero}'),
        content: Text(
          pago.metodo == 'EFECTIVO'
              ? 'Confirmas que cobraste ${formatearPrecio(pago.total)} en efectivo? Se descuenta '
                  'el stock, se emite el comprobante y entra al arqueo de tu caja.'
              : 'Confirmas que el deposito QR de ${formatearPrecio(pago.total)} esta en la '
                  'cuenta? Se descuenta el stock y se emite el comprobante.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contexto, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(contexto, true),
            child: const Text('Aprobar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _pagoEnProceso = pago.pagoId);
    try {
      final resultado = await cajaService.aprobarPago(pago.pagoId);
      if (!mounted) return;
      final aprobado = resultado.pagoEstado == 'APROBADO';
      mostrarAviso(
        context,
        aprobado
            ? 'Pedido ${resultado.numero} aprobado'
            : 'Pedido ${resultado.numero} anulado (${resultado.pagoEstado}): ${resultado.mensaje}',
        esError: !aprobado,
      );
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    } finally {
      if (mounted) setState(() => _pagoEnProceso = null);
      await _cargarPagosPendientes();
    }
  }

  Future<void> _rechazarPago(PagoPorVerificarOut pago) async {
    final motivo = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        backgroundColor: Paleta.blanco,
        title: Text('Rechazar ${pago.numero}'),
        content: TextField(
          controller: motivo,
          maxLength: 200,
          decoration: InputDecoration(
            labelText: 'Motivo (opcional, lo ve la clienta)',
            hintText: pago.metodo == 'QR' ? 'No encontramos el deposito' : 'No se presento a pagar',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contexto, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Paleta.rojo),
            onPressed: () => Navigator.pop(contexto, true),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    final texto = motivo.text;
    motivo.dispose();
    if (confirmado != true || !mounted) return;

    setState(() => _pagoEnProceso = pago.pagoId);
    try {
      final resultado = await cajaService.rechazarPago(pago.pagoId, motivo: texto);
      if (!mounted) return;
      mostrarAviso(context, 'Pedido ${resultado.numero} rechazado y anulado');
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    } finally {
      if (mounted) setState(() => _pagoEnProceso = null);
      await _cargarPagosPendientes();
    }
  }

  Future<void> _cargar() async {
    // la lista de pagos online no bloquea la pantalla de caja: se carga aparte
    _cargarPagosPendientes();
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final sesion = await cajaService.sesionActual();
      final cajas = sesion == null ? await cajaService.listarCajas() : <CajaOut>[];
      if (!mounted) return;
      setState(() {
        _sesion = sesion;
        _cajas = cajas;
        _cajaId = cajas.where((c) => !c.tieneSesionAbierta).firstOrNull?.id ??
            (cajas.isEmpty ? null : cajas.first.id);
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

  Future<void> _abrirSesion() async {
    final cajaId = _cajaId;
    if (cajaId == null) return;

    setState(() => _abriendo = true);
    try {
      final sesion = await cajaService.abrirSesion(
        cajaId,
        double.tryParse(_montoInicial.text.replaceAll(',', '.')) ?? 0,
      );
      if (!mounted) return;
      setState(() => _sesion = sesion);
      mostrarAviso(context, 'Caja ${sesion.cajaNombre} abierta');
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    } finally {
      if (mounted) setState(() => _abriendo = false);
    }
  }

  Future<void> _buscarPrenda() async {
    final codigo = _codigo.text.trim();
    if (codigo.isEmpty) return;

    setState(() => _buscando = true);
    try {
      final variante = await cajaService.buscarVariante(codigo);
      if (!mounted) return;
      setState(() {
        final existente = _ticket
            .where((linea) => linea.variante.varianteId == variante.varianteId)
            .firstOrNull;
        if (existente != null) {
          existente.cantidad += 1;
        } else {
          _ticket.add(_LineaTicket(variante));
        }
        _codigo.clear();
      });
      _codigoFoco.requestFocus();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  Future<void> _cobrar() async {
    if (_ticket.isEmpty) return;

    final recibido = double.tryParse(_montoRecibido.text.replaceAll(',', '.'));
    if (_metodoPago == 'EFECTIVO' && (recibido == null || recibido < _subtotal * 1.13)) {
      mostrarAviso(
        context,
        'El monto recibido no alcanza para cubrir el total con IVA.',
        esError: true,
      );
      return;
    }

    setState(() => _cobrando = true);
    try {
      final venta = await ventasService.registrarVentaPos(
        items: _ticket
            .map((linea) => {
                  'variante_id': linea.variante.varianteId,
                  'cantidad': linea.cantidad,
                })
            .toList(),
        metodoPago: _metodoPago,
        montoRecibido: _metodoPago == 'EFECTIVO' ? recibido : null,
      );
      if (!mounted) return;
      setState(() {
        _ticket.clear();
        _montoRecibido.clear();
      });
      await _mostrarComprobante(venta);
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    } finally {
      if (mounted) setState(() => _cobrando = false);
    }
  }

  Future<void> _mostrarComprobante(VentaPosOut venta) => showDialog<void>(
        context: context,
        builder: (contexto) => AlertDialog(
          backgroundColor: Paleta.blanco,
          title: Text('Venta ${venta.numero}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilaDato('Comprobante', venta.comprobanteNumero),
                FilaDato('Subtotal', formatearPrecio(venta.subtotal)),
                FilaDato('IVA 13%', formatearPrecio(venta.iva)),
                FilaDato('Total', formatearPrecio(venta.total)),
                if (venta.vuelto != null) FilaDato('Vuelto', formatearPrecio(venta.vuelto!)),
                if (venta.rechazados.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const EtiquetaDato('No se pudieron vender'),
                  const SizedBox(height: 4),
                  ...venta.rechazados.map(
                    (item) => Text(
                      '${item.sku}: ${item.motivo}',
                      style: const TextStyle(fontSize: 12.5, color: Paleta.rojo),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(contexto),
              child: const Text('Listo'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Caja'),
          actions: [
            const BotonNotificaciones(),
            IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: VistaAsincrona(
          cargando: _cargando,
          error: _error,
          alReintentar: _cargar,
          hijo: _sesion == null ? _vistaAbrirCaja() : _vistaVenta(),
        ),
      );

  Widget _vistaAbrirCaja() => ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          const Titular('Abrir caja', tamano: 26),
          const SizedBox(height: 8),
          const Text(
            'No tienes una sesion de caja abierta. Sin ella el sistema no deja registrar '
            'ventas presenciales.',
            style: TextStyle(color: Paleta.inkSuave, height: 1.45),
          ),
          const SizedBox(height: 22),
          if (_cajas.isEmpty)
            const MensajeError('Tu sucursal no tiene cajas activas configuradas (CU12).')
          else ...[
            const EtiquetaDato('Caja'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _cajaId,
              isExpanded: true,
              items: _cajas
                  .map(
                    (caja) => DropdownMenuItem(
                      value: caja.id,
                      enabled: !caja.tieneSesionAbierta,
                      child: Text(
                        '${caja.nombre}${caja.tieneSesionAbierta ? " (ocupada)" : ""}',
                        style: TextStyle(
                          color: caja.tieneSesionAbierta ? Paleta.inkSuave : Paleta.ink,
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (valor) => setState(() => _cajaId = valor),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _montoInicial,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Monto inicial en caja',
                prefixText: 'Bs ',
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _abriendo ? null : _abrirSesion,
              child: _abriendo
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Paleta.blanco),
                    )
                  : const Text('ABRIR SESION DE CAJA'),
            ),
          ],
          ..._seccionPagosPendientes(),
        ],
      );

  /// 2.19.1.b/c: pedidos online (EFECTIVO / QR) que esperan al cajero.
  List<Widget> _seccionPagosPendientes() => [
        const SizedBox(height: 28),
        Row(
          children: [
            const Expanded(child: EtiquetaDato('Pagos online por verificar')),
            if (_cargandoPagos)
              const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _cargarPagosPendientes,
                icon: const Icon(Icons.refresh, size: 20),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_pagosPendientes.isEmpty)
          const Text(
            'No hay pedidos online esperando cobro o verificacion.',
            style: TextStyle(fontSize: 13, color: Paleta.inkSuave),
          )
        else
          ..._pagosPendientes.map(_tarjetaPagoPendiente),
      ];

  Widget _tarjetaPagoPendiente(PagoPorVerificarOut pago) {
    final ocupado = _pagoEnProceso != null;
    final sinSesion = pago.metodo == 'EFECTIVO' && _sesion == null;
    final puedeAprobar = !ocupado && !pago.carritoModificado && !sinSesion;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TarjetaPanel(
        hijo: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(pago.numero, style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                BadgeEstado(pago.metodo),
                const SizedBox(width: 8),
                Text(
                  formatearPrecio(pago.total),
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Paleta.flameOscuro),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${pago.cliente} · ${pago.clienteEmail}',
              style: const TextStyle(fontSize: 12.5, color: Paleta.inkSuave),
            ),
            Text(
              pago.entrega == 'DOMICILIO'
                  ? 'Envio a domicilio (cobra el delivery)'
                  : 'Retira en sucursal',
              style: const TextStyle(fontSize: 12.5, color: Paleta.inkSuave),
            ),
            if (pago.metodo == 'QR')
              Text(
                pago.informadoEn != null
                    ? 'Informo el pago${pago.referenciaCliente != null ? ' · Ref: ${pago.referenciaCliente}' : ''}'
                    : 'La clienta todavia no informo el pago',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: pago.informadoEn != null ? FontWeight.w700 : FontWeight.w400,
                  color: pago.informadoEn != null ? Paleta.verde : Paleta.inkSuave,
                ),
              ),
            const SizedBox(height: 6),
            ...pago.items.map(
              (item) => Text(
                '${item.cantidad} x ${item.producto} (${item.talla} · ${item.color})',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
            if (pago.carritoModificado) ...[
              const SizedBox(height: 6),
              const Text(
                'La clienta modifico su carrito despues del pedido: solo se puede rechazar.',
                style: TextStyle(fontSize: 12.5, color: Paleta.rojo),
              ),
            ] else if (sinSesion) ...[
              const SizedBox(height: 6),
              const Text(
                'Abri una sesion de caja para cobrar este pedido en efectivo.',
                style: TextStyle(fontSize: 12.5, color: Paleta.rojo),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: puedeAprobar ? () => _aprobarPago(pago) : null,
                    child: _pagoEnProceso == pago.pagoId
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Paleta.blanco),
                          )
                        : Text(pago.metodo == 'EFECTIVO' ? 'COBRADO' : 'VERIFICADO'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: ocupado ? null : () => _rechazarPago(pago),
                    child: const Text('RECHAZAR'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _vistaVenta() {
    final iva = _subtotal * 0.13;
    final total = _subtotal + iva;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        TarjetaPanel(
          hijo: Row(
            children: [
              const Icon(Icons.point_of_sale, color: Paleta.verde),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _sesion!.cajaNombre,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Fondo inicial ${formatearPrecio(_sesion!.montoInicial)}',
                      style: const TextStyle(fontSize: 12.5, color: Paleta.inkSuave),
                    ),
                  ],
                ),
              ),
              BadgeEstado(_sesion!.estado),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const EtiquetaDato('Agregar prenda'),
        const SizedBox(height: 8),
        TextField(
          controller: _codigo,
          focusNode: _codigoFoco,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _buscarPrenda(),
          decoration: InputDecoration(
            labelText: 'SKU o codigo de barras',
            suffixIcon: IconButton(
              icon: _buscando
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.qr_code_scanner),
              onPressed: _buscando ? null : _buscarPrenda,
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (_ticket.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: EstadoVacio(
              mensaje: 'El ticket esta vacio. Escanea o escribe el codigo de la prenda.',
              icono: Icons.receipt_long_outlined,
            ),
          )
        else ...[
          const EtiquetaDato('Ticket'),
          const SizedBox(height: 8),
          ..._ticket.map(_filaTicket),
          const SizedBox(height: 12),
          TarjetaPanel(
            hijo: Column(
              children: [
                _fila('Subtotal', _subtotal),
                _fila('IVA 13%', iva),
                const Divider(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL',
                      style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.6),
                    ),
                    Text(
                      formatearPrecio(total),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Paleta.flameOscuro,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const EtiquetaDato('Metodo de pago'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'EFECTIVO', label: Text('Efectivo')),
              ButtonSegment(value: 'TARJETA', label: Text('Tarjeta')),
              ButtonSegment(value: 'QR', label: Text('QR')),
            ],
            selected: {_metodoPago},
            onSelectionChanged: (valores) => setState(() => _metodoPago = valores.first),
          ),
          if (_metodoPago == 'EFECTIVO') ...[
            const SizedBox(height: 14),
            TextField(
              controller: _montoRecibido,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Monto recibido',
                prefixText: 'Bs ',
                helperText: _vueltoEstimado(total),
              ),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _cobrando ? null : _cobrar,
            child: _cobrando
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Paleta.blanco),
                  )
                : Text('COBRAR ${formatearPrecio(total)}'),
          ),
        ],
        ..._seccionPagosPendientes(),
      ],
    );
  }

  String? _vueltoEstimado(double total) {
    final recibido = double.tryParse(_montoRecibido.text.replaceAll(',', '.'));
    if (recibido == null) return null;
    final vuelto = recibido - total;
    if (vuelto < 0) return 'Faltan ${formatearPrecio(-vuelto)}';
    return 'Vuelto ${formatearPrecio(vuelto)}';
  }

  Widget _fila(String etiqueta, double monto) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(etiqueta, style: const TextStyle(color: Paleta.inkSuave, fontSize: 13)),
            Text(formatearPrecio(monto), style: const TextStyle(fontSize: 13)),
          ],
        ),
      );

  Widget _filaTicket(_LineaTicket linea) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TarjetaPanel(
          padding: const EdgeInsets.all(10),
          hijo: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      linea.variante.producto,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${linea.variante.sku} · ${linea.variante.talla} · '
                      '${linea.variante.color}',
                      style: const TextStyle(fontSize: 12, color: Paleta.inkSuave),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatearPrecio(linea.variante.precio)} · '
                      'stock ${linea.variante.disponible}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      if (linea.cantidad <= 1) {
                        _ticket.remove(linea);
                      } else {
                        linea.cantidad -= 1;
                      }
                    }),
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                  ),
                  Text('${linea.cantidad}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: linea.cantidad >= linea.variante.disponible
                        ? null
                        : () => setState(() => linea.cantidad += 1),
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                  ),
                ],
              ),
              Text(
                formatearPrecio(linea.subtotal),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      );
}
