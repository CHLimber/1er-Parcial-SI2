export interface ProductoOut {
  id: string;
  codigo: string;
  nombre: string;
  slug: string;
  descripcion: string | null;
  precio_base: number;
  genero: string | null;
  categoria: string;
  marca: string | null;
  destacado: boolean;
}
