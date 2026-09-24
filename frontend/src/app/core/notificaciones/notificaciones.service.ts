import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, effect, inject, signal, untracked } from '@angular/core';
import { Observable, tap } from 'rxjs';

import { environment } from '../../../environments/environment';
import { AuthService } from '../auth/auth.service';
import {
  CantidadNoLeidasOut,
  LeerTodasOut,
  NotificacionOut,
  NotificacionPaginadoOut,
} from './notificaciones.models';

/** Cada cuanto se reconsulta el contador de la campana. No hay websockets: es polling simple. */
const INTERVALO_POLLING_MS = 60_000;

/**
 * Notificaciones del usuario de la sesion (PENDIENTES.txt 2.19.3), sea cliente o personal.
 *
 * `noLeidas` es el numero del badge de la campana. El polling arranca solo cuando hay sesion y
 * se detiene al cerrarla: lo maneja un `effect` sobre el usuario de `AuthService`, asi que ni la
 * cabecera ni el logout tienen que acordarse de apagarlo. Si cambia el usuario (logout y login
 * con otra cuenta) se reinicia y el contador vuelve a cero antes de la primera consulta.
 */
@Injectable({ providedIn: 'root' })
export class NotificacionesService {
  private readonly http = inject(HttpClient);
  private readonly auth = inject(AuthService);
  private readonly base = `${environment.apiUrl}/notificaciones`;

  readonly noLeidas = signal(0);

  private temporizador: ReturnType<typeof setInterval> | undefined;

  constructor() {
    effect(() => {
      const usuarioId = this.auth.usuario()?.id ?? null;
      untracked(() => {
        this.detenerPolling();
        this.noLeidas.set(0);
        if (usuarioId) this.iniciarPolling();
      });
    });
  }

  listar(pagina = 1, tamanioPagina = 20, soloNoLeidas = false): Observable<NotificacionPaginadoOut> {
    const params = new HttpParams()
      .set('pagina', pagina)
      .set('tamanio_pagina', tamanioPagina)
      .set('solo_no_leidas', soloNoLeidas);
    return this.http
      .get<NotificacionPaginadoOut>(this.base, { params })
      .pipe(tap((respuesta) => this.noLeidas.set(respuesta.no_leidas)));
  }

  marcarLeida(id: string): Observable<NotificacionOut> {
    return this.http.post<NotificacionOut>(`${this.base}/${id}/leida`, {}).pipe(
      // el contador exacto llega en el proximo refresco; mientras tanto se descuenta local
      tap(() => this.noLeidas.update((n) => Math.max(0, n - 1))),
    );
  }

  leerTodas(): Observable<LeerTodasOut> {
    return this.http
      .post<LeerTodasOut>(`${this.base}/leer-todas`, {})
      .pipe(tap(() => this.noLeidas.set(0)));
  }

  /** Reconsulta el contador; los errores se ignoran (la campana no es critica para la pagina). */
  refrescarContador(): void {
    if (!this.auth.estaAutenticado()) return;
    this.http.get<CantidadNoLeidasOut>(`${this.base}/no-leidas/cantidad`).subscribe({
      next: (respuesta) => this.noLeidas.set(respuesta.no_leidas),
      error: () => undefined,
    });
  }

  private iniciarPolling(): void {
    this.refrescarContador();
    this.temporizador = setInterval(() => {
      // con la pestania en segundo plano no vale la pena pegarle a la API
      if (typeof document !== 'undefined' && document.visibilityState === 'hidden') return;
      this.refrescarContador();
    }, INTERVALO_POLLING_MS);
  }

  private detenerPolling(): void {
    clearInterval(this.temporizador);
    this.temporizador = undefined;
  }
}
