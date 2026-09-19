import { DatePipe } from '@angular/common';
import { Component, OnDestroy, OnInit, inject, signal } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';

import { EnvioEventoOut, EnvioOut, EstadoEnvio } from '../../core/envios/envios.models';
import { EnviosService } from '../../core/envios/envios.service';
import { VentaOut } from '../../core/ventas/ventas.models';
import { VentasService } from '../../core/ventas/ventas.service';

const POLL_MS = 3000;
const POLL_MAX_INTENTOS = 20; // ~1 minuto: tiempo de sobra para que llegue el webhook de Stripe

// CU20: el reparto lo hace un servicio de delivery externo, no hay un repartidor real en la
// demo marcando DESPACHADO/ENTREGADO. Simulamos ese avance en el navegador (sin tocar el
// backend) para poder mostrar la pantalla completa sin importar la pasarela usada.
// Momentos (desde que se ve el envio, en ms) en los que pasa a DESPACHADO y a ENTREGADO.
const SIMULACION_MS: [number, number] = [2000, 4500];
const ORDEN_ENVIO: EstadoEnvio[] = ['PENDIENTE', 'DESPACHADO', 'ENTREGADO'];

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

  private readonly pasoSimulado = signal(0);
  private readonly eventosSimulados = signal<EnvioEventoOut[]>([]);

  private ventaId = '';
  private intentosPoll = 0;
  private pollHandle?: ReturnType<typeof setTimeout>;
  private simulacionIniciada = false;
  private readonly simulacionHandles: ReturnType<typeof setTimeout>[] = [];

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
    this.simulacionHandles.forEach((handle) => clearTimeout(handle));
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
      next: (envio) => {
        this.envio.set(envio);
        this.iniciarSimulacionSiCorresponde(envio);
      },
      error: () => this.envio.set(null),
    });
  }

  /**
   * El envio existe apenas se aprueba el pago (estado PENDIENTE) y el kardex real lo mueve un
   * repartidor externo desde el panel de admin -- algo que la demo no tiene. Para poder ver la
   * pantalla completa sin importar la pasarela (Stripe o Libelula/efectivo), simulamos el avance
   * PENDIENTE -> DESPACHADO -> ENTREGADO en el navegador, sin pegarle al backend.
   */
  private iniciarSimulacionSiCorresponde(envio: EnvioOut): void {
    if (this.simulacionIniciada || envio.estado !== 'PENDIENTE') return;
    this.simulacionIniciada = true;

    const avanzar = (paso: number, estado: EstadoEnvio, nota: string, ms: number) => {
      const handle = setTimeout(() => {
        this.pasoSimulado.set(paso);
        this.eventosSimulados.update((eventos) => [
          ...eventos,
          { estado, nota, fecha: new Date().toISOString() },
        ]);
      }, ms);
      this.simulacionHandles.push(handle);
    };

    avanzar(1, 'DESPACHADO', 'Retirado por el servicio de delivery (simulado)', SIMULACION_MS[0]);
    avanzar(2, 'ENTREGADO', 'Entrega confirmada por el servicio de delivery (simulado)', SIMULACION_MS[1]);
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
    const indice = ORDEN_ENVIO.indexOf(estado);
    return indice === -1 ? 0 : indice;
  }

  /** Estado real, salvo que la simulación ya lo haya adelantado (ver iniciarSimulacionSiCorresponde). */
  protected estadoMostrado(): EstadoEnvio {
    const e = this.envio();
    if (!e) return 'PENDIENTE';
    const paso = this.pasoSimulado();
    return paso > this.pasoActual(e.estado) ? ORDEN_ENVIO[paso] : e.estado;
  }

  /** Bitácora real del envío más los pasos que fue agregando la simulación. */
  protected eventosMostrados(): EnvioEventoOut[] {
    return [...(this.envio()?.eventos ?? []), ...this.eventosSimulados()];
  }

  protected readonly pasos: { estado: EstadoEnvio; etiqueta: string }[] = [
    { estado: 'PENDIENTE', etiqueta: 'Preparando' },
    { estado: 'DESPACHADO', etiqueta: 'En camino' },
    { estado: 'ENTREGADO', etiqueta: 'Entregado' },
  ];
}
