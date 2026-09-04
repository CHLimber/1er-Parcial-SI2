import { DatePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { ItemCarritoReserva, ReservaCarritoService } from '../../core/reservas/reserva-carrito.service';
import { ReservaOut } from '../../core/reservas/reservas.models';
import { ReservasService } from '../../core/reservas/reservas.service';
import { SucursalOut } from '../../core/sucursales/sucursales.models';
import { SucursalesService } from '../../core/sucursales/sucursales.service';

@Component({
  selector: 'app-reservar-page',
  standalone: true,
  imports: [FormsModule, RouterLink, DatePipe],
  templateUrl: './reservar.page.html',
  styleUrl: './reservar.page.css',
})
export class ReservarPage implements OnInit {
  private readonly reservaCarrito = inject(ReservaCarritoService);
  private readonly reservasService = inject(ReservasService);
  private readonly sucursalesService = inject(SucursalesService);
  private readonly router = inject(Router);

  protected readonly items = this.reservaCarrito.items;
  protected readonly cantidadTotal = this.reservaCarrito.cantidadTotal;

  protected readonly sucursales = signal<SucursalOut[]>([]);
  protected readonly cargandoSucursales = signal(true);

  protected readonly enviando = signal(false);
  protected readonly errorMensaje = signal<string | null>(null);
  protected readonly resultado = signal<ReservaOut | null>(null);

  protected readonly fechaMinima = new Date().toISOString().slice(0, 10);

  protected sucursalId = '';
  protected fecha = this.fechaMinima;
  protected hora = '15:00';
  protected observaciones = '';

  protected readonly sucursalSeleccionada = computed(() =>
    this.sucursales().find((s) => s.id === this.sucursalId) ?? null,
  );

  ngOnInit(): void {
    this.sucursalesService.listarSucursales().subscribe({
      next: (sucursales) => {
        this.sucursales.set(sucursales);
        if (sucursales.length > 0 && !this.sucursalId) {
          this.sucursalId = sucursales[0].id;
        }
        this.cargandoSucursales.set(false);
      },
      error: () => this.cargandoSucursales.set(false),
    });
  }

  protected quitarItem(item: ItemCarritoReserva): void {
    this.reservaCarrito.quitar(item.varianteId);
  }

  protected cambiarCantidad(item: ItemCarritoReserva, valor: number): void {
    const cantidad = Math.min(20, Math.max(1, Math.round(valor)));
    this.reservaCarrito.actualizarCantidad(item.varianteId, cantidad);
  }

  protected formatearHorario(sucursal: SucursalOut): string {
    if (!sucursal.hora_apertura || !sucursal.hora_cierre) return '';
    return `Atiende de ${sucursal.hora_apertura.slice(0, 5)} a ${sucursal.hora_cierre.slice(0, 5)}`;
  }

  protected confirmar(): void {
    this.errorMensaje.set(null);

    if (this.items().length === 0) {
      this.errorMensaje.set('Agregá al menos una prenda desde el catálogo antes de reservar.');
      return;
    }
    if (!this.sucursalId) {
      this.errorMensaje.set('Elegí una sucursal para probarte las prendas.');
      return;
    }

    this.enviando.set(true);
    this.reservasService
      .crearReserva({
        sucursal_id: this.sucursalId,
        fecha_visita: this.fecha,
        hora_visita: `${this.hora}:00`,
        observaciones: this.observaciones.trim() || null,
        items: this.items().map((item) => ({ variante_id: item.varianteId, cantidad: item.cantidad })),
      })
      .subscribe({
        next: (reserva) => {
          this.enviando.set(false);
          this.resultado.set(reserva);
          this.reservaCarrito.limpiar();
        },
        error: (error: HttpErrorResponse) => {
          this.enviando.set(false);
          this.errorMensaje.set(this.interpretarError(error));
        },
      });
  }

  protected volverAlCatalogo(): void {
    this.router.navigateByUrl('/tienda');
  }

  protected verMisReservas(): void {
    this.router.navigateByUrl('/mis-reservas');
  }

  protected formatearPrecio(precio: number): string {
    return `Bs ${precio.toFixed(2)}`;
  }

  private interpretarError(error: HttpErrorResponse): string {
    if (error.status === 409 && error.error?.detail?.mensaje) {
      return error.error.detail.mensaje;
    }
    if (error.status === 422) {
      const detalle = error.error?.detail;
      if (typeof detalle === 'string') return detalle;
      return 'Revisá la fecha, el horario y las prendas seleccionadas.';
    }
    if (error.status === 404) return 'Esa sucursal ya no está disponible.';
    if (error.status === 401) return 'Tu sesión expiró. Iniciá sesión de nuevo.';
    if (error.status === 0) return 'No se pudo conectar con el servidor. Verificá tu conexión.';
    return 'Ocurrió un error inesperado. Intentá de nuevo.';
  }
}
