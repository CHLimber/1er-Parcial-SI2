/** Espejo manual de backend/app/modules/notificaciones/schemas.py (PENDIENTES.txt 2.19.3). */

export type TipoNotificacion = 'RESERVA' | 'VENTA' | 'STOCK' | 'PROMO';

export interface NotificacionOut {
  id: string;
  tipo: TipoNotificacion;
  titulo: string;
  mensaje: string;
  /** A que apunta el aviso: RESERVA, VENTA, ENVIO, ... (texto libre en la tabla, no ENUM). */
  entidad_tipo: string | null;
  entidad_id: string | null;
  /** Venta resuelta por el backend (la propia si entidad_tipo es VENTA, la del envio si es
   * ENVIO), para abrir /compra/{venta_id} sin conocer la tabla envio. */
  venta_id: string | null;
  leida: boolean;
  fecha: string;
}

export interface NotificacionPaginadoOut {
  total: number;
  no_leidas: number;
  pagina: number;
  tamanio_pagina: number;
  items: NotificacionOut[];
}

export interface CantidadNoLeidasOut {
  no_leidas: number;
}

export interface LeerTodasOut {
  marcadas: number;
}
