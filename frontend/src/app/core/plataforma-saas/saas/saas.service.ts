import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../../environments/environment';
import { PermisoOut } from '../../acceso-y-organizacion/usuarios/usuarios-admin.models';
import {
  AsignarPlanIn,
  CheckoutSuscripcionIn,
  CheckoutSuscripcionOut,
  CuentaOut,
  CuentaUpdate,
  EmpresaDatosIn,
  EmpresaIn,
  EmpresaOut,
  EquipoIn,
  PagoManualIn,
  PagoSuscripcionOut,
  PersonalEmpresaIn,
  PersonalEmpresaOut,
  PlanIn,
  PlanOut,
  RegistroEmpresaIn,
  RolPlataformaIn,
  RolPlataformaOut,
  RolPlataformaUpdate,
  SuscripcionOut,
  TiendaOut,
} from './saas.models';

/** SaaS multi-tenant: planes, suscripcion de cada empresa y administracion de la plataforma. */
@Injectable({ providedIn: 'root' })
export class SaasService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/saas`;

  planes(): Observable<PlanOut[]> {
    return this.http.get<PlanOut[]>(`${this.base}/planes`);
  }

  /** Publico: tiendas activas para el selector de la vitrina. */
  tiendas(): Observable<TiendaOut[]> {
    return this.http.get<TiendaOut[]>(`${this.base}/tiendas`);
  }

  /** Publico: una empresa se registra sola desde la pagina de planes y queda en prueba. */
  registrarEmpresaPublica(datos: RegistroEmpresaIn): Observable<SuscripcionOut> {
    return this.http.post<SuscripcionOut>(`${this.base}/registro`, datos);
  }

  /** La de mi empresa; la plataforma pasa `empresaId`. */
  miSuscripcion(empresaId?: string | null): Observable<SuscripcionOut> {
    let params = new HttpParams();
    if (empresaId) params = params.set('empresa_id', empresaId);
    return this.http.get<SuscripcionOut>(`${this.base}/suscripcion`, { params });
  }

  pagos(empresaId?: string | null): Observable<PagoSuscripcionOut[]> {
    let params = new HttpParams();
    if (empresaId) params = params.set('empresa_id', empresaId);
    return this.http.get<PagoSuscripcionOut[]>(`${this.base}/pagos`, { params });
  }

  /** Crea el pago y devuelve la URL del Checkout hospedado de Stripe. */
  iniciarPago(datos: CheckoutSuscripcionIn): Observable<CheckoutSuscripcionOut> {
    return this.http.post<CheckoutSuscripcionOut>(`${this.base}/suscripcion/checkout`, datos);
  }

  /** Al volver del Checkout: confirma con Stripe y aplica el pago (idempotente con el webhook). */
  verificarPago(sesion: string): Observable<SuscripcionOut> {
    return this.http.post<SuscripcionOut>(`${this.base}/pagos/verificar`, null, {
      params: new HttpParams().set('sesion', sesion),
    });
  }

  // --- plataforma (SUPERADMIN) ---------------------------------------------------------------

  empresas(): Observable<EmpresaOut[]> {
    return this.http.get<EmpresaOut[]>(`${this.base}/empresas`);
  }

  registrarEmpresa(datos: EmpresaIn): Observable<EmpresaOut> {
    return this.http.post<EmpresaOut>(`${this.base}/empresas`, datos);
  }

  editarEmpresa(id: string, datos: EmpresaDatosIn): Observable<EmpresaOut> {
    return this.http.put<EmpresaOut>(`${this.base}/empresas/${id}`, datos);
  }

  cambiarEstadoEmpresa(id: string, activa: boolean): Observable<EmpresaOut> {
    return this.http.patch<EmpresaOut>(`${this.base}/empresas/${id}/estado`, { activa });
  }

  asignarPlan(id: string, datos: AsignarPlanIn): Observable<SuscripcionOut> {
    return this.http.put<SuscripcionOut>(`${this.base}/empresas/${id}/plan`, datos);
  }

  pagoManual(empresaId: string, datos: PagoManualIn): Observable<SuscripcionOut> {
    return this.http.post<SuscripcionOut>(`${this.base}/suscripciones/${empresaId}/pago-manual`, datos);
  }

  configurarPlan(codigo: string, datos: PlanIn): Observable<PlanOut> {
    return this.http.put<PlanOut>(`${this.base}/planes/${codigo}`, datos);
  }

  // --- cuentas de personal de una empresa (la plataforma las atiende) -------------------------

  personalDeEmpresa(empresaId: string): Observable<PersonalEmpresaOut[]> {
    return this.http.get<PersonalEmpresaOut[]>(`${this.base}/empresas/${empresaId}/usuarios`);
  }

  agregarAdministrador(empresaId: string, datos: PersonalEmpresaIn): Observable<PersonalEmpresaOut> {
    return this.http.post<PersonalEmpresaOut>(`${this.base}/empresas/${empresaId}/administradores`, datos);
  }

  cambiarEstadoPersonal(usuarioId: string, activo: boolean): Observable<PersonalEmpresaOut> {
    return this.http.patch<PersonalEmpresaOut>(`${this.base}/usuarios/${usuarioId}/estado`, { activo });
  }

  restablecerPasswordPersonal(usuarioId: string, password: string): Observable<void> {
    return this.http.post<void>(`${this.base}/usuarios/${usuarioId}/password`, { password });
  }

  desbloquearPersonal(usuarioId: string): Observable<PersonalEmpresaOut> {
    return this.http.post<PersonalEmpresaOut>(`${this.base}/usuarios/${usuarioId}/desbloquear`, null);
  }

  // --- gobierno de la plataforma: cuentas, roles y permisos de todas las empresas --------------

  cuentas(filtros: {
    q?: string | null;
    tipo?: 'CLIENTE' | 'STAFF' | null;
    empresaId?: string | null;
    activo?: boolean | null;
  }): Observable<CuentaOut[]> {
    let params = new HttpParams();
    if (filtros.q) params = params.set('q', filtros.q);
    if (filtros.tipo) params = params.set('tipo', filtros.tipo);
    if (filtros.empresaId) params = params.set('empresa_id', filtros.empresaId);
    if (filtros.activo !== null && filtros.activo !== undefined) params = params.set('activo', filtros.activo);
    return this.http.get<CuentaOut[]>(`${this.base}/cuentas`, { params });
  }

  agregarAlEquipo(datos: EquipoIn): Observable<CuentaOut> {
    return this.http.post<CuentaOut>(`${this.base}/equipo`, datos);
  }

  editarCuenta(id: string, datos: CuentaUpdate): Observable<CuentaOut> {
    return this.http.put<CuentaOut>(`${this.base}/cuentas/${id}`, datos);
  }

  cambiarEstadoCuenta(id: string, activo: boolean): Observable<CuentaOut> {
    return this.http.patch<CuentaOut>(`${this.base}/cuentas/${id}/estado`, { activo });
  }

  restablecerPasswordCuenta(id: string, password: string): Observable<void> {
    return this.http.post<void>(`${this.base}/cuentas/${id}/password`, { password });
  }

  desbloquearCuenta(id: string): Observable<CuentaOut> {
    return this.http.post<CuentaOut>(`${this.base}/cuentas/${id}/desbloquear`, null);
  }

  permisos(): Observable<PermisoOut[]> {
    return this.http.get<PermisoOut[]>(`${this.base}/permisos`);
  }

  roles(): Observable<RolPlataformaOut[]> {
    return this.http.get<RolPlataformaOut[]>(`${this.base}/roles`);
  }

  crearRol(datos: RolPlataformaIn): Observable<RolPlataformaOut> {
    return this.http.post<RolPlataformaOut>(`${this.base}/roles`, datos);
  }

  editarRol(id: number, datos: RolPlataformaUpdate): Observable<RolPlataformaOut> {
    return this.http.put<RolPlataformaOut>(`${this.base}/roles/${id}`, datos);
  }

  asignarPermisosRol(id: number, permisos: number[]): Observable<RolPlataformaOut> {
    return this.http.put<RolPlataformaOut>(`${this.base}/roles/${id}/permisos`, { permisos });
  }

  eliminarRol(id: number): Observable<void> {
    return this.http.delete<void>(`${this.base}/roles/${id}`);
  }
}
