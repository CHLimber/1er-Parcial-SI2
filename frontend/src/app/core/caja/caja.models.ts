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

export interface ArqueoOut {
  sesion_id: string;
  monto_inicial: number;
  monto_sistema: number;
  cantidad_ventas: number;
  total_ventas: number;
  por_metodo: Record<string, number>;
}

export interface CerrarSesionIn {
  monto_declarado: number;
}

export interface SesionCerradaOut {
  id: string;
  caja_id: string;
  caja_nombre: string;
  abierta_en: string;
  cerrada_en: string;
  monto_inicial: number;
  monto_sistema: number;
  monto_declarado: number;
  diferencia: number;
  estado: string;
}
