import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'errores.dart';
import 'operacion_sin_conexion/offline/base_local.dart';
import 'operacion_sin_conexion/offline/conexion_service.dart';

/// GET que se pueden mostrar sin red (PENDIENTES 5.3): se guardan en SQLite y, si la red falla,
/// se responde con lo guardado. Mismo criterio que CACHEABLES de offline.interceptor.ts (web).
final _cacheables = [
  RegExp(r'^/catalogo(/|$)'),
  RegExp(r'^/sucursales(/|$)'),
  RegExp(r'^/recomendaciones$'),
  RegExp(r'^/carrito$'),
  RegExp(r'^/reservas$'),
  RegExp(r'^/ventas$'),
  RegExp(r'^/notificaciones(/|$)'),
  RegExp(r'^/direcciones$'),
];

/// Escrituras que se encolan sin red y se mandan solas al volver (ConexionService.sincronizar).
const _encolables = {
  'POST /carrito/items': (
    'Agregar prenda al carrito',
    'Sin conexion: guardamos la prenda y la agregamos a tu carrito apenas vuelva la red.',
  ),
};

/// Cliente HTTP unico contra la API. Es el espejo del `authInterceptor` del frontend
/// Angular: adjunta `Authorization: Bearer <token>` a todo lo que va a la API y traduce
/// los errores de FastAPI a [ApiException]. Desde el Segundo parcial tambien es el espejo de
/// `offlineInterceptor`: cache de GET en SQLite ([baseLocal]) y cola de escrituras sin red.
class ApiClient {
  ApiClient();

  final http.Client _http = http.Client();

  /// Lo setea [ConexionService] al crearse (null en tests: sin capa offline).
  ConexionService? conexion;

  /// Lo setea AuthService al arrancar; devuelve el token de la sesion viva.
  String? Function() obtenerToken = () => null;

  /// Lo setea AuthService: slug del tenant que viaja en `X-Empresa` (multi-tenant).
  String? Function() obtenerEmpresa = () => null;

  /// Se dispara cuando la API responde 401: la sesion guardada ya no sirve.
  void Function()? alExpirarSesion;

  Uri _uri(String ruta, [Map<String, dynamic>? query]) {
    final parametros = <String, String>{};
    query?.forEach((clave, valor) {
      if (valor == null) return;
      parametros[clave] = valor is String ? valor : valor.toString();
    });
    return Uri.parse('${Config.apiUrl}$ruta').replace(
      queryParameters: parametros.isEmpty ? null : parametros,
    );
  }

  Map<String, String> _cabeceras({bool conCuerpo = false}) {
    final cabeceras = <String, String>{'Accept': 'application/json'};
    if (conCuerpo) cabeceras['Content-Type'] = 'application/json';
    final token = obtenerToken();
    if (token != null && token.isNotEmpty) {
      cabeceras['Authorization'] = 'Bearer $token';
    }
    final empresa = obtenerEmpresa();
    if (empresa != null && empresa.isNotEmpty) cabeceras['X-Empresa'] = empresa;
    return cabeceras;
  }

  Future<dynamic> get(String ruta, {Map<String, dynamic>? query}) async {
    Future<http.Response> peticion() => _http.get(_uri(ruta, query), headers: _cabeceras());
    if (conexion == null || !_cacheables.any((p) => p.hasMatch(ruta))) return _enviar(peticion);
    // la misma ruta devuelve otra cosa segun el tenant: la cache se separa por tienda
    final clave = '${obtenerEmpresa() ?? ''}|${_uri(ruta, query)}';
    try {
      final cuerpo = await _enviar(peticion);
      baseLocal.guardarRespuesta(clave, cuerpo).catchError((_) {});
      return cuerpo;
    } on ApiException catch (e) {
      if (e.statusCode != null) rethrow; // el backend respondio: no es falta de red
      conexion?.marcarSinRed();
      final guardada = await baseLocal.leerRespuesta(clave).catchError((_) => null);
      if (guardada == null) rethrow;
      conexion?.marcarDatosGuardados(guardada.$2);
      return guardada.$1;
    }
  }

