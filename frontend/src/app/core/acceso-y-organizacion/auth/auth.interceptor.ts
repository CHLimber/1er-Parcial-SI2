import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { catchError, throwError } from 'rxjs';

import { environment } from '../../../../environments/environment';
import { tiendaActual } from '../../nucleo/tenant/tienda';
import { AuthService } from './auth.service';
import { guardarAvisoLogin } from './aviso-login';

/** Motivos con los que el backend corta a TODO el personal de una empresa (cabecera X-Motivo). */
const MOTIVOS_DE_BLOQUEO = ['EMPRESA_SUSPENDIDA', 'SUSCRIPCION_VENCIDA'];

/** Adjunta el Bearer y el tenant (X-Empresa) a todo lo que va a la API. El personal opera
 * siempre su propia empresa; la clienta, la tienda que esta mirando. Si la API responde que la
 * empresa quedo suspendida o con la suscripcion vencida, cierra la sesion y lleva al login con
 * el motivo, en vez de dejar al usuario en pantallas que fallan una por una. */
export const authInterceptor: HttpInterceptorFn = (req, next) => {
  if (!req.url.startsWith(environment.apiUrl)) {
    return next(req);
  }
  const auth = inject(AuthService);
  const router = inject(Router);
  const token = auth.token;
  const headers: Record<string, string> = {
    'X-Empresa': auth.usuario()?.empresa_slug ?? tiendaActual(),
  };
  if (token) headers['Authorization'] = `Bearer ${token}`;
  return next(req.clone({ setHeaders: headers })).pipe(
    catchError((error: HttpErrorResponse) => {
      const motivo = error.headers?.get('X-Motivo');
      // sin sesion no hay nada que cerrar (es el propio login el que rebota)
      if (token && motivo && MOTIVOS_DE_BLOQUEO.includes(motivo)) {
        const detalle = error.error?.detail;
        guardarAvisoLogin(typeof detalle === 'string' ? detalle : 'Tu empresa no puede usar la plataforma.');
        auth.cerrarSesion();
        void router.navigateByUrl('/login');
      }
      return throwError(() => error);
    }),
  );
};
