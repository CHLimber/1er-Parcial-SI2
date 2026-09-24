import '../api.dart';

/// Espejo de `backend/app/modules/caja/schemas.py` (CU07).
class CajaOut {
  CajaOut({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.tieneSesionAbierta,
  });

  final String id;
  final String codigo;
  final String nombre;
  final bool tieneSesionAbierta;

  factory CajaOut.desdeJson(Map<String, dynamic> j) => CajaOut(
        id: j['id'] as String,
        codigo: j['codigo'] as String,
        nombre: j['nombre'] as String,
        tieneSesionAbierta: j['tiene_sesion_abierta'] as bool? ?? false,
      );
}

class SesionCajaOut {
  SesionCajaOut({
    required this.id,
    required this.cajaId,
    required this.cajaNombre,
    required this.abiertaEn,
    required this.montoInicial,
    required this.estado,
  });

  final String id;
  final String cajaId;
  final String cajaNombre;
  final DateTime? abiertaEn;
  final double montoInicial;
  final String estado;

  factory SesionCajaOut.desdeJson(Map<String, dynamic> j) => SesionCajaOut(
        id: j['id'] as String,
        cajaId: j['caja_id'] as String,
        cajaNombre: j['caja_nombre'] as String,
        abiertaEn: aFechaNula(j['abierta_en']),
        montoInicial: aDouble(j['monto_inicial']),
        estado: j['estado'] as String,
      );
}

/// Prenda encontrada por SKU o codigo de barras en el mostrador.
class VarianteBusquedaOut {
  VarianteBusquedaOut({
    required this.varianteId,
    required this.sku,
    required this.producto,
    required this.talla,
    required this.color,
    required this.precio,
    required this.disponible,
  });

  final String varianteId;
  final String sku;
  final String producto;
  final String talla;
  final String color;
  final double precio;
  final int disponible;

  factory VarianteBusquedaOut.desdeJson(Map<String, dynamic> j) => VarianteBusquedaOut(
        varianteId: j['variante_id'] as String,
        sku: j['sku'] as String,
        producto: j['producto'] as String,
        talla: j['talla'] as String,
        color: j['color'] as String,
        precio: aDouble(j['precio']),
        disponible: aEntero(j['disponible']),
      );
}

/// 2.19.1.b/c: prenda de un pedido online pendiente (lo que el cajero tiene que preparar).
class ItemPagoPendienteOut {
  ItemPagoPendienteOut({
    required this.sku,
    required this.producto,
    required this.talla,
    required this.color,
    required this.cantidad,
  });

  final String sku;
  final String producto;
  final String talla;
  final String color;
  final int cantidad;

  factory ItemPagoPendienteOut.desdeJson(Map<String, dynamic> j) => ItemPagoPendienteOut(
        sku: j['sku'] as String,
        producto: j['producto'] as String,
        talla: j['talla'] as String,
        color: j['color'] as String,
        cantidad: aEntero(j['cantidad']),
      );
}

/// 2.19.1.b/c: pedido online (EFECTIVO o QR) de la sucursal cuyo pago espera al cajero.
class PagoPorVerificarOut {
  PagoPorVerificarOut({
    required this.pagoId,
    required this.ventaId,
    required this.numero,
    required this.fecha,
    required this.cliente,
    required this.clienteEmail,
    required this.metodo,
    required this.entrega,
    required this.total,
    required this.costoEnvio,
    required this.informadoEn,
    required this.referenciaCliente,
    required this.carritoModificado,
    required this.items,
  });

  final String pagoId;
  final String ventaId;
  final String numero;
  final DateTime? fecha;
  final String cliente;
  final String clienteEmail;

  /// EFECTIVO o QR.
  final String metodo;
  final String entrega;
  final double total;
  final double costoEnvio;

  /// Solo QR: null = la clienta todavia no aviso que pago.
  final DateTime? informadoEn;
  final String? referenciaCliente;

  /// La clienta cambio su carrito despues del checkout: no se puede aprobar, solo rechazar.
  final bool carritoModificado;
  final List<ItemPagoPendienteOut> items;

  factory PagoPorVerificarOut.desdeJson(Map<String, dynamic> j) => PagoPorVerificarOut(
        pagoId: j['pago_id'] as String,
        ventaId: j['venta_id'] as String,
        numero: j['numero'] as String,
        fecha: aFechaNula(j['fecha']),
        cliente: j['cliente'] as String,
        clienteEmail: j['cliente_email'] as String,
        metodo: j['metodo'] as String,
        entrega: j['entrega'] as String,
        total: aDouble(j['total']),
        costoEnvio: aDouble(j['costo_envio']),
        informadoEn: aFechaNula(j['informado_en']),
        referenciaCliente: j['referencia_cliente'] as String?,
        carritoModificado: j['carrito_modificado'] as bool? ?? false,
        items: comoLista(j['items']).map(ItemPagoPendienteOut.desdeJson).toList(),
      );
}

/// CU07 (2.2): foto de la sesion abierta ANTES de declarar el cierre. monto_sistema es
/// lo que deberia haber en efectivo: monto_inicial + ventas cobradas en EFECTIVO (las de
/// TARJETA/QR/TRANSFERENCIA/PASARELA no tocan el cajon fisico).
class ArqueoOut {
  ArqueoOut({
    required this.sesionId,
    required this.montoInicial,
    required this.montoSistema,
    required this.cantidadVentas,
    required this.totalVentas,
    required this.porMetodo,
  });

