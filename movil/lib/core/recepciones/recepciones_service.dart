import '../api.dart';

/// Espejo de `backend/app/modules/recepciones/schemas.py` (CU09).
class DetalleOut {
  DetalleOut({
    required this.id,
    required this.varianteId,
    required this.sku,
    required this.producto,
    required this.talla,
    required this.color,
    required this.cantidad,
    required this.costoUnitario,
    required this.subtotal,
  });

  final String id;
  final String varianteId;
  final String sku;
  final String producto;
  final String talla;
  final String color;
  final int cantidad;
  final double costoUnitario;
  final double subtotal;

  factory DetalleOut.desdeJson(Map<String, dynamic> j) => DetalleOut(
        id: j['id'] as String,
        varianteId: j['variante_id'] as String,
        sku: j['sku'] as String,
        producto: j['producto'] as String,
        talla: j['talla'] as String,
        color: j['color'] as String,
        cantidad: aEntero(j['cantidad']),
        costoUnitario: aDouble(j['costo_unitario']),
        subtotal: aDouble(j['subtotal']),
      );
}

class RecepcionOut {
  RecepcionOut({
    required this.id,
    required this.numero,
    required this.fecha,
    required this.estado,
    required this.sucursalId,
    required this.sucursal,
    required this.proveedorId,
    required this.proveedor,
    required this.coleccionId,
    required this.coleccion,
    required this.total,
    required this.usuarioId,
    required this.registradoPor,
    required this.lineas,
    required this.unidades,
  });

  final String id;
  final String numero;
  final String fecha;
  final String estado;
  final String sucursalId;
  final String sucursal;
  final String proveedorId;
  final String proveedor;
  final String? coleccionId;
  final String? coleccion;
  final double? total;
  final String? usuarioId;
  final String? registradoPor;
  final int lineas;
  final int unidades;

  bool get esBorrador => estado == 'BORRADOR';

  factory RecepcionOut.desdeJson(Map<String, dynamic> j) => RecepcionOut(
        id: j['id'] as String,
        numero: j['numero'] as String,
        fecha: j['fecha'] as String,
        estado: j['estado'] as String,
        sucursalId: j['sucursal_id'] as String,
        sucursal: j['sucursal'] as String,
        proveedorId: j['proveedor_id'] as String,
        proveedor: j['proveedor'] as String,
        coleccionId: j['coleccion_id'] as String?,
        coleccion: j['coleccion'] as String?,
        total: aDoubleNulo(j['total']),
        usuarioId: j['usuario_id'] as String?,
        registradoPor: j['registrado_por'] as String?,
        lineas: aEntero(j['lineas']),
        unidades: aEntero(j['unidades']),
      );
}

class RecepcionDetalleOut extends RecepcionOut {
  RecepcionDetalleOut({
    required super.id,
    required super.numero,
    required super.fecha,
    required super.estado,
    required super.sucursalId,
    required super.sucursal,
    required super.proveedorId,
    required super.proveedor,
    required super.coleccionId,
    required super.coleccion,
    required super.total,
    required super.usuarioId,
    required super.registradoPor,
    required super.lineas,
    required super.unidades,
    required this.detalle,
  });

  final List<DetalleOut> detalle;

  factory RecepcionDetalleOut.desdeJson(Map<String, dynamic> j) {
    final base = RecepcionOut.desdeJson(j);
    return RecepcionDetalleOut(
      id: base.id,
      numero: base.numero,
      fecha: base.fecha,
      estado: base.estado,
      sucursalId: base.sucursalId,
      sucursal: base.sucursal,
      proveedorId: base.proveedorId,
      proveedor: base.proveedor,
      coleccionId: base.coleccionId,
      coleccion: base.coleccion,
      total: base.total,
      usuarioId: base.usuarioId,
      registradoPor: base.registradoPor,
      lineas: base.lineas,
      unidades: base.unidades,
      detalle: comoLista(j['detalle']).map(DetalleOut.desdeJson).toList(),
    );
  }
}

class VarianteBuscadaOut {
  VarianteBuscadaOut({
    required this.id,
    required this.sku,
    required this.producto,
    required this.talla,
    required this.color,
    required this.codigoHex,
    required this.precioBase,
    required this.stockSucursal,
  });

  final String id;
  final String sku;
  final String producto;
  final String talla;
  final String color;
  final String codigoHex;
  final double precioBase;
  final int stockSucursal;

