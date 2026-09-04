export interface ReservaItemIn {
  variante_id: string;
  cantidad: number;
}

export interface ReservaCrear {
  sucursal_id: string;
  fecha_visita: string;
  hora_visita: string;
  observaciones?: string | null;
  items: ReservaItemIn[];
}

export interface ItemRechazadoOut {
  variante_id: string;
  sku: string;
  motivo: string;
}

export interface ReservaItemOut {
  id: string;
  variante_id: string;
  sku: string;
  producto: string;
  talla: string;
  color: string;
  cantidad: number;
  estado_item: string;
}

export interface ReservaOut {
  id: string;
  codigo: string;
  sucursal_id: string;
  sucursal: string;
  estado: string;
  fecha_visita: string;
  hora_visita: string;
  expira_en: string;
  creada_en: string;
  observaciones: string | null;
  items: ReservaItemOut[];
  items_rechazados: ItemRechazadoOut[];
}
