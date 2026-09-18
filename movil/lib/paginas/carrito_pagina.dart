import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../compartido/widgets.dart';
import '../core/carrito/carrito_service.dart';
import '../core/config.dart';
import '../core/direcciones/direcciones_models.dart';
import '../core/direcciones/direcciones_service.dart';
import '../core/envios/envios_models.dart';
import '../core/envios/envios_service.dart';
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
  String _metodoPago = 'STRIPE';

  // CU20 - entrega a domicilio
  List<DireccionOut> _direcciones = const [];
  String _entrega = 'RETIRO_SUCURSAL';
  String? _direccionId;
  CotizacionEnvio? _cotizacion;
  bool _cotizando = false;
  String? _errorEnvio;

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
      // la libreta puede estar vacia (clienta recien registrada) y eso no rompe el carrito
      var direcciones = _direcciones;
      if (direcciones.isEmpty) {
        try {
          direcciones = await direccionesService.listar();
        } catch (_) {
          direcciones = const [];
        }
      }
      if (!mounted) return;
      setState(() {
        _carrito = carrito;
        _sucursales = sucursales;
        _sucursalId ??= sucursales.isEmpty ? null : sucursales.first.id;
        _direcciones = direcciones;
        _direccionId ??= _direccionPorDefecto(direcciones);
        _cargando = false;
      });
      _cotizarEnvio();
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

  String? _direccionPorDefecto(List<DireccionOut> direcciones) {
    if (direcciones.isEmpty) return null;
    for (final direccion in direcciones) {
      if (direccion.esPrincipal) return direccion.id;
    }
    return direcciones.first.id;
  }

  /// CU20: la tarifa depende de la sucursal, de la direccion y del monto del carrito (de ese
  /// monto sale el envio gratis). Es informativa: el backend vuelve a cotizar antes de cobrar.
  Future<void> _cotizarEnvio() async {
    final carrito = _carrito;
    if (_entrega != 'DOMICILIO' || carrito == null || _sucursalId == null || _direccionId == null) {
      if (mounted) setState(() => _cotizacion = null);
      return;
    }

    setState(() {
      _cotizando = true;
      _errorEnvio = null;
    });
    try {
      final cotizacion = await enviosService.cotizar(
        sucursalId: _sucursalId!,
        direccionId: _direccionId,
        montoPedido: carrito.subtotal,
      );
      if (!mounted) return;
      setState(() {
        _cotizacion = cotizacion;
        _cotizando = false;
        _errorEnvio = cotizacion.dentroCobertura
            ? null
            : 'Tu direccion queda a ${cotizacion.distanciaKm.toStringAsFixed(1)} km y esta '
                'sucursal reparte hasta ${cotizacion.radioKm.toStringAsFixed(0)} km. '
                'Proba con otra sucursal o retira en tienda.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cotizacion = null;
        _cotizando = false;
        _errorEnvio = interpretarError(error);
      });
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

    // una compra nacida de una reserva se retira si o si donde se comprometio el stock
    final entrega = desdeReserva ? 'RETIRO_SUCURSAL' : _entrega;
    if (entrega == 'DOMICILIO' && _direccionId == null) {
      setState(() => _errorCheckout = 'Elegi la direccion a la que llevamos tu pedido.');
      return;
    }

    setState(() {
      _procesando = true;
      _errorCheckout = null;
    });

    try {
      final checkout = await ventasService.checkout(
        sucursalId: desdeReserva ? null : _sucursalId,
        entrega: entrega,
        direccionId: entrega == 'DOMICILIO' ? _direccionId : null,
        metodoPago: _metodoPago,
        codigoCupon: _cupon.text.trim(),
      );
      if (!mounted) return;
      context.read<CarritoService>().reiniciar();

      if (checkout.esUrlExterna) {
        // Stripe: la pagina de pago la aloja la pasarela, se abre en el navegador.
        final abierto = await launchUrl(
          Uri.parse(checkout.urlPago!),
          mode: LaunchMode.externalApplication,
        );
        if (!mounted) return;
        if (!abierto) {
          mostrarAviso(context, 'No se pudo abrir la pagina de Stripe.', esError: true);
        }
        context.push('/compra/${checkout.ventaId}');
      } else if (checkout.esPagoSimulado) {
        // QR no tiene sandbox: se resuelve con la pantalla de pago simulado.
        context.push('/pago-simulado/${checkout.ventaId}');
      } else {
        // EFECTIVO: ya quedo pagada al toque, directo a la confirmacion.
        context.push('/compra/${checkout.ventaId}');
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
                      onChanged: (valor) {
                        setState(() => _sucursalId = valor);
                        _cotizarEnvio();
                      },
                    ),
                    const SizedBox(height: 20),
                    const EtiquetaDato('Como lo queres recibir'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _OpcionPasarela(
                            nombre: 'Retiro en tienda',
                            detalle: 'Lo buscas por la sucursal',
                            elegida: _entrega == 'RETIRO_SUCURSAL',
                            alElegir: () {
                              setState(() => _entrega = 'RETIRO_SUCURSAL');
                              _cotizarEnvio();
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _OpcionPasarela(
                            nombre: 'A domicilio',
                            detalle: 'Te lo llevamos a casa',
                            elegida: _entrega == 'DOMICILIO',
                            alElegir: () {
                              setState(() => _entrega = 'DOMICILIO');
                              _cotizarEnvio();
                            },
                          ),
                        ),
                      ],
                    ),
                    if (_entrega == 'DOMICILIO') ...[
                      const SizedBox(height: 16),
                      if (_direcciones.isEmpty)
                        TarjetaPanel(
                          alTocar: () async {
                            await context.push('/mis-direcciones');
                            if (mounted) _cargar();
                          },
                          hijo: const Row(
                            children: [
                              Icon(Icons.add_location_alt_outlined, color: Paleta.flame),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Todavia no tenes direcciones guardadas. Agrega una para que '
                                  'te llevemos el pedido.',
                                  style: TextStyle(fontSize: 13, height: 1.35),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        DropdownButtonFormField<String>(
                          initialValue: _direccionId,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Direccion de entrega'),
                          items: _direcciones
                              .map(
                                (direccion) => DropdownMenuItem(
                                  value: direccion.id,
                                  child: Text(
                                    '${direccion.alias} - ${direccion.direccion}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (valor) {
                            setState(() => _direccionId = valor);
                            _cotizarEnvio();
                          },
                        ),
                      const SizedBox(height: 12),
                      if (_cotizando)
                        const Text(
                          'Calculando la tarifa del envio...',
                          style: TextStyle(color: Paleta.inkSuave, fontSize: 13),
                        )
                      else if (_cotizacion != null)
                        _ResumenEnvio(cotizacion: _cotizacion!, subtotal: carrito.subtotal),
                      if (_errorEnvio != null) ...[
                        const SizedBox(height: 10),
                        MensajeError(_errorEnvio!),
                      ],
                    ],
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
                          elegida: _metodoPago == 'STRIPE',
                          alElegir: () => setState(() => _metodoPago = 'STRIPE'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _OpcionPasarela(
                          nombre: 'QR',
                          detalle: 'QR y banca en linea (simulado)',
                          elegida: _metodoPago == 'QR',
                          alElegir: () => setState(() => _metodoPago = 'QR'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _OpcionPasarela(
                          nombre: 'Efectivo',
                          detalle: _entrega == 'DOMICILIO'
                              ? 'Le pagas al repartidor'
                              : 'Pagas al retirar en tienda',
                          elegida: _metodoPago == 'EFECTIVO',
                          alElegir: () => setState(() => _metodoPago = 'EFECTIVO'),
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
                        : Text('PAGAR CON ${_metodoPago == "STRIPE" ? "STRIPE" : _metodoPago == "QR" ? "QR" : "EFECTIVO"}'),
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

/// CU20: que se cobra por el envio y por que. Muestra los parametros de la tarifa
/// (fn_cotizar_envio en db/02_logica.sql) para que la clienta entienda el precio.
class _ResumenEnvio extends StatelessWidget {
  const _ResumenEnvio({required this.cotizacion, required this.subtotal});

  final CotizacionEnvio cotizacion;
  final double subtotal;

  @override
  Widget build(BuildContext context) {
    final total = subtotal + cotizacion.costo;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Paleta.blanco,
        border: Border.all(color: Paleta.paperLinea),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cotizacion.esGratis
                ? 'Envio gratis'
                : 'Envio: ${formatearPrecio(cotizacion.costo)}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            cotizacion.esGratis
                ? 'Tu compra supera los ${formatearPrecio(cotizacion.gratisDesde)}, '
                    'asi que el delivery corre por nuestra cuenta.'
                : '${cotizacion.distanciaKm.toStringAsFixed(1)} km desde la sucursal · '
                    'llega en unos ${cotizacion.duracionMin} min · '
                    '${formatearPrecio(cotizacion.tarifaBase)} de base + '
                    '${formatearPrecio(cotizacion.precioKm)} por km',
            style: const TextStyle(fontSize: 12, color: Paleta.inkSuave, height: 1.35),
          ),
          const SizedBox(height: 8),
          Text(
            'Total sin IVA: ${formatearPrecio(total)}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}
