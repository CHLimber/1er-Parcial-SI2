/** Espejo manual de app/modules/sucursales/admin_schemas.py (CU12). */

export interface SucursalIn {
  codigo: string;
  nombre: string;
  ciudad: string;
  direccion: string;
  telefono: string | null;
  latitud: number | null;
  longitud: number | null;
  hora_apertura: string | null;
  hora_cierre: string | null;
  cantidad_vestidores: number;
}

export interface SucursalAdminOut extends SucursalIn {
  id: string;
  activa: boolean;
  empleados: number;
  cajas: number;
}

export interface CajaOut {
  id: string;
  sucursal_id: string;
  codigo: string;
  nombre: string;
  activa: boolean;
  sesion_abierta: boolean;
}

export interface CajaIn {
  codigo: string;
  nombre: string;
}
