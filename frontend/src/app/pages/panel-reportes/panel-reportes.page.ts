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
import { CategoriaOut } from '../../core/catalogo/catalogo.models';
import { CatalogoService } from '../../core/catalogo/catalogo.service';
import {
  CajaOcupacionOut,
  CanalVenta,
  ClienteRankingOut,
  EnvioEstadoOut,
  FiltroReportes,
  IndicadoresOut,
  ModoEntrega,
  ProductoRankingOut,
  ProductoSinMovimientoOut,
  RecepcionPendienteProveedorOut,
  ReservaEstadoOut,
  StockSucursalOut,
  VendedorOut,
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

const ETIQUETAS_ESTADO_RESERVA: Record<string, string | undefined> = {
  PENDIENTE: 'Pendiente',
  CONFIRMADA: 'Confirmada',
  PREPARADA: 'Preparada',
  CLIENTE_PRESENTE: 'Cliente presente',
  ATENDIDA: 'Atendida',
  CONVERTIDA: 'Convertida',
  CANCELADA: 'Cancelada',
  EXPIRADA: 'Expirada',
};

const ETIQUETAS_ESTADO_ENVIO: Record<string, string | undefined> = {
  PENDIENTE: 'Pendiente',
  ASIGNADO: 'Asignado',
  EN_RUTA: 'En ruta',
  ENTREGADO: 'Entregado',
  FALLIDO: 'Fallido',
  CANCELADO: 'Cancelado',
};

type VistaReportes = 'graficas' | 'estaticos' | 'dinamicos' | 'ia';

type TipoEstatico = 'stock' | 'reservas' | 'envios' | 'ocupacion' | 'clientes' | 'sinMovimiento' | 'recepciones';

const ETIQUETAS_TIPO_ESTATICO: Record<TipoEstatico, string> = {
  stock: 'Stock disponible por sucursal',
  reservas: 'Reservas por estado',
  envios: 'Envíos por estado',
  ocupacion: 'Ocupación de cajas',
  clientes: 'Top clientes',
  sinMovimiento: 'Productos sin movimiento',
  recepciones: 'Recepciones pendientes por proveedor',
};

type TipoDinamico = 'indicadores' | 'ventasDiarias' | 'ventasPorSucursal' | 'topProductos';

const ETIQUETAS_TIPO_DINAMICO: Record<TipoDinamico, string> = {
  indicadores: 'Indicadores del período',
  ventasDiarias: 'Ventas diarias',
  ventasPorSucursal: 'Ventas por sucursal',
  topProductos: 'Top 10 productos más vendidos',
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

/**
 * CU15 - Consultar Reportes e Indicadores: submenu con 4 vistas, cada una con su propio filtro.
 *
 * "Graficas" es el tablero original (KPIs + Chart.js): solo filtra por desde/hasta/sucursal (el
 * canal de "Ventas diarias" sigue siendo un selector aparte, embebido en esa seccion, como ya
 * estaba). No cambia de comportamiento.
 *
 * "Reporte Estaticos" y "Reporte Dinamicos" no muestran todo junto: el usuario elige un "tipo de
 * consulta" (que endpoint mirar) y aprieta Consultar. Estaticos solo permite elegir sucursal (los
 * 7 reportes de foto actual no aceptan mas filtros en el backend). Dinamicos expone todos los
 * filtros que el backend acepta (fecha, sucursal, categoria, vendedor, canal, entrega): antes esos
 * filtros vivian en una barra compartida que le pegaba a los 4 endpoints dinamicos a la vez, lo
 * cual era redundante -- ahora se arma UNA consulta a la vez con el filtro completo.
 *
 * La seccion "Graficas" se oculta con `[hidden]` (no `@if`): si sus <canvas> salieran del DOM los
 * `@ViewChild` quedarian apuntando a elementos destruidos la proxima vez que llega una respuesta
 * HTTP con esa vista oculta, y Chart.js fallaria contra un nativeElement inexistente. Estaticos,
 * Dinamicos e IA no tienen canvas, asi que usan `@if` sin problema.
 */
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
  private readonly catalogoServicio = inject(CatalogoService);
  private readonly fb = inject(FormBuilder);
  protected readonly auth = inject(AuthService);

  protected readonly puedeElegirSucursal = this.auth.tienePermiso('sucursales.actualizar');
  protected readonly sucursales = signal<SucursalOut[]>([]);
  protected readonly categorias = signal<CategoriaOut[]>([]);
  protected readonly vendedores = signal<VendedorOut[]>([]);

  protected readonly vista = signal<VistaReportes>('graficas');
  protected readonly error = signal<string | null>(null);

  protected readonly ETIQUETAS_ESTADO_RESERVA = ETIQUETAS_ESTADO_RESERVA;
  protected readonly ETIQUETAS_ESTADO_ENVIO = ETIQUETAS_ESTADO_ENVIO;
  protected readonly ETIQUETAS_TIPO_ESTATICO = ETIQUETAS_TIPO_ESTATICO;
  protected readonly ETIQUETAS_TIPO_DINAMICO = ETIQUETAS_TIPO_DINAMICO;

  // --- Graficas: solo desde/hasta/sucursal (canal sigue embebido en "Ventas diarias") ---

  protected readonly filtro = this.fb.nonNullable.group({
    desde: haceDiasIso(30),
    hasta: hoyIso(),
    sucursal_id: '',
    canal: '',
  });

  protected readonly cargandoIndicadores = signal(true);
  protected readonly indicadores = signal<IndicadoresOut | null>(null);
  protected readonly stock = signal<StockSucursalOut[]>([]);
  protected readonly reservas = signal<ReservaEstadoOut[]>([]);
  protected readonly envios = signal<EnvioEstadoOut[]>([]);
  protected readonly sinMovimiento = signal<ProductoSinMovimientoOut[]>([]);
  protected readonly topClientes = signal<ClienteRankingOut[]>([]);
  protected readonly ocupacionCajas = signal<CajaOcupacionOut[]>([]);
  protected readonly recepcionesPendientes = signal<RecepcionPendienteProveedorOut[]>([]);

  protected readonly sinVentasDiarias = signal(false);
  protected readonly sinVentasSucursal = signal(false);
  protected readonly sinTopProductos = signal(false);
  protected readonly sinStock = signal(false);
  protected readonly sinReservas = signal(false);
  protected readonly sinEnvios = signal(false);
  protected readonly sinSinMovimiento = signal(false);
  protected readonly sinTopClientes = signal(false);
  protected readonly sinOcupacionCajas = signal(false);
  protected readonly sinRecepcionesPendientes = signal(false);

  @ViewChild('canvasVentasDiarias') private refVentasDiarias!: ElementRef<HTMLCanvasElement>;
  @ViewChild('canvasVentasSucursal') private refVentasSucursal!: ElementRef<HTMLCanvasElement>;
  @ViewChild('canvasTopProductos') private refTopProductos!: ElementRef<HTMLCanvasElement>;
  @ViewChild('canvasStock') private refStock!: ElementRef<HTMLCanvasElement>;
  @ViewChild('canvasReservas') private refReservas!: ElementRef<HTMLCanvasElement>;
  @ViewChild('canvasEnvios') private refEnvios!: ElementRef<HTMLCanvasElement>;
  @ViewChild('canvasOcupacionCajas') private refOcupacionCajas!: ElementRef<HTMLCanvasElement>;

  private chartVentasDiarias?: Chart;
  private chartVentasSucursal?: Chart;
  private chartTopProductos?: Chart;
  private chartStock?: Chart;
  private chartReservas?: Chart;
  private chartEnvios?: Chart;
  private chartOcupacionCajas?: Chart;

  private vistaLista = false;

  // --- Reporte Estaticos: tipo de consulta + sucursal ---

  protected readonly filtroEstatico = this.fb.nonNullable.group({
    tipo: 'stock' as TipoEstatico,
    sucursal_id: '',
  });

  protected readonly estaticoCargando = signal(false);
  protected readonly estaticoTipoActivo = signal<TipoEstatico | null>(null);
  protected readonly estSinResultados = signal(false);
  protected readonly estStock = signal<StockSucursalOut[]>([]);
  protected readonly estReservas = signal<ReservaEstadoOut[]>([]);
  protected readonly estEnvios = signal<EnvioEstadoOut[]>([]);
  protected readonly estOcupacionCajas = signal<CajaOcupacionOut[]>([]);
  protected readonly estTopClientes = signal<ClienteRankingOut[]>([]);
  protected readonly estSinMovimiento = signal<ProductoSinMovimientoOut[]>([]);
  protected readonly estRecepcionesPendientes = signal<RecepcionPendienteProveedorOut[]>([]);

  // --- Reporte Dinamicos: tipo de consulta + todos los filtros ---

  protected readonly filtroDinamico = this.fb.nonNullable.group({
    tipo: 'indicadores' as TipoDinamico,
    desde: haceDiasIso(30),
    hasta: hoyIso(),
    sucursal_id: '',
    categoria_id: '',
    vendedor_id: '',
    canal: '',
    entrega: '',
  });

  protected readonly dinCargando = signal(false);
  protected readonly dinTipoActivo = signal<TipoDinamico | null>(null);
  protected readonly dinSinResultados = signal(false);
  protected readonly dinIndicadores = signal<IndicadoresOut | null>(null);
  protected readonly dinVentasDiarias = signal<VentaDiariaOut[]>([]);
  protected readonly dinVentasPorSucursal = signal<VentaPorSucursalOut[]>([]);
  protected readonly dinTopProductos = signal<ProductoRankingOut[]>([]);

  ngOnInit(): void {
    this.sucursalesServicio.listarSucursales().subscribe({
      next: (sucursales) => this.sucursales.set(sucursales),
      error: () => this.sucursales.set([]),
    });
    this.catalogoServicio.obtenerFiltros().subscribe({
      next: (filtros) => this.categorias.set(filtros.categorias),
      error: () => this.categorias.set([]),
    });
    this.cargarVendedores(null);
  }

  protected cargarVendedores(sucursalId: string | null): void {
    this.servicio.vendedores(sucursalId).subscribe({
      next: (filas) => this.vendedores.set(filas),
      error: () => this.vendedores.set([]),
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
    this.chartEnvios?.destroy();
    this.chartOcupacionCajas?.destroy();
  }

  protected cambiarVista(vista: VistaReportes): void {
    this.vista.set(vista);
    if (vista === 'estaticos' && this.estaticoTipoActivo() === null) this.consultarEstatico();
    if (vista === 'dinamicos' && this.dinTipoActivo() === null) this.consultarDinamico();
  }

  private manejarError(e: HttpErrorResponse, porDefecto: string): void {
    this.error.set(interpretarError(e, porDefecto));
  }

  // =========================================================================
  //  GRAFICAS
  // =========================================================================

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
    this.cargarEnvios();
    this.cargarSinMovimiento();
    this.cargarTopClientes();
    this.cargarOcupacionCajas();
    this.cargarRecepcionesPendientes();
  }

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

  private cargarVentasDiarias(): void {
    const canal = (this.filtro.controls.canal.value || undefined) as CanalVenta | undefined;
    this.servicio.ventasDiarias({ ...this.filtroActual(), canal }).subscribe({
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

  private cargarReservas(): void {
    this.servicio.reservasPorEstado(this.filtroActual().sucursal_id).subscribe({
      next: (filas) => this.dibujarReservas(filas),
      error: (e: HttpErrorResponse) => this.manejarError(e, 'No se pudieron cargar las reservas por estado.'),
    });
  }

  private dibujarReservas(filas: ReservaEstadoOut[]): void {
    this.sinReservas.set(filas.length === 0);
    this.reservas.set(filas);
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

  private cargarEnvios(): void {
    this.servicio.enviosPorEstado(this.filtroActual().sucursal_id).subscribe({
      next: (filas) => this.dibujarEnvios(filas),
      error: (e: HttpErrorResponse) => this.manejarError(e, 'No se pudieron cargar los envíos por estado.'),
    });
  }

  private dibujarEnvios(filas: EnvioEstadoOut[]): void {
    this.sinEnvios.set(filas.length === 0);
    this.envios.set(filas);
    this.chartEnvios?.destroy();
    this.chartEnvios = new Chart(this.refEnvios.nativeElement, {
      type: 'bar',
      data: {
        labels: filas.map((f) => ETIQUETAS_ESTADO_ENVIO[f.estado] ?? f.estado),
        datasets: [
          {
            label: 'Envíos',
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

  private cargarSinMovimiento(): void {
    this.servicio.productosSinMovimiento(this.filtroActual().sucursal_id, 50).subscribe({
      next: (filas) => {
        this.sinSinMovimiento.set(filas.length === 0);
        this.sinMovimiento.set(filas);
      },
      error: (e: HttpErrorResponse) => this.manejarError(e, 'No se pudieron cargar los productos sin movimiento.'),
    });
  }

  private cargarTopClientes(): void {
    this.servicio.topClientes(this.filtroActual().sucursal_id, 10).subscribe({
      next: (filas) => {
        this.sinTopClientes.set(filas.length === 0);
        this.topClientes.set(filas);
      },
      error: (e: HttpErrorResponse) => this.manejarError(e, 'No se pudo cargar el ranking de clientes.'),
    });
  }

  private cargarOcupacionCajas(): void {
    this.servicio.ocupacionCajas(this.filtroActual().sucursal_id).subscribe({
      next: (filas) => this.dibujarOcupacionCajas(filas),
      error: (e: HttpErrorResponse) => this.manejarError(e, 'No se pudo cargar la ocupación de cajas.'),
    });
  }

  private dibujarOcupacionCajas(filas: CajaOcupacionOut[]): void {
    this.sinOcupacionCajas.set(filas.length === 0);
    this.ocupacionCajas.set(filas);
    this.chartOcupacionCajas?.destroy();
    this.chartOcupacionCajas = new Chart(this.refOcupacionCajas.nativeElement, {
      type: 'bar',
      data: {
        labels: filas.map((f) => f.sucursal),
        datasets: [
          {
            label: 'Cajas abiertas',
            data: filas.map((f) => f.cajas_abiertas),
            backgroundColor: COLOR_FLAME,
            borderRadius: 4,
            maxBarThickness: 40,
          },
          {
            label: 'Cajas totales',
            data: filas.map((f) => f.total_cajas),
            backgroundColor: COLOR_GRID,
            borderRadius: 4,
            maxBarThickness: 40,
          },
        ],
      },
      options: opcionesBase(true),
    });
  }

  private cargarRecepcionesPendientes(): void {
    this.servicio.recepcionesPendientes(this.filtroActual().sucursal_id).subscribe({
      next: (filas) => {
        this.sinRecepcionesPendientes.set(filas.length === 0);
        this.recepcionesPendientes.set(filas);
      },
      error: (e: HttpErrorResponse) => this.manejarError(e, 'No se pudieron cargar las recepciones pendientes.'),
    });
  }

  // =========================================================================
  //  REPORTE ESTATICOS: una consulta a la vez, sucursal como unico filtro
  // =========================================================================

  protected consultarEstatico(): void {
    const crudo = this.filtroEstatico.getRawValue();
    const tipo = crudo.tipo;
    const sucursalId = this.puedeElegirSucursal ? crudo.sucursal_id || null : null;

    this.error.set(null);
    this.estaticoCargando.set(true);

    const alTerminar = (cantidad: number): void => {
      this.estSinResultados.set(cantidad === 0);
      this.estaticoTipoActivo.set(tipo);
      this.estaticoCargando.set(false);
    };
    const alFallar = (e: HttpErrorResponse, mensaje: string): void => {
      this.manejarError(e, mensaje);
      this.estaticoCargando.set(false);
    };

    switch (tipo) {
      case 'stock':
        this.servicio.stockPorSucursal(sucursalId).subscribe({
          next: (f) => {
            this.estStock.set(f);
            alTerminar(f.length);
          },
          error: (e) => alFallar(e, 'No se pudo cargar el stock por sucursal.'),
        });
        break;
      case 'reservas':
        this.servicio.reservasPorEstado(sucursalId).subscribe({
          next: (f) => {
            this.estReservas.set(f);
            alTerminar(f.length);
          },
          error: (e) => alFallar(e, 'No se pudieron cargar las reservas por estado.'),
        });
        break;
      case 'envios':
        this.servicio.enviosPorEstado(sucursalId).subscribe({
          next: (f) => {
            this.estEnvios.set(f);
            alTerminar(f.length);
          },
          error: (e) => alFallar(e, 'No se pudieron cargar los envíos por estado.'),
        });
        break;
      case 'ocupacion':
        this.servicio.ocupacionCajas(sucursalId).subscribe({
          next: (f) => {
            this.estOcupacionCajas.set(f);
            alTerminar(f.length);
          },
          error: (e) => alFallar(e, 'No se pudo cargar la ocupación de cajas.'),
        });
        break;
      case 'clientes':
        this.servicio.topClientes(sucursalId, 10).subscribe({
          next: (f) => {
            this.estTopClientes.set(f);
            alTerminar(f.length);
          },
          error: (e) => alFallar(e, 'No se pudo cargar el ranking de clientes.'),
        });
        break;
      case 'sinMovimiento':
        this.servicio.productosSinMovimiento(sucursalId, 50).subscribe({
          next: (f) => {
            this.estSinMovimiento.set(f);
            alTerminar(f.length);
          },
          error: (e) => alFallar(e, 'No se pudieron cargar los productos sin movimiento.'),
        });
        break;
      case 'recepciones':
        this.servicio.recepcionesPendientes(sucursalId).subscribe({
          next: (f) => {
            this.estRecepcionesPendientes.set(f);
            alTerminar(f.length);
          },
          error: (e) => alFallar(e, 'No se pudieron cargar las recepciones pendientes.'),
        });
        break;
    }
  }

  // =========================================================================
  //  REPORTE DINAMICOS: una consulta a la vez, con todos los filtros
  // =========================================================================

  protected consultarDinamico(): void {
    const crudo = this.filtroDinamico.getRawValue();
    const tipo = crudo.tipo;
    const filtro: FiltroReportes = {
      desde: crudo.desde || undefined,
      hasta: crudo.hasta || undefined,
      sucursal_id: this.puedeElegirSucursal ? crudo.sucursal_id || undefined : undefined,
      categoria_id: crudo.categoria_id || undefined,
      vendedor_id: crudo.vendedor_id || undefined,
      canal: (crudo.canal || undefined) as CanalVenta | undefined,
      entrega: (crudo.entrega || undefined) as ModoEntrega | undefined,
    };

    this.error.set(null);
    this.dinCargando.set(true);

    const alTerminar = (cantidad: number): void => {
      this.dinSinResultados.set(cantidad === 0);
      this.dinTipoActivo.set(tipo);
      this.dinCargando.set(false);
    };
    const alFallar = (e: HttpErrorResponse, mensaje: string): void => {
      this.manejarError(e, mensaje);
      this.dinCargando.set(false);
    };

    switch (tipo) {
      case 'indicadores':
        this.servicio.indicadores(filtro).subscribe({
          next: (d) => {
            this.dinIndicadores.set(d);
            alTerminar(1);
          },
          error: (e) => alFallar(e, 'No se pudieron cargar los indicadores.'),
        });
        break;
      case 'ventasDiarias':
        this.servicio.ventasDiarias(filtro).subscribe({
          next: (f) => {
            this.dinVentasDiarias.set(f);
            alTerminar(f.length);
          },
          error: (e) => alFallar(e, 'No se pudieron cargar las ventas diarias.'),
        });
        break;
      case 'ventasPorSucursal':
        this.servicio.ventasPorSucursal(filtro).subscribe({
          next: (f) => {
            this.dinVentasPorSucursal.set(f);
            alTerminar(f.length);
          },
          error: (e) => alFallar(e, 'No se pudieron cargar las ventas por sucursal.'),
        });
        break;
      case 'topProductos':
        this.servicio.topProductos(filtro, 10).subscribe({
          next: (f) => {
            this.dinTopProductos.set(f);
            alTerminar(f.length);
          },
          error: (e) => alFallar(e, 'No se pudo cargar el ranking de productos.'),
        });
        break;
    }
  }
}
