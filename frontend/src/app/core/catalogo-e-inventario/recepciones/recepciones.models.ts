export type EstadoRecepcion = 'BORRADOR' | 'CONFIRMADA' | 'ANULADA';

export interface RecepcionIn {
  sucursal_id?: string | null;
  proveedor_id: string;
  coleccion_id?: string | null;
  numero?: string | null;
  fecha?: string | null;
}

export interface DetalleIn {
  variante_id: string;
  cantidad: number;
  costo_unitario: number;
}

export interface DetalleOut {
  id: string;
  variante_id: string;
  sku: string;
  producto: string;
  talla: string;
  color: string;
  cantidad: number;
  costo_unitario: number;
  subtotal: number;
}

export interface RecepcionOut {
  id: string;
  numero: string;
  fecha: string;
  estado: EstadoRecepcion;
  sucursal_id: string;
  sucursal: string;
  proveedor_id: string;
  proveedor: string;
  coleccion_id: string | null;
  coleccion: string | null;
  total: number | null;
  usuario_id: string | null;
  registrado_por: string | null;
  lineas: number;
  unidades: number;
}

export interface RecepcionDetalleOut extends RecepcionOut {
  detalle: DetalleOut[];
}

export interface VarianteBuscadaOut {
  id: string;
  sku: string;
  producto: string;
  talla: string;
  color: string;
  codigo_hex: string;
  precio_base: number;
  stock_sucursal: number;
}

export interface MovimientoOut {
  variante_id: string;
  sku: string;
  producto: string;
  cantidad: number;
  saldo_anterior: number;
  saldo_nuevo: number;
  fecha: string;
}
