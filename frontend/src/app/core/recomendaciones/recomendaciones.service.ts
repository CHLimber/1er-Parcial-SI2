import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import { ProductoRecomendadoOut } from './recomendaciones.models';

@Injectable({ providedIn: 'root' })
export class RecomendacionesService {
  private readonly http = inject(HttpClient);

  obtener(limite = 8): Observable<ProductoRecomendadoOut[]> {
    const params = new HttpParams().set('limite', limite);
    return this.http.get<ProductoRecomendadoOut[]>(`${environment.apiUrl}/recomendaciones`, { params });
  }
}
