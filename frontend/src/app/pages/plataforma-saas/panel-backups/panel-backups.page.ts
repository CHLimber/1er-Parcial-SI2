import { NgTemplateOutlet } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnDestroy, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { AuthService } from '../../../core/acceso-y-organizacion/auth/auth.service';
import { BackupOut, ProgramacionOut } from '../../../core/plataforma-saas/backups/backups.models';
import { BackupsService } from '../../../core/plataforma-saas/backups/backups.service';
import { EmpresaOut } from '../../../core/plataforma-saas/saas/saas.models';
import { SaasService } from '../../../core/plataforma-saas/saas/saas.service';
import { interpretarError } from '../../../shared/errores';
import { PanelShell } from '../../../shared/panel/panel-shell';

const REFRESCO_MS = 3000;

/**
 * Copias de seguridad (CU30). Dos caras de la misma pantalla:
 *  - la PLATAFORMA (SUPERADMIN) ve la copia automatica general (cuando corre, cual fue la ultima,
 *    su historial), puede lanzar otra a mano y tambien respaldar la empresa que elija;
 *  - el ADMIN de una empresa ve y lanza las copias manuales de la suya.
 * Mientras alguna copia esta EN_CURSO la pantalla se refresca sola cada 3 segundos.
 */
@Component({
  selector: 'app-panel-backups-page',
  standalone: true,
  imports: [PanelShell, FormsModule, NgTemplateOutlet],
  templateUrl: './panel-backups.page.html',
  styleUrls: ['../../../shared/panel/panel-comun.css', './panel-backups.page.css'],
})
export class PanelBackupsPage implements OnInit, OnDestroy {
  private readonly servicio = inject(BackupsService);
  private readonly saas = inject(SaasService);
  private readonly auth = inject(AuthService);

  protected readonly esPlataforma = this.auth.esPlataforma();
  protected readonly puedeCrear = this.auth.tienePermiso('backups.crear');
  protected readonly puedeEliminar = this.auth.tienePermiso('backups.eliminar');

  protected solapa: 'automatica' | 'empresas' = 'automatica';
  protected empresaElegida = '';

  protected readonly programacion = signal<ProgramacionOut | null>(null);
  protected readonly generales = signal<BackupOut[]>([]);
  protected readonly deEmpresas = signal<BackupOut[]>([]);
  protected readonly empresas = signal<EmpresaOut[]>([]);
  protected readonly cargando = signal(true);
  protected readonly ocupado = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly aviso = signal<string | null>(null);

  private temporizador: ReturnType<typeof setTimeout> | null = null;

  ngOnInit(): void {
    if (this.esPlataforma) {
      this.saas.empresas().subscribe({ next: (e) => this.empresas.set(e) });
    }
    this.cargar();
  }

  ngOnDestroy(): void {
    if (this.temporizador) clearTimeout(this.temporizador);
  }

  protected cargar(): void {
    let pendientes = this.esPlataforma ? 3 : 1;
    const listo = () => {
      if (--pendientes > 0) return;
      this.cargando.set(false);
      this.programarRefresco();
    };
    const fallo = (e: HttpErrorResponse) => {
      this.error.set(interpretarError(e, 'No se pudieron cargar las copias de seguridad.'));
      listo();
    };
    if (this.esPlataforma) {
      this.servicio.programacion().subscribe({
        next: (p) => {
          this.programacion.set(p);
          listo();
        },
        error: fallo,
      });
      this.servicio.generales().subscribe({
        next: (b) => {
          this.generales.set(b);
          listo();
        },
        error: fallo,
      });
    }
    this.servicio.deEmpresa(this.esPlataforma ? this.empresaElegida || null : null).subscribe({
      next: (b) => {
        this.deEmpresas.set(b);
        listo();
      },
      error: fallo,
    });
  }

  private programarRefresco(): void {
    if (this.temporizador) clearTimeout(this.temporizador);
    const hayEnCurso = [...this.generales(), ...this.deEmpresas()].some((b) => b.estado === 'EN_CURSO');
    if (hayEnCurso) this.temporizador = setTimeout(() => this.cargar(), REFRESCO_MS);
  }

