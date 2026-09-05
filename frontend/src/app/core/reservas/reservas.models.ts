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

export interface ResolverReservaIn {
  decisiones: DecisionItemIn[];
  metodo_pago?: MetodoPagoReserva | null;
  monto_recibido?: number | null;
}

export interface ResolverReservaOut {
  reserva: ReservaStaffOut;
  venta_id: string | null;
  venta_numero: string | null;
  comprobante_numero: string | null;
  total_cobrado: number | null;
}
