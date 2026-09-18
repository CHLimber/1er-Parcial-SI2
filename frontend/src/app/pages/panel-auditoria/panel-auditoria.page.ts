import { DatePipe, JsonPipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule } from '@angular/forms';

import { AccionAuditoria, AuditoriaOut, FiltroAuditoria } from '../../core/auditoria/auditoria.models';
import { AuditoriaService } from '../../core/auditoria/auditoria.service';
import { interpretarError } from '../../shared/errores';
import { PanelShell } from '../../shared/panel/panel-shell';

const ETIQUETAS_ACCION: Record<AccionAuditoria, string> = {
  CREAR: 'Creación',
  ACTUALIZAR: 'Modificación',
  ELIMINAR: 'Baja',
  LOGIN: 'Inicio de sesión',
};

const TAMANIO_PAGINA = 20;

/** CU19 - Consultar Bitácora de Auditoría: solo lectura sobre la tabla `auditoria`. */
@Component({
  selector: 'app-panel-auditoria-page',
  standalone: true,
  imports: [DatePipe, JsonPipe, PanelShell, ReactiveFormsModule],
  templateUrl: './panel-auditoria.page.html',
  styleUrls: ['../../shared/panel/panel-comun.css', './panel-auditoria.page.css'],
})
export class PanelAuditoriaPage implements OnInit {
  private readonly servicio = inject(AuditoriaService);
  private readonly fb = inject(FormBuilder);

  protected readonly etiquetasAccion = ETIQUETAS_ACCION;

  protected readonly error = signal<string | null>(null);
  protected readonly cargando = signal(true);
  protected readonly items = signal<AuditoriaOut[]>([]);
  protected readonly total = signal(0);
  protected readonly pagina = signal(1);
  protected readonly entidades = signal<string[]>([]);
  protected readonly filaExpandida = signal<number | null>(null);

  protected readonly filtro = this.fb.nonNullable.group({
    entidad: '',
    accion: '',
    entidad_id: '',
    desde: '',
    hasta: '',
  });

  protected get totalPaginas(): number {
    return Math.max(1, Math.ceil(this.total() / TAMANIO_PAGINA));
  }

  ngOnInit(): void {
    this.servicio.entidades().subscribe({
      next: (valores) => this.entidades.set(valores),
      error: () => this.entidades.set([]),
    });
    this.cargar();
  }

  protected aplicarFiltro(): void {
    this.pagina.set(1);
    this.cargar();
  }

  protected irAPagina(pagina: number): void {
    if (pagina < 1 || pagina > this.totalPaginas) return;
    this.pagina.set(pagina);
    this.cargar();
  }

  protected alternarDetalle(id: number): void {
    this.filaExpandida.update((actual) => (actual === id ? null : id));
  }

  private filtroActual(): FiltroAuditoria {
    const crudo = this.filtro.getRawValue();
    return {
      entidad: crudo.entidad || undefined,
      accion: (crudo.accion || undefined) as AccionAuditoria | undefined,
      entidad_id: crudo.entidad_id.trim() || undefined,
      desde: crudo.desde || undefined,
      hasta: crudo.hasta || undefined,
    };
  }

  private cargar(): void {
    this.cargando.set(true);
    this.error.set(null);
    this.servicio.listar(this.filtroActual(), this.pagina(), TAMANIO_PAGINA).subscribe({
      next: (datos) => {
        this.items.set(datos.items);
        this.total.set(datos.total);
        this.cargando.set(false);
      },
      error: (e: HttpErrorResponse) => {
        this.error.set(interpretarError(e, 'No se pudo cargar la bitácora de auditoría.'));
        this.cargando.set(false);
      },
    });
  }
}
