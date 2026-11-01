import { HttpErrorResponse } from '@angular/common/http';
import { Component, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { RouterLink } from '@angular/router';

import { AuthService } from '../../../core/acceso-y-organizacion/auth/auth.service';
import { interpretarError } from '../../../shared/errores';

/** Recuperacion de cuenta, paso 1: la persona escribe su correo y recibe un enlace de un solo uso.
 * Para CLIENTE y STAFF. La respuesta es la misma exista o no el correo. */
@Component({
  selector: 'app-recuperar-password-page',
  standalone: true,
  imports: [ReactiveFormsModule, RouterLink],
  templateUrl: './recuperar-password.page.html',
  styleUrl: '../login/login.page.css',
})
export class RecuperarPasswordPage {
  private readonly fb = inject(FormBuilder);
  private readonly auth = inject(AuthService);

  protected readonly cargando = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly mensaje = signal<string | null>(null);
  /** Solo si el backend esta en modo demostracion (sin correo configurado). */
  protected readonly enlace = signal<string | null>(null);

  protected readonly form = this.fb.nonNullable.group({
    email: ['', [Validators.required, Validators.email]],
  });

  protected enviar(): void {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }
    this.cargando.set(true);
    this.error.set(null);
    this.auth.recuperarPassword(this.form.getRawValue().email.trim()).subscribe({
      next: (respuesta) => {
        this.cargando.set(false);
        this.mensaje.set(respuesta.mensaje);
        this.enlace.set(respuesta.enlace ?? null);
      },
      error: (e: HttpErrorResponse) => {
        this.cargando.set(false);
        this.error.set(interpretarError(e, 'No pudimos procesar el pedido. Intentá de nuevo en unos minutos.'));
      },
    });
  }
}
