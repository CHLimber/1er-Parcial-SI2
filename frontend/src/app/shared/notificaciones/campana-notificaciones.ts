import { DatePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, ElementRef, computed, inject, signal } from '@angular/core';
import { Router } from '@angular/router';

import { AuthService } from '../../core/auth/auth.service';
import { PERMISO_ATENDER_RESERVAS, PERMISO_CAJA } from '../../core/auth/auth.guard';
import { NotificacionOut } from '../../core/notificaciones/notificaciones.models';
import { NotificacionesService } from '../../core/notificaciones/notificaciones.service';
import { interpretarError } from '../errores';

const TAMANIO_PAGINA = 15;

/**
 * Campana de notificaciones (PENDIENTES.txt 2.19.3): icono con el contador de no leidas y un
 * panel desplegable con la lista. Vive en la cabecera de la tienda y en `panel-shell`, sobre
 * fondo `--ink`. El contador lo mantiene `NotificacionesService` por polling; la lista se pide
 * recien al abrir el panel.
 *
 * Tocar un aviso lo marca como leido y, si hay una pantalla que lo explique, navega a ella
 * (ver `destino`). En telefono el panel deja de colgar de la campana y pasa a ocupar todo el
 * ancho debajo de la cabecera.
 */
@Component({
  selector: 'app-campana-notificaciones',
  standalone: true,
  imports: [DatePipe],
  templateUrl: './campana-notificaciones.html',
  styleUrl: './campana-notificaciones.css',
  host: {
    '(document:click)': 'alClickFuera($event)',
    '(document:keydown.escape)': 'cerrar()',
    '[style.--campana-abajo]': 'abajo()',
  },
})
export class CampanaNotificaciones {
  private readonly servicio = inject(NotificacionesService);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly elemento = inject<ElementRef<HTMLElement>>(ElementRef);

  protected readonly noLeidas = this.servicio.noLeidas;
  protected readonly badge = computed(() => (this.noLeidas() > 99 ? '99+' : String(this.noLeidas())));

  protected readonly abierto = signal(false);
  /** Borde inferior de la campana en el viewport: en telefono el panel se fija justo debajo. */
  protected readonly abajo = signal('4.2rem');
  protected readonly items = signal<NotificacionOut[]>([]);
  protected readonly total = signal(0);
  protected readonly cargando = signal(false);
  protected readonly error = signal<string | null>(null);
  private pagina = 1;

  protected readonly hayMas = computed(() => this.items().length < this.total());

  protected alternar(): void {
    if (this.abierto()) {
      this.cerrar();
      return;
    }
    this.abajo.set(`${Math.round(this.elemento.nativeElement.getBoundingClientRect().bottom)}px`);
    this.abierto.set(true);
    this.cargar(1);
  }

  protected cerrar(): void {
    this.abierto.set(false);
  }

  protected alClickFuera(evento: MouseEvent): void {
    if (!this.abierto()) return;
    const objetivo = evento.target as Node | null;
    if (objetivo && !this.elemento.nativeElement.contains(objetivo)) this.cerrar();
  }

  protected cargarMas(): void {
    this.cargar(this.pagina + 1);
  }

  protected marcarTodas(): void {
    this.servicio.leerTodas().subscribe({
      next: () => this.items.update((lista) => lista.map((n) => ({ ...n, leida: true }))),
      error: (e: HttpErrorResponse) => this.error.set(interpretarError(e)),
    });
  }

  protected abrir(notificacion: NotificacionOut): void {
    if (!notificacion.leida) {
      // se marca en la lista al toque; si el POST falla, el proximo refresco lo corrige
      this.items.update((lista) =>
        lista.map((n) => (n.id === notificacion.id ? { ...n, leida: true } : n)),
      );
      this.servicio.marcarLeida(notificacion.id).subscribe({ error: () => undefined });
    }

    const ruta = this.destino(notificacion);
    if (ruta) {
      this.cerrar();
      this.router.navigate(ruta);
    }
  }

  /** Etiqueta corta del tipo, para el renglon de metadatos de cada aviso. */
  protected etiquetaTipo(notificacion: NotificacionOut): string {
    if (notificacion.entidad_tipo === 'ENVIO') return 'Envío';
    switch (notificacion.tipo) {
      case 'RESERVA':
        return 'Reserva';
      case 'VENTA':
        return 'Compra';
      case 'STOCK':
        return 'Stock';
      case 'PROMO':
        return 'Promoción';
    }
  }

  protected tieneDestino(notificacion: NotificacionOut): boolean {
    return this.destino(notificacion) !== null;
  }

  /**
   * A que pantalla lleva cada aviso. Solo se navega a pantallas que el usuario puede abrir:
   * para el resto el aviso se marca leido y el panel queda abierto.
   *  - STOCK (personal): inventario del panel. Va primero porque el aviso de stock bajo
   *    se guarda con entidad_tipo VENTA (la venta que lo disparo).
   *  - RESERVA: la clienta va a sus reservas; el encargado a atender reservas.
   *  - VENTA / ENVIO (clienta): el detalle de la compra (venta_id lo resuelve el backend).
   *  - VENTA (cajero): la caja, donde se cobran/verifican los pagos.
   *  - PROMO: la tienda.
   */
  private destino(n: NotificacionOut): string[] | null {
    const usuario = this.auth.usuario();
    const esStaff = usuario?.tipo === 'STAFF';

    if (n.entidad_tipo === 'TRASPASO') {
      return esStaff && this.auth.tienePermiso('traspasos.leer') ? ['/panel/traspasos'] : null;
    }
    if (n.tipo === 'STOCK') {
      return esStaff && this.auth.tienePermiso('inventario.leer', 'inventario.actualizar')
        ? ['/panel/inventario']
        : null;
    }
    if (n.tipo === 'PROMO') return ['/tienda'];

    if (n.entidad_tipo === 'RESERVA' || n.tipo === 'RESERVA') {
      if (!esStaff) return ['/mis-reservas'];
      return this.auth.tienePermiso(PERMISO_ATENDER_RESERVAS) ? ['/atender-reservas'] : null;
    }

    if (!esStaff) return n.venta_id ? ['/compra', n.venta_id] : ['/mis-compras'];
    if (n.entidad_tipo === 'VENTA' && this.auth.tienePermiso(PERMISO_CAJA)) return ['/caja'];
    return null;
  }

  private cargar(pagina: number): void {
    this.cargando.set(true);
    this.error.set(null);
    this.servicio.listar(pagina, TAMANIO_PAGINA).subscribe({
      next: (respuesta) => {
        this.pagina = respuesta.pagina;
        this.total.set(respuesta.total);
        this.items.update((lista) => (pagina === 1 ? respuesta.items : [...lista, ...respuesta.items]));
        this.cargando.set(false);
      },
      error: (e: HttpErrorResponse) => {
        this.error.set(interpretarError(e, 'No se pudieron cargar las notificaciones.'));
        this.cargando.set(false);
      },
    });
  }
}
