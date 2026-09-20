import { HttpErrorResponse } from '@angular/common/http';
import {
  Component,
  ElementRef,
  OnDestroy,
  OnInit,
  ViewChild,
  inject,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { Stripe, StripeEmbeddedCheckout, loadStripe } from '@stripe/stripe-js';
import { firstValueFrom } from 'rxjs';

import { CarritoService } from '../../core/carrito/carrito.service';
import { CarritoItemOut, CarritoOut } from '../../core/carrito/carrito.models';
import { DireccionOut } from '../../core/direcciones/direcciones.models';
import { DireccionesService } from '../../core/direcciones/direcciones.service';
import { CotizacionOut } from '../../core/envios/envios.models';
import { EnviosService } from '../../core/envios/envios.service';
import { CheckoutIn, MetodoPagoCheckout, ModoEntrega } from '../../core/ventas/ventas.models';
import { PagosService, VentasService } from '../../core/ventas/ventas.service';
import { SucursalOut } from '../../core/sucursales/sucursales.models';
import { SucursalesService } from '../../core/sucursales/sucursales.service';

@Component({
  selector: 'app-carrito-page',
  standalone: true,
  imports: [FormsModule, RouterLink],
  templateUrl: './carrito.page.html',
  styleUrls: ['./carrito.page.css', '../../shared/responsive.css'],
})
export class CarritoPage implements OnInit, OnDestroy {
  private readonly carritoService = inject(CarritoService);
  private readonly ventasService = inject(VentasService);
  private readonly pagosService = inject(PagosService);
  private readonly sucursalesService = inject(SucursalesService);
  private readonly direccionesService = inject(DireccionesService);
  private readonly enviosService = inject(EnviosService);
  private readonly router = inject(Router);

  @ViewChild('stripeContenedor') private stripeContenedorRef?: ElementRef<HTMLDivElement>;

  protected readonly carrito = signal<CarritoOut | null>(null);
  protected readonly cargando = signal(true);
  protected readonly sucursales = signal<SucursalOut[]>([]);

  protected readonly enviando = signal(false);
  protected readonly errorMensaje = signal<string | null>(null);

  // CU20
  protected readonly direcciones = signal<DireccionOut[]>([]);
  protected readonly cotizacion = signal<CotizacionOut | null>(null);
  protected readonly cotizando = signal(false);
  protected readonly errorEnvio = signal<string | null>(null);

  protected sucursalId = '';
  protected metodoPago: MetodoPagoCheckout = 'STRIPE';
  protected codigoCupon = '';
  protected entrega: ModoEntrega = 'RETIRO_SUCURSAL';
  protected direccionId = '';

  // Stripe embebido: el script de Stripe.js se precarga apenas se conoce la publishable key
  // (ngOnInit), no recien cuando se elige la pasarela -- asi Stripe() ya esta listo para cuando
  // se arma el Checkout Session (al entrar al carrito con Stripe seleccionado por defecto, o al
  // tocar el boton "Stripe"). stripePromise queda cacheada durante toda la vida del componente:
  // cambiar de pasarela y volver a Stripe no la vuelve a pedir.
  private stripePromise: Promise<Stripe | null> | null = null;
  private stripeCheckout: StripeEmbeddedCheckout | null = null;
  protected readonly mostrandoStripe = signal(false);
  protected readonly montandoStripe = signal(false);

  // Cada cambio que afecta el total (cantidad, quitar item, entrega, sucursal...) dispara un
  // iniciarStripe() nuevo que crea OTRA venta+Checkout Session en el backend y monta OTRO iframe.
  // Si dos de esas llamadas quedan en vuelo a la vez (p.ej. se sube la cantidad mientras el Stripe
  // inicial todavia se esta montando), no hay garantia de que la que resuelve al final sea la mas
  // reciente -- puede ganar la vieja y quedar mostrando un monto desactualizado aunque el resto de
  // la pantalla ya se haya refrescado. Este contador identifica la solicitud vigente; cualquier
  // resultado que llegue despues de haber sido superado se descarta.
  private stripeSolicitudId = 0;

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
    this.direccionesService.listar().subscribe({
      next: (direcciones) => {
        this.direcciones.set(direcciones);
        const principal = direcciones.find((direccion) => direccion.es_principal);
        this.direccionId = principal?.id ?? direcciones[0]?.id ?? '';
      },
    });
    this.precargarStripe();
  }

  ngOnDestroy(): void {
    this.stripeCheckout?.destroy();
  }

  private precargarStripe(): void {
    if (this.stripePromise) return;
    this.stripePromise = firstValueFrom(this.pagosService.obtenerConfig())
      .then((config) => (config.stripe_publishable_key ? loadStripe(config.stripe_publishable_key) : null))
      .catch(() => null);
  }

  private cargarCarrito(): void {
    this.cargando.set(true);
    this.carritoService.verCarrito().subscribe({
      next: (carrito) => {
        this.carrito.set(carrito);
        this.cargando.set(false);
        this.cotizarEnvio();
        // Stripe es la pasarela por defecto: apenas se conoce el carrito, se carga su formulario
        // para que ya este listo cuando la clienta mire hacia abajo, sin tener que tocar nada.
        if (this.metodoPago === 'STRIPE' && carrito.items.length > 0) {
          this.iniciarStripe();
        }
      },
      error: () => {
        this.cargando.set(false);
        this.errorMensaje.set('No se pudo cargar tu carrito por ahora.');
      },
    });
  }

  /**
   * CU20: pide la tarifa cada vez que cambia algo que la afecta (modo de entrega, dirección,
   * sucursal que despacha o el monto del carrito, del que depende el envío gratis). Es solo
   * informativo: el backend vuelve a cotizar en el checkout antes de cobrar.
   */
  protected cotizarEnvio(): void {
    this.errorEnvio.set(null);
    const carrito = this.carrito();

    if (this.entrega !== 'DOMICILIO' || !carrito || !this.sucursalId || !this.direccionId) {
      this.cotizacion.set(null);
      return;
    }

    this.cotizando.set(true);
    this.enviosService
      .cotizar({
        sucursal_id: this.sucursalId,
        direccion_id: this.direccionId,
        monto_pedido: carrito.subtotal,
      })
      .subscribe({
        next: (cotizacion) => {
          this.cotizacion.set(cotizacion);
          this.cotizando.set(false);
          if (!cotizacion.dentro_cobertura) {
            this.errorEnvio.set(
              `Tu dirección queda a ${cotizacion.distancia_km.toFixed(1)} km y esta sucursal ` +
                `reparte hasta ${cotizacion.radio_km} km. Probá con otra sucursal o retirá en tienda.`,
            );
          }
        },
        error: (error: HttpErrorResponse) => {
          this.cotizando.set(false);
          this.cotizacion.set(null);
          this.errorEnvio.set(this.interpretarError(error));
        },
      });
  }

  protected elegirEntrega(entrega: ModoEntrega): void {
    this.entrega = entrega;
    this.cotizarEnvio();
    this.refrescarStripeSiCorresponde();
  }

  /** Cambiar de sucursal o de direccion cambia el total (por el costo de envio) -- si Stripe ya
   * estaba montado con el monto viejo, hay que volver a armarlo para que cobre el correcto. */
  protected actualizarCotizacionYPago(): void {
    this.cotizarEnvio();
    this.refrescarStripeSiCorresponde();
  }

  private refrescarStripeSiCorresponde(): void {
    if (this.metodoPago === 'STRIPE' && (this.mostrandoStripe() || this.montandoStripe())) {
      this.cerrarStripeEmbebido();
      this.iniciarStripe();
    }
  }

  /** IVA 13% fijo (ver CLAUDE.md): no es parametrizable, asi que se puede reflejar en el
   * frontend sin pedirselo al backend. Solo para mostrar -- lo que se cobra siempre lo calcula
   * el backend en /ventas/checkout, con esta misma formula. */
  private static readonly IVA_TASA = 0.13;

  private redondear(monto: number): number {
    return Math.round(monto * 100) / 100;
  }

  /** Tarifa del delivery, tal cual la cotizo fn_cotizar_envio(): el flete no lleva IVA, se suma
   * aparte del 13% de las prendas (ver /ventas/checkout en el backend). 0 si se retira en tienda
   * o si el envio salio gratis. */
  protected costoEnvio(): number {
    return this.cotizacion()?.costo ?? 0;
  }

  /** Lo que se cobra de verdad: 13% de IVA solo sobre las prendas, mas el envio sin impuesto. */
  protected totalConIva(subtotal: number): number {
    return this.redondear(subtotal * (1 + CarritoPage.IVA_TASA) + this.costoEnvio());
  }

  protected prendasConIva(subtotal: number): number {
    return this.redondear(subtotal * (1 + CarritoPage.IVA_TASA));
  }

  protected cambiarCantidad(item: CarritoItemOut, valor: number): void {
    const cantidad = Math.min(20, Math.max(1, Math.round(valor)));
    this.carritoService.actualizarCantidad(item.id, cantidad).subscribe({
      next: (carrito) => {
        this.carrito.set(carrito);
        this.cotizarEnvio();
        this.refrescarStripeSiCorresponde();
      },
    });
  }

  protected quitarItem(item: CarritoItemOut): void {
    this.carritoService.quitarItem(item.id).subscribe({
      next: (carrito) => {
        this.carrito.set(carrito);
        this.cotizarEnvio();
        this.refrescarStripeSiCorresponde();
      },
    });
  }

  protected elegirMetodoPago(metodo: MetodoPagoCheckout): void {
    if (this.metodoPago === metodo) return;
    this.metodoPago = metodo;
    this.errorMensaje.set(null);
    this.cerrarStripeEmbebido();
    if (metodo === 'STRIPE') {
      this.iniciarStripe();
    }
  }

  /** Junta y valida los datos del checkout. Devuelve null (con errorMensaje seteado) si falta algo. */
  private construirCheckoutIn(metodo: MetodoPagoCheckout): CheckoutIn | null {
    const carrito = this.carrito();
    if (!carrito || carrito.items.length === 0) {
      this.errorMensaje.set('Tu carrito esta vacio.');
      return null;
    }
    if (!carrito.reserva_id && !this.sucursalId) {
      this.errorMensaje.set('Elegi la sucursal desde la que se despacha tu pedido.');
      return null;
    }

    // una compra nacida de una reserva se retira si o si donde se comprometio el stock
    const entrega: ModoEntrega = carrito.reserva_id ? 'RETIRO_SUCURSAL' : this.entrega;
    if (entrega === 'DOMICILIO' && !this.direccionId) {
      this.errorMensaje.set('Elegi la direccion a la que llevamos tu pedido.');
      return null;
    }

    return {
      sucursal_id: carrito.reserva_id ? null : this.sucursalId,
      entrega,
      direccion_id: entrega === 'DOMICILIO' ? this.direccionId : null,
      metodo_pago: metodo,
      codigo_cupon: this.codigoCupon.trim() || null,
      canal: 'WEB',
    };
  }

  /** Boton "Pagar" de QR y Efectivo -- Stripe no lo usa, tiene su propio boton adentro del iframe. */
  protected pagar(): void {
    this.errorMensaje.set(null);
    const body = this.construirCheckoutIn(this.metodoPago);
    if (!body) return;

    this.enviando.set(true);
    this.ventasService.checkout(body).subscribe({
      next: (checkout) => {
        this.enviando.set(false);
        if (checkout.url_pago?.startsWith('http')) {
          window.location.href = checkout.url_pago;
        } else if (checkout.url_pago) {
          // QR (pasarela simulada) o EFECTIVO (ya quedo pagada): navegacion interna de siempre
          this.router.navigateByUrl(checkout.url_pago);
        }
      },
      error: (error: HttpErrorResponse) => {
        this.enviando.set(false);
        this.errorMensaje.set(this.interpretarError(error));
      },
    });
  }

  /** Se dispara solo al elegir "Stripe" (o al entrar al carrito, que ya viene elegido por
   * defecto): arma el checkout y monta el formulario inline, sin esperar un click en "Pagar". */
  private iniciarStripe(): void {
    const body = this.construirCheckoutIn('STRIPE');
    if (!body) return;

    // Se marca esta llamada como la vigente ANTES de esperar al backend: si mientras tanto llega
    // otro cambio (nueva cantidad, otra sucursal...) que llama a iniciarStripe() de nuevo, ese
    // segundo llamado pisa el contador y esta respuesta, cuando llegue, se reconoce como vieja.
    const solicitudId = ++this.stripeSolicitudId;
    this.montandoStripe.set(true);
    this.ventasService.checkout(body).subscribe({
      next: async (checkout) => {
        if (solicitudId !== this.stripeSolicitudId) return; // superada por una solicitud mas nueva
        if (checkout.client_secret) {
          await this.montarStripeEmbebido(checkout.client_secret, checkout.venta_id, solicitudId);
        } else {
          // no deberia pasar en canal WEB, pero por las dudas no se deja colgado el spinner
          this.montandoStripe.set(false);
          this.errorMensaje.set('No se pudo iniciar el pago con Stripe. Intenta de nuevo.');
        }
      },
      error: (error: HttpErrorResponse) => {
        if (solicitudId !== this.stripeSolicitudId) return;
        this.montandoStripe.set(false);
        this.errorMensaje.set(this.interpretarError(error));
      },
    });
  }

  private async montarStripeEmbebido(
    clientSecret: string,
    ventaId: string,
    solicitudId: number,
  ): Promise<void> {
    const stripe = await this.stripePromise;
    if (solicitudId !== this.stripeSolicitudId) return; // superada mientras se cargaba Stripe.js
    const contenedor = this.stripeContenedorRef?.nativeElement;
    if (!stripe || !contenedor) {
      this.montandoStripe.set(false);
      this.errorMensaje.set('No se pudo cargar el formulario de Stripe. Intenta de nuevo.');
      return;
    }

    try {
      const checkout = await stripe.createEmbeddedCheckoutPage({
        clientSecret,
        onComplete: () => this.router.navigateByUrl(`/compra/${ventaId}`),
      });
      if (solicitudId !== this.stripeSolicitudId) {
        // otra solicitud ya se volvio la vigente mientras Stripe armaba este Checkout Session:
        // se descarta sin montar para no pisar el iframe correcto (o dejar dos superpuestos)
        checkout.destroy();
        return;
      }
      this.stripeCheckout = checkout;
      checkout.mount(contenedor);
      this.mostrandoStripe.set(true);
    } catch {
      if (solicitudId === this.stripeSolicitudId) {
        this.errorMensaje.set('No se pudo iniciar el pago con Stripe. Intenta de nuevo.');
      }
    } finally {
      if (solicitudId === this.stripeSolicitudId) {
        this.montandoStripe.set(false);
      }
    }
  }

  private cerrarStripeEmbebido(): void {
    this.stripeSolicitudId++; // invalida cualquier solicitud de Stripe que haya quedado en vuelo
    this.stripeCheckout?.destroy();
    this.stripeCheckout = null;
    this.mostrandoStripe.set(false);
    this.montandoStripe.set(false);
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
