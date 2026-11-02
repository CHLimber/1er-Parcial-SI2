/** Espejo manual de backend/app/modules/operacion_comercial/devoluciones/schemas.py (los montos
 * Decimal llegan como string; se pasan por Number() antes de operar). */

/** SOLICITADA (registrada en caja o pedida online) -> CONFIRMADA (online aceptada, espera a la
 * clienta) -> APROBADA (concretada en caja). RECHAZADA, CANCELADA (la clienta) y EXPIRADA (no vino)
 * la cierran sin mover plata. */
export type EstadoDevolucion =
  | 'SOLICITADA'
  | 'CONFIRMADA'
  | 'APROBADA'
  | 'RECHAZADA'
  | 'CANCELADA'
  | 'EXPIRADA';

/** DEVOLUCION: vuelve la plata. INTERCAMBIO: otra talla/color de la misma prenda; se cobra o se
 * devuelve la diferencia de precio. */
export type TipoDevolucion = 'DEVOLUCION' | 'INTERCAMBIO';
export type OrigenDevolucion = 'CAJA' | 'ONLINE';

/** TALLA/COLOR son intercambios; el resto son devoluciones con reintegro. */
export type MotivoDevolucion = 'TALLA' | 'COLOR' | 'DEFECTO' | 'NO_GUSTO' | 'OTRO';

export const MOTIVOS_DEVOLUCION: { valor: MotivoDevolucion; etiqueta: string; tipo: TipoDevolucion }[] = [
  { valor: 'TALLA', etiqueta: 'Otra talla', tipo: 'INTERCAMBIO' },
  { valor: 'COLOR', etiqueta: 'Otro color', tipo: 'INTERCAMBIO' },
  { valor: 'DEFECTO', etiqueta: 'Prenda con defecto', tipo: 'DEVOLUCION' },
  { valor: 'NO_GUSTO', etiqueta: 'No le gustó', tipo: 'DEVOLUCION' },
  { valor: 'OTRO', etiqueta: 'Otro motivo', tipo: 'DEVOLUCION' },
];

export function motivosDe(tipo: TipoDevolucion) {
  return MOTIVOS_DEVOLUCION.filter((m) => m.tipo === tipo);
}

export const ESTADO_DEVOLUCION_TEXTO: Record<EstadoDevolucion, string> = {
  SOLICITADA: 'Por aceptar',
  CONFIRMADA: 'Aceptada · espera visita',
  APROBADA: 'Realizada',
  RECHAZADA: 'Rechazada',
  CANCELADA: 'Cancelada',
  EXPIRADA: 'Vencida',
};

export type MetodoDiferencia = 'EFECTIVO' | 'TARJETA' | 'QR';

export interface LineaDevolucionIn {
  venta_detalle_id: string;
  cantidad: number;
  /** obligatoria en un intercambio (TALLA/COLOR): la variante que se lleva a cambio */
  variante_solicitada_id?: string | null;
}

/** Registro en caja (origen CAJA). */
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

/** Solicitud online de la clienta (origen ONLINE), como una reserva. */
export interface SolicitudClienteIn {
  venta_id: string;
  motivo_tipo: MotivoDevolucion;
  motivo: string;
  fecha_visita: string;
  hora_visita: string;
  lineas: LineaDevolucionIn[];
}

/** Concretar en caja: condiciones vistas al recibir la prenda y cómo paga la diferencia. */
export interface AprobacionIn {
  con_etiqueta?: boolean | null;
  sin_uso?: boolean | null;
  con_comprobante?: boolean | null;
  diferencia_metodo?: MetodoDiferencia | null;
}

export interface VarianteCambioOut {
  variante_id: string;
  sku: string;
  talla: string;
  color: string;
  /** precio de lista sin IVA */
  precio: number;
  disponible: number;
}

export interface RechazoIn {
  motivo: string;
}

/** Cómo vuelve la plata: por donde entró. STRIPE se reembolsa por la API; EFECTIVO y QR salen en
 * efectivo del cajón de la sesión de caja de quien aprueba; el resto se devuelve fuera del sistema. */
export type MetodoReintegro = 'STRIPE' | 'EFECTIVO' | 'TARJETA' | 'QR' | 'TRANSFERENCIA';

