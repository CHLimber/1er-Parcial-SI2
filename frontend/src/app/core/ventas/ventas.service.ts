import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import {
  CheckoutIn,
  CheckoutOut,
  VentaOut,
  VentaPosIn,
  VentaPosOut,
  VentaResumenOut,
} from './ventas.models';

@Injectable({ providedIn: 'root' })
export class VentasService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/ventas`;

  checkout(datos: CheckoutIn): Observable<CheckoutOut> {
    return this.http.post<CheckoutOut>(`${this.base}/checkout`, datos);
  }

  obtenerVenta(ventaId: string): Observable<VentaOut> {
    return this.http.get<VentaOut>(`${this.base}/${ventaId}`);
  }

  listarMisCompras(): Observable<VentaResumenOut[]> {
    return this.http.get<VentaResumenOut[]>(this.base);
  }

  registrarVentaPos(datos: VentaPosIn): Observable<VentaPosOut> {
    return this.http.post<VentaPosOut>(`${this.base}/pos`, datos);
  }
}

/** 2.19.1.c: la clienta solo informa que pagó el QR; lo aprueba el cajero desde caja. */
export interface InformarPagoIn {
  referencia: string | null;
}

export interface InformarPagoOut {
  venta_id: string;
  pago_id: string;
  pago_estado: string;
  informado_en: string;
  referencia_cliente: string | null;
  mensaje: string;
}

export interface ConfigPagoOut {
  stripe_publishable_key: string;
}

@Injectable({ providedIn: 'root' })
export class PagosService {
  private readonly http = inject(HttpClient);

  informarPagoQr(ventaId: string, referencia: string | null): Observable<InformarPagoOut> {
    const body: InformarPagoIn = { referencia };
    return this.http.post<InformarPagoOut>(`${environment.apiUrl}/pagos/qr/${ventaId}/informar`, body);
  }

  obtenerConfig(): Observable<ConfigPagoOut> {
    return this.http.get<ConfigPagoOut>(`${environment.apiUrl}/pagos/config`);
  }
}
