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
