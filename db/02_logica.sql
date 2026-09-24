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


-- ---------------------------------------------------------------------
--  CU07 - ARQUEO DE CAJA
-- ---------------------------------------------------------------------

-- Cuanto efectivo deberia haber en el cajon por las ventas de una sesion (sesion_caja.
-- monto_inicial + esto = monto_sistema). Solo EFECTIVO: TARJETA/QR/TRANSFERENCIA/PASARELA no
-- tocan el cajon fisico. STABLE (no escribe nada) para que se pueda llamar tanto desde una
-- consulta de solo lectura (vista previa del arqueo) como adentro del UPDATE que cierra la
-- sesion, sin abrir una ventana entre "leer" el total y "escribirlo".
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
--  La llama el job periodico del backend (app/core/jobs.py) cada pocos minutos.
--  Sin esto, el cliente que no aparece congela el stock para siempre.
--
--  Concurrencia: compite con los endpoints que tambien liberan el compromiso
--  (cancelar/rechazar/no-presentado en reservas/router.py, que bloquean la reserva
--  con FOR UPDATE) y con el checkout de un carrito armado desde la reserva. Por eso:
--   * cada reserva vencida se BLOQUEA (FOR UPDATE SKIP LOCKED) antes de tocarla: si
--     otro la tiene tomada se la saltea y la agarra el proximo ciclo, ya con el
--     estado actualizado (el recheck del WHERE sobre la fila bloqueada descarta la
--     que otro ya paso a CANCELADA/ATENDIDA/...);
--   * los items liberados pasan a DESCARTADO en la misma transaccion (igual que
--     _liberar_compromiso), asi nadie los vuelve a liberar y la reserva EXPIRADA no
--     queda con items "vivos";
--   * no se expira una reserva con una venta PENDIENTE ligada (venta.reserva_id):
--     cuando ese pago se apruebe, tg_venta_descuenta_stock libera el compromiso de la
--     reserva antes de descontar, y si ya lo hubiera liberado este job, se liberaria
--     dos veces. Se re-chequea con una sentencia aparte (snapshot nuevo) DESPUES de
--     tener el lock, porque el checkout inserta la venta con la reserva bloqueada.
--  Devuelve la cantidad de reservas expiradas.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_expirar_reservas()
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE
    r          RECORD;
    d          RECORD;
    v_contador INT := 0;
BEGIN
    FOR r IN
        SELECT res.id, res.sucursal_id
          FROM reserva res
         WHERE res.estado IN ('PENDIENTE','CONFIRMADA','PREPARADA')
           AND res.expira_en < now()
         ORDER BY res.expira_en
           FOR UPDATE SKIP LOCKED
    LOOP
        IF EXISTS (SELECT 1 FROM venta v
                    WHERE v.reserva_id = r.id AND v.estado = 'PENDIENTE') THEN
            CONTINUE;  -- la resuelve el pago en curso; si se anula, la expira el proximo ciclo
        END IF;

        FOR d IN
            SELECT rd.variante_id, rd.cantidad
              FROM reserva_detalle rd
             WHERE rd.reserva_id = r.id
               AND rd.estado_item IN ('RESERVADO','PREPARADO')
        LOOP
            PERFORM fn_mover_inventario(
                r.sucursal_id, d.variante_id, 'LIBERACION', d.cantidad,
                'Reserva expirada sin presentacion del cliente', 'RESERVA', r.id);
        END LOOP;

        UPDATE reserva_detalle
           SET estado_item = 'DESCARTADO'
         WHERE reserva_id = r.id
           AND estado_item IN ('RESERVADO','PREPARADO');

        UPDATE reserva SET estado = 'EXPIRADA' WHERE id = r.id;
        v_contador := v_contador + 1;
    END LOOP;

    RETURN v_contador;
END;
$$;

