import '../../api.dart';

/// Devoluciones e intercambios (PENDIENTES 10). Espejo manual de
/// `backend/app/modules/operacion_comercial/devoluciones/schemas.py`.
///
/// - DEVOLUCION: vuelve la prenda y vuelve la plata.
/// - INTERCAMBIO (motivo TALLA/COLOR): otra talla/color de la misma prenda; lo devuelto es credito
///   y se cobra o se devuelve la diferencia de precio.
/// Mismas reglas para los dos: 3 dias desde la compra, una sola por compra, hasta 3 prendas.
/// Origen CAJA (la registra el personal) u ONLINE (la pide la clienta desde Mis compras, la
/// sucursal la acepta y se concreta en caja cuando llega, como una reserva).
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
    this.maxUnidades = 3,
    this.solicitudVigente,
    this.esVentaDeCambio = false,
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
  final String plazoVenceEn;
  final bool fueraDePlazo;
  final String? reintegroMetodo;
  final List<LineaVentaOut> lineas;
  final String? cambioVenceEn;
  final bool fueraDePlazoCambio;

  /// tope de prendas por compra
  final int maxUnidades;

  /// numero de la devolucion/intercambio que ya tiene la compra (una sola por compra)
  final String? solicitudVigente;

  /// la compra salio de un intercambio: no se devuelve de nuevo
  final bool esVentaDeCambio;

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
        maxUnidades: aEntero(j['max_unidades'] ?? 3),
        solicitudVigente: j['solicitud_vigente'] as String?,
        esVentaDeCambio: j['es_venta_de_cambio'] as bool? ?? false,
      );
}

/// Otra talla/color de la misma prenda con su precio de lista (sin IVA) y su disponible.
class VarianteCambioOut {
  VarianteCambioOut({
    required this.varianteId,
    required this.sku,
    required this.talla,
    required this.color,
    required this.disponible,
    this.precio = 0,
  });

  final String varianteId;
  final String sku;
  final String talla;
  final String color;
  final int disponible;
  final double precio;

  factory VarianteCambioOut.desdeJson(Map<String, dynamic> j) => VarianteCambioOut(
        varianteId: j['variante_id'] as String,
        sku: j['sku'] as String,
        talla: j['talla'] as String,
        color: j['color'] as String,
        disponible: aEntero(j['disponible']),
        precio: aDouble(j['precio']),
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

/// Motivos por tipo: TALLA/COLOR son intercambios, el resto devoluciones.
const motivosIntercambio = <String, String>{
  'TALLA': 'Otra talla',
  'COLOR': 'Otro color',
};
const motivosSoloDevolucion = <String, String>{
  'DEFECTO': 'Prenda con defecto',
  'NO_GUSTO': 'No le gusto',
  'OTRO': 'Otro motivo',
};
const motivosDevolucion = <String, String>{...motivosIntercambio, ...motivosSoloDevolucion};

Map<String, String> motivosDe(String tipo) =>
    tipo == 'INTERCAMBIO' ? motivosIntercambio : motivosSoloDevolucion;

const estadosDevolucion = <String, String>{
  'SOLICITADA': 'Por aceptar',
  'CONFIRMADA': 'Aceptada, espera visita',
  'APROBADA': 'Realizada',
  'RECHAZADA': 'Rechazada',
  'CANCELADA': 'Cancelada',
  'EXPIRADA': 'Vencida',
};

/// Como vuelve la plata: por donde entro. EFECTIVO y QR salen en efectivo desde la caja.
const comoSeReintegra = <String, String>{
  'STRIPE': 'a la tarjeta (Stripe)',
  'EFECTIVO': 'en efectivo, desde la caja',
  'QR': 'en efectivo, desde la caja',
  'TARJETA': 'a la tarjeta (fuera del sistema)',
  'TRANSFERENCIA': 'por transferencia (fuera del sistema)',
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
    this.precioSolicitado,
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

  /// intercambio: lo que se lleva la clienta y su precio de lista pactado
  final String? tallaSolicitada;
  final String? colorSolicitado;
  final double? precioSolicitado;

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
        precioSolicitado: j['precio_solicitado'] == null ? null : aDouble(j['precio_solicitado']),
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
    this.tipo = 'DEVOLUCION',
    this.origen = 'CAJA',
    this.montoCambio = 0,
    this.diferencia = 0,
    this.montoReintegrado = 0,
    this.diferenciaCobrada = 0,
    this.diferenciaMetodo,
    this.fechaVisita,
    this.horaVisita,
    this.conEtiqueta = true,
    this.sinUso = true,
    this.conComprobante = true,
  });

