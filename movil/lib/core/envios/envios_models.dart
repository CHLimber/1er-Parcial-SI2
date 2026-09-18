import '../api.dart';

/// Espejo manual de `backend/app/modules/envios/schemas.py` y `admin_schemas.py` (CU20).
///
/// El reparto lo hace un servicio de delivery externo, no personal de FashionStore: la
/// sucursal solo marca cuando el paquete SALE hacia ese servicio (DESPACHADO) y cuando el
/// servicio confirma que LLEGO (ENTREGADO) o que fallo (FALLIDO).

class CotizacionEnvio {
  const CotizacionEnvio({
    required this.distanciaKm,
    required this.duracionMin,
    required this.proveedor,
    required this.costo,
    required this.esGratis,
    required this.dentroCobertura,
    required this.radioKm,
    required this.tarifaBase,
    required this.precioKm,
    required this.gratisDesde,
  });

  final double distanciaKm;
  final int duracionMin;

  /// ORS (openrouteservice) o HAVERSINE (estimacion propia de respaldo).
  final String proveedor;
  final double costo;
  final bool esGratis;
  final bool dentroCobertura;
  final double radioKm;
  final double tarifaBase;
  final double precioKm;
  final double gratisDesde;

  factory CotizacionEnvio.desdeJson(Map<String, dynamic> j) => CotizacionEnvio(
        distanciaKm: aDouble(j['distancia_km']),
        duracionMin: aEntero(j['duracion_min']),
        proveedor: j['proveedor'] as String,
        costo: aDouble(j['costo']),
        esGratis: j['es_gratis'] as bool? ?? false,
        dentroCobertura: j['dentro_cobertura'] as bool? ?? false,
        radioKm: aDouble(j['radio_km']),
        tarifaBase: aDouble(j['tarifa_base']),
        precioKm: aDouble(j['precio_km']),
        gratisDesde: aDouble(j['gratis_desde']),
      );
}

class EventoEnvio {
  const EventoEnvio({
    required this.estado,
    required this.nota,
    required this.fecha,
    this.usuario,
  });

  final String estado;
  final String? nota;
  final DateTime fecha;
  final String? usuario;

  factory EventoEnvio.desdeJson(Map<String, dynamic> j) => EventoEnvio(
        estado: j['estado'] as String,
        nota: j['nota'] as String?,
        fecha: DateTime.parse(j['fecha'] as String).toLocal(),
        usuario: j['usuario'] as String?,
      );
}

/// Seguimiento que ve la clienta.
class EnvioOut {
  const EnvioOut({
    required this.id,
    required this.ventaId,
    required this.numeroVenta,
    required this.estado,
    required this.sucursal,
    required this.ciudad,
    required this.direccion,
    required this.referencia,
    required this.distanciaKm,
    required this.duracionMin,
    required this.costo,
    required this.observacion,
    required this.eventos,
  });

  final String id;
  final String ventaId;
  final String numeroVenta;
  final String estado;
  final String sucursal;
  final String ciudad;
  final String direccion;
  final String? referencia;
  final double distanciaKm;
  final int duracionMin;
  final double costo;
  final String? observacion;
  final List<EventoEnvio> eventos;

  factory EnvioOut.desdeJson(Map<String, dynamic> j) => EnvioOut(
        id: j['id'] as String,
        ventaId: j['venta_id'] as String,
        numeroVenta: j['numero_venta'] as String,
        estado: j['estado'] as String,
        sucursal: j['sucursal'] as String,
        ciudad: j['ciudad'] as String,
        direccion: j['direccion'] as String,
        referencia: j['referencia'] as String?,
        distanciaKm: aDouble(j['distancia_km']),
        duracionMin: aEntero(j['duracion_min']),
        costo: aDouble(j['costo']),
        observacion: j['observacion'] as String?,
        eventos: comoLista(j['eventos']).map(EventoEnvio.desdeJson).toList(),
      );
}

/// Envio como lo ve el panel de despacho.
class EnvioAdminOut {
  const EnvioAdminOut({
    required this.id,
    required this.ventaId,
    required this.numeroVenta,
    required this.estado,
    required this.sucursalId,
    required this.sucursal,
    required this.cliente,
    required this.clienteTelefono,
    required this.ciudad,
    required this.direccion,
    required this.referencia,
    required this.latitud,
    required this.longitud,
    required this.distanciaKm,
    required this.duracionMin,
    required this.costo,
    required this.proveedorRuteo,
    required this.totalVenta,
    required this.observacion,
  });

