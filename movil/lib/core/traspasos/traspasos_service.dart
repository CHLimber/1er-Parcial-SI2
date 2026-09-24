import '../api.dart';

/// Traspasos de mercaderia entre sucursales (PENDIENTES 2.7/2.19.7). Espejo de
/// `backend/app/modules/traspasos/schemas.py`. El origen solicita y despacha (sale
/// stock); el destino recibe (entra lo recibido); ANULADO revierte segun el estado. El
/// backend nunca escribe inventario directo, lo hace el trigger `tg_traspaso_stock`.
class DetalleTraspasoOut {
  DetalleTraspasoOut({
    required this.id,
    required this.varianteId,
    required this.sku,
    required this.producto,
    required this.talla,
    required this.color,
    required this.codigoHex,
    required this.cantidadSolicitada,
    required this.cantidadRecibida,
    required this.disponibleOrigen,
    required this.disponibleDestino,
  });

  final String id;
  final String varianteId;
  final String sku;
  final String producto;
  final String talla;
  final String color;
  final String codigoHex;
  final int cantidadSolicitada;
  final int? cantidadRecibida;
  final int disponibleOrigen;
  final int disponibleDestino;

  factory DetalleTraspasoOut.desdeJson(Map<String, dynamic> j) => DetalleTraspasoOut(
        id: j['id'] as String,
        varianteId: j['variante_id'] as String,
        sku: j['sku'] as String,
        producto: j['producto'] as String,
        talla: j['talla'] as String,
        color: j['color'] as String,
        codigoHex: j['codigo_hex'] as String,
        cantidadSolicitada: aEntero(j['cantidad_solicitada']),
        cantidadRecibida: j['cantidad_recibida'] == null ? null : aEntero(j['cantidad_recibida']),
        disponibleOrigen: aEntero(j['disponible_origen']),
        disponibleDestino: aEntero(j['disponible_destino']),
      );
}

class TraspasoOut {
  TraspasoOut({
    required this.id,
    required this.numero,
    required this.estado,
    required this.sucursalOrigenId,
    required this.origen,
    required this.sucursalDestinoId,
    required this.destino,
    required this.fechaSolicitud,
    required this.fechaDespacho,
    required this.fechaRecepcion,
    required this.solicitadoPor,
    required this.recibidoPor,
    required this.observacion,
    required this.lineas,
    required this.unidadesSolicitadas,
    required this.unidadesRecibidas,
    required this.miLado,
  });

  final String id;
  final String numero;
  final String estado;
  final String sucursalOrigenId;
  final String origen;
  final String sucursalDestinoId;
  final String destino;
  final String fechaSolicitud;
  final String? fechaDespacho;
  final String? fechaRecepcion;
  final String? solicitadoPor;
  final String? recibidoPor;
  final String? observacion;
  final int lineas;
  final int unidadesSolicitadas;
  final int? unidadesRecibidas;
  /// ORIGEN, DESTINO o AMBOS (ADMIN). La pantalla lo usa para ofrecer
  /// despachar/recibir/anular; quien autoriza de verdad es el backend.
  final String miLado;

  factory TraspasoOut.desdeJson(Map<String, dynamic> j) => TraspasoOut(
        id: j['id'] as String,
        numero: j['numero'] as String,
        estado: j['estado'] as String,
        sucursalOrigenId: j['sucursal_origen_id'] as String,
        origen: j['origen'] as String,
        sucursalDestinoId: j['sucursal_destino_id'] as String,
        destino: j['destino'] as String,
        fechaSolicitud: j['fecha_solicitud'] as String,
        fechaDespacho: j['fecha_despacho'] as String?,
        fechaRecepcion: j['fecha_recepcion'] as String?,
        solicitadoPor: j['solicitado_por'] as String?,
        recibidoPor: j['recibido_por'] as String?,
        observacion: j['observacion'] as String?,
        lineas: aEntero(j['lineas']),
        unidadesSolicitadas: aEntero(j['unidades_solicitadas']),
        unidadesRecibidas:
            j['unidades_recibidas'] == null ? null : aEntero(j['unidades_recibidas']),
        miLado: j['mi_lado'] as String? ?? 'AMBOS',
      );
}

class TraspasoDetalleOut extends TraspasoOut {
  TraspasoDetalleOut({
    required super.id,
    required super.numero,
    required super.estado,
    required super.sucursalOrigenId,
    required super.origen,
    required super.sucursalDestinoId,
    required super.destino,
    required super.fechaSolicitud,
    required super.fechaDespacho,
    required super.fechaRecepcion,
    required super.solicitadoPor,
    required super.recibidoPor,
    required super.observacion,
    required super.lineas,
    required super.unidadesSolicitadas,
    required super.unidadesRecibidas,
    required super.miLado,
    required this.detalle,
  });

  final List<DetalleTraspasoOut> detalle;

  factory TraspasoDetalleOut.desdeJson(Map<String, dynamic> j) {
    final base = TraspasoOut.desdeJson(j);
    return TraspasoDetalleOut(
      id: base.id,
      numero: base.numero,
      estado: base.estado,
      sucursalOrigenId: base.sucursalOrigenId,
      origen: base.origen,
      sucursalDestinoId: base.sucursalDestinoId,
      destino: base.destino,
      fechaSolicitud: base.fechaSolicitud,
      fechaDespacho: base.fechaDespacho,
      fechaRecepcion: base.fechaRecepcion,
      solicitadoPor: base.solicitadoPor,
      recibidoPor: base.recibidoPor,
      observacion: base.observacion,
      lineas: base.lineas,
      unidadesSolicitadas: base.unidadesSolicitadas,
      unidadesRecibidas: base.unidadesRecibidas,
      miLado: base.miLado,
      detalle: comoLista(j['detalle']).map(DetalleTraspasoOut.desdeJson).toList(),
    );
  }
}

