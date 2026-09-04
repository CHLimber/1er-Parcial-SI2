import { HttpErrorResponse } from '@angular/common/http';
import { Component, inject, signal } from '@angular/core';
import { AbstractControl, FormBuilder, ReactiveFormsModule, ValidationErrors, Validators } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { AuthService } from '../../core/auth/auth.service';

function passwordsIgualesValidator(control: AbstractControl): ValidationErrors | null {
  const password = control.get('password')?.value;
  const confirmarPassword = control.get('confirmarPassword')?.value;
  return password === confirmarPassword ? null : { passwordsDistintos: true };
}

function passwordSeguraValidator(control: AbstractControl): ValidationErrors | null {
  const valor: string = control.value ?? '';
  const errores: ValidationErrors = {};
  if (!/[a-z]/.test(valor)) errores['faltaMinuscula'] = true;
  if (!/[A-Z]/.test(valor)) errores['faltaMayuscula'] = true;
  if (!/\d/.test(valor)) errores['faltaNumero'] = true;
  return Object.keys(errores).length ? errores : null;
}

@Component({
  selector: 'app-registro-page',
  standalone: true,
  imports: [ReactiveFormsModule, RouterLink],
  templateUrl: './registro.page.html',
  styleUrl: './registro.page.css',
})
export class RegistroPage {
  private readonly fb = inject(FormBuilder);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  protected readonly cargando = signal(false);
  protected readonly errorMensaje = signal<string | null>(null);
  protected readonly mostrarPassword = signal(false);

  protected readonly form = this.fb.nonNullable.group(
    {
      nombre: ['', [Validators.required, Validators.maxLength(80)]],
      apellido: ['', [Validators.required, Validators.maxLength(80)]],
      email: ['', [Validators.required, Validators.email]],
      telefono: [''],
      password: ['', [Validators.required, Validators.minLength(8), passwordSeguraValidator]],
      confirmarPassword: ['', [Validators.required]],
    },
    { validators: passwordsIgualesValidator },
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
    this.errorMensaje.set(null);

    const { confirmarPassword, telefono, ...datos } = this.form.getRawValue();

    this.auth
      .registrarse({ ...datos, telefono: telefono || null })
      .subscribe({
        next: () => this.router.navigateByUrl('/tienda'),
        error: (error: HttpErrorResponse) => {
          this.cargando.set(false);
          this.errorMensaje.set(this.interpretarError(error));
        },
      });
  }

  private interpretarError(error: HttpErrorResponse): string {
    if (error.status === 409) return 'Ese correo ya está registrado.';
    if (error.status === 422) return 'Revisá los datos ingresados.';
    if (error.status === 0) return 'No se pudo conectar con el servidor. Verificá tu conexión.';
    return 'Ocurrió un error inesperado. Intentá de nuevo.';
  }
}
