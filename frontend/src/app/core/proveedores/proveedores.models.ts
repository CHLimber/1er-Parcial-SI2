export interface ProveedorOut {
  id: string;
  nombre: string;
  nit: string | null;
  contacto: string | null;
  email: string | null;
  telefono: string | null;
  activo: boolean;
  productos: number;
  recepciones: number;
}

export interface ProveedorIn {
  nombre: string;
  nit: string | null;
  contacto: string | null;
  email: string | null;
  telefono: string | null;
}
