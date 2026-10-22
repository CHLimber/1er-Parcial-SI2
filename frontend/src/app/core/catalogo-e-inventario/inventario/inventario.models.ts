/** Espejo manual de app/modules/inventario/schemas.py (PENDIENTES.txt 2.6, ajustes manuales). */

export interface VarianteBuscadaOut {
  id: string;
  sku: string;
  producto: string;
  talla: string;
  color: string;
  codigo_hex: string;
  sucursal_id: string;
  sucursal: string;
  cantidad_fisica: number;
  cantidad_reservada: number;
  disponible: number;
}

export interface AjusteIn {
  sucursal_id: string;
  variante_id: string;
  cantidad_fisica_nueva: number;
  motivo: string;
}

export interface AjusteOut {
  movimiento_id: number;
  sucursal_id: string;
  variante_id: string;
  saldo_anterior: number;
  saldo_nuevo: number;
  motivo: string;
  fecha: string;
}

/**
 * saldo_anterior/saldo_nuevo son el DISPONIBLE (fisico - reservado) para todos los tipos
 * salvo AJUSTE, donde son cantidad_fisica cruda (fn_mover_inventario, db/02_logica.sql).
 */
export interface MovimientoKardexOut {
  id: number;
  tipo: string;
  cantidad: number;
  saldo_anterior: number;
  saldo_nuevo: number;
  motivo: string | null;
  documento_tipo: string | null;
  documento_id: string | null;
  usuario: string | null;
  fecha: string;
}
