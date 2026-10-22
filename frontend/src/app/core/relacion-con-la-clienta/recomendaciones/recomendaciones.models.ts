import { ProductoOut } from '../../catalogo-e-inventario/catalogo/catalogo.models';

export interface ProductoRecomendadoOut extends ProductoOut {
  /** Por que se sugiere esta prenda (CU17): historial del cliente, destacado o tendencia. */
  motivo: string;
}
