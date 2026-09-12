import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';

import { AuthService } from '../../core/auth/auth.service';
import { CajaOut, SucursalAdminOut, SucursalIn } from '../../core/sucursales/sucursales-admin.models';
import { SucursalesAdminService } from '../../core/sucursales/sucursales-admin.service';
import { interpretarError } from '../../shared/errores';
import { PanelShell } from '../../shared/panel/panel-shell';

/** CU12 - Gestionar Sucursales (y sus cajas). */
@Component({
  selector: 'app-panel-sucursales-page',
  standalone: true,
  imports: [PanelShell, ReactiveFormsModule],
  templateUrl: './panel-sucursales.page.html',
  styleUrls: ['../../shared/panel/panel-comun.css'],
})
export class PanelSucursalesPage implements OnInit {
  private readonly servicio = inject(SucursalesAdminService);
  private readonly fb = inject(FormBuilder);
  private readonly auth = inject(AuthService);

  protected readonly cargando = signal(true);
  protected readonly sucursales = signal<SucursalAdminOut[]>([]);
  protected readonly ciudades = signal<string[]>([]);
  protected readonly error = signal<string | null>(null);

  protected readonly formularioAbierto = signal(false);
  protected readonly editando = signal<SucursalAdminOut | null>(null);
  protected readonly guardando = signal(false);
  protected readonly errorFormulario = signal<string | null>(null);

  protected readonly seleccionada = signal<SucursalAdminOut | null>(null);
  protected readonly cajas = signal<CajaOut[]>([]);
  protected readonly errorCaja = signal<string | null>(null);
  protected readonly guardandoCaja = signal(false);

  protected readonly puedeGestionar = this.auth.tienePermiso('sucursales.gestionar');

  protected readonly form = this.fb.nonNullable.group({
    codigo: ['', [Validators.required, Validators.maxLength(20)]],
    nombre: ['', [Validators.required, Validators.maxLength(120)]],
    ciudad: ['', [Validators.required]],
    direccion: ['', [Validators.required, Validators.maxLength(250)]],
    telefono: [''],
    hora_apertura: [''],
    hora_cierre: [''],
    cantidad_vestidores: [0, [Validators.required, Validators.min(0), Validators.max(50)]],
  });

  protected readonly formCaja = this.fb.nonNullable.group({
    codigo: ['', [Validators.required, Validators.maxLength(20)]],
    nombre: ['', [Validators.required, Validators.maxLength(60)]],
  });

  ngOnInit(): void {
    this.servicio.ciudades().subscribe({
      next: (ciudades) => this.ciudades.set(ciudades),
      error: () => this.ciudades.set([]),
    });
    this.cargar();
  }

  protected cargar(): void {
    this.cargando.set(true);
    this.error.set(null);
    this.servicio.listar().subscribe({
      next: (sucursales) => {
        this.sucursales.set(sucursales);
        this.cargando.set(false);
        const actual = this.seleccionada();
        if (actual) {
          const refrescada = sucursales.find((s) => s.id === actual.id) ?? null;
          this.seleccionada.set(refrescada);
        }
      },
      error: (e: HttpErrorResponse) => {
        this.error.set(interpretarError(e, 'No se pudieron cargar las sucursales.'));
        this.cargando.set(false);
      },
    });
  }

  protected nueva(): void {
    this.editando.set(null);
    this.errorFormulario.set(null);
    this.form.reset({
      codigo: '',
      nombre: '',
      ciudad: this.ciudades()[0] ?? '',
      direccion: '',
      telefono: '',
      hora_apertura: '',
      hora_cierre: '',
      cantidad_vestidores: 0,
    });
    this.formularioAbierto.set(true);
  }

  protected editar(sucursal: SucursalAdminOut): void {
    this.editando.set(sucursal);
    this.errorFormulario.set(null);
    this.form.reset({
      codigo: sucursal.codigo,
      nombre: sucursal.nombre,
      ciudad: sucursal.ciudad,
      direccion: sucursal.direccion,
      telefono: sucursal.telefono ?? '',
      hora_apertura: this.aHoraCorta(sucursal.hora_apertura),
      hora_cierre: this.aHoraCorta(sucursal.hora_cierre),
      cantidad_vestidores: sucursal.cantidad_vestidores,
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
    const datos: SucursalIn = {
      codigo: crudo.codigo.trim().toUpperCase(),
      nombre: crudo.nombre.trim(),
      ciudad: crudo.ciudad,
      direccion: crudo.direccion.trim(),
      telefono: crudo.telefono.trim() || null,
      latitud: null,
      longitud: null,
      hora_apertura: crudo.hora_apertura || null,
      hora_cierre: crudo.hora_cierre || null,
      cantidad_vestidores: Number(crudo.cantidad_vestidores),
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

  protected alternarEstado(sucursal: SucursalAdminOut): void {
    this.error.set(null);
    this.servicio.cambiarEstado(sucursal.id, !sucursal.activa).subscribe({
      next: () => this.cargar(),
      error: (e: HttpErrorResponse) => this.error.set(interpretarError(e)),
    });
  }

  protected verCajas(sucursal: SucursalAdminOut): void {
    this.seleccionada.set(sucursal);
    this.errorCaja.set(null);
    this.formCaja.reset({ codigo: '', nombre: '' });
    this.cajas.set([]);
    this.servicio.listarCajas(sucursal.id).subscribe({
      next: (cajas) => this.cajas.set(cajas),
      error: (e: HttpErrorResponse) => this.errorCaja.set(interpretarError(e)),
    });
  }

  protected cerrarCajas(): void {
    this.seleccionada.set(null);
    this.cajas.set([]);
  }

  protected agregarCaja(): void {
    const sucursal = this.seleccionada();
    if (!sucursal || this.formCaja.invalid) {
      this.formCaja.markAllAsTouched();
      return;
    }

    const crudo = this.formCaja.getRawValue();
    this.guardandoCaja.set(true);
    this.errorCaja.set(null);
    this.servicio
      .crearCaja(sucursal.id, { codigo: crudo.codigo.trim().toUpperCase(), nombre: crudo.nombre.trim() })
      .subscribe({
        next: (caja) => {
          this.guardandoCaja.set(false);
          this.cajas.update((lista) => [...lista, caja]);
          this.formCaja.reset({ codigo: '', nombre: '' });
          this.cargar();
        },
        error: (e: HttpErrorResponse) => {
          this.guardandoCaja.set(false);
          this.errorCaja.set(interpretarError(e));
        },
      });
  }

  protected alternarCaja(caja: CajaOut): void {
    this.errorCaja.set(null);
    this.servicio.cambiarEstadoCaja(caja.id, !caja.activa).subscribe({
      next: (actualizada) => {
        this.cajas.update((lista) => lista.map((c) => (c.id === actualizada.id ? actualizada : c)));
        this.cargar();
      },
      error: (e: HttpErrorResponse) => this.errorCaja.set(interpretarError(e)),
    });
  }

  protected etiquetaCiudad(ciudad: string): string {
    return ciudad.replace(/_/g, ' ');
  }

  /** Postgres devuelve TIME como "09:00:00"; el input[type=time] quiere "09:00". */
  protected aHoraCorta(hora: string | null): string {
    return hora ? hora.slice(0, 5) : '';
  }
}
