export interface LoginRequest {
  email: string;
  password: string;
}

export interface UsuarioOut {
  id: string;
  email: string;
  nombre: string;
  apellido: string;
  tipo: 'CLIENTE' | 'STAFF';
  rol: string | null;
}

export interface TokenResponse {
  access_token: string;
  token_type: string;
  usuario: UsuarioOut;
}
