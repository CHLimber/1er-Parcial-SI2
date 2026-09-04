export interface CajaOut {
  id: string;
  codigo: string;
  nombre: string;
  tiene_sesion_abierta: boolean;
}

export interface AbrirSesionIn {
  caja_id: string;
  monto_inicial: number;
}

export interface SesionCajaOut {
  id: string;
  caja_id: string;
  caja_nombre: string;
  abierta_en: string;
  monto_inicial: number;
  estado: string;
}

export interface VarianteBusquedaOut {
  variante_id: string;
  sku: string;
  producto: string;
  talla: string;
  color: string;
  precio: number;
  disponible: number;
}
