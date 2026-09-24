import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

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
      // el monto del carrito cambio: si el envio a domicilio dependia de superar el umbral
      // de envio gratis, hay que recotizar (mismo criterio que carrito.page.ts en la web).
      _cotizarEnvio();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    }
  }

  /// IVA 13% fijo (ver CLAUDE.md): no es parametrizable, se puede reflejar en la app sin
  /// pedirselo al backend. Solo para mostrar -- lo que se cobra siempre lo calcula el
  /// backend en /ventas/checkout, con esta misma formula (espejo de carrito.page.ts).
  static const double _ivaTasa = 0.13;

  double _redondear(double monto) => (monto * 100).round() / 100;

  /// Tarifa del delivery, tal cual la cotizo fn_cotizar_envio(): el flete no lleva IVA. 0 si
  /// se retira en tienda o si el envio salio gratis.
  double _costoEnvio() => _cotizacion?.costo ?? 0;

  /// Lo que se cobra de verdad: 13% de IVA solo sobre las prendas, mas el envio sin impuesto.
  double _totalConIva(double subtotal) => _redondear(subtotal * (1 + _ivaTasa) + _costoEnvio());

  double _prendasConIva(double subtotal) => _redondear(subtotal * (1 + _ivaTasa));

  /// Lo que se ve debajo del selector de metodo de pago, segun cual este elegido -- espejo del
  /// `@switch (metodoPago)` de carrito.page.html: QR muestra la imagen fija (sin pedirsela a
  /// ningun servicio), Efectivo explica cuando se cobra y Stripe aclara que se abre el navegador
  /// (la web lo muestra inline con un iframe; la app movil sigue con el Checkout hospedado).
  Widget _contenidoMetodoPago() {
    switch (_metodoPago) {
      case 'QR':
        return Column(
          key: const ValueKey('qr'),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                'assets/images/pago-qr.jpeg',
                height: 190,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Tocá "Pagar con QR" para generar tu pedido, escaneá el código desde tu app bancaria '
              'y avisanos que pagaste. La sucursal verifica el depósito y recién ahí confirma tu '
              'compra.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Paleta.inkSuave, height: 1.35),
            ),
          ],
        );
      case 'EFECTIVO':
        final cuando = _entrega == 'DOMICILIO'
            ? 'Pagás en efectivo cuando te entreguen el pedido.'
            : 'Pagás en efectivo al retirar el pedido en la sucursal.';
        return Row(
          key: const ValueKey('efectivo'),
          children: [
            const Icon(Icons.info_outline, size: 18, color: Paleta.inkSuave),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$cuando Tu pedido queda pendiente de cobro: el cajero lo confirma cuando registra el '
                'pago, y recién ahí se emite el comprobante.',
                style: const TextStyle(fontSize: 13, color: Paleta.inkSuave, height: 1.4),
              ),
            ),
          ],
        );
      default: // STRIPE
        return const Row(
          key: ValueKey('stripe'),
          children: [
            Icon(Icons.credit_card, size: 18, color: Paleta.inkSuave),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Se abre un formulario seguro de Stripe para ingresar tu tarjeta, sin salir de '
                'la app.',
                style: TextStyle(fontSize: 13, color: Paleta.inkSuave, height: 1.4),
              ),
            ),
          ],
        );
    }
  }

  String get _textoBotonPago => switch (_metodoPago) {
        'QR' => 'PAGAR CON QR',
        'EFECTIVO' => 'CONFIRMAR PEDIDO EN EFECTIVO',
        _ => 'PAGAR CON TARJETA',
      };

  IconData get _iconoBotonPago => switch (_metodoPago) {
        'QR' => Icons.qr_code_2,
        'EFECTIVO' => Icons.payments_outlined,
        _ => Icons.credit_card,
      };

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
      if (_metodoPago == 'STRIPE') {
        // La publishable key se pide una sola vez (perezoso) y se cachea en ventas_service.dart.
        await asegurarStripeInicializado();
      }

      final checkout = await ventasService.checkout(
        sucursalId: desdeReserva ? null : _sucursalId,
        entrega: entrega,
        direccionId: entrega == 'DOMICILIO' ? _direccionId : null,
        metodoPago: _metodoPago,
        codigoCupon: _cupon.text.trim(),
      );
      if (!mounted) return;

      if (checkout.pasarela == 'STRIPE') {
        final clientSecret = checkout.clientSecret;
        if (clientSecret == null) {
          // Cruce de canal muy improbable: el mismo carrito ya tenia un checkout STRIPE
          // pendiente iniciado desde la web (Checkout Session, no PaymentIntent), asi que este
          // dispositivo no tiene con que mostrar el PaymentSheet. Ver PENDIENTES.txt 2.14.
          setState(
            () => _errorCheckout = 'No se pudo continuar este pago desde el celular. Volve a '
                'intentarlo.',
          );
          return;
        }
        // CU06: el PaymentSheet nativo de flutter_stripe se muestra DENTRO de la app, nunca se
        // abre el navegador. Si el cliente lo cierra sin pagar, la venta y el pago quedan
        // PENDIENTE (igual que si cerrara una pestana de checkout hospedado) y el proximo
        // intento con los mismos datos reutiliza este mismo PaymentIntent (iniciar_checkout).
        final pagoConfirmado = await _mostrarPaymentSheet(clientSecret);
        if (!mounted) return;
        if (!pagoConfirmado) return; // cancelado o rechazado: se queda en el carrito
        context.read<CarritoService>().reiniciar();
        context.push('/compra/${checkout.ventaId}');
        return;
      }

      context.read<CarritoService>().reiniciar();
      if (checkout.esPagoSimulado) {
        // QR: la pantalla muestra el codigo y la clienta informa que pago (2.19.1.c).
        context.push('/pago-simulado/${checkout.ventaId}');
      } else {
        // EFECTIVO: queda pendiente de cobro hasta que el cajero lo apruebe (2.19.1.b).
        context.push('/compra/${checkout.ventaId}');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorCheckout = interpretarError(error));
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  /// Muestra el formulario de tarjeta nativo de Stripe (PaymentSheet) sin salir de la app.
  /// Devuelve true si Stripe confirmo el pago (la confirmacion definitiva del pedido sigue
  /// llegando por el webhook firmado); false si el cliente cancelo o el pago fue rechazado.
  Future<bool> _mostrarPaymentSheet(String clientSecret) async {
    try {
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'FashionStore',
          appearance: PaymentSheetAppearance(
            colors: PaymentSheetAppearanceColors(primary: Paleta.flame),
          ),
        ),
      );
      await Stripe.instance.presentPaymentSheet();
      return true;
    } on StripeException catch (error) {
      if (error.error.code == FailureCode.Canceled) return false;
      if (mounted) {
        mostrarAviso(
          context,
          error.error.localizedMessage ?? error.error.message ?? 'No se pudo procesar el pago.',
          esError: true,
        );
      }
      return false;
    } catch (_) {
      if (mounted) mostrarAviso(context, 'No se pudo procesar el pago con Stripe.', esError: true);
      return false;
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
                  if (carrito.reservaId != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Paleta.gold.withValues(alpha: 0.12),
                        border: Border.all(color: Paleta.gold.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.local_offer_outlined, color: Paleta.gold, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Esta compra viene de tu reserva ${carrito.reservaCodigo ?? ""}. '
                              'Se despacha desde la misma sucursal donde comprometiste el stock.',
                              style: const TextStyle(fontSize: 13, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  const EtiquetaDato('Tus prendas'),
                  const SizedBox(height: 10),
                  ...carrito.items.map(_filaItem),
                  const SizedBox(height: 22),
                  if (carrito.reservaId == null) ...[
                    const EtiquetaDato('Entrega'),
                    const SizedBox(height: 10),
                    TarjetaPanel(
                      hijo: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Sucursal de despacho', style: TextStyle(fontWeight: FontWeight.w700)),
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
                          const Text('Como lo queres recibir', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _OpcionPasarela(
                                  icono: Icons.storefront_outlined,
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
                                  icono: Icons.local_shipping_outlined,
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
                              Material(
                                color: Paleta.flame.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () async {
                                    await context.push('/mis-direcciones');
                                    if (mounted) _cargar();
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        Icon(Icons.add_location_alt_outlined, color: Paleta.flame),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            'Todavia no tenes direcciones guardadas. Agrega una '
                                            'para que te llevemos el pedido.',
                                            style: TextStyle(fontSize: 13, height: 1.35),
                                          ),
                                        ),
                                        Icon(Icons.chevron_right, color: Paleta.flame),
                                      ],
                                    ),
                                  ),
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
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'Calculando la tarifa del envio...',
                                      style: TextStyle(color: Paleta.inkSuave, fontSize: 13),
                                    ),
                                  ],
                                ),
                              )
                            else if (_cotizacion != null)
                              _ResumenEnvio(cotizacion: _cotizacion!),
                            if (_errorEnvio != null) ...[
                              const SizedBox(height: 10),
                              MensajeError(_errorEnvio!),
                            ],
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],
                  const EtiquetaDato('Resumen'),
                  const SizedBox(height: 10),
                  // Un solo lugar con los importes, siempre con IVA incluido, para que lo que se
                  // ve aca sea exactamente lo que cobra la pasarela (espejo de carrito.page.html).
                  TarjetaPanel(
                    padding: const EdgeInsets.all(14),
                    hijo: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_entrega == 'DOMICILIO' && _cotizacion != null) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Prendas (IVA incluido)', style: TextStyle(color: Paleta.inkSuave)),
                              Text(formatearPrecio(_prendasConIva(carrito.subtotal))),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Delivery', style: TextStyle(color: Paleta.inkSuave)),
                              Text(formatearPrecio(_costoEnvio())),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Divider(height: 1),
                          const SizedBox(height: 10),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total a pagar', style: TextStyle(fontWeight: FontWeight.w700)),
                            Text(
                              formatearPrecio(_totalConIva(carrito.subtotal)),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 19,
                                color: Paleta.flameOscuro,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const EtiquetaDato('Forma de pago'),
                  const SizedBox(height: 10),
                  TarjetaPanel(
                    hijo: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _OpcionPasarela(
                                icono: Icons.credit_card_outlined,
                                nombre: 'Stripe',
                                detalle: 'Tarjeta de credito o debito',
                                elegida: _metodoPago == 'STRIPE',
                                alElegir: () => setState(() => _metodoPago = 'STRIPE'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _OpcionPasarela(
                                icono: Icons.qr_code_2_outlined,
                                nombre: 'QR',
                                detalle: 'QR y banca en linea',
                                elegida: _metodoPago == 'QR',
                                alElegir: () => setState(() => _metodoPago = 'QR'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _OpcionPasarela(
                                icono: Icons.payments_outlined,
                                nombre: 'Efectivo',
                                detalle: _entrega == 'DOMICILIO'
                                    ? 'Pagas al recibir el pedido'
                                    : 'Pagas al retirar en tienda',
                                elegida: _metodoPago == 'EFECTIVO',
                                alElegir: () => setState(() => _metodoPago = 'EFECTIVO'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: KeyedSubtree(
                            key: ValueKey(_metodoPago),
                            child: _contenidoMetodoPago(),
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _cupon,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Cupon (opcional)',
                            hintText: 'BIENVENIDA10',
                            prefixIcon: Icon(Icons.sell_outlined, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_errorCheckout != null) ...[
                    MensajeError(_errorCheckout!),
                    const SizedBox(height: 14),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _procesando ? null : _pagar,
                      icon: _procesando
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Paleta.blanco),
                            )
                          : Icon(_iconoBotonPago),
                      label: Text(_procesando ? 'Procesando...' : _textoBotonPago),
                    ),
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
    required this.icono,
    required this.nombre,
    required this.detalle,
    required this.elegida,
    required this.alElegir,
  });

  final IconData icono;
  final String nombre;
  final String detalle;
  final bool elegida;
  final VoidCallback alElegir;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: alElegir,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
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
              Icon(icono, size: 19, color: elegida ? Paleta.flame : Paleta.inkSuave),
              const SizedBox(height: 8),
              Text(nombre, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
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
/// (fn_cotizar_envio en db/02_logica.sql) para que la clienta entienda el precio. El total
/// final (con IVA) se muestra aparte, en el resumen de pago (espejo del bloque "envio" de
/// carrito.page.html en la web, que tampoco repite el total ahi). Sin borde propio: ya vive
/// adentro de la tarjeta "Entrega", un segundo borde se veria como una caja dentro de otra.
class _ResumenEnvio extends StatelessWidget {
  const _ResumenEnvio({required this.cotizacion});

  final CotizacionEnvio cotizacion;

  @override
  Widget build(BuildContext context) {
    final color = cotizacion.esGratis ? Paleta.verde : Paleta.ink;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (cotizacion.esGratis ? Paleta.verde : Paleta.gold).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            cotizacion.esGratis ? Icons.celebration_outlined : Icons.local_shipping_outlined,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cotizacion.esGratis
                      ? 'Envio gratis'
                      : 'Envio: ${formatearPrecio(cotizacion.costo)}',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
