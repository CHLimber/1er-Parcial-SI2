import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import {
  AbrirSesionIn,
  ArqueoOut,
  CajaOut,
  CerrarSesionIn,
  PagoPorVerificarOut,
  ResolucionPagoOut,
  SesionCajaOut,
  SesionCerradaOut,
  VarianteBusquedaOut,
} from './caja.models';

@Injectable({ providedIn: 'root' })
export class CajaService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/caja`;

  listarCajas(): Observable<CajaOut[]> {
    return this.http.get<CajaOut[]>(`${this.base}/cajas`);
  }

  obtenerSesionActual(): Observable<SesionCajaOut | null> {
    return this.http.get<SesionCajaOut | null>(`${this.base}/sesion-actual`);
  }

  abrirSesion(datos: AbrirSesionIn): Observable<SesionCajaOut> {
    return this.http.post<SesionCajaOut>(`${this.base}/abrir`, datos);
  }

  buscarVariante(codigo: string): Observable<VarianteBusquedaOut> {
    const params = new HttpParams().set('codigo', codigo);
    return this.http.get<VarianteBusquedaOut>(`${this.base}/buscar-variante`, { params });
  }

  obtenerArqueo(): Observable<ArqueoOut> {
    return this.http.get<ArqueoOut>(`${this.base}/arqueo`);
  }

  cerrarSesion(datos: CerrarSesionIn): Observable<SesionCerradaOut> {
    return this.http.post<SesionCerradaOut>(`${this.base}/cerrar`, datos);
  }

  listarPagosPendientes(): Observable<PagoPorVerificarOut[]> {
    return this.http.get<PagoPorVerificarOut[]>(`${this.base}/pagos-pendientes`);
  }

  aprobarPago(pagoId: string): Observable<ResolucionPagoOut> {
    return this.http.post<ResolucionPagoOut>(`${this.base}/pagos/${pagoId}/aprobar`, {});
  }

  rechazarPago(pagoId: string, motivo: string | null): Observable<ResolucionPagoOut> {
    return this.http.post<ResolucionPagoOut>(`${this.base}/pagos/${pagoId}/rechazar`, { motivo });
  }
}