COMMENT ON FUNCTION fn_expirar_reservas IS
    'Expira las reservas vencidas y libera su stock comprometido (items -> DESCARTADO). '
    'Bloquea cada reserva con FOR UPDATE SKIP LOCKED y saltea las que tienen una venta '
    'PENDIENTE ligada. Debe ejecutarse periodicamente; devuelve cuantas reservas expiro.';
 
 
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


-- ---------------------------------------------------------------------
--  DEVOLUCIONES (PENDIENTES 2.7): al aprobarla vuelve el stock
--  Mismo patron que tg_confirmar_recepcion: el backend solo mueve el estado
--  (SOLICITADA -> APROBADA) y es la base la que reingresa cada linea con
--  fn_mover_inventario tipo DEVOLUCION, en la sucursal de la devolucion.
--  Ademas la base es la ultima barrera de dos reglas:
--   * una devolucion resuelta (APROBADA/RECHAZADA) no cambia mas de estado;
--   * lo APROBADO de cada linea de venta no supera lo vendido. La venta se
--     bloquea con FOR UPDATE para que dos aprobaciones simultaneas de la misma
--     venta se serialicen y la segunda vea la primera.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_devolucion_stock()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    d RECORD;
BEGIN
    IF NEW.estado = OLD.estado THEN
        RETURN NEW;
    END IF;
    IF OLD.estado <> 'SOLICITADA' THEN
        RAISE EXCEPTION 'La devolucion ya esta % y no puede cambiar de estado', lower(OLD.estado::text);
    END IF;

    IF NEW.estado = 'APROBADA' THEN
        PERFORM 1 FROM venta WHERE id = NEW.venta_id FOR UPDATE;

        FOR d IN
            SELECT vd.id, vd.variante_id, vd.cantidad AS vendida, dd.cantidad,
                   (SELECT COALESCE(SUM(dd2.cantidad), 0)
                      FROM devolucion_detalle dd2
                      JOIN devolucion dv ON dv.id = dd2.devolucion_id
                     WHERE dd2.venta_detalle_id = vd.id
                       AND dv.estado = 'APROBADA') AS aprobada
              FROM devolucion_detalle dd
              JOIN venta_detalle vd ON vd.id = dd.venta_detalle_id
             WHERE dd.devolucion_id = NEW.id
        LOOP
            -- "aprobada" ya incluye esta devolucion (el trigger es AFTER UPDATE)
            IF d.aprobada > d.vendida THEN
                RAISE EXCEPTION 'Se devolverian % unidad(es) de una linea que vendio %',
                                d.aprobada, d.vendida;
            END IF;
            PERFORM fn_mover_inventario(
                NEW.sucursal_id, d.variante_id, 'DEVOLUCION', d.cantidad,
                'Devolucion de venta: ' || left(NEW.motivo, 150), 'DEVOLUCION', NEW.id,
                NEW.resuelta_por_id);
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_devolucion_stock ON devolucion;
CREATE TRIGGER tg_devolucion_stock
    AFTER UPDATE OF estado ON devolucion
    FOR EACH ROW EXECUTE FUNCTION fn_devolucion_stock();


