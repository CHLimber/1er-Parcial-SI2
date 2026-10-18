import { DecimalPipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, ElementRef, OnDestroy, OnInit, ViewChild, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Chart, registerables } from 'chart.js';

import { DashboardAnalitico, MuestraSinteticos } from '../../core/analitica/analitica.models';
import { AnaliticaService } from '../../core/analitica/analitica.service';
import { AuthService } from '../../core/auth/auth.service';
import { SucursalOut } from '../../core/sucursales/sucursales.models';
import { SucursalesService } from '../../core/sucursales/sucursales.service';
import { interpretarError } from '../../shared/errores';
import { PanelShell } from '../../shared/panel/panel-shell';

Chart.register(...registerables);

const COLOR_INK = '#2e2530';
const COLOR_INK_SOFT = '#7a6b76';
const COLOR_GRID = '#ecd9d1';
const COLORES_TIPO: Record<string, string> = {
  verano: '#c1516b',
  invierno: '#2a78d6',
  atemporal: '#c9a15f',
  accesorio: '#1baf7a',
};

const NOMBRE_MODELO: Record<string, string> = {
  random_forest: 'Random Forest',
  regresion_lineal: 'Regresión lineal',
  ingenuo_semana_anterior: 'Ingenuo (semana anterior)',
};

/**
 * CU26 - Dashboard analítico (Módulo G, etapas 6 a 9). Los modelos se entrenan con datos
 * sintéticos y acá se aplican a las ventas reales de la empresa: pronóstico de demanda
 * (supervisado), segmentos de clientas (KMeans) y días atípicos (IsolationForest), con las
 * métricas de evaluación y los hallazgos en texto. Solo plan Profesional; el backend igual
 * responde 403 si el plan no lo incluye.
 */
@Component({
  selector: 'app-panel-analitica-page',
  standalone: true,
  imports: [PanelShell, FormsModule, DecimalPipe],
  templateUrl: './panel-analitica.page.html',
  styleUrls: [
    '../../shared/panel/panel-comun.css',
    '../panel-reportes/panel-reportes.page.css',
    './panel-analitica.page.css',
  ],
})
export class PanelAnaliticaPage implements OnInit, OnDestroy {
  private readonly servicio = inject(AnaliticaService);
  private readonly sucursalesService = inject(SucursalesService);
  protected readonly auth = inject(AuthService);

  @ViewChild('graficoPronostico') private refPronostico?: ElementRef<HTMLCanvasElement>;
  @ViewChild('graficoImportancias') private refImportancias?: ElementRef<HTMLCanvasElement>;
  private chartPronostico?: Chart;
  private chartImportancias?: Chart;

  protected readonly incluidoEnPlan = this.auth.tieneFuncion('analitica_ml');
  protected readonly eligeSucursal = this.auth.tienePermiso('sucursales.actualizar');
  protected readonly puedeEntrenar = this.auth.tienePermiso('analitica.actualizar');
  protected readonly nombreModelo = NOMBRE_MODELO;

  protected readonly sucursales = signal<SucursalOut[]>([]);
  protected sucursalId = '';
  protected horizonte = 14;
  protected semilla = 42;

  protected readonly datos = signal<DashboardAnalitico | null>(null);
  protected readonly cargando = signal(false);
  protected readonly entrenando = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly aviso = signal<string | null>(null);
  protected readonly muestra = signal<MuestraSinteticos | null>(null);
  protected tipoMuestra: 'demanda' | 'clientes' = 'demanda';

  ngOnInit(): void {
    if (!this.incluidoEnPlan) return;
    if (this.eligeSucursal) {
      this.sucursalesService.listarSucursales().subscribe({ next: (s) => this.sucursales.set(s) });
    }
    this.cargar();
  }

  ngOnDestroy(): void {
    this.chartPronostico?.destroy();
    this.chartImportancias?.destroy();
  }

