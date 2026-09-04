import { Component, OnInit, inject, signal } from '@angular/core';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import { VentaOut } from '../../core/ventas/ventas.models';
import { PagosService, VentasService } from '../../core/ventas/ventas.service';

@Component({
  selector: 'app-pago-simulado-page',
  standalone: true,
  imports: [RouterLink],
  templateUrl: './pago-simulado.page.html',
  styleUrl: './pago-simulado.page.css',
})
export class PagoSimuladoPage implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly ventasService = inject(VentasService);
  private readonly pagosService = inject(PagosService);

  protected readonly venta = signal<VentaOut | null>(null);
  protected readonly cargando = signal(true);
  protected readonly noEncontrada = signal(false);
  protected readonly procesando = signal(false);

  private ventaId = '';

  ngOnInit(): void {
    this.ventaId = this.route.snapshot.paramMap.get('ventaId') ?? '';
    if (!this.ventaId) {
      this.noEncontrada.set(true);
      this.cargando.set(false);
      return;
    }
    this.cargarVenta();
  }

  private cargarVenta(): void {
    this.ventasService.obtenerVenta(this.ventaId).subscribe({
      next: (venta) => {
        this.venta.set(venta);
        this.cargando.set(false);
        if (venta.pago?.estado !== 'PENDIENTE') {
          // ya se resolvio (por ejemplo, se reintento el checkout): saltar directo a la confirmacion
          this.router.navigateByUrl(`/compra/${this.ventaId}`);
        }
      },
      error: () => {
        this.noEncontrada.set(true);
        this.cargando.set(false);
      },
    });
  }

  protected simularPago(resultado: 'APROBADO' | 'RECHAZADO'): void {
    const venta = this.venta();
    if (!venta?.pago?.pasarela || !venta.pago.id_transaccion) return;

    this.procesando.set(true);
    this.pagosService
      .simularWebhook(venta.pago.pasarela, venta.pago.id_transaccion, resultado)
      .subscribe({
        next: () => {
          this.procesando.set(false);
          this.router.navigateByUrl(`/compra/${this.ventaId}`);
        },
        error: () => {
          this.procesando.set(false);
        },
      });
  }

  protected formatearPrecio(precio: number): string {
    return `Bs ${precio.toFixed(2)}`;
  }
}
