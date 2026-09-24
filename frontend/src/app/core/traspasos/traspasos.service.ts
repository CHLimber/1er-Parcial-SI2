import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import {
  DireccionTraspaso,
  EstadoTraspaso,
  MovimientoTraspasoOut,
  RecibirIn,
  TraspasoDetalleOut,
  TraspasoIn,
  TraspasoOut,
  VarianteTraspasoOut,
} from './traspasos.models';

/** Traspasos de mercaderia entre sucursales (PENDIENTES 2.7). */
@Injectable({ providedIn: 'root' })
export class TraspasosService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/traspasos`;

  listar(estado?: EstadoTraspaso | null, direccion?: DireccionTraspaso | null): Observable<TraspasoOut[]> {
    let params = new HttpParams();
    if (estado) params = params.set('estado', estado);
    if (direccion) params = params.set('direccion', direccion);
    return this.http.get<TraspasoOut[]>(this.base, { params });
  }

  obtener(id: string): Observable<TraspasoDetalleOut> {
    return this.http.get<TraspasoDetalleOut>(`${this.base}/${id}`);
  }

  movimientos(id: string): Observable<MovimientoTraspasoOut[]> {
    return this.http.get<MovimientoTraspasoOut[]>(`${this.base}/${id}/movimientos`);
  }

  buscarVariantes(
    q: string,
    origenId?: string | null,
    destinoId?: string | null,
  ): Observable<VarianteTraspasoOut[]> {
    let params = new HttpParams().set('q', q);
    if (origenId) params = params.set('origen_id', origenId);
    if (destinoId) params = params.set('destino_id', destinoId);
    return this.http.get<VarianteTraspasoOut[]>(`${this.base}/variantes`, { params });
  }

  crear(datos: TraspasoIn): Observable<TraspasoDetalleOut> {
    return this.http.post<TraspasoDetalleOut>(this.base, datos);
  }

  despachar(id: string): Observable<TraspasoDetalleOut> {
    return this.http.post<TraspasoDetalleOut>(`${this.base}/${id}/despachar`, {});
  }

  recibir(id: string, datos: RecibirIn): Observable<TraspasoDetalleOut> {
    return this.http.post<TraspasoDetalleOut>(`${this.base}/${id}/recibir`, datos);
  }

  anular(id: string): Observable<TraspasoDetalleOut> {
    return this.http.post<TraspasoDetalleOut>(`${this.base}/${id}/anular`, {});
  }
}
