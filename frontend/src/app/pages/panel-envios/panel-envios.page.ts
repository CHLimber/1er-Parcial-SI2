import { DatePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { AuthService } from '../../core/auth/auth.service';
import {
  EnvioAdminDetalleOut,
  EnvioAdminOut,
  EstadoEnvio,
  RepartidorOut,
  ResumenEnviosOut,
} from '../../core/envios/envios.models';
import { EnviosService } from '../../core/envios/envios.service';
import { SucursalOut } from '../../core/sucursales/sucursales.models';
import { SucursalesService } from '../../core/sucursales/sucursales.service';
import { interpretarError } from '../../shared/errores';
import { MapaPunto } from '../../shared/mapa/mapa-punto';
import { PanelShell } from '../../shared/panel/panel-shell';

/** Transiciones que ofrece la pantalla; el backend las vuelve a validar (TRANSICIONES en
 * app/modules/envios/admin_router.py). */
const SIGUIENTES: Record<EstadoEnvio, EstadoEnvio[]> = {
  PENDIENTE: ['CANCELADO'],
  ASIGNADO: ['EN_RUTA', 'PENDIENTE', 'CANCELADO'],
  EN_RUTA: ['ENTREGADO', 'FALLIDO'],
  FALLIDO: ['EN_RUTA', 'CANCELADO'],
  ENTREGADO: [],
  CANCELADO: [],
};

/**
 * CU20 - panel de despacho. Un encargado ve la cola de su sucursal y asigna repartidor; un
 * repartidor ve solo su hoja de ruta y mueve el estado. La API acota ambas cosas, acá solo se
 * evita mostrar botones que van a dar 403.
 */
@Component({
  selector: 'app-panel-envios-page',
  standalone: true,
  imports: [FormsModule, DatePipe, PanelShell, MapaPunto],
  templateUrl: './panel-envios.page.html',
  styleUrls: ['../../shared/panel/panel-comun.css', './panel-envios.page.css'],
})
export class PanelEnviosPage implements OnInit {
  private readonly enviosService = inject(EnviosService);
  private readonly sucursalesService = inject(SucursalesService);
  private readonly auth = inject(AuthService);

  protected readonly envios = signal<EnvioAdminOut[]>([]);
  protected readonly resumen = signal<ResumenEnviosOut | null>(null);
  protected readonly repartidores = signal<RepartidorOut[]>([]);
  protected readonly sucursales = signal<SucursalOut[]>([]);
  protected readonly detalle = signal<EnvioAdminDetalleOut | null>(null);

  protected readonly cargando = signal(true);
  protected readonly trabajando = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly exito = signal<string | null>(null);

  protected filtroEstado: EstadoEnvio | '' = '';
  protected filtroSucursal = '';
  protected soloAbiertos = true;
  protected repartidorElegido = '';
  protected observacion = '';

  /** Solo el ADMIN de la cadena puede filtrar por sucursal (mismo criterio que el backend). */
  protected readonly puedeElegirSucursal = computed(() =>
    this.auth.tienePermiso('sucursales.actualizar'),
  );
  protected readonly esRepartidor = computed(() => this.auth.usuario()?.cargo === 'REPARTIDOR');
  protected readonly puedeAsignar = computed(
    () => this.auth.tienePermiso('envios.actualizar') && !this.esRepartidor(),
  );

  ngOnInit(): void {
    this.cargar();
    if (this.puedeElegirSucursal()) {
      this.sucursalesService.listarSucursales().subscribe({
        next: (sucursales) => this.sucursales.set(sucursales),
      });
    }
  }

  protected cargar(): void {
    this.cargando.set(true);
    this.error.set(null);

    const sucursalId = this.filtroSucursal || null;
    this.enviosService
      .listar({
        estado: this.filtroEstado || null,
        sucursalId,
        soloAbiertos: this.soloAbiertos,
      })
      .subscribe({
        next: (envios) => {
          this.envios.set(envios);
          this.cargando.set(false);
        },
        error: (error: HttpErrorResponse) => {
          this.error.set(interpretarError(error, 'No se pudieron cargar los envíos.'));
          this.cargando.set(false);
        },
      });

    this.enviosService.resumen(sucursalId).subscribe({
      next: (resumen) => this.resumen.set(resumen),
      error: () => this.resumen.set(null),
    });

    if (this.puedeAsignar()) {
      this.enviosService.repartidores(sucursalId).subscribe({
        next: (repartidores) => this.repartidores.set(repartidores),
        error: () => this.repartidores.set([]),
      });
    }
  }

  protected abrir(envio: EnvioAdminOut): void {
    this.error.set(null);
    this.exito.set(null);
    this.repartidorElegido = envio.repartidor_id ?? '';
    this.observacion = '';
    this.enviosService.detalle(envio.id).subscribe({
      next: (detalle) => this.detalle.set(detalle),
      error: (error: HttpErrorResponse) => this.error.set(interpretarError(error)),
    });
  }

  protected cerrarDetalle(): void {
    this.detalle.set(null);
  }

  protected asignar(): void {
    const envio = this.detalle();
    if (!envio || !this.repartidorElegido) {
      this.error.set('Elegí un repartidor.');
      return;
    }

    this.trabajando.set(true);
    this.enviosService
      .asignar(envio.id, this.repartidorElegido, this.observacion.trim() || null)
      .subscribe({
        next: () => {
          this.trabajando.set(false);
          this.exito.set('Repartidor asignado.');
          this.observacion = '';
          this.refrescar(envio.id);
        },
        error: (error: HttpErrorResponse) => {
          this.trabajando.set(false);
          this.error.set(interpretarError(error, 'No se pudo asignar el repartidor.'));
        },
      });
  }

  protected cambiarEstado(estado: EstadoEnvio): void {
    const envio = this.detalle();
    if (!envio) return;

    if (estado === 'FALLIDO' && !this.observacion.trim()) {
      this.error.set('Un envío fallido necesita que anotes el motivo.');
      return;
    }

    this.trabajando.set(true);
    this.enviosService.cambiarEstado(envio.id, estado, this.observacion.trim() || null).subscribe({
      next: (actualizado) => {
        this.trabajando.set(false);
        this.exito.set(`Envío marcado como ${this.etiqueta(actualizado.estado).toLowerCase()}.`);
        this.observacion = '';
        this.refrescar(envio.id);
      },
      error: (error: HttpErrorResponse) => {
        this.trabajando.set(false);
        this.error.set(interpretarError(error, 'No se pudo cambiar el estado.'));
      },
    });
  }

  private refrescar(envioId: string): void {
    this.cargar();
    this.enviosService.detalle(envioId).subscribe({
      next: (detalle) => {
        this.detalle.set(detalle);
        this.repartidorElegido = detalle.repartidor_id ?? '';
      },
      error: () => this.detalle.set(null),
    });
  }

  protected siguientes(estado: EstadoEnvio): EstadoEnvio[] {
    return SIGUIENTES[estado];
  }

  protected etiqueta(estado: EstadoEnvio): string {
    switch (estado) {
      case 'PENDIENTE':
        return 'Pendiente';
      case 'ASIGNADO':
        return 'Asignado';
      case 'EN_RUTA':
        return 'En ruta';
      case 'ENTREGADO':
        return 'Entregado';
      case 'FALLIDO':
        return 'Fallido';
      case 'CANCELADO':
        return 'Cancelado';
      default:
        return estado;
    }
  }

  protected claseBadge(estado: EstadoEnvio): string {
    if (estado === 'ENTREGADO') return 'badge badge--ok';
    if (estado === 'FALLIDO' || estado === 'CANCELADO') return 'badge badge--alerta';
    if (estado === 'PENDIENTE') return 'badge badge--baja';
    return 'badge';
  }

  protected precio(monto: number): string {
    return `Bs ${monto.toFixed(2)}`;
  }
}
