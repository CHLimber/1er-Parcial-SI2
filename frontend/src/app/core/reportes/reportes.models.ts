export type CanalVenta = 'WEB' | 'MOVIL' | 'POS';

export interface FiltroReportes {
  desde?: string | null;
  hasta?: string | null;
  sucursal_id?: string | null;
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
