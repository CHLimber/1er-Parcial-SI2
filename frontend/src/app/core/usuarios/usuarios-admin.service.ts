import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import {
  ClienteUpdate,
  PermisoOut,
  RolIn,
  RolOut,
  StaffIn,
  StaffUpdate,
  UsuarioAdminOut,
} from './usuarios-admin.models';

/** CU13 - Gestionar Usuarios y Roles. */
@Injectable({ providedIn: 'root' })
export class UsuariosAdminService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/admin`;

  listarUsuarios(
    q?: string | null,
    tipo?: 'CLIENTE' | 'STAFF' | null,
    activo?: boolean | null,
  ): Observable<UsuarioAdminOut[]> {
    let params = new HttpParams();
    if (q) params = params.set('q', q);
    if (tipo) params = params.set('tipo', tipo);
    if (activo !== null && activo !== undefined) params = params.set('activo', activo);
    return this.http.get<UsuarioAdminOut[]>(`${this.base}/usuarios`, { params });
  }

  crearStaff(datos: StaffIn): Observable<UsuarioAdminOut> {
    return this.http.post<UsuarioAdminOut>(`${this.base}/usuarios`, datos);
  }

  actualizarStaff(id: string, datos: StaffUpdate): Observable<UsuarioAdminOut> {
    return this.http.put<UsuarioAdminOut>(`${this.base}/usuarios/${id}`, datos);
  }

  actualizarCliente(id: string, datos: ClienteUpdate): Observable<UsuarioAdminOut> {
    return this.http.put<UsuarioAdminOut>(`${this.base}/clientes/${id}`, datos);
  }

  cambiarEstado(id: string, activo: boolean): Observable<UsuarioAdminOut> {
    return this.http.patch<UsuarioAdminOut>(`${this.base}/usuarios/${id}/estado`, { activo });
  }

  restablecerPassword(id: string, password: string): Observable<void> {
    return this.http.post<void>(`${this.base}/usuarios/${id}/password`, { password });
  }

  listarPermisos(): Observable<PermisoOut[]> {
    return this.http.get<PermisoOut[]>(`${this.base}/permisos`);
  }

  listarRoles(): Observable<RolOut[]> {
    return this.http.get<RolOut[]>(`${this.base}/roles`);
  }

  crearRol(datos: RolIn): Observable<RolOut> {
    return this.http.post<RolOut>(`${this.base}/roles`, datos);
  }

  actualizarRol(id: number, datos: RolIn): Observable<RolOut> {
    return this.http.put<RolOut>(`${this.base}/roles/${id}`, datos);
  }

  asignarPermisos(id: number, permisos: number[]): Observable<RolOut> {
    return this.http.put<RolOut>(`${this.base}/roles/${id}/permisos`, { permisos });
  }

  eliminarRol(id: number): Observable<void> {
    return this.http.delete<void>(`${this.base}/roles/${id}`);
  }
}
