import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { Router } from '@angular/router';

import { AuthService } from '../../core/auth/auth.service';
import { CatalogoService } from '../../core/catalogo/catalogo.service';
import { ProductoOut } from '../../core/catalogo/catalogo.models';

@Component({
  selector: 'app-tienda-page',
  standalone: true,
  imports: [],
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

  ngOnInit(): void {
    this.catalogo.listarProductos(8).subscribe({
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

  protected cerrarSesion(): void {
    this.auth.cerrarSesion();
    this.router.navigateByUrl('/login');
  }

  protected formatearPrecio(precio: number): string {
    return `Bs ${precio.toFixed(2)}`;
  }
}
