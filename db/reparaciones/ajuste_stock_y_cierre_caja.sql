-- =====================================================================
--  Reparacion/migracion: fn_mover_inventario (soporte AJUSTE absoluto) y
--  fn_total_efectivo_sesion (arqueo/cierre de caja, CU07).
--
--  Sirve para una base ya desplegada (Railway) que quedo creada antes del
--  commit "Agregar ajuste manual de stock, gestion de promociones y job de
--  expiracion de reservas": Railway no re-ejecuta db/02_logica.sql solo
--  con un git push, asi que el backend nuevo (que ya asume este
--  comportamiento) queda hablando con las funciones viejas.
--
--  Sintomas sin este script:
--   - POST /inventario/ajustar con tipo AJUSTE resta/suma en vez de fijar
--     el valor absoluto que cargo quien hizo el recuento fisico.
--   - POST /caja/cerrar (o GET /caja/arqueo) responde 500
--     "function fn_total_efectivo_sesion(uuid) does not exist".
--
--  Es idempotente (CREATE OR REPLACE FUNCTION): se puede correr las veces
--  que haga falta. No toca datos, solo el cuerpo de las dos funciones.
--
--  Este archivo vive en db/reparaciones/ a proposito: docker-entrypoint-
--  initdb.d solo ejecuta lo que esta en el primer nivel de db/, asi que no
--  se corre solo en local (docker compose down -v ya toma la version nueva
--  de 02_logica.sql directamente).
--
--  Uso:
--    docker run --rm -i postgres:16 psql "<DATABASE_PUBLIC_URL>" -v ON_ERROR_STOP=1 \
--      < db/reparaciones/ajuste_stock_y_cierre_caja.sql
-- =====================================================================

BEGIN;

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

COMMENT ON FUNCTION fn_mover_inventario IS
    'Unico punto de escritura del stock. Bloquea la fila con FOR UPDATE para resolver la '
    'concurrencia entre dos clientes que reservan la ultima prenda, y deja el asiento en el kardex.';

CREATE OR REPLACE FUNCTION fn_total_efectivo_sesion(p_sesion_id UUID)
RETURNS NUMERIC(12,2)
LANGUAGE sql STABLE
AS $$
    SELECT COALESCE(SUM(p.monto), 0)
    FROM pago p
    JOIN venta v ON v.id = p.venta_id
    WHERE v.sesion_caja_id = p_sesion_id
      AND p.estado = 'APROBADO'
      AND p.metodo = 'EFECTIVO';
$$;

COMMENT ON FUNCTION fn_total_efectivo_sesion IS
    'CU07: total EFECTIVO cobrado en una sesion de caja, para el arqueo y el cierre.';

COMMIT;

-- Verificacion rapida: ambas funciones tienen que existir despues de esto.
SELECT proname, pg_get_function_identity_arguments(oid) AS argumentos
  FROM pg_proc
 WHERE proname IN ('fn_mover_inventario', 'fn_total_efectivo_sesion');
