/** Espejo manual de backend/app/modules/devoluciones/schemas.py (los montos Decimal llegan como string). */
export type EstadoDevolucion = 'SOLICITADA' | 'APROBADA' | 'RECHAZADA';

export interface LineaDevolucionIn {
  venta_detalle_id: string;
  cantidad: number;
}

export interface DevolucionIn {
  venta_id: string;
  motivo: string;
  lineas: LineaDevolucionIn[];
}

export interface RechazoIn {
  motivo: string;
}

/** Cómo vuelve la plata: por donde entró. STRIPE se reembolsa por la API; EFECTIVO sale del
 * cajón de la sesión de caja de quien aprueba; el resto se devuelve fuera del sistema. */
export type MetodoReintegro = 'STRIPE' | 'EFECTIVO' | 'TARJETA' | 'QR' | 'TRANSFERENCIA';

/** Cambio de prenda: la venta nueva (cobrada en caja) que reemplaza lo devuelto. */
export interface CambioIn {
  venta_numero: string;
}

export interface LineaVentaOut {
  venta_detalle_id: string;
  variante_id: string;
  sku: string;
  producto: string;
  talla: string;
  color: string;
  cantidad_vendida: number;
  precio_unitario: number;
  subtotal: number;
  /** unidades en devoluciones APROBADAS */
  devuelta: number;
  /** unidades en devoluciones SOLICITADAS */
  en_tramite: number;
  devolvible: number;
  /** lo que se reintegra por unidad, con el descuento y el IVA prorrateados */
  reembolso_unitario: number;
}

export interface VentaDevolvibleOut {
  venta_id: string;
  numero: string;
  fecha: string;
  estado: string;
  canal: string;
  sucursal_id: string;
  sucursal: string;
  cliente: string | null;
  subtotal: number;
  descuento: number;
  costo_envio: number;
  total: number;
  total_devuelto: number;
  /** fecha de la venta + configuracion.devolucion_plazo_dias */
  plazo_vence_en: string;
  /** true: registrar la devolución responde 409 */
  fuera_de_plazo: boolean;
  reintegro_metodo: MetodoReintegro | null;
  lineas: LineaVentaOut[];
}

export interface DetalleDevolucionOut {
  id: string;
  venta_detalle_id: string;
  variante_id: string;
  sku: string;
  producto: string;
  talla: string;
  color: string;
  cantidad: number;
  cantidad_vendida: number;
  precio_unitario: number;
}

export interface DevolucionOut {
  id: string;
  venta_id: string;
  venta_numero: string;
  venta_total: number;
  sucursal_id: string;
  sucursal: string;
  cliente: string | null;
  motivo: string;
  monto_devuelto: number;
  estado: EstadoDevolucion;
  fecha: string;
  registrada_por: string | null;
  resuelta_por: string | null;
  resuelta_en: string | null;
  motivo_rechazo: string | null;
  lineas: number;
  unidades: number;
  /** se fija al aprobar */
  reintegro_metodo: MetodoReintegro | null;
  /** id del reembolso en Stripe (re_...) */
  reintegro_referencia: string | null;
  venta_cambio_id: string | null;
  venta_cambio_numero: string | null;
}

export interface DevolucionDetalleOut extends DevolucionOut {
  detalle: DetalleDevolucionOut[];
  /** true si la devolucion completo la venta y el pago paso a REEMBOLSADO */
  pago_reembolsado: boolean;
}
