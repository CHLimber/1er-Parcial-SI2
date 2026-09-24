import 'dart:async';

import 'package:flutter/widgets.dart';

import '../api.dart';
import '../auth/auth_service.dart';
import 'notificaciones_models.dart';

/// Notificaciones del usuario de la sesion (PENDIENTES.txt 2.19.3), espejo de
/// `NotificacionesService` del frontend. Es un ChangeNotifier porque el contador de no
/// leidas se muestra en el badge de la campana (tienda y cuenta).
///
/// Escucha a [AuthService]: con sesion arranca un polling cada 60 s del contador, y al cerrar
/// sesion (o si la API responde 401 y la sesion expira) lo detiene y vuelve a cero. Con la app
/// en segundo plano el tick se saltea.
class NotificacionesService extends ChangeNotifier {
  NotificacionesService(this._auth) {
    _auth.addListener(_alCambiarSesion);
    _alCambiarSesion();
  }

  static const Duration _intervalo = Duration(seconds: 60);

  final AuthService _auth;
  Timer? _temporizador;
  String? _usuarioId;

  int _noLeidas = 0;
  int get noLeidas => _noLeidas;

  void _alCambiarSesion() {
    final usuarioId = _auth.estaAutenticado ? _auth.usuario?.id : null;
    if (usuarioId == _usuarioId) return;
    _usuarioId = usuarioId;

    _temporizador?.cancel();
    _temporizador = null;
    _fijar(0);
    if (usuarioId == null) return;

    refrescarContador();
    _temporizador = Timer.periodic(_intervalo, (_) {
      final estado = WidgetsBinding.instance.lifecycleState;
      if (estado != null && estado != AppLifecycleState.resumed) return;
      refrescarContador();
    });
  }

  void _fijar(int valor) {
    if (valor == _noLeidas) return;
    _noLeidas = valor;
    notifyListeners();
  }

  /// Reconsulta el contador; los errores se ignoran (la campana no es critica).
  Future<void> refrescarContador() async {
    if (!_auth.estaAutenticado) return;
    try {
      final respuesta = await api.get('/notificaciones/no-leidas/cantidad');
      // la sesion pudo cerrarse mientras volvia la respuesta
      if (!_auth.estaAutenticado) return;
      _fijar(aEntero((respuesta as Map<String, dynamic>)['no_leidas']));
    } catch (_) {}
  }

  Future<NotificacionPaginadoOut> listar({
    int pagina = 1,
    int tamanioPagina = 20,
    bool soloNoLeidas = false,
  }) async {
    final respuesta = await api.get('/notificaciones', query: {
      'pagina': pagina,
      'tamanio_pagina': tamanioPagina,
      'solo_no_leidas': soloNoLeidas,
    });
    final resultado = NotificacionPaginadoOut.desdeJson(respuesta as Map<String, dynamic>);
    _fijar(resultado.noLeidas);
    return resultado;
  }

  /// Solo tiene sentido para una notificacion todavia no leida: descuenta el badge local
  /// y el valor exacto llega en el proximo refresco.
  Future<NotificacionOut> marcarLeida(String id) async {
    final respuesta = await api.post('/notificaciones/$id/leida');
    _fijar(_noLeidas > 0 ? _noLeidas - 1 : 0);
    return NotificacionOut.desdeJson(respuesta as Map<String, dynamic>);
  }

  Future<void> leerTodas() async {
    await api.post('/notificaciones/leer-todas');
    _fijar(0);
  }

  @override
  void dispose() {
    _auth.removeListener(_alCambiarSesion);
    _temporizador?.cancel();
    super.dispose();
  }
}
