import { HttpClient } from '@angular/common/http';
import { Injectable, computed, signal } from '@angular/core';
import { Observable, map, tap } from 'rxjs';

import { environment } from '../../../environments/environment';
import { LoginRequest, TokenResponse, UsuarioOut } from './auth.models';

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

  constructor(private readonly http: HttpClient) {}

  get token(): string | null {
    return this.sesion()?.token ?? null;
  }

  iniciarSesion(credenciales: LoginRequest): Observable<UsuarioOut> {
    return this.http.post<TokenResponse>(`${environment.apiUrl}/auth/login`, credenciales).pipe(
      tap((respuesta) => {
        const guardada: SesionGuardada = { token: respuesta.access_token, usuario: respuesta.usuario };
        this.sesion.set(guardada);
        localStorage.setItem(STORAGE_KEY, JSON.stringify(guardada));
      }),
      map((respuesta) => respuesta.usuario),
    );
  }

  cerrarSesion(): void {
    this.sesion.set(null);
    localStorage.removeItem(STORAGE_KEY);
  }

  private leerSesionGuardada(): SesionGuardada | null {
    const crudo = localStorage.getItem(STORAGE_KEY);
    if (!crudo) return null;
    try {
      return JSON.parse(crudo) as SesionGuardada;
    } catch {
      localStorage.removeItem(STORAGE_KEY);
      return null;
    }
  }
}
