import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../acceso_y_organizacion/auth/auth_service.dart';
import '../../api.dart';
import '../notificaciones/notificaciones_service.dart';
import 'firebase_opciones.dart';

/// Push al celular con Firebase Cloud Messaging.
///
/// Con la app cerrada o en segundo plano, Android dibuja solo la notificacion del sistema (el
/// backend manda el bloque `notification`), asi que aca no hace falta codigo para eso. Lo que si
/// hace este servicio:
///
///  - registrar el token del telefono en el backend al iniciar sesion (y cuando Firebase lo
///    renueva) y darlo de baja al cerrar sesion, para que un telefono sin sesion no reciba avisos;
///  - con la app abierta, refrescar el contador de la campana (FCM no dibuja nada en primer plano);
///  - abrir la pantalla correcta al tocar la notificacion.
///
/// Sin claves de Firebase ([OpcionesFirebase.configurado] en false) no hace nada.
class PushService {
  PushService(this._auth, this._notificaciones);

  final AuthService _auth;
  final NotificacionesService _notificaciones;

  /// La asigna la app cuando el router ya existe: recibe la ruta a la que ir al tocar un aviso.
  void Function(String ruta)? irARuta;

  bool _activo = false;
  String? _usuarioRegistrado;
  String? _token;
  RemoteMessage? _inicial;

  bool get activo => _activo;

  Future<void> inicializar() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    if (!OpcionesFirebase.configurado) {
      debugPrint('Push apagado: faltan las claves de Firebase (firebase_opciones.dart).');
      return;
    }
    try {
      await Firebase.initializeApp(options: OpcionesFirebase.actuales);
      final mensajeria = FirebaseMessaging.instance;
      // Android 13+ pide el permiso POST_NOTIFICATIONS aca; si lo niega, la campana sigue andando
      await mensajeria.requestPermission();
      FirebaseMessaging.onMessage.listen((_) => _notificaciones.refrescarContador());
      FirebaseMessaging.onMessageOpenedApp.listen(_abrir);
      // onRegistered entrega el ID de instalacion, no el token FCM que acepta el campo `token`
      // de la API HTTP v1 que usa el backend: por eso se sigue con onTokenRefresh/getToken.
      // ignore: deprecated_member_use
      mensajeria.onTokenRefresh.listen((token) {
        _token = token;
        if (_usuarioRegistrado != null) _sinEsperar(_registrar(token));
      });
      _inicial = await mensajeria.getInitialMessage();
      _activo = true;
      _auth.antesDeCerrarSesion = darDeBaja;
      _auth.addListener(_alCambiarSesion);
      _alCambiarSesion();
    } catch (error) {
      // un fallo de Firebase (sin Play Services, claves mal pegadas) no puede tumbar la app
      debugPrint('Push apagado: no arranco Firebase ($error).');
    }
  }

  /// Si la app se abrio tocando una notificacion con la app cerrada, se navega cuando el router
  /// ya esta listo (lo llama la app despues de asignar [irARuta]).
  void abrirNotificacionInicial() {
    final mensaje = _inicial;
    _inicial = null;
    if (mensaje != null) _abrir(mensaje);
  }

  void _alCambiarSesion() {
    final usuarioId = _auth.estaAutenticado ? _auth.usuario?.id : null;
    if (usuarioId == null || usuarioId == _usuarioRegistrado) return;
    _usuarioRegistrado = usuarioId;
    _sinEsperar(_registrarActual());
  }

  Future<void> _registrarActual() async {
    try {
      // ignore: deprecated_member_use -- ver onTokenRefresh arriba
      final token = _token ??= await FirebaseMessaging.instance.getToken();
      if (token != null) await _registrar(token);
    } catch (error) {
      debugPrint('No se pudo registrar el telefono para push ($error).');
    }
  }

  Future<void> _registrar(String token) async {
    if (!_auth.estaAutenticado) return;
    await api.post(
      '/notificaciones/dispositivos',
      cuerpo: {'token': token, 'plataforma': Platform.isIOS ? 'IOS' : 'ANDROID'},
      notificarSesionExpirada: false,
    );
  }

  /// Lo llama [AuthService.cerrarSesion] ANTES de borrar el token de sesion: la baja necesita
  /// estar autenticada. Si falla (sin red) no frena el cierre de sesion.
  Future<void> darDeBaja() async {
    final token = _token;
    _usuarioRegistrado = null;
    if (!_activo || token == null) return;
    try {
      await api
          .post(
            '/notificaciones/dispositivos/baja',
            cuerpo: {'token': token},
            notificarSesionExpirada: false,
          )
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  void _abrir(RemoteMessage mensaje) {
    final datos = mensaje.data;
    final id = datos['entidad_id'];
    final ruta = (datos['entidad_tipo'] == 'VENTA' && id != null && id.isNotEmpty)
        ? '/compra/$id'
        : '/notificaciones';
    irARuta?.call(ruta);
  }
}

void _sinEsperar(Future<void> futuro) {
  futuro.catchError((_) {});
}
