import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { AuthService } from '../../../core/acceso-y-organizacion/auth/auth.service';
import { EmpresaIn, EmpresaOut, PlanIn, PlanOut } from '../../../core/plataforma-saas/saas/saas.models';
import { SaasService } from '../../../core/plataforma-saas/saas/saas.service';
import { interpretarError } from '../../../shared/errores';
import { PanelShell } from '../../../shared/panel/panel-shell';

const CIUDADES = ['SANTA_CRUZ', 'LA_PAZ', 'EL_ALTO', 'COCHABAMBA', 'SUCRE', 'ORURO', 'POTOSI', 'TARIJA', 'TRINIDAD', 'COBIJA'];

function empresaVacia(): EmpresaIn {
  return {
    slug: '',
    nombre: '',
    razon_social: '',
    nit: '',
    email: '',
    telefono: '',
    plan_codigo: 'BASICO',
    dias_prueba: 14,
    administrador: { email: '', nombre: '', apellido: '', password: '' },
    sucursal: { codigo: '', nombre: '', ciudad: 'LA_PAZ', direccion: '' },
  };
}

/**
 * Administracion de la plataforma SaaS (rol SUPERADMIN): empresas contratantes (CU01 registrar
 * con su administrador, CU02 asignar/cambiar plan con fechas, CU05 renovar sin cobro real,
 * suspender/reactivar) y configuracion de los planes (CU03: precio, topes y funciones, que rigen
 * en el request siguiente para todas las empresas del plan).
 */
@Component({
  selector: 'app-panel-empresas-page',
  standalone: true,
  imports: [PanelShell, FormsModule],
  templateUrl: './panel-empresas.page.html',
  styleUrls: ['../../../shared/panel/panel-comun.css', './panel-empresas.page.css'],
})
export class PanelEmpresasPage implements OnInit {
  private readonly servicio = inject(SaasService);
  protected readonly auth = inject(AuthService);

  protected readonly ciudades = CIUDADES;
  protected solapa: 'empresas' | 'planes' = 'empresas';

  protected readonly empresas = signal<EmpresaOut[]>([]);
  protected readonly planes = signal<PlanOut[]>([]);
  protected readonly elegida = signal<EmpresaOut | null>(null);
  protected readonly cargando = signal(true);
  protected readonly ocupado = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly aviso = signal<string | null>(null);

  protected creando = false;
  protected conSucursal = true;
  protected nueva: EmpresaIn = empresaVacia();

  // asignar plan / renovar sobre la empresa elegida
  protected planAsignado = 'BASICO';
  protected estadoAsignado: 'PRUEBA' | 'ACTIVA' | 'VENCIDA' | 'CANCELADA' = 'ACTIVA';
  protected venceAsignado = '';
  protected mesesRenovar = 1;
  protected metodoRenovar: 'TRANSFERENCIA' | 'EFECTIVO' = 'TRANSFERENCIA';

  // edicion de planes (CU03)
  protected edicion: Record<string, PlanIn> = {};

  ngOnInit(): void {
    this.cargar();
    this.cargarPlanes();
  }

  protected cargar(seleccion?: string): void {
    this.cargando.set(true);
    this.servicio.empresas().subscribe({
      next: (empresas) => {
        this.empresas.set(empresas);
        const id = seleccion ?? this.elegida()?.id;
        this.elegir(empresas.find((e) => e.id === id) ?? null);
        this.cargando.set(false);
      },
      error: (e: HttpErrorResponse) => {
        this.error.set(interpretarError(e, 'No se pudieron cargar las empresas.'));
        this.cargando.set(false);
      },
    });
  }

  private cargarPlanes(): void {
    this.servicio.planes().subscribe({
      next: (planes) => {
        this.planes.set(planes);
        this.edicion = Object.fromEntries(
          planes.map((p) => {
            const { id: _id, codigo: _codigo, ...resto } = p;
            return [p.codigo, { ...resto, precio_mensual: Number(p.precio_mensual), activo: true }];
          }),
        );
      },
    });
  }

  protected elegir(empresa: EmpresaOut | null): void {
    this.elegida.set(empresa);
    if (!empresa?.suscripcion) return;
    this.planAsignado = empresa.suscripcion.plan.codigo;
    this.estadoAsignado = empresa.suscripcion.estado as 'PRUEBA' | 'ACTIVA' | 'VENCIDA' | 'CANCELADA';
    this.venceAsignado = empresa.suscripcion.vence_en.slice(0, 10);
  }

  protected registrar(): void {
    const datos: EmpresaIn = { ...this.nueva, sucursal: this.conSucursal ? this.nueva.sucursal : null };
    this.accion(this.servicio.registrarEmpresa(datos), (e) => {
      this.creando = false;
      this.nueva = empresaVacia();
      this.aviso.set(`Empresa ${e.nombre} registrada: su administrador ya puede iniciar sesión.`);
      this.cargar(e.id);
    });
  }

  protected asignarPlan(empresa: EmpresaOut): void {
    this.accion(
      this.servicio.asignarPlan(empresa.id, {
        plan_codigo: this.planAsignado,
        estado: this.estadoAsignado,
        vence_en: new Date(`${this.venceAsignado}T23:59:59`).toISOString(),
      }),
      (s) => {
        this.aviso.set(`${s.empresa}: plan ${s.plan.nombre} (${s.estado}) hasta el ${this.fecha(s.vence_en)}.`);
        this.cargar(empresa.id);
      },
    );
  }

  protected renovar(empresa: EmpresaOut): void {
    this.accion(
      this.servicio.pagoManual(empresa.id, {
        plan_codigo: this.planAsignado,
        meses: this.mesesRenovar,
        metodo: this.metodoRenovar,
      }),
      (s) => {
        this.aviso.set(`Renovación registrada: ${s.empresa} vigente hasta el ${this.fecha(s.vence_en)}.`);
        this.cargar(empresa.id);
      },
    );
  }

  protected cambiarEstado(empresa: EmpresaOut): void {
    const activa = !empresa.activa;
    if (!activa && !confirm(`¿Suspender ${empresa.nombre}? Su personal queda sin acceso y su tienda deja de verse.`)) {
      return;
    }
    this.accion(this.servicio.cambiarEstadoEmpresa(empresa.id, activa), (e) => {
      this.aviso.set(`${e.nombre} ${e.activa ? 'reactivada' : 'suspendida'}.`);
      this.cargar(e.id);
    });
  }

  protected guardarPlan(codigo: string): void {
    this.accion(this.servicio.configurarPlan(codigo, this.edicion[codigo]), (p) => {
      this.aviso.set(`Plan ${p.nombre} actualizado: rige desde ya para todas sus empresas.`);
      this.cargarPlanes();
      this.cargar();
    });
  }

  /** Corre una accion contra la API con el manejo comun de ocupado/error. */
  private accion<T>(pedido: import('rxjs').Observable<T>, alTerminar: (resultado: T) => void): void {
    this.ocupado.set(true);
    this.error.set(null);
    this.aviso.set(null);
    pedido.subscribe({
      next: (resultado) => {
        this.ocupado.set(false);
        alTerminar(resultado);
      },
      error: (e: HttpErrorResponse) => {
        this.ocupado.set(false);
        this.error.set(interpretarError(e));
      },
    });
  }

  protected tope(valor: number | null | undefined): string {
    return valor === null || valor === undefined ? '∞' : String(valor);
  }

  protected fecha(valor: string | null | undefined): string {
    return valor ? new Date(valor).toLocaleDateString('es-BO') : '—';
  }

  protected numeroONulo(valor: string | number | null): number | null {
    return valor === '' || valor === null ? null : Number(valor);
  }
}