  factory VarianteBuscadaOut.desdeJson(Map<String, dynamic> j) => VarianteBuscadaOut(
        id: j['id'] as String,
        sku: j['sku'] as String,
        producto: j['producto'] as String,
        talla: j['talla'] as String,
        color: j['color'] as String,
        codigoHex: j['codigo_hex'] as String,
        precioBase: aDouble(j['precio_base']),
        stockSucursal: aEntero(j['stock_sucursal']),
      );
}

/// Asiento del kardex generado al confirmar: muestra el efecto real sobre el stock.
class MovimientoOut {
  MovimientoOut({
    required this.varianteId,
    required this.sku,
    required this.producto,
    required this.cantidad,
    required this.saldoAnterior,
    required this.saldoNuevo,
    required this.fecha,
  });

  final String varianteId;
  final String sku;
  final String producto;
  final int cantidad;
  final int saldoAnterior;
  final int saldoNuevo;
  final DateTime? fecha;

  factory MovimientoOut.desdeJson(Map<String, dynamic> j) => MovimientoOut(
        varianteId: j['variante_id'] as String,
        sku: j['sku'] as String,
        producto: j['producto'] as String,
        cantidad: aEntero(j['cantidad']),
        saldoAnterior: aEntero(j['saldo_anterior']),
        saldoNuevo: aEntero(j['saldo_nuevo']),
        fecha: aFechaNula(j['fecha']),
      );
}

/// CU09: Registrar Recepcion de Mercaderia. Confirmar es el unico camino por el que entra
/// stock nuevo: el trigger `tg_confirmar_recepcion` llama a `fn_mover_inventario`.
class RecepcionesService {
  Future<List<RecepcionOut>> listar({String? estado, String? proveedorId}) async {
    final respuesta = await api.get('/recepciones', query: {
      'estado': estado,
      'proveedor_id': proveedorId,
    });
    return comoLista(respuesta).map(RecepcionOut.desdeJson).toList();
  }

  Future<RecepcionDetalleOut> obtener(String recepcionId) async {
    final respuesta = await api.get('/recepciones/$recepcionId');
    return RecepcionDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<List<VarianteBuscadaOut>> buscarVariantes(String q, {String? sucursalId}) async {
    final respuesta = await api.get('/recepciones/variantes', query: {
      'q': q,
      'sucursal_id': sucursalId,
    });
    return comoLista(respuesta).map(VarianteBuscadaOut.desdeJson).toList();
  }

  Future<List<MovimientoOut>> movimientos(String recepcionId) async {
    final respuesta = await api.get('/recepciones/$recepcionId/movimientos');
    return comoLista(respuesta).map(MovimientoOut.desdeJson).toList();
  }

  Future<RecepcionDetalleOut> crear({
    String? sucursalId,
    required String proveedorId,
    String? coleccionId,
    String? numero,
    DateTime? fecha,
  }) async {
    final respuesta = await api.post('/recepciones', cuerpo: {
      'sucursal_id': sucursalId,
      'proveedor_id': proveedorId,
      'coleccion_id': coleccionId,
      'numero': (numero?.isEmpty ?? true) ? null : numero,
      'fecha': fecha?.toIso8601String().split('T').first,
    });
    return RecepcionDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<RecepcionDetalleOut> agregarLinea(
    String recepcionId, {
    required String varianteId,
    required int cantidad,
    required double costoUnitario,
  }) async {
    final respuesta = await api.post('/recepciones/$recepcionId/detalle', cuerpo: {
      'variante_id': varianteId,
      'cantidad': cantidad,
      'costo_unitario': costoUnitario,
    });
    return RecepcionDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<RecepcionDetalleOut> editarLinea(
    String recepcionId,
    String detalleId, {
    required String varianteId,
    required int cantidad,
    required double costoUnitario,
  }) async {
    final respuesta = await api.put('/recepciones/$recepcionId/detalle/$detalleId', cuerpo: {
      'variante_id': varianteId,
      'cantidad': cantidad,
      'costo_unitario': costoUnitario,
    });
    return RecepcionDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<RecepcionDetalleOut> quitarLinea(String recepcionId, String detalleId) async {
    final respuesta = await api.delete('/recepciones/$recepcionId/detalle/$detalleId');
    return RecepcionDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<RecepcionDetalleOut> confirmar(String recepcionId) async {
    final respuesta = await api.post('/recepciones/$recepcionId/confirmar');
    return RecepcionDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<RecepcionDetalleOut> anular(String recepcionId) async {
    final respuesta = await api.post('/recepciones/$recepcionId/anular');
    return RecepcionDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }
}

final recepcionesService = RecepcionesService();
