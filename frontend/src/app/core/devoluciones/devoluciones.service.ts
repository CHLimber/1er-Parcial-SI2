import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import {
  DevolucionDetalleOut,
  DevolucionIn,
  DevolucionOut,
  EstadoDevolucion,
  VentaDevolvibleOut,
} from './devoluciones.models';

/** Devoluciones de ventas (PENDIENTES 2.7): registrar, aprobar (reingresa stock) o rechazar. */
@Injectable({ providedIn: 'root' })
export class DevolucionesService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/devoluciones`;

  listar(estado?: EstadoDevolucion | null, venta?: string | null): Observable<DevolucionOut[]> {
    let params = new HttpParams();
    if (estado) params = params.set('estado', estado);
    if (venta) params = params.set('venta', venta);
    return this.http.get<DevolucionOut[]>(this.base, { params });
  }

  buscarVenta(numero: string): Observable<VentaDevolvibleOut> {
    return this.http.get<VentaDevolvibleOut>(`${this.base}/venta`, {
      params: new HttpParams().set('numero', numero),
    });
  }

  obtener(id: string): Observable<DevolucionDetalleOut> {
    return this.http.get<DevolucionDetalleOut>(`${this.base}/${id}`);
  }

  registrar(datos: DevolucionIn): Observable<DevolucionDetalleOut> {
    return this.http.post<DevolucionDetalleOut>(this.base, datos);
  }

  aprobar(id: string): Observable<DevolucionDetalleOut> {
    return this.http.post<DevolucionDetalleOut>(`${this.base}/${id}/aprobar`, {});
  }

  rechazar(id: string, motivo: string): Observable<DevolucionDetalleOut> {
    return this.http.post<DevolucionDetalleOut>(`${this.base}/${id}/rechazar`, { motivo });
  }
}
