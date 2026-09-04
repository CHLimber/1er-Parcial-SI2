import { DatePipe } from '@angular/common';
import { Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';

import { ReservaOut } from '../../core/reservas/reservas.models';
import { ReservasService } from '../../core/reservas/reservas.service';

@Component({
  selector: 'app-mis-reservas-page',
  standalone: true,
  imports: [RouterLink, DatePipe],
  templateUrl: './mis-reservas.page.html',
  styleUrl: './mis-reservas.page.css',
})
export class MisReservasPage implements OnInit {
  private readonly reservasService = inject(ReservasService);

  protected readonly reservas = signal<ReservaOut[]>([]);
  protected readonly cargando = signal(true);
  protected readonly error = signal<string | null>(null);

  ngOnInit(): void {
    this.reservasService.listarMisReservas().subscribe({
      next: (reservas) => {
        this.reservas.set(reservas);
        this.cargando.set(false);
      },
      error: () => {
        this.error.set('No se pudieron cargar tus reservas por ahora.');
        this.cargando.set(false);
      },
    });
  }

  protected etiquetaEstado(estado: string): string {
    switch (estado) {
      case 'PENDIENTE':
        return 'Pendiente de confirmación';
      case 'CONFIRMADA':
        return 'Confirmada';
      case 'PREPARADA':
        return 'Prendas preparadas';
      case 'CLIENTE_PRESENTE':
        return 'En tienda';
      case 'ATENDIDA':
        return 'Atendida';
      case 'CONVERTIDA':
        return 'Convertida en compra';
      case 'CANCELADA':
        return 'Cancelada';
      case 'EXPIRADA':
        return 'Expirada';
      default:
        return estado;
    }
  }
}
