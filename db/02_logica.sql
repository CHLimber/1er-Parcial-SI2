-- =====================================================================
--  FashionStore - Logica de negocio en base de datos
--  Vistas, funciones y triggers que sostienen inventario y reservas
-- =====================================================================
 
-- ---------------------------------------------------------------------
--  VISTAS DE CONSULTA
-- ---------------------------------------------------------------------
 
-- Disponibilidad consolidada por prenda y sucursal (RF08, RF21)
CREATE OR REPLACE VIEW v_disponibilidad AS
SELECT
    p.id                AS producto_id,
    p.nombre            AS producto,
    pv.id               AS variante_id,
    pv.sku,
    t.codigo            AS talla,
    c.nombre            AS color,
    s.id                AS sucursal_id,
    s.nombre            AS sucursal,
    s.ciudad,
    i.cantidad_fisica,
    i.cantidad_reservada,
    i.disponible,
    CASE
        WHEN i.disponible > 0                    THEN 'DISPONIBLE'
        WHEN i.cantidad_reservada > 0            THEN 'RESERVADA'
        ELSE                                          'AGOTADA'
    END AS situacion
FROM inventario i
JOIN producto_variante pv ON pv.id = i.variante_id
JOIN producto p           ON p.id  = pv.producto_id
JOIN talla t              ON t.id  = pv.talla_id
JOIN color c              ON c.id  = pv.color_id
JOIN sucursal s           ON s.id  = i.sucursal_id
WHERE p.activo AND pv.activa AND s.activa;
 
-- Existencias totales de la cadena, sin abrir por sucursal
CREATE OR REPLACE VIEW v_stock_global AS
SELECT
    pv.id  AS variante_id,
    pv.sku,
    p.nombre AS producto,
    SUM(i.cantidad_fisica)    AS total_fisico,
    SUM(i.cantidad_reservada) AS total_reservado,
    SUM(i.disponible)         AS total_disponible,
    COUNT(*) FILTER (WHERE i.disponible > 0) AS sucursales_con_stock
FROM producto_variante pv
JOIN producto p    ON p.id = pv.producto_id
LEFT JOIN inventario i ON i.variante_id = pv.id
GROUP BY pv.id, pv.sku, p.nombre;
 
-- Ventas por dia, sucursal y canal: base de los dashboards (RF24)
CREATE OR REPLACE VIEW v_ventas_diarias AS
SELECT
    v.fecha::date  AS dia,
    s.nombre       AS sucursal,
    v.canal,
    COUNT(*)       AS cantidad_ventas,
    SUM(v.total)   AS monto_total,
    AVG(v.total)   AS ticket_promedio