  protected cargar(): void {
    this.cargando.set(true);
    this.error.set(null);
    this.servicio.dashboard(this.sucursalId || null, this.horizonte).subscribe({
      next: (datos) => {
        this.datos.set(datos);
        this.cargando.set(false);
        // los <canvas> aparecen recien cuando datos() tiene valor: se dibuja en el tick siguiente
        setTimeout(() => this.dibujar(datos));
      },
      error: (e: HttpErrorResponse) => {
        this.cargando.set(false);
        this.error.set(interpretarError(e, 'No se pudo cargar el dashboard analítico.'));
      },
    });
  }

  protected reentrenar(): void {
    this.entrenando.set(true);
    this.aviso.set(null);
    this.error.set(null);
    this.servicio.entrenar(this.semilla).subscribe({
      next: (modelo) => {
        this.entrenando.set(false);
        this.aviso.set(
          `Modelos reentrenados con la semilla ${modelo.semilla}: R² ${modelo.demanda.metricas.random_forest.r2}` +
            ` (Random Forest), ${modelo.clientes.k} segmentos con silueta ${modelo.clientes.silueta}.`,
        );
        this.cargar();
      },
      error: (e: HttpErrorResponse) => {
        this.entrenando.set(false);
        this.error.set(interpretarError(e, 'No se pudieron reentrenar los modelos.'));
      },
    });
  }

  protected verMuestra(): void {
    this.servicio.muestra(this.tipoMuestra).subscribe({
      next: (m) => this.muestra.set(m),
      error: (e: HttpErrorResponse) => this.error.set(interpretarError(e, 'No se pudo leer la muestra.')),
    });
  }

  protected descargarCsv(): void {
    this.servicio.csv(this.tipoMuestra).subscribe({
      next: (blob) => {
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `sinteticos_${this.tipoMuestra}.csv`;
        a.click();
        URL.revokeObjectURL(url);
      },
      error: (e: HttpErrorResponse) => this.error.set(interpretarError(e, 'No se pudo descargar el CSV.')),
    });
  }

  protected metricas(d: DashboardAnalitico) {
    return Object.entries(d.modelo.demanda.metricas).map(([clave, m]) => ({ clave, ...m }));
  }

  protected nombresEjemplo(s: { ejemplos: { nombre: string }[] }): string {
    return s.ejemplos.map((e) => e.nombre).join(', ');
  }

  protected variacion(v: number | null): string {
    if (v === null) return '—';
    return `${v > 0 ? '+' : ''}${v.toFixed(1)}%`;
  }

  private dibujar(d: DashboardAnalitico): void {
    if (this.refPronostico) {
      this.chartPronostico?.destroy();
      this.chartPronostico = new Chart(this.refPronostico.nativeElement, {
        type: 'bar',
        data: {
          labels: d.pronostico_diario.map((p) => p.dia.slice(5)),
          datasets: (['verano', 'invierno', 'atemporal', 'accesorio'] as const).map((t) => ({
            label: t[0].toUpperCase() + t.slice(1),
            data: d.pronostico_diario.map((p) => p[t]),
            backgroundColor: COLORES_TIPO[t],
            stack: 'tipo',
          })),
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: { legend: { labels: { color: COLOR_INK } } },
          scales: {
            x: { stacked: true, grid: { color: COLOR_GRID }, ticks: { color: COLOR_INK_SOFT } },
            y: { stacked: true, grid: { color: COLOR_GRID }, ticks: { color: COLOR_INK_SOFT }, beginAtZero: true,
              title: { display: true, text: 'Unidades', color: COLOR_INK_SOFT } },
          },
        },
      });
    }
    if (this.refImportancias) {
      const top = d.modelo.demanda.importancias.slice(0, 8);
      this.chartImportancias?.destroy();
      this.chartImportancias = new Chart(this.refImportancias.nativeElement, {
        type: 'bar',
        data: {
          labels: top.map((i) => i.variable),
          datasets: [{ label: 'Importancia', data: top.map((i) => i.importancia), backgroundColor: '#c1516b', borderRadius: 4 }],
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          indexAxis: 'y',
          plugins: { legend: { display: false } },
          scales: {
            x: { grid: { color: COLOR_GRID }, ticks: { color: COLOR_INK_SOFT }, beginAtZero: true },
            y: { grid: { display: false }, ticks: { color: COLOR_INK } },
          },
        },
      });
    }
  }
}
