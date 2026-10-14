import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { AuthService } from '../../core/auth/auth.service';
import {
  CambiosMesOut,
  DevolucionDetalleOut,
  DevolucionOut,
  EstadoDevolucion,
  MOTIVOS_DEVOLUCION,
  MetodoReintegro,
  MotivoDevolucion,
  NotaDevolucionOut,
  VarianteCambioOut,
  VentaDevolvibleOut,
} from '../../core/devoluciones/devoluciones.models';
import { DevolucionesService } from '../../core/devoluciones/devoluciones.service';
import { interpretarError } from '../../shared/errores';
import { PanelShell } from '../../shared/panel/panel-shell';

/**
 * Devoluciones de ventas (PENDIENTES 2.7). Dos pasos, los dos del personal: registrar la
 * devolucion sobre una venta pagada (nace SOLICITADA, no mueve stock) y resolverla: aprobar
 * reingresa el stock (trigger en la base) y calcula lo que se reintegra; rechazar pide motivo.
 * PENDIENTES 4.11: plazo desde la venta (configuracion.devolucion_plazo_dias), reintegro segun
 * como se pago (Stripe por la API, efectivo desde la caja abierta, el resto manual) y cambio de
 * prenda = devolucion aprobada + venta nueva en caja vinculada aca.
 * Segundo parcial (PENDIENTES 5.8-5.10): motivo estructurado (TALLA/COLOR son cambios, con su
 * propio plazo y la variante que se lleva la clienta), condiciones de la prenda, nota de
 * devolucion imprimible y la consulta "que prendas solicitaron cambio en el mes".
 */
@Component({
  selector: 'app-panel-devoluciones-page',
  standalone: true,
  imports: [PanelShell, FormsModule],
  templateUrl: './panel-devoluciones.page.html',
  // lista/tarjeta/ficha/carga son las mismas piezas que la pantalla de recepciones
  styleUrls: [
    '../../shared/panel/panel-comun.css',
    '../panel-recepciones/panel-recepciones.page.css',
    './panel-devoluciones.page.css',
  ],
})
export class PanelDevolucionesPage implements OnInit {
  private readonly servicio = inject(DevolucionesService);
  private readonly auth = inject(AuthService);

  protected readonly puedeRegistrar = this.auth.tienePermiso('devoluciones.crear');
  protected readonly puedeResolver = this.auth.tienePermiso('devoluciones.actualizar');
  /** los montos Decimal llegan como string: el template los compara con Number() */
  protected readonly Number = Number;

  protected readonly cargando = signal(true);
  protected readonly devoluciones = signal<DevolucionOut[]>([]);
  protected readonly error = signal<string | null>(null);
  protected filtroEstado: '' | EstadoDevolucion = '';
  protected filtroVenta = '';
  protected filtroMotivo: '' | MotivoDevolucion = '';
  protected filtroDesde = '';
  protected filtroHasta = '';
  protected readonly motivos = MOTIVOS_DEVOLUCION;

  /** 'lista' = devoluciones; 'cambios' = consulta de cambios del mes */
  protected readonly vista = signal<'lista' | 'cambios'>('lista');
  protected mesConsulta = new Date().toISOString().slice(0, 7); // YYYY-MM
  protected incluirOtrosMotivos = false;
  protected readonly cambiosMes = signal<CambiosMesOut | null>(null);
  protected readonly cargandoCambios = signal(false);
  protected readonly errorCambios = signal<string | null>(null);

  protected readonly seleccionada = signal<DevolucionDetalleOut | null>(null);
  protected readonly errorDetalle = signal<string | null>(null);
  protected readonly aviso = signal<string | null>(null);
  protected readonly ocupado = signal(false);
  protected motivoRechazo = '';
  protected readonly rechazando = signal(false);
  protected numeroVentaCambio = '';

