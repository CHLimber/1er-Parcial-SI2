import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../../environments/environment';
import { DashboardAnalitico, MuestraSinteticos, ResumenModelo } from './analitica.models';

/** Modulo G: dashboard de machine learning (CU28) y reentrenamiento de los modelos (CU29). */
@Injectable({ providedIn: 'root' })
export class AnaliticaService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/analitica`;

  dashboard(sucursalId: string | null, horizonte: number): Observable<DashboardAnalitico> {
    let params = new HttpParams().set('horizonte', horizonte);
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    return this.http.get<DashboardAnalitico>(`${this.base}/dashboard`, { params });
  }

  entrenar(semilla: number, dias = 540, clientes = 1500): Observable<ResumenModelo> {
    return this.http.post<ResumenModelo>(`${this.base}/entrenar`, { semilla, dias, clientes });
  }

  muestra(tipo: 'demanda' | 'clientes', limite = 12): Observable<MuestraSinteticos> {
    const params = new HttpParams().set('tipo', tipo).set('limite', limite);
    return this.http.get<MuestraSinteticos>(`${this.base}/datos-sinteticos`, { params });
  }

  /** CSV completo de los datos sinteticos (etapa 1), para bajarlo como archivo. */
  csv(tipo: 'demanda' | 'clientes'): Observable<Blob> {
    const params = new HttpParams().set('tipo', tipo).set('formato', 'csv').set('limite', 20000);
    return this.http.get(`${this.base}/datos-sinteticos`, { params, responseType: 'blob' });
  }
}
