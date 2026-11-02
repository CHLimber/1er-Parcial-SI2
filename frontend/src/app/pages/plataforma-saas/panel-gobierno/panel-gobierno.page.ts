import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';

import { AuthService } from '../../../core/acceso-y-organizacion/auth/auth.service';
import { PermisoOut } from '../../../core/acceso-y-organizacion/usuarios/usuarios-admin.models';
import {
  CuentaOut,
  EmpresaOut,
  RolPlataformaOut,
} from '../../../core/plataforma-saas/saas/saas.models';
import { SaasService } from '../../../core/plataforma-saas/saas/saas.service';
import { interpretarError } from '../../../shared/errores';
import { ListaRequisitosPassword } from '../../../shared/lista-requisitos-password/lista-requisitos-password';
import { PanelShell } from '../../../shared/panel/panel-shell';
import { passwordSeguraValidator } from '../../../shared/validacion-password';

type AccionCrud = 'leer' | 'crear' | 'actualizar' | 'eliminar';

const ACCIONES: { accion: AccionCrud; etiqueta: string }[] = [
  { accion: 'leer', etiqueta: 'Leer' },
  { accion: 'crear', etiqueta: 'Crear' },
  { accion: 'actualizar', etiqueta: 'Actualizar' },
  { accion: 'eliminar', etiqueta: 'Eliminar' },
];

/** Modulos que son solo de la plataforma: el backend no deja asignarlos a ningun otro rol. */
const MODULOS_PLATAFORMA = ['empresas', 'planes'];

const ORDEN_MODULOS = [
  'usuarios',
  'roles',
  'catalogo',
  'proveedores',
  'sucursales',
  'inventario',
  'recepciones',
  'reservas',
  'caja',
  'ventas',
  'reportes',
];

interface FilaMatriz {
  modulo: string;
  celdas: (PermisoOut | null)[];
}

/**
 * Gobierno de la plataforma (SUPERADMIN): las cuentas de todas las empresas (personal, clientas y
 * equipo de la plataforma) y la matriz de roles y permisos. Los roles del sistema los comparten
 * todas las empresas: lo que se cambia aca llega a todas.
 */
@Component({
  selector: 'app-panel-gobierno-page',
  standalone: true,
  imports: [PanelShell, ReactiveFormsModule, ListaRequisitosPassword],
  templateUrl: './panel-gobierno.page.html',
  styleUrls: ['../../../shared/panel/panel-comun.css', './panel-gobierno.page.css'],
})
export class PanelGobiernoPage implements OnInit {
  private readonly servicio = inject(SaasService);
  private readonly fb = inject(FormBuilder);
  protected readonly auth = inject(AuthService);

  protected solapa: 'cuentas' | 'roles' = 'cuentas';
  protected readonly puedeEditar = this.auth.tienePermiso('empresas.actualizar');

  protected readonly empresas = signal<EmpresaOut[]>([]);
  protected readonly roles = signal<RolPlataformaOut[]>([]);
  protected readonly permisos = signal<PermisoOut[]>([]);

  // --- cuentas ---
  protected readonly cargando = signal(true);
  protected readonly cuentas = signal<CuentaOut[]>([]);
  protected readonly error = signal<string | null>(null);
  protected readonly aviso = signal<string | null>(null);
  protected busqueda = '';
  protected filtroTipo: '' | 'CLIENTE' | 'STAFF' = '';
  protected filtroEmpresa = '';
  protected filtroEstado: '' | 'true' | 'false' = '';

  protected readonly editando = signal<CuentaOut | null>(null);
  protected readonly passwordDe = signal<CuentaOut | null>(null);
  protected readonly equipoAbierto = signal(false);
  protected readonly guardando = signal(false);
  protected readonly errorFormulario = signal<string | null>(null);

