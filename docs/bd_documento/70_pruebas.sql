

-- ---------------------------------------------------------------------
--  8.2.6.4  PRUEBAS DE EJECUCION
--  Cada bloque muestra el estado antes, ejecuta y muestra el estado despues. Los casos de
--  error se envuelven en un bloque DO con EXCEPTION para que el script siga corriendo y el
--  mensaje quede como NOTICE.
-- ---------------------------------------------------------------------

-- ===== a) Procedimientos =====

-- sp_venta_pos: vende 1 vestido y 2 blusas en la caja abierta de Santa Cruz
SELECT pv.sku, i.cantidad_fisica, i.disponible
  FROM inventario i JOIN producto_variante pv ON pv.id = i.variante_id
 WHERE i.sucursal_id = (SELECT id FROM sucursal WHERE codigo = 'SC-01')
   AND pv.sku IN ('VES-001-M-Bei', 'BLU-001-L-Neg');

CALL sp_venta_pos('d1000000-0000-4000-8000-000000000003',
                  '[{"sku": "VES-001-M-Bei", "cantidad": 1}, {"sku": "BLU-001-L-Neg", "cantidad": 2}]',
                  'EFECTIVO');

SELECT pv.sku, i.cantidad_fisica, i.disponible
  FROM inventario i JOIN producto_variante pv ON pv.id = i.variante_id
 WHERE i.sucursal_id = (SELECT id FROM sucursal WHERE codigo = 'SC-01')
   AND pv.sku IN ('VES-001-M-Bei', 'BLU-001-L-Neg');

-- sp_venta_pos con stock insuficiente: la venta entera se deshace (no queda venta a medias)
DO $$
DECLARE
    v_numero VARCHAR;
BEGIN
    CALL sp_venta_pos('d1000000-0000-4000-8000-000000000003',
                      '[{"sku": "BLU-001-L-Neg", "cantidad": 1}, {"sku": "ABR-001-S-Neg", "cantidad": 50}]',
                      'EFECTIVO', v_numero);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Venta rechazada y revertida: %', SQLERRM;
END;
$$;

-- sp_cerrar_sesion_caja: arqueo de la caja de hoy en Santa Cruz (la cajera cuenta Bs 1070,
-- un faltante de Bs 3.60 frente a lo que dice el sistema)
SELECT fn_total_efectivo_sesion('d1000000-0000-4000-8000-000000000003') AS efectivo_cobrado;
CALL sp_cerrar_sesion_caja('d1000000-0000-4000-8000-000000000003', 1070.00);
SELECT estado, monto_inicial, monto_sistema, monto_declarado, diferencia
  FROM sesion_caja WHERE id = 'd1000000-0000-4000-8000-000000000003';

-- sp_ajustar_stock: el recuento encontro 21 blusas XS blancas en Santa Cruz (el sistema dice 22)
CALL sp_ajustar_stock('SC-01', 'BLU-001-XS-Bla', 21, 'Recuento semanal: una prenda danada',
                      'almacen.scz@fashionstore.bo');
SELECT tipo, cantidad, saldo_anterior, saldo_nuevo, motivo
  FROM movimiento_inventario
 WHERE documento_tipo = 'AJUSTE'
 ORDER BY id DESC LIMIT 1;

-- sp_expirar_reservas: se registra una reserva que ya vencio y el job la expira
INSERT INTO reserva (id, usuario_id, sucursal_id, codigo, fecha_visita, hora_visita, expira_en, estado)
VALUES ('c1000000-0000-4000-8000-000000000004',
        (SELECT id FROM usuario WHERE email = 'cliente2@fashionstore.bo'),
        (SELECT id FROM sucursal WHERE codigo = 'OR-01'), 'RES-0000000004',
        CURRENT_DATE - 1, '10:00', now() - interval '1 hour', 'CONFIRMADA');
