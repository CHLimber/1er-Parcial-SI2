import { DatePipe } from '@angular/common';
import { Component, OnInit, inject, signal } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';

import { VentaOut } from '../../core/ventas/ventas.models';
import { VentasService } from '../../core/ventas/ventas.service';

@Component({
  selector: 'app-compra-page',
  standalone: true,
  imports: [RouterLink, DatePipe],
  templateUrl: './compra.page.html',
  styleUrl: './compra.page.css',
})
export class CompraPage implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly ventasService = inject(VentasService);

  protected readonly venta = signal<VentaOut | null>(null);
  protected readonly cargando = signal(true);
  protected readonly noEncontrada = signal(false);

  ngOnInit(): void {
    const ventaId = this.route.snapshot.paramMap.get('ventaId');
    if (!ventaId) {
      this.noEncontrada.set(true);
      this.cargando.set(false);
      return;
    }
    this.ventasService.obtenerVenta(ventaId).subscribe({
      next: (venta) => {
        this.venta.set(venta);
        this.cargando.set(false);
      },
      error: () => {
        this.noEncontrada.set(true);
        this.cargando.set(false);
      },
    });
  }

  protected formatearPrecio(precio: number): string {
    return `Bs ${precio.toFixed(2)}`;
  }
}
