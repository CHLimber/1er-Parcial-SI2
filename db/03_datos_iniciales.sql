-- =====================================================================
--  FashionStore - Datos iniciales para desarrollo local
--  Cubre login, catalogo (con filtros por categoria/busqueda), inventario
--  multi-sucursal y promociones. Suficiente para desarrollar y demostrar
--  el frontend/movil de punta a punta sin depender de datos reales.
--  Password de todos los usuarios demo: "demo1234"
-- =====================================================================

-- ---------------------------------------------------------------------
-- ROLES Y ORGANIZACION
-- ---------------------------------------------------------------------

INSERT INTO rol (nombre, descripcion, es_sistema) VALUES
    ('ADMIN',     'Administracion general del sistema', TRUE),
    ('ENCARGADO', 'Responsable de una sucursal', TRUE),
    ('CAJERO',    'Maneja caja y ventas presenciales', TRUE),
    ('VENDEDOR',  'Atiende clientes y reservas en tienda', TRUE);

INSERT INTO sucursal (codigo, nombre, ciudad, direccion, hora_apertura, hora_cierre, cantidad_vestidores) VALUES
    ('SC-01', 'FashionStore Equipetrol', 'SANTA_CRUZ', 'Av. San Martin #100',      '09:00', '20:00', 3),
    ('LP-01', 'FashionStore Sopocachi',  'LA_PAZ',     'Av. 6 de Agosto #2050',    '09:30', '19:30', 2),
    ('CB-01', 'FashionStore Cala Cala',  'COCHABAMBA', 'Av. America Este #480',    '09:00', '20:00', 2);

INSERT INTO caja (sucursal_id, codigo, nombre) VALUES
    ((SELECT id FROM sucursal WHERE codigo = 'SC-01'), 'CAJA-01', 'Caja principal Equipetrol'),
    ((SELECT id FROM sucursal WHERE codigo = 'LP-01'), 'CAJA-01', 'Caja principal Sopocachi'),
    ((SELECT id FROM sucursal WHERE codigo = 'CB-01'), 'CAJA-01', 'Caja principal Cala Cala');

-- ---------------------------------------------------------------------
-- USUARIOS
-- ---------------------------------------------------------------------

INSERT INTO usuario (email, password_hash, nombre, apellido, tipo, rol_id, email_verificado)
VALUES (
    'admin@fashionstore.bo',
    crypt('demo1234', gen_salt('bf')),
    'Admin',
    'Sistema',
    'STAFF',
    (SELECT id FROM rol WHERE nombre = 'ADMIN'),
    TRUE
);

INSERT INTO usuario (email, password_hash, nombre, apellido, tipo, rol_id, email_verificado) VALUES
    ('encargada.lapaz@fashionstore.bo', crypt('demo1234', gen_salt('bf')), 'Mariana', 'Quispe',
     'STAFF', (SELECT id FROM rol WHERE nombre = 'ENCARGADO'), TRUE),
    ('cajero.cbba@fashionstore.bo',     crypt('demo1234', gen_salt('bf')), 'Jorge',   'Fernandez',
     'STAFF', (SELECT id FROM rol WHERE nombre = 'CAJERO'),    TRUE),
    ('vendedor.scz@fashionstore.bo',    crypt('demo1234', gen_salt('bf')), 'Camila',  'Rocha',
     'STAFF', (SELECT id FROM rol WHERE nombre = 'VENDEDOR'),  TRUE);

INSERT INTO usuario (email, password_hash, nombre, apellido, tipo, email_verificado) VALUES
    ('cliente@fashionstore.bo',  crypt('demo1234', gen_salt('bf')), 'Cliente', 'Demo',   'CLIENTE', TRUE),
    ('cliente2@fashionstore.bo', crypt('demo1234', gen_salt('bf')), 'Valeria', 'Rojas',  'CLIENTE', TRUE);