export const COMO_SE_REINTEGRA: Record<MetodoReintegro, string> = {
  STRIPE: 'a la tarjeta (Stripe)',
  EFECTIVO: 'en efectivo, desde la caja',
  QR: 'en efectivo, desde la caja',
  TARJETA: 'a la tarjeta (fuera del sistema)',
  TRANSFERENCIA: 'por transferencia (fuera del sistema)',
};

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
  /** unidades en devoluciones en trámite */
  en_tramite: number;
  devolvible: number;
  /** lo que vale cada unidad devuelta, con el descuento y el IVA prorrateados */
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
  plazo_vence_en: string;
  fuera_de_plazo: boolean;
  cambio_vence_en: string;
  fuera_de_plazo_cambio: boolean;
  reintegro_metodo: MetodoReintegro | null;
  /** tope de prendas por compra */
  max_unidades: number;
  /** número de la devolución/intercambio que ya tiene la compra (una sola por compra) */
  solicitud_vigente: string | null;
  /** la compra salió de un intercambio: no se devuelve de nuevo */
  es_venta_de_cambio: boolean;
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
  /** precio de lista (sin IVA) pactado de la prenda nueva */
  precio_solicitado: number | null;
}

export interface DevolucionOut {
  id: string;
  /** número de la nota (NDV-000001) */
  numero: string;
  tipo: TipoDevolucion;
  origen: OrigenDevolucion;
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
  /** lo que vale lo devuelto (crédito en un intercambio); estimado hasta aprobar */
  monto_devuelto: number;
  /** lo que valen las prendas nuevas del intercambio (con IVA) */
  monto_cambio: number;
  /** monto_cambio - monto_devuelto: > 0 la clienta paga, < 0 se le devuelve */
  diferencia: number;
  /** lo que efectivamente volvió a la clienta */
  monto_reintegrado: number;
  diferencia_cobrada: number;
  diferencia_metodo: MetodoDiferencia | null;
  estado: EstadoDevolucion;
  fecha: string;
  fecha_visita: string | null;
  hora_visita: string | null;
  expira_en: string | null;
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
  /** intercambio: la venta con las prendas nuevas, armada al aprobar */
  venta_cambio_id: string | null;
  venta_cambio_numero: string | null;
}

export interface DevolucionDetalleOut extends DevolucionOut {
  detalle: DetalleDevolucionOut[];
  /** true si la devolución completó la venta y el pago pasó a REEMBOLSADO */
  pago_reembolsado: boolean;
}

/** "Qué prendas solicitaron cambio en el mes" (PENDIENTES 5.10). */
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

/** Datos de la nota imprimible (PENDIENTES 5.9). */
export interface NotaDevolucionOut {
  empresa_razon_social: string;
  empresa_nit: string;
  sucursal_direccion: string | null;
  sucursal_ciudad: string;
  venta_fecha: string;
  plazo_dias: number;
  devolucion: DevolucionDetalleOut;
}

/** Solicitudes que esperan al personal de la sucursal (lo muestra Caja). */
export interface PendientesDevolucionOut {
  por_aceptar: number;
  por_concretar: number;
}

// --- lado de la clienta (Mis devoluciones) -------------------------------------------------------

export interface LineaClienteOut {
  venta_detalle_id: string;
  variante_id: string;
  producto: string;
  talla: string;
  color: string;
  cantidad_vendida: number;
  devolvible: number;
  /** precio de lista que figura en la compra (sin IVA) */
  precio_unitario: number;
  /** lo que vale cada unidad devuelta (con IVA y descuento) */
  reembolso_unitario: number;
  variantes_cambio: VarianteCambioOut[];
}

export interface OpcionesDevolucionOut {
  venta_id: string;
  numero: string;
  fecha: string;
  sucursal_id: string;
  sucursal: string;
  sucursal_direccion: string | null;
  hora_apertura: string | null;
  hora_cierre: string | null;
  plazo_vence_en: string;
  max_unidades: number;
  iva_tasa: number;
  reintegro_metodo: MetodoReintegro | null;
  puede_solicitar: boolean;
  motivo_no: string | null;
  lineas: LineaClienteOut[];
}
