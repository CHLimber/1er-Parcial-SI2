import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../compartido/widgets.dart';
import '../core/config.dart';
import '../core/errores.dart';
import '../core/tema.dart';
import '../core/ventas/ventas_models.dart';
import '../core/ventas/ventas_service.dart';

/// Pago QR (2.19.1.c). Antes esta pantalla "aprobaba" el pago sola contra un webhook publico;
/// ahora muestra el QR, la clienta deposita desde su banco y solo INFORMA que pago (con una
/// referencia opcional). Quien aprueba o rechaza es el cajero de la sucursal desde caja.
class PagoSimuladoPagina extends StatefulWidget {
  const PagoSimuladoPagina({super.key, required this.ventaId});

  final String ventaId;

  @override
  State<PagoSimuladoPagina> createState() => _PagoSimuladoPaginaState();
}

class _PagoSimuladoPaginaState extends State<PagoSimuladoPagina> {
  final _referencia = TextEditingController();

  VentaOut? _venta;
  bool _cargando = true;
  bool _enviando = false;
  String? _error;
  String? _errorInforme;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _referencia.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final venta = await ventasService.obtenerVenta(widget.ventaId);
      if (!mounted) return;
      // Si ya se resolvio (lo verifico el cajero, o se reintento el checkout), ir a la confirmacion.
      if (venta.pago?.estado != 'PENDIENTE') {
        context.pushReplacement('/compra/${widget.ventaId}');
        return;
      }
      _referencia.text = venta.pago?.referenciaCliente ?? '';
      setState(() {
        _venta = venta;
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

  Future<void> _informarPago() async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _errorInforme = null;
    });
    try {
      await pagosService.informarPagoQr(widget.ventaId, referencia: _referencia.text);
      if (!mounted) return;
      context.pushReplacement('/compra/${widget.ventaId}');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorInforme = interpretarError(error);
        _enviando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final venta = _venta;
    final esQr = venta?.pago?.pasarela == 'QR';
    final yaInformado = venta?.pago?.informadoEn != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Pago con QR')),
      body: VistaAsincrona(
        cargando: _cargando,
        error: _error,
        alReintentar: _cargar,
        hijo: venta == null
            ? const EstadoVacio(mensaje: 'No se encontro la venta.')
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                children: [
                  const EtiquetaDato('Orden de pago'),
                  const SizedBox(height: 6),
                  Titular(venta.numero, tamano: 26),
                  const SizedBox(height: 18),
                  TarjetaPanel(
                    hijo: Column(
                      children: [
                        FilaDato('Sucursal', venta.sucursal),
                        FilaDato('Subtotal', formatearPrecio(venta.subtotal)),
                        if (venta.descuento > 0)
                          FilaDato('Descuento', '- ${formatearPrecio(venta.descuento)}'),
                        if (venta.costoEnvio > 0)
                          FilaDato('Envio', formatearPrecio(venta.costoEnvio)),
                        FilaDato('IVA 13%', formatearPrecio(venta.iva)),
                        const Divider(height: 20),
                        FilaDato(
                          'Total a pagar',
                          '',
                          valorWidget: Text(
                            formatearPrecio(venta.total),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Paleta.flameOscuro,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (!esQr) ...[
                    const Text(
                      'Este pedido no se paga con QR. Volve al carrito para generar un nuevo '
                      'intento de pago.',
                      style: TextStyle(color: Paleta.inkSuave, height: 1.45),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => context.go('/carrito'),
                      child: const Text('VOLVER AL CARRITO'),
                    ),
                  ] else ...[
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.asset(
                          'assets/images/pago-qr.jpeg',
                          height: 220,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      yaInformado
                          ? 'Ya nos avisaste que pagaste. La sucursal esta verificando el deposito '
                              'y te notificamos cuando lo apruebe. Si te olvidaste de algo, podes '
                              'actualizar la referencia.'
                          : 'Escanea el QR desde la app de tu banco y paga el total exacto. Despues '
                              'toca "YA PAGUE": la sucursal verifica el deposito y confirma tu '
                              'pedido.',
                      style: const TextStyle(color: Paleta.inkSuave, height: 1.45),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _referencia,
                      maxLength: 200,
                      enabled: !_enviando,
                      decoration: const InputDecoration(
                        labelText: 'Referencia del deposito (opcional)',
                        hintText: 'Nro. de operacion o nombre del titular',
                      ),
                    ),
                    if (_errorInforme != null) ...[
                      const SizedBox(height: 6),
                      Text(_errorInforme!, style: const TextStyle(color: Paleta.rojo)),
                    ],
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _enviando ? null : _informarPago,
                      icon: _enviando
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Paleta.blanco,
                              ),
                            )
                          : const Icon(Icons.check),
                      label: Text(yaInformado ? 'ACTUALIZAR REFERENCIA' : 'YA PAGUE'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () => context.pushReplacement('/compra/${widget.ventaId}'),
                      child: const Text('VER ESTADO DEL PEDIDO'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
