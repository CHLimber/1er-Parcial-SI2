import { DatePipe } from '@angular/common';
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

/** Campos que nunca se muestran en claro, aunque el backend los llegue a mandar algun dia. */
const CAMPOS_SENSIBLES = /password|contrasenia|contraseña|hash|token|secret/i;

interface CampoValor {
  campo: string;
  valor: string;
}

interface FilaComparacion {
  campo: string;
  antes: string;
  despues: string;
  cambio: boolean;
}

/** CU19 - Consultar Bitácora de Auditoría: solo lectura sobre la tabla `auditoria`. */
@Component({
  selector: 'app-panel-auditoria-page',
  standalone: true,
  imports: [DatePipe, PanelShell, ReactiveFormsModule],
  providers: [DatePipe],
  templateUrl: './panel-auditoria.page.html',
  styleUrls: ['../../shared/panel/panel-comun.css', './panel-auditoria.page.css'],
})
export class PanelAuditoriaPage implements OnInit {
  private readonly servicio = inject(AuditoriaService);
  private readonly fb = inject(FormBuilder);
  private readonly datePipe = inject(DatePipe);

  protected readonly etiquetasAccion = ETIQUETAS_ACCION;

  protected readonly error = signal<string | null>(null);
  protected readonly cargando = signal(true);
  protected readonly items = signal<AuditoriaOut[]>([]);
  protected readonly total = signal(0);
  protected readonly pagina = signal(1);
  protected readonly entidades = signal<string[]>([]);
  protected readonly filaExpandida = signal<number | null>(null);
  protected readonly mostrarSinCambiosDe = signal<number | null>(null);

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
    this.mostrarSinCambiosDe.set(null);
  }

  protected alternarSinCambios(id: number): void {
    this.mostrarSinCambiosDe.update((actual) => (actual === id ? null : id));
  }

  /** CREAR/ELIMINAR: solo existe un lado (despues o antes) -- se lista campo por campo. */
  protected soloValores(datos: Record<string, unknown>): CampoValor[] {
    return Object.keys(datos).map((campo) => ({ campo, valor: this.formatearValor(campo, datos[campo]) }));
  }

  protected filasTotales(fila: AuditoriaOut): FilaComparacion[] {
    if (!fila.datos_antes || !fila.datos_despues) return [];
    const antes = fila.datos_antes;
    const despues = fila.datos_despues;
    const claves = new Set([...Object.keys(antes), ...Object.keys(despues)]);
    return Array.from(claves).map((campo) => ({
      campo,
      antes: this.formatearValor(campo, antes[campo]),
      despues: this.formatearValor(campo, despues[campo]),
      cambio: JSON.stringify(antes[campo]) !== JSON.stringify(despues[campo]),
    }));
  }

  protected filasCambiadas(fila: AuditoriaOut): FilaComparacion[] {
    return this.filasTotales(fila).filter((f) => f.cambio);
  }

  protected filasSinCambio(fila: AuditoriaOut): FilaComparacion[] {
    return this.filasTotales(fila).filter((f) => !f.cambio);
  }

  /** "precio_base" -> "Precio base": una etiqueta legible sin necesitar un diccionario por entidad. */
  protected etiquetaCampo(campo: string): string {
    const texto = campo.replace(/_/g, ' ').trim();
    return texto.charAt(0).toUpperCase() + texto.slice(1);
  }

  private formatearValor(campo: string, valor: unknown): string {
    if (valor !== null && valor !== undefined && valor !== '' && CAMPOS_SENSIBLES.test(campo)) {
      return '••••••••';
    }
    if (valor === null || valor === undefined || valor === '') return '—';
    if (typeof valor === 'boolean') return valor ? 'Sí' : 'No';
    if (typeof valor === 'number') return String(valor);
    if (typeof valor === 'string') {
      if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(valor)) {
        return this.datePipe.transform(valor, 'dd/MM/yyyy HH:mm') ?? valor;
      }
      if (/^\d{4}-\d{2}-\d{2}$/.test(valor)) {
        return this.datePipe.transform(valor, 'dd/MM/yyyy') ?? valor;
      }
      return valor;
    }
    if (Array.isArray(valor)) {
      return valor.length === 0 ? '—' : valor.map((v) => this.formatearValor(campo, v)).join(', ');
    }
    if (typeof valor === 'object') {
      return Object.entries(valor as Record<string, unknown>)
        .map(([k, v]) => `${this.etiquetaCampo(k)}: ${this.formatearValor(k, v)}`)
        .join(' · ');
    }
    return String(valor);
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
