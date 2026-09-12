import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';

import { AuthService } from '../../core/auth/auth.service';
import { SucursalOut } from '../../core/sucursales/sucursales.models';
import { SucursalesService } from '../../core/sucursales/sucursales.service';
import {
  CARGOS,
  CargoEmpleado,
  PermisoOut,
  RolOut,
  UsuarioAdminOut,
} from '../../core/usuarios/usuarios-admin.models';
import { UsuariosAdminService } from '../../core/usuarios/usuarios-admin.service';
import { interpretarError } from '../../shared/errores';
import { PanelShell } from '../../shared/panel/panel-shell';

interface GrupoPermisos {
  modulo: string;
  permisos: PermisoOut[];
}

/** CU13 - Gestionar Usuarios y Roles. */
@Component({
  selector: 'app-panel-usuarios-page',
  standalone: true,
  imports: [PanelShell, ReactiveFormsModule],
  templateUrl: './panel-usuarios.page.html',
  styleUrls: ['../../shared/panel/panel-comun.css', './panel-usuarios.page.css'],
})
export class PanelUsuariosPage implements OnInit {
  private readonly servicio = inject(UsuariosAdminService);
  private readonly sucursalesService = inject(SucursalesService);
  private readonly fb = inject(FormBuilder);
  protected readonly auth = inject(AuthService);

  protected readonly cargos = CARGOS;
  protected solapa: 'usuarios' | 'roles' = 'usuarios';

  protected readonly puedeGestionarUsuarios = this.auth.tienePermiso('usuarios.gestionar');
  protected readonly puedeGestionarRoles = this.auth.tienePermiso('roles.gestionar');
  protected readonly puedeVerRoles = this.auth.tienePermiso('roles.ver', 'roles.gestionar');

  // --- usuarios ---
  protected readonly cargando = signal(true);
  protected readonly usuarios = signal<UsuarioAdminOut[]>([]);
  protected readonly error = signal<string | null>(null);
  protected busqueda = '';
  protected filtroTipo: '' | 'CLIENTE' | 'STAFF' = '';
  protected filtroEstado: '' | 'true' | 'false' = '';

  protected readonly sucursales = signal<SucursalOut[]>([]);
  protected readonly roles = signal<RolOut[]>([]);
  protected readonly permisos = signal<PermisoOut[]>([]);

  protected readonly formularioAbierto = signal(false);
  protected readonly editando = signal<UsuarioAdminOut | null>(null);
  protected readonly guardando = signal(false);
  protected readonly errorFormulario = signal<string | null>(null);
  protected readonly avisoFormulario = signal<string | null>(null);

  protected readonly formStaff = this.fb.nonNullable.group({
    nombre: ['', [Validators.required, Validators.maxLength(80)]],
    apellido: ['', [Validators.required, Validators.maxLength(80)]],
    email: ['', [Validators.required, Validators.email]],
    telefono: [''],
    password: [''],
    rol_id: [0, [Validators.required, Validators.min(1)]],
    sucursal_id: ['', [Validators.required]],
    cargo: ['VENDEDOR' as CargoEmpleado, [Validators.required]],
    ci: [''],
    fecha_ingreso: [''],
  });

  protected readonly formPassword = this.fb.nonNullable.group({
    password: ['', [Validators.required, Validators.minLength(8)]],
  });
  protected readonly passwordAbierto = signal<UsuarioAdminOut | null>(null);

  // --- roles ---
  protected readonly rolSeleccionado = signal<RolOut | null>(null);
  protected readonly permisosMarcados = signal<Set<number>>(new Set());
  protected readonly guardandoRol = signal(false);
  protected readonly errorRol = signal<string | null>(null);
  protected readonly avisoRol = signal<string | null>(null);

  protected readonly formRol = this.fb.nonNullable.group({
    nombre: ['', [Validators.required, Validators.maxLength(60)]],
    descripcion: [''],
  });

  protected readonly grupos = computed<GrupoPermisos[]>(() => {
    const porModulo = new Map<string, PermisoOut[]>();
    for (const permiso of this.permisos()) {
      const lista = porModulo.get(permiso.modulo) ?? [];
      lista.push(permiso);
      porModulo.set(permiso.modulo, lista);
    }
    return [...porModulo.entries()].map(([modulo, permisos]) => ({ modulo, permisos }));
  });

  ngOnInit(): void {
    this.cargarUsuarios();
    this.sucursalesService.listarSucursales().subscribe({
      next: (sucursales) => this.sucursales.set(sucursales),
      error: () => this.sucursales.set([]),
    });
    if (this.puedeVerRoles) {
      this.cargarRoles();
      this.servicio.listarPermisos().subscribe({
        next: (permisos) => this.permisos.set(permisos),
        error: () => this.permisos.set([]),
      });
    }
  }

  // ------------------------------------------------------------------
  //  USUARIOS
  // ------------------------------------------------------------------

