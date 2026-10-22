import { HttpClient, HttpContext, HttpContextToken } from '@angular/common/http';
import { Injectable, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';

import { offlineDb } from './offline-db';

/** Marca los pedidos que manda la sincronizacion: el interceptor no los vuelve a encolar. */
export const SINCRONIZANDO = new HttpContextToken<boolean>(() => false);

/**
 * Estado online/offline de la PWA (PENDIENTES 5.2) y sincronizacion de la cola. Al volver la red
 * manda en orden lo que quedo en `cola` (IndexedDB); una operacion que el backend rechaza (4xx:
 * p.ej. ya no hay stock) se descarta y se avisa, para no trabar la cola.
 */
@Injectable({ providedIn: 'root' })
export class ConexionService {
  private readonly http = inject(HttpClient);

  readonly enLinea = signal(typeof navigator === 'undefined' ? true : navigator.onLine);
  /** operaciones guardadas sin conexion, todavia no enviadas */
  readonly pendientes = signal(0);
  /** respuesta servida desde la base temporal: cuando se guardo */
  readonly datosDe = signal<string | null>(null);
  readonly ultimoAviso = signal<string | null>(null);
  /** callbacks a correr despues de sincronizar (p.ej. refrescar el contador del carrito) */
  private readonly alSincronizar: (() => void)[] = [];
  private sincronizando = false;

  constructor() {
    if (typeof window === 'undefined') return;
    window.addEventListener('online', () => {
      this.enLinea.set(true);
      this.datosDe.set(null);
      void this.sincronizar();
    });
    window.addEventListener('offline', () => this.enLinea.set(false));
    void this.contarPendientes();
    if (this.enLinea()) void this.sincronizar();
  }

  despuesDeSincronizar(callback: () => void): void {
    this.alSincronizar.push(callback);
  }

  async contarPendientes(): Promise<void> {
    try {
      this.pendientes.set((await offlineDb.pendientes()).length);
    } catch {
      this.pendientes.set(0);
    }
  }

  async sincronizar(): Promise<void> {
    if (this.sincronizando) return;
    this.sincronizando = true;
    let enviadas = 0;
    let descartadas = 0;
    try {
      for (const op of await offlineDb.pendientes()) {
        try {
          await firstValueFrom(
            this.http.request(op.metodo, op.url, {
              body: op.cuerpo,
              context: new HttpContext().set(SINCRONIZANDO, true),
            }),
          );
          enviadas++;
          await offlineDb.quitar(op.id!);
        } catch (error: unknown) {
          const estado = (error as { status?: number }).status ?? 0;
          if (estado === 0 || estado === 504) break; // se volvio a cortar: queda para la proxima
          descartadas++;
          await offlineDb.quitar(op.id!);
        }
      }
    } catch {
      // IndexedDB no disponible: no hay cola que sincronizar
    } finally {
      this.sincronizando = false;
      await this.contarPendientes();
    }
    if (enviadas || descartadas) {
      this.ultimoAviso.set(
        `Volvió la conexión: se sincronizaron ${enviadas} operación(es)` +
          (descartadas ? ` y ${descartadas} ya no se pudieron hacer (por ejemplo, sin stock).` : '.'),
      );
      this.alSincronizar.forEach((callback) => callback());
    }
  }
}
