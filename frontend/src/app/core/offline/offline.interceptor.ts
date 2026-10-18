import { HttpErrorResponse, HttpInterceptorFn, HttpRequest, HttpResponse } from '@angular/common/http';
import { inject } from '@angular/core';
import { Observable, catchError, from, mergeMap, tap, throwError } from 'rxjs';

import { environment } from '../../../environments/environment';
import { ConexionService, SINCRONIZANDO } from './conexion.service';
import { offlineDb } from './offline-db';

/**
 * Funcionamiento offline/online de la PWA (Segundo parcial, PENDIENTES 5.2), sobre la base
 * temporal de offline-db.ts:
 *   - GET a la API que se pueden mostrar sin red (CACHEABLES): red primero; cada respuesta buena
 *     se guarda en IndexedDB y, si la red falla (sinRed), se responde con lo guardado.
 *   - Escrituras ENCOLABLES (agregar al carrito) sin conexion: se guardan en la cola y se mandan
 *     solas cuando vuelve la red (ConexionService.sincronizar). La pantalla recibe un 503 con un
 *     `detail` que explica eso, y interpretarError lo muestra tal cual.
 * Lo demas (pagar, reservar, gestion) necesita red de verdad: falla como siempre.
 */
const CACHEABLES = [
  /\/catalogo(\/|\?|$)/,
  /\/sucursales(\/|\?|$)/,
  /\/recomendaciones(\/|\?|$)/,
  /\/carrito(\?|$)/,
  /\/reservas(\?|$)/,
  /\/ventas(\?|$)/,
  /\/notificaciones(\/|\?|$)/,
  /\/direcciones(\?|$)/,
  /\/saas\/planes$/,
];

const ENCOLABLES: { metodo: string; patron: RegExp; descripcion: string; aviso: string }[] = [
  {
    metodo: 'POST',
    patron: /\/carrito\/items$/,
    descripcion: 'Agregar prenda al carrito',
    aviso: 'Sin conexión: guardamos la prenda y la agregamos a tu carrito apenas vuelva la red.',
  },
];

/** Sin red el navegador da status 0, pero con el service worker activo la respuesta es un 504
 * "Gateway Timeout" que arma el propio SW: los dos significan "no hubo red". */
function sinRed(error: HttpErrorResponse): boolean {
  return error.status === 0 || (error.status === 504 && error.statusText === 'Gateway Timeout');
}

function esDeLaApi(req: HttpRequest<unknown>): boolean {
  return req.url.startsWith(environment.apiUrl);
}

export const offlineInterceptor: HttpInterceptorFn = (req, next) => {
  if (!esDeLaApi(req) || req.context.get(SINCRONIZANDO)) return next(req);
  const conexion = inject(ConexionService);
  const ruta = req.url.slice(environment.apiUrl.length);

  if (req.method === 'GET' && CACHEABLES.some((p) => p.test(ruta))) {
    // la misma URL devuelve otra cosa segun el tenant (X-Empresa): sin esto, una clienta que
    // cambia de tienda sin red veria el catalogo cacheado de la anterior
    const clave = `${req.headers.get('X-Empresa') ?? ''}|${req.urlWithParams}`;
    return next(req).pipe(
      tap((evento) => {
        if (evento instanceof HttpResponse && evento.ok) void offlineDb.guardarRespuesta(clave, evento.body).catch(() => null);
      }),
      catchError((error: HttpErrorResponse) =>
        !sinRed(error)
          ? throwError(() => error)
          : (from(offlineDb.leerRespuesta(clave).catch(() => undefined)).pipe(
              mergeMap((guardada) => {
                if (!guardada) return throwError(() => error);
                conexion.datosDe.set(guardada.guardadoEn);
                return [new HttpResponse({ status: 200, body: guardada.cuerpo, url: clave })];
              }),
            ) as Observable<HttpResponse<unknown>>),
      ),
    );
  }

  const encolable = ENCOLABLES.find((e) => e.metodo === req.method && e.patron.test(ruta));
  if (!encolable) return next(req);

  const encolar = () =>
    from(
      offlineDb
        .encolar({ metodo: req.method as 'POST', url: req.url, cuerpo: req.body, descripcion: encolable.descripcion })
        .then(() => conexion.contarPendientes()),
    ).pipe(
      mergeMap(() =>
        throwError(
          () => new HttpErrorResponse({ status: 503, url: req.url, error: { detail: encolable.aviso, encolada: true } }),
        ),
      ),
    );

  if (!conexion.enLinea()) return encolar();
  return next(req).pipe(catchError((error: HttpErrorResponse) => (sinRed(error) ? encolar() : throwError(() => error))));
};
