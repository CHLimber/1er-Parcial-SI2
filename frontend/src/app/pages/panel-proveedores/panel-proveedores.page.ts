import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';

import { AuthService } from '../../core/auth/auth.service';
import { ProveedorIn, ProveedorOut } from '../../core/proveedores/proveedores.models';
import { ProveedoresService } from '../../core/proveedores/proveedores.service';
import { interpretarError } from '../../shared/errores';
import { PanelShell } from '../../shared/panel/panel-shell';

/** CU11 - Gestionar Proveedores. */
@Component({
  selector: 'app-panel-proveedores-page',
  standalone: true,
  imports: [PanelShell, ReactiveFormsModule],
  templateUrl: './panel-proveedores.page.html',
  styleUrls: ['../../shared/panel/panel-comun.css'],
})
export class PanelProveedoresPage implements OnInit {
  private readonly servicio = inject(ProveedoresService);
  private readonly fb = inject(FormBuilder);
  private readonly auth = inject(AuthService);

  protected readonly cargando = signal(true);
  protected readonly proveedores = signal<ProveedorOut[]>([]);
  protected readonly error = signal<string | null>(null);
  protected readonly errorFormulario = signal<string | null>(null);
  protected readonly guardando = signal(false);
  protected readonly editando = signal<ProveedorOut | null>(null);
  protected readonly formularioAbierto = signal(false);

  protected busqueda = '';
  protected filtroEstado: '' | 'true' | 'false' = '';

  protected readonly puedeGestionar = this.auth.tienePermiso('proveedores.gestionar');

  protected readonly form = this.fb.nonNullable.group({
    nombre: ['', [Validators.required, Validators.minLength(2), Validators.maxLength(150)]],
    nit: [''],
    contacto: [''],
    email: ['', [Validators.email]],
    telefono: [''],
  });

  ngOnInit(): void {
    this.cargar();
  }

  protected cargar(): void {
    this.cargando.set(true);
    this.error.set(null);
    const activo = this.filtroEstado === '' ? null : this.filtroEstado === 'true';
    this.servicio.listar(this.busqueda || undefined, activo).subscribe({
      next: (proveedores) => {
        this.proveedores.set(proveedores);
        this.cargando.set(false);
      },
      error: (e: HttpErrorResponse) => {
        this.error.set(interpretarError(e, 'No se pudo cargar el padrón de proveedores.'));
        this.cargando.set(false);
      },
    });
  }

  protected nuevo(): void {
    this.editando.set(null);
    this.errorFormulario.set(null);
    this.form.reset({ nombre: '', nit: '', contacto: '', email: '', telefono: '' });
    this.formularioAbierto.set(true);
  }

  protected editar(proveedor: ProveedorOut): void {
    this.editando.set(proveedor);
    this.errorFormulario.set(null);
    this.form.reset({
      nombre: proveedor.nombre,
      nit: proveedor.nit ?? '',
      contacto: proveedor.contacto ?? '',
      email: proveedor.email ?? '',
      telefono: proveedor.telefono ?? '',
    });
    this.formularioAbierto.set(true);
  }

  protected cerrarFormulario(): void {
    this.formularioAbierto.set(false);
    this.editando.set(null);
  }

  protected guardar(): void {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }

    const crudo = this.form.getRawValue();
    const datos: ProveedorIn = {
      nombre: crudo.nombre.trim(),
      nit: crudo.nit.trim() || null,
      contacto: crudo.contacto.trim() || null,
      email: crudo.email.trim() || null,
      telefono: crudo.telefono.trim() || null,
    };

    this.guardando.set(true);
    this.errorFormulario.set(null);

    const enEdicion = this.editando();
    const peticion = enEdicion
      ? this.servicio.actualizar(enEdicion.id, datos)
      : this.servicio.crear(datos);

    peticion.subscribe({
      next: () => {
        this.guardando.set(false);
        this.cerrarFormulario();
        this.cargar();
      },
      error: (e: HttpErrorResponse) => {
        this.guardando.set(false);
        this.errorFormulario.set(interpretarError(e));
      },
    });
  }

  protected alternarEstado(proveedor: ProveedorOut): void {
    this.error.set(null);
    this.servicio.cambiarEstado(proveedor.id, !proveedor.activo).subscribe({
      next: (actualizado) =>
        this.proveedores.update((lista) =>
          lista.map((p) => (p.id === actualizado.id ? actualizado : p)),
        ),
      error: (e: HttpErrorResponse) => this.error.set(interpretarError(e)),
    });
  }
}
