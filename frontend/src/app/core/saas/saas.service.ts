import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import {
  AsignarPlanIn,
  CheckoutSuscripcionIn,
  CheckoutSuscripcionOut,
  EmpresaDatosIn,
  EmpresaIn,
  EmpresaOut,
  PagoManualIn,
  PagoSuscripcionOut,
  PlanIn,
  PlanOut,
  SuscripcionOut,
  TiendaOut,
} from './saas.models';

/** SaaS multi-tenant: planes, suscripcion de cada empresa y administracion de la plataforma. */
@Injectable({ providedIn: 'root' })
export class SaasService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/saas`;

  planes(): Observable<PlanOut[]> {
    return this.http.get<PlanOut[]>(`${this.base}/planes`);
  }

  /** Publico: tiendas activas para el selector de la vitrina. */
  tiendas(): Observable<TiendaOut[]> {
    return this.http.get<TiendaOut[]>(`${this.base}/tiendas`);
  }

  /** La de mi empresa; la plataforma pasa `empresaId`. */
  miSuscripcion(empresaId?: string | null): Observable<SuscripcionOut> {
    let params = new HttpParams();
    if (empresaId) params = params.set('empresa_id', empresaId);
    return this.http.get<SuscripcionOut>(`${this.base}/suscripcion`, { params });
  }

  pagos(empresaId?: string | null): Observable<PagoSuscripcionOut[]> {
    let params = new HttpParams();
    if (empresaId) params = params.set('empresa_id', empresaId);
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

  // --- plataforma (SUPERADMIN) ---------------------------------------------------------------

  empresas(): Observable<EmpresaOut[]> {
    return this.http.get<EmpresaOut[]>(`${this.base}/empresas`);
  }

  registrarEmpresa(datos: EmpresaIn): Observable<EmpresaOut> {
    return this.http.post<EmpresaOut>(`${this.base}/empresas`, datos);
  }

  editarEmpresa(id: string, datos: EmpresaDatosIn): Observable<EmpresaOut> {
    return this.http.put<EmpresaOut>(`${this.base}/empresas/${id}`, datos);
  }

  cambiarEstadoEmpresa(id: string, activa: boolean): Observable<EmpresaOut> {
    return this.http.patch<EmpresaOut>(`${this.base}/empresas/${id}/estado`, { activa });
  }

  asignarPlan(id: string, datos: AsignarPlanIn): Observable<SuscripcionOut> {
    return this.http.put<SuscripcionOut>(`${this.base}/empresas/${id}/plan`, datos);
  }

  pagoManual(empresaId: string, datos: PagoManualIn): Observable<SuscripcionOut> {
    return this.http.post<SuscripcionOut>(`${this.base}/suscripciones/${empresaId}/pago-manual`, datos);
  }

  configurarPlan(codigo: string, datos: PlanIn): Observable<PlanOut> {
    return this.http.put<PlanOut>(`${this.base}/planes/${codigo}`, datos);
  }
}
