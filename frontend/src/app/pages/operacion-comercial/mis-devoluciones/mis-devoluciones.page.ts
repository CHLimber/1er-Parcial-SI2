import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import {
  COMO_SE_REINTEGRA,
  DevolucionDetalleOut,
  ESTADO_DEVOLUCION_TEXTO,
  LineaClienteOut,
  MotivoDevolucion,
  OpcionesDevolucionOut,
  TipoDevolucion,
  VarianteCambioOut,
  motivosDe,
} from '../../../core/operacion-comercial/devoluciones/devoluciones.models';
import { MisDevolucionesService } from '../../../core/operacion-comercial/devoluciones/devoluciones.service';
import { interpretarError } from '../../../shared/errores';

/**
 * Devoluciones e intercambios de la clienta (PENDIENTES 10). Desde Mis compras pide la devolución
 * o el intercambio de una compra, como una reserva: elige prendas (hasta 3), motivo, la talla/color
 * nueva si es intercambio y el día y la hora en que pasa por la sucursal. La sucursal la acepta y
 * todo se concreta en caja: ahí se revisa la prenda y se devuelve la plata o se paga la diferencia.
 * Con ?venta=<id> abre el formulario de esa compra; sin parámetro muestra las solicitudes.
 */
@Component({
  selector: 'app-mis-devoluciones-page',
  standalone: true,
  imports: [RouterLink, FormsModule],
  templateUrl: './mis-devoluciones.page.html',
  styleUrls: [
    '../mis-compras/mis-compras.page.css',
    './mis-devoluciones.page.css',
    '../../../shared/responsive.css',
  ],
})
export class MisDevolucionesPage implements OnInit {
  private readonly servicio = inject(MisDevolucionesService);
  private readonly ruta = inject(ActivatedRoute);
  private readonly router = inject(Router);

  protected readonly Number = Number;

  // --- listado ---
  protected readonly solicitudes = signal<DevolucionDetalleOut[]>([]);
  protected readonly cargando = signal(true);
  protected readonly error = signal<string | null>(null);
  protected readonly aviso = signal<string | null>(null);
  protected readonly cancelando = signal<string | null>(null);

  // --- formulario ---
  protected readonly opciones = signal<OpcionesDevolucionOut | null>(null);
  protected readonly errorForm = signal<string | null>(null);
  protected readonly enviando = signal(false);
  protected readonly tipo = signal<TipoDevolucion>('DEVOLUCION');
  protected readonly motivoTipo = signal<MotivoDevolucion>('NO_GUSTO');
  protected motivo = '';
  protected fechaVisita = '';
  protected horaVisita = '';
  protected readonly cantidades = signal<Partial<Record<string, number>>>({});
  protected readonly solicitadas = signal<Partial<Record<string, string>>>({});

  protected readonly motivosDelTipo = computed(() => motivosDe(this.tipo()));
  protected readonly unidades = computed(() =>
    Object.values(this.cantidades()).reduce((suma: number, c) => suma + (c ?? 0), 0),
  );

  /** lo que vale lo devuelto (con IVA y descuento): crédito en un intercambio */
  protected readonly valorDevuelto = computed(() => {
    const op = this.opciones();
    if (!op) return 0;
    const cantidades = this.cantidades();
    return op.lineas.reduce((s, l) => s + (cantidades[l.venta_detalle_id] ?? 0) * Number(l.reembolso_unitario), 0);
  });

  /** lo que valen las prendas nuevas elegidas (precio de lista + IVA) */
  protected readonly valorNuevo = computed(() => {
    const op = this.opciones();
    if (!op || this.tipo() !== 'INTERCAMBIO') return 0;
    const cantidades = this.cantidades();
    const solicitadas = this.solicitadas();
    let subtotal = 0;
    for (const linea of op.lineas) {
      const opcion = linea.variantes_cambio.find((v) => v.variante_id === solicitadas[linea.venta_detalle_id]);
      if (opcion) subtotal += (cantidades[linea.venta_detalle_id] ?? 0) * Number(opcion.precio);
    }
    return Math.round(subtotal * (1 + Number(op.iva_tasa)) * 100) / 100;
  });

  protected readonly diferencia = computed(() => this.valorNuevo() - this.valorDevuelto());

  /** fecha mínima y máxima de la visita: hoy y el último día del plazo */
  protected readonly hoy = this.fechaLocal(new Date());
  protected readonly ultimoDia = computed(() => {
    const op = this.opciones();
    return op ? this.fechaLocal(new Date(op.plazo_vence_en)) : this.hoy;
  });

  ngOnInit(): void {
    this.ruta.queryParamMap.subscribe((params) => {
      const venta = params.get('venta');
      if (venta) this.abrirFormulario(venta);
      else this.opciones.set(null);
    });
    this.cargarSolicitudes();
  }

  private cargarSolicitudes(): void {
    this.cargando.set(true);
    this.servicio.listar().subscribe({
      next: (lista) => {
        this.solicitudes.set(lista);
        this.cargando.set(false);
      },
      error: (e: HttpErrorResponse) => {
        this.error.set(interpretarError(e, 'No se pudieron cargar tus devoluciones.'));
        this.cargando.set(false);
      },
    });
  }

  private abrirFormulario(ventaId: string): void {
    this.errorForm.set(null);
    this.aviso.set(null);
    this.cantidades.set({});
    this.solicitadas.set({});
    this.motivo = '';
    this.fechaVisita = this.hoy;
    this.servicio.opciones(ventaId).subscribe({
      next: (op) => {
        this.opciones.set(op);
        this.horaVisita = op.hora_apertura?.slice(0, 5) ?? '10:00';
        this.elegirTipo('DEVOLUCION');
      },
      error: (e: HttpErrorResponse) => this.errorForm.set(interpretarError(e)),
    });
  }

