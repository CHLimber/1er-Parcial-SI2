import { DecimalPipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import {
  AfterViewInit,
  Component,
  ElementRef,
  OnDestroy,
  OnInit,
  ViewChild,
  inject,
  signal,
} from '@angular/core';
import { FormBuilder, ReactiveFormsModule } from '@angular/forms';
import { Chart, ChartOptions, registerables } from 'chart.js';

import { AuthService } from '../../core/auth/auth.service';
import {
  CanalVenta,
  FiltroReportes,
  IndicadoresOut,
  ProductoRankingOut,
  ReservaEstadoOut,
  StockSucursalOut,
  VentaDiariaOut,
  VentaPorSucursalOut,
} from '../../core/reportes/reportes.models';
import { ReportesService } from '../../core/reportes/reportes.service';
import { SucursalOut } from '../../core/sucursales/sucursales.models';
import { SucursalesService } from '../../core/sucursales/sucursales.service';
import { interpretarError } from '../../shared/errores';
import { PanelShell } from '../../shared/panel/panel-shell';

Chart.register(...registerables);

// Paleta de marca (styles.css) para series unicas; paleta categorica validada
// (dataviz skill: CVD-safe, no forma parte de la identidad visual) para el
// unico grafico con series de verdad (ventas diarias por canal).
const COLOR_FLAME = '#c1516b';
const COLOR_GOLD = '#c9a15f';
const COLOR_INK = '#2e2530';
const COLOR_INK_SOFT = '#7a6b76';
const COLOR_GRID = '#ecd9d1';

const ORDEN_CANALES: CanalVenta[] = ['WEB', 'MOVIL', 'POS'];
const COLORES_CANAL: Record<CanalVenta, string> = { WEB: '#2a78d6', MOVIL: '#eb6834', POS: '#1baf7a' };
const ETIQUETAS_CANAL: Record<CanalVenta, string> = { WEB: 'Web', MOVIL: 'Móvil', POS: 'Caja (POS)' };

const ETIQUETAS_ESTADO_RESERVA: Record<string, string> = {
  PENDIENTE: 'Pendiente',
  CONFIRMADA: 'Confirmada',
  PREPARADA: 'Preparada',
  CLIENTE_PRESENTE: 'Cliente presente',
  ATENDIDA: 'Atendida',
  CONVERTIDA: 'Convertida',
  CANCELADA: 'Cancelada',
  EXPIRADA: 'Expirada',
};

function hoyIso(): string {
  return new Date().toISOString().slice(0, 10);
}

function haceDiasIso(dias: number): string {
  const fecha = new Date();
  fecha.setDate(fecha.getDate() - dias);
  return fecha.toISOString().slice(0, 10);
}

function opcionesBase(mostrarLeyenda: boolean, indiceHorizontal = false): ChartOptions {
  return {
    responsive: true,
    maintainAspectRatio: false,
    indexAxis: indiceHorizontal ? 'y' : 'x',
    plugins: {
      legend: { display: mostrarLeyenda, labels: { color: COLOR_INK } },
      tooltip: { backgroundColor: COLOR_INK, titleColor: '#fffaf6', bodyColor: '#fffaf6' },
    },
    scales: {
      x: { grid: { color: COLOR_GRID }, ticks: { color: COLOR_INK_SOFT }, beginAtZero: !indiceHorizontal },
      y: { grid: { color: COLOR_GRID }, ticks: { color: COLOR_INK_SOFT }, beginAtZero: indiceHorizontal },
    },
  };
}

/** CU15 - Consultar Reportes e Indicadores: dinamicos (con filtro) y estaticos (foto actual). */
@Component({
  selector: 'app-panel-reportes-page',
  standalone: true,
  imports: [DecimalPipe, PanelShell, ReactiveFormsModule],
  templateUrl: './panel-reportes.page.html',
  styleUrls: ['../../shared/panel/panel-comun.css', './panel-reportes.page.css'],
})
export class PanelReportesPage implements OnInit, AfterViewInit, OnDestroy {
  private readonly servicio = inject(ReportesService);
  private readonly sucursalesServicio = inject(SucursalesService);
  private readonly fb = inject(FormBuilder);
  protected readonly auth = inject(AuthService);

  protected readonly puedeElegirSucursal = this.auth.tienePermiso('sucursales.actualizar');
  protected readonly sucursales = signal<SucursalOut[]>([]);

  protected readonly error = signal<string | null>(null);
  protected readonly cargandoIndicadores = signal(true);
  protected readonly indicadores = signal<IndicadoresOut | null>(null);

  protected readonly stock = signal<StockSucursalOut[]>([]);

  protected readonly sinVentasDiarias = signal(false);
  protected readonly sinVentasSucursal = signal(false);
  protected readonly sinTopProductos = signal(false);
  protected readonly sinStock = signal(false);
  protected readonly sinReservas = signal(false);

  protected readonly filtro = this.fb.nonNullable.group({
    desde: haceDiasIso(30),
    hasta: hoyIso(),
    sucursal_id: '',
    canal: '',
  });

  @ViewChild('canvasVentasDiarias') private refVentasDiarias!: ElementRef<HTMLCanvasElement>;
  @ViewChild('canvasVentasSucursal') private refVentasSucursal!: ElementRef<HTMLCanvasElement>;
  @ViewChild('canvasTopProductos') private refTopProductos!: ElementRef<HTMLCanvasElement>;
  @ViewChild('canvasStock') private refStock!: ElementRef<HTMLCanvasElement>;
  @ViewChild('canvasReservas') private refReservas!: ElementRef<HTMLCanvasElement>;

  private chartVentasDiarias?: Chart;
  private chartVentasSucursal?: Chart;
  private chartTopProductos?: Chart;
  private chartStock?: Chart;
  private chartReservas?: Chart;

  private vistaLista = false;

  ngOnInit(): void {
    this.sucursalesServicio.listarSucursales().subscribe({
      next: (sucursales) => this.sucursales.set(sucursales),
      error: () => this.sucursales.set([]),
    });
  }

  ngAfterViewInit(): void {
    this.vistaLista = true;
    this.cargarTodo();
  }

  ngOnDestroy(): void {
    this.chartVentasDiarias?.destroy();
    this.chartVentasSucursal?.destroy();
    this.chartTopProductos?.destroy();
    this.chartStock?.destroy();
    this.chartReservas?.destroy();
  }

  protected aplicarFiltro(): void {
    this.cargarTodo();
  }

  private filtroActual(): FiltroReportes {
    const crudo = this.filtro.getRawValue();
    return {
      desde: crudo.desde || undefined,
      hasta: crudo.hasta || undefined,
      sucursal_id: this.puedeElegirSucursal ? crudo.sucursal_id || undefined : undefined,
    };
  }

  private cargarTodo(): void {
    if (!this.vistaLista) return;
    this.error.set(null);
    this.cargarIndicadores();
    this.cargarVentasDiarias();
    this.cargarVentasPorSucursal();
    this.cargarTopProductos();
    this.cargarStock();
    this.cargarReservas();
  }

  private manejarError(e: HttpErrorResponse, porDefecto: string): void {
    this.error.set(interpretarError(e, porDefecto));
  }

  // --- indicadores (dinamico) ---

  private cargarIndicadores(): void {
    this.cargandoIndicadores.set(true);
    this.servicio.indicadores(this.filtroActual()).subscribe({
      next: (datos) => {
        this.indicadores.set(datos);
        this.cargandoIndicadores.set(false);
      },
      error: (e: HttpErrorResponse) => {
        this.manejarError(e, 'No se pudieron cargar los indicadores.');
        this.cargandoIndicadores.set(false);
      },
    });
  }

  // --- ventas diarias (dinamico) ---

  private cargarVentasDiarias(): void {
    const canal = (this.filtro.controls.canal.value || null) as CanalVenta | null;
    this.servicio.ventasDiarias(this.filtroActual(), canal).subscribe({
      next: (filas) => this.dibujarVentasDiarias(filas),
      error: (e: HttpErrorResponse) => this.manejarError(e, 'No se pudieron cargar las ventas diarias.'),
    });
  }

  private dibujarVentasDiarias(filas: VentaDiariaOut[]): void {
    this.sinVentasDiarias.set(filas.length === 0);
    const dias = [...new Set(filas.map((f) => f.dia))].sort();
    const canalesPresentes = ORDEN_CANALES.filter((canal) => filas.some((f) => f.canal === canal));
    const canales = canalesPresentes.length ? canalesPresentes : ORDEN_CANALES;

    const datasets = canales.map((canal) => ({
      label: ETIQUETAS_CANAL[canal],
      data: dias.map((dia) => filas.find((f) => f.dia === dia && f.canal === canal)?.monto_total ?? 0),
      borderColor: COLORES_CANAL[canal],
      backgroundColor: COLORES_CANAL[canal],
      borderWidth: 2,
      tension: 0.25,
      pointRadius: 3,
    }));

    this.chartVentasDiarias?.destroy();
    this.chartVentasDiarias = new Chart(this.refVentasDiarias.nativeElement, {
      type: 'line',
      data: { labels: dias, datasets },
      options: opcionesBase(datasets.length > 1),
    });
  }

  // --- ventas por sucursal (dinamico) ---

  private cargarVentasPorSucursal(): void {
    this.servicio.ventasPorSucursal(this.filtroActual()).subscribe({
      next: (filas) => this.dibujarVentasPorSucursal(filas),
      error: (e: HttpErrorResponse) => this.manejarError(e, 'No se pudieron cargar las ventas por sucursal.'),
    });
  }

  private dibujarVentasPorSucursal(filas: VentaPorSucursalOut[]): void {
    this.sinVentasSucursal.set(filas.length === 0);
    this.chartVentasSucursal?.destroy();
    this.chartVentasSucursal = new Chart(this.refVentasSucursal.nativeElement, {
      type: 'bar',
      data: {
        labels: filas.map((f) => f.sucursal),
        datasets: [
          {
            label: 'Monto vendido (Bs)',
            data: filas.map((f) => f.monto_total),
            backgroundColor: COLOR_FLAME,
            borderRadius: 4,
            maxBarThickness: 48,
          },
        ],
      },
      options: opcionesBase(false),
    });
  }

  // --- top productos (dinamico) ---

  private cargarTopProductos(): void {
    this.servicio.topProductos(this.filtroActual(), 10).subscribe({
      next: (filas) => this.dibujarTopProductos(filas),
      error: (e: HttpErrorResponse) => this.manejarError(e, 'No se pudo cargar el ranking de productos.'),
    });
  }

  private dibujarTopProductos(filas: ProductoRankingOut[]): void {
    this.sinTopProductos.set(filas.length === 0);
    this.chartTopProductos?.destroy();
    this.chartTopProductos = new Chart(this.refTopProductos.nativeElement, {
      type: 'bar',
      data: {
        labels: filas.map((f) => f.producto),
        datasets: [
          {
            label: 'Unidades vendidas',
            data: filas.map((f) => f.unidades_vendidas),
            backgroundColor: COLOR_FLAME,
            borderRadius: 4,
            maxBarThickness: 28,
          },
        ],
      },
      options: opcionesBase(false, true),
    });
  }

  // --- stock por sucursal (estatico) ---

  private cargarStock(): void {
    this.servicio.stockPorSucursal(this.filtroActual().sucursal_id).subscribe({
      next: (filas) => this.dibujarStock(filas),
      error: (e: HttpErrorResponse) => this.manejarError(e, 'No se pudo cargar el stock por sucursal.'),
    });
  }

  private dibujarStock(filas: StockSucursalOut[]): void {
    this.sinStock.set(filas.length === 0);
    this.stock.set(filas);
    this.chartStock?.destroy();
    this.chartStock = new Chart(this.refStock.nativeElement, {
      type: 'bar',
      data: {
        labels: filas.map((f) => f.sucursal),
        datasets: [
          {
            label: 'Unidades disponibles',
            data: filas.map((f) => f.total_disponible),
            backgroundColor: COLOR_FLAME,
            borderRadius: 4,
            maxBarThickness: 48,
          },
        ],
      },
      options: opcionesBase(false),
    });
  }

  // --- reservas por estado (estatico) ---

  private cargarReservas(): void {
    this.servicio.reservasPorEstado(this.filtroActual().sucursal_id).subscribe({
      next: (filas) => this.dibujarReservas(filas),
      error: (e: HttpErrorResponse) => this.manejarError(e, 'No se pudieron cargar las reservas por estado.'),
    });
  }

  private dibujarReservas(filas: ReservaEstadoOut[]): void {
    this.sinReservas.set(filas.length === 0);
    this.chartReservas?.destroy();
    this.chartReservas = new Chart(this.refReservas.nativeElement, {
      type: 'bar',
      data: {
        labels: filas.map((f) => ETIQUETAS_ESTADO_RESERVA[f.estado] ?? f.estado),
        datasets: [
          {
            label: 'Reservas',
            data: filas.map((f) => f.cantidad),
            backgroundColor: COLOR_GOLD,
            borderRadius: 4,
            maxBarThickness: 48,
          },
        ],
      },
      options: opcionesBase(false),
    });
  }
}
