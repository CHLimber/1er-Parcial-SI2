import '../api.dart';

/// Devoluciones de ventas (PENDIENTES 2.7/2.19.7). Espejo de
/// `backend/app/modules/devoluciones/schemas.py`. Registrar nace SOLICITADA y no mueve
/// stock; aprobar dispara `tg_devolucion_stock` (reingresa el stock, tipo DEVOLUCION) y
/// recalcula el monto a reintegrar; rechazar solo pide un motivo.
class LineaVentaOut {
  LineaVentaOut({
    required this.ventaDetalleId,
    required this.varianteId,
    required this.sku,
    required this.producto,
    required this.talla,
    required this.color,
    required this.cantidadVendida,
    required this.precioUnitario,
    required this.subtotal,
    required this.devuelta,
    required this.enTramite,
    required this.devolvible,
    required this.reembolsoUnitario,
  });

  final String ventaDetalleId;
  final String varianteId;
  final String sku;
  final String producto;
  final String talla;
  final String color;
  final int cantidadVendida;
  final double precioUnitario;
  final double subtotal;
  final int devuelta;
  final int enTramite;
  final int devolvible;
  final double reembolsoUnitario;

  factory LineaVentaOut.desdeJson(Map<String, dynamic> j) => LineaVentaOut(
        ventaDetalleId: j['venta_detalle_id'] as String,
        varianteId: j['variante_id'] as String,
        sku: j['sku'] as String,
        producto: j['producto'] as String,
        talla: j['talla'] as String,
        color: j['color'] as String,
        cantidadVendida: aEntero(j['cantidad_vendida']),
        precioUnitario: aDouble(j['precio_unitario']),
        subtotal: aDouble(j['subtotal']),
        devuelta: aEntero(j['devuelta']),
        enTramite: aEntero(j['en_tramite']),
        devolvible: aEntero(j['devolvible']),
        reembolsoUnitario: aDouble(j['reembolso_unitario']),
      );
}

class VentaDevolvibleOut {
  VentaDevolvibleOut({
    required this.ventaId,
    required this.numero,
    required this.fecha,
    required this.estado,
    required this.canal,
    required this.sucursalId,
    required this.sucursal,
    required this.cliente,
    required this.subtotal,
    required this.descuento,
    required this.costoEnvio,
    required this.total,
    required this.totalDevuelto,
    required this.lineas,
  });

  final String ventaId;
  final String numero;
  final String fecha;
  final String estado;
  final String canal;
  final String sucursalId;
  final String sucursal;
  final String? cliente;
  final double subtotal;
  final double descuento;
  final double costoEnvio;
  final double total;
  final double totalDevuelto;
  final List<LineaVentaOut> lineas;

  factory VentaDevolvibleOut.desdeJson(Map<String, dynamic> j) => VentaDevolvibleOut(
        ventaId: j['venta_id'] as String,
        numero: j['numero'] as String,
        fecha: j['fecha'] as String,
        estado: j['estado'] as String,
        canal: j['canal'] as String,
        sucursalId: j['sucursal_id'] as String,
        sucursal: j['sucursal'] as String,
        cliente: j['cliente'] as String?,
        subtotal: aDouble(j['subtotal']),
        descuento: aDouble(j['descuento']),
        costoEnvio: aDouble(j['costo_envio']),
        total: aDouble(j['total']),
        totalDevuelto: aDouble(j['total_devuelto']),
        lineas: comoLista(j['lineas']).map(LineaVentaOut.desdeJson).toList(),
      );
}

class DetalleDevolucionOut {
  DetalleDevolucionOut({
    required this.id,
    required this.ventaDetalleId,
    required this.varianteId,
    required this.sku,
    required this.producto,
    required this.talla,
    required this.color,
    required this.cantidad,
    required this.cantidadVendida,
    required this.precioUnitario,
  });

  final String id;
  final String ventaDetalleId;
  final String varianteId;
  final String sku;
  final String producto;
  final String talla;
  final String color;
  final int cantidad;
  final int cantidadVendida;
  final double precioUnitario;

  factory DetalleDevolucionOut.desdeJson(Map<String, dynamic> j) => DetalleDevolucionOut(
        id: j['id'] as String,
        ventaDetalleId: j['venta_detalle_id'] as String,
        varianteId: j['variante_id'] as String,
        sku: j['sku'] as String,
        producto: j['producto'] as String,
        talla: j['talla'] as String,
        color: j['color'] as String,
        cantidad: aEntero(j['cantidad']),
        cantidadVendida: aEntero(j['cantidad_vendida']),
        precioUnitario: aDouble(j['precio_unitario']),
      );
}

class DevolucionOut {
  DevolucionOut({
    required this.id,
    required this.ventaId,
    required this.ventaNumero,
    required this.ventaTotal,
    required this.sucursalId,
    required this.sucursal,
    required this.cliente,
    required this.motivo,
    required this.montoDevuelto,
    required this.estado,
    required this.fecha,
    required this.registradaPor,
    required this.resueltaPor,
    required this.resueltaEn,
    required this.motivoRechazo,
    required this.lineas,
    required this.unidades,
  });

