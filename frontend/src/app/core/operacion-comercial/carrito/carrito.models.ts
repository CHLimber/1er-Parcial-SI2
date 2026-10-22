export interface CarritoItemIn {
  variante_id: string;
  cantidad: number;
}

export interface CarritoItemOut {
  id: string;
  variante_id: string;
  sku: string;
  producto: string;
  producto_slug: string;
  talla: string;
  color: string;
  codigo_hex: string;
  imagen_url: string | null;
  precio_unitario: number;
  cantidad: number;
  subtotal: number;
}

export interface CarritoOut {
  id: string;
  estado: string;
  reserva_id: string | null;
  reserva_codigo: string | null;
  items: CarritoItemOut[];
  cantidad_items: number;
  subtotal: number;
}
