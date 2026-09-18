-- =====================================================================
--  Reparacion/migracion: CU16 "Usar Vestidor Virtual (RA)"
--
--  Sirve para una base YA desplegada (tipico: Railway) que no se puede recrear con
--  "docker compose down -v", y que por lo tanto no tiene nada de lo que CU16 agrego a
--  db/03_datos_iniciales.sql. Sin esto, la app movil contra ese backend no muestra
--  ningun boton de realidad aumentada: los endpoints funcionan, pero `ar` vuelve vacio
--  para todos los productos.
--
--  Que agrega:
--    1. El color "Turquesa" (el de las tiras del modelo 3D de la sandalia).
--    2. Los overlays 2D (AR_OVERLAY) de las 3 prendas de torso que ya existian:
--       blusa de lino, vestido de punto y tapado de lana, con sus anclajes y escala_base.
--    3. Dos productos NUEVOS que existen porque tenemos su modelo 3D y no correspondian
--       a ninguna prenda del catalogo (ver PENDIENTES.txt 2.8): BOT-004 "Bota Texana de
--       Cuero" y SAN-004 "Sandalia Deportiva de Tiras", con variantes, inventario
--       repartido por clima, foto de catalogo y su modelo AR_MODELO.
--
--  OJO, los archivos NO van en este script: los .glb y .png viven en
--  backend/app/media_semilla/ar/ y el backend los copia a MEDIA_DIR en cada arranque
--  (app/main.py), asi que se publican solos al desplegar el backend. Este script solo
--  crea las filas que los referencian. Desplegar el backend ANTES de correrlo, o las
--  URLs van a dar 404 hasta el proximo deploy.
--
--  Las URLs quedan como http://localhost:8081/... igual que en el seed, a proposito: la
--  app movil las reescribe a la base que este usando (core/config.dart,
--  `resolverUrlMedia`), asi que la misma fila sirve para Docker local y para Railway.
--
--  Es idempotente: se puede correr las veces que haga falta.
--
--  Uso:
--    docker run --rm -i postgres:16 psql "<DATABASE_PUBLIC_URL>" -v ON_ERROR_STOP=1 \
--      < db/reparaciones/cu16_vestidor_virtual.sql
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. Color nuevo
-- ---------------------------------------------------------------------
INSERT INTO color (nombre, codigo_hex) VALUES ('Turquesa', '#009688')
ON CONFLICT (nombre) DO NOTHING;

