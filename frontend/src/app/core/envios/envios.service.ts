import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import { CotizacionIn, CotizacionOut, EnvioOut } from './envios.models';

@Injectable({ providedIn: 'root' })
export class EnviosService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/envios`;

  cotizar(datos: CotizacionIn): Observable<CotizacionOut> {
    return this.http.post<CotizacionOut>(`${this.base}/cotizar`, datos);
  }

  misEnvios(): Observable<EnvioOut[]> {
    return this.http.get<EnvioOut[]>(`${this.base}/mis`);
  }

  envioDeVenta(ventaId: string): Observable<EnvioOut> {
    return this.http.get<EnvioOut>(`${this.base}/venta/${ventaId}`);
  }
}
