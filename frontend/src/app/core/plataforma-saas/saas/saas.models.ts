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

/** CU03: lo que la plataforma puede configurar de un plan. */
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
  sucursales: number;
  /** Ciudades con sucursal activa, como las guarda la base (SANTA_CRUZ, LA_PAZ...). */
  ciudades: string[];
  prendas: number;
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

/** Una cuenta de personal de una empresa, vista por la plataforma. */
export interface PersonalEmpresaOut {
  id: string;
  email: string;
  nombre: string;
  apellido: string;
  rol: string | null;
  cargo: string | null;
  sucursal: string | null;
  activo: boolean;
  bloqueado: boolean;
  ultimo_acceso: string | null;
}

export interface PersonalEmpresaIn {
  email: string;
  nombre: string;
  apellido: string;
  password: string;
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

/** CU01 por autoregistro (pagina publica de planes): sin dias de prueba y con sucursal obligatoria. */
export type RegistroEmpresaIn = Omit<EmpresaIn, 'dias_prueba' | 'sucursal'> & {
  sucursal: { codigo: string; nombre: string; ciudad: string; direccion: string };
};

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

/** CU05: renovacion simulada registrada por la plataforma. */
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

// --- gobierno de la plataforma: cuentas, roles y permisos de todas las empresas -----------------

/** Una cuenta cualquiera: personal de una empresa, clienta o equipo de la plataforma. */
export interface CuentaOut {
  id: string;
  email: string;
  nombre: string;
  apellido: string;
  telefono: string | null;
  tipo: 'CLIENTE' | 'STAFF';
  rol_id: number | null;
  rol: string | null;
  empresa_id: string | null;
  empresa: string | null;
  activo: boolean;
  bloqueado: boolean;
  ultimo_acceso: string | null;
  creado_en: string;
}

export interface CuentaUpdate {
  email: string;
  nombre: string;
  apellido: string;
  telefono: string | null;
  rol_id: number | null;
}

export interface EquipoIn {
  email: string;
  nombre: string;
  apellido: string;
  password: string;
}

export interface RolPlataformaOut {
  id: number;
  nombre: string;
  descripcion: string | null;
  es_sistema: boolean;
  empresa_id: string | null;
  empresa: string | null;
  usuarios: number;
  permisos: number[];
  /** SUPERADMIN, ADMIN, ENCARGADO y CAJERO: el codigo los nombra, no se renombran ni se eliminan. */
  protegido: boolean;
}

export interface RolPlataformaIn {
  nombre: string;
  descripcion: string | null;
  /** null = rol del sistema, compartido por todas las empresas. */
  empresa_id: string | null;
}

export interface RolPlataformaUpdate {
  nombre: string;
  descripcion: string | null;
}
