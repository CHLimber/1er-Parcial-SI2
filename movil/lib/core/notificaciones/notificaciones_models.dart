import '../api.dart';

/// Espejo de `backend/app/modules/notificaciones/schemas.py` (PENDIENTES.txt 2.19.3).
class NotificacionOut {
  NotificacionOut({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.mensaje,
    required this.entidadTipo,
    required this.entidadId,
    required this.ventaId,
    required this.leida,
    required this.fecha,
  });

  final String id;

  /// tipo_notificacion: RESERVA / VENTA / STOCK / PROMO.
  final String tipo;
  final String titulo;
  final String mensaje;

  /// A que apunta el aviso: RESERVA, VENTA, ENVIO, ... (texto libre en la tabla).
  final String? entidadTipo;
  final String? entidadId;

  /// Venta resuelta por el backend (la propia si es VENTA, la del envio si es ENVIO).
  final String? ventaId;
  final bool leida;
  final DateTime? fecha;

  NotificacionOut copiarLeida() => NotificacionOut(
        id: id,
        tipo: tipo,
        titulo: titulo,
        mensaje: mensaje,
        entidadTipo: entidadTipo,
        entidadId: entidadId,
        ventaId: ventaId,
        leida: true,
        fecha: fecha,
      );

  factory NotificacionOut.desdeJson(Map<String, dynamic> j) => NotificacionOut(
        id: j['id'] as String,
        tipo: j['tipo'] as String,
        titulo: j['titulo'] as String,
        mensaje: j['mensaje'] as String,
        entidadTipo: j['entidad_tipo'] as String?,
        entidadId: j['entidad_id'] as String?,
        ventaId: j['venta_id'] as String?,
        leida: j['leida'] as bool? ?? false,
        fecha: aFechaNula(j['fecha']),
      );
}

class NotificacionPaginadoOut {
  NotificacionPaginadoOut({
    required this.total,
    required this.noLeidas,
    required this.pagina,
    required this.tamanioPagina,
    required this.items,
  });

  final int total;
  final int noLeidas;
  final int pagina;
  final int tamanioPagina;
  final List<NotificacionOut> items;

  factory NotificacionPaginadoOut.desdeJson(Map<String, dynamic> j) => NotificacionPaginadoOut(
        total: aEntero(j['total']),
        noLeidas: aEntero(j['no_leidas']),
        pagina: aEntero(j['pagina']),
        tamanioPagina: aEntero(j['tamanio_pagina']),
        items: comoLista(j['items']).map(NotificacionOut.desdeJson).toList(),
      );
}