INSERT INTO reserva_detalle (reserva_id, variante_id, cantidad)
VALUES ('c1000000-0000-4000-8000-000000000004',
        (SELECT id FROM producto_variante WHERE sku = 'ABR-001-S-Neg'), 1);

CALL sp_expirar_reservas();
SELECT r.codigo, r.estado, rd.estado_item
  FROM reserva r JOIN reserva_detalle rd ON rd.reserva_id = r.id
 WHERE r.id = 'c1000000-0000-4000-8000-000000000004';

-- sp_renovar_suscripcion: Moda Urbana paga un mes y vuelve a quedar ACTIVA
CALL sp_renovar_suscripcion('moda-urbana', 1);
SELECT e.nombre, su.estado, su.vence_en::date
  FROM suscripcion su JOIN empresa e ON e.id = su.empresa_id
 WHERE e.slug = 'moda-urbana';


-- ===== b) Funciones =====

-- fn_cotizar_envio: domicilio a 2.5 km por una compra de Bs 305.82 (la tarifa por km ya es 4)
SELECT * FROM fn_cotizar_envio(2.5, 305.82);
-- Compra desde Bs 800: el envio sale gratis
SELECT * FROM fn_cotizar_envio(5.0, 950.00);
-- 15 km: fuera del radio de reparto de la sucursal
SELECT costo, dentro_cobertura FROM fn_cotizar_envio(15.0, 200.00);

-- fn_total_efectivo_sesion: efectivo de la sesion de ayer en La Paz (cerrada con faltante)
SELECT fn_total_efectivo_sesion('d1000000-0000-4000-8000-000000000002') AS efectivo_la_paz;

-- fn_mover_inventario: entrada directa de 5 unidades y su asiento en el kardex
SELECT fn_mover_inventario((SELECT id FROM sucursal WHERE codigo = 'TJ-01'),
                           (SELECT id FROM producto_variante WHERE sku = 'BLU-001-M-Bla'),
                           'ENTRADA', 5, 'Prueba de la funcion', NULL, NULL, NULL) AS movimiento_id;
SELECT tipo, cantidad, saldo_anterior, saldo_nuevo FROM movimiento_inventario ORDER BY id DESC LIMIT 1;

-- fn_mover_inventario rechaza una salida mayor al disponible
DO $$
BEGIN
    PERFORM fn_mover_inventario((SELECT id FROM sucursal WHERE codigo = 'TJ-01'),
                                (SELECT id FROM producto_variante WHERE sku = 'BLU-001-M-Bla'),
                                'SALIDA', 999, 'Prueba de error', NULL, NULL, NULL);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Rechazado: %', SQLERRM;
END;
$$;

-- fn_mover_inventario rechaza mover stock de una prenda de OTRA empresa (multi-tenant)
DO $$
BEGIN
    PERFORM fn_mover_inventario((SELECT id FROM sucursal WHERE codigo = 'SC-01'),
                                (SELECT id FROM producto_variante WHERE sku = 'AND-001-M-Gri'),
                                'ENTRADA', 1, 'Prueba de aislamiento', NULL, NULL, NULL);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Rechazado: %', SQLERRM;
END;
$$;


-- ===== c) Triggers =====

-- tg_reserva_compromete_stock: una reserva nueva sube cantidad_reservada (no toca lo fisico)
SELECT cantidad_fisica, cantidad_reservada, disponible FROM inventario
 WHERE sucursal_id = (SELECT id FROM sucursal WHERE codigo = 'CB-01')
   AND variante_id = (SELECT id FROM producto_variante WHERE sku = 'PAN-001-40-Azu');

INSERT INTO reserva (id, usuario_id, sucursal_id, codigo, fecha_visita, hora_visita, expira_en)
VALUES ('c1000000-0000-4000-8000-000000000003',
        (SELECT id FROM usuario WHERE email = 'andrea.lopez@gmail.com'),
        (SELECT id FROM sucursal WHERE codigo = 'CB-01'), 'RES-0000000003',
        CURRENT_DATE + 2, '11:00', (CURRENT_DATE + 2) + time '11:00' + interval '4 hours');
