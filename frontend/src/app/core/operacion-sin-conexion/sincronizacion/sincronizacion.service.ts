import { HttpClient, HttpContext, HttpErrorResponse, HttpParams } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';

import { environment } from '../../../../environments/environment';
import { AuthService } from '../../acceso-y-organizacion/auth/auth.service';
import { ConexionService, SINCRONIZANDO } from '../offline/conexion.service';
import { offlineDb } from '../offline/offline-db';
import {
  AccionResolver,
  LoteOut,
  OperacionIn,
  OperacionLocal,
  OperacionServidor,
  PaqueteOffline,
  ResultadoOperacion,
} from './sincronizacion.models';

const LOTE = 50;
const REINTENTO_BASE_MS = 30_000;
const REINTENTO_MAX_MS = 10 * 60_000;
const PERIODO_MS = 60_000;

export interface LineaLocal {
  variante_id: string;
  cantidad: number;
}

function uuid(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) return crypto.randomUUID();
  // respaldo para navegadores viejos / contexto no seguro: UUID v4 con Math.random
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  });
}

/** Mismo calculo que el backend (subtotal + IVA 13% redondeado al centavo), en centavos. */
export function totalConIva(lineas: { precio: number; cantidad: number }[], tasa = 0.13): number {
  const subtotal = lineas.reduce((s, l) => s + Math.round(l.precio * 100) * l.cantidad, 0);
  return (subtotal + Math.round(subtotal * tasa)) / 100;
}

/**
 * Operacion offline del personal (Modulos B y D): baja el paquete de la sucursal (CU17), registra
 * ventas de contado y reservas en IndexedDB con un UUID propio (CU19/CU20), las manda al volver la
 * red (CU22) con reintentos y backoff, y guarda lo que contesto el servidor (CU21). Las
 * operaciones nunca se borran por enviarse (RN12): una venta ENVIADA cuya respuesta no llego
 * (se corto la red a mitad) se reenvia con el mismo id y el servidor devuelve lo que ya habia
 * hecho, sin duplicarla (RN11).
 */
@Injectable({ providedIn: 'root' })
export class SincronizacionService {
  private readonly http = inject(HttpClient);
  private readonly auth = inject(AuthService);
  private readonly conexion = inject(ConexionService);
  private readonly base = `${environment.apiUrl}/sync`;

  readonly paquete = signal<PaqueteOffline | null>(null);
  /** cuando se descargo el paquete (para avisar si puede estar desactualizado) */
  readonly paqueteDe = signal<string | null>(null);
  private readonly todas = signal<OperacionLocal[]>([]);
  readonly operaciones = computed(() =>
    this.todas()
      .filter((o) => o.usuario_id === this.auth.usuario()?.id)
      .sort((a, b) => b.op.registrada_en.localeCompare(a.op.registrada_en)),
  );
  readonly pendientes = computed(
    () => this.operaciones().filter((o) => o.estado === 'REGISTRADA' || o.estado === 'ENVIADA').length,
  );
  readonly enConflicto = computed(() => this.operaciones().filter((o) => o.estado === 'CONFLICTO').length);
  readonly sincronizando = signal(false);
  readonly ultimoResultado = signal<string | null>(null);

  private reintentos = 0;
  private temporizador: ReturnType<typeof setTimeout> | null = null;

  constructor() {
    if (typeof window === 'undefined') return;
    void this.cargarLocal();
    window.addEventListener('online', () => void this.sincronizar());
    setInterval(() => {
      if (this.conexion.enLinea() && this.pendientes() > 0) void this.sincronizar();
    }, PERIODO_MS);
  }

  private claveP(): string {
    return `paquete:${this.auth.usuario()?.id ?? 'anonimo'}`;
  }

  async cargarLocal(): Promise<void> {
    try {
      const guardado = await offlineDb.leerPaquete<PaqueteOffline>(this.claveP());
      this.paquete.set(guardado?.datos ?? null);
      this.paqueteDe.set(guardado?.datos.generado_en ?? null);
      this.todas.set(await offlineDb.operaciones<OperacionLocal>());
    } catch {
      // IndexedDB no disponible (modo privado de algunos navegadores): solo online
    }
  }

  /** CU17: baja (o refresca) el paquete offline de la sucursal. Necesita red. */
  async descargarPaquete(sucursalId?: string | null): Promise<PaqueteOffline> {
    let params = new HttpParams();
    if (sucursalId) params = params.set('sucursal_id', sucursalId);
    const paquete = await firstValueFrom(
      this.http.get<PaqueteOffline>(`${this.base}/catalogo`, {
        params,
        context: new HttpContext().set(SINCRONIZANDO, true),
      }),
    );
    // lo vendido offline que todavia no se confirmo ya no esta en el stock del servidor: se
    // vuelve a descontar del paquete nuevo para no ofrecer dos veces la misma prenda
    for (const o of this.operaciones()) {
      if (o.estado === 'REGISTRADA' || o.estado === 'ENVIADA') this.descontar(paquete, this.lineasDe(o.op));
    }
    await offlineDb.guardarPaquete(this.claveP(), paquete);
    this.paquete.set(paquete);
    this.paqueteDe.set(paquete.generado_en);
    return paquete;
  }

