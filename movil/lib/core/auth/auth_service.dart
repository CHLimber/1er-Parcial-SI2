import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import 'auth_models.dart';

/// Sesion del usuario. Espejo de `AuthService` del frontend: guarda token + usuario en
/// el almacenamiento local (aca SharedPreferences en vez de localStorage) y lo restaura
/// al arrancar la app.
class AuthService extends ChangeNotifier {
  static const String _claveSesion = 'fashionstore.sesion';

  String? _token;
  UsuarioOut? _usuario;
  bool _listo = false;

  String? get token => _token;
  UsuarioOut? get usuario => _usuario;
  bool get estaAutenticado => _token != null && _usuario != null;
  bool get esStaff => _usuario?.esStaff ?? false;
  List<String> get permisos => _usuario?.permisos ?? const [];

  /// Falso hasta que se termino de leer la sesion guardada (evita parpadeos al iniciar).
  bool get listo => _listo;

  /// CU13: la UI se arma con los permisos del rol, no con su nombre. Basta con tener uno.
  bool tienePermiso(List<String> codigos) => codigos.any(permisos.contains);

  Future<void> inicializar() async {
    api.obtenerToken = () => _token;
    api.alExpirarSesion = () {
      if (estaAutenticado) cerrarSesion();
    };

    final prefs = await SharedPreferences.getInstance();
    final crudo = prefs.getString(_claveSesion);
    if (crudo != null) {
      try {
        final datos = jsonDecode(crudo) as Map<String, dynamic>;
        _token = datos['token'] as String?;
        _usuario = UsuarioOut.desdeJson(datos['usuario'] as Map<String, dynamic>);
      } catch (_) {
        await prefs.remove(_claveSesion);
        _token = null;
        _usuario = null;
      }
    }
    _listo = true;
    notifyListeners();
  }

  Future<UsuarioOut> iniciarSesion(String email, String password) async {
    final respuesta = await api.post('/auth/login', cuerpo: {'email': email, 'password': password});
    return _guardar(respuesta as Map<String, dynamic>);
  }

  Future<UsuarioOut> registrarse(RegistroRequest datos) async {
    final respuesta = await api.post('/auth/registro', cuerpo: datos.aJson());
    return _guardar(respuesta as Map<String, dynamic>);
  }

  /// Vuelve a pedir el usuario al backend: si el administrador cambio su rol o sus
  /// permisos (CU13), la sesion guardada en el dispositivo quedo desactualizada.
  Future<void> refrescarSesion() async {
    if (!estaAutenticado) return;
    final respuesta = await api.get('/auth/yo');
    _usuario = UsuarioOut.desdeJson(respuesta as Map<String, dynamic>);
    await _persistir();
    notifyListeners();
  }

  Future<void> cerrarSesion() async {
    _token = null;
    _usuario = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_claveSesion);
  }

  Future<UsuarioOut> _guardar(Map<String, dynamic> respuesta) async {
    _token = respuesta['access_token'] as String;
    _usuario = UsuarioOut.desdeJson(respuesta['usuario'] as Map<String, dynamic>);
    await _persistir();
    notifyListeners();
    return _usuario!;
  }

  Future<void> _persistir() async {
    if (_token == null || _usuario == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _claveSesion,
      jsonEncode({'token': _token, 'usuario': _usuario!.aJson()}),
    );
  }
}
