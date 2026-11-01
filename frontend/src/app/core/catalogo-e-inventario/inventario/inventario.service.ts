import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../../environments/environment';
import {
  AjusteIn,
  AjusteOut,
  AlertaInventario,
  MovimientoKardexOut,
  ResumenInventarioOut,
  VarianteBuscadaOut,
} from './inventario.models';

/** Ajustes manuales de stock (PENDIENTES.txt 2.6). */
@Injectable({ providedIn: 'root' })
export class InventarioService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/inventario`;

  /** Sin texto lista las prendas con menos disponible primero; `alerta` filtra las que piden reposicion. */
  buscarVariantes(
    q: string,
    sucursalId?: string | null,
    alerta?: AlertaInventario | null,
  ): Observable<VarianteBuscadaOut[]> {
    let params = new HttpParams().set('q', q);
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    if (alerta) params = params.set('alerta', alerta);
    return this.http.get<VarianteBuscadaOut[]>(`${this.base}/variantes`, { params });
  }

  resumen(sucursalId?: string | null): Observable<ResumenInventarioOut> {
    let params = new HttpParams();
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    return this.http.get<ResumenInventarioOut>(`${this.base}/resumen`, { params });
  }

  kardex(varianteId: string, sucursalId: string, limite = 50): Observable<MovimientoKardexOut[]> {
    const params = new HttpParams().set('sucursal_id', sucursalId).set('limite', limite);
    return this.http.get<MovimientoKardexOut[]>(`${this.base}/${varianteId}/kardex`, { params });
  }

  ajustar(datos: AjusteIn): Observable<AjusteOut> {
    return this.http.post<AjusteOut>(`${this.base}/ajustes`, datos);
  }
}
