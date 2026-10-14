import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import {
  CheckoutSuscripcionIn,
  CheckoutSuscripcionOut,
  PagoManualIn,
  PagoSuscripcionOut,
  PlanOut,
  SuscripcionOut,
} from './saas.models';

/** SaaS (Segundo parcial, PENDIENTES 5.4-5.6): planes y suscripcion de cada tenant (sucursal). */
@Injectable({ providedIn: 'root' })
export class SaasService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/saas`;

  planes(): Observable<PlanOut[]> {
    return this.http.get<PlanOut[]>(`${this.base}/planes`);
  }

  miSuscripcion(sucursalId?: string | null): Observable<SuscripcionOut> {
    let params = new HttpParams();
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    return this.http.get<SuscripcionOut>(`${this.base}/suscripcion`, { params });
  }

  /** Todos los tenants para el ADMIN de la plataforma; el propio para el resto. */
  suscripciones(): Observable<SuscripcionOut[]> {
    return this.http.get<SuscripcionOut[]>(`${this.base}/suscripciones`);
  }

  pagos(sucursalId?: string | null): Observable<PagoSuscripcionOut[]> {
    let params = new HttpParams();
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    return this.http.get<PagoSuscripcionOut[]>(`${this.base}/pagos`, { params });
  }

  /** Crea el pago y devuelve la URL del Checkout hospedado de Stripe. */
  iniciarPago(datos: CheckoutSuscripcionIn): Observable<CheckoutSuscripcionOut> {
    return this.http.post<CheckoutSuscripcionOut>(`${this.base}/suscripcion/checkout`, datos);
  }

  /** Al volver del Checkout: confirma con Stripe y aplica el pago (idempotente con el webhook). */
  verificarPago(sesion: string): Observable<SuscripcionOut> {
    return this.http.post<SuscripcionOut>(`${this.base}/pagos/verificar`, null, {
      params: new HttpParams().set('sesion', sesion),
    });
  }

  pagoManual(sucursalId: string, datos: PagoManualIn): Observable<SuscripcionOut> {
    return this.http.post<SuscripcionOut>(`${this.base}/suscripciones/${sucursalId}/pago-manual`, datos);
  }
}
