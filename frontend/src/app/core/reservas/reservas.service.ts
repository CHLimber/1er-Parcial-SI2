import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import { ReservaCrear, ReservaOut } from './reservas.models';

@Injectable({ providedIn: 'root' })
export class ReservasService {
  private readonly http = inject(HttpClient);

  crearReserva(datos: ReservaCrear): Observable<ReservaOut> {
    return this.http.post<ReservaOut>(`${environment.apiUrl}/reservas`, datos);
  }

  listarMisReservas(): Observable<ReservaOut[]> {
    return this.http.get<ReservaOut[]>(`${environment.apiUrl}/reservas`);
  }
}
