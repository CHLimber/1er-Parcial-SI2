export interface ReservaItemIn {
  variante_id: string;
  cantidad: number;
}

export interface ReservaCrear {
  sucursal_id: string;
  fecha_visita: string;
  hora_visita: string;
  observaciones?: string | null;
  items: ReservaItemIn[];
}

export interface ItemRechazadoOut {
  variante_id: string;
  sku: string;
  motivo: string;
}

export interface ReservaItemOut {
  id: string;
  variante_id: string;
  sku: string;
  producto: string;
  talla: string;
  color: string;
  cantidad: number;
  estado_item: string;
  /** precio de lista unitario sin IVA (lo que se cobra en el vestidor) */
  precio?: number | null;
}

export interface ReservaOut {
  id: string;
  codigo: string;
  sucursal_id: string;
  sucursal: string;
  estado: string;
  fecha_visita: string;
  hora_visita: string;
  expira_en: string;
  creada_en: string;
  observaciones: string | null;
  items: ReservaItemOut[];
  items_rechazados: ItemRechazadoOut[];
}

// --- CU08: Atender Reserva (Encargado de Sucursal) --------------------------

export interface ClienteBreveOut {
  nombre: string;
  apellido: string;
  email: string;
  telefono: string | null;
}

export interface ReservaStaffOut {
  id: string;
  codigo: string;
  cliente: ClienteBreveOut;
  sucursal_id: string;
  sucursal: string;
  estado: string;
  fecha_visita: string;
  hora_visita: string;
  expira_en: string;
  creada_en: string;
  observaciones: string | null;
  vestidor_asignado: string | null;
  atendida_en: string | null;
  items: ReservaItemOut[];
}

export interface ItemDisponibilidadIn {
  variante_id: string;
  disponible: boolean;
  motivo?: string | null;
}

export interface PrepararReservaIn {
  items: ItemDisponibilidadIn[];
}

export interface MarcarPresenteIn {
  vestidor_asignado?: string | null;
}

export interface DecisionItemIn {
  variante_id: string;
  comprado: boolean;
}

export type MetodoPagoReserva = 'EFECTIVO' | 'TARJETA' | 'QR';

/** Cobro en el vestidor: los de /resolver mas STRIPE (formulario de tarjeta en pantalla). */
export type MetodoCobroVestidor = MetodoPagoReserva | 'STRIPE';

/** Estado del cobro con tarjeta (Stripe) de una reserva en el vestidor. */
export interface CobroStripeOut {
  estado: 'SIN_COBRO' | 'PENDIENTE' | 'PAGADA' | 'ENTREGADA' | 'ANULADA';
  venta_id: string | null;
  venta_numero: string | null;
  total: number | null;
  client_secret: string | null;
  canal: 'WEB' | 'MOVIL' | null;
  comprobante_numero: string | null;
  mensaje: string | null;
}

export interface ResolverReservaIn {
  decisiones: DecisionItemIn[];
  metodo_pago?: MetodoPagoReserva | null;
  monto_recibido?: number | null;
}

// 2.19.1.a: el Encargado rechaza una reserva PENDIENTE
export interface RechazarReservaIn {
  motivo: string;
}

// 2.19.2: el cliente cancela su propia reserva
export interface CancelarReservaIn {
  motivo?: string | null;
}

export interface ResolverReservaOut {
  reserva: ReservaStaffOut;
  venta_id: string | null;
  venta_numero: string | null;
  comprobante_numero: string | null;
  total_cobrado: number | null;
}