INSERT INTO empleado (usuario_id, sucursal_id, cargo, fecha_ingreso) VALUES
    ((SELECT id FROM usuario WHERE email = 'admin@fashionstore.bo'),
     (SELECT id FROM sucursal WHERE codigo = 'SC-01'), 'ENCARGADO', CURRENT_DATE),
    ((SELECT id FROM usuario WHERE email = 'encargada.lapaz@fashionstore.bo'),
     (SELECT id FROM sucursal WHERE codigo = 'LP-01'), 'ENCARGADO', CURRENT_DATE),
    ((SELECT id FROM usuario WHERE email = 'cajero.cbba@fashionstore.bo'),
     (SELECT id FROM sucursal WHERE codigo = 'CB-01'), 'CAJERO', CURRENT_DATE),
    ((SELECT id FROM usuario WHERE email = 'vendedor.scz@fashionstore.bo'),
     (SELECT id FROM sucursal WHERE codigo = 'SC-01'), 'VENDEDOR', CURRENT_DATE);

INSERT INTO perfil_cliente (usuario_id, talla_superior_id, talla_inferior_id, talla_calzado_id,
                             color_favorito_id, fecha_nacimiento, puntos_fidelidad, acepta_marketing)
VALUES (
    (SELECT id FROM usuario WHERE email = 'cliente@fashionstore.bo'),
    NULL, NULL, NULL, NULL,  -- se completan una vez existan las tallas mas abajo (ver UPDATE al final)
    '1998-05-14', 120, TRUE
);

INSERT INTO direccion (usuario_id, alias, ciudad, direccion, referencia, es_principal)
VALUES (
    (SELECT id FROM usuario WHERE email = 'cliente@fashionstore.bo'),
    'Casa', 'SANTA_CRUZ', 'Calle Beni #345', 'Porton verde, frente a la plaza', TRUE
);

-- ---------------------------------------------------------------------
-- TALLAS Y COLORES
-- ---------------------------------------------------------------------

INSERT INTO talla (codigo, tipo, orden) VALUES
    ('XS',    'LETRA', 0),
    ('S',     'LETRA', 1),
    ('M',     'LETRA', 2),
    ('L',     'LETRA', 3),
    ('XL',    'LETRA', 4),
    ('XXL',   'LETRA', 5),
    ('UNICA', 'LETRA', 0),
    ('38',    'NUMERO', 1),
    ('40',    'NUMERO', 2),
    ('42',    'NUMERO', 3),
    ('44',    'NUMERO', 4),
    ('46',    'NUMERO', 5),
    ('38',    'CALZADO', 1),
    ('39',    'CALZADO', 2),
    ('40',    'CALZADO', 3),
    ('41',    'CALZADO', 4),
    ('42',    'CALZADO', 5);

INSERT INTO color (nombre, codigo_hex) VALUES
    ('Negro',       '#000000'),
    ('Blanco',      '#FFFFFF'),
    ('Azul',        '#1E3A8A'),
    ('Rojo',        '#DC2626'),
    ('Gris',        '#6B7280'),
    ('Beige',       '#D2B48C'),
    ('Verde Oliva', '#556B2F');

UPDATE perfil_cliente SET
    talla_superior_id = (SELECT id FROM talla WHERE codigo = 'M'  AND tipo = 'LETRA'),
    talla_inferior_id = (SELECT id FROM talla WHERE codigo = '40' AND tipo = 'NUMERO'),
    talla_calzado_id  = (SELECT id FROM talla WHERE codigo = '40' AND tipo = 'CALZADO'),
    color_favorito_id = (SELECT id FROM color WHERE nombre = 'Azul')
WHERE usuario_id = (SELECT id FROM usuario WHERE email = 'cliente@fashionstore.bo');

-- ---------------------------------------------------------------------
-- CATALOGO: proveedores, categorias, marcas, temporada y coleccion
-- ---------------------------------------------------------------------

INSERT INTO proveedor (nombre, nit, contacto, email, telefono) VALUES
    ('Textiles Andinos SRL',   '890111222', 'Rene Choque',    'ventas@textilesandinos.bo', '70011122'),
    ('Urban Import Bolivia',   '890333444', 'Diego Salazar',  'contacto@urbanimport.bo',   '70033344');

