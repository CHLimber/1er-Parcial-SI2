import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import { FiltrosCatalogo, FiltrosOut, ProductoDetalleOut, ProductoOut } from './catalogo.models';

@Injectable({ providedIn: 'root' })
export class CatalogoService {
  private readonly http = inject(HttpClient);

  listarProductos(filtros: FiltrosCatalogo = {}): Observable<ProductoOut[]> {
    let params = new HttpParams().set('limit', filtros.limit ?? 20).set('offset', filtros.offset ?? 0);
    if (filtros.categoriaSlug) params = params.set('categoria_slug', filtros.categoriaSlug);
    if (filtros.q) params = params.set('q', filtros.q);
    if (filtros.temporadaId) params = params.set('temporada_id', filtros.temporadaId);
    if (filtros.tallaId) params = params.set('talla_id', filtros.tallaId);
    if (filtros.colorId) params = params.set('color_id', filtros.colorId);
    return this.http.get<ProductoOut[]>(`${environment.apiUrl}/catalogo/productos`, { params });
  }

  obtenerFiltros(): Observable<FiltrosOut> {
    return this.http.get<FiltrosOut>(`${environment.apiUrl}/catalogo/filtros`);
  }

  obtenerProducto(slug: string): Observable<ProductoDetalleOut> {
    return this.http.get<ProductoDetalleOut>(`${environment.apiUrl}/catalogo/productos/${slug}`);
  }
}
