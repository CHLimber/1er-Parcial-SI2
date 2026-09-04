import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import { SucursalOut } from './sucursales.models';

@Injectable({ providedIn: 'root' })
export class SucursalesService {
  private readonly http = inject(HttpClient);

  listarSucursales(): Observable<SucursalOut[]> {
    return this.http.get<SucursalOut[]>(`${environment.apiUrl}/sucursales`);
  }
}
