import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { AuthService } from '../../core/auth/auth.service';
import { SucursalOut } from '../../core/sucursales/sucursales.models';
import { SucursalesService } from '../../core/sucursales/sucursales.service';
import {
  DireccionTraspaso,
  EstadoTraspaso,
  MovimientoTraspasoOut,
  TraspasoDetalleOut,
  TraspasoOut,
  VarianteTraspasoOut,
} from '../../core/traspasos/traspasos.models';
import { TraspasosService } from '../../core/traspasos/traspasos.service';
import { interpretarError } from '../../shared/errores';
import { PanelShell } from '../../shared/panel/panel-shell';

interface LineaNueva {
  variante: VarianteTraspasoOut;
  cantidad: number;
}

/**
 * Traspasos entre sucursales (PENDIENTES 2.7). El origen arma y despacha (sale su stock), el
 * destino recibe indicando lo que llego (entra eso). Las tres tiendas estan en climas distintos:
 * mover el surtido hacia donde rota es la operacion natural del negocio.
 */
@Component({
  selector: 'app-panel-traspasos-page',
  standalone: true,
  imports: [PanelShell, FormsModule],
  templateUrl: './panel-traspasos.page.html',
  // lista/tarjeta/buscador/resultados/carga son las mismas piezas que la pantalla de recepciones
  styleUrls: [
    '../../shared/panel/panel-comun.css',
    '../panel-recepciones/panel-recepciones.page.css',
    './panel-traspasos.page.css',
  ],
})
export class PanelTraspasosPage implements OnInit {
  private readonly servicio = inject(TraspasosService);
  private readonly sucursalesService = inject(SucursalesService);
  private readonly auth = inject(AuthService);

  protected readonly puedeCrear = this.auth.tienePermiso('traspasos.crear');
  protected readonly puedeMover = this.auth.tienePermiso('traspasos.actualizar');
  protected readonly puedeAnular = this.auth.tienePermiso('traspasos.eliminar');
  /** el ADMIN elige el origen; el encargado siempre manda desde su sucursal */
  protected readonly eligeOrigen = this.auth.tienePermiso('sucursales.actualizar');

  protected readonly cargando = signal(true);
  protected readonly traspasos = signal<TraspasoOut[]>([]);
  protected readonly error = signal<string | null>(null);
  protected filtroEstado: '' | EstadoTraspaso = '';
  protected filtroDireccion: '' | DireccionTraspaso = '';

  protected readonly sucursales = signal<SucursalOut[]>([]);

  protected readonly seleccionado = signal<TraspasoDetalleOut | null>(null);
  protected readonly movimientos = signal<MovimientoTraspasoOut[]>([]);
  protected readonly errorDetalle = signal<string | null>(null);
  protected readonly aviso = signal<string | null>(null);
  protected readonly ocupado = signal(false);

  // --- recepcion en destino ---
  protected readonly recibidas = signal<Record<string, number>>({});
  protected observacion = '';

  // --- alta ---
  protected readonly creando = signal(false);
  protected origenId = '';
  protected destinoId = '';
  protected termino = '';
  protected readonly resultados = signal<VarianteTraspasoOut[]>([]);
  protected readonly buscando = signal(false);
  protected readonly lineasNuevas = signal<LineaNueva[]>([]);
  protected readonly errorNuevo = signal<string | null>(null);

  protected readonly unidadesNuevas = computed(() =>
    this.lineasNuevas().reduce((suma, linea) => suma + linea.cantidad, 0),
  );

  protected readonly faltante = computed(() => {
    const traspaso = this.seleccionado();
    if (!traspaso) return 0;
    const recibidas = this.recibidas();
    return traspaso.detalle.reduce(
      (suma, linea) => suma + linea.cantidad_solicitada - (recibidas[linea.id] ?? linea.cantidad_solicitada),
      0,
    );
  });

  ngOnInit(): void {
    this.cargar();
    this.sucursalesService.listarSucursales().subscribe({
      next: (sucursales) => this.sucursales.set(sucursales),
      error: () => this.sucursales.set([]),
    });
  }