  final String id;
  final String ventaId;
  final String ventaNumero;
  final double ventaTotal;
  final String sucursalId;
  final String sucursal;
  final String? cliente;
  final String motivo;

  /// lo que vale lo devuelto (credito en un intercambio); estimado hasta concretarla
  final double montoDevuelto;
  final String estado;
  final String fecha;
  final String? registradaPor;
  final String? resueltaPor;
  final String? resueltaEn;
  final String? motivoRechazo;
  final int lineas;
  final int unidades;

  /// Se fija al aprobar: STRIPE, EFECTIVO, QR (los dos desde la caja), TARJETA o TRANSFERENCIA.
  final String? reintegroMetodo;
  final String? reintegroReferencia;

  /// intercambio: la venta con las prendas nuevas, armada al concretarlo
  final String? ventaCambioId;
  final String? ventaCambioNumero;
  final String numero;
  final String motivoTipo;

  /// DEVOLUCION | INTERCAMBIO
  final String tipo;

  /// CAJA | ONLINE
  final String origen;

  /// lo que valen las prendas nuevas (con IVA)
  final double montoCambio;

  /// montoCambio - montoDevuelto: > 0 la clienta paga, < 0 se le devuelve
  final double diferencia;

  /// lo que efectivamente volvio a la clienta
  final double montoReintegrado;
  final double diferenciaCobrada;
  final String? diferenciaMetodo;
  final String? fechaVisita;
  final String? horaVisita;
  final bool conEtiqueta;
  final bool sinUso;
  final bool conComprobante;

  bool get esIntercambio => tipo == 'INTERCAMBIO';
  bool get enTramite => estado == 'SOLICITADA' || estado == 'CONFIRMADA';
  bool get solicitada => estado == 'SOLICITADA';

  /// "dd/mm hh:mm" de la visita, o '' si no tiene
  String get visita {
    final f = fechaVisita;
    if (f == null) return '';
    final partes = f.split('-');
    final hora = (horaVisita ?? '').length >= 5 ? horaVisita!.substring(0, 5) : '';
    return partes.length == 3 ? '${partes[2]}/${partes[1]} $hora' : f;
  }

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
        tipo: j['tipo'] as String? ?? 'DEVOLUCION',
        origen: j['origen'] as String? ?? 'CAJA',
        montoCambio: aDouble(j['monto_cambio'] ?? 0),
        diferencia: aDouble(j['diferencia'] ?? 0),
        montoReintegrado: aDouble(j['monto_reintegrado'] ?? 0),
        diferenciaCobrada: aDouble(j['diferencia_cobrada'] ?? 0),
        diferenciaMetodo: j['diferencia_metodo'] as String?,
        fechaVisita: j['fecha_visita'] as String?,
        horaVisita: j['hora_visita'] as String?,
        conEtiqueta: j['con_etiqueta'] as bool? ?? true,
        sinUso: j['sin_uso'] as bool? ?? true,
        conComprobante: j['con_comprobante'] as bool? ?? true,
      );
}

/// La devolucion con su detalle. Se arma reusando el json de la cabecera.
class DevolucionDetalleOut extends DevolucionOut {
  DevolucionDetalleOut._(DevolucionOut b, this.detalle, this.pagoReembolsado)
      : super(
          id: b.id,
          ventaId: b.ventaId,
          ventaNumero: b.ventaNumero,
          ventaTotal: b.ventaTotal,
          sucursalId: b.sucursalId,
          sucursal: b.sucursal,
          cliente: b.cliente,
          motivo: b.motivo,
          montoDevuelto: b.montoDevuelto,
          estado: b.estado,
          fecha: b.fecha,
          registradaPor: b.registradaPor,
          resueltaPor: b.resueltaPor,
          resueltaEn: b.resueltaEn,
          motivoRechazo: b.motivoRechazo,
          lineas: b.lineas,
          unidades: b.unidades,
          reintegroMetodo: b.reintegroMetodo,
          reintegroReferencia: b.reintegroReferencia,
          ventaCambioId: b.ventaCambioId,
          ventaCambioNumero: b.ventaCambioNumero,
          numero: b.numero,
          motivoTipo: b.motivoTipo,
          tipo: b.tipo,
          origen: b.origen,
          montoCambio: b.montoCambio,
          diferencia: b.diferencia,
          montoReintegrado: b.montoReintegrado,
          diferenciaCobrada: b.diferenciaCobrada,
          diferenciaMetodo: b.diferenciaMetodo,
          fechaVisita: b.fechaVisita,
          horaVisita: b.horaVisita,
          conEtiqueta: b.conEtiqueta,
          sinUso: b.sinUso,
          conComprobante: b.conComprobante,
        );