  protected cargarUsuarios(): void {
    this.cargando.set(true);
    this.error.set(null);
    const activo = this.filtroEstado === '' ? null : this.filtroEstado === 'true';
    this.servicio.listarUsuarios(this.busqueda || null, this.filtroTipo || null, activo).subscribe({
      next: (usuarios) => {
        this.usuarios.set(usuarios);
        this.cargando.set(false);
      },
      error: (e: HttpErrorResponse) => {
        this.error.set(interpretarError(e, 'No se pudo cargar el padrón de usuarios.'));
        this.cargando.set(false);
      },
    });
  }

  protected nuevoStaff(): void {
    this.editando.set(null);
    this.errorFormulario.set(null);
    this.avisoFormulario.set(null);
    this.formStaff.reset({
      nombre: '',
      apellido: '',
      email: '',
      telefono: '',
      password: '',
      rol_id: this.roles()[0]?.id ?? 0,
      sucursal_id: this.sucursales()[0]?.id ?? '',
      cargo: 'VENDEDOR',
      ci: '',
      fecha_ingreso: '',
    });
    this.formStaff.controls.password.setValidators([Validators.required, Validators.minLength(8)]);
    this.formStaff.controls.password.updateValueAndValidity();
    this.formularioAbierto.set(true);
  }

  protected editarUsuario(usuario: UsuarioAdminOut): void {
    this.editando.set(usuario);
    this.errorFormulario.set(null);
    this.avisoFormulario.set(
      usuario.tipo === 'CLIENTE'
        ? 'De un cliente solo se corrigen los datos de contacto: el esquema no le permite tener rol operativo.'
        : null,
    );
    this.formStaff.reset({
      nombre: usuario.nombre,
      apellido: usuario.apellido,
      email: usuario.email,
      telefono: usuario.telefono ?? '',
      password: '',
      rol_id: usuario.rol_id ?? 0,
      sucursal_id: usuario.empleado?.sucursal_id ?? this.sucursales()[0]?.id ?? '',
      cargo: usuario.empleado?.cargo ?? 'VENDEDOR',
      ci: usuario.empleado?.ci ?? '',
      fecha_ingreso: usuario.empleado?.fecha_ingreso ?? '',
    });
    this.formStaff.controls.password.clearValidators();
    this.formStaff.controls.password.updateValueAndValidity();
    this.formularioAbierto.set(true);
  }

  protected cerrarFormulario(): void {
    this.formularioAbierto.set(false);
    this.editando.set(null);
  }

  protected get editandoCliente(): boolean {
    return this.editando()?.tipo === 'CLIENTE';
  }

  protected guardarUsuario(): void {
    const enEdicion = this.editando();
    const crudo = this.formStaff.getRawValue();

    if (enEdicion?.tipo === 'CLIENTE') {
      const camposCliente = ['nombre', 'apellido', 'email'] as const;
      if (camposCliente.some((campo) => this.formStaff.controls[campo].invalid)) {
        this.formStaff.markAllAsTouched();
        return;
      }
      this.guardando.set(true);
      this.errorFormulario.set(null);
      this.servicio
        .actualizarCliente(enEdicion.id, {
          email: crudo.email.trim(),
          nombre: crudo.nombre.trim(),
          apellido: crudo.apellido.trim(),
          telefono: crudo.telefono.trim() || null,
        })
        .subscribe({
          next: () => {
            this.guardando.set(false);
            this.cerrarFormulario();
            this.cargarUsuarios();
          },
          error: (e: HttpErrorResponse) => {
            this.guardando.set(false);
            this.errorFormulario.set(interpretarError(e));
          },
        });
      return;
    }

    if (this.formStaff.invalid) {
      this.formStaff.markAllAsTouched();
      return;
    }

    const comunes = {
      email: crudo.email.trim(),
      nombre: crudo.nombre.trim(),
      apellido: crudo.apellido.trim(),
      telefono: crudo.telefono.trim() || null,
      rol_id: Number(crudo.rol_id),
      sucursal_id: crudo.sucursal_id,
      cargo: crudo.cargo,
      ci: crudo.ci.trim() || null,
      fecha_ingreso: crudo.fecha_ingreso || null,
    };

    this.guardando.set(true);
    this.errorFormulario.set(null);

    const peticion = enEdicion
      ? this.servicio.actualizarStaff(enEdicion.id, comunes)
      : this.servicio.crearStaff({ ...comunes, password: crudo.password });

    peticion.subscribe({
      next: () => {
        this.guardando.set(false);
        this.cerrarFormulario();
        this.cargarUsuarios();
        this.cargarRoles();
      },
      error: (e: HttpErrorResponse) => {
        this.guardando.set(false);
        this.errorFormulario.set(interpretarError(e));
      },
    });
  }

  protected alternarEstadoUsuario(usuario: UsuarioAdminOut): void {
    this.error.set(null);
    this.servicio.cambiarEstado(usuario.id, !usuario.activo).subscribe({
      next: (actualizado) =>
        this.usuarios.update((lista) => lista.map((u) => (u.id === actualizado.id ? actualizado : u))),
      error: (e: HttpErrorResponse) => this.error.set(interpretarError(e)),
    });
  }

  protected abrirPassword(usuario: UsuarioAdminOut): void {
    this.passwordAbierto.set(usuario);
    this.formPassword.reset({ password: '' });
    this.errorFormulario.set(null);
    this.avisoFormulario.set(null);
  }

