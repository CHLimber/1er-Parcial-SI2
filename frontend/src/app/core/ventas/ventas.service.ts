import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import { CheckoutIn, CheckoutOut, Pasarela, VentaOut, VentaResumenOut } from './ventas.models';

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
}

export interface WebhookIn {
  evento_id: string;
  id_transaccion: string;
  estado: 'APROBADO' | 'RECHAZADO';
}

export interface WebhookOut {
  procesado: boolean;
  venta_estado: string | null;
  pago_estado: string | null;
  mensaje: string;
}

@Injectable({ providedIn: 'root' })
export class PagosService {
  private readonly http = inject(HttpClient);

  simularWebhook(pasarela: Pasarela, idTransaccion: string, estado: 'APROBADO' | 'RECHAZADO'): Observable<WebhookOut> {
    const body: WebhookIn = {
      evento_id: crypto.randomUUID(),
      id_transaccion: idTransaccion,
      estado,
    };
    return this.http.post<WebhookOut>(`${environment.apiUrl}/pagos/webhook/${pasarela}`, body);
  }
}
