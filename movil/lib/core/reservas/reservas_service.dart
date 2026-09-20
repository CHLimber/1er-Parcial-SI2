import 'package:flutter/foundation.dart';

import '../api.dart';
import 'reservas_models.dart';

/// CU04 (cliente) y CU08 (encargado de sucursal).
class ReservasService {
  /// `MisReservasPagina` vive dentro del IndexedStack de la barra inferior, que
  /// mantiene su estado (y su lista ya cargada) al cambiar de pestana -- sin esto,
  /// confirmar una reserva y volver a esa pantalla mostraria la lista vieja, como si
  /// la reserva nueva no se hubiera guardado. Se notifica al crear una reserva para
  /// que esa pantalla sepa que tiene que volver a pedir la lista.
  final ValueNotifier<int> actualizaciones = ValueNotifier<int>(0);

  Future<ReservaOut> crear({
    required String sucursalId,
    required DateTime fechaVisita,
    required String horaVisita,
    String? observaciones,
    required List<ItemCarritoReserva> items,
  }) async {
    final respuesta = await api.post('/reservas', cuerpo: {
      'sucursal_id': sucursalId,
      'fecha_visita': fechaVisita.toIso8601String().split('T').first,
      'hora_visita': horaVisita,
      'observaciones': (observaciones?.isEmpty ?? true) ? null : observaciones,
      'items': items
          .map((i) => {'variante_id': i.varianteId, 'cantidad': i.cantidad})
          .toList(),
    });
    final reserva = ReservaOut.desdeJson(respuesta as Map<String, dynamic>);
    actualizaciones.value++;
    return reserva;
  }

  Future<List<ReservaOut>> listarMisReservas() async {
    final respuesta = await api.get('/reservas');
    return comoLista(respuesta).map(ReservaOut.desdeJson).toList();
  }

  // --- CU08: cola de la sucursal -------------------------------------------

  Future<List<ReservaStaffOut>> listarDeSucursal({String? estado}) async {
    final respuesta = await api.get('/reservas/sucursal', query: {'estado': estado});
    return comoLista(respuesta).map(ReservaStaffOut.desdeJson).toList();
  }

  Future<ReservaStaffOut> obtenerDeSucursal(String reservaId) async {
    final respuesta = await api.get('/reservas/sucursal/$reservaId');
    return ReservaStaffOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  /// Marca que prendas estan realmente en el perchero antes de que llegue el cliente.
  Future<ReservaStaffOut> preparar(
    String reservaId,
    List<Map<String, dynamic>> items,
  ) async {
    final respuesta = await api.post('/reservas/$reservaId/preparar', cuerpo: {'items': items});
    return ReservaStaffOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<ReservaStaffOut> marcarPresente(String reservaId, String? vestidor) async {
    final respuesta = await api.post(
      '/reservas/$reservaId/presente',
      cuerpo: {'vestidor_asignado': (vestidor?.isEmpty ?? true) ? null : vestidor},
    );
    return ReservaStaffOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  /// Cierra la reserva: lo comprado se vende (y libera el resto del compromiso).
  Future<ResolverReservaOut> resolver(
    String reservaId, {
    required List<Map<String, dynamic>> decisiones,
    String? metodoPago,
    double? montoRecibido,
  }) async {
    final respuesta = await api.post('/reservas/$reservaId/resolver', cuerpo: {
      'decisiones': decisiones,
      'metodo_pago': metodoPago,
      'monto_recibido': montoRecibido,
    });
    return ResolverReservaOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<ReservaStaffOut> marcarNoPresentado(String reservaId) async {
    final respuesta = await api.post('/reservas/$reservaId/no-presentado');
    return ReservaStaffOut.desdeJson(respuesta as Map<String, dynamic>);
  }
}

final reservasService = ReservasService();
