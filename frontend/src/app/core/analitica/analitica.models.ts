/** Espejo manual de lo que devuelve backend/app/modules/analitica/router.py (Modulo G). */

export interface MetricasRegresion {
  mae: number;
  rmse: number;
  r2: number;
  mape: number;
}

export interface ResumenModelo {
  entrenado_en: string;
  semilla: number;
  demanda: {
    metricas: Record<'random_forest' | 'regresion_lineal' | 'ingenuo_semana_anterior', MetricasRegresion>;
    cv_mae: number[];
    importancias: { variable: string; importancia: number }[];
    filas: number;
    filas_entrenamiento: number;
    filas_prueba: number;
    periodo: [string, string];
  };
  clientes: {
    k: number;
    silueta: number;
    ari_vs_perfiles: number;
    evaluacion_k: { k: number; silueta: number; inercia: number }[];
    nombres: string[];
    filas: number;
  };
}

export type TipoPrenda = 'VERANO' | 'INVIERNO' | 'ATEMPORAL' | 'ACCESORIO';

export interface PronosticoDia {
  dia: string;
  verano: number;
  invierno: number;
  atemporal: number;
  accesorio: number;
  total: number;
}

export interface PronosticoSucursal {
  sucursal: string;
  tipo: TipoPrenda;
  real_ultimos_dias: number;
  pronostico: number;
  variacion_pct: number | null;
}

export interface Segmento {
  segmento: string;
  clientas: number;
  monto_promedio: number;
  compras_promedio: number;
  recencia_promedio: number;
  ejemplos: { nombre: string; email: string }[];
}

export interface DiaAtipico {
  sucursal: string;
  dia: string;
  total: number;
  tickets: number;
  mediana_sucursal: number;
  tipo: 'PICO' | 'CAIDA';
}

export interface DashboardAnalitico {
  empresa_id: string;
  sucursales: string[];
  horizonte: number;
  indicadores: {
    unidades_pronosticadas: number;
    unidades_ultimos_dias: number;
    variacion_pct: number | null;
    clientas_segmentadas: number;
    dias_atipicos: number;
  };
  pronostico_diario: PronosticoDia[];
  pronostico_por_sucursal: PronosticoSucursal[];
  segmentos: Segmento[];
  anomalias: DiaAtipico[];
  hallazgos: string[];
  modelo: ResumenModelo;
}

export interface MuestraSinteticos {
  columnas: string[];
  filas: (string | number)[][];
  total_generado: number;
}
