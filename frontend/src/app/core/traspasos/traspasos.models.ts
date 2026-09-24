/** Espejo manual de backend/app/modules/traspasos/schemas.py. */
export type EstadoTraspaso = 'SOLICITADO' | 'EN_TRANSITO' | 'RECIBIDO' | 'ANULADO';
export type DireccionTraspaso = 'SALIENTES' | 'ENTRANTES';
/** Desde que lado mira el traspaso quien consulta (AMBOS = ADMIN). */
export type LadoTraspaso = 'ORIGEN' | 'DESTINO' | 'AMBOS';

export interface LineaTraspasoIn {
  variante_id: string;
  cantidad: number;
}

export interface TraspasoIn {
  sucursal_origen_id?: string | null;
  sucursal_destino_id: string;
  lineas: LineaTraspasoIn[];
}

export interface LineaRecibidaIn {
  detalle_id: string;
  cantidad_recibida: number;
}

export interface RecibirIn {
  lineas: LineaRecibidaIn[];
  observacion?: string | null;
}

export interface DetalleTraspasoOut {
  id: string;
  variante_id: string;
  sku: string;
  producto: string;
  talla: string;
  color: string;
  codigo_hex: string;
  cantidad_solicitada: number;
  cantidad_recibida: number | null;
  disponible_origen: number;
  disponible_destino: number;
}

export interface TraspasoOut {
  id: string;
  numero: string;
  estado: EstadoTraspaso;
  sucursal_origen_id: string;
  origen: string;
  sucursal_destino_id: string;
  destino: string;
  fecha_solicitud: string;
  fecha_despacho: string | null;
  fecha_recepcion: string | null;
  solicitado_por: string | null;
  recibido_por: string | null;
  observacion: string | null;
  lineas: number;
  unidades_solicitadas: number;
  unidades_recibidas: number | null;
  mi_lado: LadoTraspaso;
}

export interface TraspasoDetalleOut extends TraspasoOut {
  detalle: DetalleTraspasoOut[];
}

export interface VarianteTraspasoOut {
  id: string;
  sku: string;
  producto: string;
  talla: string;
  color: string;
  codigo_hex: string;
  disponible_origen: number;
  disponible_destino: number;
}

export interface MovimientoTraspasoOut {
  sucursal: string;
  tipo: string;
  sku: string;
  producto: string;
  cantidad: number;
  saldo_anterior: number;
  saldo_nuevo: number;
  fecha: string;
}
