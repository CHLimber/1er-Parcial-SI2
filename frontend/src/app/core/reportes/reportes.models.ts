export type CanalVenta = 'WEB' | 'MOVIL' | 'POS';
export type ModoEntrega = 'RETIRO_SUCURSAL' | 'DOMICILIO';

export interface FiltroReportes {
  desde?: string | null;
  hasta?: string | null;
  sucursal_id?: string | null;
  categoria_id?: string | null;
  vendedor_id?: string | null;
  canal?: CanalVenta | null;
  entrega?: ModoEntrega | null;
}

export interface VendedorOut {
  id: string;
  nombre: string;
}

export interface IndicadoresOut {
  desde: string;
  hasta: string;
  ventas_cantidad: number;
  ventas_monto: number;
  ticket_promedio: number;
  reservas_creadas: number;
  reservas_convertidas: number;
  tasa_conversion_reservas: number;
  variantes_stock_bajo: number;
  variantes_agotadas: number;
  // CU20: ventas del periodo que llevaron flete y cuanto se cobro por eso (venta.costo_envio).
  envios_cantidad: number;
  envios_monto: number;
}

export interface VentaDiariaOut {
  dia: string;
  sucursal_id: string;
  sucursal: string;
  canal: CanalVenta;
  cantidad_ventas: number;
  monto_total: number;
  ticket_promedio: number;
}

export interface VentaPorSucursalOut {
  sucursal_id: string;
  sucursal: string;
  cantidad_ventas: number;
  monto_total: number;
  ticket_promedio: number;
  // CU20: costo de envio cobrado (venta.costo_envio) sumado dentro del mismo grupo de sucursal.
  costo_envio_total: number;
}

export interface ProductoRankingOut {
  producto_id: string;
  producto: string;
  unidades_vendidas: number;
  monto_vendido: number;
}

export interface StockSucursalOut {
  sucursal_id: string;
  sucursal: string;
  total_fisico: number;
  total_reservado: number;
  total_disponible: number;
  variantes_agotadas: number;
  variantes_stock_bajo: number;
}

export interface ReservaEstadoOut {
  estado: string;
  cantidad: number;
}

export interface EnvioEstadoOut {
  estado: string;
  cantidad: number;
}

export interface ProductoSinMovimientoOut {
  variante_id: string;
  producto: string;
  talla: string;
  color: string;
  sucursal_id: string;
  sucursal: string;
  cantidad_fisica: number;
}

export interface ClienteRankingOut {
  usuario_id: string;
  cliente: string;
  email: string;
  cantidad_compras: number;
  monto_total: number;
}

export interface CajaOcupacionOut {
  sucursal_id: string;
  sucursal: string;
  total_cajas: number;
  cajas_abiertas: number;
}

export interface RecepcionPendienteProveedorOut {
  proveedor_id: string;
  proveedor: string;
  cantidad: number;
  monto_total: number;
}

export interface MensajeReporteIn {
  rol: 'user' | 'assistant';
  texto: string;
}

export interface ColumnaOut {
  clave: string;
  etiqueta: string;
}

export interface ConsultaIaOut {
  respuesta: string;
  titulo: string | null;
  columnas: ColumnaOut[];
  tabla: Record<string, unknown>[];
}

// Consolidado de existencias (GET /reportes/existencias, vista v_existencias_consolidadas).
export type SituacionExistencia = 'DISPONIBLE' | 'RESERVADA' | 'PROXIMA_A_INGRESAR' | 'AGOTADA';

export interface FiltroExistencias {
  sucursal_id?: string | null;
  categoria_id?: string | null;
  busqueda?: string | null;
  situacion?: SituacionExistencia | null;
  pagina?: number;
  tamanio_pagina?: number;
}

export interface ExistenciaOut {
  producto_id: string;
  producto: string;
  categoria: string;
  variante_id: string;
  sku: string;
  talla: string;
  color: string;
  sucursal_id: string;
  sucursal: string;
  cantidad_fisica: number;
  cantidad_reservada: number;
  disponible: number;
  stock_minimo: number;
  vendidas: number;
  proximas_a_ingresar: number;
  situacion: SituacionExistencia;
}

/** Respeta sucursal/categoria/busqueda pero no la situacion: las tarjetas siguen mostrando todo. */
export interface ResumenExistenciasOut {
  variantes_total: number;
  variantes_disponibles: number;
  variantes_reservadas: number;
  variantes_proximas_a_ingresar: number;
  variantes_agotadas: number;
  unidades_fisicas: number;
  unidades_reservadas: number;
  unidades_disponibles: number;
  unidades_vendidas: number;
  unidades_por_ingresar: number;
}

export interface ExistenciasPaginadoOut {
  total: number;
  pagina: number;
  tamanio_pagina: number;
  resumen: ResumenExistenciasOut;
  items: ExistenciaOut[];
}