  final List<DetalleDevolucionOut> detalle;
  final bool pagoReembolsado;

  factory DevolucionDetalleOut.desdeJson(Map<String, dynamic> j) => DevolucionDetalleOut._(
        DevolucionOut.desdeJson(j),
        comoLista(j['detalle']).map(DetalleDevolucionOut.desdeJson).toList(),
        j['pago_reembolsado'] as bool? ?? false,
      );
}

/// Solicitudes que esperan al personal (lo muestra Caja).
class PendientesDevolucion {
  PendientesDevolucion(this.porAceptar, this.porConcretar);
  final int porAceptar;
  final int porConcretar;
  int get total => porAceptar + porConcretar;
}

/// Lado del personal: registrar en caja, aceptar solicitudes online, concretar o rechazar. El
/// backend nunca toca inventario directo: lo hace el trigger `tg_devolucion_stock`.
class DevolucionesService {
  Future<List<DevolucionOut>> listar({
    String? tipo,
    String? estado,
    String? venta,
    String? motivoTipo,
    String? origen,
  }) async {
    final respuesta = await api.get('/devoluciones', query: {
      'tipo': tipo,
      'estado': estado,
      'venta': venta,
      'motivo_tipo': motivoTipo,
      'origen': origen,
    });
    return comoLista(respuesta).map(DevolucionOut.desdeJson).toList();
  }

  Future<PendientesDevolucion> pendientes() async {
    final r = await api.get('/devoluciones/pendientes') as Map<String, dynamic>;
    return PendientesDevolucion(aEntero(r['por_aceptar']), aEntero(r['por_concretar']));
  }

