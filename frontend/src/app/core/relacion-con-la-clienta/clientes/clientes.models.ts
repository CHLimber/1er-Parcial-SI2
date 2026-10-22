/** Espejo manual de backend/app/modules/clientes/schemas.py (cartera de clientas por tenant). */
export type Segmento = 'NUEVA' | 'FRECUENTE' | 'VIP' | 'INACTIVA';

export const SEGMENTOS: { valor: Segmento; etiqueta: string }[] = [
  { valor: 'NUEVA', etiqueta: 'Nueva' },
  { valor: 'FRECUENTE', etiqueta: 'Frecuente' },
  { valor: 'VIP', etiqueta: 'VIP' },
  { valor: 'INACTIVA', etiqueta: 'Inactiva' },
];

export interface PerfilClienteIn {
  /** null = usar el sugerido por el historial */
  segmento: Segmento | null;
  talla_habitual: string | null;
  estilo_preferido: string | null;
  telefono_contacto: string | null;
  acepta_whatsapp: boolean;
  notas: string | null;
}

export interface AltaClienteIn extends PerfilClienteIn {
  email: string;
}

export interface ClienteTenantOut {
  usuario_id: string;
  nombre: string;
  email: string;
  telefono: string | null;
  /** historial en ESTA sucursal */
  compras: number;
  total_comprado: number | string;
  ultima_compra: string | null;
  reservas: number;
  segmento_sugerido: Segmento;
  tiene_perfil: boolean;
  /** el fijado en la ficha o, si no hay, el sugerido */
  segmento: Segmento;
  talla_habitual: string | null;
  estilo_preferido: string | null;
  telefono_contacto: string | null;
  acepta_whatsapp: boolean;
  notas: string | null;
  actualizado_en: string | null;
  actualizado_por: string | null;
}