class VarianteTraspasoOut {
  VarianteTraspasoOut({
    required this.id,
    required this.sku,
    required this.producto,
    required this.talla,
    required this.color,
    required this.codigoHex,
    required this.disponibleOrigen,
    required this.disponibleDestino,
  });

  final String id;
  final String sku;
  final String producto;
  final String talla;
  final String color;
  final String codigoHex;
  final int disponibleOrigen;
  final int disponibleDestino;

  factory VarianteTraspasoOut.desdeJson(Map<String, dynamic> j) => VarianteTraspasoOut(
        id: j['id'] as String,
        sku: j['sku'] as String,
        producto: j['producto'] as String,
        talla: j['talla'] as String,
        color: j['color'] as String,
        codigoHex: j['codigo_hex'] as String,
        disponibleOrigen: aEntero(j['disponible_origen']),
        disponibleDestino: aEntero(j['disponible_destino']),
      );
}

/// Asiento del kardex generado por el traspaso, en cualquiera de las dos sucursales.
class MovimientoTraspasoOut {
  MovimientoTraspasoOut({
    required this.sucursal,
    required this.tipo,
    required this.sku,
    required this.producto,
    required this.cantidad,
    required this.saldoAnterior,
    required this.saldoNuevo,
    required this.fecha,
  });

  final String sucursal;
  final String tipo;
  final String sku;
  final String producto;
  final int cantidad;
  final int saldoAnterior;
  final int saldoNuevo;
  final String fecha;

  factory MovimientoTraspasoOut.desdeJson(Map<String, dynamic> j) => MovimientoTraspasoOut(
        sucursal: j['sucursal'] as String,
        tipo: j['tipo'] as String,
        sku: j['sku'] as String,
        producto: j['producto'] as String,
        cantidad: aEntero(j['cantidad']),
        saldoAnterior: aEntero(j['saldo_anterior']),
        saldoNuevo: aEntero(j['saldo_nuevo']),
        fecha: j['fecha'] as String,
      );
}

/// Traspasos entre sucursales: crear (SOLICITADO, no mueve stock), despachar (sale del
/// origen), recibir (entra al destino, se puede informar menos de lo despachado) y
/// anular (revierte si ya estaba EN_TRANSITO).
class TraspasosService {
  Future<List<TraspasoOut>> listar({String? estado, String? direccion}) async {
    final respuesta = await api.get('/traspasos', query: {
      'estado': estado,
      'direccion': direccion,
    });
    return comoLista(respuesta).map(TraspasoOut.desdeJson).toList();
  }

  Future<TraspasoDetalleOut> obtener(String traspasoId) async {
    final respuesta = await api.get('/traspasos/$traspasoId');
    return TraspasoDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<List<MovimientoTraspasoOut>> movimientos(String traspasoId) async {
    final respuesta = await api.get('/traspasos/$traspasoId/movimientos');
    return comoLista(respuesta).map(MovimientoTraspasoOut.desdeJson).toList();
  }

  Future<List<VarianteTraspasoOut>> buscarVariantes(
    String q, {
    String? origenId,
    String? destinoId,
  }) async {
    final respuesta = await api.get('/traspasos/variantes', query: {
      'q': q,
      'origen_id': origenId,
      'destino_id': destinoId,
    });
    return comoLista(respuesta).map(VarianteTraspasoOut.desdeJson).toList();
  }

  Future<TraspasoDetalleOut> crear({
    String? sucursalOrigenId,
    required String sucursalDestinoId,
    required List<MapEntry<String, int>> lineas,
  }) async {
    final respuesta = await api.post('/traspasos', cuerpo: {
      'sucursal_origen_id': sucursalOrigenId,
      'sucursal_destino_id': sucursalDestinoId,
      'lineas': lineas.map((l) => {'variante_id': l.key, 'cantidad': l.value}).toList(),
    });
    return TraspasoDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<TraspasoDetalleOut> despachar(String traspasoId) async {
    final respuesta = await api.post('/traspasos/$traspasoId/despachar');
    return TraspasoDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  /// [recibidas] son solo las lineas que difieren de lo solicitado: las que no se
  /// mandan se toman como recibidas completas (mismo criterio que el backend).
  Future<TraspasoDetalleOut> recibir(
    String traspasoId, {
    required List<MapEntry<String, int>> recibidas,
    String? observacion,
  }) async {
    final respuesta = await api.post('/traspasos/$traspasoId/recibir', cuerpo: {
      'lineas': recibidas
          .map((l) => {'detalle_id': l.key, 'cantidad_recibida': l.value})
          .toList(),
      'observacion': (observacion?.isEmpty ?? true) ? null : observacion,
    });
    return TraspasoDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<TraspasoDetalleOut> anular(String traspasoId) async {
    final respuesta = await api.post('/traspasos/$traspasoId/anular');
    return TraspasoDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }
}

final traspasosService = TraspasosService();
