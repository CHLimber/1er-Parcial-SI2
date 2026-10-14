import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import {
  CambiosMesOut,
  DevolucionDetalleOut,
  DevolucionIn,
  DevolucionOut,
  EstadoDevolucion,
  MotivoDevolucion,
  NotaDevolucionOut,
  VarianteCambioOut,
  VentaDevolvibleOut,
} from './devoluciones.models';

export interface FiltroDevoluciones {
  estado?: EstadoDevolucion | null;
  venta?: string | null;
  motivo_tipo?: MotivoDevolucion | null;
  desde?: string | null;
  hasta?: string | null;
}

/** Devoluciones de ventas (PENDIENTES 2.7): registrar, aprobar (reingresa stock) o rechazar. */
@Injectable({ providedIn: 'root' })
export class DevolucionesService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/devoluciones`;

  listar(filtro: FiltroDevoluciones = {}): Observable<DevolucionOut[]> {
    let params = new HttpParams();
    for (const [clave, valor] of Object.entries(filtro)) {
      if (valor) params = params.set(clave, valor);
    }
    return this.http.get<DevolucionOut[]>(this.base, { params });
  }

  /** Otras tallas/colores de la misma prenda con su disponible, para elegir el cambio. */
  variantesCambio(varianteId: string, sucursalId: string): Observable<VarianteCambioOut[]> {
    return this.http.get<VarianteCambioOut[]>(`${this.base}/variantes-cambio`, {
      params: new HttpParams().set('variante_id', varianteId).set('sucursal_id', sucursalId),
    });
  }

  /** Que prendas solicitaron cambio en el mes (PENDIENTES 5.10). */
  cambiosDelMes(anio: number, mes: number, incluirOtrosMotivos = false): Observable<CambiosMesOut> {
    return this.http.get<CambiosMesOut>(`${this.base}/cambios-mes`, {
      params: new HttpParams()
        .set('anio', anio)
        .set('mes', mes)
        .set('incluir_otros_motivos', incluirOtrosMotivos),
    });
  }

  nota(id: string): Observable<NotaDevolucionOut> {
    return this.http.get<NotaDevolucionOut>(`${this.base}/${id}/nota`);
  }

  buscarVenta(numero: string): Observable<VentaDevolvibleOut> {
    return this.http.get<VentaDevolvibleOut>(`${this.base}/venta`, {
      params: new HttpParams().set('numero', numero),
    });
  }

  obtener(id: string): Observable<DevolucionDetalleOut> {
    return this.http.get<DevolucionDetalleOut>(`${this.base}/${id}`);
  }

  registrar(datos: DevolucionIn): Observable<DevolucionDetalleOut> {
    return this.http.post<DevolucionDetalleOut>(this.base, datos);
  }

  aprobar(id: string): Observable<DevolucionDetalleOut> {
    return this.http.post<DevolucionDetalleOut>(`${this.base}/${id}/aprobar`, {});
  }

  rechazar(id: string, motivo: string): Observable<DevolucionDetalleOut> {
    return this.http.post<DevolucionDetalleOut>(`${this.base}/${id}/rechazar`, { motivo });
  }

  /** Cambio de prenda: vincula la venta nueva (cobrada en caja) a una devolución aprobada. */
  vincularCambio(id: string, ventaNumero: string): Observable<DevolucionDetalleOut> {
    return this.http.post<DevolucionDetalleOut>(`${this.base}/${id}/cambio`, {
      venta_numero: ventaNumero,
    });
  }
}
