import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../compartido/widgets.dart';
import '../core/config.dart';
import '../core/errores.dart';
import '../core/tema.dart';
import '../core/ventas/ventas_models.dart';
import '../core/ventas/ventas_service.dart';

/// CU06 con QR: no hay sandbox real, asi que esta pantalla hace de pasarela y
/// manda el resultado al webhook. El backend es idempotente por `evento_id`.
class PagoSimuladoPagina extends StatefulWidget {
  const PagoSimuladoPagina({super.key, required this.ventaId});

  final String ventaId;

  @override
  State<PagoSimuladoPagina> createState() => _PagoSimuladoPaginaState();
}

class _PagoSimuladoPaginaState extends State<PagoSimuladoPagina> {
  VentaOut? _venta;
  bool _cargando = true;
  bool _procesando = false;
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
      final venta = await ventasService.obtenerVenta(widget.ventaId);
      if (!mounted) return;
      // Si ya se resolvio (por ejemplo, se reintento el checkout), saltar a la confirmacion.
      if (venta.pago?.estado != 'PENDIENTE') {
        context.pushReplacement('/compra/${widget.ventaId}');
        return;
      }
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

  Future<void> _simularPago(String resultado) async {
    final pago = _venta?.pago;
    if (pago?.pasarela == null || pago?.idTransaccion == null) return;

    setState(() => _procesando = true);
    try {
      await pagosService.simularWebhook(pago!.pasarela!, pago.idTransaccion!, resultado);
      if (!mounted) return;
      context.pushReplacement('/compra/${widget.ventaId}');
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
      setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final venta = _venta;

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
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Paleta.gold.withValues(alpha: 0.12),
                      border: Border.all(color: Paleta.gold.withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Entorno de prueba: el QR no tiene sandbox disponible, asi que esta '
                      'pantalla simula la respuesta de la pasarela.',
                      style: TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 22),
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
                        if (venta.pago?.idTransaccion != null) ...[
                          const SizedBox(height: 6),
                          FilaDato('Transaccion', venta.pago!.idTransaccion!),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  ElevatedButton.icon(
                    onPressed: _procesando ? null : () => _simularPago('APROBADO'),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('SIMULAR PAGO APROBADO'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _procesando ? null : () => _simularPago('RECHAZADO'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Paleta.rojo,
                      side: const BorderSide(color: Paleta.rojo),
                    ),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('SIMULAR PAGO RECHAZADO'),
                  ),
                  if (_procesando) ...[
                    const SizedBox(height: 20),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
      ),
    );
  }
}
