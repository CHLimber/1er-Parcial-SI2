import { inject } from '@angular/core';
import { Routes } from '@angular/router';

import {
  authGuard,
  invitadoGuard,
  PERMISO_ATENDER_RESERVAS,
  PERMISO_CAJA,
  permisoGuard,
} from './core/auth/auth.guard';
import { AuthService } from './core/auth/auth.service';
import { primeraSeccionPanel } from './shared/panel/panel-shell';

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
    path: 'mis-compras',
    loadComponent: () =>
      import('./pages/mis-compras/mis-compras.page').then((m) => m.MisComprasPage),
    canActivate: [authGuard],
  },
  {
    path: 'carrito',
    loadComponent: () => import('./pages/carrito/carrito.page').then((m) => m.CarritoPage),
    canActivate: [authGuard],
  },
  {
    path: 'mis-direcciones',
    loadComponent: () =>
      import('./pages/mis-direcciones/mis-direcciones.page').then((m) => m.MisDireccionesPage),
    canActivate: [authGuard],
  },
  {
    // Cambiar mi propia contrasena: CLIENTE y STAFF, sin permiso de CU13 (no gestiona a
    // otro). Se llega desde la cabecera de la tienda y desde panel-shell.
    path: 'cambiar-password',
    loadComponent: () =>
      import('./pages/cambiar-password/cambiar-password.page').then(
        (m) => m.CambiarPasswordPage,
      ),
    canActivate: [authGuard],
  },
  {
    path: 'asistente',
    loadComponent: () => import('./pages/asistente/asistente.page').then((m) => m.AsistentePage),
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
    canActivate: [authGuard, permisoGuard(PERMISO_CAJA)],
  },
  {
    path: 'atender-reservas',
    loadComponent: () =>
      import('./pages/atender-reservas/atender-reservas.page').then((m) => m.AtenderReservasPage),
    canActivate: [authGuard, permisoGuard(PERMISO_ATENDER_RESERVAS)],
  },

  // Panel de gestion (CU09 a CU13). Cada pantalla exige el mismo permiso que su endpoint.
  {
    path: 'panel',
    canActivate: [authGuard],
    children: [
      {
        // Sin pantalla propia: el menu de arriba (panel-shell) ya lista todas las secciones
        // habilitadas para el rol, asi que /panel manda directo a la primera de ellas.
        path: '',
        pathMatch: 'full',
        redirectTo: () => primeraSeccionPanel(inject(AuthService)),
      },
      {
        path: 'catalogo',
        loadComponent: () =>
          import('./pages/panel-catalogo/panel-catalogo.page').then((m) => m.PanelCatalogoPage),
        canActivate: [
          permisoGuard('catalogo.leer', 'catalogo.crear', 'catalogo.actualizar', 'catalogo.eliminar'),
        ],
      },
      {
        path: 'recepciones',
        loadComponent: () =>
          import('./pages/panel-recepciones/panel-recepciones.page').then(
            (m) => m.PanelRecepcionesPage,
          ),
        canActivate: [
          permisoGuard(
            'recepciones.leer',
            'recepciones.crear',
            'recepciones.actualizar',
            'recepciones.eliminar',
          ),
        ],
      },
      {
        path: 'inventario',
        loadComponent: () =>
          import('./pages/panel-inventario/panel-inventario.page').then(
            (m) => m.PanelInventarioPage,
          ),
        canActivate: [permisoGuard('inventario.leer', 'inventario.actualizar')],
      },
      {
        path: 'traspasos',
        loadComponent: () =>
          import('./pages/panel-traspasos/panel-traspasos.page').then((m) => m.PanelTraspasosPage),
        canActivate: [
          permisoGuard('traspasos.leer', 'traspasos.crear', 'traspasos.actualizar', 'traspasos.eliminar'),
        ],
      },
      {
        path: 'devoluciones',
        loadComponent: () =>
          import('./pages/panel-devoluciones/panel-devoluciones.page').then(
            (m) => m.PanelDevolucionesPage,
          ),
        canActivate: [
          permisoGuard('devoluciones.leer', 'devoluciones.crear', 'devoluciones.actualizar'),
        ],
      },
      {
        path: 'proveedores',
        loadComponent: () =>
          import('./pages/panel-proveedores/panel-proveedores.page').then(
            (m) => m.PanelProveedoresPage,
          ),
        canActivate: [
          permisoGuard(
            'proveedores.leer',
            'proveedores.crear',
            'proveedores.actualizar',
            'proveedores.eliminar',
          ),
        ],
      },
      {
        path: 'sucursales',
        loadComponent: () =>
          import('./pages/panel-sucursales/panel-sucursales.page').then((m) => m.PanelSucursalesPage),
        canActivate: [
          permisoGuard(
            'sucursales.leer',
            'sucursales.crear',
            'sucursales.actualizar',
            'sucursales.eliminar',
          ),
        ],
      },
      {
        path: 'usuarios',
        loadComponent: () =>
          import('./pages/panel-usuarios/panel-usuarios.page').then((m) => m.PanelUsuariosPage),
        canActivate: [
          permisoGuard(
            'usuarios.leer',
            'usuarios.crear',
            'usuarios.actualizar',
            'usuarios.eliminar',
            'roles.leer',
          ),
        ],
      },
      {
        path: 'reportes',
        loadComponent: () =>
          import('./pages/panel-reportes/panel-reportes.page').then((m) => m.PanelReportesPage),
        canActivate: [permisoGuard('reportes.leer')],
      },
      {
        path: 'auditoria',
        loadComponent: () =>
          import('./pages/panel-auditoria/panel-auditoria.page').then((m) => m.PanelAuditoriaPage),
        canActivate: [permisoGuard('auditoria.leer')],
      },
    ],
  },

  { path: '', pathMatch: 'full', redirectTo: 'tienda' },
  { path: '**', redirectTo: 'tienda' },
];
