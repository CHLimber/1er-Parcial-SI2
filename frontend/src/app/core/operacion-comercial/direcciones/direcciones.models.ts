// Espejo manual de app/modules/direcciones/schemas.py (CU20).

export type CiudadBO =
  | 'SANTA_CRUZ'
  | 'LA_PAZ'
  | 'EL_ALTO'
  | 'COCHABAMBA'
  | 'SUCRE'
  | 'ORURO'
  | 'POTOSI'
  | 'TARIJA'
  | 'TRINIDAD'
  | 'COBIJA';

export const CIUDADES: { valor: CiudadBO; etiqueta: string }[] = [
  { valor: 'SANTA_CRUZ', etiqueta: 'Santa Cruz' },
  { valor: 'LA_PAZ', etiqueta: 'La Paz' },
  { valor: 'EL_ALTO', etiqueta: 'El Alto' },
  { valor: 'COCHABAMBA', etiqueta: 'Cochabamba' },
  { valor: 'SUCRE', etiqueta: 'Sucre' },
  { valor: 'ORURO', etiqueta: 'Oruro' },
  { valor: 'POTOSI', etiqueta: 'Potosi' },
  { valor: 'TARIJA', etiqueta: 'Tarija' },
  { valor: 'TRINIDAD', etiqueta: 'Trinidad' },
  { valor: 'COBIJA', etiqueta: 'Cobija' },
];

export interface DireccionIn {
  alias: string;
  ciudad: CiudadBO;
  direccion: string;
  referencia: string | null;
  latitud: number | null;
  longitud: number | null;
  es_principal: boolean;
}

export interface DireccionOut {
  id: string;
  alias: string;
  ciudad: string;
  direccion: string;
  referencia: string | null;
  latitud: number | null;
  longitud: number | null;
  es_principal: boolean;
}

export interface SugerenciaDireccionOut {
  etiqueta: string;
  latitud: number;
  longitud: number;
  ciudad: string | null;
}

export interface BusquedaDireccionOut {
  geocodificador_disponible: boolean;
  resultados: SugerenciaDireccionOut[];
}