  Future<VentaDevolvibleOut> buscarVenta(String numero) async {
    final respuesta = await api.get('/devoluciones/venta', query: {'numero': numero});
    return VentaDevolvibleOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<DevolucionDetalleOut> obtener(String devolucionId) async {
    final respuesta = await api.get('/devoluciones/$devolucionId');
    return DevolucionDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  /// [solicitadas]: venta_detalle_id -> variante que se lleva la clienta (solo intercambio).
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

  /// Acepta una solicitud online: la sucursal espera a la clienta.
  Future<DevolucionDetalleOut> confirmar(String devolucionId) async {
    final respuesta = await api.post('/devoluciones/$devolucionId/confirmar');
    return DevolucionDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  /// Concreta en caja. [diferenciaMetodo]: EFECTIVO, TARJETA o QR si la clienta paga diferencia.
  Future<DevolucionDetalleOut> aprobar(
    String devolucionId, {
    bool? conEtiqueta,
    bool? sinUso,
    bool? conComprobante,
    String? diferenciaMetodo,
  }) async {
    final respuesta = await api.post('/devoluciones/$devolucionId/aprobar', cuerpo: {
      'con_etiqueta': conEtiqueta,
      'sin_uso': sinUso,
      'con_comprobante': conComprobante,
      'diferencia_metodo': diferenciaMetodo,
    });
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
}

final devolucionesService = DevolucionesService();

// --- lado de la clienta (Mis devoluciones) ------------------------------------------------------

class LineaClienteOut {
  LineaClienteOut({
    required this.ventaDetalleId,
    required this.varianteId,
    required this.producto,
    required this.talla,
    required this.color,
    required this.cantidadVendida,
    required this.devolvible,
    required this.precioUnitario,
    required this.reembolsoUnitario,
    required this.variantesCambio,
  });

  final String ventaDetalleId;
  final String varianteId;
  final String producto;
  final String talla;
  final String color;
  final int cantidadVendida;
  final int devolvible;
  final double precioUnitario;

  /// lo que vale cada unidad devuelta (con IVA y descuento)
  final double reembolsoUnitario;
  final List<VarianteCambioOut> variantesCambio;

  factory LineaClienteOut.desdeJson(Map<String, dynamic> j) => LineaClienteOut(
        ventaDetalleId: j['venta_detalle_id'] as String,
        varianteId: j['variante_id'] as String,
        producto: j['producto'] as String,
        talla: j['talla'] as String,
        color: j['color'] as String,
        cantidadVendida: aEntero(j['cantidad_vendida']),
        devolvible: aEntero(j['devolvible']),
        precioUnitario: aDouble(j['precio_unitario']),
        reembolsoUnitario: aDouble(j['reembolso_unitario']),
        variantesCambio: comoLista(j['variantes_cambio']).map(VarianteCambioOut.desdeJson).toList(),
      );
}

class OpcionesDevolucionOut {
  OpcionesDevolucionOut({
    required this.ventaId,
    required this.numero,
    required this.sucursal,
    required this.sucursalDireccion,
    required this.horaApertura,
    required this.horaCierre,
    required this.plazoVenceEn,
    required this.maxUnidades,
    required this.ivaTasa,
    required this.reintegroMetodo,
    required this.puedeSolicitar,
    required this.motivoNo,
    required this.lineas,
  });

  final String ventaId;
  final String numero;
  final String sucursal;
  final String? sucursalDireccion;
  final String? horaApertura;
  final String? horaCierre;
  final DateTime plazoVenceEn;
  final int maxUnidades;
  final double ivaTasa;
  final String? reintegroMetodo;
  final bool puedeSolicitar;
  final String? motivoNo;
  final List<LineaClienteOut> lineas;

  factory OpcionesDevolucionOut.desdeJson(Map<String, dynamic> j) => OpcionesDevolucionOut(
        ventaId: j['venta_id'] as String,
        numero: j['numero'] as String,
        sucursal: j['sucursal'] as String,
        sucursalDireccion: j['sucursal_direccion'] as String?,
        horaApertura: j['hora_apertura'] as String?,
        horaCierre: j['hora_cierre'] as String?,
        plazoVenceEn: DateTime.parse(j['plazo_vence_en'] as String).toLocal(),
        maxUnidades: aEntero(j['max_unidades']),
        ivaTasa: aDouble(j['iva_tasa']),
        reintegroMetodo: j['reintegro_metodo'] as String?,
        puedeSolicitar: j['puede_solicitar'] as bool? ?? false,
        motivoNo: j['motivo_no'] as String?,
        lineas: comoLista(j['lineas']).map(LineaClienteOut.desdeJson).toList(),
      );
}

/// La clienta pide la devolucion o el intercambio de una compra suya (como una reserva).
class MisDevolucionesService {
  Future<List<DevolucionDetalleOut>> listar() async {
    final respuesta = await api.get('/mis-devoluciones');
    return comoLista(respuesta).map(DevolucionDetalleOut.desdeJson).toList();
  }

  Future<OpcionesDevolucionOut> opciones(String ventaId) async {
    final respuesta = await api.get('/mis-devoluciones/venta/$ventaId');
    return OpcionesDevolucionOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<DevolucionDetalleOut> solicitar({
    required String ventaId,
    required String motivoTipo,
    required String motivo,
    required String fechaVisita,
    required String horaVisita,
    required List<MapEntry<String, int>> lineas,
    Map<String, String> solicitadas = const {},
  }) async {
    final respuesta = await api.post('/mis-devoluciones', cuerpo: {
      'venta_id': ventaId,
      'motivo_tipo': motivoTipo,
      'motivo': motivo,
      'fecha_visita': fechaVisita,
      'hora_visita': horaVisita,
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

  Future<DevolucionDetalleOut> cancelar(String id) async {
    final respuesta = await api.post('/mis-devoluciones/$id/cancelar');
    return DevolucionDetalleOut.desdeJson(respuesta as Map<String, dynamic>);
  }
}

final misDevolucionesService = MisDevolucionesService();
