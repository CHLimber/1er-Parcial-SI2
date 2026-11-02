import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../../environments/environment';
import {
  AprobacionIn,
  CambiosMesOut,
  DevolucionDetalleOut,
  DevolucionIn,
  DevolucionOut,
  EstadoDevolucion,
  MotivoDevolucion,
  NotaDevolucionOut,
  OpcionesDevolucionOut,
  OrigenDevolucion,
  PendientesDevolucionOut,
  SolicitudClienteIn,
  TipoDevolucion,
  VarianteCambioOut,
  VentaDevolvibleOut,
} from './devoluciones.models';

export interface FiltroDevoluciones {
  tipo?: TipoDevolucion | null;
  origen?: OrigenDevolucion | null;
  estado?: EstadoDevolucion | null;
  venta?: string | null;
  motivo_tipo?: MotivoDevolucion | null;
  desde?: string | null;
  hasta?: string | null;
}

/** Devoluciones e intercambios, lado del personal: registrar en caja, aceptar las solicitudes
 * online, concretar (stock + plata) o rechazar. */
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

  /** Cuántas solicitudes esperan al personal de la sucursal. */
  pendientes(): Observable<PendientesDevolucionOut> {
    return this.http.get<PendientesDevolucionOut>(`${this.base}/pendientes`);
  }

  /** Otras tallas/colores de la misma prenda con su precio y disponible, para elegir el cambio. */
  variantesCambio(varianteId: string, sucursalId: string): Observable<VarianteCambioOut[]> {
    return this.http.get<VarianteCambioOut[]>(`${this.base}/variantes-cambio`, {
      params: new HttpParams().set('variante_id', varianteId).set('sucursal_id', sucursalId),
    });
  }

  /** Qué prendas solicitaron cambio en el mes (PENDIENTES 5.10). */
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

  /** Acepta una solicitud online: la sucursal espera a la clienta. */
  confirmar(id: string): Observable<DevolucionDetalleOut> {
    return this.http.post<DevolucionDetalleOut>(`${this.base}/${id}/confirmar`, {});
  }

  /** Concreta en caja: reingresa el stock, devuelve la plata o cobra la diferencia. */
  aprobar(id: string, datos: AprobacionIn = {}): Observable<DevolucionDetalleOut> {
    return this.http.post<DevolucionDetalleOut>(`${this.base}/${id}/aprobar`, datos);
  }

  rechazar(id: string, motivo: string): Observable<DevolucionDetalleOut> {
    return this.http.post<DevolucionDetalleOut>(`${this.base}/${id}/rechazar`, { motivo });
  }
}

/** Lado de la clienta: pedir una devolución o un intercambio desde Mis compras. */
@Injectable({ providedIn: 'root' })
export class MisDevolucionesService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/mis-devoluciones`;

  listar(): Observable<DevolucionDetalleOut[]> {
    return this.http.get<DevolucionDetalleOut[]>(this.base);
  }

  opciones(ventaId: string): Observable<OpcionesDevolucionOut> {
    return this.http.get<OpcionesDevolucionOut>(`${this.base}/venta/${ventaId}`);
  }

  solicitar(datos: SolicitudClienteIn): Observable<DevolucionDetalleOut> {
    return this.http.post<DevolucionDetalleOut>(this.base, datos);
  }

  cancelar(id: string): Observable<DevolucionDetalleOut> {
    return this.http.post<DevolucionDetalleOut>(`${this.base}/${id}/cancelar`, {});
  }
}