  Future<dynamic> post(
    String ruta, {
    Object? cuerpo,
    Map<String, dynamic>? query,
    bool notificarSesionExpirada = true,
  }) async {
    Future<http.Response> peticion() => _http.post(
          _uri(ruta, query),
          headers: _cabeceras(conCuerpo: true),
          body: jsonEncode(cuerpo ?? const <String, dynamic>{}),
        );
    final encolable = _encolables['POST $ruta'];
    if (conexion == null || encolable == null) {
      return _enviar(peticion, notificarSesionExpirada: notificarSesionExpirada);
    }
    if (conexion!.enLinea) {
      try {
        return await _enviar(peticion, notificarSesionExpirada: notificarSesionExpirada);
      } on ApiException catch (e) {
        if (e.statusCode != null) rethrow;
        conexion?.marcarSinRed();
      }
    }
    await baseLocal.encolar(metodo: 'POST', ruta: ruta, cuerpo: cuerpo, descripcion: encolable.$1);
    await conexion?.contarPendientes();
    throw ApiException(encolable.$2, statusCode: 503);
  }

  /// La usa la sincronizacion de la cola: manda tal cual, sin volver a encolar.
  Future<dynamic> enviarSinCola(String metodo, String ruta, Object? cuerpo) => _enviar(
        () => _http.send(
          http.Request(metodo, _uri(ruta))
            ..headers.addAll(_cabeceras(conCuerpo: true))
            ..body = jsonEncode(cuerpo ?? const <String, dynamic>{}),
        ).then(http.Response.fromStream),
      );

  Future<dynamic> put(String ruta, {Object? cuerpo}) => _enviar(
        () => _http.put(
          _uri(ruta),
          headers: _cabeceras(conCuerpo: true),
          body: jsonEncode(cuerpo ?? const <String, dynamic>{}),
        ),
      );

  Future<dynamic> patch(String ruta, {Object? cuerpo}) => _enviar(
        () => _http.patch(
          _uri(ruta),
          headers: _cabeceras(conCuerpo: true),
          body: jsonEncode(cuerpo ?? const <String, dynamic>{}),
        ),
      );

  Future<dynamic> delete(String ruta) =>
      _enviar(() => _http.delete(_uri(ruta), headers: _cabeceras()));

  Future<dynamic> _enviar(
    Future<http.Response> Function() peticion, {
    bool notificarSesionExpirada = true,
  }) async {
    late final http.Response respuesta;
    try {
      respuesta = await peticion().timeout(const Duration(seconds: 30));
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        Config.apuntaAProduccion
            ? 'No se pudo conectar con el servidor. Revisa tu conexion a internet.'
            : 'No se pudo conectar con ${Config.apiUrl}. '
                'Verifica que el backend local este corriendo.',
      );
    }

    final cuerpo = utf8.decode(respuesta.bodyBytes);
    if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) {
      if (respuesta.statusCode == 204 || cuerpo.isEmpty) return null;
      return jsonDecode(cuerpo);
    }

    // Ojo: `POST /auth/password` (cambiar mi propia contrasena) tambien devuelve 401
    // cuando la contrasena ACTUAL esta mal, no porque la sesion haya vencido -- ese
    // llamado pasa `notificarSesionExpirada: false` para no cerrar la sesion sola.
    if (respuesta.statusCode == 401 && notificarSesionExpirada) alExpirarSesion?.call();
    throw ApiException(
      mensajeDesdeCuerpo(cuerpo, respuesta.statusCode),
      statusCode: respuesta.statusCode,
    );
  }
}

/// Instancia compartida por todos los servicios (el equivalente a `providedIn: 'root'`).
final ApiClient api = ApiClient();

// --- Ayudas de parseo comunes a todos los modelos --------------------------

double aDouble(dynamic valor) {
  if (valor == null) return 0;
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor.toString()) ?? 0;
}

double? aDoubleNulo(dynamic valor) {
  if (valor == null) return null;
  if (valor is num) return valor.toDouble();
  return double.tryParse(valor.toString());
}

int aEntero(dynamic valor) {
  if (valor == null) return 0;
  if (valor is int) return valor;
  if (valor is num) return valor.toInt();
  return int.tryParse(valor.toString()) ?? 0;
}

DateTime? aFechaNula(dynamic valor) {
  if (valor == null) return null;
  return DateTime.tryParse(valor.toString());
}

List<Map<String, dynamic>> comoLista(dynamic valor) =>
    (valor as List? ?? const []).cast<Map<String, dynamic>>();
