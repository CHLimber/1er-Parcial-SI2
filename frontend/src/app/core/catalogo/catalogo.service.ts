import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import { ProductoOut } from './catalogo.models';

@Injectable({ providedIn: 'root' })
export class CatalogoService {
  private readonly http = inject(HttpClient);

  listarProductos(limit = 8): Observable<ProductoOut[]> {
    const params = new HttpParams().set('limit', limit);
    return this.http.get<ProductoOut[]>(`${environment.apiUrl}/catalogo/productos`, { params });
  }
}