INSERT INTO categoria (nombre, slug) VALUES
    ('Ropa',        'ropa'),
    ('Calzado',     'calzado'),
    ('Accesorios',  'accesorios');

INSERT INTO categoria (categoria_padre_id, nombre, slug) VALUES
    ((SELECT id FROM categoria WHERE slug = 'ropa'), 'Camisetas',  'camisetas'),
    ((SELECT id FROM categoria WHERE slug = 'ropa'), 'Pantalones', 'pantalones'),
    ((SELECT id FROM categoria WHERE slug = 'ropa'), 'Vestidos',   'vestidos'),
    ((SELECT id FROM categoria WHERE slug = 'ropa'), 'Chaquetas',  'chaquetas'),
    ((SELECT id FROM categoria WHERE slug = 'calzado'), 'Zapatillas', 'zapatillas');

INSERT INTO marca (nombre) VALUES
    ('FashionStore Basics'),
    ('Andina Denim'),
    ('UrbanStep');

INSERT INTO temporada (nombre, tipo, fecha_inicio, fecha_fin) VALUES
    ('Primavera-Verano 2026', 'PRIMAVERA_VERANO', '2026-09-01', '2027-02-28');

INSERT INTO coleccion (temporada_id, proveedor_id, nombre, descripcion, anio) VALUES
    ((SELECT id FROM temporada WHERE nombre = 'Primavera-Verano 2026'),
     (SELECT id FROM proveedor WHERE nombre = 'Textiles Andinos SRL'),
     'Coleccion Verano Urbano 2026',
     'Piezas livianas para clima calido con estetica urbana.',
     2026);

-- ---------------------------------------------------------------------
-- PRODUCTOS Y VARIANTES
-- ---------------------------------------------------------------------

INSERT INTO producto (categoria_id, marca_id, codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'camisetas'),
    (SELECT id FROM marca WHERE nombre = 'FashionStore Basics'),
    'CAM-001',
    'Camiseta Basica',
    'camiseta-basica',
    'Camiseta de algodon 100%, corte regular.',
    'Algodon',
    'UNISEX',
    89.90,
    TRUE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'pantalones'),
    (SELECT id FROM marca WHERE nombre = 'Andina Denim'),
    (SELECT id FROM proveedor WHERE nombre = 'Textiles Andinos SRL'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Verano Urbano 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Primavera-Verano 2026'),
    'PAN-001', 'Jean Slim Fit', 'jean-slim-fit',
    'Jean corte slim, tiro medio, con elastano para mayor comodidad.',
    'Denim 98% algodon 2% elastano', 'HOMBRE', 249.90, TRUE
);

INSERT INTO producto (categoria_id, marca_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'vestidos'),
    (SELECT id FROM marca WHERE nombre = 'FashionStore Basics'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Verano Urbano 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Primavera-Verano 2026'),
    'VES-001', 'Vestido Floral Manga Corta', 'vestido-floral-manga-corta',
    'Vestido liviano estampado floral, ideal para clima calido.',
    'Viscosa', 'MUJER', 179.90, TRUE
);

INSERT INTO producto (categoria_id, marca_id, codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'chaquetas'),
    (SELECT id FROM marca WHERE nombre = 'UrbanStep'),
    'CHA-001', 'Chaqueta Impermeable Urban', 'chaqueta-impermeable-urban',
    'Chaqueta cortavientos con capucha desmontable.',
    'Nylon impermeable', 'UNISEX', 349.90, FALSE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'zapatillas'),
    (SELECT id FROM marca WHERE nombre = 'UrbanStep'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    'ZAP-001', 'Zapatillas Urban Run', 'zapatillas-urban-run',
    'Zapatillas deportivas con suela de espuma amortiguada.',
    'Mesh y sintetico', 'UNISEX', 429.90, TRUE
);

