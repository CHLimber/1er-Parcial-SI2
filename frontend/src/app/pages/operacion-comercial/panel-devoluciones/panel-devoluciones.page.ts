import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { AuthService } from '../../../core/acceso-y-organizacion/auth/auth.service';
import {
  CambiosMesOut,
  COMO_SE_REINTEGRA,
  DevolucionDetalleOut,
  DevolucionOut,
  ESTADO_DEVOLUCION_TEXTO,
  EstadoDevolucion,
  MOTIVOS_DEVOLUCION,
  MetodoDiferencia,
  MetodoReintegro,
  MotivoDevolucion,
  NotaDevolucionOut,
  OrigenDevolucion,
  TipoDevolucion,
  VarianteCambioOut,
  VentaDevolvibleOut,
  motivosDe,
} from '../../../core/operacion-comercial/devoluciones/devoluciones.models';
import { DevolucionesService } from '../../../core/operacion-comercial/devoluciones/devoluciones.service';
import { interpretarError } from '../../../shared/errores';
import { PanelShell } from '../../../shared/panel/panel-shell';

const IVA = 0.13;

/**
 * Devoluciones e intercambios (PENDIENTES 10), en dos pestañas con las mismas reglas: 3 días desde
 * la compra, una sola por compra y hasta 3 prendas.
 *  - Devolución: vuelve la prenda y vuelve la plata (Stripe por la API; efectivo y QR desde la caja).
 *  - Intercambio: otra talla/color de la misma prenda. Lo devuelto es crédito: si lo nuevo cuesta
 *    más la clienta paga la diferencia al concretarlo; si cuesta menos se le devuelve lo que sobra.
 * Dos orígenes: registrada acá en caja (la clienta está presente) o pedida online desde Mis compras,
 * que el personal acepta y concreta cuando la clienta llega a la sucursal.
 */
