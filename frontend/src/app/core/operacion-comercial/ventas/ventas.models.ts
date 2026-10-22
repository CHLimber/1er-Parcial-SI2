/** STRIPE y QR van por pasarela (pago.pasarela); EFECTIVO no tiene pasarela. QR y EFECTIVO quedan
 * PENDIENTE hasta que el cajero de la sucursal los aprueba desde caja (2.19.1.b/c) -- ver
 * CheckoutIn.metodo_pago en el backend. */
export type Pasarela = 'STRIPE' | 'QR';
export type MetodoPagoCheckout = Pasarela | 'EFECTIVO';
export type ModoEntrega = 'RETIRO_SUCURSAL' | 'DOMICILIO';

export interface CheckoutIn {
  sucursal_id: string | null;
  entrega: ModoEntrega;
  direccion_id?: string | null;
  metodo_pago: MetodoPagoCheckout;
  codigo_cupon?: string | null;
  canal: 'WEB' | 'MOVIL';
}

export interface CheckoutOut {
  venta_id: string;
  numero: string;
  pago_id: string;
  pasarela: Pasarela | null;
  id_transaccion: string | null;
  /** STRIPE en web no la manda (se paga inline con client_secret); en los demás casos es a
   * dónde navegar (pasarela simulada, o directo a /compra/{id} si ya quedó pagada). */
  url_pago: string | null;
  /** Solo STRIPE en web: Stripe.js lo usa para montar el Checkout embebido inline. */
  client_secret: string | null;
  subtotal: number;
  descuento: number;
  /** CU20: tarifa del delivery ya cobrada. 0 si se retira en tienda o si el envío salió gratis. */
  costo_envio: number;
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
  /** Solo QR: cuándo la clienta avisó "ya pagué" y la referencia que dejó. */
  informado_en: string | null;
  referencia_cliente: string | null;
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
  costo_envio: number;
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