  protected elegirTipo(tipo: TipoDevolucion): void {
    this.tipo.set(tipo);
    this.motivoTipo.set(tipo === 'INTERCAMBIO' ? 'TALLA' : 'NO_GUSTO');
    this.solicitadas.set({});
  }

  protected cambiarMotivo(motivo: MotivoDevolucion): void {
    this.motivoTipo.set(motivo);
    this.solicitadas.set({});
  }

  /** TALLA: mismo color, otra talla. COLOR: misma talla, otro color. */
  protected opcionesPara(linea: LineaClienteOut): VarianteCambioOut[] {
    return this.motivoTipo() === 'TALLA'
      ? linea.variantes_cambio.filter((v) => v.talla !== linea.talla && v.color === linea.color)
      : linea.variantes_cambio.filter((v) => v.color !== linea.color && v.talla === linea.talla);
  }

  protected cambiarCantidad(linea: LineaClienteOut, delta: number): void {
    const op = this.opciones();
    if (!op) return;
    const actual = this.cantidades()[linea.venta_detalle_id] ?? 0;
    const resto = op.max_unidades - this.unidades() + actual;
    const nueva = Math.max(0, Math.min(actual + delta, linea.devolvible, resto));
    this.cantidades.update((c) => ({ ...c, [linea.venta_detalle_id]: nueva }));
  }

  protected elegirVariante(ventaDetalleId: string, varianteId: string): void {
    this.solicitadas.update((s) => ({ ...s, [ventaDetalleId]: varianteId }));
  }

  protected enviar(): void {
    const op = this.opciones();
    if (!op) return;
    const lineas = Object.entries(this.cantidades())
      .filter(([, c]) => (c ?? 0) > 0)
      .map(([venta_detalle_id, cantidad]) => ({
        venta_detalle_id,
        cantidad: cantidad ?? 0,
        variante_solicitada_id: this.tipo() === 'INTERCAMBIO' ? (this.solicitadas()[venta_detalle_id] ?? null) : null,
      }));
    if (lineas.length === 0) {
      this.errorForm.set('Elegí al menos una prenda.');
      return;
    }
    if (this.tipo() === 'INTERCAMBIO' && lineas.some((l) => !l.variante_solicitada_id)) {
      this.errorForm.set('Elegí qué talla o color te llevás por cada prenda.');
      return;
    }
    if (this.motivo.trim().length < 3) {
      this.errorForm.set('Contanos brevemente el motivo.');
      return;
    }
    if (!this.fechaVisita || !this.horaVisita) {
      this.errorForm.set('Elegí cuándo vas a pasar por la sucursal.');
      return;
    }
    this.enviando.set(true);
    this.errorForm.set(null);
    this.servicio
      .solicitar({
        venta_id: op.venta_id,
        motivo_tipo: this.motivoTipo(),
        motivo: this.motivo.trim(),
        fecha_visita: this.fechaVisita,
        hora_visita: this.horaVisita,
        lineas,
      })
      .subscribe({
        next: (solicitud) => {
          this.enviando.set(false);
          this.aviso.set(
            `Enviamos tu solicitud ${solicitud.numero}. Te avisamos cuando la sucursal la acepte; llevá la prenda con su etiqueta y el comprobante.`,
          );
          this.router.navigate([], { queryParams: {} });
          this.cargarSolicitudes();
        },
        error: (e: HttpErrorResponse) => {
          this.enviando.set(false);
          this.errorForm.set(interpretarError(e));
        },
      });
  }

  protected cancelar(solicitud: DevolucionDetalleOut): void {
    this.cancelando.set(solicitud.id);
    this.servicio.cancelar(solicitud.id).subscribe({
      next: () => {
        this.cancelando.set(null);
        this.aviso.set(`Cancelaste la solicitud ${solicitud.numero}.`);
        this.cargarSolicitudes();
      },
      error: (e: HttpErrorResponse) => {
        this.cancelando.set(null);
        this.error.set(interpretarError(e));
      },
    });
  }

  // --- formato ---

  protected enTramite(d: DevolucionDetalleOut): boolean {
    return d.estado === 'SOLICITADA' || d.estado === 'CONFIRMADA';
  }

  protected estadoTexto(d: DevolucionDetalleOut): string {
    if (d.estado === 'SOLICITADA' && d.origen === 'ONLINE') return 'Esperando que la sucursal la acepte';
    if (d.estado === 'CONFIRMADA') return 'Aceptada: te esperamos en la sucursal';
    return ESTADO_DEVOLUCION_TEXTO[d.estado];
  }

  protected comoSeDevuelve(metodo: keyof typeof COMO_SE_REINTEGRA | null): string {
    return metodo ? COMO_SE_REINTEGRA[metodo].replace(', desde la caja', ' en la sucursal') : 'en la sucursal';
  }

  protected precio(valor: number | string | null | undefined): string {
    return valor === null || valor === undefined ? '—' : `Bs ${Number(valor).toFixed(2)}`;
  }

  protected fechaCorta(valor: string): string {
    return new Date(valor).toLocaleDateString('es-BO', { day: '2-digit', month: '2-digit' });
  }

  protected visita(d: DevolucionDetalleOut): string {
    if (!d.fecha_visita) return '';
    const [, mes, dia] = d.fecha_visita.split('-');
    return `${dia}/${mes} a las ${d.hora_visita?.slice(0, 5) ?? ''}`;
  }

  private fechaLocal(fecha: Date): string {
    const mes = String(fecha.getMonth() + 1).padStart(2, '0');
    const dia = String(fecha.getDate()).padStart(2, '0');
    return `${fecha.getFullYear()}-${mes}-${dia}`;
  }
}
