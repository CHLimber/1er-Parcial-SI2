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

  protected readonly ventaStripe = signal<VentaOut | null>(null);
  protected readonly cargando = signal(true);
  protected readonly noEncontrada = signal(false);
  protected readonly errorConfirmando = signal(false);

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
        if (venta.pago?.estado !== 'PENDIENTE') {
          // ya se resolvio (por ejemplo, se reintento el checkout): saltar directo a la confirmacion
          this.router.navigateByUrl(`/compra/${this.ventaId}`);
          return;
        }
        if (venta.pago?.pasarela === 'STRIPE') {
          this.ventaStripe.set(venta);
          this.cargando.set(false);
          return;
        }
        this.confirmarPago(venta);
      },
      error: () => {
        this.noEncontrada.set(true);
        this.cargando.set(false);
      },
    });
  }

  private confirmarPago(venta: VentaOut): void {
    if (!venta.pago?.pasarela || !venta.pago.id_transaccion) {
      this.errorConfirmando.set(true);
      this.cargando.set(false);
      return;
    }
    this.pagosService
      .simularWebhook(venta.pago.pasarela, venta.pago.id_transaccion, 'APROBADO')
      .subscribe({
        next: () => this.router.navigateByUrl(`/compra/${this.ventaId}`),
        error: () => {
          this.errorConfirmando.set(true);
          this.cargando.set(false);
        },
      });
  }

  protected formatearPrecio(precio: number): string {
    return `Bs ${precio.toFixed(2)}`;
  }
}
