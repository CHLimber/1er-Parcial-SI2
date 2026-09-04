import { Routes } from '@angular/router';

import { authGuard, invitadoGuard } from './core/auth/auth.guard';

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
  { path: '', pathMatch: 'full', redirectTo: 'tienda' },
  { path: '**', redirectTo: 'tienda' },
];
