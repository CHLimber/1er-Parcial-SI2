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
    if (error.status === 401) return 'Correo o contraseña incorrectos.';
    if (error.status === 0) return 'No se pudo conectar con el servidor. Verificá tu conexión.';
    return 'Ocurrió un error inesperado. Intentá de nuevo.';
  }
}
