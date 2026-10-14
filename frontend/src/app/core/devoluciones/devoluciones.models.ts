/** Espejo manual de backend/app/modules/devoluciones/schemas.py (los montos Decimal llegan como string). */
export type EstadoDevolucion = 'SOLICITADA' | 'APROBADA' | 'RECHAZADA';

/** Segundo parcial (PENDIENTES 5.8): TALLA/COLOR son cambios (la clienta se lleva otra variante de
 * la misma prenda, con su propio plazo); el resto son devoluciones con reintegro. */
export type MotivoDevolucion = 'TALLA' | 'COLOR' | 'DEFECTO' | 'NO_GUSTO' | 'OTRO';

export const MOTIVOS_DEVOLUCION: { valor: MotivoDevolucion; etiqueta: string }[] = [
  { valor: 'TALLA', etiqueta: 'Cambio por talla' },
  { valor: 'COLOR', etiqueta: 'Cambio por color' },
  { valor: 'DEFECTO', etiqueta: 'Prenda con defecto' },
  { valor: 'NO_GUSTO', etiqueta: 'No le gustó' },
  { valor: 'OTRO', etiqueta: 'Otro motivo' },
];

export interface LineaDevolucionIn {
  venta_detalle_id: string;
  cantidad: number;
  /** obligatoria en TALLA/COLOR: la variante que se lleva a cambio */
  variante_solicitada_id?: string | null;
}

export interface DevolucionIn {
  venta_id: string;
  motivo_tipo: MotivoDevolucion;
  motivo: string;
  /** condiciones de la prenda verificadas al recibirla */
  con_etiqueta: boolean;
  sin_uso: boolean;
  con_comprobante: boolean;
  lineas: LineaDevolucionIn[];
}

export interface VarianteCambioOut {
  variante_id: string;
  sku: string;
  talla: string;
  color: string;
  disponible: number;
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
  /** cambio por talla/color: fecha de la venta + configuracion.cambio_plazo_dias */
  cambio_vence_en: string;
  fuera_de_plazo_cambio: boolean;
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
  variante_solicitada_id: string | null;
  talla_solicitada: string | null;
  color_solicitado: string | null;
  sku_solicitado: string | null;
}

export interface DevolucionOut {
  id: string;
  /** numero de la nota de devolucion (NDV-000001) */
  numero: string;
  venta_id: string;
  venta_numero: string;
  venta_total: number;
  sucursal_id: string;
  sucursal: string;
  cliente: string | null;
  motivo_tipo: MotivoDevolucion;
  motivo: string;
  con_etiqueta: boolean;
  sin_uso: boolean;
  con_comprobante: boolean;
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

/** "Que prendas solicitaron cambio en el mes" (PENDIENTES 5.10). */
export interface CambioMesOut {
  producto_id: string;
  producto: string;
  motivo_tipo: MotivoDevolucion;
  talla_original: string;
  color_original: string;
  talla_solicitada: string | null;
  color_solicitado: string | null;
  solicitudes: number;
  unidades: number;
  aprobadas: number;
  rechazadas: number;
  pendientes: number;
  sucursales: string[];
}

export interface CambiosMesOut {
  anio: number;
  mes: number;
  desde: string;
  hasta: string;
  total_solicitudes: number;
  total_unidades: number;
  filas: CambioMesOut[];
}

/** Datos de la nota de devolucion imprimible (PENDIENTES 5.9). */
export interface NotaDevolucionOut {
  empresa_razon_social: string;
  empresa_nit: string;
  sucursal_direccion: string | null;
  sucursal_ciudad: string;
  venta_fecha: string;
  plazo_dias: number;
  devolucion: DevolucionDetalleOut;
}
