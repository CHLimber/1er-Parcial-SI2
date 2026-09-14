import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import { CarritoService } from '../../core/carrito/carrito.service';
import { CatalogoService } from '../../core/catalogo/catalogo.service';
import { ProductoDetalleOut, VarianteOut } from '../../core/catalogo/catalogo.models';
import { ReservaCarritoService } from '../../core/reservas/reserva-carrito.service';

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
  private readonly reservaCarrito = inject(ReservaCarritoService);
  private readonly carritoService = inject(CarritoService);

  protected readonly producto = signal<ProductoDetalleOut | null>(null);
  protected readonly cargando = signal(true);
  protected readonly noEncontrado = signal(false);

  protected readonly tallaSeleccionada = signal<string | null>(null);
  protected readonly colorSeleccionado = signal<string | null>(null);
  protected readonly colorElegidoManualmente = signal(false);
  protected readonly agregadoAReserva = signal(false);
  protected readonly agregadoAlCarrito = signal(false);
  protected readonly errorCarrito = signal<string | null>(null);
  protected readonly itemsEnReserva = this.reservaCarrito.cantidadTotal;
  protected readonly itemsEnCarrito = this.carritoService.cantidadItems;

  protected readonly tallas = computed(() => {
    const producto = this.producto();
    if (!producto) return [];
    return [...new Set(producto.variantes.map((v) => v.talla))];
  });

  protected readonly colorDeCatalogo = computed<string | null>(() => {
    const producto = this.producto();
    if (!producto?.imagen_url) return null;
    return (
      producto.variantes.find((v) => v.imagen_url === producto.imagen_url)?.color ?? null
    );
  });

  protected readonly colores = computed(() => {
    const producto = this.producto();
    if (!producto) return [];
    const vistos = new Map<string, string>();
    for (const variante of producto.variantes) {
      if (!vistos.has(variante.color)) vistos.set(variante.color, variante.codigo_hex);
    }
    const lista = [...vistos.entries()].map(([nombre, codigoHex]) => ({ nombre, codigoHex }));
    const colorCatalogo = this.colorDeCatalogo();
    if (!colorCatalogo) return lista;
    const indice = lista.findIndex((c) => c.nombre === colorCatalogo);
    if (indice <= 0) return lista;
    const [principal] = lista.splice(indice, 1);
    return [principal, ...lista];
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

  protected readonly imagenActual = computed<string | null>(() => {
    const producto = this.producto();
    if (!producto) return null;
    if (!this.colorElegidoManualmente()) return producto.imagen_url;
    const color = this.colorSeleccionado();
    const variantePorColor = producto.variantes.find(
      (v) => v.color === color && v.imagen_url,
    );
    return variantePorColor?.imagen_url ?? producto.imagen_url;
  });

  ngOnInit(): void {
    this.carritoService.refrescar();

    const slug = this.route.snapshot.paramMap.get('slug');
    if (!slug) {
      this.noEncontrado.set(true);
      this.cargando.set(false);
      return;
    }
    this.catalogo.obtenerProducto(slug).subscribe({
      next: (producto) => {
        this.producto.set(producto);
        const colorCatalogo = producto.variantes.find(
          (v) => v.imagen_url === producto.imagen_url,
        )?.color;
        const varianteInicial =
          producto.variantes.find((v) => v.color === colorCatalogo) ?? producto.variantes[0];
        if (varianteInicial) {
          this.tallaSeleccionada.set(varianteInicial.talla);
          this.colorSeleccionado.set(varianteInicial.color);
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
    this.colorElegidoManualmente.set(true);
  }

  protected agregarAReserva(): void {
    const producto = this.producto();
    const variante = this.varianteSeleccionada();
    if (!producto || !variante) return;

    this.reservaCarrito.agregar({
      varianteId: variante.id,
      sku: variante.sku,
      producto: producto.nombre,
      productoSlug: producto.slug,
      talla: variante.talla,
      color: variante.color,
      codigoHex: variante.codigo_hex,
      precio: variante.precio,
      imagenUrl: this.imagenActual(),
      cantidad: 1,
    });
    this.agregadoAReserva.set(true);
    setTimeout(() => this.agregadoAReserva.set(false), 2500);
  }

  protected irAReservar(): void {
    this.router.navigateByUrl('/reservar');
  }

  protected comprarAhora(): void {
    const variante = this.varianteSeleccionada();
    if (!variante) return;

    this.errorCarrito.set(null);
    this.carritoService.agregarItem({ variante_id: variante.id, cantidad: 1 }).subscribe({
      next: () => {
        this.agregadoAlCarrito.set(true);
        setTimeout(() => this.agregadoAlCarrito.set(false), 2500);
      },
      error: () => {
        this.errorCarrito.set('No se pudo agregar la prenda al carrito. Puede que ya no tenga stock.');
      },
    });
  }

  protected irAlCarrito(): void {
    this.router.navigateByUrl('/carrito');
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
