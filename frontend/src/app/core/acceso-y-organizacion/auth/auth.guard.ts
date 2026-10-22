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

/**
 * CU07 (caja) y CU08 (atender reservas) tambien se guardan por permiso (PENDIENTES 3.1), no por
 * rol ni cargo: son los mismos codigos que exigen get_cajero_actual / get_encargado_actual.
 */
export const PERMISO_CAJA = 'caja.crear';
export const PERMISO_ATENDER_RESERVAS = 'reservas.actualizar';
