// Espejo manual de app/modules/envios/schemas.py y admin_schemas.py (CU20).

export type EstadoEnvio =
  | 'PENDIENTE'
  | 'ASIGNADO'
  | 'EN_RUTA'
  | 'ENTREGADO'
  | 'FALLIDO'
  | 'CANCELADO';

export interface CotizacionIn {
  sucursal_id: string;
  direccion_id?: string | null;
  latitud?: number | null;
  longitud?: number | null;
  monto_pedido: number;
}

export interface CotizacionOut {
  distancia_km: number;
  duracion_min: number;
  /** ORS (openrouteservice) o HAVERSINE (estimacion propia de respaldo). */
  proveedor: string;
  costo: number;
  es_gratis: boolean;
  dentro_cobertura: boolean;
  radio_km: number;
  tarifa_base: number;
  precio_km: number;
  gratis_desde: number;
}

export interface EnvioEventoOut {
  estado: EstadoEnvio;
  nota: string | null;
  fecha: string;
}

export interface EnvioOut {
  id: string;
  venta_id: string;
  numero_venta: string;
  estado: EstadoEnvio;
  sucursal: string;
  ciudad: string;
  direccion: string;
  referencia: string | null;
  latitud: number | null;
  longitud: number | null;
  distancia_km: number;
  duracion_min: number;
  costo: number;
  repartidor: string | null;
  observacion: string | null;
  creado_en: string;
  asignado_en: string | null;
  despachado_en: string | null;
  cerrado_en: string | null;
  eventos: EnvioEventoOut[];
}

export interface EnvioAdminOut {
  id: string;
  venta_id: string;
  numero_venta: string;
  estado: EstadoEnvio;
  sucursal_id: string;
  sucursal: string;
  cliente: string;
  cliente_telefono: string | null;
  ciudad: string;
  direccion: string;
  referencia: string | null;
  latitud: number | null;
  longitud: number | null;
  distancia_km: number;
  duracion_min: number;
  costo: number;
  proveedor_ruteo: string;
  total_venta: number;
  repartidor_id: string | null;
  repartidor: string | null;
  observacion: string | null;
  creado_en: string;
  asignado_en: string | null;
  despachado_en: string | null;
  cerrado_en: string | null;
}

export interface ItemEnvioOut {
  producto: string;
  sku: string;
  talla: string;
  color: string;
  cantidad: number;
}

export interface EventoAdminOut {
  estado: EstadoEnvio;
  nota: string | null;
  usuario: string | null;
  fecha: string;
}

export interface EnvioAdminDetalleOut extends EnvioAdminOut {
  items: ItemEnvioOut[];
  eventos: EventoAdminOut[];
}

export interface RepartidorOut {
  id: string;
  nombre: string;
  sucursal_id: string;
  sucursal: string;
  envios_activos: number;
}

export interface ResumenEnviosOut {
  pendientes: number;
  asignados: number;
  en_ruta: number;
  entregados_hoy: number;
  fallidos: number;
}
