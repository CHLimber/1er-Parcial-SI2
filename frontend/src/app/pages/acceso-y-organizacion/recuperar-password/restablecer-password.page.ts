import { HttpErrorResponse } from '@angular/common/http';
import { Component, inject, signal } from '@angular/core';
import {
  AbstractControl,
  FormBuilder,
  ReactiveFormsModule,
  ValidationErrors,
  Validators,
} from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';

import { AuthService } from '../../../core/acceso-y-organizacion/auth/auth.service';
import { interpretarError } from '../../../shared/errores';
import { ListaRequisitosPassword } from '../../../shared/lista-requisitos-password/lista-requisitos-password';
import { passwordSeguraValidator } from '../../../shared/validacion-password';

function passwordsIgualesValidator(control: AbstractControl): ValidationErrors | null {
  return control.get('passwordNueva')?.value === control.get('confirmarPassword')?.value
    ? null
    : { passwordsDistintos: true };
}

/** Recuperacion de cuenta, paso 2: con el token del enlace del correo elige la contraseña nueva. */
@Component({
  selector: 'app-restablecer-password-page',
  standalone: true,
  imports: [ReactiveFormsModule, RouterLink, ListaRequisitosPassword],
  templateUrl: './restablecer-password.page.html',
  styleUrl: '../login/login.page.css',
})
export class RestablecerPasswordPage {
  private readonly fb = inject(FormBuilder);
  private readonly auth = inject(AuthService);
  private readonly token = inject(ActivatedRoute).snapshot.queryParamMap.get('token') ?? '';

  protected readonly sinToken = this.token === '';
  protected readonly cargando = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly listo = signal(false);
  protected readonly mostrarPassword = signal(false);

  protected readonly form = this.fb.nonNullable.group(
    {
      passwordNueva: ['', [Validators.required, passwordSeguraValidator]],
      confirmarPassword: ['', [Validators.required]],
    },
    { validators: [passwordsIgualesValidator] },
  );

  protected alternarPassword(): void {
    this.mostrarPassword.update((valor) => !valor);
  }

  protected enviar(): void {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }
    this.cargando.set(true);
    this.error.set(null);
    this.auth.restablecerPassword(this.token, this.form.getRawValue().passwordNueva).subscribe({
      next: () => {
        this.cargando.set(false);
        this.listo.set(true);
      },
      error: (e: HttpErrorResponse) => {
        this.cargando.set(false);
        this.error.set(interpretarError(e, 'No se pudo cambiar la contraseña. Pedí un enlace nuevo.'));
      },
    });
  }
}
