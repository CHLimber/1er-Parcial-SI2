import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../compartido/widgets.dart';
import '../core/carrito/carrito_service.dart';
import '../core/config.dart';
import '../core/errores.dart';
import '../core/sucursales/sucursales_models.dart';
import '../core/sucursales/sucursales_service.dart';
import '../core/tema.dart';
import '../core/ventas/ventas_service.dart';
import 'tienda_pagina.dart';

/// CU05: Comprar por Web/App. El checkout deja la venta y el pago en PENDIENTE; el
/// detalle de la venta (y el descuento de stock) se escribe recien cuando el webhook
/// confirma el pago (CU06).
class CarritoPagina extends StatefulWidget {
  const CarritoPagina({super.key});

  @override
  State<CarritoPagina> createState() => _CarritoPaginaState();
}

class _CarritoPaginaState extends State<CarritoPagina> {
  final _cupon = TextEditingController();

  CarritoOut? _carrito;
  List<SucursalOut> _sucursales = [];
  String? _sucursalId;
  String _pasarela = 'STRIPE';

  bool _cargando = true;
  bool _procesando = false;
  String? _error;
  String? _errorCheckout;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _cupon.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final carrito = await context.read<CarritoService>().verCarrito();
      final sucursales = _sucursales.isEmpty ? await sucursalesService.listar() : _sucursales;
      if (!mounted) return;
      setState(() {
        _carrito = carrito;
        _sucursales = sucursales;
        _sucursalId ??= sucursales.isEmpty ? null : sucursales.first.id;
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

  Future<void> _cambiarCantidad(CarritoItemOut item, int cantidad) async {
    try {
      final carrito = cantidad <= 0
          ? await context.read<CarritoService>().quitarItem(item.id)
          : await context.read<CarritoService>().actualizarCantidad(item.id, cantidad);
      if (!mounted) return;
      setState(() => _carrito = carrito);
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  Future<void> _pagar() async {
    final carrito = _carrito;
    if (carrito == null || carrito.items.isEmpty) return;

    // Si el carrito nacio de una reserva, la sucursal ya quedo fijada por el compromiso.
    final desdeReserva = carrito.reservaId != null;
    if (!desdeReserva && (_sucursalId == null || _sucursalId!.isEmpty)) {
      setState(() => _errorCheckout = 'Elige la sucursal desde la que se despacha tu pedido.');
      return;
    }

    setState(() {
      _procesando = true;
      _errorCheckout = null;
    });

    try {
      final checkout = await ventasService.checkout(
        sucursalId: desdeReserva ? null : _sucursalId,
        pasarela: _pasarela,
        codigoCupon: _cupon.text.trim(),
      );
      if (!mounted) return;
      context.read<CarritoService>().reiniciar();

      if (checkout.esUrlExterna) {
        // Stripe: la pagina de pago la aloja la pasarela, se abre en el navegador.
        final abierto = await launchUrl(
          Uri.parse(checkout.urlPago),
          mode: LaunchMode.externalApplication,
        );
        if (!mounted) return;
        if (!abierto) {
          mostrarAviso(context, 'No se pudo abrir la pagina de Stripe.', esError: true);
        }
        context.push('/compra/${checkout.ventaId}');
      } else {
        // LIBELULA no tiene sandbox: se resuelve con la pantalla de pago simulado.
        context.push('/pago-simulado/${checkout.ventaId}');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorCheckout = interpretarError(error));
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final carrito = _carrito;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Carrito'),
        actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: VistaAsincrona(
        cargando: _cargando,
        error: _error,
        alReintentar: _cargar,
        hijo: (carrito == null || carrito.items.isEmpty)
            ? EstadoVacio(
                mensaje: 'Tu carrito esta vacio.',
                icono: Icons.shopping_bag_outlined,
                accion: ElevatedButton(
                  onPressed: () => context.go('/tienda'),
                  child: const Text('VER CATALOGO'),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  if (carrito.reservaId != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Paleta.gold.withValues(alpha: 0.12),
                        border: Border.all(color: Paleta.gold.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Esta compra viene de tu reserva ${carrito.reservaCodigo ?? ""}. '
                        'Se despacha desde la misma sucursal donde comprometiste el stock.',
                        style: const TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                  ...carrito.items.map(_filaItem),
                  const SizedBox(height: 10),
                  const Divider(),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Subtotal', style: TextStyle(color: Paleta.inkSuave)),
                      Text(
                        formatearPrecio(carrito.subtotal),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'El IVA (13%) se calcula al confirmar el pago.',
                    style: TextStyle(fontSize: 12, color: Paleta.inkSuave),
                  ),
                  const SizedBox(height: 24),
                  if (carrito.reservaId == null) ...[
                    const EtiquetaDato('Sucursal de despacho'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _sucursalId,
                      isExpanded: true,
                      items: _sucursales
                          .map(
                            (sucursal) => DropdownMenuItem(
                              value: sucursal.id,
                              child: Text(
                                '${sucursal.nombre} · ${sucursal.ciudad}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (valor) => setState(() => _sucursalId = valor),
                    ),
                    const SizedBox(height: 20),
                  ],
                  const EtiquetaDato('Forma de pago'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _OpcionPasarela(
                          nombre: 'Stripe',
                          detalle: 'Tarjeta de credito o debito',
                          elegida: _pasarela == 'STRIPE',
                          alElegir: () => setState(() => _pasarela = 'STRIPE'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _OpcionPasarela(
                          nombre: 'Libelula',
                          detalle: 'QR y banca en linea (simulado)',
                          elegida: _pasarela == 'LIBELULA',
                          alElegir: () => setState(() => _pasarela = 'LIBELULA'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _cupon,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Cupon (opcional)',
                      hintText: 'BIENVENIDA10',
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_errorCheckout != null) ...[
                    MensajeError(_errorCheckout!),
                    const SizedBox(height: 14),
                  ],
                  ElevatedButton(
                    onPressed: _procesando ? null : _pagar,
                    child: _procesando
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Paleta.blanco),
                          )
                        : Text('PAGAR CON ${_pasarela == "STRIPE" ? "STRIPE" : "LIBELULA"}'),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _filaItem(CarritoItemOut item) => Padding(
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
                      '${formatearPrecio(item.precioUnitario)}  ·  '
                      'Subtotal ${formatearPrecio(item.subtotal)}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
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
                        onPressed: () => _cambiarCantidad(item, item.cantidad - 1),
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                      ),
                      Text('${item.cantidad}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: item.cantidad >= 20
                            ? null
                            : () => _cambiarCantidad(item, item.cantidad + 1),
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => _cambiarCantidad(item, 0),
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

class _OpcionPasarela extends StatelessWidget {
  const _OpcionPasarela({
    required this.nombre,
    required this.detalle,
    required this.elegida,
    required this.alElegir,
  });

  final String nombre;
  final String detalle;
  final bool elegida;
  final VoidCallback alElegir;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: alElegir,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: elegida ? Paleta.flame.withValues(alpha: 0.1) : Paleta.blanco,
            border: Border.all(
              color: elegida ? Paleta.flame : Paleta.paperLinea,
              width: elegida ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nombre, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                detalle,
                style: const TextStyle(fontSize: 11.5, color: Paleta.inkSuave, height: 1.3),
              ),
            ],
          ),
        ),
      );
}
