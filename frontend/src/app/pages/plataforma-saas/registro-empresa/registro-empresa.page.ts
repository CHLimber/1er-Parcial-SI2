import { HttpErrorResponse } from '@angular/common/http';
import { Component, ElementRef, OnInit, computed, inject, signal, viewChild } from '@angular/core';
import { AbstractControl, FormBuilder, ReactiveFormsModule, ValidationErrors, Validators } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { Observable, of, switchMap, tap } from 'rxjs';

import { AuthService } from '../../../core/acceso-y-organizacion/auth/auth.service';
import { PlanOut } from '../../../core/plataforma-saas/saas/saas.models';
import { SaasService } from '../../../core/plataforma-saas/saas/saas.service';
import { interpretarError } from '../../../shared/errores';
import { ListaRequisitosPassword } from '../../../shared/lista-requisitos-password/lista-requisitos-password';
import { passwordSeguraValidator } from '../../../shared/validacion-password';

// Espejo de la enum ciudad_bo del esquema (db/01_schema.sql).
const CIUDADES = [
  ['SANTA_CRUZ', 'Santa Cruz'],
  ['LA_PAZ', 'La Paz'],
  ['EL_ALTO', 'El Alto'],
  ['COCHABAMBA', 'Cochabamba'],
  ['SUCRE', 'Sucre'],
  ['ORURO', 'Oruro'],
  ['POTOSI', 'Potosí'],
  ['TARIJA', 'Tarija'],
  ['TRINIDAD', 'Trinidad'],
  ['COBIJA', 'Cobija'],
] as const;

const MESES = [1, 3, 6, 12] as const;

type Controles = 'plan' | 'nombre' | 'razonSocial' | 'nit' | 'slug' | 'telefono' | 'sucursalCodigo'
  | 'sucursalNombre' | 'sucursalCiudad' | 'sucursalDireccion' | 'nombreAdmin' | 'apellidoAdmin'
  | 'email' | 'password' | 'confirmarPassword';

interface Paso {
  titulo: string;
  corto: string;
  /** campos que se validan antes de dejar pasar al siguiente (el ultimo paso no valida nada) */
  campos: Controles[];
}

const PASOS: Paso[] = [
  { titulo: 'Elegí tu plan', corto: 'Plan', campos: ['plan'] },
  { titulo: 'Datos de tu empresa', corto: 'Empresa', campos: ['nombre', 'razonSocial', 'nit', 'slug', 'telefono'] },
  {
    titulo: 'Tu primera sucursal',
    corto: 'Sucursal',
    campos: ['sucursalCodigo', 'sucursalNombre', 'sucursalCiudad', 'sucursalDireccion'],
  },
  {
    titulo: 'Cuenta de administración',
    corto: 'Cuenta',
    campos: ['nombreAdmin', 'apellidoAdmin', 'email', 'password', 'confirmarPassword'],
  },
  { titulo: 'Confirmá y pagá', corto: 'Pago', campos: [] },
];

function passwordsIgualesValidator(control: AbstractControl): ValidationErrors | null {
  const password = control.get('password')?.value;
  const confirmarPassword = control.get('confirmarPassword')?.value;
  return password === confirmarPassword ? null : { passwordsDistintos: true };
}

/** "Boutique Sol" -> "boutique-sol": el identificador (slug) de la tienda en la URL y el header. */
function aSlug(texto: string): string {
  return texto
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40);
}

/**
 * Autoregistro de una empresa (CU01, pagina publica) como asistente de 5 pasos: plan, empresa,
 * sucursal, cuenta y pago. El ultimo paso cobra de verdad con Stripe: recien ahi se crea la
 * empresa (pendiente de pago), se inicia sesion con las credenciales cargadas y se redirige al
 * Checkout; al volver, Mi suscripcion confirma el pago y activa el plan. Si algo falla despues de
 * crear la empresa, un reintento no la vuelve a crear (`registrada`).
 */
@Component({
  selector: 'app-registro-empresa-page',
  standalone: true,
  imports: [ReactiveFormsModule, RouterLink, ListaRequisitosPassword],
  templateUrl: './registro-empresa.page.html',
  styleUrls: ['../../acceso-y-organizacion/registro/registro.page.css', './registro-empresa.page.css'],
})
export class RegistroEmpresaPage implements OnInit {
  private readonly fb = inject(FormBuilder);
  private readonly saas = inject(SaasService);
  private readonly auth = inject(AuthService);
  private readonly ruta = inject(ActivatedRoute);
  private readonly titulo = viewChild<ElementRef<HTMLElement>>('titulo');

