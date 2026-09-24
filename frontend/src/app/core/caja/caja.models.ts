export interface CajaOut {
  id: string;
  codigo: string;
  nombre: string;
  tiene_sesion_abierta: boolean;
}

export interface AbrirSesionIn {
  caja_id: string;
  monto_inicial: number;
}

export interface SesionCajaOut {
  id: string;
  caja_id: string;
  caja_nombre: string;
  abierta_en: string;
  monto_inicial: number;
  estado: string;
}

export interface VarianteBusquedaOut {
  variante_id: string;
  sku: string;
  producto: string;
  talla: string;
  color: string;
  precio: number;
  disponible: number;
}

export interface ArqueoOut {
  sesion_id: string;
  monto_inicial: number;
  monto_sistema: number;
  cantidad_ventas: number;
  total_ventas: number;
  por_metodo: Record<string, number>;
}

export interface CerrarSesionIn {
  monto_declarado: number;
}

export interface SesionCerradaOut {
  id: string;
  caja_id: string;
  caja_nombre: string;
  abierta_en: string;
  cerrada_en: string;
  monto_inicial: number;
  monto_sistema: number;
  monto_declarado: number;
  diferencia: number;
  estado: string;
}

/** 2.19.1.b/c: pedido online con pago EFECTIVO o QR que espera al cajero. */
export interface ItemPagoPendienteOut {
  sku: string;
  producto: string;
  talla: string;
  color: string;
  cantidad: number;
}

export interface PagoPorVerificarOut {
  pago_id: string;
  venta_id: string;
  numero: string;
  fecha: string;
  cliente: string;
  cliente_email: string;
  metodo: 'EFECTIVO' | 'QR';
  entrega: string;
  total: number;
  costo_envio: number;
  /** Solo QR: null = la clienta todavía no avisó que pagó. */
  informado_en: string | null;
  referencia_cliente: string | null;
  /** La clienta cambió su carrito después del checkout: no se puede aprobar, solo rechazar. */
  carrito_modificado: boolean;
  items: ItemPagoPendienteOut[];
}

export interface RechazarPagoIn {
  motivo: string | null;
}

export interface ResolucionPagoOut {
  pago_id: string;
  venta_id: string;
  numero: string;
  venta_estado: string;
  pago_estado: string;
  mensaje: string;
}
