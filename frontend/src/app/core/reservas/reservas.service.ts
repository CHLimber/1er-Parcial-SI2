import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import {
  MarcarPresenteIn,
  PrepararReservaIn,
  ReservaCrear,
  ReservaOut,
  ReservaStaffOut,
  ResolverReservaIn,
  ResolverReservaOut,
} from './reservas.models';

@Injectable({ providedIn: 'root' })
export class ReservasService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/reservas`;

  crearReserva(datos: ReservaCrear): Observable<ReservaOut> {
    return this.http.post<ReservaOut>(this.base, datos);
  }

  listarMisReservas(): Observable<ReservaOut[]> {
    return this.http.get<ReservaOut[]>(this.base);
  }

  // --- CU08: Atender Reserva (Encargado de Sucursal) ------------------------

  listarReservasSucursal(estado?: string): Observable<ReservaStaffOut[]> {
    const params = estado ? new HttpParams().set('estado', estado) : undefined;
    return this.http.get<ReservaStaffOut[]>(`${this.base}/sucursal`, { params });
  }

  obtenerReservaSucursal(reservaId: string): Observable<ReservaStaffOut> {
    return this.http.get<ReservaStaffOut>(`${this.base}/sucursal/${reservaId}`);
  }

  prepararReserva(reservaId: string, datos: PrepararReservaIn): Observable<ReservaStaffOut> {
    return this.http.post<ReservaStaffOut>(`${this.base}/${reservaId}/preparar`, datos);
  }

  marcarClientePresente(reservaId: string, datos: MarcarPresenteIn): Observable<ReservaStaffOut> {
    return this.http.post<ReservaStaffOut>(`${this.base}/${reservaId}/presente`, datos);
  }

  resolverReserva(reservaId: string, datos: ResolverReservaIn): Observable<ResolverReservaOut> {
    return this.http.post<ResolverReservaOut>(`${this.base}/${reservaId}/resolver`, datos);
  }

  marcarNoPresentado(reservaId: string): Observable<ReservaStaffOut> {
    return this.http.post<ReservaStaffOut>(`${this.base}/${reservaId}/no-presentado`, {});
  }
}
