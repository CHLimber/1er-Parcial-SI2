import { DatePipe } from '@angular/common';
import { Component, OnDestroy, OnInit, inject, signal } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';

import { EnvioOut, EstadoEnvio } from '../../core/envios/envios.models';
import { EnviosService } from '../../core/envios/envios.service';
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
  private readonly enviosService = inject(EnviosService);

  protected readonly venta = signal<VentaOut | null>(null);
  protected readonly envio = signal<EnvioOut | null>(null);
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
        // CU20: el envio existe recien cuando el pago fue aprobado, asi que se pide despues de
        // la venta y un 404 aca es lo normal mientras el pago sigue pendiente.
        if (venta.entrega === 'DOMICILIO' && venta.estado !== 'PENDIENTE') {
          this.cargarEnvio();
        }
      },
      error: () => {
        this.noEncontrada.set(true);
        this.cargando.set(false);
      },
    });
  }

  private cargarEnvio(): void {
    this.enviosService.envioDeVenta(this.ventaId).subscribe({
      next: (envio) => this.envio.set(envio),
      error: () => this.envio.set(null),
    });
  }

  protected formatearPrecio(precio: number): string {
    return `Bs ${precio.toFixed(2)}`;
  }

  protected etiquetaEnvio(estado: EstadoEnvio): string {
    switch (estado) {
      case 'PENDIENTE':
        return 'Preparando tu pedido';
      case 'DESPACHADO':
        return 'En camino con el servicio de delivery';
      case 'ENTREGADO':
        return 'Entregado';
      case 'FALLIDO':
        return 'No se pudo entregar';
      case 'CANCELADO':
        return 'Envío cancelado';
      default:
        return estado;
    }
  }

  /** Posición del estado dentro de la línea de tiempo, para pintar los pasos cumplidos. */
  protected pasoActual(estado: EstadoEnvio): number {
    const orden: EstadoEnvio[] = ['PENDIENTE', 'DESPACHADO', 'ENTREGADO'];
    const indice = orden.indexOf(estado);
    return indice === -1 ? 0 : indice;
  }

  protected readonly pasos: { estado: EstadoEnvio; etiqueta: string }[] = [
    { estado: 'PENDIENTE', etiqueta: 'Preparando' },
    { estado: 'DESPACHADO', etiqueta: 'En camino' },
    { estado: 'ENTREGADO', etiqueta: 'Entregado' },
  ];
}