  // --- alta ---
  protected readonly creando = signal(false);
  protected numeroVenta = '';
  protected readonly venta = signal<VentaDevolvibleOut | null>(null);
  protected readonly buscandoVenta = signal(false);
  protected readonly errorNueva = signal<string | null>(null);
  /** cantidad a devolver por venta_detalle_id */
  protected readonly cantidades = signal<Partial<Record<string, number>>>({});
  protected motivo = '';
  protected readonly motivoTipo = signal<MotivoDevolucion>('TALLA');
  protected conEtiqueta = true;
  protected sinUso = true;
  protected conComprobante = true;
  /** variante elegida a cambio, por venta_detalle_id (solo TALLA/COLOR) */
  protected readonly solicitadas = signal<Partial<Record<string, string>>>({});
  /** opciones de cambio por variante vendida: otras tallas/colores de la misma prenda */
  protected readonly opcionesCambio = signal<Partial<Record<string, VarianteCambioOut[]>>>({});

  protected readonly esCambio = computed(() => ['TALLA', 'COLOR'].includes(this.motivoTipo()));

  protected readonly estimado = computed(() => {
    const venta = this.venta();
    if (!venta) return 0;
    const cantidades = this.cantidades();
    return venta.lineas.reduce(
      (suma, linea) => suma + (cantidades[linea.venta_detalle_id] ?? 0) * Number(linea.reembolso_unitario),
      0,
    );
  });

  protected readonly unidadesElegidas = computed(() =>
    Object.values(this.cantidades()).reduce((suma: number, cantidad) => suma + (cantidad ?? 0), 0),
  );

  ngOnInit(): void {
    this.cargar();
  }

  protected cargar(): void {
    this.cargando.set(true);
    this.error.set(null);
    this.servicio
      .listar({
        estado: this.filtroEstado || null,
        venta: this.filtroVenta.trim() || null,
        motivo_tipo: this.filtroMotivo || null,
        desde: this.filtroDesde || null,
        hasta: this.filtroHasta || null,
      })
      .subscribe({
        next: (devoluciones) => {
          this.devoluciones.set(devoluciones);
          this.cargando.set(false);
        },
        error: (e: HttpErrorResponse) => {
          this.error.set(interpretarError(e, 'No se pudieron cargar las devoluciones.'));
          this.cargando.set(false);
        },
      });
  }

  // ------------------------------------------------------------ cambios del mes

  protected verCambios(): void {
    this.vista.set('cambios');
    this.cargarCambios();
  }

  protected cargarCambios(): void {
    const [anio, mes] = this.mesConsulta.split('-').map(Number);
    if (!anio || !mes) return;
    this.cargandoCambios.set(true);
    this.errorCambios.set(null);
    this.servicio.cambiosDelMes(anio, mes, this.incluirOtrosMotivos).subscribe({
      next: (datos) => {
        this.cambiosMes.set(datos);
        this.cargandoCambios.set(false);
      },
      error: (e: HttpErrorResponse) => {
        this.errorCambios.set(interpretarError(e));
        this.cargandoCambios.set(false);
      },
    });
  }

  // ------------------------------------------------------------ alta

  protected abrirNueva(): void {
    this.creando.set(true);
    this.seleccionada.set(null);
    this.venta.set(null);
    this.numeroVenta = '';
    this.motivo = '';
    this.motivoTipo.set('TALLA');
    this.conEtiqueta = this.sinUso = this.conComprobante = true;
    this.cantidades.set({});
    this.solicitadas.set({});
    this.opcionesCambio.set({});
    this.errorNueva.set(null);
  }

  protected cambiarMotivo(motivo: MotivoDevolucion): void {
    this.motivoTipo.set(motivo);
    this.solicitadas.set({});
    if (this.esCambio()) this.cargarOpcionesCambio();
  }

  /** Para cada prenda de la venta, las otras tallas/colores con su stock en la sucursal. */
  private cargarOpcionesCambio(): void {
    const venta = this.venta();
    if (!venta) return;
    for (const linea of venta.lineas) {
      if (this.opcionesCambio()[linea.variante_id]) continue;
      this.servicio.variantesCambio(linea.variante_id, venta.sucursal_id).subscribe({
        next: (opciones) =>
          this.opcionesCambio.update((actual) => ({ ...actual, [linea.variante_id]: opciones })),
      });
    }
  }

  /** Opciones validas segun el motivo: TALLA = mismo color, otra talla; COLOR = misma talla, otro color. */
  protected opcionesPara(varianteId: string, talla: string, color: string): VarianteCambioOut[] {
    const todas = this.opcionesCambio()[varianteId] ?? [];
    return this.motivoTipo() === 'TALLA'
      ? todas.filter((o) => o.talla !== talla && o.color === color)
      : todas.filter((o) => o.color !== color && o.talla === talla);
  }