  /** CU20: venta de contado registrada localmente (aunque haya red, pasa por la misma cola). */
  async registrarVenta(lineas: LineaLocal[], montoRecibido: number | null, clienteEmail: string | null): Promise<OperacionLocal> {
    const paquete = this.exigirPaquete();
    const precios = this.preciosLocales(paquete);
    const total = totalConIva(lineas.map((l) => ({ precio: precios.get(l.variante_id)!.precio, cantidad: l.cantidad })), paquete.iva_tasa);
    const op: OperacionIn = {
      ...this.cabecera(paquete, 'VENTA'),
      venta: {
        items: lineas.map((l) => ({
          variante_id: l.variante_id,
          cantidad: l.cantidad,
          precio_unitario: precios.get(l.variante_id)!.precio.toFixed(2),
        })),
        metodo_pago: 'EFECTIVO',
        total: total.toFixed(2),
        monto_recibido: montoRecibido !== null ? montoRecibido.toFixed(2) : null,
        sesion_caja_id: paquete.sesion_caja_id,
        cliente_email: clienteEmail,
      },
    };
    const descripcion = lineas.map((l) => `${l.cantidad}× ${precios.get(l.variante_id)!.nombre}`).join(', ');
    return this.guardarNueva(op, `Venta: ${descripcion}`, total, lineas);
  }

  /** CU19: reserva registrada localmente para una clienta de la cartera. */
  async registrarReserva(
    lineas: LineaLocal[],
    clienteEmail: string,
    fechaVisita: string,
    horaVisita: string,
    observaciones: string | null,
  ): Promise<OperacionLocal> {
    const paquete = this.exigirPaquete();
    const precios = this.preciosLocales(paquete);
    const op: OperacionIn = {
      ...this.cabecera(paquete, 'RESERVA'),
      reserva: {
        cliente_email: clienteEmail,
        fecha_visita: fechaVisita,
        hora_visita: horaVisita,
        items: lineas,
        observaciones,
      },
    };
    const descripcion = lineas.map((l) => `${l.cantidad}× ${precios.get(l.variante_id)!.nombre}`).join(', ');
    return this.guardarNueva(op, `Reserva para ${clienteEmail}: ${descripcion}`, 0, lineas);
  }

  /** CU22: manda lo pendiente. Lo dispara el boton, el evento `online` y un temporizador. */
  async sincronizar(): Promise<void> {
    if (this.sincronizando() || !this.conexion.enLinea()) return;
    const porEnviar = this.operaciones()
      .filter((o) => o.estado === 'REGISTRADA' || o.estado === 'ENVIADA')
      .sort((a, b) => a.op.registrada_en.localeCompare(b.op.registrada_en));
    if (!porEnviar.length) return;
    this.sincronizando.set(true);
    let confirmadas = 0;
    let rechazadas = 0;
    let conflictos = 0;
    try {
      for (let i = 0; i < porEnviar.length; i += LOTE) {
        const lote = porEnviar.slice(i, i + LOTE);
        const ahora = new Date().toISOString();
        for (const o of lote) {
          await this.actualizar({ ...o, estado: 'ENVIADA', intentos_envio: o.intentos_envio + 1, ultimo_envio: ahora });
        }
        const respuesta = await firstValueFrom(
          this.http.post<LoteOut>(
            `${this.base}/operaciones`,
            { operaciones: lote.map((o) => o.op) },
            { context: new HttpContext().set(SINCRONIZANDO, true) },
          ),
        );
        for (const r of respuesta.resultados) {
          await this.aplicarRespuesta(r);
        }
        confirmadas += respuesta.confirmadas;
        rechazadas += respuesta.rechazadas;
        conflictos += respuesta.en_conflicto;
      }
      this.reintentos = 0;
      this.ultimoResultado.set(
        `Sincronización: ${confirmadas} confirmada(s), ${rechazadas} rechazada(s), ${conflictos} en conflicto.`,
      );
    } catch (error) {
      // la operacion queda ENVIADA (sin respuesta) y se reintenta con el mismo id
      const e = error as HttpErrorResponse;
      const mensaje =
        e.status === 0 || e.status === 504
          ? 'Sin conexión con el servidor: se reintenta solo.'
          : e.status === 401
            ? 'La sesión expiró: iniciá sesión para sincronizar.'
            : `El servidor respondió ${e.status}: se reintenta más tarde.`;
      for (const o of porEnviar) {
        const actual = this.todas().find((x) => x.id === o.id);
        if (actual?.estado === 'ENVIADA') await this.actualizar({ ...actual, error_red: mensaje });
      }
      this.ultimoResultado.set(mensaje);
      this.programarReintento();
    } finally {
      this.sincronizando.set(false);
    }
  }

  /** CU23: reintentar / aceptar el precio actual / descartar una operacion en conflicto. */
  async resolver(id: string, accion: AccionResolver, nota?: string): Promise<void> {
    const r = await firstValueFrom(
      this.http.post<ResultadoOperacion>(`${this.base}/operaciones/${id}/resolver`, { accion, nota: nota ?? null }),
    );
    await this.aplicarRespuesta(r);
  }

