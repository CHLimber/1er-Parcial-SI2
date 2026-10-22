import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/operacion_sin_conexion/offline/conexion_service.dart';
import '../core/tema.dart';

/// Franja inferior con el estado de la conexion (PENDIENTES 5.3), espejo de
/// `shared/offline/aviso-conexion.ts` de la web: sin red (y de cuando son los datos que se
/// ven), operaciones pendientes, y el resultado de la sincronizacion al volver la red. Se monta
/// una sola vez en `MaterialApp.builder`, asi aparece sobre todas las pantallas.
class AvisoConexion extends StatelessWidget {
  const AvisoConexion({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // nullable: los widget tests montan la app sin la capa offline
    final conexion = context.watch<ConexionService?>();
    if (conexion == null) return child;
    String? texto;
    var esError = false;
    if (!conexion.enLinea) {
      esError = true;
      final fecha = conexion.datosDe;
      texto = 'Sin conexion. '
          '${fecha == null ? 'Podes seguir viendo lo que ya cargaste.' : 'Datos guardados el ${DateFormat('dd/MM HH:mm').format(fecha)}.'}'
          '${conexion.pendientes > 0 ? ' ${conexion.pendientes} operacion(es) esperan la red.' : ''}';
    } else if (conexion.ultimoAviso != null) {
      texto = conexion.ultimoAviso;
    }

    return Stack(
      children: [
        child,
        if (texto != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12 + MediaQuery.of(context).padding.bottom + (esError ? 0 : 64),
            child: Material(
              elevation: 6,
              color: esError ? Paleta.ink : Paleta.blanco,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(esError ? Icons.cloud_off : Icons.cloud_done,
                        size: 18, color: esError ? Colors.white : Paleta.ink),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        texto,
                        style: TextStyle(color: esError ? Colors.white : Paleta.ink, fontSize: 13),
                      ),
                    ),
                    if (!esError)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: conexion.cerrarAviso,
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
