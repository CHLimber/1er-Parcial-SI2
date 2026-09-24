import '../api.dart';

/// CU19 - Consultar Bitacora de Auditoria. Espejo de
/// `backend/app/modules/auditoria/schemas.py` y de
/// `frontend/src/app/core/auditoria/auditoria.models.ts`. Solo lectura sobre la tabla
/// `auditoria`; el backend ya devuelve `datos_antes`/`datos_despues` como objeto JSON
/// (el parseo de texto a jsonb pasa en el router, asyncpg no tiene ese codec), asi que
/// aca llegan directo como Map.
class AuditoriaOut {
  AuditoriaOut({
    required this.id,
    required this.fecha,
    required this.usuarioId,
    required this.usuarioNombre,
    required this.usuarioEmail,
    required this.entidad,
    required this.entidadId,
    required this.accion,
    required this.datosAntes,
    required this.datosDespues,
    required this.ip,
  });

  final int id;
  final DateTime fecha;
  final String? usuarioId;
  final String? usuarioNombre;
  final String? usuarioEmail;
  final String entidad;
  final String entidadId;
  final String accion;
  final Map<String, dynamic>? datosAntes;
  final Map<String, dynamic>? datosDespues;
  final String? ip;

  factory AuditoriaOut.desdeJson(Map<String, dynamic> j) => AuditoriaOut(
        id: aEntero(j['id']),
        fecha: DateTime.parse(j['fecha'] as String),
        usuarioId: j['usuario_id'] as String?,
        usuarioNombre: j['usuario_nombre'] as String?,
        usuarioEmail: j['usuario_email'] as String?,
        entidad: j['entidad'] as String,
        entidadId: j['entidad_id'] as String,
        accion: j['accion'] as String,
        datosAntes: (j['datos_antes'] as Map?)?.cast<String, dynamic>(),
        datosDespues: (j['datos_despues'] as Map?)?.cast<String, dynamic>(),
        ip: j['ip'] as String?,
      );
}

class AuditoriaPaginadoOut {
  AuditoriaPaginadoOut({
    required this.total,
    required this.pagina,
    required this.tamanioPagina,
    required this.items,
  });

  final int total;
  final int pagina;
  final int tamanioPagina;
  final List<AuditoriaOut> items;

  factory AuditoriaPaginadoOut.desdeJson(Map<String, dynamic> j) => AuditoriaPaginadoOut(
        total: aEntero(j['total']),
        pagina: aEntero(j['pagina']),
        tamanioPagina: aEntero(j['tamanio_pagina']),
        items: comoLista(j['items']).map(AuditoriaOut.desdeJson).toList(),
      );
}

/// Permiso unico de este CU, sembrado solo para ADMIN (ver CLAUDE.md / PENDIENTES 2.12).
const permisoAuditoria = 'auditoria.leer';

class AuditoriaService {
  Future<AuditoriaPaginadoOut> listar({
    String? usuarioId,
    String? entidad,
    String? entidadId,
    String? accion,
    DateTime? desde,
    DateTime? hasta,
    required int pagina,
    required int tamanioPagina,
  }) async {
    final respuesta = await api.get('/auditoria', query: {
      'usuario_id': usuarioId,
      'entidad': entidad,
      'entidad_id': (entidadId?.isEmpty ?? true) ? null : entidadId,
      'accion': accion,
      'desde': desde == null ? null : _soloFecha(desde),
      'hasta': hasta == null ? null : _soloFecha(hasta),
      'pagina': pagina,
      'tamanio_pagina': tamanioPagina,
    });
    return AuditoriaPaginadoOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  /// Valores distintos de `entidad` ya registrados, para armar el filtro (no se
  /// hardcodea: `entidad` es VARCHAR libre, no un ENUM).
  Future<List<String>> entidades() async {
    final respuesta = await api.get('/auditoria/entidades');
    return (respuesta as List).cast<String>();
  }

  String _soloFecha(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-'
      '${fecha.month.toString().padLeft(2, '0')}-'
      '${fecha.day.toString().padLeft(2, '0')}';
}

final auditoriaService = AuditoriaService();