  protected crearGeneral(): void {
    this.lanzar(this.servicio.crearGeneral(), 'Copia general iniciada: se está generando en el servidor.');
  }

  protected crearDeEmpresa(): void {
    const empresa = this.empresas().find((e) => e.id === this.empresaElegida);
    if (this.esPlataforma && !empresa) {
      this.error.set('Elegí la empresa que querés respaldar.');
      return;
    }
    this.lanzar(
      this.servicio.crearDeEmpresa(this.esPlataforma ? this.empresaElegida : null),
      `Copia de ${empresa?.nombre ?? 'tu empresa'} iniciada: se está generando en el servidor.`,
    );
  }

  private lanzar(llamada: ReturnType<BackupsService['crearGeneral']>, mensaje: string): void {
    this.ocupado.set(true);
    this.error.set(null);
    this.aviso.set(null);
    llamada.subscribe({
      next: () => {
        this.ocupado.set(false);
        this.aviso.set(mensaje);
        this.cargar();
      },
      error: (e: HttpErrorResponse) => {
        this.ocupado.set(false);
        this.error.set(interpretarError(e));
      },
    });
  }

  protected descargar(copia: BackupOut): void {
    this.error.set(null);
    this.servicio.descargar(copia.id).subscribe({
      next: (blob) => {
        const url = URL.createObjectURL(blob);
        const enlace = document.createElement('a');
        enlace.href = url;
        enlace.download = this.nombreArchivo(copia);
        enlace.click();
        URL.revokeObjectURL(url);
      },
      // con responseType blob el detalle del error llega dentro de un Blob
      error: async (e: HttpErrorResponse) => {
        let detalle: string | null = null;
        if (e.error instanceof Blob) {
          try {
            detalle = JSON.parse(await e.error.text()).detail ?? null;
          } catch {
            detalle = null;
          }
        }
        this.error.set(detalle ?? interpretarError(e, 'No se pudo descargar la copia.'));
      },
    });
  }

  protected eliminar(copia: BackupOut): void {
    if (!confirm('¿Eliminar esta copia de seguridad? El archivo se borra del servidor y no se puede recuperar.')) return;
    this.error.set(null);
    this.servicio.eliminar(copia.id).subscribe({
      next: () => {
        this.aviso.set('Copia eliminada.');
        this.cargar();
      },
      error: (e: HttpErrorResponse) => this.error.set(interpretarError(e)),
    });
  }

  /** Mismo criterio que el backend: slug de la empresa (o "plataforma") y fecha en hora de Bolivia. */
  private nombreArchivo(copia: BackupOut): string {
    const partes = Object.fromEntries(
      new Intl.DateTimeFormat('en-GB', {
        timeZone: 'America/La_Paz',
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
        hourCycle: 'h23',
      })
        .formatToParts(new Date(copia.iniciado_en))
        .map((p) => [p.type, p.value]),
    );
    const alcance = copia.empresa_id
      ? (this.empresas().find((e) => e.id === copia.empresa_id)?.slug ?? 'empresa')
      : 'plataforma';
    return `fashionstore-${alcance}-${partes['year']}${partes['month']}${partes['day']}-${partes['hour']}${partes['minute']}${partes['second']}.zip`;
  }

  protected cambiarFiltroEmpresa(): void {
    this.cargar();
  }

  protected fechaHora(valor: string | null): string {
    return valor ? new Date(valor).toLocaleString('es-BO', { dateStyle: 'medium', timeStyle: 'short' }) : '—';
  }

  protected tamano(bytes: number | null): string {
    if (bytes === null) return '—';
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }

  protected duracion(segundos: number | null): string {
    if (segundos === null) return '—';
    if (segundos < 1) return '<1 s';
    if (segundos < 60) return `${Math.round(segundos)} s`;
    return `${Math.floor(segundos / 60)} min ${Math.round(segundos % 60)} s`;
  }

  protected etiquetaEstado(estado: BackupOut['estado']): string {
    return { EN_CURSO: 'En curso', COMPLETADO: 'Completada', FALLIDO: 'Fallida' }[estado];
  }
}
