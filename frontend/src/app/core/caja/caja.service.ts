import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import { AbrirSesionIn, CajaOut, SesionCajaOut, VarianteBusquedaOut } from './caja.models';

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
}
