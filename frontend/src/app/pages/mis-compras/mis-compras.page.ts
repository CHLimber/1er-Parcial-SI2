import { DatePipe } from '@angular/common';
import { Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';

import { VentaResumenOut } from '../../core/ventas/ventas.models';
import { VentasService } from '../../core/ventas/ventas.service';

/** CU14 - Consultar Historial de Reservas y Compras (mitad "compras"; la mitad
 * "reservas" es mis-reservas.page.ts). Reusa GET /ventas, que ya devuelve todo el
 * historial del cliente (no solo lo pendiente): CU05/CU06/CU07 alimentan la misma
 * tabla venta sin importar el canal. */
@Component({
  selector: 'app-mis-compras-page',
  standalone: true,
  imports: [RouterLink, DatePipe],
  templateUrl: './mis-compras.page.html',
  styleUrls: ['./mis-compras.page.css', '../../shared/responsive.css'],
})
export class MisComprasPage implements OnInit {
  private readonly ventasService = inject(VentasService);

  protected readonly compras = signal<VentaResumenOut[]>([]);
  protected readonly cargando = signal(true);
  protected readonly error = signal<string | null>(null);

  ngOnInit(): void {
    this.ventasService.listarMisCompras().subscribe({
      next: (compras) => {
        this.compras.set(compras);
        this.cargando.set(false);
      },
      error: () => {
        this.error.set('No se pudieron cargar tus compras por ahora.');
        this.cargando.set(false);
      },
    });
  }

  protected etiquetaEstado(estado: string): string {
    switch (estado) {
      case 'PENDIENTE':
        return 'Pago pendiente';
      case 'PAGADA':
        return 'Pagada';
      case 'ENTREGADA':
        return 'Entregada';
      case 'ANULADA':
        return 'Anulada';
      default:
        return estado;
    }
  }

  protected etiquetaCanal(canal: string): string {
    switch (canal) {
      case 'WEB':
        return 'Web';
      case 'MOVIL':
        return 'App móvil';
      case 'POS':
        return 'En sucursal';
      default:
        return canal;
    }
  }

  protected formatearPrecio(precio: number): string {
    return `Bs ${precio.toFixed(2)}`;
  }
}
