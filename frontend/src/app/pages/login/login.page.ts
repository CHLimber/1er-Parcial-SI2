import { HttpErrorResponse } from '@angular/common/http';
import { Component, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { AuthService } from '../../core/auth/auth.service';

@Component({
  selector: 'app-login-page',
  standalone: true,
  imports: [ReactiveFormsModule, RouterLink],
  templateUrl: './login.page.html',
  styleUrl: './login.page.css',
})
export class LoginPage {
  private readonly fb = inject(FormBuilder);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  protected readonly cargando = signal(false);
  protected readonly errorMensaje = signal<string | null>(null);
  protected readonly mostrarPassword = signal(false);

  protected readonly form = this.fb.nonNullable.group({
    email: ['', [Validators.required, Validators.email]],
    password: ['', [Validators.required]],
  });

  protected alternarPassword(): void {
    this.mostrarPassword.update((valor) => !valor);
  }

  protected enviar(): void {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }

    this.cargando.set(true);
    this.errorMensaje.set(null);

    this.auth.iniciarSesion(this.form.getRawValue()).subscribe({
      next: (usuario) => {
        // Por rol y no por permiso a proposito: ENCARGADO y ADMIN tambien tienen caja.crear
        // (pueden cubrir la caja), pero su pantalla de entrada no es esa.
        const esCajero = usuario.tipo === 'STAFF' && usuario.rol === 'CAJERO';
        this.router.navigateByUrl(esCajero ? '/caja' : '/tienda');
      },
      error: (error: HttpErrorResponse) => {
        this.cargando.set(false);
        this.errorMensaje.set(this.interpretarError(error));
      },
    });
  }

  private interpretarError(error: HttpErrorResponse): string {
    if (error.status === 0) return 'No se pudo conectar con el servidor. Verificá tu conexión.';
    // 401 (credenciales invalidas) y 429 (cuenta bloqueada por intentos) traen en `detail`
    // el mensaje puntual del backend, con los intentos restantes o los minutos de bloqueo.
    const detalle = error.error?.detail;
    if ((error.status === 401 || error.status === 429) && typeof detalle === 'string') {
      return detalle;
    }
    if (error.status === 401) return 'Correo o contraseña incorrectos.';
    return 'Ocurrió un error inesperado. Intentá de nuevo.';
  }
}
