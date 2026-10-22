import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../../environments/environment';
import { AltaClienteIn, ClienteTenantOut, PerfilClienteIn, Segmento } from './clientes.models';

/** Cartera y perfil de clientas de la sucursal (Segundo parcial, PENDIENTES 5.7). */
@Injectable({ providedIn: 'root' })
export class ClientesService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/clientes`;

  private params(sucursalId?: string | null): HttpParams {
    return sucursalId ? new HttpParams().set('sucursal_id', sucursalId) : new HttpParams();
  }

  listar(sucursalId: string | null, q: string | null, segmento: Segmento | null): Observable<ClienteTenantOut[]> {
    let params = this.params(sucursalId);
    if (q) params = params.set('q', q);
    if (segmento) params = params.set('segmento', segmento);
    return this.http.get<ClienteTenantOut[]>(this.base, { params });
  }

  editarPerfil(usuarioId: string, datos: PerfilClienteIn, sucursalId: string | null): Observable<ClienteTenantOut> {
    return this.http.put<ClienteTenantOut>(`${this.base}/${usuarioId}/perfil`, datos, {
      params: this.params(sucursalId),
    });
  }

  agregar(datos: AltaClienteIn, sucursalId: string | null): Observable<ClienteTenantOut> {
    return this.http.post<ClienteTenantOut>(this.base, datos, { params: this.params(sucursalId) });
  }
}
