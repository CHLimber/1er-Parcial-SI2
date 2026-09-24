import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/auth/auth_service.dart';
import 'core/carrito/carrito_service.dart';
import 'core/notificaciones/notificaciones_service.dart';
import 'core/reservas/reserva_carrito_service.dart';
import 'core/tema.dart';
import 'rutas.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final auth = AuthService();
  final reservaCarrito = ReservaCarritoService();
  await auth.inicializar();
  await reservaCarrito.inicializar();

  final carrito = CarritoService();
  // PENDIENTES 2.19.3: escucha a auth y hace polling del contador solo mientras hay sesion.
  final notificaciones = NotificacionesService(auth);
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
      ],
      child: AppFashionStore(auth: auth),
    ),
  );
}

void unawaited(Future<void> futuro) {
  futuro.catchError((_) {});
}

class AppFashionStore extends StatefulWidget {
  const AppFashionStore({super.key, required this.auth});

  final AuthService auth;

  @override
  State<AppFashionStore> createState() => _AppFashionStoreState();
}

class _AppFashionStoreState extends State<AppFashionStore> {
  late final router = construirRouter(widget.auth);

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'FashionStore',
        debugShowCheckedModeBanner: false,
        theme: construirTema(),
        routerConfig: router,
      );
}
