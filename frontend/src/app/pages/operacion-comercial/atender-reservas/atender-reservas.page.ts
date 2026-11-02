import { HttpErrorResponse } from '@angular/common/http';
import { Component, ElementRef, OnDestroy, OnInit, ViewChild, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { Stripe, StripeEmbeddedCheckout, loadStripe } from '@stripe/stripe-js';
import { firstValueFrom } from 'rxjs';

import { AuthService } from '../../../core/acceso-y-organizacion/auth/auth.service';
import {
  CobroStripeOut,
  MetodoCobroVestidor,
  MetodoPagoReserva,
  ReservaItemOut,
  ReservaStaffOut,
  ResolverReservaOut,
} from '../../../core/operacion-comercial/reservas/reservas.models';
import { ReservasService } from '../../../core/operacion-comercial/reservas/reservas.service';
import { PagosService } from '../../../core/operacion-comercial/ventas/ventas.service';
import { PanelShell } from '../../../shared/panel/panel-shell';

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
  { valor: 'PENDIENTE', etiqueta: 'Por confirmar' },
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
  imports: [FormsModule, PanelShell],
  templateUrl: './atender-reservas.page.html',
  styleUrls: ['./atender-reservas.page.css', '../../../shared/responsive.css'],
})
export class AtenderReservasPage implements OnInit, OnDestroy {
  private readonly reservasService = inject(ReservasService);
  private readonly pagosService = inject(PagosService);
  private readonly router = inject(Router);
  protected readonly auth = inject(AuthService);

  protected readonly filtros = FILTROS;
  protected filtroActual: string = '';

  protected readonly cargandoCola = signal(true);
  protected readonly reservas = signal<ReservaStaffOut[]>([]);

  protected readonly busqueda = signal('');
  protected readonly orden = signal<'RECIENTES' | 'ANTIGUAS' | 'VISITA'>('RECIENTES');

  /** La cola ya filtrada por la busqueda (codigo, clienta, correo, telefono) y ordenada. */
  protected readonly reservasVisibles = computed<ReservaStaffOut[]>(() => {
    const q = this.busqueda().trim().toLowerCase();
    const lista = q
      ? this.reservas().filter((r) =>
          [r.codigo, r.cliente.nombre, r.cliente.apellido, r.cliente.email, r.cliente.telefono ?? '']
            .join(' ')
            .toLowerCase()
            .includes(q),
        )
      : [...this.reservas()];
    const creada = (r: ReservaStaffOut) => new Date(r.creada_en).getTime();
    const visita = (r: ReservaStaffOut) => new Date(`${r.fecha_visita}T${r.hora_visita}`).getTime();
    switch (this.orden()) {
      case 'ANTIGUAS':
        return lista.sort((a, b) => creada(a) - creada(b));
      case 'VISITA':
        return lista.sort((a, b) => visita(a) - visita(b));
      default:
        return lista.sort((a, b) => creada(b) - creada(a));
    }
  });
  protected readonly errorCola = signal<string | null>(null);

  protected readonly seleccionada = signal<ReservaStaffOut | null>(null);
  protected readonly cargandoAccion = signal(false);
  protected readonly errorAccion = signal<string | null>(null);
  protected readonly resultadoResolver = signal<ResolverReservaOut | null>(null);

  protected itemsPreparar: PreparacionItem[] = [];
  protected motivoRechazo = '';
  protected vestidorAsignado = '';
  protected itemsResolver: DecisionItem[] = [];
  protected readonly metodosPago: { valor: MetodoCobroVestidor; etiqueta: string }[] = [
    { valor: 'EFECTIVO', etiqueta: 'Efectivo' },
    { valor: 'TARJETA', etiqueta: 'Tarjeta (POS)' },
    { valor: 'QR', etiqueta: 'QR' },
    { valor: 'STRIPE', etiqueta: 'Stripe' },
  ];
  protected metodoPago: MetodoCobroVestidor = 'EFECTIVO';
  protected montoRecibido: number | null = null;

  // Cobro con Stripe en el vestidor (PENDIENTES 11): el formulario de tarjeta de Stripe se monta
  // aca mismo y la venta se cierra sola cuando Stripe confirma (webhook o verificacion del backend).
  @ViewChild('stripeContenedor') private stripeContenedorRef?: ElementRef<HTMLDivElement>;
  private stripePromise: Promise<Stripe | null> | null = null;
  private stripeCheckout: StripeEmbeddedCheckout | null = null;
  protected readonly cobroStripe = signal<CobroStripeOut | null>(null);
  protected readonly montandoStripe = signal(false);
  protected readonly verificandoStripe = signal(false);

