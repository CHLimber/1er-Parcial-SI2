import { HttpErrorResponse } from '@angular/common/http';
import { Component, computed, inject, signal } from '@angular/core';
import {
  AbstractControl,
  FormBuilder,
  ReactiveFormsModule,
  ValidationErrors,
  Validators,
} from '@angular/forms';
import { RouterLink } from '@angular/router';

import { AuthService } from '../../core/auth/auth.service';
import { ListaRequisitosPassword } from '../../shared/lista-requisitos-password/lista-requisitos-password';
import { passwordSeguraValidator } from '../../shared/validacion-password';

function passwordsIgualesValidator(control: AbstractControl): ValidationErrors | null {
  const nueva = control.get('passwordNueva')?.value;
  const confirmar = control.get('confirmarPassword')?.value;
  return nueva === confirmar ? null : { passwordsDistintos: true };
}

function passwordDistintaDeActualValidator(control: AbstractControl): ValidationErrors | null {
  const actual = control.get('passwordActual')?.value;
  const nueva = control.get('passwordNueva')?.value;
  return actual && nueva && actual === nueva ? { passwordIgualALaActual: true } : null;
}

/**
 * Cambiar mi propia contraseña: para CLIENTE y STAFF (cualquiera logueado), a diferencia
 * de CU13 (`pages/panel-usuarios`), que resetea la de otro sin conocer la actual. Se llega
 * aca desde la cabecera de la tienda y desde el panel de gestion (`panel-shell`).
 */
@Component({
  selector: 'app-cambiar-password-page',
  standalone: true,
  imports: [ReactiveFormsModule, RouterLink, ListaRequisitosPassword],
  templateUrl: './cambiar-password.page.html',
  styleUrls: ['./cambiar-password.page.css', '../../shared/responsive.css'],
})
export class CambiarPasswordPage {
  private readonly fb = inject(FormBuilder);
  private readonly auth = inject(AuthService);

  protected readonly esStaff = computed(() => this.auth.usuario()?.tipo === 'STAFF');
  protected readonly volverA = computed(() => (this.esStaff() ? '/panel' : '/tienda'));

  protected readonly guardando = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly aviso = signal<string | null>(null);
  protected readonly mostrarPassword = signal(false);

  protected readonly form = this.fb.nonNullable.group(
    {
      passwordActual: ['', [Validators.required]],
      passwordNueva: ['', [Validators.required, passwordSeguraValidator]],
      confirmarPassword: ['', [Validators.required]],
    },
    { validators: [passwordsIgualesValidator, passwordDistintaDeActualValidator] },
  );

  protected alternarPassword(): void {
    this.mostrarPassword.update((valor) => !valor);
  }

  protected enviar(): void {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }

    this.guardando.set(true);
    this.error.set(null);
    this.aviso.set(null);

    const { passwordActual, passwordNueva } = this.form.getRawValue();
    this.auth.cambiarPassword({ password_actual: passwordActual, password_nueva: passwordNueva }).subscribe({
      next: () => {
        this.guardando.set(false);
        this.aviso.set('Tu contraseña se actualizó correctamente.');
        this.form.reset({ passwordActual: '', passwordNueva: '', confirmarPassword: '' });
      },
      error: (e: HttpErrorResponse) => {
        this.guardando.set(false);
        this.error.set(this.interpretarError(e));
      },
    });
  }

  /**
   * Espejo de `pages/login/login.page.ts::interpretarError`: no se reusa el `interpretarError`
   * compartido porque este endpoint devuelve 401 cuando la contraseña ACTUAL esta mal (no
   * cuando la sesion expiro), y el compartido siempre lo lee como sesion vencida.
   */
  private interpretarError(error: HttpErrorResponse): string {
    if (error.status === 0) return 'No se pudo conectar con el servidor. Verificá tu conexión.';
    const detalle = error.error?.detail;
    if ((error.status === 401 || error.status === 422) && typeof detalle === 'string') {
      return detalle;
    }
    if (error.status === 401) return 'La contraseña actual no es correcta.';
    return 'No se pudo cambiar la contraseña. Intentá de nuevo.';
  }
}
