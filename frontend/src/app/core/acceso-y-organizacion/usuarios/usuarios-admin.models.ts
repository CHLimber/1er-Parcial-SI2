/** Espejo manual de app/modules/usuarios/admin_schemas.py (CU13). */

export type CargoEmpleado = 'ENCARGADO' | 'CAJERO' | 'VENDEDOR' | 'ALMACEN';

export const CARGOS: CargoEmpleado[] = ['ENCARGADO', 'CAJERO', 'VENDEDOR', 'ALMACEN'];

export interface EmpleadoOut {
  sucursal_id: string;
  sucursal: string;
  cargo: CargoEmpleado;
  ci: string | null;
  fecha_ingreso: string | null;
  activo: boolean;
}

export interface UsuarioAdminOut {
  id: string;
  email: string;
  nombre: string;
  apellido: string;
  telefono: string | null;
  tipo: 'CLIENTE' | 'STAFF';
  rol_id: number | null;
  rol: string | null;
  activo: boolean;
  email_verificado: boolean;
  ultimo_acceso: string | null;
  creado_en: string;
  empleado: EmpleadoOut | null;
}

export interface StaffIn {
  email: string;
  password: string;
  nombre: string;
  apellido: string;
  telefono: string | null;
  rol_id: number;
  sucursal_id: string;
  cargo: CargoEmpleado;
  ci: string | null;
  fecha_ingreso: string | null;
}

export type StaffUpdate = Omit<StaffIn, 'password'>;

export interface ClienteUpdate {
  email: string;
  nombre: string;
  apellido: string;
  telefono: string | null;
}

export interface PermisoOut {
  id: number;
  codigo: string;
  modulo: string;
  descripcion: string | null;
}

export interface RolOut {
  id: number;
  nombre: string;
  descripcion: string | null;
  es_sistema: boolean;
  usuarios: number;
  permisos: number[];
}

export interface RolIn {
  nombre: string;
  descripcion: string | null;
}
