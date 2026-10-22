import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';

import { environment } from '../../../../environments/environment';
import { tiendaActual } from '../../nucleo/tenant/tienda';
import { AuthService } from './auth.service';

/** Adjunta el Bearer y el tenant (X-Empresa) a todo lo que va a la API. El personal opera
 * siempre su propia empresa; la clienta, la tienda que esta mirando. */
export const authInterceptor: HttpInterceptorFn = (req, next) => {
  if (!req.url.startsWith(environment.apiUrl)) {
    return next(req);
  }
  const auth = inject(AuthService);
  const token = auth.token;
  const headers: Record<string, string> = {
    'X-Empresa': auth.usuario()?.empresa_slug ?? tiendaActual(),
  };
  if (token) headers['Authorization'] = `Bearer ${token}`;
  return next(req.clone({ setHeaders: headers }));
};
