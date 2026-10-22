import '../../api.dart';

/// Devoluciones de ventas (PENDIENTES 2.7/2.19.7). Espejo de
/// `backend/app/modules/devoluciones/schemas.py`. Registrar nace SOLICITADA y no mueve
/// stock; aprobar dispara `tg_devolucion_stock` (reingresa el stock, tipo DEVOLUCION) y
/// recalcula el monto a reintegrar; rechazar solo pide un motivo.
/// PENDIENTES 4.11: plazo desde la venta, reintegro segun como se pago (STRIPE por la API,
/// EFECTIVO desde la caja abierta, TARJETA/QR/TRANSFERENCIA fuera del sistema) y cambio de
/// prenda = devolucion aprobada + venta nueva en caja, vinculada con [vincularCambio].
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
    required this.plazoVenceEn,
    required this.fueraDePlazo,
    required this.reintegroMetodo,
    required this.lineas,
    this.cambioVenceEn,
    this.fueraDePlazoCambio = false,
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

  /// fecha de la venta + configuracion.devolucion_plazo_dias
  final String plazoVenceEn;

  /// true: registrar la devolucion responde 409
  final bool fueraDePlazo;
  final String? reintegroMetodo;
  final List<LineaVentaOut> lineas;

  /// Segundo parcial (5.8): cambio por talla/color, con su propio plazo (cambio_plazo_dias)
  final String? cambioVenceEn;
  final bool fueraDePlazoCambio;

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
        plazoVenceEn: j['plazo_vence_en'] as String,
        fueraDePlazo: j['fuera_de_plazo'] as bool? ?? false,
        reintegroMetodo: j['reintegro_metodo'] as String?,
        lineas: comoLista(j['lineas']).map(LineaVentaOut.desdeJson).toList(),
        cambioVenceEn: j['cambio_vence_en'] as String?,
        fueraDePlazoCambio: j['fuera_de_plazo_cambio'] as bool? ?? false,
      );
}

/// Otra talla/color de la misma prenda con su disponible en la sucursal (cambio por talla).
class VarianteCambioOut {
  VarianteCambioOut({
    required this.varianteId,
    required this.sku,
    required this.talla,
    required this.color,
    required this.disponible,
  });

  final String varianteId;
  final String sku;
  final String talla;
  final String color;
  final int disponible;

  factory VarianteCambioOut.desdeJson(Map<String, dynamic> j) => VarianteCambioOut(
        varianteId: j['variante_id'] as String,
        sku: j['sku'] as String,
        talla: j['talla'] as String,
        color: j['color'] as String,
        disponible: aEntero(j['disponible']),
      );
}

/// Una fila de "que prendas solicitaron cambio en el mes" (PENDIENTES 5.10).
class CambioMesOut {
  CambioMesOut({
    required this.producto,
    required this.motivoTipo,
    required this.tallaOriginal,
    required this.colorOriginal,
    required this.tallaSolicitada,
    required this.colorSolicitado,
    required this.solicitudes,
    required this.unidades,
    required this.aprobadas,
    required this.pendientes,
    required this.rechazadas,
    required this.sucursales,
  });

  final String producto;
  final String motivoTipo;
  final String tallaOriginal;
  final String colorOriginal;
  final String? tallaSolicitada;
  final String? colorSolicitado;
  final int solicitudes;
  final int unidades;
  final int aprobadas;
  final int pendientes;
  final int rechazadas;
  final List<String> sucursales;

  factory CambioMesOut.desdeJson(Map<String, dynamic> j) => CambioMesOut(
        producto: j['producto'] as String,
        motivoTipo: j['motivo_tipo'] as String,
        tallaOriginal: j['talla_original'] as String,
        colorOriginal: j['color_original'] as String,
        tallaSolicitada: j['talla_solicitada'] as String?,
        colorSolicitado: j['color_solicitado'] as String?,
        solicitudes: aEntero(j['solicitudes']),
        unidades: aEntero(j['unidades']),
        aprobadas: aEntero(j['aprobadas']),
        pendientes: aEntero(j['pendientes']),
        rechazadas: aEntero(j['rechazadas']),
        sucursales: (j['sucursales'] as List? ?? const []).cast<String>(),
      );
}