  protected elegirCambio(ventaDetalleId: string, varianteId: string): void {
    this.solicitadas.update((actual) => ({ ...actual, [ventaDetalleId]: varianteId }));
  }

  protected buscarVenta(): void {
    const numero = this.numeroVenta.trim();
    if (!numero) return;
    this.buscandoVenta.set(true);
    this.errorNueva.set(null);
    this.venta.set(null);
    this.cantidades.set({});
    this.servicio.buscarVenta(numero).subscribe({
      next: (venta) => {
        this.venta.set(venta);
        this.buscandoVenta.set(false);
        if (this.esCambio()) this.cargarOpcionesCambio();
      },
      error: (e: HttpErrorResponse) => {
        this.buscandoVenta.set(false);
        this.errorNueva.set(interpretarError(e));
      },
    });
  }

  protected fijarCantidad(ventaDetalleId: string, valor: number, maximo: number): void {
    const cantidad = Math.max(0, Math.min(Math.floor(Number(valor) || 0), maximo));
    this.cantidades.update((actual) => ({ ...actual, [ventaDetalleId]: cantidad }));
  }

  protected registrar(): void {
    const venta = this.venta();
    if (!venta) return;
    const solicitadas = this.solicitadas();
    const lineas = Object.entries(this.cantidades())
      .map(([venta_detalle_id, cantidad]) => ({
        venta_detalle_id,
        cantidad: cantidad ?? 0,
        variante_solicitada_id: this.esCambio() ? (solicitadas[venta_detalle_id] ?? null) : null,
      }))
      .filter((linea) => linea.cantidad > 0);
    if (lineas.length === 0) {
      this.errorNueva.set('Indicá al menos una prenda a devolver.');
      return;
    }
    if (this.esCambio() && lineas.some((linea) => !linea.variante_solicitada_id)) {
      this.errorNueva.set('Elegí qué talla o color se lleva la clienta por cada prenda.');
      return;
    }
    if (this.motivo.trim().length < 3) {
      this.errorNueva.set('Escribí el motivo de la devolución.');
      return;
    }

    this.ocupado.set(true);
    this.errorNueva.set(null);
    const datos = {
      venta_id: venta.venta_id,
      motivo_tipo: this.motivoTipo(),
      motivo: this.motivo.trim(),
      con_etiqueta: this.conEtiqueta,
      sin_uso: this.sinUso,
      con_comprobante: this.conComprobante,
      lineas,
    };
    this.servicio.registrar(datos).subscribe({
      next: (devolucion) => {
        this.ocupado.set(false);
        this.creando.set(false);
        this.seleccionada.set(devolucion);
        this.aviso.set(
          `Nota ${devolucion.numero} registrada. Queda pendiente de aprobación: todavía no volvió al stock.`,
        );
        this.cargar();
      },
      error: (e: HttpErrorResponse) => {
        this.ocupado.set(false);
        this.errorNueva.set(interpretarError(e));
      },
    });
  }

  // ------------------------------------------------------------ detalle

  protected abrir(devolucion: DevolucionOut): void {
    this.creando.set(false);
    this.errorDetalle.set(null);
    this.aviso.set(null);
    this.rechazando.set(false);
    this.servicio.obtener(devolucion.id).subscribe({
      next: (detalle) => this.seleccionada.set(detalle),
      error: (e: HttpErrorResponse) => this.errorDetalle.set(interpretarError(e)),
    });
  }

  protected aprobar(): void {
    const devolucion = this.seleccionada();
    if (!devolucion) return;
    this.ocupado.set(true);
    this.errorDetalle.set(null);
    this.servicio.aprobar(devolucion.id).subscribe({
      next: (detalle) => {
        this.ocupado.set(false);
        this.seleccionada.set(detalle);
        this.aviso.set(
          `Devolución aprobada: ${detalle.unidades} unidad(es) volvieron al stock de ${detalle.sucursal}. ` +
            this.instruccionReintegro(detalle.reintegro_metodo, detalle.monto_devuelto) +
            (detalle.pago_reembolsado ? ' La venta quedó devuelta completa y el pago pasó a reembolsado.' : ''),
        );
        this.cargar();
      },
      error: (e: HttpErrorResponse) => {
        this.ocupado.set(false);
        this.errorDetalle.set(interpretarError(e));
      },
    });
  }

