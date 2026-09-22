import { Component, computed, input } from '@angular/core';

import { reglasPassword } from '../validacion-password';

/**
 * Checklist en vivo de la politica de contrasena (CU02/CU13): que reglas cumple ya lo
 * que el usuario escribio y cuales le faltan. Se re-evalua en cada deteccion de cambios
 * porque `password` viaja como el valor crudo del FormControl, no como signal.
 */
@Component({
  selector: 'app-lista-requisitos-password',
  standalone: true,
  templateUrl: './lista-requisitos-password.html',
  styleUrl: './lista-requisitos-password.css',
})
export class ListaRequisitosPassword {
  readonly password = input<string>('');

  protected readonly reglas = computed(() => reglasPassword(this.password()));
}
