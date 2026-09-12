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

/**
 * CU13: guarda por codigo de permiso. Es el espejo de requiere_permiso() del backend, pero solo
 * evita mostrar pantallas inutiles: la autorizacion real la hace la API en cada endpoint.
 */
export function permisoGuard(...codigos: string[]): CanActivateFn {
  return () => {
    const auth = inject(AuthService);
    const router = inject(Router);

    if (!auth.estaAutenticado()) return router.createUrlTree(['/login']);
    if (auth.tienePermiso(...codigos)) return true;

    return router.createUrlTree(['/tienda']);
  };
}
