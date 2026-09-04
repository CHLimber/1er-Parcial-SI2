import { Routes } from '@angular/router';

import { authGuard, invitadoGuard } from './core/auth/auth.guard';

export const routes: Routes = [
  {
    path: 'login',
    loadComponent: () => import('./pages/login/login.page').then((m) => m.LoginPage),
    canActivate: [invitadoGuard],
  },
  {
    path: 'tienda',
    loadComponent: () => import('./pages/tienda/tienda.page').then((m) => m.TiendaPage),
    canActivate: [authGuard],
  },
  { path: '', pathMatch: 'full', redirectTo: 'tienda' },
  { path: '**', redirectTo: 'tienda' },
];