INSERT INTO reserva_detalle (reserva_id, variante_id, cantidad)
VALUES ('c1000000-0000-4000-8000-000000000003',
        (SELECT id FROM producto_variante WHERE sku = 'PAN-001-40-Azu'), 2);

SELECT cantidad_fisica, cantidad_reservada, disponible FROM inventario
 WHERE sucursal_id = (SELECT id FROM sucursal WHERE codigo = 'CB-01')
   AND variante_id = (SELECT id FROM producto_variante WHERE sku = 'PAN-001-40-Azu');

-- tg_reserva_historial: la encargada confirma la reserva y queda el asiento en el historial
UPDATE reserva
   SET estado = 'CONFIRMADA', vestidor_asignado = 'V-2',
       atendida_por_id = (SELECT id FROM usuario WHERE email = 'admin@fashionstore.bo')
 WHERE id = 'c1000000-0000-4000-8000-000000000001';
SELECT estado_anterior, estado_nuevo, fecha FROM reserva_historial
 WHERE reserva_id = 'c1000000-0000-4000-8000-000000000001';

-- tg_venta_descuenta_stock: la clienta de La Paz se prueba el tapado reservado y lo compra.
-- Como la venta nace de la reserva, el trigger primero LIBERA el compromiso y despues descuenta.
INSERT INTO venta (id, sucursal_id, usuario_id, canal, entrega, reserva_id, numero,
                   subtotal, descuento, iva, total, estado, registrada_por_id)
VALUES ('b1000000-0000-4000-8000-000000000009', (SELECT id FROM sucursal WHERE codigo = 'LP-01'),
        (SELECT id FROM usuario WHERE email = 'cliente2@fashionstore.bo'), 'POS', 'RETIRO_SUCURSAL',
        'c1000000-0000-4000-8000-000000000002', 'V-LP00000003', 449.90, 0, 58.49, 508.39, 'ENTREGADA',
        (SELECT id FROM usuario WHERE email = 'encargada.lapaz@fashionstore.bo'));
INSERT INTO venta_detalle (venta_id, variante_id, cantidad, precio_unitario, subtotal)
VALUES ('b1000000-0000-4000-8000-000000000009',
        (SELECT id FROM producto_variante WHERE sku = 'ABR-001-L-Cam'), 1, 449.90, 449.90);
INSERT INTO pago (venta_id, metodo, monto, estado, confirmado_en)
VALUES ('b1000000-0000-4000-8000-000000000009', 'TARJETA', 508.39, 'APROBADO', now());
UPDATE reserva_detalle SET estado_item = 'COMPRADO' WHERE reserva_id = 'c1000000-0000-4000-8000-000000000002';
UPDATE reserva SET estado = 'CONVERTIDA', atendida_en = now()
 WHERE id = 'c1000000-0000-4000-8000-000000000002';

SELECT tipo, cantidad, saldo_anterior, saldo_nuevo, motivo
  FROM movimiento_inventario
 WHERE documento_id = 'b1000000-0000-4000-8000-000000000009'
 ORDER BY id;

-- tg_confirmar_recepcion: al confirmar la recepcion entra el stock de cada linea
UPDATE recepcion SET estado = 'CONFIRMADA' WHERE id = 'f1000000-0000-4000-8000-000000000001';
SELECT pv.sku, m.tipo, m.cantidad, m.saldo_anterior, m.saldo_nuevo
  FROM movimiento_inventario m JOIN producto_variante pv ON pv.id = m.variante_id
 WHERE m.documento_id = 'f1000000-0000-4000-8000-000000000001';

-- tg_traspaso_stock: sale del origen al despachar y entra en destino lo que llego
UPDATE traspaso
   SET estado = 'EN_TRANSITO', fecha_despacho = now(),
       actualizado_por_id = (SELECT id FROM usuario WHERE email = 'encargado.cbba@fashionstore.bo')
 WHERE id = 'f2000000-0000-4000-8000-000000000001';