  protected cargar(): void {
    this.cargando.set(true);
    this.error.set(null);
    this.servicio.listar(this.filtroEstado || null, this.filtroDireccion || null).subscribe({
      next: (traspasos) => {
        this.traspasos.set(traspasos);
        this.cargando.set(false);
      },
      error: (e: HttpErrorResponse) => {
        this.error.set(interpretarError(e, 'No se pudieron cargar los traspasos.'));
        this.cargando.set(false);
      },
    });
  }

  // ------------------------------------------------------------ alta

  protected abrirNuevo(): void {
    this.creando.set(true);
    this.seleccionado.set(null);
    this.errorNuevo.set(null);
    this.lineasNuevas.set([]);
    this.resultados.set([]);
    this.termino = '';
    this.origenId = this.eligeOrigen ? (this.sucursales()[0]?.id ?? '') : '';
    this.destinoId = this.sucursales().find((s) => s.id !== this.origenId)?.id ?? '';
  }

  protected cambioSucursales(): void {
    // el stock que se mostro era de otro par de sucursales
    this.resultados.set([]);
    this.lineasNuevas.set([]);
  }

  protected buscar(): void {
    if (!this.termino.trim()) return;
    this.buscando.set(true);
    this.errorNuevo.set(null);
    this.servicio
      .buscarVariantes(this.termino.trim(), this.eligeOrigen ? this.origenId : null, this.destinoId || null)
      .subscribe({
        next: (resultados) => {
          this.resultados.set(resultados);
          this.buscando.set(false);
        },
        error: (e: HttpErrorResponse) => {
          this.buscando.set(false);
          this.errorNuevo.set(interpretarError(e));
        },
      });
  }

  protected agregar(variante: VarianteTraspasoOut): void {
    if (variante.disponible_origen <= 0) {
      this.errorNuevo.set(`${variante.sku} no tiene unidades disponibles en el origen.`);
      return;
    }
    this.errorNuevo.set(null);
    this.lineasNuevas.update((lineas) =>
      lineas.some((l) => l.variante.id === variante.id) ? lineas : [...lineas, { variante, cantidad: 1 }],
    );
  }

  protected fijarCantidadNueva(varianteId: string, valor: number): void {
    this.lineasNuevas.update((lineas) =>
      lineas.map((l) =>
        l.variante.id === varianteId
          ? { ...l, cantidad: Math.max(1, Math.min(Math.floor(Number(valor) || 1), l.variante.disponible_origen)) }
          : l,
      ),
    );
  }

  protected quitar(varianteId: string): void {
    this.lineasNuevas.update((lineas) => lineas.filter((l) => l.variante.id !== varianteId));
  }

  protected crear(): void {
    if (!this.destinoId) {
      this.errorNuevo.set('Elegí la sucursal de destino.');
      return;
    }
    if (this.lineasNuevas().length === 0) {
      this.errorNuevo.set('Agregá al menos una prenda.');
      return;
    }
    this.ocupado.set(true);
    this.errorNuevo.set(null);
    this.servicio
      .crear({
        sucursal_origen_id: this.eligeOrigen ? this.origenId || null : null,
        sucursal_destino_id: this.destinoId,
        lineas: this.lineasNuevas().map((l) => ({ variante_id: l.variante.id, cantidad: l.cantidad })),
      })
      .subscribe({
        next: (traspaso) => {
          this.ocupado.set(false);
          this.creando.set(false);
          this.aplicar(traspaso);
          this.aviso.set('Traspaso solicitado. El stock sale del origen recién al despacharlo.');
          this.cargar();
        },
        error: (e: HttpErrorResponse) => {
          this.ocupado.set(false);
          this.errorNuevo.set(interpretarError(e));
        },
      });
  }

  // ------------------------------------------------------------ detalle y ciclo de vida

  protected abrir(traspaso: TraspasoOut): void {
    this.creando.set(false);
    this.errorDetalle.set(null);
    this.aviso.set(null);
    this.servicio.obtener(traspaso.id).subscribe({
      next: (detalle) => this.aplicar(detalle),
      error: (e: HttpErrorResponse) => this.errorDetalle.set(interpretarError(e)),
    });
  }

