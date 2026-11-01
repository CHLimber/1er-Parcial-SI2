-- Indices de rendimiento (PENDIENTES 9.11). Solo agregan indices: no cambian columnas, tipos ni
-- semantica. Es idempotente (IF NOT EXISTS) y ya esta incorporado a db/01_schema.sql, asi que
-- solo hace falta aplicarlo a bases creadas ANTES de este cambio:
--   docker exec -i fashionstore-db-1 psql -U fashionstore -d fashionstore -v ON_ERROR_STOP=1 \
--       < db/reparaciones/indices_rendimiento.sql
--
-- Criterio: claves foraneas que los routers usan en WHERE/JOIN y que Postgres no indexa solo,
-- y los listados por sucursal/usuario de las pantallas de gestion.

-- Lineas de cada documento (se cargan por documento al abrir el detalle). venta_detalle(venta_id)
-- es la FK mas consultada del sistema: totales, devoluciones, alerta de stock tras cada venta,
-- reportes. Los otros detalles se leen igual por su cabecera.
CREATE INDEX IF NOT EXISTS ix_venta_detalle_venta           ON venta_detalle(venta_id);
CREATE INDEX IF NOT EXISTS ix_recepcion_detalle_recepcion   ON recepcion_detalle(recepcion_id);
CREATE INDEX IF NOT EXISTS ix_traspaso_detalle_traspaso     ON traspaso_detalle(traspaso_id);
CREATE INDEX IF NOT EXISTS ix_devolucion_detalle_devolucion ON devolucion_detalle(devolucion_id);
-- cuanto de cada linea de venta ya se devolvio (devoluciones/router.py::_lineas_de_venta)
CREATE INDEX IF NOT EXISTS ix_devolucion_detalle_linea      ON devolucion_detalle(venta_detalle_id);
CREATE INDEX IF NOT EXISTS ix_reserva_historial_reserva     ON reserva_historial(reserva_id, fecha);

-- Listados de gestion por sucursal, del mas reciente al mas viejo
CREATE INDEX IF NOT EXISTS ix_recepcion_sucursal   ON recepcion(sucursal_id, fecha DESC);
CREATE INDEX IF NOT EXISTS ix_recepcion_proveedor  ON recepcion(proveedor_id);
CREATE INDEX IF NOT EXISTS ix_traspaso_origen      ON traspaso(sucursal_origen_id, fecha_solicitud DESC);
CREATE INDEX IF NOT EXISTS ix_traspaso_destino     ON traspaso(sucursal_destino_id, fecha_solicitud DESC);
CREATE INDEX IF NOT EXISTS ix_devolucion_sucursal  ON devolucion(sucursal_id, fecha DESC);
CREATE INDEX IF NOT EXISTS ix_movimiento_sucursal  ON movimiento_inventario(sucursal_id, fecha DESC);

-- Ventas: la reserva de origen (reservas/router.py pregunta si hay un pago en curso sobre ella) y
-- los pedidos PENDIENTES que el job de vencimiento revisa en cada pasada (indice parcial, chico)
CREATE INDEX IF NOT EXISTS ix_venta_reserva    ON venta(reserva_id) WHERE reserva_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_venta_pendiente  ON venta(fecha) WHERE estado = 'PENDIENTE';

-- Notificaciones: GET /notificaciones lista TODAS las del usuario (ix_notificacion_pendiente solo
-- cubre las no leidas) y la campana de la web/movil lo consulta cada 60 s
CREATE INDEX IF NOT EXISTS ix_notificacion_usuario ON notificacion(usuario_id, fecha DESC);

-- Conteos del listado de proveedores y baja de personal con caja abierta
CREATE INDEX IF NOT EXISTS ix_proveedor_empresa     ON proveedor(empresa_id);
CREATE INDEX IF NOT EXISTS ix_producto_proveedor    ON producto(proveedor_id) WHERE proveedor_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_sesion_caja_empleado  ON sesion_caja(empleado_id) WHERE estado = 'ABIERTA';
