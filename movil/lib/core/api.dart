import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'errores.dart';

/// Cliente HTTP unico contra la API. Es el espejo del `authInterceptor` del frontend
/// Angular: adjunta `Authorization: Bearer <token>` a todo lo que va a la API y traduce
/// los errores de FastAPI a [ApiException].
class ApiClient {
  ApiClient();

  final http.Client _http = http.Client();

  /// Lo setea AuthService al arrancar; devuelve el token de la sesion viva.
  String? Function() obtenerToken = () => null;

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
    return cabeceras;
  }

  Future<dynamic> get(String ruta, {Map<String, dynamic>? query}) =>
      _enviar(() => _http.get(_uri(ruta, query), headers: _cabeceras()));

  Future<dynamic> post(String ruta, {Object? cuerpo, Map<String, dynamic>? query}) => _enviar(
        () => _http.post(
          _uri(ruta, query),
          headers: _cabeceras(conCuerpo: true),
          body: jsonEncode(cuerpo ?? const <String, dynamic>{}),
        ),
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

  Future<dynamic> _enviar(Future<http.Response> Function() peticion) async {
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

    if (respuesta.statusCode == 401) alExpirarSesion?.call();
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