  protected readonly pasos = PASOS;
  protected readonly ciudades = CIUDADES;
  protected readonly opcionesMeses = MESES;

  protected readonly paso = signal(0);
  protected readonly planes = signal<PlanOut[]>([]);
  protected readonly cargando = signal(false);
  protected readonly errorMensaje = signal<string | null>(null);
  protected readonly mostrarPassword = signal(false);
  protected readonly meses = signal<number>(1);
  /** La empresa ya existe: un reintento de pago no vuelve a registrarla. */
  protected readonly registrada = signal(false);
  protected readonly esUltimo = computed(() => this.paso() === PASOS.length - 1);
  /** Mientras la persona no edite el identificador a mano, sigue al nombre de la empresa. */
  private slugEditado = false;

  protected readonly form = this.fb.nonNullable.group(
    {
      plan: ['', [Validators.required]],
      nombre: ['', [Validators.required, Validators.minLength(2), Validators.maxLength(120)]],
      razonSocial: ['', [Validators.required, Validators.minLength(2), Validators.maxLength(180)]],
      nit: ['', [Validators.required, Validators.minLength(3), Validators.maxLength(30)]],
      slug: ['', [Validators.required, Validators.pattern(/^[a-z0-9][a-z0-9-]{1,38}$/)]],
      telefono: [''],
      sucursalCodigo: ['', [Validators.required, Validators.minLength(2), Validators.maxLength(20)]],
      sucursalNombre: ['Casa central', [Validators.required, Validators.minLength(2), Validators.maxLength(120)]],
      sucursalCiudad: ['SANTA_CRUZ', [Validators.required]],
      sucursalDireccion: ['', [Validators.required, Validators.minLength(3), Validators.maxLength(250)]],
      nombreAdmin: ['', [Validators.required, Validators.maxLength(80)]],
      apellidoAdmin: ['', [Validators.required, Validators.maxLength(80)]],
      email: ['', [Validators.required, Validators.email]],
      password: ['', [Validators.required, passwordSeguraValidator]],
      confirmarPassword: ['', [Validators.required]],
    },
    { validators: passwordsIgualesValidator },
  );

  private readonly codigoPlan = signal('');
  protected readonly planElegido = computed(() => this.planes().find((p) => p.codigo === this.codigoPlan()) ?? null);
  protected readonly total = computed(() => Number(this.planElegido()?.precio_mensual ?? 0) * this.meses());

  ngOnInit(): void {
    const elegido = this.ruta.snapshot.queryParamMap.get('plan')?.toUpperCase() ?? '';
    this.saas.planes().subscribe({
      next: (planes) => {
        this.planes.set(planes);
        const existe = planes.some((p) => p.codigo === elegido);
        this.form.controls.plan.setValue(existe ? elegido : (planes[0]?.codigo ?? ''));
      },
      error: () => this.errorMensaje.set('No se pudieron cargar los planes. Recargá la página.'),
    });

    this.form.controls.plan.valueChanges.subscribe((codigo) => this.codigoPlan.set(codigo));
    this.form.controls.nombre.valueChanges.subscribe((nombre) => {
      if (!this.slugEditado) this.form.controls.slug.setValue(aSlug(nombre));
    });
  }

  protected slugEscrito(): void {
    this.slugEditado = true;
  }

  protected alternarPassword(): void {
    this.mostrarPassword.update((valor) => !valor);
  }

  protected elegirPlan(codigo: string): void {
    this.form.controls.plan.setValue(codigo);
  }

  protected precio(plan: PlanOut | null): string {
    return `Bs ${Number(plan?.precio_mensual ?? 0).toFixed(0)}`;
  }

  protected bs(valor: number): string {
    return `Bs ${valor.toFixed(2)}`;
  }

  protected nombreCiudad(codigo: string): string {
    return CIUDADES.find((c) => c[0] === codigo)?.[1] ?? codigo;
  }