  ngOnInit(): void {
    this.cargarCola();
    this.stripePromise = firstValueFrom(this.pagosService.obtenerConfig())
      .then((config) => (config.stripe_publishable_key ? loadStripe(config.stripe_publishable_key) : null))
      .catch(() => null);
  }

  ngOnDestroy(): void {
    this.desmontarStripe();
  }

  /** Total con IVA de lo que la clienta compra (precio de lista + 13%), para QR y Stripe. */
  protected get totalCompra(): number {
    const subtotal = this.itemsResolver
      .filter((item) => item.comprado)
      .reduce((suma, item) => suma + (item.detalle.precio ?? 0) * item.detalle.cantidad, 0);
    return Math.round(subtotal * 1.13 * 100) / 100;
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
    this.motivoRechazo = '';

    this.itemsPreparar = reserva.items
      .filter((item) => item.estado_item === 'RESERVADO')
      .map((item) => ({ variante_id: item.variante_id, detalle: item, disponible: true, motivo: '' }));

    this.itemsResolver = reserva.items
      .filter((item) => item.estado_item === 'PREPARADO')
      .map((item) => ({ variante_id: item.variante_id, detalle: item, comprado: true }));

    this.desmontarStripe();
    this.cobroStripe.set(null);
    if (reserva.estado === 'CLIENTE_PRESENTE') this.retomarCobroStripe(reserva.id);
  }

  /** Si quedo un cobro con tarjeta a medias (se recargo la pagina), lo vuelve a mostrar. */
  private retomarCobroStripe(reservaId: string): void {
    this.reservasService.estadoCobroStripe(reservaId).subscribe({
      next: (cobro) => {
        if (this.seleccionada()?.id !== reservaId) return;
        if (cobro.estado === 'PENDIENTE' && cobro.client_secret && cobro.canal === 'WEB') {
          this.metodoPago = 'STRIPE';
          this.cobroStripe.set(cobro);
          setTimeout(() => this.montarStripe(cobro.client_secret!));
        }
      },
    });
  }

  /** Arma la venta pendiente y monta el formulario de Stripe para que la clienta pague ahi. */
  protected cobrarConStripe(): void {
    const reserva = this.seleccionada();
    if (!reserva) return;
    this.cargandoAccion.set(true);
    this.errorAccion.set(null);
    this.reservasService
      .iniciarCobroStripe(
        reserva.id,
        this.itemsResolver.map((item) => ({ variante_id: item.variante_id, comprado: item.comprado })),
      )
      .subscribe({
        next: (cobro) => {
          this.cargandoAccion.set(false);
          this.cobroStripe.set(cobro);
          if (cobro.client_secret) setTimeout(() => this.montarStripe(cobro.client_secret!));
        },
        error: (error: HttpErrorResponse) => {
          this.cargandoAccion.set(false);
          this.errorAccion.set(this.interpretarError(error));
        },
      });
  }

  private async montarStripe(clientSecret: string): Promise<void> {
    this.desmontarStripe();
    this.montandoStripe.set(true);
    const stripe = await this.stripePromise;
    const contenedor = this.stripeContenedorRef?.nativeElement;
    if (!stripe || !contenedor) {
      this.montandoStripe.set(false);
      this.errorAccion.set('No se pudo cargar el formulario de Stripe (revisá STRIPE_PUBLISHABLE_KEY).');
      return;
    }
    try {
      const checkout = await stripe.createEmbeddedCheckoutPage({
        clientSecret,
        onComplete: () => this.verificarCobroStripe(true),
      });
      this.stripeCheckout = checkout;
      checkout.mount(contenedor);
    } catch {
      this.errorAccion.set('No se pudo iniciar el pago con Stripe. Intentá de nuevo.');
    } finally {
      this.montandoStripe.set(false);
    }
  }

  private desmontarStripe(): void {
    this.stripeCheckout?.destroy();
    this.stripeCheckout = null;
  }

