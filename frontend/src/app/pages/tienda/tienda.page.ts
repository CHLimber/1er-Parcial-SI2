import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';

import { AuthService } from '../../core/auth/auth.service';
import { CatalogoService } from '../../core/catalogo/catalogo.service';
import { FiltrosOut, ProductoOut } from '../../core/catalogo/catalogo.models';

@Component({
  selector: 'app-tienda-page',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './tienda.page.html',
  styleUrl: './tienda.page.css',
})
export class TiendaPage implements OnInit {
  private readonly auth = inject(AuthService);
  private readonly catalogo = inject(CatalogoService);
  private readonly router = inject(Router);

  protected readonly usuario = this.auth.usuario;
  protected readonly esStaff = computed(() => this.usuario()?.tipo === 'STAFF');

  protected readonly productos = signal<ProductoOut[]>([]);
  protected readonly cargandoCatalogo = signal(true);
  protected readonly errorCatalogo = signal<string | null>(null);

  protected readonly filtros = signal<FiltrosOut | null>(null);

  protected categoriaSlug = '';
  protected q = '';
  protected tallaId: number | null = null;
  protected colorId: number | null = null;
  protected temporadaId = '';

  protected hayFiltrosActivos(): boolean {
    return !!(this.categoriaSlug || this.q || this.tallaId || this.colorId || this.temporadaId);
  }

  ngOnInit(): void {
    this.catalogo.obtenerFiltros().subscribe({
      next: (filtros) => this.filtros.set(filtros),
      error: () => this.filtros.set(null),
    });
    this.buscar();
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
    this.buscar();
  }

  protected verProducto(producto: ProductoOut): void {
    this.router.navigate(['/producto', producto.slug]);
  }

  protected cerrarSesion(): void {
    this.auth.cerrarSesion();
    this.router.navigateByUrl('/login');
  }

  protected formatearPrecio(precio: number): string {
    return `Bs ${precio.toFixed(2)}`;
  }
}