/// Motivos de devolucion (PENDIENTES 5.8): TALLA/COLOR son cambios.
const motivosDevolucion = <String, String>{
  'TALLA': 'Cambio por talla',
  'COLOR': 'Cambio por color',
  'DEFECTO': 'Prenda con defecto',
  'NO_GUSTO': 'No le gusto',
  'OTRO': 'Otro motivo',
};

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
    this.tallaSolicitada,
    this.colorSolicitado,
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

  /// cambio por talla/color: lo que se lleva la clienta
  final String? tallaSolicitada;
  final String? colorSolicitado;

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
        tallaSolicitada: j['talla_solicitada'] as String?,
        colorSolicitado: j['color_solicitado'] as String?,
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
    this.reintegroMetodo,
    this.reintegroReferencia,
    this.ventaCambioId,
    this.ventaCambioNumero,
    this.numero = '',
    this.motivoTipo = 'OTRO',
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

  /// Se fija al aprobar: STRIPE, EFECTIVO, TARJETA, QR o TRANSFERENCIA.
  final String? reintegroMetodo;

  /// Id del reembolso en Stripe (re_...).
  final String? reintegroReferencia;
  final String? ventaCambioId;
  final String? ventaCambioNumero;

  /// numero de la nota de devolucion (NDV-000001) y motivo estructurado (Segundo parcial)
  final String numero;
  final String motivoTipo;

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
        reintegroMetodo: j['reintegro_metodo'] as String?,
        reintegroReferencia: j['reintegro_referencia'] as String?,
        ventaCambioId: j['venta_cambio_id'] as String?,
        ventaCambioNumero: j['venta_cambio_numero'] as String?,
        numero: j['numero'] as String? ?? '',
        motivoTipo: j['motivo_tipo'] as String? ?? 'OTRO',
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
    super.reintegroMetodo,
    super.reintegroReferencia,
    super.ventaCambioId,
    super.ventaCambioNumero,
    super.numero,
    super.motivoTipo,
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
      reintegroMetodo: base.reintegroMetodo,
      reintegroReferencia: base.reintegroReferencia,
      ventaCambioId: base.ventaCambioId,
      ventaCambioNumero: base.ventaCambioNumero,
      numero: base.numero,
      motivoTipo: base.motivoTipo,
      detalle: comoLista(j['detalle']).map(DetalleDevolucionOut.desdeJson).toList(),
      pagoReembolsado: j['pago_reembolsado'] as bool? ?? false,
    );
  }
}

/// Devoluciones de ventas: registrar (sobre una venta PAGADA/ENTREGADA, con lineas y
/// cantidades), aprobar (reingresa stock) o rechazar (con motivo). El backend nunca toca
/// inventario directo, lo hace el trigger `tg_devolucion_stock`.
class DevolucionesService {
  Future<List<DevolucionOut>> listar({String? estado, String? venta, String? motivoTipo}) async {
    final respuesta = await api.get('/devoluciones', query: {
      'estado': estado,
      'venta': venta,
      'motivo_tipo': motivoTipo,
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

  /// [solicitadas]: venta_detalle_id -> variante que se lleva la clienta (solo TALLA/COLOR).
  Future<DevolucionDetalleOut> registrar({
    required String ventaId,
    required String motivo,
    required List<MapEntry<String, int>> lineas,
    String motivoTipo = 'OTRO',
    bool conEtiqueta = true,
    bool sinUso = true,
    bool conComprobante = true,
    Map<String, String> solicitadas = const {},
  }) async {
    final respuesta = await api.post('/devoluciones', cuerpo: {
      'venta_id': ventaId,
      'motivo_tipo': motivoTipo,
      'motivo': motivo,
      'con_etiqueta': conEtiqueta,
      'sin_uso': sinUso,
      'con_comprobante': conComprobante,
      'lineas': lineas
          .map((l) => {
                'venta_detalle_id': l.key,
                'cantidad': l.value,
                'variante_solicitada_id': solicitadas[l.key],
              })
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

  Future<List<VarianteCambioOut>> variantesCambio(String varianteId, String sucursalId) async {
    final respuesta = await api.get('/devoluciones/variantes-cambio', query: {
      'variante_id': varianteId,
      'sucursal_id': sucursalId,
    });
    return comoLista(respuesta).map(VarianteCambioOut.desdeJson).toList();
  }

  /// Que prendas solicitaron cambio en el mes (PENDIENTES 5.10).
  Future<List<CambioMesOut>> cambiosDelMes(int anio, int mes) async {
    final respuesta = await api.get('/devoluciones/cambios-mes', query: {'anio': anio, 'mes': mes});
    return comoLista((respuesta as Map<String, dynamic>)['filas']).map(CambioMesOut.desdeJson).toList();
  }

  /// Cambio de prenda: vincula la venta nueva (cobrada en caja) a una devolucion aprobada.
  Future<DevolucionDetalleOut> vincularCambio(String devolucionId, String ventaNumero) async {
    final respuesta = await api.post('/devoluciones/$devolucionId/cambio', cuerpo: {
      'venta_numero': ventaNumero,
    });
    return DevolucionDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }
}

final devolucionesService = DevolucionesService();
