/** Espejo manual de backend/app/modules/saas/schemas.py (los montos Decimal llegan como string). */

export interface PlanOut {
  id: number;
  codigo: string;
  nombre: string;
  descripcion: string | null;
  precio_mensual: number | string;
  /** null = sin limite */
  max_sucursales: number | null;
  max_empleados: number | null;
  max_cajas: number | null;
  perfiles_clientes: boolean;
  traspasos: boolean;
  operacion_offline: boolean;
  reportes: boolean;
  ia_reportes: boolean;
  analitica_ml: boolean;
}

/** CU05: lo que la plataforma puede configurar de un plan. */
export type PlanIn = Omit<PlanOut, 'id' | 'codigo'> & { activo: boolean };

export interface UsoOut {
  sucursales: number;
  empleados: number;
  cajas: number;
}

/** Suscripcion de un tenant (empresa) con su uso actual contra los topes del plan. */
export interface SuscripcionOut {
  empresa_id: string;
  empresa: string;
  empresa_slug: string;
  empresa_activa: boolean;
  plan: PlanOut;
  /** PRUEBA | ACTIVA | VENCIDA | CANCELADA (el guardado; manda `vigente`) */
  estado: string;
  vigente: boolean;
  inicio: string;
  vence_en: string;
  dias_restantes: number;
  uso: UsoOut;
}

export interface TiendaOut {
  slug: string;
  nombre: string;
}

export interface EmpresaOut {
  id: string;
  slug: string;
  nombre: string;
  razon_social: string;
  nit: string;
  email: string | null;
  telefono: string | null;
  activa: boolean;
  creada_en: string;
  administradores: string[];
  suscripcion: SuscripcionOut | null;
}

export interface EmpresaDatosIn {
  nombre: string;
  razon_social: string;
  nit: string;
  email?: string | null;
  telefono?: string | null;
}

/** CU01: el tenant, su administrador, su plan y (opcional) su primera sucursal. */
export interface EmpresaIn extends EmpresaDatosIn {
  slug: string;
  plan_codigo: string;
  dias_prueba: number;
  administrador: { email: string; nombre: string; apellido: string; password: string };
  sucursal?: {
    codigo: string;
    nombre: string;
    ciudad: string;
    direccion: string;
  } | null;
}

/** CU02: asignar / cambiar plan con fechas (administrativo, sin cobro). */
export interface AsignarPlanIn {
  plan_codigo: string;
  estado: 'PRUEBA' | 'ACTIVA' | 'VENCIDA' | 'CANCELADA';
  inicio?: string | null;
  vence_en: string;
}

export interface CheckoutSuscripcionIn {
  plan_codigo: string;
  meses: number;
}

export interface CheckoutSuscripcionOut {
  pago_id: string;
  monto: number | string;
  url_pago: string;
}

/** CU04: renovacion simulada registrada por la plataforma. */
export interface PagoManualIn {
  plan_codigo: string;
  meses: number;
  metodo: 'EFECTIVO' | 'TRANSFERENCIA';
}

export interface PagoSuscripcionOut {
  id: string;
  empresa: string;
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