INSERT INTO producto (categoria_id, marca_id, codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'accesorios'),
    (SELECT id FROM marca WHERE nombre = 'FashionStore Basics'),
    'ACC-001', 'Bufanda Basica', 'bufanda-basica',
    'Bufanda tejida de talla unica.',
    'Acrilico', 'UNISEX', 59.90, FALSE
);

-- Camiseta Basica: tallas S/M/L x todos los colores
INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'camiseta-basica'), t.id, c.id,
       'CAM-001-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo IN ('S', 'M', 'L');

-- Jean Slim Fit: tallas numericas 38/40/42/44 x Azul/Negro/Gris
INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'jean-slim-fit'), t.id, c.id,
       'PAN-001-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'NUMERO' AND t.codigo IN ('38', '40', '42', '44')
  AND c.nombre IN ('Azul', 'Negro', 'Gris');

-- Vestido Floral: tallas S/M/L x Rojo/Negro/Beige
INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'vestido-floral-manga-corta'), t.id, c.id,
       'VES-001-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo IN ('S', 'M', 'L')
  AND c.nombre IN ('Rojo', 'Negro', 'Beige');

-- Chaqueta Impermeable: tallas M/L/XL x Negro/Azul
INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'chaqueta-impermeable-urban'), t.id, c.id,
       'CHA-001-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo IN ('M', 'L', 'XL')
  AND c.nombre IN ('Negro', 'Azul');

-- Zapatillas Urban Run: tallas de calzado 38-42 x Blanco/Negro
INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'zapatillas-urban-run'), t.id, c.id,
       'ZAP-001-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'CALZADO' AND t.codigo IN ('38', '39', '40', '41', '42')
  AND c.nombre IN ('Blanco', 'Negro');

-- Bufanda Basica: talla unica x Gris/Beige/Rojo
INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'bufanda-basica'), t.id, c.id,
       'ACC-001-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo = 'UNICA'
  AND c.nombre IN ('Gris', 'Beige', 'Rojo');

-- Una imagen principal de catalogo por producto (placeholder)
INSERT INTO producto_imagen (producto_id, uso, url, formato, es_principal, orden)
SELECT id, 'CATALOGO', 'https://picsum.photos/seed/' || slug || '/600/800', 'JPG', TRUE, 0
FROM producto;

-- ---------------------------------------------------------------------
-- INVENTARIO: cada variante existente en cada sucursal
-- ---------------------------------------------------------------------

INSERT INTO inventario (sucursal_id, variante_id, cantidad_fisica, stock_minimo)
SELECT s.id, pv.id, (5 + floor(random() * 25))::int, 5
FROM producto_variante pv
CROSS JOIN sucursal s
ON CONFLICT (sucursal_id, variante_id) DO NOTHING;

-- ---------------------------------------------------------------------
-- PROMOCIONES
-- ---------------------------------------------------------------------

INSERT INTO promocion (nombre, codigo_cupon, tipo, valor, alcance, fecha_inicio, fecha_fin) VALUES
    ('Bienvenida 10%', 'BIENVENIDA10', 'PORCENTAJE', 10, 'TODO', '2026-01-01', '2026-12-31');

INSERT INTO promocion (nombre, codigo_cupon, tipo, valor, alcance, temporada_id, fecha_inicio, fecha_fin)
VALUES (
    'Verano 15% en coleccion de temporada', 'VERANO15', 'PORCENTAJE', 15, 'TEMPORADA',
    (SELECT id FROM temporada WHERE nombre = 'Primavera-Verano 2026'),
    '2026-09-01', '2027-02-28'
);

-- ---------------------------------------------------------------------
-- PARAMETRIA
-- ---------------------------------------------------------------------

INSERT INTO configuracion (clave, valor, descripcion) VALUES
    ('reserva_horas_vigencia', '4', 'Horas antes de que una reserva pendiente expire automaticamente'),
    ('empresa_razon_social',   'FashionStore Bolivia S.R.L.', 'Razon social para comprobantes'),
    ('empresa_nit',            '1234567890', 'NIT para comprobantes');
