/** Espejo manual de app/modules/catalogo/admin_schemas.py (CU10). */

export interface ProductoIn {
  codigo: string;
  nombre: string;
  descripcion: string | null;
  categoria_id: string;
  marca_id: string | null;
  proveedor_id: string | null;
  temporada_id: string | null;
  coleccion_id: string | null;
  material: string | null;
  genero: string | null;
  precio_base: number;
  destacado: boolean;
}

export interface VarianteIn {
  talla_id: number;
  color_id: number;
  sku: string;
  codigo_barras: string | null;
  precio: number | null;
  precio_oferta: number | null;
}

export interface ImagenIn {
  url: string;
  uso: string;
  formato: string | null;
  color_id: number | null;
  es_principal: boolean;
  orden: number;
}

export interface ImagenOut {
  id: string;
  url: string;
  uso: string;
  formato: string | null;
  color_id: number | null;
  es_principal: boolean;
  orden: number;
}

export interface VarianteAdminOut {
  id: string;
  sku: string;
  codigo_barras: string | null;
  talla_id: number;
  talla: string;
  color_id: number;
  color: string;
  codigo_hex: string;
  precio: number | null;
  precio_oferta: number | null;
  activa: boolean;
  stock_fisico: number;
  stock_disponible: number;
}

export interface ProductoAdminOut {
  id: string;
  codigo: string;
  nombre: string;
  slug: string;
  descripcion: string | null;
  categoria_id: string;
  categoria: string;
  marca_id: string | null;
  marca: string | null;
  proveedor_id: string | null;
  proveedor: string | null;
  temporada_id: string | null;
  temporada: string | null;
  coleccion_id: string | null;
  coleccion: string | null;
  material: string | null;
  genero: string | null;
  precio_base: number;
  destacado: boolean;
  activo: boolean;
  variantes_activas: number;
  stock_total: number;
}

export interface ProductoAdminDetalleOut extends ProductoAdminOut {
  variantes: VarianteAdminOut[];
  imagenes: ImagenOut[];
}

export interface CategoriaAdminOut {
  id: string;
  nombre: string;
  slug: string;
  categoria_padre_id: string | null;
  categoria_padre: string | null;
  imagen_url: string | null;
  orden: number;
  activa: boolean;
  productos: number;
}

export interface CategoriaIn {
  nombre: string;
  categoria_padre_id: string | null;
  imagen_url: string | null;
  orden: number;
}

export interface MarcaAdminOut {
  id: string;
  nombre: string;
  logo_url: string | null;
}

export interface OpcionOut {
  id: string;
  nombre: string;
}

export interface TemporadaAdminOut {
  id: string;
  nombre: string;
  tipo: string;
  fecha_inicio: string;
  fecha_fin: string;
}

export interface ColeccionOut {
  id: string;
  nombre: string;
  temporada_id: string;
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

export interface ReferenciasOut {
  categorias: CategoriaAdminOut[];
  marcas: MarcaAdminOut[];
  proveedores: OpcionOut[];
  temporadas: TemporadaAdminOut[];
  colecciones: ColeccionOut[];
  tallas: TallaOut[];
  colores: ColorOut[];
  generos: string[];
}

/** CU10 - Promociones (PENDIENTES.txt 2.1). */
export interface PromocionIn {
  nombre: string;
  codigo_cupon: string;
  tipo: string;
  valor: number;
  alcance: string;
  categoria_id: string | null;
  temporada_id: string | null;
  monto_minimo: number | null;
  fecha_inicio: string;
  fecha_fin: string;
  uso_maximo: number | null;
}

export interface PromocionEstadoIn {
  activa: boolean;
}

export interface PromocionAdminOut {
  id: string;
  nombre: string;
  codigo_cupon: string;
  tipo: string;
  valor: number;
  alcance: string;
  categoria_id: string | null;
  categoria: string | null;
  temporada_id: string | null;
  temporada: string | null;
  monto_minimo: number | null;
  fecha_inicio: string;
  fecha_fin: string;
  uso_maximo: number | null;
  usos_actuales: number;
  activa: boolean;
}
