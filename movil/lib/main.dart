import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'compartido/aviso_conexion.dart';
import 'core/acceso_y_organizacion/auth/auth_service.dart';
import 'core/operacion_comercial/carrito/carrito_service.dart';
import 'core/nucleo/notificaciones/notificaciones_service.dart';
import 'core/nucleo/push/push_service.dart';
import 'core/operacion_sin_conexion/offline/conexion_service.dart';
import 'core/operacion_comercial/reservas/reserva_carrito_service.dart';
import 'core/operacion_sin_conexion/sincronizacion/sincronizacion_service.dart';
import 'core/tema.dart';
import 'rutas.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final auth = AuthService();
  final reservaCarrito = ReservaCarritoService();
  await auth.inicializar();
  await reservaCarrito.inicializar();

  final carrito = CarritoService();
  // PENDIENTES 5.3: cache SQLite + cola sin red; al sincronizar, el carrito cambia
  final conexion = ConexionService()..despuesDeSincronizar(() => unawaited(carrito.refrescar()));
  // PENDIENTES 2.19.3: escucha a auth y hace polling del contador solo mientras hay sesion.
  final notificaciones = NotificacionesService(auth);
  // Push al celular (FCM): sin claves de Firebase queda apagado y no pasa nada
  final push = PushService(auth, notificaciones);
  await push.inicializar();
  // Modulos C y D: venta y reserva sin conexion en SQLite; se recarga al cambiar de usuario
  final sincronizacion = SincronizacionService(
    usuarioActual: () => auth.usuario?.id,
    conexion: conexion,
  );
  String? usuarioAnterior = auth.usuario?.id;
  auth.addListener(() {
    if (auth.usuario?.id == usuarioAnterior) return;
    usuarioAnterior = auth.usuario?.id;
    unawaited(sincronizacion.cargarLocal().then((_) => sincronizacion.sincronizar()));
  });
  unawaited(sincronizacion.cargarLocal().then((_) => sincronizacion.sincronizar()));
  if (auth.estaAutenticado) {
    // el contador del carrito se refresca sin bloquear el arranque
    unawaited(carrito.refrescar());
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: reservaCarrito),
        ChangeNotifierProvider.value(value: carrito),
        ChangeNotifierProvider.value(value: notificaciones),
        ChangeNotifierProvider.value(value: conexion),
        ChangeNotifierProvider.value(value: sincronizacion),
      ],
      child: AppFashionStore(auth: auth, push: push),
    ),
  );
}

void unawaited(Future<void> futuro) {
  futuro.catchError((_) {});
}

class AppFashionStore extends StatefulWidget {
  const AppFashionStore({super.key, required this.auth, this.push});

  final AuthService auth;

  /// null en los tests: sin push.
  final PushService? push;

  @override
  State<AppFashionStore> createState() => _AppFashionStoreState();
}

class _AppFashionStoreState extends State<AppFashionStore> {
  late final router = construirRouter(widget.auth);

  @override
  void initState() {
    super.initState();
    widget.push?.irARuta = router.go;
    // con la app cerrada, tocar un aviso la abre: se navega ya con el router armado
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.push?.abrirNotificacionInicial());
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'FashionStore',
        debugShowCheckedModeBanner: false,
        theme: construirTema(),
        routerConfig: router,
        builder: (context, child) => AvisoConexion(child: child ?? const SizedBox.shrink()),
      );
}
