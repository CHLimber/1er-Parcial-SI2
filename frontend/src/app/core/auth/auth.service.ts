import { HttpClient } from '@angular/common/http';
import { Injectable, computed, signal } from '@angular/core';
import { Observable, map, tap } from 'rxjs';

import { environment } from '../../../environments/environment';
import { LoginRequest, RegistroRequest, TokenResponse, UsuarioOut } from './auth.models';

const STORAGE_KEY = 'fashionstore.sesion';

interface SesionGuardada {
  token: string;
  usuario: UsuarioOut;
}

@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly sesion = signal<SesionGuardada | null>(this.leerSesionGuardada());

  readonly usuario = computed(() => this.sesion()?.usuario ?? null);
  readonly estaAutenticado = computed(() => this.sesion() !== null);
  readonly esStaff = computed(() => this.usuario()?.tipo === 'STAFF');
  readonly permisos = computed(() => this.usuario()?.permisos ?? []);

  constructor(private readonly http: HttpClient) {}

  get token(): string | null {
    return this.sesion()?.token ?? null;
  }

  /** CU13: la UI se arma con los permisos del rol, no con su nombre. Basta con tener uno. */
  tienePermiso(...codigos: string[]): boolean {
    const propios = this.permisos();
    return codigos.some((codigo) => propios.includes(codigo));
  }

  iniciarSesion(credenciales: LoginRequest): Observable<UsuarioOut> {
    return this.http.post<TokenResponse>(`${environment.apiUrl}/auth/login`, credenciales).pipe(
      tap((respuesta) => this.guardar(respuesta)),
      map((respuesta) => respuesta.usuario),
    );
  }

  registrarse(datos: RegistroRequest): Observable<UsuarioOut> {
    return this.http.post<TokenResponse>(`${environment.apiUrl}/auth/registro`, datos).pipe(
      tap((respuesta) => this.guardar(respuesta)),
      map((respuesta) => respuesta.usuario),
    );
  }

  /**
   * Vuelve a pedir el usuario al backend. Si el administrador cambio el rol o los permisos
   * (CU13), la sesion guardada en el navegador queda desactualizada hasta este refresco.
   */
  refrescarSesion(): Observable<UsuarioOut> {
    return this.http.get<UsuarioOut>(`${environment.apiUrl}/auth/yo`).pipe(
      tap((usuario) => {
        const actual = this.sesion();
        if (!actual) return;
        const guardada: SesionGuardada = { token: actual.token, usuario };
        this.sesion.set(guardada);
        localStorage.setItem(STORAGE_KEY, JSON.stringify(guardada));
      }),
    );
  }

  cerrarSesion(): void {
    this.sesion.set(null);
    localStorage.removeItem(STORAGE_KEY);
  }

  private guardar(respuesta: TokenResponse): void {
    const guardada: SesionGuardada = { token: respuesta.access_token, usuario: respuesta.usuario };
    this.sesion.set(guardada);
    localStorage.setItem(STORAGE_KEY, JSON.stringify(guardada));
  }

  private leerSesionGuardada(): SesionGuardada | null {
    const crudo = localStorage.getItem(STORAGE_KEY);
    if (!crudo) return null;
    try {
      const guardada = JSON.parse(crudo) as SesionGuardada;
      // sesiones guardadas antes de CU13 no traen permisos
      guardada.usuario.permisos ??= [];
      return guardada;
    } catch {
      localStorage.removeItem(STORAGE_KEY);
      return null;
    }
  }
}