  protected readonly formCuenta = this.fb.nonNullable.group({
    nombre: ['', [Validators.required, Validators.maxLength(80)]],
    apellido: ['', [Validators.required, Validators.maxLength(80)]],
    email: ['', [Validators.required, Validators.email]],
    telefono: [''],
    rol_id: [0],
  });
  protected readonly formPassword = this.fb.nonNullable.group({
    password: ['', [Validators.required, passwordSeguraValidator]],
  });
  protected readonly formEquipo = this.fb.nonNullable.group({
    nombre: ['', [Validators.required, Validators.maxLength(80)]],
    apellido: ['', [Validators.required, Validators.maxLength(80)]],
    email: ['', [Validators.required, Validators.email]],
    password: ['', [Validators.required, passwordSeguraValidator]],
  });

  /** Roles que se le pueden dar a la cuenta que se edita: los del sistema (menos SUPERADMIN) y
   * los propios de SU empresa. */
  protected readonly rolesDeLaCuenta = computed(() => {
    const cuenta = this.editando();
    if (!cuenta || cuenta.empresa_id === null) return [];
    return this.roles().filter(
      (r) => r.empresa_id === cuenta.empresa_id || (r.empresa_id === null && r.nombre !== 'SUPERADMIN'),
    );
  });
  protected readonly cambiaRol = computed(() => this.rolesDeLaCuenta().length > 0);

  // --- roles ---
  protected readonly rolSeleccionado = signal<RolPlataformaOut | null>(null);
  protected readonly creandoRol = signal(false);
  protected readonly permisosMarcados = signal<Set<number>>(new Set());
  protected readonly guardandoRol = signal(false);
  protected readonly errorRol = signal<string | null>(null);
  protected readonly avisoRol = signal<string | null>(null);

  protected readonly formRol = this.fb.nonNullable.group({
    nombre: ['', [Validators.required, Validators.minLength(2), Validators.maxLength(60)]],
    descripcion: [''],
    empresa_id: [''],
  });

  protected readonly acciones = ACCIONES;

  /** Del sistema primero (compartidos), despues los propios de cada empresa. */
  protected readonly rolesDelSistema = computed(() => this.roles().filter((r) => r.empresa_id === null));
  protected readonly rolesPropios = computed(() => this.roles().filter((r) => r.empresa_id !== null));

  /** SUPERADMIN no cambia sus permisos; el resto si, y la plataforma los edita siempre. */
  protected readonly permisosEditables = computed(() => {
    const r = this.rolSeleccionado();
    return this.puedeEditar && r !== null && !(r.protegido && r.nombre === 'SUPERADMIN');
  });

  protected readonly filasMatriz = computed<FilaMatriz[]>(() => {
    const permisos = this.permisos();
    const presentes = new Set(permisos.map((p) => p.modulo));
    const conocidos = ORDEN_MODULOS.filter((m) => presentes.has(m));
    const resto = [...presentes].filter((m) => !ORDEN_MODULOS.includes(m)).sort();
    return [...conocidos, ...resto].map((modulo) => ({
      modulo,
      celdas: ACCIONES.map(({ accion }) => permisos.find((p) => p.codigo === `${modulo}.${accion}`) ?? null),
    }));
  });

  ngOnInit(): void {
    this.servicio.empresas().subscribe({ next: (e) => this.empresas.set(e), error: () => this.empresas.set([]) });
    this.servicio.permisos().subscribe({ next: (p) => this.permisos.set(p), error: () => this.permisos.set([]) });
    this.cargarRoles();
    this.cargarCuentas();
  }

  // ------------------------------------------------------------------
  //  CUENTAS
  // ------------------------------------------------------------------

  protected cargarCuentas(): void {
    this.cargando.set(true);
    this.error.set(null);
    this.servicio
      .cuentas({
        q: this.busqueda.trim() || null,
        tipo: this.filtroTipo || null,
        empresaId: this.filtroEmpresa || null,
        activo: this.filtroEstado === '' ? null : this.filtroEstado === 'true',
      })
      .subscribe({
        next: (cuentas) => {
          this.cuentas.set(cuentas);
          this.cargando.set(false);
        },
        error: (e: HttpErrorResponse) => {
          this.error.set(interpretarError(e, 'No se pudo cargar el padrón de cuentas.'));
          this.cargando.set(false);
        },
      });
  }

  protected esPropia(cuenta: CuentaOut): boolean {
    return cuenta.id === this.auth.usuario()?.id;
  }

