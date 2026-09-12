import { Routes } from '@angular/router';

import {
  authGuard,
  cajeroGuard,
  encargadoGuard,
  invitadoGuard,
  permisoGuard,
} from './core/auth/auth.guard';

export const routes: Routes = [
  {
    path: 'login',
    loadComponent: () => import('./pages/login/login.page').then((m) => m.LoginPage),
    canActivate: [invitadoGuard],
  },
  {
    path: 'registro',
    loadComponent: () => import('./pages/registro/registro.page').then((m) => m.RegistroPage),
    canActivate: [invitadoGuard],
  },
  {
    path: 'tienda',
    loadComponent: () => import('./pages/tienda/tienda.page').then((m) => m.TiendaPage),
    canActivate: [authGuard],
  },
  {
    path: 'producto/:slug',
    loadComponent: () =>
      import('./pages/producto-detalle/producto-detalle.page').then((m) => m.ProductoDetallePage),
    canActivate: [authGuard],
  },
  {
    path: 'reservar',
    loadComponent: () => import('./pages/reservar/reservar.page').then((m) => m.ReservarPage),
    canActivate: [authGuard],
  },
  {
    path: 'mis-reservas',
    loadComponent: () =>
      import('./pages/mis-reservas/mis-reservas.page').then((m) => m.MisReservasPage),
    canActivate: [authGuard],
  },
  {
    path: 'carrito',
    loadComponent: () => import('./pages/carrito/carrito.page').then((m) => m.CarritoPage),
    canActivate: [authGuard],
  },
  {
    path: 'pago-simulado/:ventaId',
    loadComponent: () =>
      import('./pages/pago-simulado/pago-simulado.page').then((m) => m.PagoSimuladoPage),
    canActivate: [authGuard],
  },
  {
    path: 'compra/:ventaId',
    loadComponent: () => import('./pages/compra/compra.page').then((m) => m.CompraPage),
    canActivate: [authGuard],
  },
  {
    path: 'caja',
    loadComponent: () => import('./pages/caja/caja.page').then((m) => m.CajaPage),
    canActivate: [authGuard, cajeroGuard],
  },
  {
    path: 'atender-reservas',
    loadComponent: () =>
      import('./pages/atender-reservas/atender-reservas.page').then((m) => m.AtenderReservasPage),
    canActivate: [authGuard, encargadoGuard],
  },

  // Panel de gestion (CU09 a CU13). Cada pantalla exige el mismo permiso que su endpoint.
  {
    path: 'panel',
    canActivate: [authGuard],
    children: [
      {
        path: '',
        loadComponent: () => import('./pages/panel/panel.page').then((m) => m.PanelPage),
      },
      {
        path: 'catalogo',
        loadComponent: () =>
          import('./pages/panel-catalogo/panel-catalogo.page').then((m) => m.PanelCatalogoPage),
        canActivate: [permisoGuard('catalogo.ver', 'catalogo.gestionar')],
      },
      {
        path: 'recepciones',
        loadComponent: () =>
          import('./pages/panel-recepciones/panel-recepciones.page').then(
            (m) => m.PanelRecepcionesPage,
          ),
        canActivate: [
          permisoGuard('recepciones.ver', 'recepciones.registrar', 'recepciones.confirmar'),
        ],
      },
      {
        path: 'proveedores',
        loadComponent: () =>
          import('./pages/panel-proveedores/panel-proveedores.page').then(
            (m) => m.PanelProveedoresPage,
          ),
        canActivate: [permisoGuard('proveedores.ver', 'proveedores.gestionar')],
      },
      {
        path: 'sucursales',
        loadComponent: () =>
          import('./pages/panel-sucursales/panel-sucursales.page').then((m) => m.PanelSucursalesPage),
        canActivate: [permisoGuard('sucursales.ver', 'sucursales.gestionar')],
      },
      {
        path: 'usuarios',
        loadComponent: () =>
          import('./pages/panel-usuarios/panel-usuarios.page').then((m) => m.PanelUsuariosPage),
        canActivate: [permisoGuard('usuarios.ver', 'usuarios.gestionar', 'roles.ver')],
      },
    ],
  },

  { path: '', pathMatch: 'full', redirectTo: 'tienda' },
  { path: '**', redirectTo: 'tienda' },
];