-- ---------------------------------------------------------------------
--  TRASPASOS ENTRE SUCURSALES (PENDIENTES 2.7)
--  El backend solo cambia traspaso.estado (y antes carga cantidad_recibida al
--  recibir); el stock lo mueve este trigger, firmando el kardex con
--  traspaso.actualizado_por_id:
--    SOLICITADO  -> EN_TRANSITO : TRASPASO_SAL en el origen por lo solicitado
--                                 (falla si el origen no tiene disponible).
--    EN_TRANSITO -> RECIBIDO    : TRASPASO_ENT en el destino por lo RECIBIDO.
--                                 Si llego de menos, la diferencia salio del
--                                 origen y no entro en ningun lado: se investiga
--                                 y se corrige con un AJUSTE (el kardex no se
--                                 reescribe), igual que una recepcion.
--    EN_TRANSITO -> ANULADO     : TRASPASO_ENT de vuelta en el ORIGEN (el envio
--                                 no salio o volvio entero).
--    SOLICITADO  -> ANULADO     : nada que mover.
--  Cualquier otra transicion es un error.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_traspaso_stock()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    d RECORD;
BEGIN
    IF NEW.estado = OLD.estado THEN
        RETURN NEW;
    END IF;

    IF OLD.estado = 'SOLICITADO' AND NEW.estado = 'EN_TRANSITO' THEN
        FOR d IN SELECT * FROM traspaso_detalle WHERE traspaso_id = NEW.id LOOP
            PERFORM fn_mover_inventario(
                NEW.sucursal_origen_id, d.variante_id, 'TRASPASO_SAL', d.cantidad_solicitada,
                'Traspaso ' || NEW.numero || ': salida del origen', 'TRASPASO', NEW.id,
                NEW.actualizado_por_id);
        END LOOP;

    ELSIF OLD.estado = 'EN_TRANSITO' AND NEW.estado = 'RECIBIDO' THEN
        FOR d IN SELECT * FROM traspaso_detalle WHERE traspaso_id = NEW.id LOOP
            IF d.cantidad_recibida IS NULL THEN
                RAISE EXCEPTION 'Falta indicar la cantidad recibida de todas las lineas';
            END IF;
            IF d.cantidad_recibida > d.cantidad_solicitada THEN
                RAISE EXCEPTION 'Se recibieron % unidad(es) de una linea que despacho %',
                                d.cantidad_recibida, d.cantidad_solicitada;
            END IF;
            IF d.cantidad_recibida > 0 THEN
                PERFORM fn_mover_inventario(
                    NEW.sucursal_destino_id, d.variante_id, 'TRASPASO_ENT', d.cantidad_recibida,
                    'Traspaso ' || NEW.numero || ': entrada en destino', 'TRASPASO', NEW.id,
                    NEW.actualizado_por_id);
            END IF;
        END LOOP;

    ELSIF OLD.estado = 'EN_TRANSITO' AND NEW.estado = 'ANULADO' THEN
        FOR d IN SELECT * FROM traspaso_detalle WHERE traspaso_id = NEW.id LOOP
            PERFORM fn_mover_inventario(
                NEW.sucursal_origen_id, d.variante_id, 'TRASPASO_ENT', d.cantidad_solicitada,
                'Traspaso ' || NEW.numero || ' anulado en transito: vuelve al origen', 'TRASPASO',
                NEW.id, NEW.actualizado_por_id);
        END LOOP;

    ELSIF NOT (OLD.estado = 'SOLICITADO' AND NEW.estado = 'ANULADO') THEN
        RAISE EXCEPTION 'Un traspaso % no puede pasar a %',
                        lower(OLD.estado::text), lower(NEW.estado::text);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_traspaso_stock ON traspaso;
CREATE TRIGGER tg_traspaso_stock
    AFTER UPDATE OF estado ON traspaso
    FOR EACH ROW EXECUTE FUNCTION fn_traspaso_stock();


-- ---------------------------------------------------------------------
--  CU20 - TARIFA DEL DELIVERY
--  La distancia la trae el backend del proveedor de ruteo (openrouteservice
--  de HeiGIT, o el respaldo Haversine); el precio se arma aca, con los
--  parametros de la tabla configuracion, para que la regla comercial viva
--  en un solo lugar y no haya que redesplegar el backend para cambiarla.
--    delivery_tarifa_base       Bs fijos por salir a repartir
--    delivery_precio_km         Bs por kilometro de ruta
--    delivery_costo_minimo      piso de la tarifa
--    delivery_radio_km          hasta donde reparte una sucursal
--    delivery_gratis_desde      monto de compra que deja el envio en 0
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_cotizar_envio(
    p_distancia_km NUMERIC,
    p_monto_pedido NUMERIC DEFAULT 0
)
RETURNS TABLE (
    costo            NUMERIC,
    tarifa_base      NUMERIC,
    precio_km        NUMERIC,
    radio_km         NUMERIC,
    gratis_desde     NUMERIC,
    es_gratis        BOOLEAN,
    dentro_cobertura BOOLEAN
)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_base    NUMERIC;
    v_km      NUMERIC;
    v_minimo  NUMERIC;
    v_radio   NUMERIC;
    v_gratis  NUMERIC;
    v_costo   NUMERIC;
