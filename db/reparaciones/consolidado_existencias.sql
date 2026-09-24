-- =====================================================================
--  Reparacion/migracion: consolidado de existencias (CU15, PENDIENTES 2.19.5)
--
--  Sirve para una base ya desplegada (Railway) que no tiene la vista
--  v_existencias_consolidadas que GET /reportes/existencias (y la herramienta
--  consultar_existencias del "Reporte con IA") pasan a leer.
--
--  Sintoma sin este script: GET /reportes/existencias responde 500
--  "relation v_existencias_consolidadas does not exist". El resto de CU15
--  sigue andando, no es bloqueante para el resto del sistema.
--
--  Es idempotente (CREATE OR REPLACE VIEW): se puede correr las veces que
--  haga falta. Solo crea una vista, no toca datos ni otras vistas.
--  OJO: CREATE OR REPLACE VIEW no permite quitar ni reordenar columnas de
--  una vista existente; si alguna vez cambia la lista de columnas, anteponer
--  DROP VIEW IF EXISTS v_existencias_consolidadas;
--
--  Misma definicion que el final de db/02_logica.sql (en local la toma
--  directo docker compose down -v; este archivo no se corre solo porque
--  docker-entrypoint-initdb.d solo ejecuta el primer nivel de db/).
--
--  Uso:
--    docker run --rm -i postgres:16 psql "<DATABASE_PUBLIC_URL>" -v ON_ERROR_STOP=1 \
--      < db/reparaciones/consolidado_existencias.sql
-- =====================================================================

BEGIN;

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

COMMIT;
