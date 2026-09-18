import '../api.dart';

/// Espejo manual de `backend/app/modules/direcciones/schemas.py` (CU20).
class DireccionOut {
  const DireccionOut({
    required this.id,
    required this.alias,
    required this.ciudad,
    required this.direccion,
    required this.referencia,
    required this.latitud,
    required this.longitud,
    required this.esPrincipal,
  });

  final String id;
  final String alias;
  final String ciudad;
  final String direccion;
  final String? referencia;
  final double? latitud;
  final double? longitud;
  final bool esPrincipal;

  /// Sin coordenadas no se puede cotizar el delivery.
  bool get tienePunto => latitud != null && longitud != null;

  factory DireccionOut.desdeJson(Map<String, dynamic> j) => DireccionOut(
        id: j['id'] as String,
        alias: j['alias'] as String,
        ciudad: j['ciudad'] as String,
        direccion: j['direccion'] as String,
        referencia: j['referencia'] as String?,
        latitud: aDoubleNulo(j['latitud']),
        longitud: aDoubleNulo(j['longitud']),
        esPrincipal: j['es_principal'] as bool? ?? false,
      );
}

class DireccionIn {
  const DireccionIn({
    required this.alias,
    required this.ciudad,
    required this.direccion,
    this.referencia,
    this.latitud,
    this.longitud,
    this.esPrincipal = false,
  });

  final String alias;
  final String ciudad;
  final String direccion;
  final String? referencia;
  final double? latitud;
  final double? longitud;
  final bool esPrincipal;

  Map<String, dynamic> aJson() => {
        'alias': alias,
        'ciudad': ciudad,
        'direccion': direccion,
        'referencia': (referencia?.isEmpty ?? true) ? null : referencia,
        'latitud': latitud,
        'longitud': longitud,
        'es_principal': esPrincipal,
      };
}

class SugerenciaDireccion {
  const SugerenciaDireccion({
    required this.etiqueta,
    required this.latitud,
    required this.longitud,
    required this.ciudad,
  });

  final String etiqueta;
  final double latitud;
  final double longitud;
  final String? ciudad;

  factory SugerenciaDireccion.desdeJson(Map<String, dynamic> j) => SugerenciaDireccion(
        etiqueta: j['etiqueta'] as String,
        latitud: aDouble(j['latitud']),
        longitud: aDouble(j['longitud']),
        ciudad: j['ciudad'] as String?,
      );
}

class BusquedaDireccion {
  const BusquedaDireccion({required this.geocodificadorDisponible, required this.resultados});

  /// false cuando el backend no tiene ORS_API_KEY: hay que marcar el punto a mano.
  final bool geocodificadorDisponible;
  final List<SugerenciaDireccion> resultados;

  factory BusquedaDireccion.desdeJson(Map<String, dynamic> j) => BusquedaDireccion(
        geocodificadorDisponible: j['geocodificador_disponible'] as bool? ?? false,
        resultados: comoLista(j['resultados']).map(SugerenciaDireccion.desdeJson).toList(),
      );
}

/// Las mismas ciudades del ENUM `ciudad_bo` de db/01_schema.sql.
const ciudadesBolivia = <String, String>{
  'SANTA_CRUZ': 'Santa Cruz',
  'LA_PAZ': 'La Paz',
  'EL_ALTO': 'El Alto',
  'COCHABAMBA': 'Cochabamba',
  'SUCRE': 'Sucre',
  'ORURO': 'Oruro',
  'POTOSI': 'Potosi',
  'TARIJA': 'Tarija',
  'TRINIDAD': 'Trinidad',
  'COBIJA': 'Cobija',
};
