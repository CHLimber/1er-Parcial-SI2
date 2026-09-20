// Espejo manual de app/modules/envios/schemas.py y admin_schemas.py (CU20).
//
// El reparto lo hace un servicio de delivery externo, no personal de FashionStore: la
// sucursal solo marca cuando el paquete SALE hacia ese servicio (DESPACHADO) y cuando el
// servicio confirma que LLEGO (ENTREGADO) o que fallo (FALLIDO).

export type EstadoEnvio = 'PENDIENTE' | 'DESPACHADO' | 'ENTREGADO' | 'FALLIDO' | 'CANCELADO';

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
  observacion: string | null;
  creado_en: string;
  despachado_en: string | null;
  cerrado_en: string | null;
  eventos: EnvioEventoOut[];
}

