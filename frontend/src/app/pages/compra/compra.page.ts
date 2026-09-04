import { DatePipe } from '@angular/common';
import { Component, OnDestroy, OnInit, inject, signal } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';

import { VentaOut } from '../../core/ventas/ventas.models';
import { VentasService } from '../../core/ventas/ventas.service';

const POLL_MS = 3000;
const POLL_MAX_INTENTOS = 20; // ~1 minuto: tiempo de sobra para que llegue el webhook de Stripe

@Component({
  selector: 'app-compra-page',
  standalone: true,
  imports: [RouterLink, DatePipe],
  templateUrl: './compra.page.html',
  styleUrl: './compra.page.css',
})
export class CompraPage implements OnInit, OnDestroy {
  private readonly route = inject(ActivatedRoute);
  private readonly ventasService = inject(VentasService);

  protected readonly venta = signal<VentaOut | null>(null);
  protected readonly cargando = signal(true);
  protected readonly noEncontrada = signal(false);

  private ventaId = '';
  private intentosPoll = 0;
  private pollHandle?: ReturnType<typeof setTimeout>;

  ngOnInit(): void {
    this.ventaId = this.route.snapshot.paramMap.get('ventaId') ?? '';
    if (!this.ventaId) {
      this.noEncontrada.set(true);
      this.cargando.set(false);
      return;
    }
    this.cargarVenta();
  }

  ngOnDestroy(): void {
    if (this.pollHandle) clearTimeout(this.pollHandle);
  }

  private cargarVenta(): void {
    this.ventasService.obtenerVenta(this.ventaId).subscribe({
      next: (venta) => {
        this.venta.set(venta);
        this.cargando.set(false);
        // Con Stripe la confirmacion llega de forma asincrona por webhook: mientras el pago
        // siga PENDIENTE, reconsultamos unos segundos en vez de dejar la pantalla congelada.
        if (venta.estado === 'PENDIENTE' && this.intentosPoll < POLL_MAX_INTENTOS) {
          this.intentosPoll++;
          this.pollHandle = setTimeout(() => this.cargarVenta(), POLL_MS);
        }
      },
      error: () => {
        this.noEncontrada.set(true);
        this.cargando.set(false);
      },
    });
  }

  protected formatearPrecio(precio: number): string {
    return `Bs ${precio.toFixed(2)}`;
  }
}
