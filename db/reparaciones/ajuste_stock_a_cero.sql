-- =====================================================================
--  Reparacion/migracion: ajuste manual de stock a 0 (PENDIENTES 4.10 f).
--
--  Antes, un recuento fisico no podia dejar una variante en 0 unidades (se
--  perdio o se danio la ultima): el schema del backend exigia > 0,
--  fn_mover_inventario rechazaba p_cantidad <= 0 y el kardex tenia
--  CHECK (cantidad > 0). Este script:
--   - reemplaza el CHECK anonimo de movimiento_inventario.cantidad por
--     ck_movimiento_cantidad (> 0, o = 0 solo para AJUSTE);
--   - redefine fn_mover_inventario con la misma validacion.
--
--  Sirve para una base ya desplegada (Railway, o un volumen de Docker que no
--  se quiere recrear con `docker compose down -v`): docker-entrypoint-
--  initdb.d solo corre 01/02/03 al crear el volumen. Es idempotente y no
--  toca datos: los movimientos existentes ya cumplen cantidad > 0.
--
--  Uso:
--    docker run --rm -i postgres:16 psql "<DATABASE_PUBLIC_URL>" -v ON_ERROR_STOP=1 --      < db/reparaciones/ajuste_stock_a_cero.sql
-- =====================================================================

BEGIN;

-- el CHECK inline de 01_schema.sql no tenia nombre: Postgres lo llamo asi
ALTER TABLE movimiento_inventario DROP CONSTRAINT IF EXISTS movimiento_inventario_cantidad_check;
ALTER TABLE movimiento_inventario DROP CONSTRAINT IF EXISTS ck_movimiento_cantidad;
ALTER TABLE movimiento_inventario ADD CONSTRAINT ck_movimiento_cantidad CHECK (
    cantidad > 0 OR (tipo = 'AJUSTE' AND cantidad = 0)
);

-- copia exacta de db/02_logica.sql
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
    -- AJUSTE es un recuento absoluto y puede dejar la prenda en 0; el resto son deltas
    IF p_cantidad < 0 OR (p_cantidad = 0 AND p_tipo <> 'AJUSTE') THEN
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
 
    -- AJUSTE fija cantidad_fisica al valor absoluto p_cantidad (un recuento fisico, no un
    -- delta): el saldo que le importa a quien ajusta es el fisico, no el disponible (que
    -- ademas resta lo reservado y no coincidiria con el numero que la persona acaba de
    -- contar). El resto de los tipos siguen trackeando disponible, que es lo correcto para
    -- ellos -- una RESERVA, por ejemplo, no toca lo fisico.
    IF p_tipo = 'AJUSTE' THEN
        v_saldo_previo := v_inv.cantidad_fisica;
    ELSE
        v_saldo_previo := v_inv.cantidad_fisica - v_inv.cantidad_reservada;
    END IF;

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
 
    IF p_tipo = 'AJUSTE' THEN
        SELECT cantidad_fisica INTO v_saldo_nuevo FROM inventario WHERE id = v_inv.id;
    ELSE
        SELECT cantidad_fisica - cantidad_reservada INTO v_saldo_nuevo
          FROM inventario WHERE id = v_inv.id;
    END IF;

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

COMMIT;
