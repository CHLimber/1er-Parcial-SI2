import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import { ProveedorIn, ProveedorOut } from './proveedores.models';

/** CU11 - Gestionar Proveedores. */
@Injectable({ providedIn: 'root' })
export class ProveedoresService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/proveedores`;

  listar(q?: string, activo?: boolean | null): Observable<ProveedorOut[]> {
    let params = new HttpParams();
    if (q) params = params.set('q', q);
    if (activo !== null && activo !== undefined) params = params.set('activo', activo);
    return this.http.get<ProveedorOut[]>(this.base, { params });
  }

  crear(datos: ProveedorIn): Observable<ProveedorOut> {
    return this.http.post<ProveedorOut>(this.base, datos);
  }

  actualizar(id: string, datos: ProveedorIn): Observable<ProveedorOut> {
    return this.http.put<ProveedorOut>(`${this.base}/${id}`, datos);
  }

  cambiarEstado(id: string, activo: boolean): Observable<ProveedorOut> {
    return this.http.patch<ProveedorOut>(`${this.base}/${id}/estado`, { activo });
  }
}