  protected rechazar(): void {
    const devolucion = this.seleccionada();
    if (!devolucion) return;
    if (this.motivoRechazo.trim().length < 3) {
      this.errorDetalle.set('Escribí por qué se rechaza la devolución.');
      return;
    }
    this.ocupado.set(true);
    this.errorDetalle.set(null);
    this.servicio.rechazar(devolucion.id, this.motivoRechazo.trim()).subscribe({
      next: (detalle) => {
        this.ocupado.set(false);
        this.rechazando.set(false);
        this.motivoRechazo = '';
        this.seleccionada.set(detalle);
        this.aviso.set('Devolución rechazada. Se le avisó a la clienta.');
        this.cargar();
      },
      error: (e: HttpErrorResponse) => {
        this.ocupado.set(false);
        this.errorDetalle.set(interpretarError(e));
      },
    });
  }

  /** Cambio de prenda: la prenda nueva se cobra en caja y aca se vincula esa venta. */
  protected vincularCambio(): void {
    const devolucion = this.seleccionada();
    const numero = this.numeroVentaCambio.trim();
    if (!devolucion || !numero) return;
    this.ocupado.set(true);
    this.errorDetalle.set(null);
    this.servicio.vincularCambio(devolucion.id, numero).subscribe({
      next: (detalle) => {
        this.ocupado.set(false);
        this.numeroVentaCambio = '';
        this.seleccionada.set(detalle);
        this.aviso.set(`Cambio registrado: la venta ${detalle.venta_cambio_numero} reemplaza lo devuelto.`);
      },
      error: (e: HttpErrorResponse) => {
        this.ocupado.set(false);
        this.errorDetalle.set(interpretarError(e));
      },
    });
  }

  // ------------------------------------------------------------ nota de devolucion

  /** Arma la nota en una ventana aparte y abre el dialogo de impresion (o "Guardar como PDF"). */
  protected imprimirNota(): void {
    const devolucion = this.seleccionada();
    if (!devolucion) return;
    this.servicio.nota(devolucion.id).subscribe({
      next: (nota) => {
        const ventana = window.open('', '_blank', 'width=720,height=900');
        if (!ventana) {
          this.errorDetalle.set('El navegador bloqueó la ventana de impresión: permití las ventanas emergentes.');
          return;
        }
        ventana.document.write(this.htmlNota(nota));
        ventana.document.close();
        ventana.focus();
        ventana.print();
      },
      error: (e: HttpErrorResponse) => this.errorDetalle.set(interpretarError(e)),
    });
  }

