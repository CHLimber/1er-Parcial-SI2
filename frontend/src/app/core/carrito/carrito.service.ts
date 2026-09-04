import { HttpClient } from '@angular/common/http';
import { Injectable, inject, signal } from '@angular/core';
import { Observable, tap } from 'rxjs';

import { environment } from '../../../environments/environment';
import { CarritoItemIn, CarritoOut } from './carrito.models';

@Injectable({ providedIn: 'root' })
export class CarritoService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/carrito`;

  private readonly cantidadItemsSignal = signal(0);
  readonly cantidadItems = this.cantidadItemsSignal.asReadonly();

  private registrar(carrito: CarritoOut): CarritoOut {
    this.cantidadItemsSignal.set(carrito.cantidad_items);
    return carrito;
  }

  refrescar(): void {
    this.verCarrito().subscribe({ error: () => this.cantidadItemsSignal.set(0) });
  }

  verCarrito(): Observable<CarritoOut> {
    return this.http.get<CarritoOut>(this.base).pipe(tap((c) => this.registrar(c)));
  }

  agregarItem(item: CarritoItemIn): Observable<CarritoOut> {
    return this.http.post<CarritoOut>(`${this.base}/items`, item).pipe(tap((c) => this.registrar(c)));
  }

  actualizarCantidad(itemId: string, cantidad: number): Observable<CarritoOut> {
    return this.http
      .patch<CarritoOut>(`${this.base}/items/${itemId}`, { cantidad })
      .pipe(tap((c) => this.registrar(c)));
  }

  quitarItem(itemId: string): Observable<CarritoOut> {
    return this.http.delete<CarritoOut>(`${this.base}/items/${itemId}`).pipe(tap((c) => this.registrar(c)));
  }

  crearDesdeReserva(reservaId: string): Observable<CarritoOut> {
    return this.http
      .post<CarritoOut>(`${this.base}/desde-reserva/${reservaId}`, {})
      .pipe(tap((c) => this.registrar(c)));
  }
}