  /** CU21: vuelve a preguntar al servidor como quedo (p.ej. si el encargado lo resolvio). */
  async refrescar(id: string): Promise<void> {
    const r = await firstValueFrom(this.http.get<OperacionServidor>(`${this.base}/operaciones/${id}`));
    await this.aplicarRespuesta(r);
  }

  /** El log del servidor (panel del encargado). */
  logServidor(filtros: { estado?: string | null; solo_abiertas?: boolean; sucursal_id?: string | null; desde?: string | null }) {
    let params = new HttpParams();
    if (filtros.estado) params = params.set('estado', filtros.estado);
    if (filtros.solo_abiertas) params = params.set('solo_abiertas', true);
    if (filtros.sucursal_id) params = params.set('sucursal_id', filtros.sucursal_id);
    if (filtros.desde) params = params.set('desde', filtros.desde);
    return this.http.get<OperacionServidor[]>(`${this.base}/operaciones`, { params });
  }

  resolverEnServidor(id: string, accion: AccionResolver, nota?: string) {
    return this.http.post<ResultadoOperacion>(`${this.base}/operaciones/${id}/resolver`, { accion, nota: nota ?? null });
  }

  /** Saca del dispositivo las operaciones ya cerradas (confirmadas o rechazadas). Es una accion
   * explicita del usuario: las pendientes y en conflicto no se tocan. */
  async archivarCerradas(): Promise<number> {
    const cerradas = this.operaciones().filter((o) => o.estado === 'CONFIRMADA' || o.estado === 'RECHAZADA');
    for (const o of cerradas) await offlineDb.quitarOperacion(o.id);
    this.todas.update((todas) => todas.filter((o) => !cerradas.includes(o)));
    return cerradas.length;
  }

  // ---------------------------------------------------------------------------------------------

  private exigirPaquete(): PaqueteOffline {
    const paquete = this.paquete();
    if (!paquete) throw new Error('Descargá el catálogo de la sucursal antes de operar sin conexión.');
    return paquete;
  }

  private cabecera(paquete: PaqueteOffline, tipo: 'VENTA' | 'RESERVA') {
    return {
      id: uuid(),
      tipo,
      empresa_id: paquete.empresa_id,
      sucursal_id: paquete.sucursal.id,
      usuario_id: this.auth.usuario()!.id,
      registrada_en: new Date().toISOString(),
    };
  }

  private preciosLocales(paquete: PaqueteOffline): Map<string, { precio: number; nombre: string }> {
    const mapa = new Map<string, { precio: number; nombre: string }>();
    for (const p of paquete.productos) {
      for (const v of p.variantes) mapa.set(v.id, { precio: v.precio, nombre: `${p.nombre} ${v.talla}/${v.color}` });
    }
    return mapa;
  }

  private lineasDe(op: OperacionIn): LineaLocal[] {
    return (op.venta?.items ?? op.reserva?.items ?? []).map((i) => ({ variante_id: i.variante_id, cantidad: i.cantidad }));
  }

  private descontar(paquete: PaqueteOffline, lineas: LineaLocal[]): void {
    for (const p of paquete.productos) {
      for (const v of p.variantes) {
        const l = lineas.find((x) => x.variante_id === v.id);
        if (l) v.disponible = Math.max(0, v.disponible - l.cantidad);
      }
    }
  }

  private async guardarNueva(op: OperacionIn, descripcion: string, total: number, lineas: LineaLocal[]): Promise<OperacionLocal> {
    const local: OperacionLocal = {
      id: op.id,
      usuario_id: op.usuario_id,
      estado: 'REGISTRADA',
      op,
      descripcion,
      total,
      intentos_envio: 0,
      ultimo_envio: null,
      error_red: null,
      respuesta: null,
    };
    await offlineDb.guardarOperacion(local);
    this.todas.update((todas) => [...todas, local]);
    // la existencia conocida baja en el dispositivo: no se ofrece de nuevo lo ya vendido/reservado
    const paquete = structuredClone(this.paquete()!);
    this.descontar(paquete, lineas);
    await offlineDb.guardarPaquete(this.claveP(), paquete);
    this.paquete.set(paquete);
    void this.sincronizar();
    return local;
  }

  private async aplicarRespuesta(r: ResultadoOperacion): Promise<void> {
    const actual = this.todas().find((o) => o.id === r.id);
    if (!actual) return;
    await this.actualizar({ ...actual, estado: r.estado, respuesta: r, error_red: null });
  }

  private async actualizar(o: OperacionLocal): Promise<void> {
    await offlineDb.guardarOperacion(o);
    this.todas.update((todas) => todas.map((x) => (x.id === o.id ? o : x)));
  }

  private programarReintento(): void {
    if (this.temporizador) clearTimeout(this.temporizador);
    const espera = Math.min(REINTENTO_BASE_MS * 2 ** this.reintentos, REINTENTO_MAX_MS);
    this.reintentos++;
    this.temporizador = setTimeout(() => void this.sincronizar(), espera);
  }
}
