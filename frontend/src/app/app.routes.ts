import { inject } from '@angular/core';
import { Routes } from '@angular/router';

import {
  authGuard,
  invitadoGuard,
  PERMISO_ATENDER_RESERVAS,
  PERMISO_CAJA,
  permisoGuard,
} from './core/acceso-y-organizacion/auth/auth.guard';
import { AuthService } from './core/acceso-y-organizacion/auth/auth.service';
import { primeraSeccionPanel } from './shared/panel/panel-shell';

export const routes: Routes = [
  {
    path: 'login',
    loadComponent: () => import('./pages/acceso-y-organizacion/login/login.page').then((m) => m.LoginPage),
    canActivate: [invitadoGuard],
  },
  {
    path: 'registro',
    loadComponent: () => import('./pages/acceso-y-organizacion/registro/registro.page').then((m) => m.RegistroPage),
    canActivate: [invitadoGuard],
  },
  {
    path: 'tienda',
    loadComponent: () => import('./pages/catalogo-e-inventario/tienda/tienda.page').then((m) => m.TiendaPage),
    canActivate: [authGuard],
  },
  {
    path: 'producto/:slug',
    loadComponent: () =>
      import('./pages/catalogo-e-inventario/producto-detalle/producto-detalle.page').then((m) => m.ProductoDetallePage),
    canActivate: [authGuard],
  },
  {
    path: 'reservar',
    loadComponent: () => import('./pages/operacion-comercial/reservar/reservar.page').then((m) => m.ReservarPage),
    canActivate: [authGuard],
  },
  {
    path: 'mis-reservas',
    loadComponent: () =>
      import('./pages/operacion-comercial/mis-reservas/mis-reservas.page').then((m) => m.MisReservasPage),
    canActivate: [authGuard],
  },
  {
    path: 'mis-compras',
    loadComponent: () =>
      import('./pages/operacion-comercial/mis-compras/mis-compras.page').then((m) => m.MisComprasPage),
    canActivate: [authGuard],
  },
  {
    path: 'carrito',
    loadComponent: () => import('./pages/operacion-comercial/carrito/carrito.page').then((m) => m.CarritoPage),
    canActivate: [authGuard],
  },
  {
    path: 'mis-direcciones',
    loadComponent: () =>
      import('./pages/operacion-comercial/mis-direcciones/mis-direcciones.page').then((m) => m.MisDireccionesPage),
    canActivate: [authGuard],
  },
  {
    // Cambiar mi propia contrasena: CLIENTE y STAFF, sin permiso de CU13 (no gestiona a
    // otro). Se llega desde la cabecera de la tienda y desde panel-shell.
    path: 'cambiar-password',
    loadComponent: () =>
      import('./pages/acceso-y-organizacion/cambiar-password/cambiar-password.page').then(
        (m) => m.CambiarPasswordPage,
      ),
    canActivate: [authGuard],
  },
  {
    path: 'asistente',
    loadComponent: () => import('./pages/relacion-con-la-clienta/asistente/asistente.page').then((m) => m.AsistentePage),
    canActivate: [authGuard],
  },
  {
    path: 'pago-simulado/:ventaId',
    loadComponent: () =>
      import('./pages/operacion-comercial/pago-simulado/pago-simulado.page').then((m) => m.PagoSimuladoPage),
    canActivate: [authGuard],
  },
  {
    path: 'compra/:ventaId',
    loadComponent: () => import('./pages/operacion-comercial/compra/compra.page').then((m) => m.CompraPage),
    canActivate: [authGuard],
  },
  {
    path: 'caja',
    loadComponent: () => import('./pages/operacion-comercial/caja/caja.page').then((m) => m.CajaPage),
    canActivate: [authGuard, permisoGuard(PERMISO_CAJA)],
  },
  {
    path: 'atender-reservas',
    loadComponent: () =>
      import('./pages/operacion-comercial/atender-reservas/atender-reservas.page').then((m) => m.AtenderReservasPage),
    canActivate: [authGuard, permisoGuard(PERMISO_ATENDER_RESERVAS)],
  },

  {
    // Operacion sin conexion del personal (PWA): ventas de contado y reservas con sincronizacion
    path: 'offline',
    loadComponent: () =>
      import('./pages/operacion-sin-conexion/venta-offline/venta-offline.page').then((m) => m.VentaOfflinePage),
    canActivate: [authGuard, permisoGuard(PERMISO_CAJA, PERMISO_ATENDER_RESERVAS)],
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
          import('./pages/catalogo-e-inventario/panel-catalogo/panel-catalogo.page').then((m) => m.PanelCatalogoPage),
        canActivate: [
          permisoGuard('catalogo.leer', 'catalogo.crear', 'catalogo.actualizar', 'catalogo.eliminar'),
        ],
      },
      {
        path: 'recepciones',
        loadComponent: () =>
          import('./pages/catalogo-e-inventario/panel-recepciones/panel-recepciones.page').then(
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
          import('./pages/catalogo-e-inventario/panel-inventario/panel-inventario.page').then(
            (m) => m.PanelInventarioPage,
          ),
        canActivate: [permisoGuard('inventario.leer', 'inventario.actualizar')],
      },
      {
        path: 'traspasos',
        loadComponent: () =>
          import('./pages/catalogo-e-inventario/panel-traspasos/panel-traspasos.page').then((m) => m.PanelTraspasosPage),
        canActivate: [
          permisoGuard('traspasos.leer', 'traspasos.crear', 'traspasos.actualizar', 'traspasos.eliminar'),
        ],
      },
      {
        path: 'devoluciones',
        loadComponent: () =>
          import('./pages/operacion-comercial/panel-devoluciones/panel-devoluciones.page').then(
            (m) => m.PanelDevolucionesPage,
          ),
        canActivate: [
          permisoGuard('devoluciones.leer', 'devoluciones.crear', 'devoluciones.actualizar'),
        ],
      },
      {
        path: 'proveedores',
        loadComponent: () =>
          import('./pages/catalogo-e-inventario/panel-proveedores/panel-proveedores.page').then(
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
          import('./pages/acceso-y-organizacion/panel-sucursales/panel-sucursales.page').then((m) => m.PanelSucursalesPage),
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
          import('./pages/acceso-y-organizacion/panel-usuarios/panel-usuarios.page').then((m) => m.PanelUsuariosPage),
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
          import('./pages/inteligencia-de-negocio/panel-reportes/panel-reportes.page').then((m) => m.PanelReportesPage),
        canActivate: [permisoGuard('reportes.leer')],
      },
      {
        // Segundo parcial (PENDIENTES 5.7): cartera y perfil de clientas por tenant
        path: 'clientes',
        loadComponent: () =>
          import('./pages/relacion-con-la-clienta/panel-clientes/panel-clientes.page').then((m) => m.PanelClientesPage),
        canActivate: [permisoGuard('clientes.leer', 'clientes.actualizar')],
      },
      {
        // Segundo parcial (PENDIENTES 5.4-5.6): plan y pago de la suscripcion del tenant
        path: 'suscripcion',
        loadComponent: () =>
          import('./pages/plataforma-saas/panel-suscripcion/panel-suscripcion.page').then((m) => m.PanelSuscripcionPage),
        canActivate: [permisoGuard('suscripciones.leer', 'suscripciones.actualizar')],
      },
      {
        // Modulo G: dashboard de machine learning (plan Profesional; el backend da 403 si no)
        path: 'analitica',
        loadComponent: () =>
          import('./pages/inteligencia-de-negocio/panel-analitica/panel-analitica.page').then((m) => m.PanelAnaliticaPage),
        canActivate: [permisoGuard('analitica.leer')],
      },
      {
        // Modulo D: log de operaciones offline recibidas y resolucion de conflictos (CU24/CU23)
        path: 'sincronizacion',
        loadComponent: () =>
          import('./pages/operacion-sin-conexion/panel-sincronizacion/panel-sincronizacion.page').then(
            (m) => m.PanelSincronizacionPage,
          ),
        canActivate: [permisoGuard('sincronizacion.leer', 'sincronizacion.actualizar')],
      },
      {
        // Plataforma SaaS: empresas contratantes y configuracion de planes
        path: 'empresas',
        loadComponent: () =>
          import('./pages/plataforma-saas/panel-empresas/panel-empresas.page').then((m) => m.PanelEmpresasPage),
        canActivate: [permisoGuard('empresas.leer')],
      },
      {
        path: 'auditoria',
        loadComponent: () =>
          import('./pages/acceso-y-organizacion/panel-auditoria/panel-auditoria.page').then((m) => m.PanelAuditoriaPage),
        canActivate: [permisoGuard('auditoria.leer')],
      },
    ],
  },

  { path: '', pathMatch: 'full', redirectTo: 'tienda' },
  { path: '**', redirectTo: 'tienda' },
];
