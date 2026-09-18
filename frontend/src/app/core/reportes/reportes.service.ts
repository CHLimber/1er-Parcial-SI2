import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import {
  CanalVenta,
  FiltroReportes,
  IndicadoresOut,
  ProductoRankingOut,
  ReservaEstadoOut,
  StockSucursalOut,
  VentaDiariaOut,
  VentaPorSucursalOut,
} from './reportes.models';

function paramsDesdeFiltro(filtro: FiltroReportes, extra: Record<string, string | number> = {}): HttpParams {
  let params = new HttpParams();
  if (filtro.desde) params = params.set('desde', filtro.desde);
  if (filtro.hasta) params = params.set('hasta', filtro.hasta);
  if (filtro.sucursal_id) params = params.set('sucursal_id', filtro.sucursal_id);
  for (const [clave, valor] of Object.entries(extra)) {
    params = params.set(clave, valor);
  }
  return params;
}

@Injectable({ providedIn: 'root' })
export class ReportesService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/reportes`;

  indicadores(filtro: FiltroReportes): Observable<IndicadoresOut> {
    return this.http.get<IndicadoresOut>(`${this.base}/indicadores`, { params: paramsDesdeFiltro(filtro) });
  }

  ventasDiarias(filtro: FiltroReportes, canal?: CanalVenta | null): Observable<VentaDiariaOut[]> {
    const extra: Record<string, string> = canal ? { canal } : {};
    return this.http.get<VentaDiariaOut[]>(`${this.base}/ventas-diarias`, {
      params: paramsDesdeFiltro(filtro, extra),
    });
  }

  ventasPorSucursal(filtro: FiltroReportes): Observable<VentaPorSucursalOut[]> {
    return this.http.get<VentaPorSucursalOut[]>(`${this.base}/ventas-por-sucursal`, {
      params: paramsDesdeFiltro(filtro),
    });
  }

  topProductos(filtro: FiltroReportes, limite = 10): Observable<ProductoRankingOut[]> {
    return this.http.get<ProductoRankingOut[]>(`${this.base}/top-productos`, {
      params: paramsDesdeFiltro(filtro, { limite }),
    });
  }

  stockPorSucursal(sucursalId?: string | null): Observable<StockSucursalOut[]> {
    let params = new HttpParams();
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    return this.http.get<StockSucursalOut[]>(`${this.base}/stock-por-sucursal`, { params });
  }

  reservasPorEstado(sucursalId?: string | null): Observable<ReservaEstadoOut[]> {
    let params = new HttpParams();
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    return this.http.get<ReservaEstadoOut[]>(`${this.base}/reservas-por-estado`, { params });
  }
}
