import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../api.dart';
import '../errores.dart';
import 'base_local.dart';

/// Estado online/offline de la app (PENDIENTES 5.3), espejo de `ConexionService` de la web.
/// Escucha a connectivity_plus y, al volver la red, manda en orden lo que quedo en la tabla
/// `pendiente` de SQLite. Un rechazo del backend (4xx: p.ej. sin stock) descarta la operacion
/// y se avisa, para no trabar la cola.
class ConexionService extends ChangeNotifier {
  ConexionService({Connectivity? conectividad}) : _conectividad = conectividad ?? Connectivity() {
    api.conexion = this;
    _suscripcion = _conectividad.onConnectivityChanged.listen(_alCambiar);
    _conectividad.checkConnectivity().then(_alCambiar).catchError((_) {});
    contarPendientes();
  }

  final Connectivity _conectividad;
  StreamSubscription<List<ConnectivityResult>>? _suscripcion;
  bool _sincronizando = false;

  bool enLinea = true;
  int pendientes = 0;

  /// Cuando se guardaron los datos que se estan mostrando sin red (null = datos en vivo).
  DateTime? datosDe;
  String? ultimoAviso;

  /// Lo que hay que refrescar despues de sincronizar (p.ej. el contador del carrito).
  final List<VoidCallback> _alSincronizar = [];

  void despuesDeSincronizar(VoidCallback callback) => _alSincronizar.add(callback);

  void _alCambiar(List<ConnectivityResult> resultados) {
    final ahora = resultados.any((r) => r != ConnectivityResult.none);
    if (ahora == enLinea) return;
    enLinea = ahora;
    if (ahora) {
      datosDe = null;
      sincronizar();
    }
    notifyListeners();
  }

  /// La llama [ApiClient] cuando un pedido fallo por red aunque connectivity diga que hay.
  void marcarSinRed() {
    if (!enLinea) return;
    enLinea = false;
    notifyListeners();
  }

  void marcarDatosGuardados(DateTime fecha) {
    datosDe = fecha;
    notifyListeners();
  }

  void cerrarAviso() {
    ultimoAviso = null;
    notifyListeners();
  }

  Future<void> contarPendientes() async {
    try {
      pendientes = (await baseLocal.pendientes()).length;
    } catch (_) {
      pendientes = 0;
    }
    notifyListeners();
  }

  Future<void> sincronizar() async {
    if (_sincronizando) return;
    _sincronizando = true;
    var enviadas = 0;
    var descartadas = 0;
    try {
      for (final op in await baseLocal.pendientes()) {
        try {
          await api.enviarSinCola(op.metodo, op.ruta, op.cuerpo);
          enviadas++;
          await baseLocal.quitar(op.id);
        } on ApiException catch (e) {
          if (e.statusCode == null) break; // se volvio a cortar: queda para la proxima
          descartadas++;
          await baseLocal.quitar(op.id);
        }
      }
    } catch (_) {
      // sin base local: nada que sincronizar
    } finally {
      _sincronizando = false;
    }
    await contarPendientes();
    if (enviadas > 0 || descartadas > 0) {
      ultimoAviso = 'Volvio la conexion: se sincronizaron $enviadas operacion(es)'
          '${descartadas > 0 ? ' y $descartadas ya no se pudieron hacer (por ejemplo, sin stock).' : '.'}';
      for (final callback in _alSincronizar) {
        callback();
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _suscripcion?.cancel();
    super.dispose();
  }
}
