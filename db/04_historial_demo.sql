-- =====================================================================
--  FashionStore - Historial demo de ventas y mermas (Segundo parcial)
--
--  60 dias de ventas POS en todas las sucursales activas, para que los reportes de CU15 (y la
--  consulta con IA de varias sucursales, PENDIENTES 5.11), las sugerencias de traspaso por
--  demanda (5.12) y el reporte de perdidas (5.13) tengan datos con que trabajar apenas se
--  levanta la base.
--
--  Patron de demanda: cada sucursal vende de 1 a 3 tickets por dia, eligiendo prendas segun lo
--  que tiene disponible (asi el clima de cada ciudad ya pesa, porque el stock se repartio por
--  clima). En las ultimas 2 semanas entra el calor: Tarija y Santa Cruz suman tickets y se
--  inclinan a Primavera-Verano, sobre todo a 6 prendas "tendencia" de la temporada. Eso es lo
--  que detecta GET /traspasos/sugerencias (demanda que crece y stock que no alcanza).
--
--  Todo pasa por las tablas de siempre: venta_detalle dispara tg_venta_descuenta_stock, que
--  descuenta con fn_mover_inventario (el kardex queda con fecha de hoy, la venta con su fecha
--  historica). Cada dia es una sesion de caja CERRADA con el arqueo cuadrado.
--
--  Re-ejecutable: si ya hay ventas 'H-%' no hace nada. Tambien se puede correr sobre una base
--  existente (Railway / Docker con volumen) despues de db/reparaciones/segundo_parcial.sql.
-- =====================================================================

DO $$
DECLARE
    r_suc    RECORD;
    r_var    RECORD;
    v_dia    DATE;
    v_ses    UUID;
    v_caja   UUID;
    v_emp    UUID;
    v_venta  UUID;
    v_tickets INT;
    v_lineas INT;
    v_sub    NUMERIC(12,2);
    v_iva    NUMERIC(12,2);
    v_efectivo NUMERIC(12,2);
    v_seq    INT := 0;
    v_reciente BOOLEAN;
    v_calor  BOOLEAN;
    v_tendencia UUID[];