  /** Consulta el cobro; con `insistir` reintenta unos segundos mientras Stripe lo confirma. */
  protected verificarCobroStripe(insistir = false, intento = 0): void {
    const reserva = this.seleccionada();
    if (!reserva) return;
    this.verificandoStripe.set(true);
    this.reservasService.estadoCobroStripe(reserva.id).subscribe({
      next: (cobro) => {
        if (cobro.estado === 'PAGADA' || cobro.estado === 'ENTREGADA') {
          this.verificandoStripe.set(false);
          this.desmontarStripe();
          this.cobroStripe.set(null);
          const convertida = { ...reserva, estado: 'CONVERTIDA' };
          this.refrescarSeleccionada(convertida);
          this.resultadoResolver.set({
            reserva: convertida,
            venta_id: cobro.venta_id,
            venta_numero: cobro.venta_numero,
            comprobante_numero: cobro.comprobante_numero,
            total_cobrado: cobro.total,
          });
          return;
        }
        if (cobro.estado === 'PENDIENTE' && insistir && intento < 10) {
          setTimeout(() => this.verificarCobroStripe(true, intento + 1), 2000);
          return;
        }
        this.verificandoStripe.set(false);
        if (cobro.estado === 'ANULADA') {
          this.desmontarStripe();
          this.cobroStripe.set(null);
          this.errorAccion.set('Stripe no aprobó el pago. Elegí otra forma de pago o volvé a intentar.');
        } else if (cobro.estado === 'PENDIENTE') {
          this.errorAccion.set('Stripe todavía no confirmó el pago. Esperá unos segundos y actualizá.');
        }
      },
      error: (error: HttpErrorResponse) => {
        this.verificandoStripe.set(false);
        this.errorAccion.set(this.interpretarError(error));
      },
    });
  }

  /** La clienta prefiere otra forma de pago: se cierra el intento en Stripe. */
  protected cancelarCobroStripe(): void {
    const reserva = this.seleccionada();
    if (!reserva) return;
    this.cargandoAccion.set(true);
    this.reservasService.cancelarCobroStripe(reserva.id).subscribe({
      next: () => {
        this.cargandoAccion.set(false);
        this.desmontarStripe();
        this.cobroStripe.set(null);
      },
      error: (error: HttpErrorResponse) => {
        this.cargandoAccion.set(false);
        this.errorAccion.set(this.interpretarError(error));
      },
    });
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

  /** 2.19.1.a: la sucursal acepta la reserva (PENDIENTE -> CONFIRMADA). */
  protected confirmarReserva(): void {
    const reserva = this.seleccionada();
    if (!reserva) return;

    this.cargandoAccion.set(true);
    this.errorAccion.set(null);
    this.reservasService.confirmarReserva(reserva.id).subscribe({
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

  /** 2.19.1.a: la sucursal rechaza la reserva; el backend libera el stock y avisa al cliente. */
  protected rechazarReserva(): void {
    const reserva = this.seleccionada();
    if (!reserva) return;

    const motivo = this.motivoRechazo.trim();
    if (motivo.length < 3) {
      this.errorAccion.set('Indicá el motivo del rechazo (se le envía al cliente).');
      return;
    }
    if (!confirm(`¿Rechazar la reserva ${reserva.codigo}? Se libera el stock y se avisa al cliente.`)) {
      return;
    }

    this.cargandoAccion.set(true);
    this.errorAccion.set(null);
    this.reservasService.rechazarReserva(reserva.id, { motivo }).subscribe({
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
        metodo_pago: this.hayCompras ? (this.metodoPago as MetodoPagoReserva) : null,
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

  protected elegirMetodoPago(metodo: MetodoCobroVestidor): void {
    // salir de Stripe con un cobro abierto lo cierra, si no /resolver responde "pago en curso"
    if (this.metodoPago === 'STRIPE' && metodo !== 'STRIPE' && this.cobroStripe()) {
      this.cancelarCobroStripe();
    }
    this.metodoPago = metodo;
    if (metodo !== 'EFECTIVO') this.montoRecibido = null;
  }

  protected cerrarSesion(): void {
    this.auth.cerrarSesion();
    this.router.navigateByUrl('/login');
  }

  /** "02/11/2026 14:30" a partir del instante en que la clienta creo la reserva. */
  protected fechaCreada(iso: string): string {
    const d = new Date(iso);
    return Number.isNaN(d.getTime())
      ? '—'
      : d.toLocaleString('es-BO', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
  }

  protected formatearPrecio(precio: number): string {
    return `Bs ${precio.toFixed(2)}`;
  }

  protected etiquetaEstado(estado: string): string {
    switch (estado) {
      case 'PENDIENTE':
        return 'Por confirmar';
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

const FILTROS_ACTIVOS = ['PENDIENTE', 'CONFIRMADA', 'PREPARADA', 'CLIENTE_PRESENTE'];
