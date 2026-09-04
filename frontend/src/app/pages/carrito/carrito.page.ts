import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { CarritoService } from '../../core/carrito/carrito.service';
import { CarritoItemOut, CarritoOut } from '../../core/carrito/carrito.models';
import { Pasarela } from '../../core/ventas/ventas.models';
import { VentasService } from '../../core/ventas/ventas.service';
import { SucursalOut } from '../../core/sucursales/sucursales.models';
import { SucursalesService } from '../../core/sucursales/sucursales.service';

@Component({
  selector: 'app-carrito-page',
  standalone: true,
  imports: [FormsModule, RouterLink],
  templateUrl: './carrito.page.html',
  styleUrl: './carrito.page.css',
})
export class CarritoPage implements OnInit {
  private readonly carritoService = inject(CarritoService);
  private readonly ventasService = inject(VentasService);
  private readonly sucursalesService = inject(SucursalesService);
  private readonly router = inject(Router);

  protected readonly carrito = signal<CarritoOut | null>(null);
  protected readonly cargando = signal(true);
  protected readonly sucursales = signal<SucursalOut[]>([]);

  protected readonly enviando = signal(false);
  protected readonly errorMensaje = signal<string | null>(null);

  protected sucursalId = '';
  protected pasarela: Pasarela = 'STRIPE';
  protected codigoCupon = '';

  ngOnInit(): void {
    this.cargarCarrito();
    this.sucursalesService.listarSucursales().subscribe({
      next: (sucursales) => {
        this.sucursales.set(sucursales);
        if (sucursales.length > 0 && !this.sucursalId) {
          this.sucursalId = sucursales[0].id;
        }
      },
    });
  }

  private cargarCarrito(): void {
    this.cargando.set(true);
    this.carritoService.verCarrito().subscribe({
      next: (carrito) => {
        this.carrito.set(carrito);
        this.cargando.set(false);
      },
      error: () => {
        this.cargando.set(false);
        this.errorMensaje.set('No se pudo cargar tu carrito por ahora.');
      },
    });
  }

  protected cambiarCantidad(item: CarritoItemOut, valor: number): void {
    const cantidad = Math.min(20, Math.max(1, Math.round(valor)));
    this.carritoService.actualizarCantidad(item.id, cantidad).subscribe({
      next: (carrito) => this.carrito.set(carrito),
    });
  }

  protected quitarItem(item: CarritoItemOut): void {
    this.carritoService.quitarItem(item.id).subscribe({
      next: (carrito) => this.carrito.set(carrito),
    });
  }

  protected elegirPasarela(pasarela: Pasarela): void {
    this.pasarela = pasarela;
  }

  protected pagar(): void {
    this.errorMensaje.set(null);
    const carrito = this.carrito();
    if (!carrito || carrito.items.length === 0) {
      this.errorMensaje.set('Tu carrito esta vacio.');
      return;
    }
    if (!carrito.reserva_id && !this.sucursalId) {
      this.errorMensaje.set('Elegi la sucursal desde la que se despacha tu pedido.');
      return;
    }

    this.enviando.set(true);
    this.ventasService
      .checkout({
        sucursal_id: carrito.reserva_id ? null : this.sucursalId,
        entrega: 'RETIRO_SUCURSAL',
        pasarela: this.pasarela,
        codigo_cupon: this.codigoCupon.trim() || null,
        canal: 'WEB',
      })
      .subscribe({
        next: (checkout) => {
          this.enviando.set(false);
          if (checkout.url_pago.startsWith('http')) {
            // Stripe: pagina de pago alojada por la pasarela, fuera del router de Angular
            window.location.href = checkout.url_pago;
          } else {
            this.router.navigateByUrl(checkout.url_pago);
          }
        },
        error: (error: HttpErrorResponse) => {
          this.enviando.set(false);
          this.errorMensaje.set(this.interpretarError(error));
        },
      });
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
      return 'Revisa la sucursal y el cupon ingresado.';
    }
    if (error.status === 404) return 'No encontramos algo necesario para tu compra.';
    if (error.status === 401) return 'Tu sesion expiro. Inicia sesion de nuevo.';
    if (error.status === 0) return 'No se pudo conectar con el servidor. Verifica tu conexion.';
    return 'Ocurrio un error inesperado. Intenta de nuevo.';
  }
}