  final String sesionId;
  final double montoInicial;
  final double montoSistema;
  final int cantidadVentas;
  final double totalVentas;
  final Map<String, double> porMetodo;

  factory ArqueoOut.desdeJson(Map<String, dynamic> j) => ArqueoOut(
        sesionId: j['sesion_id'] as String,
        montoInicial: aDouble(j['monto_inicial']),
        montoSistema: aDouble(j['monto_sistema']),
        cantidadVentas: aEntero(j['cantidad_ventas']),
        totalVentas: aDouble(j['total_ventas']),
        porMetodo: (j['por_metodo'] as Map<String, dynamic>? ?? const {})
            .map((clave, valor) => MapEntry(clave, aDouble(valor))),
      );
}

/// Resultado de POST /caja/cerrar: la sesion queda CERRADA y `diferencia` la calculo
/// Postgres solo (columna GENERATED = monto_declarado - monto_sistema).
class SesionCerradaOut {
  SesionCerradaOut({
    required this.id,
    required this.cajaId,
    required this.cajaNombre,
    required this.abiertaEn,
    required this.cerradaEn,
    required this.montoInicial,
    required this.montoSistema,
    required this.montoDeclarado,
    required this.diferencia,
    required this.estado,
  });

  final String id;
  final String cajaId;
  final String cajaNombre;
  final DateTime? abiertaEn;
  final DateTime? cerradaEn;
  final double montoInicial;
  final double montoSistema;
  final double montoDeclarado;
  final double diferencia;
  final String estado;

  factory SesionCerradaOut.desdeJson(Map<String, dynamic> j) => SesionCerradaOut(
        id: j['id'] as String,
        cajaId: j['caja_id'] as String,
        cajaNombre: j['caja_nombre'] as String,
        abiertaEn: aFechaNula(j['abierta_en']),
        cerradaEn: aFechaNula(j['cerrada_en']),
        montoInicial: aDouble(j['monto_inicial']),
        montoSistema: aDouble(j['monto_sistema']),
        montoDeclarado: aDouble(j['monto_declarado']),
        diferencia: aDouble(j['diferencia']),
        estado: j['estado'] as String,
      );
}

class ResolucionPagoOut {
  ResolucionPagoOut({
    required this.pagoId,
    required this.ventaId,
    required this.numero,
    required this.ventaEstado,
    required this.pagoEstado,
    required this.mensaje,
  });

  final String pagoId;
  final String ventaId;
  final String numero;
  final String ventaEstado;
  final String pagoEstado;
  final String mensaje;

  factory ResolucionPagoOut.desdeJson(Map<String, dynamic> j) => ResolucionPagoOut(
        pagoId: j['pago_id'] as String,
        ventaId: j['venta_id'] as String,
        numero: j['numero'] as String,
        ventaEstado: j['venta_estado'] as String,
        pagoEstado: j['pago_estado'] as String,
        mensaje: j['mensaje'] as String,
      );
}

/// CU07: sesion de caja del cajero. El backend exige sesion ABIERTA para POST /ventas/pos.
class CajaService {
  Future<List<CajaOut>> listarCajas() async {
    final respuesta = await api.get('/caja/cajas');
    return comoLista(respuesta).map(CajaOut.desdeJson).toList();
  }

  Future<SesionCajaOut?> sesionActual() async {
    final respuesta = await api.get('/caja/sesion-actual');
    if (respuesta == null) return null;
    return SesionCajaOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<SesionCajaOut> abrirSesion(String cajaId, double montoInicial) async {
    final respuesta = await api.post('/caja/abrir', cuerpo: {
      'caja_id': cajaId,
      'monto_inicial': montoInicial,
    });
    return SesionCajaOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<VarianteBusquedaOut> buscarVariante(String codigo) async {
    final respuesta = await api.get('/caja/buscar-variante', query: {'codigo': codigo});
    return VarianteBusquedaOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  /// 2.19.1.b/c: pedidos online en EFECTIVO o QR que esperan al cajero.
  Future<List<PagoPorVerificarOut>> listarPagosPendientes() async {
    final respuesta = await api.get('/caja/pagos-pendientes');
    return comoLista(respuesta).map(PagoPorVerificarOut.desdeJson).toList();
  }

  Future<ResolucionPagoOut> aprobarPago(String pagoId) async {
    final respuesta = await api.post('/caja/pagos/$pagoId/aprobar', cuerpo: <String, dynamic>{});
    return ResolucionPagoOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<ResolucionPagoOut> rechazarPago(String pagoId, {String? motivo}) async {
    final respuesta = await api.post('/caja/pagos/$pagoId/rechazar', cuerpo: {
      'motivo': (motivo?.trim().isEmpty ?? true) ? null : motivo!.trim(),
    });
    return ResolucionPagoOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  /// CU07 (2.2): arqueo de la sesion abierta, para que el cajero cuente el cajon antes
  /// de declarar el cierre.
  Future<ArqueoOut> obtenerArqueo() async {
    final respuesta = await api.get('/caja/arqueo');
    return ArqueoOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  /// CU07 (2.2): cierra la sesion abierta con lo que el cajero conto de verdad en el cajon.
  Future<SesionCerradaOut> cerrarSesion(double montoDeclarado) async {
    final respuesta = await api.post('/caja/cerrar', cuerpo: {
      'monto_declarado': montoDeclarado,
    });
    return SesionCerradaOut.desdeJson(respuesta as Map<String, dynamic>);
  }
}

final cajaService = CajaService();
