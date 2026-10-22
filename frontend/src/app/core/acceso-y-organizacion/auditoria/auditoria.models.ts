export type AccionAuditoria = 'CREAR' | 'ACTUALIZAR' | 'ELIMINAR' | 'LOGIN';

export interface AuditoriaOut {
  id: number;
  fecha: string;
  usuario_id: string | null;
  usuario_nombre: string | null;
  usuario_email: string | null;
  entidad: string;
  entidad_id: string;
  accion: AccionAuditoria;
  datos_antes: Record<string, unknown> | null;
  datos_despues: Record<string, unknown> | null;
  ip: string | null;
}

export interface AuditoriaPaginadoOut {
  total: number;
  pagina: number;
  tamanio_pagina: number;
  items: AuditoriaOut[];
}

export interface FiltroAuditoria {
  usuario_id?: string | null;
  entidad?: string | null;
  entidad_id?: string | null;
  accion?: AccionAuditoria | null;
  desde?: string | null;
  hasta?: string | null;
}