@Component({
  selector: 'app-panel-devoluciones-page',
  standalone: true,
  imports: [PanelShell, FormsModule],
  templateUrl: './panel-devoluciones.page.html',
  // lista/tarjeta/ficha/carga son las mismas piezas que la pantalla de recepciones
  styleUrls: [
    '../../../shared/panel/panel-comun.css',
    '../../catalogo-e-inventario/panel-recepciones/panel-recepciones.page.css',
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
  protected readonly estados = Object.entries(ESTADO_DEVOLUCION_TEXTO) as [EstadoDevolucion, string][];

  /** pestaña: una por tipo, más la consulta de cambios del mes */
  protected readonly vista = signal<TipoDevolucion | 'cambios'>('DEVOLUCION');
  protected readonly tipo = computed<TipoDevolucion>(() => (this.vista() === 'INTERCAMBIO' ? 'INTERCAMBIO' : 'DEVOLUCION'));
  protected readonly motivosDelTipo = computed(() => motivosDe(this.tipo()));

  protected readonly cargando = signal(true);
  protected readonly devoluciones = signal<DevolucionOut[]>([]);
  protected readonly error = signal<string | null>(null);
  protected filtroEstado: '' | EstadoDevolucion = '';
  protected filtroOrigen: '' | OrigenDevolucion = '';
  protected filtroVenta = '';
  protected filtroMotivo: '' | MotivoDevolucion = '';
  protected filtroDesde = '';
  protected filtroHasta = '';

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
  /** al concretar: condiciones vistas al recibir la prenda y cómo paga la diferencia */
  protected aprConEtiqueta = true;
  protected aprSinUso = true;
  protected aprConComprobante = true;
  protected metodoDiferencia: MetodoDiferencia | '' = '';

  // --- alta en caja ---
  protected readonly creando = signal(false);
  protected numeroVenta = '';
  protected readonly venta = signal<VentaDevolvibleOut | null>(null);
  protected readonly buscandoVenta = signal(false);
  protected readonly errorNueva = signal<string | null>(null);
  /** cantidad por venta_detalle_id */
  protected readonly cantidades = signal<Partial<Record<string, number>>>({});
  protected motivo = '';
  protected readonly motivoTipo = signal<MotivoDevolucion>('NO_GUSTO');
  protected conEtiqueta = true;
  protected sinUso = true;
  protected conComprobante = true;
  /** variante elegida a cambio, por venta_detalle_id (solo intercambio) */
  protected readonly solicitadas = signal<Partial<Record<string, string>>>({});
  /** opciones de cambio por variante vendida: otras tallas/colores de la misma prenda */
  protected readonly opcionesCambio = signal<Partial<Record<string, VarianteCambioOut[]>>>({});

  protected readonly esIntercambio = computed(() => this.tipo() === 'INTERCAMBIO');

  /** lo que vale lo devuelto (crédito en un intercambio) */
  protected readonly estimado = computed(() => {
    const venta = this.venta();
    if (!venta) return 0;
    const cantidades = this.cantidades();
    return venta.lineas.reduce(
      (suma, linea) => suma + (cantidades[linea.venta_detalle_id] ?? 0) * Number(linea.reembolso_unitario),
      0,
    );
  });

  /** lo que valen las prendas nuevas elegidas, con IVA */
  protected readonly estimadoNuevo = computed(() => {
    const venta = this.venta();
    if (!venta || !this.esIntercambio()) return 0;
    const cantidades = this.cantidades();
    const solicitadas = this.solicitadas();
    let subtotal = 0;
    for (const linea of venta.lineas) {
      const elegida = solicitadas[linea.venta_detalle_id];
      const opcion = (this.opcionesCambio()[linea.variante_id] ?? []).find((o) => o.variante_id === elegida);
      if (opcion) subtotal += (cantidades[linea.venta_detalle_id] ?? 0) * Number(opcion.precio);
    }
    return Math.round(subtotal * (1 + IVA) * 100) / 100;
  });

  protected readonly unidadesElegidas = computed(() =>
    Object.values(this.cantidades()).reduce((suma: number, cantidad) => suma + (cantidad ?? 0), 0),
  );

  /** motivo por el que la venta buscada no admite otra devolución/intercambio (o null) */
  protected readonly bloqueoVenta = computed(() => {
    const v = this.venta();
    if (!v) return null;
    if (v.es_venta_de_cambio) return 'Esta venta salió de un intercambio: ya usó su devolución.';
    if (v.solicitud_vigente) return `La venta ya tiene la ${v.solicitud_vigente}: se permite una sola por compra.`;
    const vencida = this.esIntercambio() ? v.fuera_de_plazo_cambio : v.fuera_de_plazo;
    if (vencida) {
      const hasta = this.esIntercambio() ? v.cambio_vence_en : v.plazo_vence_en;
      return `Venció el plazo el ${this.fecha(hasta)}: ya no se puede registrar.`;
    }
    return null;
  });

  ngOnInit(): void {
    this.cargar();
  }

  protected elegirVista(vista: TipoDevolucion | 'cambios'): void {
    this.vista.set(vista);
    if (vista === 'cambios') {
      this.cargarCambios();
      return;
    }
    this.filtroMotivo = '';
    this.creando.set(false);
    this.seleccionada.set(null);
    this.cargar();
  }

  protected cargar(): void {
    this.cargando.set(true);
    this.error.set(null);
    this.servicio
      .listar({
        tipo: this.tipo(),
        origen: this.filtroOrigen || null,
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

  // ------------------------------------------------------------ alta en caja

  protected abrirNueva(): void {
    this.creando.set(true);
    this.seleccionada.set(null);
    this.venta.set(null);
    this.numeroVenta = '';
    this.motivo = '';
    this.motivoTipo.set(this.esIntercambio() ? 'TALLA' : 'NO_GUSTO');
    this.conEtiqueta = this.sinUso = this.conComprobante = true;
    this.cantidades.set({});
    this.solicitadas.set({});
    this.opcionesCambio.set({});
    this.errorNueva.set(null);
  }

  protected cambiarMotivo(motivo: MotivoDevolucion): void {
    this.motivoTipo.set(motivo);
    this.solicitadas.set({});
    if (this.esIntercambio()) this.cargarOpcionesCambio();
  }

  /** Para cada prenda de la venta, las otras tallas/colores con su precio y stock en la sucursal. */
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

  /** Opciones válidas según el motivo: TALLA = mismo color, otra talla; COLOR = misma talla, otro color. */
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
        if (this.esIntercambio()) this.cargarOpcionesCambio();
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
        variante_solicitada_id: this.esIntercambio() ? (solicitadas[venta_detalle_id] ?? null) : null,
      }))
      .filter((linea) => linea.cantidad > 0);
    if (lineas.length === 0) {
      this.errorNueva.set('Indicá al menos una prenda.');
      return;
    }
    if (this.unidadesElegidas() > venta.max_unidades) {
      this.errorNueva.set(`Se pueden devolver o cambiar hasta ${venta.max_unidades} prendas por compra.`);
      return;
    }
    if (this.esIntercambio() && lineas.some((linea) => !linea.variante_solicitada_id)) {
      this.errorNueva.set('Elegí qué talla o color se lleva la clienta por cada prenda.');
      return;
    }
    if (this.motivo.trim().length < 3) {
      this.errorNueva.set('Escribí el detalle del motivo.');
      return;
    }

    this.ocupado.set(true);
    this.errorNueva.set(null);
    this.servicio
      .registrar({
        venta_id: venta.venta_id,
        motivo_tipo: this.motivoTipo(),
        motivo: this.motivo.trim(),
        con_etiqueta: this.conEtiqueta,
        sin_uso: this.sinUso,
        con_comprobante: this.conComprobante,
        lineas,
      })
      .subscribe({
        next: (devolucion) => {
          this.ocupado.set(false);
          this.creando.set(false);
          this.prepararAprobacion(devolucion);
          this.seleccionada.set(devolucion);
          this.aviso.set(
            `Nota ${devolucion.numero} registrada. Concretala abajo para mover el stock y la plata.`,
          );
          this.cargar();
        },
        error: (e: HttpErrorResponse) => {
          this.ocupado.set(false);
          this.errorNueva.set(interpretarError(e));
        },
      });
  }

  // ------------------------------------------------------------ detalle y resolución

  protected abrir(devolucion: DevolucionOut): void {
    this.creando.set(false);
    this.errorDetalle.set(null);
    this.aviso.set(null);
    this.rechazando.set(false);
    this.servicio.obtener(devolucion.id).subscribe({
      next: (detalle) => {
        this.prepararAprobacion(detalle);
        this.seleccionada.set(detalle);
      },
      error: (e: HttpErrorResponse) => this.errorDetalle.set(interpretarError(e)),
    });
  }

  private prepararAprobacion(devolucion: DevolucionOut): void {
    this.aprConEtiqueta = devolucion.con_etiqueta;
    this.aprSinUso = devolucion.sin_uso;
    this.aprConComprobante = devolucion.con_comprobante;
    this.metodoDiferencia = '';
  }

  protected enTramite(devolucion: DevolucionOut): boolean {
    return devolucion.estado === 'SOLICITADA' || devolucion.estado === 'CONFIRMADA';
  }

  protected confirmar(): void {
    const devolucion = this.seleccionada();
    if (!devolucion) return;
    this.ocupado.set(true);
    this.errorDetalle.set(null);
    this.servicio.confirmar(devolucion.id).subscribe({
      next: (detalle) => {
        this.ocupado.set(false);
        this.seleccionada.set(detalle);
        this.aviso.set('Solicitud aceptada. Se le avisó a la clienta; concretala en caja cuando llegue.');
        this.cargar();
      },
      error: (e: HttpErrorResponse) => {
        this.ocupado.set(false);
        this.errorDetalle.set(interpretarError(e));
      },
    });
  }

  protected aprobar(): void {
    const devolucion = this.seleccionada();
    if (!devolucion) return;
    if (devolucion.tipo === 'INTERCAMBIO' && Number(devolucion.diferencia) > 0 && !this.metodoDiferencia) {
      this.errorDetalle.set('Elegí cómo paga la clienta la diferencia.');
      return;
    }
    this.ocupado.set(true);
    this.errorDetalle.set(null);
    this.servicio
      .aprobar(devolucion.id, {
        con_etiqueta: this.aprConEtiqueta,
        sin_uso: this.aprSinUso,
        con_comprobante: this.aprConComprobante,
        diferencia_metodo: this.metodoDiferencia || null,
      })
      .subscribe({
        next: (detalle) => {
          this.ocupado.set(false);
          this.seleccionada.set(detalle);
          this.aviso.set(this.resumenAprobacion(detalle));
          this.cargar();
        },
        error: (e: HttpErrorResponse) => {
          this.ocupado.set(false);
          this.errorDetalle.set(interpretarError(e));
        },
      });
  }

  private resumenAprobacion(d: DevolucionDetalleOut): string {
    const reintegro = Number(d.monto_reintegrado);
    const cobrado = Number(d.diferencia_cobrada);
    let plata = 'No hay diferencia de plata.';
    if (cobrado > 0) plata = `Cobrá ${this.precio(cobrado)} de diferencia (${(d.diferencia_metodo ?? '').toLowerCase()}).`;
    else if (reintegro > 0) plata = this.instruccionReintegro(d.reintegro_metodo, reintegro);
    const base =
      d.tipo === 'INTERCAMBIO'
        ? `Intercambio realizado: entregale la prenda nueva (venta ${d.venta_cambio_numero}).`
        : `Devolución realizada: ${d.unidades} unidad(es) volvieron al stock de ${d.sucursal}.`;
    return `${base} ${plata} El comprobante le llega por correo.`;
  }

  protected rechazar(): void {
    const devolucion = this.seleccionada();
    if (!devolucion) return;
    if (this.motivoRechazo.trim().length < 3) {
      this.errorDetalle.set('Escribí por qué se rechaza.');
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
        this.aviso.set('Rechazada. Se le avisó a la clienta.');
        this.cargar();
      },
      error: (e: HttpErrorResponse) => {
        this.ocupado.set(false);
        this.errorDetalle.set(interpretarError(e));
      },
    });
  }

  // ------------------------------------------------------------ nota imprimible

  /** Arma la nota en una ventana aparte y abre el diálogo de impresión (o "Guardar como PDF"). */
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
          `<td>${l.talla_solicitada ? `${esc(l.talla_solicitada)} · ${esc(l.color_solicitado)} (${this.precio(l.precio_solicitado)} + IVA)` : '—'}</td></tr>`,
      )
      .join('');
    const titulo = d.tipo === 'INTERCAMBIO' ? 'NOTA DE INTERCAMBIO' : 'NOTA DE DEVOLUCIÓN';
    const plata =
      d.tipo === 'INTERCAMBIO'
        ? `<strong>Valor devuelto (crédito):</strong> ${this.precio(d.monto_devuelto)} · <strong>Valor nuevo:</strong> ${this.precio(d.monto_cambio)} · ` +
          (d.estado === 'APROBADA'
            ? `<strong>Pagó:</strong> ${this.precio(d.diferencia_cobrada)} · <strong>Se le devolvió:</strong> ${this.precio(d.monto_reintegrado)}`
            : `<strong>Diferencia estimada:</strong> ${this.precio(d.diferencia)}`)
        : `<strong>${d.estado === 'APROBADA' ? 'Reintegrado' : 'Reintegro estimado'}:</strong> ${this.precio(d.estado === 'APROBADA' ? d.monto_reintegrado : d.monto_devuelto)}`;
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
        <div style="text-align:right"><h1>${titulo}</h1><strong>${esc(d.numero)}</strong><br>
        ${this.fecha(d.fecha)}</div></div>
      <p><strong>Venta:</strong> ${esc(d.venta_numero)} del ${this.fecha(nota.venta_fecha)} ·
        <strong>Clienta:</strong> ${esc(d.cliente) || 'sin identificar'} · <strong>Origen:</strong> ${d.origen === 'ONLINE' ? 'solicitud online' : 'caja'}</p>
      <p><strong>Motivo:</strong> ${esc(this.etiquetaMotivo(d.motivo_tipo))} — ${esc(d.motivo)}</p>
      <p><strong>Condiciones verificadas:</strong> etiqueta ${si(d.con_etiqueta)} · sin uso ${si(d.sin_uso)} ·
        comprobante ${si(d.con_comprobante)} · plazo: ${nota.plazo_dias} días desde la compra</p>
      <table><thead><tr><th>SKU</th><th>Prenda devuelta</th><th class="n">Cant.</th><th class="n">Precio u.</th>
        <th>Se lleva a cambio</th></tr></thead><tbody>${filas}</tbody></table>
      <p><strong>Estado:</strong> ${esc(this.etiquetaEstado(d.estado))} · ${plata}
        ${d.reintegro_metodo ? ` (${esc(this.etiquetaReintegro(d.reintegro_metodo))})` : ''}
        ${d.venta_cambio_numero ? ` · <strong>Venta del cambio:</strong> ${esc(d.venta_cambio_numero)}` : ''}</p>
      <div class="firmas"><div>Firma de la clienta</div><div>Registró: ${esc(d.registrada_por)}</div></div>
      </body></html>`;
  }

  // ------------------------------------------------------------ formato

  protected etiquetaMotivo(motivo: MotivoDevolucion): string {
    return MOTIVOS_DEVOLUCION.find((m) => m.valor === motivo)?.etiqueta ?? motivo;
  }

  protected etiquetaReintegro(metodo: MetodoReintegro | null): string {
    if (!metodo) return 'Sin pago aprobado registrado';
    if (metodo === 'STRIPE') return 'Reembolso automático a la tarjeta (Stripe)';
    return COMO_SE_REINTEGRA[metodo].charAt(0).toUpperCase() + COMO_SE_REINTEGRA[metodo].slice(1);
  }

  private instruccionReintegro(metodo: MetodoReintegro | null, monto: number): string {
    const importe = this.precio(monto);
    switch (metodo) {
      case 'STRIPE':
        return `Stripe ya reembolsó ${importe} a la tarjeta de la clienta.`;
      case 'EFECTIVO':
      case 'QR':
        return `Entregale ${importe} en efectivo: ya se descontó del efectivo de tu caja.`;
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

  protected visita(d: DevolucionOut): string {
    if (!d.fecha_visita) return '';
    const [anio, mes, dia] = d.fecha_visita.split('-');
    return `${dia}/${mes}/${anio} ${d.hora_visita?.slice(0, 5) ?? ''}`;
  }

  protected etiquetaEstado(estado: EstadoDevolucion): string {
    return ESTADO_DEVOLUCION_TEXTO[estado] ?? estado;
  }
}