  final String id;
  final String ventaId;
  final String ventaNumero;
  final double ventaTotal;
  final String sucursalId;
  final String sucursal;
  final String? cliente;
  final String motivo;
  final double montoDevuelto;
  final String estado;
  final String fecha;
  final String? registradaPor;
  final String? resueltaPor;
  final String? resueltaEn;
  final String? motivoRechazo;
  final int lineas;
  final int unidades;

  bool get solicitada => estado == 'SOLICITADA';

  factory DevolucionOut.desdeJson(Map<String, dynamic> j) => DevolucionOut(
        id: j['id'] as String,
        ventaId: j['venta_id'] as String,
        ventaNumero: j['venta_numero'] as String,
        ventaTotal: aDouble(j['venta_total']),
        sucursalId: j['sucursal_id'] as String,
        sucursal: j['sucursal'] as String,
        cliente: j['cliente'] as String?,
        motivo: j['motivo'] as String,
        montoDevuelto: aDouble(j['monto_devuelto']),
        estado: j['estado'] as String,
        fecha: j['fecha'] as String,
        registradaPor: j['registrada_por'] as String?,
        resueltaPor: j['resuelta_por'] as String?,
        resueltaEn: j['resuelta_en'] as String?,
        motivoRechazo: j['motivo_rechazo'] as String?,
        lineas: aEntero(j['lineas']),
        unidades: aEntero(j['unidades']),
      );
}

class DevolucionDetalleOut extends DevolucionOut {
  DevolucionDetalleOut({
    required super.id,
    required super.ventaId,
    required super.ventaNumero,
    required super.ventaTotal,
    required super.sucursalId,
    required super.sucursal,
    required super.cliente,
    required super.motivo,
    required super.montoDevuelto,
    required super.estado,
    required super.fecha,
    required super.registradaPor,
    required super.resueltaPor,
    required super.resueltaEn,
    required super.motivoRechazo,
    required super.lineas,
    required super.unidades,
    required this.detalle,
    required this.pagoReembolsado,
  });

  final List<DetalleDevolucionOut> detalle;
  final bool pagoReembolsado;

  factory DevolucionDetalleOut.desdeJson(Map<String, dynamic> j) {
    final base = DevolucionOut.desdeJson(j);
    return DevolucionDetalleOut(
      id: base.id,
      ventaId: base.ventaId,
      ventaNumero: base.ventaNumero,
      ventaTotal: base.ventaTotal,
      sucursalId: base.sucursalId,
      sucursal: base.sucursal,
      cliente: base.cliente,
      motivo: base.motivo,
      montoDevuelto: base.montoDevuelto,
      estado: base.estado,
      fecha: base.fecha,
      registradaPor: base.registradaPor,
      resueltaPor: base.resueltaPor,
      resueltaEn: base.resueltaEn,
      motivoRechazo: base.motivoRechazo,
      lineas: base.lineas,
      unidades: base.unidades,
      detalle: comoLista(j['detalle']).map(DetalleDevolucionOut.desdeJson).toList(),
      pagoReembolsado: j['pago_reembolsado'] as bool? ?? false,
    );
  }
}

/// Devoluciones de ventas: registrar (sobre una venta PAGADA/ENTREGADA, con lineas y
/// cantidades), aprobar (reingresa stock) o rechazar (con motivo). El backend nunca toca
/// inventario directo, lo hace el trigger `tg_devolucion_stock`.
class DevolucionesService {
  Future<List<DevolucionOut>> listar({String? estado, String? venta}) async {
    final respuesta = await api.get('/devoluciones', query: {
      'estado': estado,
      'venta': venta,
    });
    return comoLista(respuesta).map(DevolucionOut.desdeJson).toList();
  }

  Future<VentaDevolvibleOut> buscarVenta(String numero) async {
    final respuesta = await api.get('/devoluciones/venta', query: {'numero': numero});
    return VentaDevolvibleOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<DevolucionDetalleOut> obtener(String devolucionId) async {
    final respuesta = await api.get('/devoluciones/$devolucionId');
    return DevolucionDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<DevolucionDetalleOut> registrar({
    required String ventaId,
    required String motivo,
    required List<MapEntry<String, int>> lineas,
  }) async {
    final respuesta = await api.post('/devoluciones', cuerpo: {
      'venta_id': ventaId,
      'motivo': motivo,
      'lineas': lineas
          .map((l) => {'venta_detalle_id': l.key, 'cantidad': l.value})
          .toList(),
    });
    return DevolucionDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<DevolucionDetalleOut> aprobar(String devolucionId) async {
    final respuesta = await api.post('/devoluciones/$devolucionId/aprobar');
    return DevolucionDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<DevolucionDetalleOut> rechazar(String devolucionId, String motivo) async {
    final respuesta = await api.post('/devoluciones/$devolucionId/rechazar', cuerpo: {
      'motivo': motivo,
    });
    return DevolucionDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }
}

final devolucionesService = DevolucionesService();
