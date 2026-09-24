import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { AuthService } from '../../core/auth/auth.service';
import {
  DevolucionDetalleOut,
  DevolucionOut,
  EstadoDevolucion,
  VentaDevolvibleOut,
} from '../../core/devoluciones/devoluciones.models';
import { DevolucionesService } from '../../core/devoluciones/devoluciones.service';
import { interpretarError } from '../../shared/errores';
import { PanelShell } from '../../shared/panel/panel-shell';

/**
 * Devoluciones de ventas (PENDIENTES 2.7). Dos pasos, los dos del personal: registrar la
 * devolucion sobre una venta pagada (nace SOLICITADA, no mueve stock) y resolverla: aprobar
 * reingresa el stock (trigger en la base) y calcula lo que se reintegra; rechazar pide motivo.
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

  protected readonly seleccionada = signal<DevolucionDetalleOut | null>(null);
  protected readonly errorDetalle = signal<string | null>(null);
  protected readonly aviso = signal<string | null>(null);
  protected readonly ocupado = signal(false);
  protected motivoRechazo = '';
  protected readonly rechazando = signal(false);

  // --- alta ---
  protected readonly creando = signal(false);
  protected numeroVenta = '';
  protected readonly venta = signal<VentaDevolvibleOut | null>(null);
  protected readonly buscandoVenta = signal(false);
  protected readonly errorNueva = signal<string | null>(null);
  /** cantidad a devolver por venta_detalle_id */
  protected readonly cantidades = signal<Partial<Record<string, number>>>({});
  protected motivo = '';

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
    this.servicio.listar(this.filtroEstado || null, this.filtroVenta.trim() || null).subscribe({
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

  // ------------------------------------------------------------ alta

  protected abrirNueva(): void {
    this.creando.set(true);
    this.seleccionada.set(null);
    this.venta.set(null);
    this.numeroVenta = '';
    this.motivo = '';
    this.cantidades.set({});
    this.errorNueva.set(null);
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
    const lineas = Object.entries(this.cantidades())
      .map(([venta_detalle_id, cantidad]) => ({ venta_detalle_id, cantidad: cantidad ?? 0 }))
      .filter((linea) => linea.cantidad > 0);
    if (lineas.length === 0) {
      this.errorNueva.set('Indicá al menos una prenda a devolver.');
      return;
    }
    if (this.motivo.trim().length < 3) {
      this.errorNueva.set('Escribí el motivo de la devolución.');
      return;
    }

    this.ocupado.set(true);
    this.errorNueva.set(null);
    this.servicio.registrar({ venta_id: venta.venta_id, motivo: this.motivo.trim(), lineas }).subscribe({
      next: (devolucion) => {
        this.ocupado.set(false);
        this.creando.set(false);
        this.seleccionada.set(devolucion);
        this.aviso.set('Devolución registrada. Queda pendiente de aprobación: todavía no volvió al stock.');
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
            `Reintegrar ${this.precio(detalle.monto_devuelto)} a la clienta.` +
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

  // ------------------------------------------------------------ formato

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
