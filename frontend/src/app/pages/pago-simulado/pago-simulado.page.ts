import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import { VentaOut } from '../../core/ventas/ventas.models';
import { PagosService, VentasService } from '../../core/ventas/ventas.service';
import { interpretarError } from '../../shared/errores';

/**
 * Pago QR (2.19.1.c). Antes la clienta pulsaba "Aprobar" aca y eso disparaba un webhook publico
 * que aprobaba el pago sin que nadie verificara nada. Ahora la pantalla muestra el QR, la clienta
 * escanea y deposita, y solo INFORMA "ya pague" (con una referencia opcional). Quien aprueba o
 * rechaza es el cajero de la sucursal, desde caja, despues de ver el deposito en la cuenta.
 */
@Component({
  selector: 'app-pago-simulado-page',
  standalone: true,
  imports: [RouterLink, FormsModule],
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
  protected readonly enviando = signal(false);
  protected readonly error = signal<string | null>(null);

  protected referencia = '';

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
          // ya se resolvio (lo verifico el cajero, o se reintento el checkout): ir a la confirmacion
          this.router.navigateByUrl(`/compra/${this.ventaId}`);
          return;
        }
        this.venta.set(venta);
        this.referencia = venta.pago.referencia_cliente ?? '';
        this.cargando.set(false);
      },
      error: () => {
        this.noEncontrada.set(true);
        this.cargando.set(false);
      },
    });
  }

  protected informarPago(): void {
    if (this.enviando()) return;
    this.enviando.set(true);
    this.error.set(null);
    const referencia = this.referencia.trim() || null;
    this.pagosService.informarPagoQr(this.ventaId, referencia).subscribe({
      next: () => this.router.navigateByUrl(`/compra/${this.ventaId}`),
      error: (err) => {
        this.error.set(interpretarError(err, 'No pudimos avisar a la sucursal. Intentalo nuevamente.'));
        this.enviando.set(false);
      },
    });
  }

  protected formatearPrecio(precio: number): string {
    return `Bs ${precio.toFixed(2)}`;
  }
}
