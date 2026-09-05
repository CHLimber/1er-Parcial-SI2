import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';

import { AuthService } from '../../core/auth/auth.service';
import {
  MetodoPagoReserva,
  ReservaItemOut,
  ReservaStaffOut,
  ResolverReservaOut,
} from '../../core/reservas/reservas.models';
import { ReservasService } from '../../core/reservas/reservas.service';

interface PreparacionItem {
  variante_id: string;
  detalle: ReservaItemOut;
  disponible: boolean;
  motivo: string;
}

interface DecisionItem {
  variante_id: string;
  detalle: ReservaItemOut;
  comprado: boolean;
}

const FILTROS = [
  { valor: '', etiqueta: 'Cola activa' },
  { valor: 'CONFIRMADA', etiqueta: 'Confirmadas' },
  { valor: 'PREPARADA', etiqueta: 'Preparadas' },
  { valor: 'CLIENTE_PRESENTE', etiqueta: 'En tienda' },
  { valor: 'CONVERTIDA', etiqueta: 'Convertidas' },
  { valor: 'CANCELADA', etiqueta: 'Canceladas' },
  { valor: 'EXPIRADA', etiqueta: 'Expiradas' },
] as const;

@Component({
  selector: 'app-atender-reservas-page',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './atender-reservas.page.html',
  styleUrl: './atender-reservas.page.css',
})
export class AtenderReservasPage implements OnInit {
  private readonly reservasService = inject(ReservasService);
  private readonly router = inject(Router);
  protected readonly auth = inject(AuthService);

  protected readonly filtros = FILTROS;
  protected filtroActual: string = '';

  protected readonly cargandoCola = signal(true);
  protected readonly reservas = signal<ReservaStaffOut[]>([]);
  protected readonly errorCola = signal<string | null>(null);

  protected readonly seleccionada = signal<ReservaStaffOut | null>(null);
  protected readonly cargandoAccion = signal(false);
  protected readonly errorAccion = signal<string | null>(null);
  protected readonly resultadoResolver = signal<ResolverReservaOut | null>(null);

  protected itemsPreparar: PreparacionItem[] = [];
  protected vestidorAsignado = '';
  protected itemsResolver: DecisionItem[] = [];
  protected readonly metodosPago: MetodoPagoReserva[] = ['EFECTIVO', 'TARJETA', 'QR'];
  protected metodoPago: MetodoPagoReserva = 'EFECTIVO';
  protected montoRecibido: number | null = null;

  ngOnInit(): void {
    this.cargarCola();
  }

  protected cambiarFiltro(valor: string): void {
    this.filtroActual = valor;
    this.cargarCola();
  }

  private cargarCola(): void {
    this.cargandoCola.set(true);
    this.errorCola.set(null);
    this.reservasService.listarReservasSucursal(this.filtroActual || undefined).subscribe({
      next: (reservas) => {
        this.reservas.set(reservas);
        this.cargandoCola.set(false);
      },
      error: () => {
        this.errorCola.set('No se pudo cargar la cola de reservas.');
        this.cargandoCola.set(false);
      },
    });
  }

  protected seleccionar(reserva: ReservaStaffOut): void {
    this.errorAccion.set(null);
    this.resultadoResolver.set(null);
    this.seleccionada.set(reserva);
    this.vestidorAsignado = reserva.vestidor_asignado ?? '';

    this.itemsPreparar = reserva.items
      .filter((item) => item.estado_item === 'RESERVADO')
      .map((item) => ({ variante_id: item.variante_id, detalle: item, disponible: true, motivo: '' }));

    this.itemsResolver = reserva.items
      .filter((item) => item.estado_item === 'PREPARADO')
      .map((item) => ({ variante_id: item.variante_id, detalle: item, comprado: true }));
  }

  private refrescarSeleccionada(reserva: ReservaStaffOut): void {
    this.seleccionada.set(reserva);
    this.reservas.update((lista) => {
      const sigueEnCola = this.filtroActual
        ? this.filtroActual === reserva.estado
        : FILTROS_ACTIVOS.includes(reserva.estado);
      if (!sigueEnCola) return lista.filter((r) => r.id !== reserva.id);
      return lista.map((r) => (r.id === reserva.id ? reserva : r));
    });
  }

