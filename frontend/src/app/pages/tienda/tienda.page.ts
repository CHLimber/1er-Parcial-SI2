import { Component, OnDestroy, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { AuthService } from '../../core/auth/auth.service';
import { CarritoService } from '../../core/carrito/carrito.service';
import { CatalogoService } from '../../core/catalogo/catalogo.service';
import { FiltrosOut, ProductoOut } from '../../core/catalogo/catalogo.models';
import { ProductoRecomendadoOut } from '../../core/recomendaciones/recomendaciones.models';
import { RecomendacionesService } from '../../core/recomendaciones/recomendaciones.service';
import { ReservaCarritoService } from '../../core/reservas/reserva-carrito.service';
import { ProductoCard } from '../../shared/catalogo/producto-card';
import { CampanaNotificaciones } from '../../shared/notificaciones/campana-notificaciones';

@Component({
  selector: 'app-tienda-page',
  standalone: true,
  imports: [CampanaNotificaciones, FormsModule, ProductoCard, RouterLink],
  templateUrl: './tienda.page.html',
  styleUrls: ['./tienda.page.css', '../../shared/responsive.css'],
})
export class TiendaPage implements OnInit, OnDestroy {
  private readonly auth = inject(AuthService);
  private readonly catalogo = inject(CatalogoService);
  private readonly router = inject(Router);
  private readonly reservaCarrito = inject(ReservaCarritoService);
  private readonly carritoService = inject(CarritoService);
  private readonly recomendacionesServicio = inject(RecomendacionesService);

  protected readonly usuario = this.auth.usuario;
  protected readonly esStaff = computed(() => this.usuario()?.tipo === 'STAFF');
  protected readonly itemsEnReserva = this.reservaCarrito.cantidadTotal;
  protected readonly itemsEnCarrito = this.carritoService.cantidadItems;

  /**
   * Menu de la cabecera en telefono y tablet: los seis enlaces de la clienta no entran en
   * una fila, asi que abajo de 64rem se pliegan detras del boton hamburguesa (ver
   * `tienda.page.css`). En escritorio el boton no se muestra y esta bandera no hace nada.
   */
  protected readonly menuAbierto = signal(false);

  /** Prendas pendientes (bolsa de reserva + carrito): el punto del boton cuando esta cerrado. */
  protected readonly itemsPendientes = computed(() => this.itemsEnReserva() + this.itemsEnCarrito());

  protected readonly productos = signal<ProductoOut[]>([]);
  protected readonly cargandoCatalogo = signal(true);
  protected readonly errorCatalogo = signal<string | null>(null);

  /** CU17: solo tiene sentido para clientes, se llena en silencio (no es critico para la pagina). */
  protected readonly recomendaciones = signal<ProductoRecomendadoOut[]>([]);

  protected readonly filtros = signal<FiltrosOut | null>(null);

  protected categoriaSlug = '';
  protected q = '';
  protected tallaId: number | null = null;
  protected colorId: number | null = null;
  protected temporadaId = '';

  /** Cantidad de resultados de la ultima busqueda, para el resumen "N prendas". */
  protected readonly totalResultados = computed(() => this.productos().length);

  /** El catalogo tiene decenas de tonos casi identicos (ver PENDIENTES.txt);
   * arrancamos mostrando solo los primeros para no saturar el filtro. */
  private static readonly COLORES_VISIBLES_INICIAL = 12;
  protected readonly mostrarTodosLosColores = signal(false);

  protected readonly coloresAMostrar = computed(() => {
    const colores = this.filtros()?.colores ?? [];
    const colorSeleccionado = colores.find((c) => c.id === this.colorId);
    if (this.mostrarTodosLosColores() || colores.length <= TiendaPage.COLORES_VISIBLES_INICIAL) {
      return colores;
    }
    const visibles = colores.slice(0, TiendaPage.COLORES_VISIBLES_INICIAL);
    if (colorSeleccionado && !visibles.includes(colorSeleccionado)) {
      visibles.push(colorSeleccionado);
    }
    return visibles;
  });

  protected readonly hayColoresOcultos = computed(
    () => (this.filtros()?.colores.length ?? 0) > this.coloresAMostrar().length,
  );

  private temporizadorBusqueda: ReturnType<typeof setTimeout> | undefined;

  protected hayFiltrosActivos(): boolean {
    return !!(this.categoriaSlug || this.q || this.tallaId || this.colorId || this.temporadaId);
  }

  ngOnInit(): void {
    this.catalogo.obtenerFiltros().subscribe({
      next: (filtros) => this.filtros.set(filtros),
      error: () => this.filtros.set(null),
    });
    this.buscar();
    if (!this.esStaff()) {
      this.carritoService.refrescar();
      this.recomendacionesServicio.obtener(8).subscribe({
        next: (productos) => this.recomendaciones.set(productos),
        error: () => this.recomendaciones.set([]),
      });
    }
  }

  /** Chips de categoria: un clic aplica el filtro al toque, sin pasar por "Filtrar". */
  protected seleccionarCategoria(slug: string): void {
    this.categoriaSlug = this.categoriaSlug === slug ? '' : slug;
    this.buscar();
  }

  protected seleccionarTalla(id: number): void {
    this.tallaId = this.tallaId === id ? null : id;
    this.buscar();
  }

  protected seleccionarColor(id: number): void {
    this.colorId = this.colorId === id ? null : id;
    this.buscar();
  }

  protected alternarTodosLosColores(): void {
    this.mostrarTodosLosColores.set(!this.mostrarTodosLosColores());
  }

  protected cambiarTemporada(): void {
    this.buscar();
  }

  /** Busqueda por texto en vivo, con una pausa corta para no pegarle a la API en cada tecla. */
  protected buscarConDemora(): void {
    clearTimeout(this.temporizadorBusqueda);
    this.temporizadorBusqueda = setTimeout(() => this.buscar(), 350);
  }

  protected quitarFiltro(campo: 'categoria' | 'q' | 'talla' | 'color' | 'temporada'): void {
    if (campo === 'categoria') this.categoriaSlug = '';
    if (campo === 'q') this.q = '';
    if (campo === 'talla') this.tallaId = null;
    if (campo === 'color') this.colorId = null;
    if (campo === 'temporada') this.temporadaId = '';
    this.buscar();
  }

  protected nombreCategoria(slug: string): string {
    return this.filtros()?.categorias.find((c) => c.slug === slug)?.nombre ?? slug;
  }

  protected codigoTalla(id: number): string {
    return this.filtros()?.tallas.find((t) => t.id === id)?.codigo ?? '';
  }

  protected nombreColor(id: number): string {
    return this.filtros()?.colores.find((c) => c.id === id)?.nombre ?? '';
  }

  protected nombreTemporada(id: string): string {
    return this.filtros()?.temporadas.find((t) => t.id === id)?.nombre ?? id;
  }

  ngOnDestroy(): void {
    clearTimeout(this.temporizadorBusqueda);
  }

  protected buscar(): void {
    this.cargandoCatalogo.set(true);
    this.errorCatalogo.set(null);
    this.catalogo
      .listarProductos({
        categoriaSlug: this.categoriaSlug || undefined,
        q: this.q.trim() || undefined,
        tallaId: this.tallaId ?? undefined,
        colorId: this.colorId ?? undefined,
        temporadaId: this.temporadaId || undefined,
        limit: 60,
      })
      .subscribe({
        next: (productos) => {
          this.productos.set(productos);
          this.cargandoCatalogo.set(false);
        },
        error: () => {
          this.errorCatalogo.set('No se pudo cargar el catálogo por ahora.');
          this.cargandoCatalogo.set(false);
        },
      });
  }

  protected limpiarFiltros(): void {
    this.categoriaSlug = '';
    this.q = '';
    this.tallaId = null;
    this.colorId = null;
    this.temporadaId = '';
    this.mostrarTodosLosColores.set(false);
    this.buscar();
  }

  protected alternarMenu(): void {
    this.menuAbierto.set(!this.menuAbierto());
  }

  /** Al navegar el componente se destruye, pero el menu tambien se cierra al tocar un enlace
   * para que la transicion no se vea con el panel todavia desplegado. */
  protected cerrarMenu(): void {
    this.menuAbierto.set(false);
  }

  protected cerrarSesion(): void {
    this.auth.cerrarSesion();
    this.router.navigateByUrl('/login');
  }
}
