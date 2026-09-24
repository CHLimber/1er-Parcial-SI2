import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/envios/envios_models.dart';
import '../core/tema.dart';

/// Ruta aproximada del delivery (CU20), de solo lectura: la sucursal, el domicilio y la linea
/// por donde iria el servicio de delivery externo. Espejo de `shared/mapa/mapa-ruta.ts` de la
/// web; mismos tiles que el mapa de `mis_direcciones_pagina.dart`.
class MapaRuta extends StatelessWidget {
  const MapaRuta({super.key, required this.cotizacion});

  final CotizacionEnvio cotizacion;

  @override
  Widget build(BuildContext context) {
    final origen = LatLng(cotizacion.origen[0], cotizacion.origen[1]);
    final destino = LatLng(cotizacion.destino[0], cotizacion.destino[1]);
    final puntos = cotizacion.ruta.length >= 2
        ? cotizacion.ruta.map((p) => LatLng(p[0], p[1])).toList()
        : [origen, destino];
    final lineaRecta = cotizacion.rutaProveedor == 'LINEA_RECTA';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 200,
            child: FlutterMap(
              // la camara inicial solo se aplica al crear el mapa: con otra direccion o
              // sucursal hay que armarlo de nuevo para que encuadre la ruta nueva
              key: ValueKey('${cotizacion.origen}-${cotizacion.destino}'),
              options: MapOptions(
                initialCameraFit: CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(puntos),
                  padding: const EdgeInsets.all(28),
                  maxZoom: 16,
                ),
                // sin arrastre: adentro de un scroll vertical le robaria el gesto a la pagina
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'bo.fashionstore.movil',
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: puntos,
                      strokeWidth: 5,
                      color: Paleta.flame.withValues(alpha: 0.85),
                      pattern: lineaRecta
                          ? StrokePattern.dashed(segments: const [10, 8])
                          : const StrokePattern.solid(),
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(point: origen, width: 22, height: 22, child: _pin(Paleta.ink)),
                    Marker(point: destino, width: 22, height: 22, child: _pin(Paleta.flame)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${lineaRecta ? 'Recorrido aproximado en linea recta' : 'Ruta aproximada del delivery'} '
          'desde la sucursal hasta tu direccion. El reparto lo hace un servicio externo y puede '
          'tomar otro camino.',
          style: const TextStyle(fontSize: 12, color: Paleta.inkSuave, height: 1.35),
        ),
      ],
    );
  }

  Widget _pin(Color color) => Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
        ),
      );
}