BEGIN
    SELECT COALESCE((SELECT valor FROM configuracion WHERE clave = 'delivery_tarifa_base'),  '8')::NUMERIC,
           COALESCE((SELECT valor FROM configuracion WHERE clave = 'delivery_precio_km'),    '3.5')::NUMERIC,
           COALESCE((SELECT valor FROM configuracion WHERE clave = 'delivery_costo_minimo'), '10')::NUMERIC,
           COALESCE((SELECT valor FROM configuracion WHERE clave = 'delivery_radio_km'),     '12')::NUMERIC,
           COALESCE((SELECT valor FROM configuracion WHERE clave = 'delivery_gratis_desde'), '800')::NUMERIC
      INTO v_base, v_km, v_minimo, v_radio, v_gratis;

    v_costo := GREATEST(v_base + (v_km * GREATEST(p_distancia_km, 0)), v_minimo);

    costo            := ROUND(v_costo, 2);
    tarifa_base      := v_base;
    precio_km        := v_km;
    radio_km         := v_radio;
    gratis_desde     := v_gratis;
    es_gratis        := v_gratis > 0 AND COALESCE(p_monto_pedido, 0) >= v_gratis;
    dentro_cobertura := p_distancia_km IS NOT NULL AND p_distancia_km <= v_radio;

    IF es_gratis THEN
        costo := 0;
    END IF;

    RETURN NEXT;
END;
$$;
COMMENT ON FUNCTION fn_cotizar_envio IS
    'CU20. Precio del delivery a partir de la distancia de ruta y el monto del pedido. '
    'Devuelve tambien los parametros usados para que el frontend pueda explicar la tarifa.';


-- ---------------------------------------------------------------------
--  CU20 - BITACORA AUTOMATICA DEL ENVIO
--  Mismo patron que tg_reserva_historial: cada cambio de estado deja un
--  asiento append-only en envio_evento, firmado con el usuario que el
--  backend escribio en envio.actualizado_por_id.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_envio_historial()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO envio_evento (envio_id, estado, nota, usuario_id)
        VALUES (NEW.id, NEW.estado, 'Envio generado por el pago aprobado, pendiente de despacho', NEW.actualizado_por_id);
    ELSIF NEW.estado IS DISTINCT FROM OLD.estado THEN
        INSERT INTO envio_evento (envio_id, estado, nota, usuario_id)
        VALUES (NEW.id, NEW.estado, NEW.observacion, NEW.actualizado_por_id);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER tg_envio_historial
    AFTER INSERT OR UPDATE ON envio
    FOR EACH ROW EXECUTE FUNCTION fn_envio_historial();

