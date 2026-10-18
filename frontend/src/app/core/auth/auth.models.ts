export interface LoginRequest {
  email: string;
  password: string;
}

/** Cambiar mi propia contraseña (CLIENTE o STAFF), a diferencia del reset de CU13 que no
 * pide la actual. */
export interface CambiarPasswordRequest {
  password_actual: string;
  password_nueva: string;
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
  /** Cargo del empleado: ENCARGADO o CAJERO. El delivery (CU20) lo hace
   * un servicio externo, no personal con este cargo. */
  cargo: string | null;
  /** Codigos de permiso del rol (CU13). Vacio para clientes. */
  permisos: string[];
  /** Multi-tenant: empresa del personal (null = clienta o plataforma), su plan y las funciones
   * del plan que hoy puede usar (vacia si la suscripcion vencio). Solo arman la UI. */
  empresa_id?: string | null;
  empresa?: string | null;
  empresa_slug?: string | null;
  plan?: string | null;
  funciones_plan?: string[];
}

export interface TokenResponse {
  access_token: string;
  token_type: string;
  usuario: UsuarioOut;
}
