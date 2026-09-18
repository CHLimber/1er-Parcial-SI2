import { Component, inject, input } from '@angular/core';
import { Router } from '@angular/router';

import { ProductoOut } from '../../core/catalogo/catalogo.models';

/**
 * Tarjeta de prenda, extraida de tienda.page (unico consumidor original) al sumarse
 * pages/recomendaciones. El selector `li[app-producto-card]` deja que el que la usa la ponga
 * directo adentro de un `<ul>` sin envolverla en un `<li>` aparte.
 */
@Component({
  selector: 'li[app-producto-card]',
  standalone: true,
  templateUrl: './producto-card.html',
  styleUrl: './producto-card.css',
  host: {
    class: 'prenda',
    '[class.prenda--agotada]': 'producto().agotado',
    '(click)': 'ir()',
  },
})
export class ProductoCard {
  private readonly router = inject(Router);

  readonly producto = input.required<ProductoOut>();
  /** Motivo de la recomendacion (CU17); ausente en el catalogo comun. */
  readonly motivo = input<string | null>(null);

  protected ir(): void {
    this.router.navigate(['/producto', this.producto().slug]);
  }
}
