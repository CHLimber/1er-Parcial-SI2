/** Espejo manual de los schemas Pydantic de backend/app/modules/plataforma_saas/backups. */

export type TipoBackup = 'AUTOMATICO' | 'MANUAL';
export type EstadoBackup = 'EN_CURSO' | 'COMPLETADO' | 'FALLIDO';

export interface BackupOut {
  id: string;
  /** null = copia general de la plataforma */
  empresa_id: string | null;
  empresa: string | null;
  tipo: TipoBackup;
  estado: EstadoBackup;
  iniciado_en: string;
  terminado_en: string | null;
  duracion_segundos: number | null;
  /** null = lo hizo el sistema (copia automatica) */
  creado_por: string | null;
  tamano_bytes: number | null;
  total_tablas: number | null;
  total_filas: number | null;
  sha256: string | null;
  /** false si el archivo ya no esta en el servidor */
  disponible: boolean;
  error: string | null;
  tablas: Record<string, number> | null;
}

export interface ProgramacionOut {
  activa: boolean;
  frecuencia: string;
  hora: string;
  zona: string;
  proxima_ejecucion: string | null;
  retencion_automaticas: number;
  retencion_manuales: number;
  ultima: BackupOut | null;
  ultima_exitosa: BackupOut | null;
}
