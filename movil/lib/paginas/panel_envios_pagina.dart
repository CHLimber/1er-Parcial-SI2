import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../compartido/widgets.dart';
import '../core/config.dart';
import '../core/envios/envios_models.dart';
import '../core/envios/envios_service.dart';
import '../core/errores.dart';
import '../core/tema.dart';

/// CU20 - panel de despacho en el telefono. El reparto lo hace un servicio de delivery
/// externo, no personal de FashionStore: un ENCARGADO/ADMIN solo marca cuando el paquete
/// sale hacia ese servicio y cuando se confirma la entrega (o la falla).
class PanelEnviosPagina extends StatefulWidget {
  const PanelEnviosPagina({super.key});

  @override
  State<PanelEnviosPagina> createState() => _PanelEnviosPaginaState();
}

class _PanelEnviosPaginaState extends State<PanelEnviosPagina> {
  List<EnvioAdminOut> _envios = const [];
  ResumenEnvios? _resumen;
  bool _cargando = true;
  bool _soloAbiertos = true;
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
      final envios = await enviosService.listar(soloAbiertos: _soloAbiertos);
      ResumenEnvios? resumen;
      try {
        resumen = await enviosService.resumen();
      } catch (_) {
        resumen = null;
      }
      if (!mounted) return;
      setState(() {
        _envios = envios;
        _resumen = resumen;
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

  Future<void> _abrir(EnvioAdminOut envio) async {
    final cambio = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _DetalleEnvioPagina(envioId: envio.id)),
    );
    if (cambio == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Envios'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: VistaAsincrona(
        cargando: _cargando,
        error: _error,
        alReintentar: _cargar,
        hijo: RefreshIndicator(
          onRefresh: _cargar,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              if (_resumen != null) _Contadores(resumen: _resumen!),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _soloAbiertos,
                onChanged: (valor) {
                  setState(() => _soloAbiertos = valor);
                  _cargar();
                },
                title: const Text('Solo los que siguen abiertos'),
              ),
              const SizedBox(height: 6),
              if (_envios.isEmpty)
                const EstadoVacio(
                  icono: Icons.local_shipping_outlined,
                  mensaje:
                      'No hay envios con ese filtro.\nLos pedidos a domicilio aparecen apenas se confirma el pago.',
                )
              else
                ..._envios.map(
                  (envio) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TarjetaPanel(
                      alTocar: () => _abrir(envio),
                      hijo: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  envio.numeroVenta,
                                  style: fuenteMono(fontSize: 12.5, color: Paleta.ink),
                                ),
                              ),
                              BadgeEstado(etiquetaEstadoEnvio(envio.estado)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            envio.cliente,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            envio.direccion,
                            style: const TextStyle(color: Paleta.inkSuave, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${envio.distanciaKm.toStringAsFixed(1)} km · '
                            '~${envio.duracionMin} min · envio ${formatearPrecio(envio.costo)}',
                            style: const TextStyle(color: Paleta.inkSuave, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Contadores extends StatelessWidget {
  const _Contadores({required this.resumen});

  final ResumenEnvios resumen;

  @override
  Widget build(BuildContext context) {
    final datos = <(String, int)>[
      ('Pendientes', resumen.pendientes),
      ('Despachados', resumen.despachados),
      ('Entregados hoy', resumen.entregadosHoy),
      ('Fallidos', resumen.fallidos),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: datos
            .map(
              (dato) => Container(
                width: 104,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Paleta.blanco,
                  border: Border.all(color: Paleta.paperLinea),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${dato.$2}', style: fuenteDisplay(fontSize: 24, color: Paleta.ink)),
                    const SizedBox(height: 2),
                    EtiquetaDato(dato.$1),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _DetalleEnvioPagina extends StatefulWidget {
  const _DetalleEnvioPagina({required this.envioId});

  final String envioId;

  @override
  State<_DetalleEnvioPagina> createState() => _DetalleEnvioPaginaState();
}

class _DetalleEnvioPaginaState extends State<_DetalleEnvioPagina> {
  final _observacion = TextEditingController();
  final _formatoFecha = DateFormat('dd/MM HH:mm');

  EnvioAdminDetalle? _detalle;
  bool _cargando = true;
  bool _trabajando = false;
  bool _huboCambios = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _observacion.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final detalle = await enviosService.detalle(widget.envioId);
      if (!mounted) return;
      setState(() {
        _detalle = detalle;
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

  Future<void> _cambiarEstado(String estado) async {
    if (estado == 'FALLIDO' && _observacion.text.trim().isEmpty) {
      mostrarAviso(context, 'Un envio fallido necesita que anotes el motivo', esError: true);
      return;
    }

    setState(() => _trabajando = true);
    try {
      await enviosService.cambiarEstado(
        widget.envioId,
        estado,
        observacion: _observacion.text.trim().isEmpty ? null : _observacion.text.trim(),
      );
      _huboCambios = true;
      _observacion.clear();
      if (!mounted) return;
      mostrarAviso(context, 'Envio marcado como ${etiquetaEstadoEnvio(estado).toLowerCase()}');
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      mostrarAviso(context, interpretarError(error), esError: true);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detalle = _detalle;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (salio, _) {
        if (!salio) Navigator.of(context).pop(_huboCambios);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(detalle?.envio.numeroVenta ?? 'Envio')),
        body: VistaAsincrona(
          cargando: _cargando,
          error: _error,
          alReintentar: _cargar,
          hijo: detalle == null
              ? const SizedBox.shrink()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    Row(
                      children: [
                        BadgeEstado(etiquetaEstadoEnvio(detalle.envio.estado)),
                        const Spacer(),
                        Text(
                          formatearPrecio(detalle.envio.totalVenta),
                          style: fuenteDisplay(fontSize: 20, color: Paleta.ink),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FilaDato('Cliente', detalle.envio.cliente),
                    if (detalle.envio.clienteTelefono != null)
                      FilaDato('Telefono', detalle.envio.clienteTelefono!),
                    FilaDato('Destino', detalle.envio.direccion),
                    if (detalle.envio.referencia != null)
                      FilaDato('Referencia', detalle.envio.referencia!),
                    FilaDato(
                      'Ruta',
                      '${detalle.envio.distanciaKm.toStringAsFixed(1)} km · '
                          '~${detalle.envio.duracionMin} min · '
                          '${detalle.envio.proveedorRuteo == 'ORS' ? 'openrouteservice' : 'estimacion propia'}',
                    ),
                    FilaDato('Cobrado por el envio', formatearPrecio(detalle.envio.costo)),
                    if (detalle.envio.latitud != null) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          height: 200,
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter:
                                  LatLng(detalle.envio.latitud!, detalle.envio.longitud!),
                              initialZoom: 15,
                              interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                              ),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'bo.fashionstore.movil',
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: LatLng(
                                      detalle.envio.latitud!,
                                      detalle.envio.longitud!,
                                    ),
                                    width: 40,
                                    height: 40,
                                    alignment: Alignment.topCenter,
                                    child: const Icon(
                                      Icons.place,
                                      color: Paleta.flame,
                                      size: 38,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    const EtiquetaDato('Que lleva'),
                    const SizedBox(height: 8),
                    ...detalle.items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '${item.cantidad} × ${item.producto}  ·  ${item.talla} · ${item.color}',
                          style: const TextStyle(fontSize: 13.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    if ((transicionesEnvio[detalle.envio.estado] ?? const []).isNotEmpty) ...[
                      const EtiquetaDato('Mover el envio'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _observacion,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Nota (obligatoria si falla)',
                          hintText: 'Ej: el servicio de delivery no pudo entregar',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: (transicionesEnvio[detalle.envio.estado] ?? const [])
                            .map(
                              (estado) => estado == 'FALLIDO' || estado == 'CANCELADO'
                                  ? OutlinedButton(
                                      onPressed: _trabajando ? null : () => _cambiarEstado(estado),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Paleta.rojo,
                                        side: const BorderSide(color: Paleta.rojo),
                                      ),
                                      child: Text(etiquetaEstadoEnvio(estado).toUpperCase()),
                                    )
                                  : FilledButton(
                                      onPressed: _trabajando ? null : () => _cambiarEstado(estado),
                                      child: Text(etiquetaEstadoEnvio(estado).toUpperCase()),
                                    ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 22),
                    ],
                    const EtiquetaDato('Bitacora'),
                    const SizedBox(height: 8),
                    ...detalle.eventos.map(
                      (evento) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${etiquetaEstadoEnvio(evento.estado)} · ${_formatoFecha.format(evento.fecha)}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            if (evento.usuario != null || evento.nota != null)
                              Text(
                                [evento.usuario, evento.nota].whereType<String>().join(' · '),
                                style: const TextStyle(color: Paleta.inkSuave, fontSize: 12.5),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
