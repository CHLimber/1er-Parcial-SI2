import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../compartido/widgets.dart';
import '../core/carrito/carrito_service.dart';
import '../core/config.dart';
import '../core/errores.dart';
import '../core/tema.dart';
import '../core/ventas/ventas_models.dart';
import '../core/ventas/ventas_service.dart';
import 'mis_reservas_pagina.dart' show fechaLegible;

/// CU06: resultado de la compra. Mientras el pago sigue PENDIENTE (el webhook de Stripe
/// puede tardar unos segundos) la pantalla ofrece volver a consultar el estado.
class CompraPagina extends StatefulWidget {
  const CompraPagina({super.key, required this.ventaId});

  final String ventaId;

  @override
  State<CompraPagina> createState() => _CompraPaginaState();
}

class _CompraPaginaState extends State<CompraPagina> {
  VentaOut? _venta;
  bool _cargando = true;
  bool _refrescando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar({bool esRefresco = false}) async {
    setState(() {
      if (esRefresco) {
        _refrescando = true;
      } else {
        _cargando = true;
        _error = null;
      }
    });
    try {
      final venta = await ventasService.obtenerVenta(widget.ventaId);
      if (!mounted) return;
      setState(() {
        _venta = venta;
        _cargando = false;
        _refrescando = false;
      });
      // el carrito quedo consumido por el checkout
      await context.read<CarritoService>().refrescar();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = interpretarError(error);
        _cargando = false;
        _refrescando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final venta = _venta;
    final estadoPago = venta?.pago?.estado ?? 'PENDIENTE';
    final aprobado = estadoPago == 'APROBADO';
    final pendiente = estadoPago == 'PENDIENTE';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tu compra'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/tienda'),
        ),
      ),
      body: VistaAsincrona(
        cargando: _cargando,
        error: _error,
        alReintentar: _cargar,
        hijo: venta == null
            ? const EstadoVacio(mensaje: 'No se encontro la venta.')
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                children: [
                  Icon(
                    aprobado
                        ? Icons.check_circle
                        : pendiente
                            ? Icons.hourglass_top
                            : Icons.cancel,
                    size: 56,
                    color: aprobado
                        ? Paleta.verde
                        : pendiente
                            ? Paleta.gold
                            : Paleta.rojo,
                  ),
                  const SizedBox(height: 14),
                  Titular(
                    aprobado
                        ? 'Pago confirmado'
                        : pendiente
                            ? 'Pago en proceso'
                            : 'Pago rechazado',
                    tamano: 28,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    aprobado
                        ? 'Tu pedido ${venta.numero} quedo registrado. Presenta este numero '
                            'en ${venta.sucursal} para retirarlo.'
                        : pendiente
                            ? 'Estamos esperando la confirmacion de la pasarela. Si ya pagaste, '
                                'vuelve a consultar en unos segundos.'
                            : 'La pasarela rechazo el pago. Puedes volver al carrito e '
                                'intentarlo con otro medio.',
                    style: const TextStyle(color: Paleta.inkSuave, height: 1.45),
                  ),
                  const SizedBox(height: 22),
                  TarjetaPanel(
                    hijo: Column(
                      children: [
                        FilaDato('Pedido', venta.numero),
                        FilaDato('Estado', '', valorWidget: BadgeEstado(venta.estado)),
                        FilaDato('Pago', '', valorWidget: BadgeEstado(estadoPago)),
                        FilaDato('Canal', venta.canal),
                        FilaDato('Entrega', venta.entrega.replaceAll('_', ' ')),
                        FilaDato('Sucursal', venta.sucursal),
                        if (venta.fecha != null) FilaDato('Fecha', fechaLegible(venta.fecha!)),
                        if (venta.comprobante != null)
                          FilaDato('Comprobante', venta.comprobante!.numero),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (venta.items.isNotEmpty) ...[
                    const EtiquetaDato('Detalle'),
                    const SizedBox(height: 8),
                    TarjetaPanel(
                      hijo: Column(
                        children: [
                          ...venta.items.map(
                            (item) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${item.cantidad} x ${item.producto}\n'
                                      '${item.talla} · ${item.color}',
                                      style: const TextStyle(fontSize: 13, height: 1.35),
                                    ),
                                  ),
                                  Text(
                                    formatearPrecio(item.subtotal),
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(height: 20),
                          _totalFila('Subtotal', venta.subtotal),
                          if (venta.descuento > 0) _totalFila('Descuento', -venta.descuento),
                          _totalFila('IVA 13%', venta.iva),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
                              Text(
                                formatearPrecio(venta.total),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Paleta.flameOscuro,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ] else
                    const Text(
                      'El detalle de la venta se escribe cuando la pasarela confirma el pago.',
                      style: TextStyle(fontSize: 13, color: Paleta.inkSuave, height: 1.4),
                    ),
                  const SizedBox(height: 24),
                  if (pendiente)
                    ElevatedButton.icon(
                      onPressed: _refrescando ? null : () => _cargar(esRefresco: true),
                      icon: _refrescando
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Paleta.blanco,
                              ),
                            )
                          : const Icon(Icons.refresh),
                      label: const Text('CONSULTAR ESTADO DEL PAGO'),
                    ),
                  if (!pendiente && !aprobado)
                    ElevatedButton(
                      onPressed: () => context.go('/carrito'),
                      child: const Text('VOLVER AL CARRITO'),
                    ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => context.go('/tienda'),
                    child: const Text('SEGUIR COMPRANDO'),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _totalFila(String etiqueta, double monto) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(etiqueta, style: const TextStyle(color: Paleta.inkSuave, fontSize: 13)),
            Text(formatearPrecio(monto), style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
}
