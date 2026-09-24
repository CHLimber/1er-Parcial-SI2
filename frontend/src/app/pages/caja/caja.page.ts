import { DatePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';

import { AuthService } from '../../core/auth/auth.service';
import {
  ArqueoOut,
  CajaOut,
  PagoPorVerificarOut,
  SesionCajaOut,
  SesionCerradaOut,
  VarianteBusquedaOut,
} from '../../core/caja/caja.models';
import { CajaService } from '../../core/caja/caja.service';
import { MetodoPagoPos, VentaPosOut } from '../../core/ventas/ventas.models';
import { VentasService } from '../../core/ventas/ventas.service';
import { CampanaNotificaciones } from '../../shared/notificaciones/campana-notificaciones';
import { interpretarError } from '../../shared/errores';

const IVA_TASA = 0.13;

interface TicketItem extends VarianteBusquedaOut {
  cantidad: number;
}

@Component({
  selector: 'app-caja-page',
  standalone: true,
  imports: [FormsModule, DatePipe, CampanaNotificaciones],
  templateUrl: './caja.page.html',
  styleUrls: ['./caja.page.css', '../../shared/responsive.css'],
})
export class CajaPage implements OnInit {
  private readonly cajaService = inject(CajaService);
  private readonly ventasService = inject(VentasService);
  private readonly router = inject(Router);
  protected readonly auth = inject(AuthService);

  protected readonly cargando = signal(true);
  protected readonly sesion = signal<SesionCajaOut | null>(null);

  protected readonly cajas = signal<CajaOut[]>([]);
  protected cajaSeleccionada = '';
  protected montoInicial = 0;
  protected readonly abriendo = signal(false);
  protected readonly errorApertura = signal<string | null>(null);

  protected readonly ticket = signal<TicketItem[]>([]);
  protected codigoBusqueda = '';
  protected readonly buscando = signal(false);
  protected readonly errorBusqueda = signal<string | null>(null);

  protected readonly metodosDisponibles: MetodoPagoPos[] = ['EFECTIVO', 'TARJETA', 'QR'];
  protected metodoPago: MetodoPagoPos = 'EFECTIVO';
  protected montoRecibido: number | null = null;
  protected readonly cobrando = signal(false);
  protected readonly errorCobro = signal<string | null>(null);
  protected readonly comprobante = signal<VentaPosOut | null>(null);

  protected readonly cerrandoCaja = signal(false);
  protected readonly arqueo = signal<ArqueoOut | null>(null);
  protected readonly cargandoArqueo = signal(false);
  protected montoDeclarado: number | null = null;
  protected readonly cerrandoSesion = signal(false);
  protected readonly errorCierre = signal<string | null>(null);
  protected readonly cierreResultado = signal<SesionCerradaOut | null>(null);

  protected readonly subtotal = computed(() =>
    this.ticket().reduce((acc, item) => acc + item.precio * item.cantidad, 0),
  );
  protected readonly iva = computed(() => this.subtotal() * IVA_TASA);
  protected readonly total = computed(() => this.subtotal() + this.iva());
  protected readonly vuelto = computed(() =>
    this.montoRecibido != null ? this.montoRecibido - this.total() : null,
  );

  // 2.19.1.b/c: pedidos online en EFECTIVO o QR que esperan que el cajero los apruebe
  protected readonly pagosPendientes = signal<PagoPorVerificarOut[]>([]);
  protected readonly cargandoPagos = signal(false);
  protected readonly pagoEnProceso = signal<string | null>(null);
  protected readonly rechazandoId = signal<string | null>(null);
  protected motivoRechazo = '';
  protected readonly mensajePagos = signal<{ texto: string; error: boolean } | null>(null);

  protected readonly diferenciaPreview = computed(() => {
    const arqueo = this.arqueo();
    if (arqueo === null || this.montoDeclarado == null) return null;
    return this.montoDeclarado - arqueo.monto_sistema;
  });

  ngOnInit(): void {
    this.cargarSesion();
    this.cargarPagosPendientes();
  }

  protected cargarPagosPendientes(): void {
    this.cargandoPagos.set(true);
    this.cajaService.listarPagosPendientes().subscribe({
      next: (pagos) => {
        this.pagosPendientes.set(pagos);
        this.cargandoPagos.set(false);
      },
      error: (error: HttpErrorResponse) => {
        this.cargandoPagos.set(false);
        this.mensajePagos.set({ texto: interpretarError(error), error: true });
      },
    });
  }

  protected aprobarPago(pago: PagoPorVerificarOut): void {
    if (this.pagoEnProceso()) return;
    this.pagoEnProceso.set(pago.pago_id);
    this.mensajePagos.set(null);
    this.cajaService.aprobarPago(pago.pago_id).subscribe({
      next: (resultado) => {
        this.pagoEnProceso.set(null);
        const aprobado = resultado.pago_estado === 'APROBADO';
        this.mensajePagos.set({
          texto: aprobado
            ? `Pedido ${resultado.numero} aprobado: se descontó el stock y se emitió el comprobante.`
            : `Pedido ${resultado.numero} anulado (${resultado.pago_estado}): ${resultado.mensaje}`,
          error: !aprobado,
        });
        this.cargarPagosPendientes();
      },
      error: (error: HttpErrorResponse) => {
        this.pagoEnProceso.set(null);
        this.mensajePagos.set({ texto: interpretarError(error), error: true });
        this.cargarPagosPendientes();
      },
    });
  }

  protected iniciarRechazo(pago: PagoPorVerificarOut): void {
    this.rechazandoId.set(pago.pago_id);
    this.motivoRechazo = '';
  }

  protected cancelarRechazo(): void {
    this.rechazandoId.set(null);
  }

  protected confirmarRechazo(pago: PagoPorVerificarOut): void {
    if (this.pagoEnProceso()) return;
    this.pagoEnProceso.set(pago.pago_id);
    this.mensajePagos.set(null);
    this.cajaService.rechazarPago(pago.pago_id, this.motivoRechazo.trim() || null).subscribe({
      next: (resultado) => {
        this.pagoEnProceso.set(null);
        this.rechazandoId.set(null);
        this.mensajePagos.set({ texto: `Pedido ${resultado.numero} rechazado y anulado.`, error: false });
        this.cargarPagosPendientes();
      },
      error: (error: HttpErrorResponse) => {
        this.pagoEnProceso.set(null);
        this.mensajePagos.set({ texto: interpretarError(error), error: true });
        this.cargarPagosPendientes();
      },
    });
  }

  private cargarSesion(): void {
    this.cargando.set(true);
    this.cajaService.obtenerSesionActual().subscribe({
      next: (sesion) => {
        this.sesion.set(sesion);
        this.cargando.set(false);
        if (!sesion) this.cargarCajas();
      },
      error: () => this.cargando.set(false),
    });
  }

  private cargarCajas(): void {
    this.cajaService.listarCajas().subscribe({
      next: (cajas) => {
        this.cajas.set(cajas);
        const libre = cajas.find((c) => !c.tiene_sesion_abierta);
        this.cajaSeleccionada = libre?.id ?? cajas[0]?.id ?? '';
      },
    });
  }

  protected abrirCaja(): void {
    if (!this.cajaSeleccionada) {
      this.errorApertura.set('Elegí una caja para abrir.');
      return;
    }
    this.abriendo.set(true);
    this.errorApertura.set(null);
    this.cajaService
      .abrirSesion({ caja_id: this.cajaSeleccionada, monto_inicial: this.montoInicial || 0 })
      .subscribe({
        next: (sesion) => {
          this.abriendo.set(false);
          this.sesion.set(sesion);
        },
        error: (error: HttpErrorResponse) => {
          this.abriendo.set(false);
          this.errorApertura.set(
            error.status === 409
              ? 'Esa caja ya tiene una sesión abierta por otro cajero.'
              : 'No se pudo abrir la caja. Intentá de nuevo.',
          );
        },
      });
  }

  protected agregarProducto(): void {
    const codigo = this.codigoBusqueda.trim();
    if (!codigo) return;

    this.buscando.set(true);
    this.errorBusqueda.set(null);
    this.cajaService.buscarVariante(codigo).subscribe({
      next: (variante) => {
        this.buscando.set(false);
        this.codigoBusqueda = '';
        this.agregarAlTicket(variante);
      },
      error: (error: HttpErrorResponse) => {
        this.buscando.set(false);
        this.errorBusqueda.set(
          error.status === 404 ? 'No se encontró esa prenda.' : 'No se pudo buscar esa prenda.',
        );
      },
    });
  }

  private agregarAlTicket(variante: VarianteBusquedaOut): void {
    this.ticket.update((items) => {
      const existente = items.find((item) => item.variante_id === variante.variante_id);
      if (existente) {
        const cantidad = Math.min(existente.cantidad + 1, Math.max(variante.disponible, 1));
        return items.map((item) => (item === existente ? { ...item, cantidad } : item));
      }
      return [...items, { ...variante, cantidad: variante.disponible > 0 ? 1 : 0 }];
    });
  }

  protected cambiarCantidad(item: TicketItem, valor: number): void {
    const cantidad = Math.min(Math.max(item.disponible, 1), Math.max(1, Math.round(valor)));
    this.ticket.update((items) =>
      items.map((actual) => (actual === item ? { ...actual, cantidad } : actual)),
    );
  }

  protected quitarItem(item: TicketItem): void {
    this.ticket.update((items) => items.filter((actual) => actual !== item));
  }

  protected elegirMetodoPago(metodo: MetodoPagoPos): void {
    this.metodoPago = metodo;
    if (metodo !== 'EFECTIVO') this.montoRecibido = null;
  }

  protected cobrar(): void {
    this.errorCobro.set(null);
    const items = this.ticket();
    if (items.length === 0) {
      this.errorCobro.set('Agregá al menos una prenda para cobrar.');
      return;
    }
    if (this.metodoPago === 'EFECTIVO' && (this.montoRecibido == null || this.montoRecibido < this.total())) {
      this.errorCobro.set('El monto recibido no puede ser menor al total.');
      return;
    }

    this.cobrando.set(true);
    this.ventasService
      .registrarVentaPos({
        items: items.map((item) => ({ variante_id: item.variante_id, cantidad: item.cantidad })),
        metodo_pago: this.metodoPago,
        monto_recibido: this.metodoPago === 'EFECTIVO' ? this.montoRecibido : null,
      })
      .subscribe({
        next: (resultado) => {
          this.cobrando.set(false);
          this.comprobante.set(resultado);
          this.ticket.set([]);
          this.montoRecibido = null;
        },
        error: (error: HttpErrorResponse) => {
          this.cobrando.set(false);
          this.errorCobro.set(this.interpretarErrorCobro(error));
          // E1: si la sesion ya no esta abierta (se cerro desde otro lado), volvemos a consultarla
          if (error.status === 409 && typeof error.error?.detail === 'string') {
            this.cargarSesion();
          }
        },
      });
  }

  protected nuevaVenta(): void {
    this.comprobante.set(null);
  }

  protected cerrarSesion(): void {
    this.auth.cerrarSesion();
    this.router.navigateByUrl('/login');
  }

  protected abrirCierreCaja(): void {
    this.cerrandoCaja.set(true);
    this.errorCierre.set(null);
    this.cierreResultado.set(null);
    this.montoDeclarado = null;
    this.cargandoArqueo.set(true);
    this.cajaService.obtenerArqueo().subscribe({
      next: (arqueo) => {
        this.arqueo.set(arqueo);
        this.cargandoArqueo.set(false);
      },
      error: (error: HttpErrorResponse) => {
        this.cargandoArqueo.set(false);
        this.errorCierre.set(
          error.status === 409
            ? 'No tenés una sesión de caja abierta.'
            : 'No se pudo cargar el arqueo. Intentá de nuevo.',
        );
      },
    });
  }

  protected cancelarCierreCaja(): void {
    this.cerrandoCaja.set(false);
    this.arqueo.set(null);
  }

  protected confirmarCierreCaja(): void {
    if (this.montoDeclarado == null || this.montoDeclarado < 0) {
      this.errorCierre.set('Ingresá el monto que contaste en caja.');
      return;
    }

    this.cerrandoSesion.set(true);
    this.errorCierre.set(null);
    this.cajaService.cerrarSesion({ monto_declarado: this.montoDeclarado }).subscribe({
      next: (resultado) => {
        this.cerrandoSesion.set(false);
        this.cierreResultado.set(resultado);
      },
      error: (error: HttpErrorResponse) => {
        this.cerrandoSesion.set(false);
        this.errorCierre.set(
          error.status === 409
            ? 'La sesión ya estaba cerrada.'
            : 'No se pudo cerrar la caja. Intentá de nuevo.',
        );
      },
    });
  }

  protected aceptarCierreCaja(): void {
    this.cerrandoCaja.set(false);
    this.arqueo.set(null);
    this.cierreResultado.set(null);
    this.sesion.set(null);
    this.cargarCajas();
  }

  protected metodosArqueo(arqueo: ArqueoOut): { metodo: string; total: number }[] {
    return Object.entries(arqueo.por_metodo).map(([metodo, total]) => ({ metodo, total }));
  }

  protected formatearPrecio(precio: number): string {
    return `Bs ${precio.toFixed(2)}`;
  }

  private interpretarErrorCobro(error: HttpErrorResponse): string {
    if (error.status === 409) {
      const detalle = error.error?.detail;
      if (typeof detalle === 'string') return detalle;
      if (detalle?.mensaje) return detalle.mensaje;
    }
    if (error.status === 401) return 'Tu sesión expiró. Iniciá sesión de nuevo.';
    if (error.status === 0) return 'No se pudo conectar con el servidor. Verificá tu conexión.';
    return 'Ocurrió un error inesperado al cobrar. Intentá de nuevo.';
  }
}
