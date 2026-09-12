import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import {
  DetalleIn,
  EstadoRecepcion,
  MovimientoOut,
  RecepcionDetalleOut,
  RecepcionIn,
  RecepcionOut,
  VarianteBuscadaOut,
} from './recepciones.models';

/** CU09 - Registrar Recepcion de Mercaderia. */
@Injectable({ providedIn: 'root' })
export class RecepcionesService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/recepciones`;

  listar(estado?: EstadoRecepcion | null, proveedorId?: string | null): Observable<RecepcionOut[]> {
    let params = new HttpParams();
    if (estado) params = params.set('estado', estado);
    if (proveedorId) params = params.set('proveedor_id', proveedorId);
    return this.http.get<RecepcionOut[]>(this.base, { params });
  }

  obtener(id: string): Observable<RecepcionDetalleOut> {
    return this.http.get<RecepcionDetalleOut>(`${this.base}/${id}`);
  }

  movimientos(id: string): Observable<MovimientoOut[]> {
    return this.http.get<MovimientoOut[]>(`${this.base}/${id}/movimientos`);
  }

  buscarVariantes(q: string, sucursalId?: string | null): Observable<VarianteBuscadaOut[]> {
    let params = new HttpParams().set('q', q);
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    return this.http.get<VarianteBuscadaOut[]>(`${this.base}/variantes`, { params });
  }

  crear(datos: RecepcionIn): Observable<RecepcionDetalleOut> {
    return this.http.post<RecepcionDetalleOut>(this.base, datos);
  }

  agregarLinea(id: string, linea: DetalleIn): Observable<RecepcionDetalleOut> {
    return this.http.post<RecepcionDetalleOut>(`${this.base}/${id}/detalle`, linea);
  }

  editarLinea(id: string, detalleId: string, linea: DetalleIn): Observable<RecepcionDetalleOut> {
    return this.http.put<RecepcionDetalleOut>(`${this.base}/${id}/detalle/${detalleId}`, linea);
  }

  quitarLinea(id: string, detalleId: string): Observable<RecepcionDetalleOut> {
    return this.http.delete<RecepcionDetalleOut>(`${this.base}/${id}/detalle/${detalleId}`);
  }

  confirmar(id: string): Observable<RecepcionDetalleOut> {
    return this.http.post<RecepcionDetalleOut>(`${this.base}/${id}/confirmar`, {});
  }

  anular(id: string): Observable<RecepcionDetalleOut> {
    return this.http.post<RecepcionDetalleOut>(`${this.base}/${id}/anular`, {});
  }
}
