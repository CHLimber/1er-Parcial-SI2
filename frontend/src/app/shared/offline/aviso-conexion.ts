import { Component, inject } from '@angular/core';

import { ConexionService } from '../../core/offline/conexion.service';

/**
 * Franja fija que avisa el estado de la PWA (PENDIENTES 5.2): sin conexion (y desde cuando son
 * los datos que se ven), operaciones guardadas pendientes de enviar, y el resultado de la
 * sincronizacion al volver la red. Vive en el componente raiz, asi aparece en todas las pantallas.
 */
@Component({
  selector: 'app-aviso-conexion',
  standalone: true,
  template: `
    @if (!conexion.enLinea()) {
      <div class="aviso aviso--offline" role="status">
        <strong>Sin conexión.</strong>
        @if (conexion.datosDe(); as fecha) {
          Mostramos los datos guardados el {{ formato(fecha) }}.
        } @else {
          Podés seguir viendo lo que ya cargaste.
        }
        @if (conexion.pendientes() > 0) {
          · {{ conexion.pendientes() }} operación(es) esperan la red.
        }
      </div>
    } @else if (conexion.ultimoAviso(); as aviso) {
      <div class="aviso aviso--ok" role="status">
        {{ aviso }}
        <button type="button" (click)="conexion.ultimoAviso.set(null)" aria-label="Cerrar aviso">×</button>
      </div>
    }
  `,
  styles: `
    .aviso {
      position: fixed;
      left: 50%;
      bottom: 1rem;
      transform: translateX(-50%);
      z-index: 1000;
      max-width: min(40rem, calc(100vw - 2rem));
      padding: 0.6rem 1rem;
      font-size: 0.88rem;
      box-shadow: 0 6px 20px rgba(0, 0, 0, 0.18);
      display: flex;
      gap: 0.5rem;
      align-items: center;
      flex-wrap: wrap;
    }
    .aviso--offline {
      background: var(--ink);
      color: var(--white);
    }
    .aviso--ok {
      background: var(--white);
      color: var(--ink);
      border: 1px solid var(--paper-line);
    }
    button {
      border: 0;
      background: transparent;
      font-size: 1.1rem;
      cursor: pointer;
      color: inherit;
    }
  `,
})
export class AvisoConexion {
  protected readonly conexion = inject(ConexionService);

  protected formato(fecha: string): string {
    return new Date(fecha).toLocaleString('es-BO', { dateStyle: 'short', timeStyle: 'short' });
  }
}
