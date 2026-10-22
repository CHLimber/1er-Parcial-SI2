export interface SucursalOut {
  id: string;
  codigo: string;
  nombre: string;
  ciudad: string;
  direccion: string;
  hora_apertura: string | null;
  hora_cierre: string | null;
  cantidad_vestidores: number;
}