  /** Quien es: clienta, equipo de la plataforma o personal de una empresa. */
  protected ambito(cuenta: CuentaOut): string {
    if (cuenta.tipo === 'CLIENTE') return 'Clienta';
    return cuenta.empresa_id === null ? 'Plataforma' : (cuenta.empresa ?? 'Empresa');
  }

  protected editar(cuenta: CuentaOut): void {
    this.cerrarPaneles();
    this.editando.set(cuenta);
    this.formCuenta.reset({
      nombre: cuenta.nombre,
      apellido: cuenta.apellido,
      email: cuenta.email,
      telefono: cuenta.telefono ?? '',
      rol_id: cuenta.rol_id ?? 0,
    });
  }

  protected guardarCuenta(): void {
    const cuenta = this.editando();
    if (!cuenta) return;
    if (this.formCuenta.invalid) {
      this.formCuenta.markAllAsTouched();
      return;
    }
    const v = this.formCuenta.getRawValue();
    this.guardando.set(true);
    this.errorFormulario.set(null);
    this.servicio
      .editarCuenta(cuenta.id, {
        email: v.email.trim(),
        nombre: v.nombre.trim(),
        apellido: v.apellido.trim(),
        telefono: v.telefono.trim() || null,
        rol_id: this.cambiaRol() ? Number(v.rol_id) : null,
      })
      .subscribe({
        next: () => {
          this.guardando.set(false);
          this.cerrarPaneles();
          this.aviso.set('Cuenta actualizada.');
          this.cargarCuentas();
          this.cargarRoles();
        },
        error: (e: HttpErrorResponse) => {
          this.guardando.set(false);
          this.errorFormulario.set(interpretarError(e));
        },
      });
  }

  protected alternarEstado(cuenta: CuentaOut): void {
    this.error.set(null);
    this.aviso.set(null);
    this.servicio.cambiarEstadoCuenta(cuenta.id, !cuenta.activo).subscribe({
      next: (actualizada) => this.reemplazar(actualizada),
      error: (e: HttpErrorResponse) => this.error.set(interpretarError(e)),
    });
  }

  protected desbloquear(cuenta: CuentaOut): void {
    this.error.set(null);
    this.aviso.set(null);
    this.servicio.desbloquearCuenta(cuenta.id).subscribe({
      next: (actualizada) => {
        this.reemplazar(actualizada);
        this.aviso.set(`Se quitó el bloqueo de ${cuenta.email}.`);
      },
      error: (e: HttpErrorResponse) => this.error.set(interpretarError(e)),
    });
  }

  protected abrirPassword(cuenta: CuentaOut): void {
    this.cerrarPaneles();
    this.passwordDe.set(cuenta);
    this.formPassword.reset({ password: '' });
  }

  protected guardarPassword(): void {
    const cuenta = this.passwordDe();
    if (!cuenta) return;
    if (this.formPassword.invalid) {
      this.formPassword.markAllAsTouched();
      return;
    }
    this.guardando.set(true);
    this.errorFormulario.set(null);
    this.servicio.restablecerPasswordCuenta(cuenta.id, this.formPassword.getRawValue().password).subscribe({
      next: () => {
        this.guardando.set(false);
        this.cerrarPaneles();
        this.aviso.set(`Contraseña de ${cuenta.email} restablecida y cuenta desbloqueada.`);
        this.cargarCuentas();
      },
      error: (e: HttpErrorResponse) => {
        this.guardando.set(false);
        this.errorFormulario.set(interpretarError(e));
      },
    });
  }

  protected nuevoEquipo(): void {
    this.cerrarPaneles();
    this.formEquipo.reset({ nombre: '', apellido: '', email: '', password: '' });
    this.equipoAbierto.set(true);
  }