FROM venta v
JOIN sucursal s ON s.id = v.sucursal_id
WHERE v.estado IN ('PAGADA','ENTREGADA')
GROUP BY 1, 2, 3;
 
 
-- ---------------------------------------------------------------------
--  FUNCION CENTRAL DE INVENTARIO
--  Todo cambio de stock pasa por aca: bloquea la fila, valida, escribe
--  el kardex y actualiza el saldo dentro de la misma transaccion.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_mover_inventario(
    p_sucursal_id    UUID,
    p_variante_id    UUID,
    p_tipo           tipo_movimiento,
    p_cantidad       INT,
    p_motivo         VARCHAR DEFAULT NULL,
    p_documento_tipo VARCHAR DEFAULT NULL,
    p_documento_id   UUID    DEFAULT NULL,
    p_usuario_id     UUID    DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_inv          inventario%ROWTYPE;
    v_saldo_previo INT;
    v_saldo_nuevo  INT;
    v_mov_id       BIGINT;
BEGIN
    IF p_cantidad <= 0 THEN
        RAISE EXCEPTION 'La cantidad del movimiento debe ser positiva (recibido: %)', p_cantidad;
    END IF;
 
    -- crea la fila de inventario si la prenda nunca estuvo en esta sucursal
    INSERT INTO inventario (sucursal_id, variante_id)
    VALUES (p_sucursal_id, p_variante_id)
    ON CONFLICT (sucursal_id, variante_id) DO NOTHING;
 
    -- FOR UPDATE: si dos clientes reservan la ultima prenda a la vez,
    -- el segundo espera y ve el saldo ya actualizado
    SELECT * INTO v_inv
    FROM inventario
    WHERE sucursal_id = p_sucursal_id AND variante_id = p_variante_id
    FOR UPDATE;
 
    v_saldo_previo := v_inv.cantidad_fisica - v_inv.cantidad_reservada;
 
    CASE p_tipo
        -- movimientos que cambian la existencia fisica
        WHEN 'ENTRADA', 'DEVOLUCION', 'TRASPASO_ENT' THEN
            UPDATE inventario
               SET cantidad_fisica = cantidad_fisica + p_cantidad,
                   actualizado_en  = now()
             WHERE id = v_inv.id;
 
        WHEN 'SALIDA', 'TRASPASO_SAL' THEN
            IF v_saldo_previo < p_cantidad THEN
                RAISE EXCEPTION 'Stock insuficiente: hay % disponible(s), se piden %',
                                v_saldo_previo, p_cantidad;
            END IF;
            UPDATE inventario
               SET cantidad_fisica = cantidad_fisica - p_cantidad,
                   actualizado_en  = now()
             WHERE id = v_inv.id;
 
        -- la reserva COMPROMETE: no toca lo fisico
        WHEN 'RESERVA' THEN
            IF v_saldo_previo < p_cantidad THEN
                RAISE EXCEPTION 'No se puede reservar: hay % disponible(s), se piden %',
                                v_saldo_previo, p_cantidad;
            END IF;
            UPDATE inventario
               SET cantidad_reservada = cantidad_reservada + p_cantidad,
                   actualizado_en     = now()
             WHERE id = v_inv.id;
 
        -- liberacion: cancelacion, expiracion o prenda descartada tras probarsela
        WHEN 'LIBERACION' THEN
            UPDATE inventario
               SET cantidad_reservada = GREATEST(cantidad_reservada - p_cantidad, 0),
                   actualizado_en     = now()
             WHERE id = v_inv.id;
 
        WHEN 'AJUSTE' THEN
            UPDATE inventario
               SET cantidad_fisica = p_cantidad,
                   actualizado_en  = now()
             WHERE id = v_inv.id;
    END CASE;
 
    SELECT cantidad_fisica - cantidad_reservada INTO v_saldo_nuevo
      FROM inventario WHERE id = v_inv.id;
 
    INSERT INTO movimiento_inventario (
        sucursal_id, variante_id, tipo, cantidad,
        saldo_anterior, saldo_nuevo, motivo,
        documento_tipo, documento_id, usuario_id)
    VALUES (
        p_sucursal_id, p_variante_id, p_tipo, p_cantidad,
        v_saldo_previo, v_saldo_nuevo, p_motivo,
        p_documento_tipo, p_documento_id, p_usuario_id)
    RETURNING id INTO v_mov_id;
 
    RETURN v_mov_id;
END;
$$;
 
COMMENT ON FUNCTION fn_mover_inventario IS
    'Unico punto de escritura del stock. Bloquea la fila con FOR UPDATE para resolver la '
    'concurrencia entre dos clientes que reservan la ultima prenda, y deja el asiento en el kardex.';
 
 
-- ---------------------------------------------------------------------
--  VENTA DESCUENTA STOCK AUTOMATICAMENTE (RF20)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_venta_descuenta_stock()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_sucursal UUID;
    v_reserva  UUID;
BEGIN
    SELECT sucursal_id, reserva_id INTO v_sucursal, v_reserva
      FROM venta WHERE id = NEW.venta_id;
 
    -- si la prenda venia reservada, primero se libera el compromiso
    IF v_reserva IS NOT NULL THEN
        PERFORM fn_mover_inventario(
            v_sucursal, NEW.variante_id, 'LIBERACION', NEW.cantidad,
            'Conversion de reserva en venta', 'VENTA', NEW.venta_id);
    END IF;
 
    PERFORM fn_mover_inventario(
        v_sucursal, NEW.variante_id, 'SALIDA', NEW.cantidad,
        'Venta', 'VENTA', NEW.venta_id);
 
    RETURN NEW;
END;
$$;
 
CREATE TRIGGER tg_venta_descuenta_stock
    AFTER INSERT ON venta_detalle
    FOR EACH ROW EXECUTE FUNCTION fn_venta_descuenta_stock();
 
 
-- ---------------------------------------------------------------------
--  RESERVA COMPROMETE STOCK
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_reserva_compromete_stock()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_sucursal UUID;
BEGIN
    SELECT sucursal_id INTO v_sucursal FROM reserva WHERE id = NEW.reserva_id;
 
    PERFORM fn_mover_inventario(
        v_sucursal, NEW.variante_id, 'RESERVA', NEW.cantidad,
        'Reserva de prenda para vestidor', 'RESERVA', NEW.reserva_id);
 
    RETURN NEW;
END;
$$;
 
CREATE TRIGGER tg_reserva_compromete_stock
    AFTER INSERT ON reserva_detalle
    FOR EACH ROW EXECUTE FUNCTION fn_reserva_compromete_stock();
 
 
-- ---------------------------------------------------------------------
--  HISTORIAL AUTOMATICO DE ESTADOS DE RESERVA
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_reserva_historial()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.estado IS DISTINCT FROM OLD.estado THEN
        INSERT INTO reserva_historial (reserva_id, estado_anterior, estado_nuevo, usuario_id)
        VALUES (NEW.id, OLD.estado::text, NEW.estado::text, NEW.atendida_por_id);
    END IF;
    RETURN NEW;
END;
$$;
 
CREATE TRIGGER tg_reserva_historial
    AFTER UPDATE ON reserva
    FOR EACH ROW EXECUTE FUNCTION fn_reserva_historial();
 
 
-- ---------------------------------------------------------------------
--  EXPIRACION DE RESERVAS VENCIDAS
--  La llama un job programado (APScheduler o cron) cada pocos minutos.
--  Sin esto, el cliente que no aparece congela el stock para siempre.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_expirar_reservas()
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE
    r          RECORD;
    v_contador INT := 0;
BEGIN
    FOR r IN
        SELECT rd.reserva_id, rd.variante_id, rd.cantidad, res.sucursal_id
          FROM reserva_detalle rd
          JOIN reserva res ON res.id = rd.reserva_id
         WHERE res.estado IN ('PENDIENTE','CONFIRMADA','PREPARADA')
           AND res.expira_en < now()
           AND rd.estado_item IN ('RESERVADO','PREPARADO')
    LOOP
        PERFORM fn_mover_inventario(
            r.sucursal_id, r.variante_id, 'LIBERACION', r.cantidad,
            'Reserva expirada sin presentacion del cliente', 'RESERVA', r.reserva_id);
        v_contador := v_contador + 1;
    END LOOP;
 
    UPDATE reserva
       SET estado = 'EXPIRADA'
     WHERE estado IN ('PENDIENTE','CONFIRMADA','PREPARADA')
       AND expira_en < now();
 
    RETURN v_contador;
END;
$$;
 
COMMENT ON FUNCTION fn_expirar_reservas IS
    'Libera el stock comprometido por reservas vencidas. Debe ejecutarse periodicamente.';
 
 
-- ---------------------------------------------------------------------
--  RECEPCION DE MERCADERIA: al confirmarla entra el stock
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_confirmar_recepcion()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    d RECORD;
BEGIN
    IF NEW.estado = 'CONFIRMADA' AND OLD.estado <> 'CONFIRMADA' THEN
        FOR d IN SELECT * FROM recepcion_detalle WHERE recepcion_id = NEW.id LOOP
            PERFORM fn_mover_inventario(
                NEW.sucursal_id, d.variante_id, 'ENTRADA', d.cantidad,
                'Recepcion de proveedor', 'RECEPCION', NEW.id, NEW.usuario_id);
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$;
 
CREATE TRIGGER tg_confirmar_recepcion
    AFTER UPDATE ON recepcion
    FOR EACH ROW EXECUTE FUNCTION fn_confirmar_recepcion();