  private htmlNota(nota: NotaDevolucionOut): string {
    const d = nota.devolucion;
    const reemplazos: Record<string, string> = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' };
    const esc = (texto: string | null | undefined) => (texto ?? '').replace(/[&<>"]/g, (c) => reemplazos[c] ?? c);
    const si = (valor: boolean) => (valor ? 'Sí' : 'No');
    const filas = d.detalle
      .map(
        (l) =>
          `<tr><td>${esc(l.sku)}</td><td>${esc(l.producto)}<br><small>${esc(l.talla)} · ${esc(l.color)}</small></td>` +
          `<td class="n">${l.cantidad}</td><td class="n">${this.precio(l.precio_unitario)}</td>` +
          `<td>${l.talla_solicitada ? `${esc(l.talla_solicitada)} · ${esc(l.color_solicitado)}` : '—'}</td></tr>`,
      )
      .join('');
    return `<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Nota ${esc(d.numero)}</title>
      <style>
        body{font-family:Arial,sans-serif;color:#111;margin:32px;font-size:13px}
        h1{font-size:20px;margin:0}
        .cab{display:flex;justify-content:space-between;border-bottom:2px solid #111;padding-bottom:8px}
        table{width:100%;border-collapse:collapse;margin:16px 0}
        th,td{border:1px solid #999;padding:6px;text-align:left;vertical-align:top}
        th{background:#eee}.n{text-align:right}small{color:#555}
        .firmas{display:flex;gap:48px;margin-top:64px}
        .firmas div{flex:1;border-top:1px solid #111;text-align:center;padding-top:4px}
      </style></head><body>
      <div class="cab"><div><h1>${esc(nota.empresa_razon_social)}</h1>NIT ${esc(nota.empresa_nit)}<br>
        ${esc(d.sucursal)} · ${esc(nota.sucursal_direccion)} · ${esc(nota.sucursal_ciudad)}</div>
        <div style="text-align:right"><h1>NOTA DE DEVOLUCIÓN</h1><strong>${esc(d.numero)}</strong><br>
        ${this.fecha(d.fecha)}</div></div>
      <p><strong>Venta:</strong> ${esc(d.venta_numero)} del ${this.fecha(nota.venta_fecha)} ·
        <strong>Clienta:</strong> ${esc(d.cliente) || 'sin identificar'}</p>
      <p><strong>Motivo:</strong> ${esc(this.etiquetaMotivo(d.motivo_tipo))} — ${esc(d.motivo)}</p>
      <p><strong>Condiciones verificadas:</strong> etiqueta ${si(d.con_etiqueta)} · sin uso ${si(d.sin_uso)} ·
        comprobante ${si(d.con_comprobante)} · plazo aplicado: ${nota.plazo_dias} días desde la compra</p>
      <table><thead><tr><th>SKU</th><th>Prenda devuelta</th><th class="n">Cant.</th><th class="n">Precio u.</th>
        <th>Se lleva a cambio</th></tr></thead><tbody>${filas}</tbody></table>
      <p><strong>Estado:</strong> ${esc(this.etiquetaEstado(d.estado))} ·
        <strong>${d.estado === 'APROBADA' ? 'Reintegrado' : 'Reintegro estimado'}:</strong> ${this.precio(d.monto_devuelto)}
        ${d.reintegro_metodo ? ` (${esc(this.etiquetaReintegro(d.reintegro_metodo))})` : ''}
        ${d.venta_cambio_numero ? ` · <strong>Venta del cambio:</strong> ${esc(d.venta_cambio_numero)}` : ''}</p>
      <div class="firmas"><div>Firma de la clienta</div><div>Registró: ${esc(d.registrada_por)}</div></div>
      </body></html>`;
  }

  // ------------------------------------------------------------ formato

  protected etiquetaMotivo(motivo: MotivoDevolucion): string {
    return this.motivos.find((m) => m.valor === motivo)?.etiqueta ?? motivo;
  }

  protected etiquetaReintegro(metodo: MetodoReintegro | null): string {
    switch (metodo) {
      case 'STRIPE':
        return 'Reembolso automático a la tarjeta (Stripe)';
      case 'EFECTIVO':
        return 'Efectivo, desde la caja abierta';
      case 'TARJETA':
        return 'Tarjeta (reversar en el POS, fuera del sistema)';
      case 'QR':
        return 'QR / transferencia a la clienta (fuera del sistema)';
      case 'TRANSFERENCIA':
        return 'Transferencia a la clienta (fuera del sistema)';
      default:
        return 'Sin pago aprobado registrado';
    }
  }

  private instruccionReintegro(metodo: MetodoReintegro | null, monto: number | string): string {
    const importe = this.precio(monto);
    switch (metodo) {
      case 'STRIPE':
        return `Stripe ya reembolsó ${importe} a la tarjeta de la clienta.`;
      case 'EFECTIVO':
        return `Entregale ${importe} en efectivo: ya se descontó del arqueo de tu caja.`;
      default:
        return `Reintegrar ${importe} a la clienta (${this.etiquetaReintegro(metodo).toLowerCase()}).`;
    }
  }

  protected precio(valor: number | string | null | undefined): string {
    return valor === null || valor === undefined ? '—' : `Bs ${Number(valor).toFixed(2)}`;
  }

  protected fecha(valor: string | null): string {
    return valor ? new Date(valor).toLocaleString('es-BO', { dateStyle: 'short', timeStyle: 'short' }) : '—';
  }

  protected etiquetaEstado(estado: EstadoDevolucion): string {
    switch (estado) {
      case 'SOLICITADA':
        return 'Pendiente';
      case 'APROBADA':
        return 'Aprobada';
      case 'RECHAZADA':
        return 'Rechazada';
    }
  }
}