-- ---------------------------------------------------------------------
--  CU15 - CONSOLIDADO DE EXISTENCIAS (PENDIENTES 2.19.5)
--  La consigna pide saber que prendas estan disponibles, reservadas,
--  vendidas, agotadas o proximas a ingresar en todas las sucursales.
--  v_disponibilidad (la del catalogo) solo distingue DISPONIBLE/RESERVADA/
--  AGOTADA y no se toca; esta vista suma lo que le faltaba en una sola
--  fila por variante x sucursal. Situacion, en orden de prioridad:
--    DISPONIBLE         disponible > 0
--    RESERVADA          disponible = 0 y hay unidades comprometidas
--    PROXIMA_A_INGRESAR sin nada fisico libre ni reservado, pero con una
--                       recepcion BORRADOR que la trae
--    AGOTADA            nada de lo anterior
--  "Vendidas" es una columna (unidades historicas), no una situacion: una
--  variante puede estar disponible y a la vez tener ventas.
--  Para Railway: db/reparaciones/consolidado_existencias.sql.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_existencias_consolidadas AS
WITH vendidas AS (
    -- Unidades vendidas historicas. venta_detalle se inserta recien al aprobar el pago, y se
    -- cuentan los mismos estados que los reportes de CU15 (PAGADA/ENTREGADA).
    SELECT v.sucursal_id, vd.variante_id, SUM(vd.cantidad)::int AS vendidas
    FROM venta_detalle vd
    JOIN venta v ON v.id = vd.venta_id
    WHERE v.estado IN ('PAGADA', 'ENTREGADA')
    GROUP BY v.sucursal_id, vd.variante_id
),
entrantes AS (
    -- Mercaderia cargada en una recepcion BORRADOR: todavia no entro al kardex (eso lo hace
    -- tg_confirmar_recepcion al confirmar), pero ya se sabe que viene.
    SELECT r.sucursal_id, rd.variante_id, SUM(rd.cantidad)::int AS proximas_a_ingresar
    FROM recepcion_detalle rd
    JOIN recepcion r ON r.id = rd.recepcion_id
    WHERE r.estado = 'BORRADOR'
    GROUP BY r.sucursal_id, rd.variante_id
),
base AS (
    -- Una variante nueva que todavia no tiene fila en inventario de esa sucursal pero ya viene
    -- en una recepcion pendiente tambien tiene que aparecer (como PROXIMA_A_INGRESAR).
    SELECT sucursal_id, variante_id FROM inventario
    UNION
    SELECT sucursal_id, variante_id FROM entrantes
)
SELECT
    p.id                                    AS producto_id,
    p.nombre                                AS producto,
    cat.id                                  AS categoria_id,
    cat.nombre                              AS categoria,
    pv.id                                   AS variante_id,
    pv.sku,
    t.codigo                                AS talla,
    t.orden                                 AS talla_orden,
    c.nombre                                AS color,
    s.id                                    AS sucursal_id,
    s.nombre                                AS sucursal,
    s.ciudad,
    COALESCE(i.cantidad_fisica, 0)          AS cantidad_fisica,
    COALESCE(i.cantidad_reservada, 0)       AS cantidad_reservada,
    COALESCE(i.disponible, 0)               AS disponible,
    COALESCE(i.stock_minimo, 0)             AS stock_minimo,
    COALESCE(ve.vendidas, 0)                AS vendidas,
    COALESCE(en.proximas_a_ingresar, 0)     AS proximas_a_ingresar,
    (CASE
        WHEN COALESCE(i.disponible, 0) > 0          THEN 'DISPONIBLE'
        WHEN COALESCE(i.cantidad_reservada, 0) > 0  THEN 'RESERVADA'
        WHEN COALESCE(en.proximas_a_ingresar, 0) > 0 THEN 'PROXIMA_A_INGRESAR'
        ELSE                                             'AGOTADA'
    END)::text                              AS situacion
FROM base b
JOIN producto_variante pv ON pv.id  = b.variante_id
JOIN producto p           ON p.id   = pv.producto_id
JOIN categoria cat        ON cat.id = p.categoria_id
JOIN talla t              ON t.id   = pv.talla_id
JOIN color c              ON c.id   = pv.color_id
JOIN sucursal s           ON s.id   = b.sucursal_id
LEFT JOIN inventario i    ON i.sucursal_id  = b.sucursal_id AND i.variante_id  = b.variante_id
LEFT JOIN vendidas ve     ON ve.sucursal_id = b.sucursal_id AND ve.variante_id = b.variante_id
LEFT JOIN entrantes en    ON en.sucursal_id = b.sucursal_id AND en.variante_id = b.variante_id
WHERE p.activo AND pv.activa AND s.activa;
COMMENT ON VIEW v_existencias_consolidadas IS
    'CU15 (consolidado de existencias). Por variante x sucursal: fisico, reservado, disponible, '
    'vendidas historicas y proximas a ingresar (recepciones BORRADOR), con la situacion derivada.';