-- ---------------------------------------------------------------------
-- 2. Productos nuevos (los que existen porque tenemos su modelo 3D)
-- ---------------------------------------------------------------------
INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                      codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
SELECT
    (SELECT id FROM categoria WHERE slug = 'botas'),
    (SELECT id FROM marca WHERE nombre = 'Cordillera Urban'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Altiplano 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Otonio-Invierno 2026'),
    'BOT-004', 'Bota Texana de Cuero', 'bota-texana-de-cuero',
    'Bota texana de caña media en cuero, con bordado artesanal y taco bajo. '
    'Se puede ver en 3D y probar en tu espacio con realidad aumentada.',
    'Cuero vacuno', 'MUJER', 549.90, TRUE
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                      codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
SELECT
    (SELECT id FROM categoria WHERE slug = 'sandalias'),
    (SELECT id FROM marca WHERE nombre = 'Aurora Bolivia'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Llanura 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Primavera-Verano 2026'),
    'SAN-004', 'Sandalia Deportiva de Tiras', 'sandalia-deportiva-de-tiras',
    'Sandalia deportiva de tiras ajustables y suela plana, comoda para caminar todo el dia. '
    'Se puede ver en 3D y probar en tu espacio con realidad aumentada.',
    'Textil y goma', 'MUJER', 229.90, TRUE
ON CONFLICT (codigo) DO NOTHING;

-- ---------------------------------------------------------------------
-- 3. Variantes (talla x color) de los productos nuevos
-- ---------------------------------------------------------------------
INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT p.id, t.id, c.id, 'BOT-004-' || t.codigo || '-' || left(c.nombre, 3)
FROM producto p
CROSS JOIN talla t
CROSS JOIN color c
WHERE p.slug = 'bota-texana-de-cuero'
  AND t.tipo = 'CALZADO' AND t.codigo IN ('35', '36', '37', '38', '39')
  AND c.nombre IN ('Camel', 'Negro', 'Vino')
ON CONFLICT (producto_id, talla_id, color_id) DO NOTHING;

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT p.id, t.id, c.id, 'SAN-004-' || t.codigo || '-' || left(c.nombre, 3)
FROM producto p
CROSS JOIN talla t
CROSS JOIN color c
WHERE p.slug = 'sandalia-deportiva-de-tiras'
  AND t.tipo = 'CALZADO' AND t.codigo IN ('35', '36', '37', '38', '39')
  AND c.nombre IN ('Turquesa', 'Negro')
ON CONFLICT (producto_id, talla_id, color_id) DO NOTHING;

-- ---------------------------------------------------------------------
-- 4. Inventario de esas variantes, con el mismo criterio de clima del seed
--    (Santa Cruz calido pesa verano, La Paz frio pesa invierno, Cochabamba parejo)
-- ---------------------------------------------------------------------
INSERT INTO inventario (sucursal_id, variante_id, cantidad_fisica, stock_minimo)
SELECT
    s.id,
    pv.id,
    (CASE
        WHEN s.ciudad = 'SANTA_CRUZ' AND t.tipo = 'PRIMAVERA_VERANO' THEN 18 + random() * 10
        WHEN s.ciudad = 'SANTA_CRUZ' AND t.tipo = 'OTONO_INVIERNO'   THEN  1 + random() * 3
        WHEN s.ciudad = 'LA_PAZ'     AND t.tipo = 'OTONO_INVIERNO'   THEN 16 + random() * 10
        WHEN s.ciudad = 'LA_PAZ'     AND t.tipo = 'PRIMAVERA_VERANO' THEN  2 + random() * 3
        WHEN s.ciudad = 'COCHABAMBA' AND t.tipo IS NOT NULL          THEN  8 + random() * 7
        ELSE 10 + random() * 8
     END)::int,
    CASE
        WHEN s.ciudad = 'SANTA_CRUZ' AND t.tipo = 'OTONO_INVIERNO'   THEN 1
        WHEN s.ciudad = 'LA_PAZ'     AND t.tipo = 'PRIMAVERA_VERANO' THEN 1
        ELSE 5
    END
FROM producto_variante pv
JOIN producto p       ON p.id = pv.producto_id
CROSS JOIN sucursal s
LEFT JOIN temporada t ON t.id = p.temporada_id
WHERE p.codigo IN ('BOT-004', 'SAN-004')
ON CONFLICT (sucursal_id, variante_id) DO NOTHING;

-- ---------------------------------------------------------------------
-- 5. Fotos de catalogo de los productos nuevos (un render del propio modelo 3D,
--    servido desde /media/catalogo como el resto de los packshots)
-- ---------------------------------------------------------------------
INSERT INTO producto_imagen (producto_id, color_id, uso, url, formato, es_principal, orden)
SELECT p.id, c.id, 'CATALOGO',
       'http://localhost:8081/media/catalogo/' || p.slug || '.jpg', 'JPG', TRUE, 0
FROM producto p
LEFT JOIN (VALUES
    ('bota-texana-de-cuero', 'Camel'),
    ('sandalia-deportiva-de-tiras', 'Turquesa')
) AS m(slug, color_nombre) ON m.slug = p.slug
LEFT JOIN color c ON c.nombre = m.color_nombre
WHERE p.slug IN ('bota-texana-de-cuero', 'sandalia-deportiva-de-tiras')
  AND NOT EXISTS (
      SELECT 1 FROM producto_imagen pi
      WHERE pi.producto_id = p.id AND pi.uso = 'CATALOGO'
  );

-- ---------------------------------------------------------------------
-- 6. Assets de realidad aumentada
--
--    Por las dudas, primero se limpian las filas de una version intermedia de este
--    mismo trabajo, donde los dos modelos 3D colgaban de BOT-001 y SAN-001 (productos
--    que NO son lo que muestran los modelos). En una base que nunca las tuvo, estos
--    DELETE no borran nada.
-- ---------------------------------------------------------------------
DELETE FROM producto_imagen
WHERE uso = 'AR_MODELO'
  AND url IN ('http://localhost:8081/media/ar/bot-001-ar.glb',
              'http://localhost:8081/media/ar/san-001-ar.glb');

-- 6.1 Overlays 2D (nivel 1): prendas de torso que ya estaban en el catalogo.
--     anclajes = coordenadas normalizadas 0-1 sobre el PNG; escala_base = ancho de
--     hombro a hombro en cm a talla M (ver IMAGENES_AR.txt punto 4).
INSERT INTO producto_imagen (producto_id, color_id, uso, url, formato, es_principal, orden,
                             anclajes, escala_base)
SELECT p.id, NULL, 'AR_OVERLAY', v.url, 'PNG', FALSE, 0, v.anclajes::jsonb, v.escala_base
FROM (VALUES
    ('blusa-de-lino-manga-corta',
     'http://localhost:8081/media/ar/blu-001-ar-blanco.png',
     '{"tipo": "TORSO", "hombro_izq": {"x": 0.20, "y": 0.27}, "hombro_der": {"x": 0.73, "y": 0.27}, "cintura": {"x": 0.50, "y": 0.65}}',
     38.0),
    ('vestido-de-punto-manga-larga',
     'http://localhost:8081/media/ar/ves-003-ar-rosa.png',
     '{"tipo": "TORSO", "hombro_izq": {"x": 0.27, "y": 0.16}, "hombro_der": {"x": 0.70, "y": 0.16}, "cintura": {"x": 0.49, "y": 0.56}}',
     36.0),
    ('tapado-de-lana-largo',
     'http://localhost:8081/media/ar/abr-001-ar-camel.png',
     '{"tipo": "TORSO", "hombro_izq": {"x": 0.29, "y": 0.13}, "hombro_der": {"x": 0.68, "y": 0.13}, "cintura": {"x": 0.50, "y": 0.40}}',
     42.0)
) AS v(slug, url, anclajes, escala_base)
JOIN producto p ON p.slug = v.slug
WHERE NOT EXISTS (
    SELECT 1 FROM producto_imagen pi WHERE pi.producto_id = p.id AND pi.uso = 'AR_OVERLAY'
);

-- 6.2 Modelos 3D (nivel 2) de los dos productos nuevos.
--     GLB reescalados a metros y apoyados en el piso; licencia CC BY 3.0:
--       "Cowboy boots" de Poly by Google  -- https://poly.pizza/m/9Qf1MHGePvS
--       "Sandal" de jeremy                -- https://poly.pizza/m/4_4lQugjiRa
INSERT INTO producto_imagen (producto_id, color_id, uso, url, formato, es_principal, orden,
                             anclajes, escala_base)
SELECT p.id, NULL, 'AR_MODELO', v.url, 'GLB', FALSE, 0, NULL, NULL
FROM (VALUES
    ('bota-texana-de-cuero',        'http://localhost:8081/media/ar/bot-004-ar.glb'),
    ('sandalia-deportiva-de-tiras', 'http://localhost:8081/media/ar/san-004-ar.glb')
) AS v(slug, url)
JOIN producto p ON p.slug = v.slug
WHERE NOT EXISTS (
    SELECT 1 FROM producto_imagen pi WHERE pi.producto_id = p.id AND pi.uso = 'AR_MODELO'
);

COMMIT;

-- Control rapido de que quedo aplicado:
--   SELECT p.codigo, p.nombre, pi.uso, pi.url
--   FROM producto_imagen pi JOIN producto p ON p.id = pi.producto_id
--   WHERE pi.uso IN ('AR_OVERLAY', 'AR_MODELO') ORDER BY pi.uso, p.codigo;