  final String id;
  final String ventaId;
  final String numeroVenta;
  final String estado;
  final String sucursalId;
  final String sucursal;
  final String cliente;
  final String? clienteTelefono;
  final String ciudad;
  final String direccion;
  final String? referencia;
  final double? latitud;
  final double? longitud;
  final double distanciaKm;
  final int duracionMin;
  final double costo;
  final String proveedorRuteo;
  final double totalVenta;
  final String? observacion;

  factory EnvioAdminOut.desdeJson(Map<String, dynamic> j) => EnvioAdminOut(
        id: j['id'] as String,
        ventaId: j['venta_id'] as String,
        numeroVenta: j['numero_venta'] as String,
        estado: j['estado'] as String,
        sucursalId: j['sucursal_id'] as String,
        sucursal: j['sucursal'] as String,
        cliente: j['cliente'] as String,
        clienteTelefono: j['cliente_telefono'] as String?,
        ciudad: j['ciudad'] as String,
        direccion: j['direccion'] as String,
        referencia: j['referencia'] as String?,
        latitud: aDoubleNulo(j['latitud']),
        longitud: aDoubleNulo(j['longitud']),
        distanciaKm: aDouble(j['distancia_km']),
        duracionMin: aEntero(j['duracion_min']),
        costo: aDouble(j['costo']),
        proveedorRuteo: j['proveedor_ruteo'] as String,
        totalVenta: aDouble(j['total_venta']),
        observacion: j['observacion'] as String?,
      );
}

class ItemEnvio {
  const ItemEnvio({
    required this.producto,
    required this.sku,
    required this.talla,
    required this.color,
    required this.cantidad,
  });

  final String producto;
  final String sku;
  final String talla;
  final String color;
  final int cantidad;

  factory ItemEnvio.desdeJson(Map<String, dynamic> j) => ItemEnvio(
        producto: j['producto'] as String,
        sku: j['sku'] as String,
        talla: j['talla'] as String,
        color: j['color'] as String,
        cantidad: aEntero(j['cantidad']),
      );
}

class EnvioAdminDetalle {
  const EnvioAdminDetalle({
    required this.envio,
    required this.items,
    required this.eventos,
  });

  final EnvioAdminOut envio;
  final List<ItemEnvio> items;
  final List<EventoEnvio> eventos;

  factory EnvioAdminDetalle.desdeJson(Map<String, dynamic> j) => EnvioAdminDetalle(
        envio: EnvioAdminOut.desdeJson(j),
        items: comoLista(j['items']).map(ItemEnvio.desdeJson).toList(),
        eventos: comoLista(j['eventos']).map(EventoEnvio.desdeJson).toList(),
      );
}

class ResumenEnvios {
  const ResumenEnvios({
    required this.pendientes,
    required this.despachados,
    required this.entregadosHoy,
    required this.fallidos,
  });

  final int pendientes;
  final int despachados;
  final int entregadosHoy;
  final int fallidos;

  factory ResumenEnvios.desdeJson(Map<String, dynamic> j) => ResumenEnvios(
        pendientes: aEntero(j['pendientes']),
        despachados: aEntero(j['despachados']),
        entregadosHoy: aEntero(j['entregados_hoy']),
        fallidos: aEntero(j['fallidos']),
      );
}

/// Etiqueta en castellano de cada estado del envio.
String etiquetaEstadoEnvio(String estado) {
  switch (estado) {
    case 'PENDIENTE':
      return 'Pendiente';
    case 'DESPACHADO':
      return 'Despachado';
    case 'ENTREGADO':
      return 'Entregado';
    case 'FALLIDO':
      return 'No se pudo entregar';
    case 'CANCELADO':
      return 'Cancelado';
    default:
      return estado;
  }
}

/// Transiciones que ofrece la app; el backend las vuelve a validar.
const transicionesEnvio = <String, List<String>>{
  'PENDIENTE': ['DESPACHADO', 'CANCELADO'],
  'DESPACHADO': ['ENTREGADO', 'FALLIDO'],
  'FALLIDO': ['DESPACHADO', 'CANCELADO'],
  'ENTREGADO': <String>[],
  'CANCELADO': <String>[],
};
