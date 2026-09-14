import 'dart:convert';

/// Error de la API ya traducido a algo que se le puede mostrar al usuario.
///
/// FastAPI manda el motivo en `detail`: un string en los errores de negocio
/// (HTTPException) y una lista de objetos en los errores de validacion de Pydantic.
class ApiException implements Exception {
  ApiException(this.mensaje, {this.statusCode});

  final String mensaje;
  final int? statusCode;

  bool get esSesionInvalida => statusCode == 401;
  bool get esSinPermiso => statusCode == 403;

  @override
  String toString() => mensaje;
}

String interpretarError(Object error) {
  if (error is ApiException) return error.mensaje;
  return 'No se pudo conectar con el servidor. Revisa tu conexion e intenta de nuevo.';
}

/// Extrae el mensaje del cuerpo de una respuesta de error de FastAPI.
String mensajeDesdeCuerpo(String cuerpo, int statusCode) {
  if (cuerpo.isEmpty) return _mensajePorDefecto(statusCode);
  try {
    final decodificado = jsonDecode(cuerpo);
    if (decodificado is Map<String, dynamic>) {
      final detail = decodificado['detail'];

      // 403/404/409: HTTPException con un motivo en texto
      if (detail is String && detail.isNotEmpty) return detail;

      // 422: lista de errores de validacion de Pydantic
      if (detail is List && detail.isNotEmpty) {
        final mensajes = detail
            .whereType<Map<String, dynamic>>()
            .map(_mensajeDeValidacion)
            .where((m) => m.isNotEmpty);
        if (mensajes.isNotEmpty) return mensajes.join(' · ');
      }

      // 409 de stock (checkout y reservas): detail es un objeto con el motivo y el
      // listado de prendas que no se pudieron comprometer.
      if (detail is Map<String, dynamic>) return _mensajeDeConflicto(detail, statusCode);
    }
  } catch (_) {
    // cuerpo que no es JSON: cae al mensaje generico
  }
  return _mensajePorDefecto(statusCode);
}

String _mensajeDeValidacion(Map<String, dynamic> error) {
  final mensaje = (error['msg']?.toString() ?? '').replaceFirst('Value error, ', '');
  if (mensaje.isEmpty) return '';
  final loc = (error['loc'] as List? ?? const [])
      .where((parte) => parte != 'body')
      .join('.');
  return loc.isEmpty ? mensaje : '$loc: $mensaje';
}

String _mensajeDeConflicto(Map<String, dynamic> detail, int statusCode) {
  final base = detail['mensaje']?.toString() ?? _mensajePorDefecto(statusCode);
  final rechazados = detail['rechazados'];
  if (rechazados is List && rechazados.isNotEmpty) {
    final lineas = rechazados
        .whereType<Map<String, dynamic>>()
        .map((item) => '${item['sku'] ?? item['variante_id']}: ${item['motivo'] ?? ''}')
        .join('\n');
    return '$base\n$lineas';
  }
  return base;
}

String _mensajePorDefecto(int statusCode) {
  switch (statusCode) {
    case 401:
      return 'Sesion invalida o expirada';
    case 403:
      return 'Tu rol no tiene permiso para esta operacion';
    case 404:
      return 'No se encontro el recurso solicitado';
    default:
      return 'Ocurrio un error inesperado (HTTP $statusCode)';
  }
}
