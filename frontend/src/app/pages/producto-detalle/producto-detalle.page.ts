import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import { CatalogoService } from '../../core/catalogo/catalogo.service';
import { ProductoDetalleOut, VarianteOut } from '../../core/catalogo/catalogo.models';

@Component({
  selector: 'app-producto-detalle-page',
  standalone: true,
  imports: [RouterLink],
  templateUrl: './producto-detalle.page.html',
  styleUrl: './producto-detalle.page.css',
})
export class ProductoDetallePage implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly catalogo = inject(CatalogoService);

  protected readonly producto = signal<ProductoDetalleOut | null>(null);
  protected readonly cargando = signal(true);
  protected readonly noEncontrado = signal(false);

  protected readonly tallaSeleccionada = signal<string | null>(null);
  protected readonly colorSeleccionado = signal<string | null>(null);

  protected readonly tallas = computed(() => {
    const producto = this.producto();
    if (!producto) return [];
    return [...new Set(producto.variantes.map((v) => v.talla))];
  });

  protected readonly colores = computed(() => {
    const producto = this.producto();
    if (!producto) return [];
    const vistos = new Map<string, string>();
    for (const variante of producto.variantes) {
      if (!vistos.has(variante.color)) vistos.set(variante.color, variante.codigo_hex);
    }
    return [...vistos.entries()].map(([nombre, codigoHex]) => ({ nombre, codigoHex }));
  });

  protected readonly varianteSeleccionada = computed<VarianteOut | null>(() => {
    const producto = this.producto();
    if (!producto) return null;
    return (
      producto.variantes.find(
        (v) => v.talla === this.tallaSeleccionada() && v.color === this.colorSeleccionado(),
      ) ?? null
    );
  });

  ngOnInit(): void {
    const slug = this.route.snapshot.paramMap.get('slug');
    if (!slug) {
      this.noEncontrado.set(true);
      this.cargando.set(false);
      return;
    }
    this.catalogo.obtenerProducto(slug).subscribe({
      next: (producto) => {
        this.producto.set(producto);
        const primeraVariante = producto.variantes[0];
        if (primeraVariante) {
          this.tallaSeleccionada.set(primeraVariante.talla);
          this.colorSeleccionado.set(primeraVariante.color);
        }
        this.cargando.set(false);
      },
      error: () => {
        this.noEncontrado.set(true);
        this.cargando.set(false);
      },
    });
  }

  protected elegirTalla(talla: string): void {
    this.tallaSeleccionada.set(talla);
  }

  protected elegirColor(color: string): void {
    this.colorSeleccionado.set(color);
  }

  protected volverAlCatalogo(): void {
    this.router.navigateByUrl('/tienda');
  }

  protected formatearPrecio(precio: number): string {
    return `Bs ${precio.toFixed(2)}`;
  }

  protected formatearCiudad(ciudad: string): string {
    return ciudad
      .toLowerCase()
      .split('_')
      .map((palabra) => palabra.charAt(0).toUpperCase() + palabra.slice(1))
      .join(' ');
  }

  protected etiquetaSituacion(situacion: string): string {
    switch (situacion) {
      case 'DISPONIBLE':
        return 'Disponible';
      case 'RESERVADA':
        return 'Todo reservado';
      default:
        return 'Agotada';
    }
  }
}