  protected guardarPassword(): void {
    const usuario = this.passwordAbierto();
    if (!usuario || this.formPassword.invalid) {
      this.formPassword.markAllAsTouched();
      return;
    }

    this.guardando.set(true);
    this.errorFormulario.set(null);
    this.servicio.restablecerPassword(usuario.id, this.formPassword.getRawValue().password).subscribe({
      next: () => {
        this.guardando.set(false);
        this.passwordAbierto.set(null);
        this.avisoFormulario.set(`Contraseña de ${usuario.email} restablecida.`);
      },
      error: (e: HttpErrorResponse) => {
        this.guardando.set(false);
        this.errorFormulario.set(interpretarError(e));
      },
    });
  }

  // ------------------------------------------------------------------
  //  ROLES Y PERMISOS
  // ------------------------------------------------------------------

  protected cargarRoles(): void {
    if (!this.puedeVerRoles) return;
    this.servicio.listarRoles().subscribe({
      next: (roles) => {
        this.roles.set(roles);
        const actual = this.rolSeleccionado();
        if (actual) {
          const refrescado = roles.find((r) => r.id === actual.id) ?? null;
          this.rolSeleccionado.set(refrescado);
          this.permisosMarcados.set(new Set(refrescado?.permisos ?? []));
        }
      },
      error: (e: HttpErrorResponse) => this.errorRol.set(interpretarError(e)),
    });
  }

  protected seleccionarRol(rol: RolOut): void {
    this.rolSeleccionado.set(rol);
    this.permisosMarcados.set(new Set(rol.permisos));
    this.errorRol.set(null);
    this.avisoRol.set(null);
    this.formRol.reset({ nombre: rol.nombre, descripcion: rol.descripcion ?? '' });
  }

  protected nuevoRol(): void {
    this.rolSeleccionado.set(null);
    this.permisosMarcados.set(new Set());
    this.errorRol.set(null);
    this.avisoRol.set(null);
    this.formRol.reset({ nombre: '', descripcion: '' });
  }

  protected estaMarcado(permisoId: number): boolean {
    return this.permisosMarcados().has(permisoId);
  }

  protected alternarPermiso(permisoId: number): void {
    this.permisosMarcados.update((actual) => {
      const copia = new Set(actual);
      if (copia.has(permisoId)) copia.delete(permisoId);
      else copia.add(permisoId);
      return copia;
    });
  }

  protected guardarRol(): void {
    if (this.formRol.invalid) {
      this.formRol.markAllAsTouched();
      return;
    }

    const crudo = this.formRol.getRawValue();
    const datos = { nombre: crudo.nombre.trim(), descripcion: crudo.descripcion.trim() || null };
    const seleccionado = this.rolSeleccionado();

    this.guardandoRol.set(true);
    this.errorRol.set(null);
    this.avisoRol.set(null);

    const peticion = seleccionado
      ? this.servicio.actualizarRol(seleccionado.id, datos)
      : this.servicio.crearRol(datos);

    peticion.subscribe({
      next: (rol) => {
        this.guardandoRol.set(false);
        this.seleccionarRol(rol);
        this.cargarRoles();
        this.avisoRol.set('Rol guardado.');
      },
      error: (e: HttpErrorResponse) => {
        this.guardandoRol.set(false);
        this.errorRol.set(interpretarError(e));
      },
    });
  }

  protected guardarPermisos(): void {
    const rol = this.rolSeleccionado();
    if (!rol) return;

    this.guardandoRol.set(true);
    this.errorRol.set(null);
    this.avisoRol.set(null);
    this.servicio.asignarPermisos(rol.id, [...this.permisosMarcados()]).subscribe({
      next: (actualizado) => {
        this.guardandoRol.set(false);
        this.seleccionarRol(actualizado);
        this.cargarRoles();
        this.avisoRol.set('Permisos actualizados. Quien tenga este rol los verá al volver a entrar.');
        // si el admin se toco sus propios permisos, que la UI se entere ya
        this.auth.refrescarSesion().subscribe({ error: () => undefined });
      },
      error: (e: HttpErrorResponse) => {
        this.guardandoRol.set(false);
        this.errorRol.set(interpretarError(e));
      },
    });
  }

  protected eliminarRol(): void {
    const rol = this.rolSeleccionado();
    if (!rol) return;

    this.guardandoRol.set(true);
    this.errorRol.set(null);
    this.servicio.eliminarRol(rol.id).subscribe({
      next: () => {
        this.guardandoRol.set(false);
        this.nuevoRol();
        this.cargarRoles();
      },
      error: (e: HttpErrorResponse) => {
        this.guardandoRol.set(false);
        this.errorRol.set(interpretarError(e));
      },
    });
  }

  // ------------------------------------------------------------------

  protected nombreRol(rolId: number): string {
    return this.roles().find((rol) => rol.id === rolId)?.nombre ?? '—';
  }

  protected fechaCorta(valor: string | null): string {
    return valor ? valor.slice(0, 10) : '—';
  }
}