  protected confirmarPreparacion(): void {
    const reserva = this.seleccionada();
    if (!reserva) return;

    this.cargandoAccion.set(true);
    this.errorAccion.set(null);
    this.reservasService
      .prepararReserva(reserva.id, {
        items: this.itemsPreparar.map((item) => ({
          variante_id: item.variante_id,
          disponible: item.disponible,
          motivo: item.disponible ? null : item.motivo || null,
        })),
      })
      .subscribe({
        next: (actualizada) => {
          this.cargandoAccion.set(false);
          this.seleccionar(actualizada);
          this.refrescarSeleccionada(actualizada);
        },
        error: (error: HttpErrorResponse) => {
          this.cargandoAccion.set(false);
          this.errorAccion.set(this.interpretarError(error));
        },
      });
  }

  protected confirmarPresencia(): void {
    const reserva = this.seleccionada();
    if (!reserva) return;

    this.cargandoAccion.set(true);
    this.errorAccion.set(null);
    this.reservasService
      .marcarClientePresente(reserva.id, { vestidor_asignado: this.vestidorAsignado || null })
      .subscribe({
        next: (actualizada) => {
          this.cargandoAccion.set(false);
          this.seleccionar(actualizada);
          this.refrescarSeleccionada(actualizada);
        },
        error: (error: HttpErrorResponse) => {
          this.cargandoAccion.set(false);
          this.errorAccion.set(this.interpretarError(error));
        },
      });
  }

  protected get hayCompras(): boolean {
    return this.itemsResolver.some((item) => item.comprado);
  }

  protected confirmarResolucion(): void {
    const reserva = this.seleccionada();
    if (!reserva) return;

    if (this.hayCompras && this.metodoPago === 'EFECTIVO' && this.montoRecibido == null) {
      this.errorAccion.set('Indicá el monto recibido en efectivo.');
      return;
    }

    this.cargandoAccion.set(true);
    this.errorAccion.set(null);
    this.reservasService
      .resolverReserva(reserva.id, {
        decisiones: this.itemsResolver.map((item) => ({
          variante_id: item.variante_id,
          comprado: item.comprado,
        })),
        metodo_pago: this.hayCompras ? this.metodoPago : null,
        monto_recibido: this.hayCompras ? this.montoRecibido : null,
      })
      .subscribe({
        next: (resultado) => {
          this.cargandoAccion.set(false);
          this.refrescarSeleccionada(resultado.reserva);
          this.resultadoResolver.set(resultado);
        },
        error: (error: HttpErrorResponse) => {
          this.cargandoAccion.set(false);
          this.errorAccion.set(this.interpretarError(error));
        },
      });
  }

  protected marcarNoPresentado(): void {
    const reserva = this.seleccionada();
    if (!reserva) return;

    this.cargandoAccion.set(true);
    this.errorAccion.set(null);
    this.reservasService.marcarNoPresentado(reserva.id).subscribe({
      next: (actualizada) => {
        this.cargandoAccion.set(false);
        this.seleccionar(actualizada);
        this.refrescarSeleccionada(actualizada);
      },
      error: (error: HttpErrorResponse) => {
        this.cargandoAccion.set(false);
        this.errorAccion.set(this.interpretarError(error));
      },
    });
  }

  protected elegirMetodoPago(metodo: MetodoPagoReserva): void {
    this.metodoPago = metodo;
    if (metodo !== 'EFECTIVO') this.montoRecibido = null;
  }

  protected cerrarSesion(): void {
    this.auth.cerrarSesion();
    this.router.navigateByUrl('/login');
  }

  protected formatearPrecio(precio: number): string {
    return `Bs ${precio.toFixed(2)}`;
  }

  protected etiquetaEstado(estado: string): string {
    switch (estado) {
      case 'CONFIRMADA':
        return 'Confirmada';
      case 'PREPARADA':
        return 'Prendas preparadas';
      case 'CLIENTE_PRESENTE':
        return 'Cliente en tienda';
      case 'ATENDIDA':
        return 'Atendida';
      case 'CONVERTIDA':
        return 'Convertida en compra';
      case 'CANCELADA':
        return 'Cancelada';
      case 'EXPIRADA':
        return 'Expirada';
      default:
        return estado;
    }
  }

  private interpretarError(error: HttpErrorResponse): string {
    if (error.status === 409 || error.status === 422) {
      const detalle = error.error?.detail;
      if (typeof detalle === 'string') return detalle;
    }
    if (error.status === 401) return 'Tu sesión expiró. Iniciá sesión de nuevo.';
    if (error.status === 0) return 'No se pudo conectar con el servidor. Verificá tu conexión.';
    return 'Ocurrió un error inesperado. Intentá de nuevo.';
  }
}

const FILTROS_ACTIVOS = ['CONFIRMADA', 'PREPARADA', 'CLIENTE_PRESENTE'];
