import { DecimalPipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { AuthService } from '../../../core/acceso-y-organizacion/auth/auth.service';
import { AccionResolver, EstadoServidor, OperacionServidor } from '../../../core/operacion-sin-conexion/sincronizacion/sincronizacion.models';
import { SincronizacionService } from '../../../core/operacion-sin-conexion/sincronizacion/sincronizacion.service';
import { SucursalOut } from '../../../core/acceso-y-organizacion/sucursales/sucursales.models';
import { SucursalesService } from '../../../core/acceso-y-organizacion/sucursales/sucursales.service';
import { interpretarError } from '../../../shared/errores';
import { PanelShell } from '../../../shared/panel/panel-shell';

const ETIQUETA_ESTADO: Record<EstadoServidor, string> = {
  CONFIRMADA: 'Confirmada',
  RECHAZADA: 'Rechazada',
  CONFLICTO: 'En conflicto',
};

/**
 * CU24/CU23 del lado del encargado: el log del servidor con todas las operaciones offline que
 * llegaron de los dispositivos de la sucursal (o de toda la empresa, para su administrador), con
 * el motivo de cada rechazo o conflicto y las acciones para resolverlo. Es el registro de
 * sincronizacion que pide RNF10: quien, cuando, cuantos intentos y que paso, sin datos de pago.
 */
@Component({
  selector: 'app-panel-sincronizacion-page',
  standalone: true,
  imports: [PanelShell, FormsModule, DecimalPipe],
  templateUrl: './panel-sincronizacion.page.html',
  styleUrls: [
    '../../../shared/panel/panel-comun.css',
    '../../catalogo-e-inventario/panel-recepciones/panel-recepciones.page.css',
    './panel-sincronizacion.page.css',
  ],
})
export class PanelSincronizacionPage implements OnInit {
  private readonly servicio = inject(SincronizacionService);
  private readonly sucursalesService = inject(SucursalesService);
  private readonly auth = inject(AuthService);

  protected readonly puedeResolver = this.auth.tienePermiso('sincronizacion.actualizar');
  protected readonly eligeSucursal = this.auth.tienePermiso('sucursales.actualizar');
  protected readonly etiquetas = ETIQUETA_ESTADO;

  protected readonly sucursales = signal<SucursalOut[]>([]);
  protected sucursalId = '';
  protected filtroEstado: '' | EstadoServidor = '';
  protected soloAbiertas = false;
  protected desde = '';

  protected readonly operaciones = signal<OperacionServidor[]>([]);
  protected readonly cargando = signal(true);
  protected readonly error = signal<string | null>(null);
  protected readonly aviso = signal<string | null>(null);
  protected readonly ocupado = signal(false);
  protected readonly seleccionada = signal<OperacionServidor | null>(null);
  protected nota = '';

  protected readonly resumen = computed(() => {
    const ops = this.operaciones();
    return {
      confirmadas: ops.filter((o) => o.estado === 'CONFIRMADA').length,
      rechazadas: ops.filter((o) => o.estado === 'RECHAZADA').length,
      conflictos: ops.filter((o) => o.estado === 'CONFLICTO' && !o.resuelta_en).length,
      duplicadas: ops.filter((o) => o.intentos > 1).length,
    };
  });

  ngOnInit(): void {
    if (this.eligeSucursal) {
      this.sucursalesService.listarSucursales().subscribe({ next: (s) => this.sucursales.set(s) });
    }
    this.cargar();
  }

  protected cargar(): void {
    this.cargando.set(true);
    this.error.set(null);
    this.servicio
      .logServidor({
        estado: this.filtroEstado || null,
        solo_abiertas: this.soloAbiertas,
        sucursal_id: this.sucursalId || null,
        desde: this.desde || null,
      })
      .subscribe({
        next: (ops) => {
          this.operaciones.set(ops);
          const actual = this.seleccionada();
          this.seleccionada.set(actual ? (ops.find((o) => o.id === actual.id) ?? null) : null);
          this.cargando.set(false);
        },
        error: (e: HttpErrorResponse) => {
          this.cargando.set(false);
          this.error.set(interpretarError(e, 'No se pudo cargar el registro de sincronización.'));
        },
      });
  }

  protected abrir(o: OperacionServidor): void {
    this.seleccionada.set(o);
    this.nota = '';
    this.aviso.set(null);
  }

  protected resolver(accion: AccionResolver): void {
    const o = this.seleccionada();
    if (!o) return;
    if (accion === 'DESCARTAR' && !confirm('¿Descartar la operación? Queda rechazada y no se vuelve a procesar.')) return;
    this.ocupado.set(true);
    this.error.set(null);
    this.servicio.resolverEnServidor(o.id, accion, this.nota.trim() || undefined).subscribe({
      next: (r) => {
        this.ocupado.set(false);
        this.aviso.set(
          r.estado === 'CONFIRMADA'
            ? 'La operación quedó confirmada.'
            : r.estado === 'RECHAZADA'
              ? 'La operación quedó rechazada.'
              : `Sigue en conflicto: ${r.motivo ?? ''}`,
        );
        this.cargar();
      },
      error: (e: HttpErrorResponse) => {
        this.ocupado.set(false);
        this.error.set(interpretarError(e, 'No se pudo resolver el conflicto.'));
      },
    });
  }

  /** Lo que se vendio/reservo, legible, a partir del payload que mando el dispositivo. */
  protected detalle(o: OperacionServidor): string {
    const p = o.payload;
    const items = p.venta?.items ?? p.reserva?.items ?? [];
    const unidades = items.reduce((s, i) => s + i.cantidad, 0);
    if (p.venta) return `${unidades} prenda(s), Bs ${p.venta.total} en efectivo`;
    if (p.reserva) return `${unidades} prenda(s) para ${p.reserva.cliente_email}, visita ${p.reserva.fecha_visita}`;
    return '';
  }

  protected fecha(iso: string | null): string {
    return iso ? iso.slice(0, 16).replace('T', ' ') : '—';
  }

  protected resultadoTexto(o: OperacionServidor): string | null {
    const r = o.resultado as { numero?: string; venta_numero?: string; codigo?: string } | null;
    return r ? (r.numero ?? r.venta_numero ?? r.codigo ?? null) : null;
  }
}
