export type Pasarela = 'STRIPE' | 'LIBELULA';
export type ModoEntrega = 'RETIRO_SUCURSAL' | 'DOMICILIO';

export interface CheckoutIn {
  sucursal_id: string | null;
  entrega: ModoEntrega;
  direccion_id?: string | null;
  pasarela: Pasarela;
  codigo_cupon?: string | null;
  canal: 'WEB' | 'MOVIL';
}

export interface CheckoutOut {
  venta_id: string;
  numero: string;
  pago_id: string;
  pasarela: Pasarela;
  id_transaccion: string;
  url_pago: string;
  subtotal: number;
  descuento: number;
  iva: number;
  total: number;
  estado: string;
}

export interface VentaItemOut {
  variante_id: string;
  sku: string;
  producto: string;
  talla: string;
  color: string;
  cantidad: number;
  precio_unitario: number;
  subtotal: number;
}

export interface PagoOut {
  id: string;
  metodo: string;
  pasarela: Pasarela | null;
  monto: number;
  estado: string;
  id_transaccion: string | null;
  creado_en: string;
  confirmado_en: string | null;
}

export interface ComprobanteOut {
  numero: string;
  tipo: string;
  emitido_en: string;
}

export interface VentaOut {
  id: string;
  numero: string;
  canal: string;
  entrega: string;
  estado: string;
  sucursal: string;
  subtotal: number;
  descuento: number;
  iva: number;
  total: number;
  fecha: string;
  items: VentaItemOut[];
  pago: PagoOut | null;
  comprobante: ComprobanteOut | null;
}

export interface VentaResumenOut {
  id: string;
  numero: string;
  canal: string;
  estado: string;
  total: number;
  fecha: string;
  sucursal: string;
}

export type MetodoPagoPos = 'EFECTIVO' | 'TARJETA' | 'QR';

export interface VentaPosItemIn {
  variante_id: string;
  cantidad: number;
}

export interface VentaPosIn {
  items: VentaPosItemIn[];
  metodo_pago: MetodoPagoPos;
  monto_recibido?: number | null;
}

export interface ItemRechazadoPosOut {
  variante_id: string;
  sku: string;
  motivo: string;
}

export interface VentaPosOut {
  venta_id: string;
  numero: string;
  comprobante_numero: string;
  items: VentaItemOut[];
  rechazados: ItemRechazadoPosOut[];
  subtotal: number;
  iva: number;
  total: number;
  vuelto: number | null;
}
