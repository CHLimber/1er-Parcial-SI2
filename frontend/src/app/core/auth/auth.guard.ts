import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';

import { AuthService } from './auth.service';

export const authGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  if (auth.estaAutenticado()) return true;

  const router = inject(Router);
  return router.createUrlTree(['/login']);
};

export const invitadoGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  if (!auth.estaAutenticado()) return true;

  const router = inject(Router);
  return router.createUrlTree(['/tienda']);
};

export const cajeroGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);

  if (!auth.estaAutenticado()) return router.createUrlTree(['/login']);

  const usuario = auth.usuario();
  if (usuario?.tipo === 'STAFF' && usuario.rol === 'CAJERO') return true;

  return router.createUrlTree(['/tienda']);
};

export const encargadoGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);

  if (!auth.estaAutenticado()) return router.createUrlTree(['/login']);

  const usuario = auth.usuario();
  if (usuario?.tipo === 'STAFF' && usuario.rol === 'ENCARGADO') return true;

  return router.createUrlTree(['/tienda']);
};
