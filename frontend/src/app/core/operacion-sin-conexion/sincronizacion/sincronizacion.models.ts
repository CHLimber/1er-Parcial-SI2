/** Espejo manual de backend/app/modules/sincronizacion/schemas.py. */

export interface VarianteOffline {
  id: string;
  sku: string;
  talla: string;
  color: string;
  codigo_hex: string;
  precio: number;
  /** existencias de la sucursal al descargar (el dispositivo las va descontando localmente) */
  disponible: number;
}

export interface ProductoOffline {
  id: string;
  codigo: string;
  nombre: string;
  slug: string;
  categoria: string;
  imagen_url: string | null;
  precio_base: number;
  variantes: VarianteOffline[];
}

export interface ClienteOffline {
  id: string;
  nombre: string;
  email: string;
  telefono: string | null;
}

export interface PaqueteOffline {
  generado_en: string;
  empresa_id: string;
  empresa: string;
  sucursal: { id: string; codigo: string; nombre: string; hora_apertura: string | null; hora_cierre: string | null };
  sesion_caja_id: string | null;
  iva_tasa: number;
  productos: ProductoOffline[];
  clientes: ClienteOffline[];
}

export interface ItemVentaOffline {
  variante_id: string;
  cantidad: number;
  precio_unitario: string;
}

export interface OperacionIn {
  id: string;
  tipo: 'VENTA' | 'RESERVA';
  empresa_id: string;
  sucursal_id: string;
  usuario_id: string;
  registrada_en: string;
  venta?: {
    items: ItemVentaOffline[];
    metodo_pago: 'EFECTIVO';
    total: string;
    monto_recibido?: string | null;
    sesion_caja_id?: string | null;
    cliente_email?: string | null;
  };
  reserva?: {
    cliente_email: string;
    fecha_visita: string;
    hora_visita: string;
    items: { variante_id: string; cantidad: number }[];
    observaciones?: string | null;
  };
}

export type EstadoServidor = 'CONFIRMADA' | 'RECHAZADA' | 'CONFLICTO';
/** Estado local: REGISTRADA (solo en el dispositivo) -> ENVIADA -> lo que diga el servidor. */
export type EstadoLocal = 'REGISTRADA' | 'ENVIADA' | EstadoServidor;

export interface ResultadoOperacion {
  id: string;
  tipo: string;
  estado: EstadoServidor;
  codigo_motivo: string | null;
  motivo: string | null;
  resultado: Record<string, unknown> | null;
  duplicada: boolean;
  intentos: number;
  recibida_en: string | null;
  resuelta_en: string | null;
  resolucion: string | null;
}

export interface LoteOut {
  resultados: ResultadoOperacion[];
  confirmadas: number;
  rechazadas: number;
  en_conflicto: number;
}

export interface OperacionServidor extends ResultadoOperacion {
  sucursal: string;
  usuario: string;
  registrada_en: string;
  payload: OperacionIn;
}

/** Lo que se guarda en IndexedDB por cada operacion offline. */
export interface OperacionLocal {
  id: string;
  /** dueno de la operacion: solo la sincroniza quien la registro */
  usuario_id: string;
  estado: EstadoLocal;
  op: OperacionIn;
  /** resumen legible para la lista (que se vendio/reservo y por cuanto) */
  descripcion: string;
  total: number;
  intentos_envio: number;
  ultimo_envio: string | null;
  error_red: string | null;
  respuesta: ResultadoOperacion | null;
}

export type AccionResolver = 'REINTENTAR' | 'ACEPTAR_PRECIO_ACTUAL' | 'DESCARTAR';
