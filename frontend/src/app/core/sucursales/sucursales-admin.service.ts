import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import { CajaIn, CajaOut, SucursalAdminOut, SucursalIn } from './sucursales-admin.models';

/** CU12 - Gestionar Sucursales. */
@Injectable({ providedIn: 'root' })
export class SucursalesAdminService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/admin/sucursales`;

  ciudades(): Observable<string[]> {
    return this.http.get<string[]>(`${this.base}/ciudades`);
  }

  listar(activa?: boolean | null): Observable<SucursalAdminOut[]> {
    let params = new HttpParams();
    if (activa !== null && activa !== undefined) params = params.set('activa', activa);
    return this.http.get<SucursalAdminOut[]>(this.base, { params });
  }

  crear(datos: SucursalIn): Observable<SucursalAdminOut> {
    return this.http.post<SucursalAdminOut>(this.base, datos);
  }

  actualizar(id: string, datos: SucursalIn): Observable<SucursalAdminOut> {
    return this.http.put<SucursalAdminOut>(`${this.base}/${id}`, datos);
  }

  cambiarEstado(id: string, activa: boolean): Observable<SucursalAdminOut> {
    return this.http.patch<SucursalAdminOut>(`${this.base}/${id}/estado`, { activa });
  }

  listarCajas(sucursalId: string): Observable<CajaOut[]> {
    return this.http.get<CajaOut[]>(`${this.base}/${sucursalId}/cajas`);
  }

  crearCaja(sucursalId: string, datos: CajaIn): Observable<CajaOut> {
    return this.http.post<CajaOut>(`${this.base}/${sucursalId}/cajas`, datos);
  }

  cambiarEstadoCaja(cajaId: string, activa: boolean): Observable<CajaOut> {
    return this.http.patch<CajaOut>(`${this.base}/cajas/${cajaId}/estado`, { activa });
  }
}