  protected guardarEquipo(): void {
    if (this.formEquipo.invalid) {
      this.formEquipo.markAllAsTouched();
      return;
    }
    const v = this.formEquipo.getRawValue();
    this.guardando.set(true);
    this.errorFormulario.set(null);
    this.servicio
      .agregarAlEquipo({ email: v.email.trim(), nombre: v.nombre.trim(), apellido: v.apellido.trim(), password: v.password })
      .subscribe({
        next: () => {
          this.guardando.set(false);
          this.cerrarPaneles();
          this.aviso.set('Integrante del equipo de la plataforma agregado.');
          this.cargarCuentas();
        },
        error: (e: HttpErrorResponse) => {
          this.guardando.set(false);
          this.errorFormulario.set(interpretarError(e));
        },
      });
  }

  protected cerrarPaneles(): void {
    this.editando.set(null);
    this.passwordDe.set(null);
    this.equipoAbierto.set(false);
    this.errorFormulario.set(null);
  }

  private reemplazar(actualizada: CuentaOut): void {
    this.cuentas.update((lista) => lista.map((c) => (c.id === actualizada.id ? actualizada : c)));
  }

  // ------------------------------------------------------------------
  //  ROLES Y PERMISOS
  // ------------------------------------------------------------------

  protected cargarRoles(): void {
    this.servicio.roles().subscribe({
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

  protected seleccionarRol(rol: RolPlataformaOut): void {
    this.creandoRol.set(false);
    this.rolSeleccionado.set(rol);
    this.permisosMarcados.set(new Set(rol.permisos));
    this.errorRol.set(null);
    this.avisoRol.set(null);
    this.formRol.reset({ nombre: rol.nombre, descripcion: rol.descripcion ?? '', empresa_id: rol.empresa_id ?? '' });
  }

  protected nuevoRol(): void {
    this.creandoRol.set(true);
    this.rolSeleccionado.set(null);
    this.permisosMarcados.set(new Set());
    this.errorRol.set(null);
    this.avisoRol.set(null);
    this.formRol.reset({ nombre: '', descripcion: '', empresa_id: '' });
  }

  protected estaMarcado(permisoId: number): boolean {
    return this.permisosMarcados().has(permisoId);
  }

  /** Un permiso de la plataforma no se le da a ningun rol que no sea SUPERADMIN (lo exige el backend). */
  protected casillaBloqueada(permiso: PermisoOut): boolean {
    const esSuperadmin = this.rolSeleccionado()?.nombre === 'SUPERADMIN' && this.rolSeleccionado()?.protegido;
    return !this.permisosEditables() || (!esSuperadmin && MODULOS_PLATAFORMA.includes(permiso.modulo));
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
    const v = this.formRol.getRawValue();
    const descripcion = v.descripcion.trim() || null;
    const seleccionado = this.rolSeleccionado();
    this.guardandoRol.set(true);
    this.errorRol.set(null);
    this.avisoRol.set(null);

    const peticion = seleccionado
      ? this.servicio.editarRol(seleccionado.id, { nombre: v.nombre.trim(), descripcion })
      : this.servicio.crearRol({ nombre: v.nombre.trim(), descripcion, empresa_id: v.empresa_id || null });

    peticion.subscribe({
      next: (rol) => {
        this.guardandoRol.set(false);
        this.cargarRoles();
        this.seleccionarRol(rol);
        this.avisoRol.set(seleccionado ? 'Rol guardado.' : 'Rol creado. Ahora marcá sus permisos.');
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
    this.servicio.asignarPermisosRol(rol.id, [...this.permisosMarcados()]).subscribe({
      next: (actualizado) => {
        this.guardandoRol.set(false);
        this.cargarRoles();
        this.seleccionarRol(actualizado);
        this.avisoRol.set(
          rol.empresa_id === null
            ? 'Permisos actualizados para todas las empresas que usan este rol.'
            : 'Permisos actualizados.',
        );
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
        this.rolSeleccionado.set(null);
        this.cargarRoles();
      },
      error: (e: HttpErrorResponse) => {
        this.guardandoRol.set(false);
        this.errorRol.set(interpretarError(e));
      },
    });
  }

  // ------------------------------------------------------------------

  protected nombreModulo(modulo: string): string {
    return modulo.charAt(0).toUpperCase() + modulo.slice(1);
  }

  protected fechaCorta(valor: string | null): string {
    return valor ? valor.slice(0, 10) : '—';
  }
}
