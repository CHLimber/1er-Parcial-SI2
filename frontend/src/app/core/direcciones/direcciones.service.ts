import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import { BusquedaDireccionOut, DireccionIn, DireccionOut } from './direcciones.models';

@Injectable({ providedIn: 'root' })
export class DireccionesService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/direcciones`;

  listar(): Observable<DireccionOut[]> {
    return this.http.get<DireccionOut[]>(this.base);
  }

  crear(datos: DireccionIn): Observable<DireccionOut> {
    return this.http.post<DireccionOut>(this.base, datos);
  }

  actualizar(id: string, datos: DireccionIn): Observable<DireccionOut> {
    return this.http.put<DireccionOut>(`${this.base}/${id}`, datos);
  }

  marcarPrincipal(id: string): Observable<DireccionOut> {
    return this.http.post<DireccionOut>(`${this.base}/${id}/principal`, {});
  }

  eliminar(id: string): Observable<void> {
    return this.http.delete<void>(`${this.base}/${id}`);
  }

  /** Geocodificacion directa: de texto a coordenadas (Pelias de openrouteservice). */
  buscar(texto: string): Observable<BusquedaDireccionOut> {
    return this.http.get<BusquedaDireccionOut>(`${this.base}/buscar`, {
      params: new HttpParams().set('texto', texto),
    });
  }

  /** Geocodificacion inversa: que direccion hay donde se solto el pin del mapa. */
  inversa(latitud: number, longitud: number): Observable<BusquedaDireccionOut> {
    return this.http.get<BusquedaDireccionOut>(`${this.base}/inversa`, {
      params: new HttpParams().set('latitud', latitud).set('longitud', longitud),
    });
  }
}
