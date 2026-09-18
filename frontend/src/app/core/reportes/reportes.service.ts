import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import {
  CajaOcupacionOut,
  ClienteRankingOut,
  ConsultaIaOut,
  EnvioEstadoOut,
  FiltroReportes,
  IndicadoresOut,
  MensajeReporteIn,
  ProductoRankingOut,
  ProductoSinMovimientoOut,
  RecepcionPendienteProveedorOut,
  ReservaEstadoOut,
  StockSucursalOut,
  VendedorOut,
  VentaDiariaOut,
  VentaPorSucursalOut,
} from './reportes.models';

function paramsDesdeFiltro(filtro: FiltroReportes, extra: Record<string, string | number> = {}): HttpParams {
  let params = new HttpParams();
  if (filtro.desde) params = params.set('desde', filtro.desde);
  if (filtro.hasta) params = params.set('hasta', filtro.hasta);
  if (filtro.sucursal_id) params = params.set('sucursal_id', filtro.sucursal_id);
  if (filtro.categoria_id) params = params.set('categoria_id', filtro.categoria_id);
  if (filtro.vendedor_id) params = params.set('vendedor_id', filtro.vendedor_id);
  if (filtro.canal) params = params.set('canal', filtro.canal);
  if (filtro.entrega) params = params.set('entrega', filtro.entrega);
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

  ventasDiarias(filtro: FiltroReportes): Observable<VentaDiariaOut[]> {
    return this.http.get<VentaDiariaOut[]>(`${this.base}/ventas-diarias`, { params: paramsDesdeFiltro(filtro) });
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

  enviosPorEstado(sucursalId?: string | null): Observable<EnvioEstadoOut[]> {
    let params = new HttpParams();
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    return this.http.get<EnvioEstadoOut[]>(`${this.base}/envios-por-estado`, { params });
  }

  productosSinMovimiento(sucursalId?: string | null, limite = 50): Observable<ProductoSinMovimientoOut[]> {
    let params = new HttpParams().set('limite', limite);
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    return this.http.get<ProductoSinMovimientoOut[]>(`${this.base}/productos-sin-movimiento`, { params });
  }

  topClientes(sucursalId?: string | null, limite = 10): Observable<ClienteRankingOut[]> {
    let params = new HttpParams().set('limite', limite);
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    return this.http.get<ClienteRankingOut[]>(`${this.base}/top-clientes`, { params });
  }

  ocupacionCajas(sucursalId?: string | null): Observable<CajaOcupacionOut[]> {
    let params = new HttpParams();
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    return this.http.get<CajaOcupacionOut[]>(`${this.base}/ocupacion-cajas`, { params });
  }

  recepcionesPendientes(sucursalId?: string | null): Observable<RecepcionPendienteProveedorOut[]> {
    let params = new HttpParams();
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    return this.http.get<RecepcionPendienteProveedorOut[]>(`${this.base}/recepciones-pendientes`, { params });
  }

  vendedores(sucursalId?: string | null): Observable<VendedorOut[]> {
    let params = new HttpParams();
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    return this.http.get<VendedorOut[]>(`${this.base}/vendedores`, { params });
  }

  consultaIa(mensajes: MensajeReporteIn[]): Observable<ConsultaIaOut> {
    return this.http.post<ConsultaIaOut>(`${this.base}/consulta-ia`, { mensajes });
  }
}
