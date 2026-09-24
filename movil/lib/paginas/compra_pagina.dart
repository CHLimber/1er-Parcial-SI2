import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../compartido/widgets.dart';
import '../core/carrito/carrito_service.dart';
import '../core/config.dart';
import '../core/envios/envios_models.dart';
import '../core/envios/envios_service.dart';
import '../core/errores.dart';
import '../core/tema.dart';
import '../core/ventas/ventas_models.dart';
import '../core/ventas/ventas_service.dart';
import 'mis_reservas_pagina.dart' show fechaLegible;

// CU20: el reparto lo hace un servicio de delivery externo, no hay un repartidor real en la
// demo marcando DESPACHADO/ENTREGADO. Simulamos ese avance en la app (sin tocar el backend)
// para poder mostrar la pantalla completa sin importar la pasarela usada -- mismo criterio que
// la web (pages/compra/compra.page.ts).
const _pasosEnvio = ['PENDIENTE', 'DESPACHADO', 'ENTREGADO'];
const _simulacionEnvio = <(int, String, String, Duration)>[
  (1, 'DESPACHADO', 'Retirado por el servicio de delivery (simulado)', Duration(milliseconds: 2000)),
  (2, 'ENTREGADO', 'Entrega confirmada por el servicio de delivery (simulado)', Duration(milliseconds: 4500)),
];

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
  EnvioOut? _envio;
  bool _cargando = true;
  bool _refrescando = false;
  String? _error;

  int _pasoSimulado = 0;
  List<EventoEnvio> _eventosSimulados = [];
  bool _simulacionIniciada = false;
  final List<Timer> _timers = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    super.dispose();
  }

  void _iniciarSimulacionSiCorresponde(EnvioOut? envio) {
    if (envio == null || _simulacionIniciada || envio.estado != 'PENDIENTE') return;
    _simulacionIniciada = true;
    for (final (paso, estado, nota, espera) in _simulacionEnvio) {
      _timers.add(Timer(espera, () {
        if (!mounted) return;
        setState(() {
          _pasoSimulado = paso;
          _eventosSimulados = [
            ..._eventosSimulados,
            EventoEnvio(estado: estado, nota: nota, fecha: DateTime.now()),
          ];
        });
      }));
    }
  }

  /// Estado real del envio, salvo que la simulacion ya lo haya adelantado.
  String _estadoEnvioMostrado() {
    final envio = _envio;
    if (envio == null) return 'PENDIENTE';
    final indiceReal = _pasosEnvio.indexOf(envio.estado);
    return _pasoSimulado > indiceReal ? _pasosEnvio[_pasoSimulado] : envio.estado;
  }

  List<EventoEnvio> _eventosEnvioMostrados() {
    final envio = _envio;
    if (envio == null) return [];
    return [...envio.eventos, ..._eventosSimulados];
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
      // CU20: el envio existe recien cuando el pago fue aprobado, asi que un 404 aca es
      // lo normal mientras la pasarela no confirmo.
      EnvioOut? envio;
      if (venta.entrega == 'DOMICILIO' && venta.estado != 'PENDIENTE') {
        try {
          envio = await enviosService.envioDeVenta(widget.ventaId);
        } catch (_) {
          envio = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _venta = venta;
        _envio = envio;
        _cargando = false;
        _refrescando = false;
      });
      _iniciarSimulacionSiCorresponde(envio);
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
                  Titular(_titulo(venta, estadoPago), tamano: 28),
                  const SizedBox(height: 8),
                  Text(
                    _explicacion(venta, estadoPago),
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
                  if (_envio != null) ...[
                    const EtiquetaDato('Tu envio'),
                    const SizedBox(height: 8),
                    _SeguimientoEnvio(
                      envio: _envio!,
                      estadoMostrado: _estadoEnvioMostrado(),
                      eventosMostrados: _eventosEnvioMostrados(),
                    ),
                    const SizedBox(height: 16),
                  ],
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
                          if (venta.costoEnvio > 0) _totalFila('Envio', venta.costoEnvio),
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
                      'El detalle de la venta se escribe cuando se confirma el pago.',
                      style: TextStyle(fontSize: 13, color: Paleta.inkSuave, height: 1.4),
                    ),
                  const SizedBox(height: 24),
                  if (pendiente &&
                      venta.pago?.pasarela == 'QR' &&
                      venta.pago?.informadoEn == null) ...[
                    ElevatedButton.icon(
                      onPressed: () => context.push('/pago-simulado/${venta.id}'),
                      icon: const Icon(Icons.qr_code_2),
                      label: const Text('PAGAR CON QR'),
                    ),
                    const SizedBox(height: 10),
                  ],
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

  /// 2.19.1.b/c: EFECTIVO y QR quedan PENDIENTE hasta que el cajero de la sucursal los verifica,
  /// asi que "esperando a la pasarela" solo aplica a Stripe.
  String _titulo(VentaOut venta, String estadoPago) {
    final pago = venta.pago;
    if (estadoPago == 'APROBADO') return 'Pago confirmado';
    if (estadoPago == 'PENDIENTE') {
      if (pago?.metodo == 'EFECTIVO') return 'Pendiente de cobro';
      if (pago?.pasarela == 'QR') {
        return pago?.informadoEn != null ? 'Pago en verificacion' : 'Esperando tu pago QR';
      }
      return 'Pago en proceso';
    }
    if (estadoPago == 'REEMBOLSADO') return 'Pedido anulado';
    return pago?.metodo == 'EFECTIVO' ? 'Pedido anulado' : 'Pago rechazado';
  }

  String _explicacion(VentaOut venta, String estadoPago) {
    final pago = venta.pago;
    switch (estadoPago) {
      case 'APROBADO':
        return venta.entrega == 'DOMICILIO'
            ? 'Tu pedido ${venta.numero} quedo registrado y sale a reparto desde ${venta.sucursal}.'
            : 'Tu pedido ${venta.numero} quedo registrado. Presenta este numero '
                'en ${venta.sucursal} para retirarlo.';
      case 'PENDIENTE':
        if (pago?.metodo == 'EFECTIVO') {
          return venta.entrega == 'DOMICILIO'
              ? 'Pagas ${formatearPrecio(venta.total)} en efectivo al recibir tu pedido. '
                  '${venta.sucursal} lo confirma cuando se registra el cobro.'
              : 'Acercate a ${venta.sucursal} y paga ${formatearPrecio(venta.total)} en caja. '
                  'Cuando el cajero registre el cobro te emitimos el comprobante.';
        }
        if (pago?.pasarela == 'QR') {
          return pago?.informadoEn != null
              ? 'Nos avisaste que pagaste el ${fechaLegible(pago!.informadoEn!)}. La sucursal '
                  'esta verificando el deposito; te notificamos cuando lo apruebe.'
              : 'Todavia no nos avisaste que pagaste este pedido.';
        }
        return 'Estamos esperando la confirmacion de la pasarela. Si ya pagaste, '
            'vuelve a consultar en unos segundos.';
      case 'REEMBOLSADO':
        return 'Hubo un problema al confirmar tu pedido y se genero un reembolso.';
      default:
        if (pago?.metodo == 'EFECTIVO') {
          return 'El pedido se anulo sin cobrarte nada: no se concreto el cobro en efectivo o '
              'el stock cambio. Tu carrito sigue disponible.';
        }
        if (pago?.pasarela == 'QR') {
          return 'La sucursal no pudo verificar tu deposito QR. Si ya pagaste, acercate con tu '
              'comprobante. Tu carrito sigue disponible.';
        }
        return 'La pasarela rechazo el pago. Puedes volver al carrito e '
            'intentarlo con otro medio.';
    }
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

/// CU20: en que anda el pedido a domicilio, con la bitacora que escribe tg_envio_historial.
class _SeguimientoEnvio extends StatelessWidget {
  const _SeguimientoEnvio({
    required this.envio,
    required this.estadoMostrado,
    required this.eventosMostrados,
  });

  final EnvioOut envio;
  final String estadoMostrado;
  final List<EventoEnvio> eventosMostrados;

  @override
  Widget build(BuildContext context) {
    final indice = _pasosEnvio.indexOf(estadoMostrado);
    final cerrado = envio.estado == 'FALLIDO' || envio.estado == 'CANCELADO';

    return TarjetaPanel(
      hijo: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  etiquetaEstadoEnvio(estadoMostrado),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              BadgeEstado(estadoMostrado),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            envio.referencia == null
                ? envio.direccion
                : '${envio.direccion} - ${envio.referencia}',
            style: const TextStyle(color: Paleta.inkSuave, fontSize: 13),
          ),
          if (!cerrado) ...[
            const SizedBox(height: 12),
            Row(
              children: List.generate(_pasosEnvio.length * 2 - 1, (posicion) {
                if (posicion.isOdd) {
                  final hecho = posicion ~/ 2 < indice;
                  return Expanded(
                    child: Container(
                      height: 2,
                      color: hecho ? Paleta.flame : Paleta.paperLinea,
                    ),
                  );
                }
                final paso = posicion ~/ 2;
                final hecho = paso <= indice;
                return Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hecho ? Paleta.flame : Paleta.blanco,
                    border: Border.all(color: hecho ? Paleta.flame : Paleta.paperLinea, width: 2),
                  ),
                );
              }),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            [
              '${envio.distanciaKm.toStringAsFixed(1)} km desde ${envio.sucursal}',
              'unos ${envio.duracionMin} min',
            ].join(' - '),
            style: const TextStyle(color: Paleta.inkSuave, fontSize: 12.5, height: 1.35),
          ),
          if (envio.observacion != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                envio.observacion!,
                style: const TextStyle(color: Paleta.inkSuave, fontSize: 12.5),
              ),
            ),
          const SizedBox(height: 10),
          ...eventosMostrados.map(
            (evento) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${etiquetaEstadoEnvio(evento.estado)} - ${fechaLegible(evento.fecha)}'
                '${evento.nota == null ? '' : ' - ${evento.nota}'}',
                style: const TextStyle(fontSize: 12, color: Paleta.inkSuave),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
