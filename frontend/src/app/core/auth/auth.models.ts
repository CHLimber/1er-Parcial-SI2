export interface LoginRequest {
  email: string;
  password: string;
}

export interface RegistroRequest {
  email: string;
  password: string;
  nombre: string;
  apellido: string;
  telefono?: string | null;
  fecha_nacimiento?: string | null;
  acepta_marketing?: boolean;
}

export interface UsuarioOut {
  id: string;
  email: string;
  nombre: string;
  apellido: string;
  tipo: 'CLIENTE' | 'STAFF';
  rol: string | null;
  /** Codigos de permiso del rol (CU13). Vacio para clientes. */
  permisos: string[];
}

export interface TokenResponse {
  access_token: string;
  token_type: string;
  usuario: UsuarioOut;
}
