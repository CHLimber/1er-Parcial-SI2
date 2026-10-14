/** Espejo manual de backend/app/modules/saas/schemas.py (los montos Decimal llegan como string). */

export interface PlanOut {
  id: number;
  codigo: string;
  nombre: string;
  descripcion: string | null;
  precio_mensual: number | string;
  /** null = sin limite */
  max_empleados: number | null;
  max_cajas: number | null;
  perfiles_clientes: boolean;
  traspasos: boolean;
  ia_reportes: boolean;
}

/** Suscripcion de un tenant (sucursal) con su uso actual contra los topes del plan. */
export interface SuscripcionOut {
  sucursal_id: string;
  sucursal: string;
  ciudad: string;
  plan: PlanOut;
  /** PRUEBA | ACTIVA | VENCIDA | CANCELADA (el guardado; manda `vigente`) */
  estado: string;
  vigente: boolean;
  inicio: string;
  vence_en: string;
  dias_restantes: number;
  empleados: number;
  cajas: number;
}

export interface CheckoutSuscripcionIn {
  plan_codigo: string;
  meses: number;
  sucursal_id?: string | null;
}

export interface CheckoutSuscripcionOut {
  pago_id: string;
  monto: number | string;
  url_pago: string;
}

export interface PagoManualIn {
  plan_codigo: string;
  meses: number;
  metodo: 'EFECTIVO' | 'TRANSFERENCIA';
}

export interface PagoSuscripcionOut {
  id: string;
  sucursal: string;
  plan: string;
  meses: number;
  monto: number | string;
  metodo: string;
  estado: string;
  periodo_desde: string | null;
  periodo_hasta: string | null;
  pagado_por: string | null;
  creado_en: string;
  confirmado_en: string | null;
}