BEGIN
    IF EXISTS (SELECT 1 FROM venta WHERE numero LIKE 'H-%') THEN
        RAISE NOTICE 'Historial demo ya cargado: no se hace nada';
        RETURN;
    END IF;

    PERFORM setseed(0.42);

    SELECT array_agg(id) INTO v_tendencia FROM (
        SELECT pv.id
          FROM producto_variante pv
          JOIN producto p  ON p.id = pv.producto_id
          JOIN temporada t ON t.id = p.temporada_id AND t.tipo = 'PRIMAVERA_VERANO'
         WHERE pv.activa
         ORDER BY random()
         LIMIT 6) x;

    FOR r_suc IN SELECT id, codigo, ciudad FROM sucursal WHERE activa ORDER BY codigo LOOP
        SELECT id INTO v_caja FROM caja WHERE sucursal_id = r_suc.id ORDER BY codigo LIMIT 1;
        SELECT usuario_id INTO v_emp
          FROM empleado
         WHERE sucursal_id = r_suc.id AND cargo IN ('CAJERO','ENCARGADO')
         ORDER BY (cargo = 'CAJERO') DESC
         LIMIT 1;
        CONTINUE WHEN v_caja IS NULL OR v_emp IS NULL;

        FOR v_dia IN
            SELECT d::date FROM generate_series(CURRENT_DATE - 60, CURRENT_DATE - 1, interval '1 day') d
        LOOP
            v_reciente := v_dia >= CURRENT_DATE - 14;
            v_calor := v_reciente AND r_suc.ciudad IN ('TARIJA','SANTA_CRUZ');

            INSERT INTO sesion_caja (caja_id, empleado_id, abierta_en, monto_inicial,
                                     cerrada_en, monto_sistema, monto_declarado, estado)
            VALUES (v_caja, v_emp, v_dia + time '09:00', 200, v_dia + time '20:00', 200, 200, 'CERRADA')
            RETURNING id INTO v_ses;
            v_efectivo := 0;

            v_tickets := 1 + floor(random() * 3)::int;
            IF v_calor THEN
                v_tickets := v_tickets + 2 + floor(random() * 3)::int;
            END IF;

            FOR i IN 1..v_tickets LOOP
                v_seq := v_seq + 1;
                INSERT INTO venta (sucursal_id, canal, sesion_caja_id, numero, fecha,
                                   subtotal, iva, total, estado, registrada_por_id)
                VALUES (r_suc.id, 'POS', v_ses, 'H-' || lpad(v_seq::text, 6, '0'),
                        v_dia + time '10:00' + random() * interval '9 hours',
                        0, 0, 0, 'ENTREGADA', v_emp)
                RETURNING id INTO v_venta;

                v_sub := 0;
                v_lineas := 1 + floor(random() * 2)::int;
                FOR r_var IN
                    SELECT pv.id, COALESCE(pv.precio, p.precio_base) AS precio
                      FROM inventario inv
                      JOIN producto_variante pv ON pv.id = inv.variante_id AND pv.activa
                      JOIN producto p           ON p.id = pv.producto_id
                      LEFT JOIN temporada t     ON t.id = p.temporada_id
                     WHERE inv.sucursal_id = r_suc.id AND inv.disponible > 1
                     ORDER BY random() * inv.disponible
                              * CASE WHEN v_calor AND pv.id = ANY(v_tendencia) THEN 60
                                     WHEN v_calor AND t.tipo = 'PRIMAVERA_VERANO' THEN 4
                                     ELSE 1 END DESC
                     LIMIT v_lineas
                LOOP
                    INSERT INTO venta_detalle (venta_id, variante_id, cantidad, precio_unitario, subtotal)
                    VALUES (v_venta, r_var.id, 1, r_var.precio, r_var.precio);
                    v_sub := v_sub + r_var.precio;
                END LOOP;

                IF v_sub = 0 THEN
                    DELETE FROM venta WHERE id = v_venta;  -- sin stock para vender: no hubo ticket
                    CONTINUE;
                END IF;

                v_iva := round(v_sub * 0.13, 2);
                UPDATE venta SET subtotal = v_sub, iva = v_iva, total = v_sub + v_iva WHERE id = v_venta;
                INSERT INTO pago (venta_id, metodo, monto, estado, creado_en, confirmado_en)
                SELECT v_venta, 'EFECTIVO', v_sub + v_iva, 'APROBADO', fecha, fecha
                  FROM venta WHERE id = v_venta;
                v_efectivo := v_efectivo + v_sub + v_iva;
            END LOOP;

            UPDATE sesion_caja
               SET monto_sistema = 200 + v_efectivo, monto_declarado = 200 + v_efectivo
             WHERE id = v_ses;
        END LOOP;
    END LOOP;

    -- Mermas (tema del parcial: perdida). Un recuento fisico por sucursal encuentra 1 o 2
    -- unidades menos en tres prendas (robo, mancha, rotura). Se registra como AJUSTE con el
    -- saldo contado, igual que lo hace el panel de inventario.
    FOR r_suc IN SELECT id FROM sucursal WHERE activa LOOP
        FOR r_var IN
            SELECT inv.variante_id, inv.cantidad_fisica
              FROM inventario inv
             WHERE inv.sucursal_id = r_suc.id AND inv.cantidad_fisica - inv.cantidad_reservada >= 3
             ORDER BY random()
             LIMIT 3
        LOOP
            PERFORM fn_mover_inventario(
                r_suc.id, r_var.variante_id, 'AJUSTE',
                r_var.cantidad_fisica - 1 - floor(random() * 2)::int,
                (ARRAY['Merma: prenda manchada en vitrina',
                       'Merma: faltante en recuento (posible robo)',
                       'Merma: costura rota en probador'])[1 + floor(random() * 3)::int],
                'AJUSTE', NULL, NULL);
        END LOOP;
    END LOOP;
END;
$$;
