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
    required this.origen,
    required this.destino,
    required this.ruta,
    required this.rutaProveedor,
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

  /// Mapa del carrito, todo en [latitud, longitud]: sucursal, domicilio y por donde iria el
  /// delivery. Aproximado (lo reparte un servicio externo); no cambia lo que se cobra.
  final List<double> origen;
  final List<double> destino;
  final List<List<double>> ruta;

  /// ORS, OSRM o LINEA_RECTA (ningun servicio de rutas respondio).
  final String rutaProveedor;

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
        origen: _punto(j['origen']),
        destino: _punto(j['destino']),
        ruta: ((j['ruta'] as List?) ?? const []).map(_punto).toList(),
        rutaProveedor: j['ruta_proveedor'] as String? ?? 'LINEA_RECTA',
      );

  static List<double> _punto(dynamic p) => (p as List).map(aDouble).toList();
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