  private aplicar(detalle: TraspasoDetalleOut): void {
    this.seleccionado.set(detalle);
    this.observacion = '';
    this.recibidas.set(Object.fromEntries(detalle.detalle.map((l) => [l.id, l.cantidad_solicitada])));
    this.movimientos.set([]);
    if (detalle.estado !== 'SOLICITADO') {
      this.servicio.movimientos(detalle.id).subscribe({
        next: (movimientos) => this.movimientos.set(movimientos),
        error: () => this.movimientos.set([]),
      });
    }
  }

  protected puedeDespachar(t: TraspasoOut): boolean {
    return this.puedeMover && t.estado === 'SOLICITADO' && t.mi_lado !== 'DESTINO';
  }

  protected puedeRecibir(t: TraspasoOut): boolean {
    return this.puedeMover && t.estado === 'EN_TRANSITO' && t.mi_lado !== 'ORIGEN';
  }

  protected puedeAnularlo(t: TraspasoOut): boolean {
    if (!this.puedeAnular) return false;
    if (t.estado === 'SOLICITADO') return true;
    return t.estado === 'EN_TRANSITO' && t.mi_lado !== 'DESTINO';
  }

  protected fijarRecibida(detalleId: string, valor: number, maximo: number): void {
    const cantidad = Math.max(0, Math.min(Math.floor(Number(valor) || 0), maximo));
    this.recibidas.update((actual) => ({ ...actual, [detalleId]: cantidad }));
  }

  private operar(
    accion: (id: string) => ReturnType<TraspasosService['despachar']>,
    mensaje: (t: TraspasoDetalleOut) => string,
  ): void {
    const traspaso = this.seleccionado();
    if (!traspaso) return;
    this.ocupado.set(true);
    this.errorDetalle.set(null);
    this.aviso.set(null);
    accion(traspaso.id).subscribe({
      next: (detalle) => {
        this.ocupado.set(false);
        this.aplicar(detalle);
        this.aviso.set(mensaje(detalle));
        this.cargar();
      },
      error: (e: HttpErrorResponse) => {
        this.ocupado.set(false);
        this.errorDetalle.set(interpretarError(e));
      },
    });
  }

  protected despachar(): void {
    this.operar(
      (id) => this.servicio.despachar(id),
      (t) => `Despachado: ${t.unidades_solicitadas} unidad(es) salieron del stock de ${t.origen}.`,
    );
  }

  protected recibir(): void {
    const recibidas = this.recibidas();
    this.operar(
      (id) =>
        this.servicio.recibir(id, {
          lineas: Object.entries(recibidas).map(([detalle_id, cantidad_recibida]) => ({
            detalle_id,
            cantidad_recibida,
          })),
          observacion: this.observacion.trim() || null,
        }),
      (t) => {
        const faltan = t.unidades_solicitadas - (t.unidades_recibidas ?? 0);
        return (
          `Recibido: ${t.unidades_recibidas} unidad(es) entraron al stock de ${t.destino}.` +
          (faltan > 0
            ? ` Faltaron ${faltan}: ya salieron del origen, corregilo con un ajuste en Inventario cuando se aclare.`
            : '')
        );
      },
    );
  }

  protected anular(): void {
    const enTransito = this.seleccionado()?.estado === 'EN_TRANSITO';
    this.operar(
      (id) => this.servicio.anular(id),
      (t) =>
        enTransito
          ? `Traspaso anulado: las ${t.unidades_solicitadas} unidad(es) volvieron al stock de ${t.origen}.`
          : 'Traspaso anulado. No se había movido stock.',
    );
  }

  // ------------------------------------------------------------ formato

  protected fecha(valor: string | null): string {
    return valor ? new Date(valor).toLocaleString('es-BO', { dateStyle: 'short', timeStyle: 'short' }) : '—';
  }

  protected etiquetaEstado(estado: EstadoTraspaso): string {
    switch (estado) {
      case 'SOLICITADO':
        return 'Solicitado';
      case 'EN_TRANSITO':
        return 'En tránsito';
      case 'RECIBIDO':
        return 'Recibido';
      case 'ANULADO':
        return 'Anulado';
    }
  }

  protected etiquetaMovimiento(tipo: string): string {
    return tipo === 'TRASPASO_SAL' ? 'Salida' : tipo === 'TRASPASO_ENT' ? 'Entrada' : tipo;
  }
}
