import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_service.dart';
import 'paginas/asistente_pagina.dart';
import 'paginas/atender_reservas_pagina.dart';
import 'paginas/caja_pagina.dart';
import 'paginas/carrito_pagina.dart';
import 'paginas/compra_pagina.dart';
import 'paginas/cuenta_pagina.dart';
import 'paginas/login_pagina.dart';
import 'paginas/mis_compras_pagina.dart';
import 'paginas/mis_direcciones_pagina.dart';
import 'paginas/mis_reservas_pagina.dart';
import 'paginas/pago_simulado_pagina.dart';
import 'paginas/panel_catalogo_pagina.dart';
import 'paginas/panel_envios_pagina.dart';
import 'paginas/panel_pagina.dart';
import 'paginas/panel_proveedores_pagina.dart';
import 'paginas/panel_recepciones_pagina.dart';
import 'paginas/panel_sucursales_pagina.dart';
import 'paginas/panel_usuarios_pagina.dart';
import 'paginas/producto_detalle_pagina.dart';
import 'paginas/registro_pagina.dart';
import 'paginas/reservar_pagina.dart';
import 'paginas/tienda_pagina.dart';
import 'compartido/navegacion_cliente.dart';

/// Rutas que solo puede ver quien NO tiene sesion (espejo de `invitadoGuard`).
const _rutasDeInvitado = {'/login', '/registro'};

/// Permisos exigidos por cada pantalla del panel, espejo de `permisoGuard` en
/// `frontend/src/app/app.routes.ts`. Quien autoriza de verdad siempre es la API.
const Map<String, List<String>> _permisosPorRuta = {
  '/panel/catalogo': [
    'catalogo.leer',
    'catalogo.crear',
    'catalogo.actualizar',
    'catalogo.eliminar',
  ],
  '/panel/recepciones': [
    'recepciones.leer',
    'recepciones.crear',
    'recepciones.actualizar',
    'recepciones.eliminar',
  ],
  '/panel/proveedores': [
    'proveedores.leer',
    'proveedores.crear',
    'proveedores.actualizar',
    'proveedores.eliminar',
  ],
  '/panel/sucursales': [
    'sucursales.leer',
    'sucursales.crear',
    'sucursales.actualizar',
    'sucursales.eliminar',
  ],
  '/panel/usuarios': [
    'usuarios.leer',
    'usuarios.crear',
    'usuarios.actualizar',
    'usuarios.eliminar',
    'roles.leer',
  ],
  '/panel/envios': ['envios.leer', 'envios.actualizar'],
};

GoRouter construirRouter(AuthService auth) {
  final navegadorRaiz = GlobalKey<NavigatorState>();
  final navegadorShell = GlobalKey<NavigatorState>();

  return GoRouter(
    navigatorKey: navegadorRaiz,
    initialLocation: '/tienda',
    refreshListenable: auth,
    redirect: (contexto, estado) {
      if (!auth.listo) return null;
      final ruta = estado.matchedLocation;
      final esDeInvitado = _rutasDeInvitado.contains(ruta);

      if (!auth.estaAutenticado) return esDeInvitado ? null : '/login';
      if (esDeInvitado) return '/tienda';

      final exigidos = _permisosPorRuta[ruta];
      if (exigidos != null && !auth.tienePermiso(exigidos)) return '/panel';
      if (ruta.startsWith('/panel') && !auth.esStaff) return '/tienda';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (contexto, estado) => const LoginPagina()),
      GoRoute(path: '/registro', builder: (contexto, estado) => const RegistroPagina()),

      // Barra inferior del cliente: las cuatro pantallas que se usan a diario.
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: navegadorRaiz,
        builder: (contexto, estado, shell) => NavegacionCliente(shell: shell),
        branches: [
          StatefulShellBranch(
            navigatorKey: navegadorShell,
            routes: [
              GoRoute(path: '/tienda', builder: (contexto, estado) => const TiendaPagina()),
            ],
          ),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/mis-reservas',
              builder: (contexto, estado) => const MisReservasPagina(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/carrito', builder: (contexto, estado) => const CarritoPagina()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/cuenta', builder: (contexto, estado) => const CuentaPagina()),
          ]),
        ],
      ),

      GoRoute(
        path: '/producto/:slug',
        builder: (contexto, estado) =>
            ProductoDetallePagina(slug: estado.pathParameters['slug']!),
      ),
      GoRoute(path: '/reservar', builder: (contexto, estado) => const ReservarPagina()),
      GoRoute(path: '/mis-compras', builder: (contexto, estado) => const MisComprasPagina()),
      GoRoute(
        path: '/mis-direcciones',
        builder: (contexto, estado) => const MisDireccionesPagina(),
      ),
      GoRoute(path: '/asistente', builder: (contexto, estado) => const AsistentePagina()),
      GoRoute(
        path: '/pago-simulado/:ventaId',
        builder: (contexto, estado) =>
            PagoSimuladoPagina(ventaId: estado.pathParameters['ventaId']!),
      ),
      GoRoute(
        path: '/compra/:ventaId',
        builder: (contexto, estado) => CompraPagina(ventaId: estado.pathParameters['ventaId']!),
      ),

      // CU07 y CU08 siguen validando por cargo en el backend (get_cajero_actual /
      // get_encargado_actual), asi que aca no se exige permiso: la API responde 403.
      GoRoute(path: '/caja', builder: (contexto, estado) => const CajaPagina()),
      GoRoute(
        path: '/atender-reservas',
        builder: (contexto, estado) => const AtenderReservasPagina(),
      ),

      // Panel de gestion (CU09 a CU13).
      GoRoute(path: '/panel', builder: (contexto, estado) => const PanelPagina()),
      GoRoute(
        path: '/panel/catalogo',
        builder: (contexto, estado) => const PanelCatalogoPagina(),
      ),
      GoRoute(
        path: '/panel/recepciones',
        builder: (contexto, estado) => const PanelRecepcionesPagina(),
      ),
      GoRoute(
        path: '/panel/proveedores',
        builder: (contexto, estado) => const PanelProveedoresPagina(),
      ),
      GoRoute(
        path: '/panel/sucursales',
        builder: (contexto, estado) => const PanelSucursalesPagina(),
      ),
      GoRoute(
        path: '/panel/usuarios',
        builder: (contexto, estado) => const PanelUsuariosPagina(),
      ),
      GoRoute(
        path: '/panel/envios',
        builder: (contexto, estado) => const PanelEnviosPagina(),
      ),
    ],
  );
}