  /** Resumen de topes del plan para las tarjetas del primer paso. */
  protected topes(plan: PlanOut): string {
    const n = (v: number | null, uno: string, varios: string) => (v === null ? `${varios} sin límite` : `${v} ${v === 1 ? uno : varios}`);
    return [
      n(plan.max_sucursales, 'sucursal', 'sucursales'),
      n(plan.max_empleados, 'persona', 'personas'),
      n(plan.max_cajas, 'caja', 'cajas'),
    ].join(' · ');
  }

  // --- navegacion del asistente --------------------------------------------------------------

  /** El paso `i` es valido si todos sus campos lo son (y, en la cuenta, las claves coinciden). */
  private pasoValido(i: number): boolean {
    const campos = PASOS[i].campos;
    campos.forEach((c) => this.form.controls[c].markAsTouched());
    if (campos.some((c) => this.form.controls[c].invalid)) return false;
    return !(campos.includes('confirmarPassword') && this.form.errors?.['passwordsDistintos']);
  }

  protected siguiente(): void {
    if (!this.pasoValido(this.paso())) return;
    this.irA(this.paso() + 1);
  }

  protected atras(): void {
    this.irA(this.paso() - 1);
  }

  /** Volver a un paso ya completado desde el indicador o desde "Editar" del resumen. */
  protected volverA(i: number): void {
    if (i < this.paso() && !this.cargando()) this.irA(i);
  }

  private irA(i: number): void {
    this.errorMensaje.set(null);
    this.paso.set(Math.min(Math.max(i, 0), PASOS.length - 1));
    // el foco al titulo del paso: lo anuncia el lector de pantalla y deja el teclado ahi
    queueMicrotask(() => this.titulo()?.nativeElement.focus());
  }

  /** Enter dentro del formulario avanza; solo en el ultimo paso cobra. */
  protected enviar(): void {
    if (this.esUltimo()) this.pagar();
    else this.siguiente();
  }

  // --- registro y pago -----------------------------------------------------------------------

  private pagar(): void {
    // por si se llego al ultimo paso sin pasar por alguno (no deberia): se valida todo
    const invalido = PASOS.findIndex((_, i) => i < PASOS.length - 1 && !this.pasoValido(i));
    if (invalido >= 0) {
      this.irA(invalido);
      return;
    }

    this.cargando.set(true);
    this.errorMensaje.set(null);
    const f = this.form.getRawValue();

    const registro$: Observable<unknown> = this.registrada()
      ? of(null)
      : this.saas.registrarEmpresaPublica({
          slug: f.slug,
          plan_codigo: f.plan,
          nombre: f.nombre.trim(),
          razon_social: f.razonSocial.trim(),
          nit: f.nit.trim(),
          email: f.email,
          telefono: f.telefono.trim() || null,
          administrador: {
            email: f.email,
            nombre: f.nombreAdmin.trim(),
            apellido: f.apellidoAdmin.trim(),
            password: f.password,
          },
          sucursal: {
            codigo: f.sucursalCodigo.trim(),
            nombre: f.sucursalNombre.trim(),
            ciudad: f.sucursalCiudad,
            direccion: f.sucursalDireccion.trim(),
          },
        });

    registro$
      .pipe(
        tap(() => this.registrada.set(true)),
        // entrar con las credenciales recien creadas (pasa por el login normal, con su bloqueo
        // de intentos); si ya hay sesion de un intento anterior, se reusa
        switchMap((): Observable<unknown> =>
          this.auth.estaAutenticado() ? of(null) : this.auth.iniciarSesion({ email: f.email, password: f.password }),
        ),
        switchMap(() => this.saas.iniciarPago({ plan_codigo: f.plan, meses: this.meses() })),
      )
      .subscribe({
        next: (checkout) => (window.location.href = checkout.url_pago),
        error: (error: HttpErrorResponse) => {
          this.cargando.set(false);
          this.errorMensaje.set(this.interpretarError(error));
        },
      });
  }

  private interpretarError(error: HttpErrorResponse): string {
    if (error.status === 0) return 'No se pudo conectar con el servidor. Verificá tu conexión.';
    const base = interpretarError(error, 'Ocurrió un error inesperado. Intentá de nuevo.');
    return this.registrada()
      ? `${base} Tu empresa ya quedó registrada: podés reintentar el pago o hacerlo después desde Mi suscripción.`
      : base;
  }
}
