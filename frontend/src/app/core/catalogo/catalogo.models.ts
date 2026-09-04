export interface ProductoOut {
  id: string;
  codigo: string;
  nombre: string;
  slug: string;
  descripcion: string | null;
  precio_base: number;
  genero: string | null;
  categoria: string;
  categoria_slug: string;
  marca: string | null;
  destacado: boolean;
  imagen_url: string | null;
  tallas: string[];
  agotado: boolean;
}

export interface CategoriaOut {
  id: string;
  nombre: string;
  slug: string;
  categoria_padre_id: string | null;
}

export interface TallaOut {
  id: number;
  codigo: string;
  tipo: string;
}

export interface ColorOut {
  id: number;
  nombre: string;
  codigo_hex: string;
}

export interface TemporadaOut {
  id: string;
  nombre: string;
  tipo: string;
}

export interface FiltrosOut {
  categorias: CategoriaOut[];
  tallas: TallaOut[];
  colores: ColorOut[];
  temporadas: TemporadaOut[];
}

export interface FiltrosCatalogo {
  categoriaSlug?: string;
  q?: string;
  temporadaId?: string;
  tallaId?: number;
  colorId?: number;
  limit?: number;
  offset?: number;
}

export interface DisponibilidadSucursalOut {
  sucursal_id: string;
  sucursal: string;
  ciudad: string;
  disponible: number;
  situacion: string;
}

export interface VarianteOut {
  id: string;
  sku: string;
  talla: string;
  color: string;
  codigo_hex: string;
  precio: number;
  disponibilidad: DisponibilidadSucursalOut[];
}

export interface ProductoDetalleOut extends ProductoOut {
  material: string | null;
  variantes: VarianteOut[];
}
