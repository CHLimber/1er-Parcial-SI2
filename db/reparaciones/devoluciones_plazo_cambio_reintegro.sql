-- =====================================================================
--  Reparacion/migracion: devoluciones con plazo, cambio de prenda y reintegro
--  (PENDIENTES 4.11). Complementa db/reparaciones/devoluciones_traspasos.sql.
--
--   - devolucion: columnas reintegro_metodo / reintegro_referencia / sesion_caja_id (como se
--     devolvio la plata; EFECTIVO sale del cajon de esa sesion) y venta_cambio_id (la venta
--     nueva de un cambio de prenda).
--   - configuracion.devolucion_plazo_dias = 30 (no pisa un valor ya cargado).
--   - fn_total_efectivo_sesion: resta el efectivo devuelto en la sesion.
--   - v_ventas_diarias y v_existencias_consolidadas: netas de devoluciones aprobadas.
--
--  Sin este script el backend nuevo falla al leer/aprobar devoluciones (columnas que no
--  existen). Es idempotente y no modifica datos existentes. Las definiciones de la funcion y
--  las vistas son copia exacta de db/02_logica.sql.
--
--  Uso:
--    docker run --rm -i postgres:16 psql "<DATABASE_PUBLIC_URL>" -v ON_ERROR_STOP=1 --      < db/reparaciones/devoluciones_plazo_cambio_reintegro.sql
-- =====================================================================

BEGIN;

ALTER TABLE devolucion ADD COLUMN IF NOT EXISTS reintegro_metodo     VARCHAR(20);
ALTER TABLE devolucion ADD COLUMN IF NOT EXISTS reintegro_referencia VARCHAR(80);
ALTER TABLE devolucion ADD COLUMN IF NOT EXISTS sesion_caja_id       UUID REFERENCES sesion_caja(id);
ALTER TABLE devolucion ADD COLUMN IF NOT EXISTS venta_cambio_id      UUID REFERENCES venta(id);

ALTER TABLE devolucion DROP CONSTRAINT IF EXISTS devolucion_reintegro_metodo_check;
ALTER TABLE devolucion ADD CONSTRAINT devolucion_reintegro_metodo_check CHECK (reintegro_metodo IN
    ('STRIPE','EFECTIVO','TARJETA','QR','TRANSFERENCIA'));
ALTER TABLE devolucion DROP CONSTRAINT IF EXISTS ck_devolucion_cambio;
ALTER TABLE devolucion ADD CONSTRAINT ck_devolucion_cambio CHECK (venta_cambio_id <> venta_id);

INSERT INTO configuracion (clave, valor, descripcion) VALUES
    ('devolucion_plazo_dias', '30', 'Dias desde la venta para aceptar una devolucion')
ON CONFLICT (clave) DO NOTHING;

CREATE OR REPLACE FUNCTION fn_total_efectivo_sesion(p_sesion_id UUID)
RETURNS NUMERIC(12,2)
LANGUAGE sql STABLE
AS $$
    SELECT
        COALESCE((SELECT SUM(p.monto)
                    FROM pago p
                    JOIN venta v ON v.id = p.venta_id
                   WHERE v.sesion_caja_id = p_sesion_id
                     AND p.estado IN ('APROBADO', 'REEMBOLSADO')
                     AND p.metodo = 'EFECTIVO'), 0)
      - COALESCE((SELECT SUM(d.monto_devuelto)
                    FROM devolucion d
                   WHERE d.sesion_caja_id = p_sesion_id
                     AND d.estado = 'APROBADA'
                     AND d.reintegro_metodo = 'EFECTIVO'), 0);
$$;

CREATE OR REPLACE VIEW v_ventas_diarias AS
WITH neta AS (
    SELECT v.*,
           v.total - COALESCE((SELECT SUM(d.monto_devuelto) FROM devolucion d
                                WHERE d.venta_id = v.id AND d.estado = 'APROBADA'), 0) AS total_neto
    FROM venta v
    WHERE v.estado IN ('PAGADA','ENTREGADA')
      AND NOT EXISTS (SELECT 1 FROM pago p WHERE p.venta_id = v.id AND p.estado = 'REEMBOLSADO')
)
SELECT
    v.fecha::date      AS dia,
    s.nombre           AS sucursal,
    v.canal,
    COUNT(*)           AS cantidad_ventas,
    SUM(v.total_neto)  AS monto_total,
    AVG(v.total_neto)  AS ticket_promedio
FROM neta v
JOIN sucursal s ON s.id = v.sucursal_id
GROUP BY 1, 2, 3;

CREATE OR REPLACE VIEW v_existencias_consolidadas AS
WITH vendidas AS (
    -- Unidades vendidas historicas, netas de devoluciones APROBADAS. venta_detalle se inserta
    -- recien al aprobar el pago, y se cuentan los mismos estados que los reportes de CU15
    -- (PAGADA/ENTREGADA).
    SELECT v.sucursal_id, vd.variante_id,
           SUM(vd.cantidad - COALESCE((SELECT SUM(dd.cantidad)
                                         FROM devolucion_detalle dd
                                         JOIN devolucion d ON d.id = dd.devolucion_id
                                        WHERE dd.venta_detalle_id = vd.id
                                          AND d.estado = 'APROBADA'), 0))::int AS vendidas
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

COMMIT;