UPDATE traspaso_detalle
   SET cantidad_recibida = CASE WHEN variante_id = (SELECT id FROM producto_variante WHERE sku = 'VES-001-M-Neg')
                                THEN 3 ELSE 1 END     -- de los vestidos beige llego 1 de 2
 WHERE traspaso_id = 'f2000000-0000-4000-8000-000000000001';

UPDATE traspaso
   SET estado = 'RECIBIDO', fecha_recepcion = now(), observacion = 'Llego un vestido beige de menos',
       usuario_recibe_id = (SELECT id FROM usuario WHERE email = 'admin@fashionstore.bo'),
       actualizado_por_id = (SELECT id FROM usuario WHERE email = 'admin@fashionstore.bo')
 WHERE id = 'f2000000-0000-4000-8000-000000000001';

SELECT s.codigo AS sucursal, pv.sku, m.tipo, m.cantidad
  FROM movimiento_inventario m
  JOIN sucursal s           ON s.id  = m.sucursal_id
  JOIN producto_variante pv ON pv.id = m.variante_id
 WHERE m.documento_id = 'f2000000-0000-4000-8000-000000000001'
 ORDER BY m.id;

-- Un traspaso RECIBIDO no puede volver a cambiar de estado
DO $$
BEGIN
    UPDATE traspaso SET estado = 'ANULADO' WHERE id = 'f2000000-0000-4000-8000-000000000001';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Rechazado: %', SQLERRM;
END;
$$;

-- tg_devolucion_stock: al aprobar la devolucion el vestido vuelve al stock de Santa Cruz
UPDATE devolucion
   SET estado = 'APROBADA', resuelta_en = now(),
       resuelta_por_id = (SELECT id FROM usuario WHERE email = 'admin@fashionstore.bo')
 WHERE id = 'f3000000-0000-4000-8000-000000000001';
SELECT d.numero, m.tipo, m.cantidad, m.saldo_anterior, m.saldo_nuevo
  FROM movimiento_inventario m JOIN devolucion d ON d.id = m.documento_id
 WHERE m.documento_id = 'f3000000-0000-4000-8000-000000000001';

-- Una devolucion ya resuelta no cambia mas de estado
DO $$
BEGIN
    UPDATE devolucion SET estado = 'RECHAZADA' WHERE id = 'f3000000-0000-4000-8000-000000000001';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Rechazado: %', SQLERRM;
END;
$$;

-- tg_envio_historial: cada cambio de estado del envio deja un evento firmado
UPDATE envio
   SET estado = 'DESPACHADO', despachado_en = now(), observacion = 'Entregado al delivery externo',
       actualizado_por_id = (SELECT id FROM usuario WHERE email = 'admin@fashionstore.bo')
 WHERE id = 'f5000000-0000-4000-8000-000000000001';
UPDATE envio
   SET estado = 'ENTREGADO', cerrado_en = now(), observacion = 'El delivery confirmo la entrega',
       actualizado_por_id = (SELECT id FROM usuario WHERE email = 'admin@fashionstore.bo')
 WHERE id = 'f5000000-0000-4000-8000-000000000001';
SELECT estado, nota, fecha FROM envio_evento
 WHERE envio_id = 'f5000000-0000-4000-8000-000000000001'
 ORDER BY fecha;

-- Kardex completo generado por los triggers y las funciones en estas pruebas
SELECT m.id, s.codigo AS sucursal, pv.sku, m.tipo, m.cantidad, m.saldo_anterior,
       m.saldo_nuevo, m.documento_tipo, m.motivo
  FROM movimiento_inventario m
  JOIN sucursal s           ON s.id  = m.sucursal_id
  JOIN producto_variante pv ON pv.id = m.variante_id
 ORDER BY m.id;
