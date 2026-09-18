import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import {
  CotizacionIn,
  CotizacionOut,
  EnvioAdminDetalleOut,
  EnvioAdminOut,
  EnvioOut,
  EstadoEnvio,
  RepartidorOut,
  ResumenEnviosOut,
} from './envios.models';

@Injectable({ providedIn: 'root' })
export class EnviosService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/envios`;
  private readonly baseAdmin = `${environment.apiUrl}/admin/envios`;

  // --- cliente ---

  cotizar(datos: CotizacionIn): Observable<CotizacionOut> {
    return this.http.post<CotizacionOut>(`${this.base}/cotizar`, datos);
  }

  misEnvios(): Observable<EnvioOut[]> {
    return this.http.get<EnvioOut[]>(`${this.base}/mis`);
  }

  envioDeVenta(ventaId: string): Observable<EnvioOut> {
    return this.http.get<EnvioOut>(`${this.base}/venta/${ventaId}`);
  }

  // --- panel de despacho ---

  listar(filtros: {
    estado?: EstadoEnvio | null;
    sucursalId?: string | null;
    soloAbiertos?: boolean;
  }): Observable<EnvioAdminOut[]> {
    let params = new HttpParams();
    if (filtros.estado) params = params.set('estado', filtros.estado);
    if (filtros.sucursalId) params = params.set('sucursal_id', filtros.sucursalId);
    if (filtros.soloAbiertos) params = params.set('solo_abiertos', true);
    return this.http.get<EnvioAdminOut[]>(this.baseAdmin, { params });
  }

  resumen(sucursalId?: string | null): Observable<ResumenEnviosOut> {
    let params = new HttpParams();
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    return this.http.get<ResumenEnviosOut>(`${this.baseAdmin}/resumen`, { params });
  }

  repartidores(sucursalId?: string | null): Observable<RepartidorOut[]> {
    let params = new HttpParams();
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    return this.http.get<RepartidorOut[]>(`${this.baseAdmin}/repartidores`, { params });
  }

  detalle(envioId: string): Observable<EnvioAdminDetalleOut> {
    return this.http.get<EnvioAdminDetalleOut>(`${this.baseAdmin}/${envioId}`);
  }

  asignar(envioId: string, repartidorId: string, observacion?: string | null): Observable<EnvioAdminOut> {
    return this.http.post<EnvioAdminOut>(`${this.baseAdmin}/${envioId}/asignar`, {
      repartidor_id: repartidorId,
      observacion: observacion ?? null,
    });
  }

  cambiarEstado(
    envioId: string,
    estado: EstadoEnvio,
    observacion?: string | null,
  ): Observable<EnvioAdminOut> {
    return this.http.post<EnvioAdminOut>(`${this.baseAdmin}/${envioId}/estado`, {
      estado,
      observacion: observacion ?? null,
    });
  }
}
