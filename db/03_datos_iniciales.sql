-- =====================================================================
--  FashionStore - Datos iniciales para desarrollo local
--  Modelo de negocio: cadena de MODA FEMENINA (mujer de 18 a 40 anios) con tres
--  sucursales en tres climas distintos de Bolivia. Todo el catalogo es genero
--  MUJER; el surtido de cada sucursal se reparte segun el clima de su ciudad y
--  la temporada de la prenda, no en partes iguales (ver INVENTARIO, mas abajo).
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
    ('VENDEDOR',  'Atiende clientes y reservas en tienda', TRUE),
    ('ALMACEN',   'Recibe mercaderia y controla existencias', TRUE);

-- ---------------------------------------------------------------------
-- PERMISOS Y ASIGNACION A ROLES (CU13)
-- El backend autoriza por codigo de permiso, no por nombre de rol:
-- ver requiere_permiso() en app/core/deps.py.
-- ---------------------------------------------------------------------

INSERT INTO permiso (codigo, modulo, descripcion) VALUES
    ('usuarios.ver',           'usuarios',    'Consultar el padron de usuarios'),
    ('usuarios.gestionar',     'usuarios',    'Crear, editar y dar de baja usuarios'),
    ('roles.ver',              'usuarios',    'Consultar roles y sus permisos'),
    ('roles.gestionar',        'usuarios',    'Crear roles y reasignar sus permisos'),
    ('catalogo.ver',           'catalogo',    'Consultar el catalogo completo, incluido lo inactivo'),
    ('catalogo.gestionar',     'catalogo',    'Alta, baja y modificacion de prendas y variantes'),
    ('proveedores.ver',        'compras',     'Consultar proveedores'),
    ('proveedores.gestionar',  'compras',     'Alta, baja y modificacion de proveedores'),
    ('sucursales.ver',         'organizacion','Consultar sucursales y cajas'),
    ('sucursales.gestionar',   'organizacion','Alta, baja y modificacion de sucursales y cajas'),
    ('inventario.ver',         'inventario',  'Consultar existencias y kardex'),
    ('inventario.ajustar',     'inventario',  'Registrar ajustes manuales de stock'),
    ('recepciones.ver',        'inventario',  'Consultar recepciones de mercaderia'),
    ('recepciones.registrar',  'inventario',  'Cargar recepciones en borrador'),
    ('recepciones.confirmar',  'inventario',  'Confirmar o anular una recepcion'),
    ('reservas.atender',       'reservas',    'Atender la cola de reservas de la sucursal'),
    ('caja.operar',            'ventas',      'Abrir y cerrar sesiones de caja'),
    ('ventas.pos',             'ventas',      'Registrar ventas presenciales'),
    ('reportes.ver',           'reportes',    'Consultar los tableros de gestion');

-- ADMIN: todo
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'ADMIN'), p.id FROM permiso p;

-- ENCARGADO: manda en su sucursal (inventario, recepciones, reservas, reportes)
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'ENCARGADO'), p.id
  FROM permiso p
 WHERE p.codigo IN ('usuarios.ver','catalogo.ver','proveedores.ver','sucursales.ver',
                    'inventario.ver','inventario.ajustar','recepciones.ver',
                    'recepciones.registrar','recepciones.confirmar','reservas.atender',
                    'reportes.ver');

-- ALMACEN: solo el flujo de entrada de mercaderia
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'ALMACEN'), p.id
  FROM permiso p
 WHERE p.codigo IN ('catalogo.ver','proveedores.ver','inventario.ver','inventario.ajustar',
                    'recepciones.ver','recepciones.registrar','recepciones.confirmar');

-- CAJERO: caja y punto de venta
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'CAJERO'), p.id
  FROM permiso p
 WHERE p.codigo IN ('catalogo.ver','inventario.ver','caja.operar','ventas.pos');

-- VENDEDOR: piso de venta y vestidores
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'VENDEDOR'), p.id
  FROM permiso p
 WHERE p.codigo IN ('catalogo.ver','inventario.ver','reservas.atender');

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
     'STAFF', (SELECT id FROM rol WHERE nombre = 'VENDEDOR'),  TRUE),
    ('almacen.scz@fashionstore.bo',     crypt('demo1234', gen_salt('bf')), 'Ruben',   'Mamani',
     'STAFF', (SELECT id FROM rol WHERE nombre = 'ALMACEN'),   TRUE);

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
     (SELECT id FROM sucursal WHERE codigo = 'SC-01'), 'VENDEDOR', CURRENT_DATE),
    ((SELECT id FROM usuario WHERE email = 'almacen.scz@fashionstore.bo'),
     (SELECT id FROM sucursal WHERE codigo = 'SC-01'), 'ALMACEN', CURRENT_DATE);

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

-- Curva de tallas femenina: LETRA para la parte superior y vestidos, NUMERO
-- para pantalones (36 a 46) y CALZADO de mujer (35 a 40).
INSERT INTO talla (codigo, tipo, orden) VALUES
    ('XS',    'LETRA', 0),
    ('S',     'LETRA', 1),
    ('M',     'LETRA', 2),
    ('L',     'LETRA', 3),
    ('XL',    'LETRA', 4),
    ('XXL',   'LETRA', 5),
    ('UNICA', 'LETRA', 0),
    ('36',    'NUMERO', 1),
    ('38',    'NUMERO', 2),
    ('40',    'NUMERO', 3),
    ('42',    'NUMERO', 4),
    ('44',    'NUMERO', 5),
    ('46',    'NUMERO', 6),
    ('35',    'CALZADO', 1),
    ('36',    'CALZADO', 2),
    ('37',    'CALZADO', 3),
    ('38',    'CALZADO', 4),
    ('39',    'CALZADO', 5),
    ('40',    'CALZADO', 6);

INSERT INTO color (nombre, codigo_hex) VALUES
    ('Negro',       '#000000'),
    ('Blanco',      '#FFFFFF'),
    ('Azul',        '#1E3A8A'),
    ('Rojo',        '#DC2626'),
    ('Gris',        '#6B7280'),
    ('Beige',       '#D2B48C'),
    ('Verde Oliva', '#556B2F'),
    ('Rosa Palo',   '#E8B4B8'),
    ('Camel',       '#C19A6B'),
    ('Vino',        '#722F37');

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
    ((SELECT id FROM categoria WHERE slug = 'ropa'),    'Blusas',     'blusas'),
    ((SELECT id FROM categoria WHERE slug = 'ropa'),    'Pantalones', 'pantalones'),
    ((SELECT id FROM categoria WHERE slug = 'ropa'),    'Vestidos',   'vestidos'),
    ((SELECT id FROM categoria WHERE slug = 'ropa'),    'Abrigos',    'abrigos'),
    ((SELECT id FROM categoria WHERE slug = 'ropa'),    'Faldas',     'faldas'),
    ((SELECT id FROM categoria WHERE slug = 'calzado'), 'Botas',      'botas'),
    ((SELECT id FROM categoria WHERE slug = 'calzado'), 'Sandalias',  'sandalias'),
    ((SELECT id FROM categoria WHERE slug = 'calzado'), 'Zapatos',    'zapatos');

-- Ver CATALOGO_DEMO.txt punto 3: Faldas/Sandalias/Zapatos se agregan para que
-- Botas (todo OI) contra Sandalias (todo PV) muestre el contraste de clima
-- entre sucursales de forma mas clara que con una sola subcategoria "Botas".
INSERT INTO marca (nombre) VALUES
    ('FashionStore Esencial'),
    ('Andina Denim'),
    ('Aurora Bolivia'),
    ('Kantuta Boutique'),
    ('Valle Textil'),
    ('Cordillera Urban');

-- Dos temporadas para que se vea el ciclo completo: la de invierno ya cerrada y
-- la de verano corriendo hoy. El tipo de temporada de cada prenda es lo que
-- decide como se reparte su stock entre las tres sucursales (ver INVENTARIO).
INSERT INTO temporada (nombre, tipo, fecha_inicio, fecha_fin, activa) VALUES
    ('Otonio-Invierno 2026',  'OTONO_INVIERNO',   '2026-03-01', '2026-08-31', FALSE),
    ('Primavera-Verano 2026', 'PRIMAVERA_VERANO', '2026-09-01', '2027-02-28', TRUE);

INSERT INTO coleccion (temporada_id, proveedor_id, nombre, descripcion, anio) VALUES
    ((SELECT id FROM temporada WHERE nombre = 'Otonio-Invierno 2026'),
     (SELECT id FROM proveedor WHERE nombre = 'Textiles Andinos SRL'),
     'Coleccion Altiplano 2026',
     'Abrigo y tejidos para el frio de altura; su peso esta en La Paz.',
     2026),
    ((SELECT id FROM temporada WHERE nombre = 'Primavera-Verano 2026'),
     (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
     'Coleccion Llanura 2026',
     'Prendas livianas para clima calido; su peso esta en Santa Cruz.',
     2026);

-- ---------------------------------------------------------------------
-- PRODUCTOS Y VARIANTES
-- ---------------------------------------------------------------------

-- Todo el catalogo es genero MUJER. Dos prendas de Primavera-Verano (pesan en
-- Santa Cruz), tres de Otonio-Invierno (pesan en La Paz) y un jean atemporal
-- sin temporada asignada, que rota parejo en las tres sucursales.

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'blusas'),
    (SELECT id FROM marca WHERE nombre = 'Aurora Bolivia'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Llanura 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Primavera-Verano 2026'),
    'BLU-001', 'Blusa de Lino Manga Corta', 'blusa-de-lino-manga-corta',
    'Blusa fresca de lino, corte holgado y escote en V.',
    'Lino 100%', 'MUJER', 159.90, TRUE
);

INSERT INTO producto (categoria_id, marca_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'vestidos'),
    (SELECT id FROM marca WHERE nombre = 'FashionStore Esencial'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Llanura 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Primavera-Verano 2026'),
    'VES-001', 'Vestido Floral Manga Corta', 'vestido-floral-manga-corta',
    'Vestido liviano estampado floral, ideal para clima calido.',
    'Viscosa', 'MUJER', 179.90, TRUE
);

-- Atemporal: no lleva temporada_id, se vende igual de bien todo el anio.
INSERT INTO producto (categoria_id, marca_id, proveedor_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'pantalones'),
    (SELECT id FROM marca WHERE nombre = 'Andina Denim'),
    (SELECT id FROM proveedor WHERE nombre = 'Textiles Andinos SRL'),
    'PAN-001', 'Jean Tiro Alto Skinny', 'jean-tiro-alto-skinny',
    'Jean de tiro alto con elastano, corte skinny que estiliza la silueta.',
    'Denim 98% algodon 2% elastano', 'MUJER', 249.90, TRUE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'abrigos'),
    (SELECT id FROM marca WHERE nombre = 'FashionStore Esencial'),
    (SELECT id FROM proveedor WHERE nombre = 'Textiles Andinos SRL'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Altiplano 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Otonio-Invierno 2026'),
    'ABR-001', 'Tapado de Lana Largo', 'tapado-de-lana-largo',
    'Tapado largo de pano de lana con cinturon, pensado para el frio de altura.',
    'Lana 70% poliester 30%', 'MUJER', 449.90, TRUE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'botas'),
    (SELECT id FROM marca WHERE nombre = 'Aurora Bolivia'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Altiplano 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Otonio-Invierno 2026'),
    'BOT-001', 'Botineta de Cuero con Taco', 'botineta-de-cuero-con-taco',
    'Botineta de cuero con taco bajo y cierre lateral.',
    'Cuero vacuno', 'MUJER', 389.90, TRUE
);

INSERT INTO producto (categoria_id, marca_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'accesorios'),
    (SELECT id FROM marca WHERE nombre = 'FashionStore Esencial'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Altiplano 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Otonio-Invierno 2026'),
    'ACC-001', 'Chalina de Alpaca', 'chalina-de-alpaca',
    'Chalina tejida en mezcla de alpaca, talla unica.',
    'Alpaca 50% acrilico 50%', 'MUJER', 89.90, FALSE
);

-- Blusa de Lino: tallas XS/S/M/L x Blanco/Rosa Palo/Negro
INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'blusa-de-lino-manga-corta'), t.id, c.id,
       'BLU-001-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo IN ('XS', 'S', 'M', 'L')
  AND c.nombre IN ('Blanco', 'Rosa Palo', 'Negro');

-- Vestido Floral: tallas S/M/L x Rojo/Negro/Beige
INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'vestido-floral-manga-corta'), t.id, c.id,
       'VES-001-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo IN ('S', 'M', 'L')
  AND c.nombre IN ('Rojo', 'Negro', 'Beige');

-- Jean Tiro Alto: tallas numericas 36/38/40/42/44 x Azul/Negro/Gris
INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), t.id, c.id,
       'PAN-001-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'NUMERO' AND t.codigo IN ('36', '38', '40', '42', '44')
  AND c.nombre IN ('Azul', 'Negro', 'Gris');

-- Tapado de Lana: tallas S/M/L/XL x Negro/Camel/Vino
INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'tapado-de-lana-largo'), t.id, c.id,
       'ABR-001-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo IN ('S', 'M', 'L', 'XL')
  AND c.nombre IN ('Negro', 'Camel', 'Vino');

-- Botineta de Cuero: tallas de calzado 35-40 x Negro/Camel
INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), t.id, c.id,
       'BOT-001-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'CALZADO' AND t.codigo IN ('35', '36', '37', '38', '39', '40')
  AND c.nombre IN ('Negro', 'Camel');

-- Chalina de Alpaca: talla unica x Gris/Beige/Vino
INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'chalina-de-alpaca'), t.id, c.id,
       'ACC-001-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo = 'UNICA'
  AND c.nombre IN ('Gris', 'Beige', 'Vino');

-- ---------------------------------------------------------------------
-- CATALOGO DE DEMOSTRACION: 34 productos nuevos (ver CATALOGO_DEMO.txt).
-- Mismo patron que los 6 de arriba: PV/OI llevan coleccion_id + temporada_id,
-- los atemporales (AT) no llevan ninguno de los dos. Genero siempre MUJER.
-- ---------------------------------------------------------------------

-- Recalibrar destacados: con 40 productos "casi todo destacado" deja de tener
-- sentido (CATALOGO_DEMO.txt punto 4.6). Los nuevos destacados se marcan en su
-- propio INSERT mas abajo, hasta sumar 9 repartidos entre las 9 categorias y
-- las dos temporadas (mas atemporales).
UPDATE producto SET destacado = FALSE WHERE codigo IN ('BLU-001', 'PAN-001');

-- ..... BLUSAS: BLU-002 a BLU-005 .....

INSERT INTO producto (categoria_id, marca_id, proveedor_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'blusas'),
    (SELECT id FROM marca WHERE nombre = 'Valle Textil'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    'BLU-002', 'Blusa de Seda Manga Larga', 'blusa-de-seda-manga-larga',
    'Blusa elegante de seda con cuello camisero, ideal para la oficina o una salida de noche.',
    'Seda 100%', 'MUJER', 219.90, TRUE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'blusas'),
    (SELECT id FROM marca WHERE nombre = 'Cordillera Urban'),
    (SELECT id FROM proveedor WHERE nombre = 'Textiles Andinos SRL'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Altiplano 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Otonio-Invierno 2026'),
    'BLU-003', 'Camisa Oversize a Cuadros', 'camisa-oversize-a-cuadros',
    'Camisa oversize de franela a cuadros, calida y facil de combinar en capas.',
    'Algodon 80% poliester 20%', 'MUJER', 189.90, FALSE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'blusas'),
    (SELECT id FROM marca WHERE nombre = 'Valle Textil'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Llanura 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Primavera-Verano 2026'),
    'BLU-004', 'Top de Tirantes de Algodon', 'top-de-tirantes-de-algodon',
    'Top basico de algodon con tirantes finos, perfecto para el calor.',
    'Algodon 95% elastano 5%', 'MUJER', 99.90, FALSE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'blusas'),
    (SELECT id FROM marca WHERE nombre = 'Cordillera Urban'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Llanura 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Primavera-Verano 2026'),
    'BLU-005', 'Blusa Cropped con Volados', 'blusa-cropped-con-volados',
    'Blusa cropped con volados en el escote, corte juvenil y fresco.',
    'Viscosa', 'MUJER', 139.90, FALSE
);

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), t.id, c.id,
       'BLU-002-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo IN ('XS', 'S', 'M', 'L')
  AND c.nombre IN ('Blanco', 'Beige', 'Vino');

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'camisa-oversize-a-cuadros'), t.id, c.id,
       'BLU-003-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo IN ('S', 'M', 'L', 'XL')
  AND c.nombre IN ('Rojo', 'Verde Oliva', 'Gris');

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'top-de-tirantes-de-algodon'), t.id, c.id,
       'BLU-004-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo IN ('XS', 'S', 'M', 'L')
  AND c.nombre IN ('Blanco', 'Negro', 'Rosa Palo');

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'blusa-cropped-con-volados'), t.id, c.id,
       'BLU-005-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo IN ('XS', 'S', 'M')
  AND c.nombre IN ('Blanco', 'Rosa Palo', 'Beige');

-- ..... VESTIDOS: VES-002 a VES-006 .....

INSERT INTO producto (categoria_id, marca_id, proveedor_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'vestidos'),
    (SELECT id FROM marca WHERE nombre = 'FashionStore Esencial'),
    (SELECT id FROM proveedor WHERE nombre = 'Textiles Andinos SRL'),
    'VES-002', 'Vestido Midi Plisado', 'vestido-midi-plisado',
    'Vestido midi plisado con cinturon a tono, silueta favorecedora para cualquier ocasion.',
    'Poliester plisado', 'MUJER', 259.90, FALSE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'vestidos'),
    (SELECT id FROM marca WHERE nombre = 'Kantuta Boutique'),
    (SELECT id FROM proveedor WHERE nombre = 'Textiles Andinos SRL'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Altiplano 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Otonio-Invierno 2026'),
    'VES-003', 'Vestido de Punto Manga Larga', 'vestido-de-punto-manga-larga',
    'Vestido de punto grueso con manga larga, calido y ajustado al cuerpo.',
    'Acrilico 60% lana 40%', 'MUJER', 299.90, FALSE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'vestidos'),
    (SELECT id FROM marca WHERE nombre = 'Valle Textil'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Llanura 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Primavera-Verano 2026'),
    'VES-004', 'Vestido Camisero de Lino', 'vestido-camisero-de-lino',
    'Vestido camisero de lino con cinturon, fresco y versatil para el dia.',
    'Lino 100%', 'MUJER', 229.90, FALSE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'vestidos'),
    (SELECT id FROM marca WHERE nombre = 'Cordillera Urban'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    'VES-005', 'Vestido Negro de Fiesta', 'vestido-negro-de-fiesta',
    'Vestido negro entallado con escote cruzado, la opcion segura para una fiesta.',
    'Poliester con elastano', 'MUJER', 389.90, FALSE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'vestidos'),
    (SELECT id FROM marca WHERE nombre = 'FashionStore Esencial'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Llanura 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Primavera-Verano 2026'),
    'VES-006', 'Vestido Largo Estampado', 'vestido-largo-estampado',
    'Vestido largo estampado de corte fluido, ideal para el clima calido.',
    'Viscosa estampada', 'MUJER', 269.90, FALSE
);

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'vestido-midi-plisado'), t.id, c.id,
       'VES-002-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo IN ('S', 'M', 'L')
  AND c.nombre IN ('Camel', 'Negro', 'Vino');

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'vestido-de-punto-manga-larga'), t.id, c.id,
       'VES-003-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo IN ('S', 'M', 'L', 'XL')
  AND c.nombre IN ('Gris', 'Negro', 'Camel');

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), t.id, c.id,
       'VES-004-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo IN ('XS', 'S', 'M', 'L')
  AND c.nombre IN ('Blanco', 'Beige', 'Azul');

-- Vestido Negro de Fiesta: un solo color (lo dice el nombre), solo varia la talla.
INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'vestido-negro-de-fiesta'), t.id, c.id,
       'VES-005-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo IN ('XS', 'S', 'M', 'L')
  AND c.nombre = 'Negro';

-- Vestido Largo Estampado: estampado, un solo color nominal (ver CATALOGO_DEMO.txt
-- punto 1 -- no se le generan variantes de color por IA, se deforma el estampado).
INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'vestido-largo-estampado'), t.id, c.id,
       'VES-006-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo IN ('S', 'M', 'L')
  AND c.nombre = 'Beige';

-- ..... PANTALONES: PAN-002 a PAN-005 .....

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'pantalones'),
    (SELECT id FROM marca WHERE nombre = 'Valle Textil'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Llanura 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Primavera-Verano 2026'),
    'PAN-002', 'Pantalon Palazzo de Lino', 'pantalon-palazzo-de-lino',
    'Pantalon palazzo de lino, tiro alto y pierna ancha para los dias de calor.',
    'Lino 100%', 'MUJER', 199.90, TRUE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'pantalones'),
    (SELECT id FROM marca WHERE nombre = 'FashionStore Esencial'),
    (SELECT id FROM proveedor WHERE nombre = 'Textiles Andinos SRL'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Altiplano 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Otonio-Invierno 2026'),
    'PAN-003', 'Pantalon de Vestir Sastrero', 'pantalon-de-vestir-sastrero',
    'Pantalon sastrero de vestir, corte recto y tela con caida para la oficina.',
    'Poliester 65% viscosa 35%', 'MUJER', 279.90, FALSE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'pantalones'),
    (SELECT id FROM marca WHERE nombre = 'Andina Denim'),
    (SELECT id FROM proveedor WHERE nombre = 'Textiles Andinos SRL'),
    'PAN-004', 'Jean Wide Leg', 'jean-wide-leg',
    'Jean wide leg de tiro alto, silueta ancha y comoda que estiliza.',
    'Denim 100% algodon', 'MUJER', 269.90, FALSE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'pantalones'),
    (SELECT id FROM marca WHERE nombre = 'Kantuta Boutique'),
    (SELECT id FROM proveedor WHERE nombre = 'Textiles Andinos SRL'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Altiplano 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Otonio-Invierno 2026'),
    'PAN-005', 'Legging Termico', 'legging-termico',
    'Legging termico afelpado por dentro, pensado para el frio de altura.',
    'Poliester afelpado con elastano', 'MUJER', 129.90, FALSE
);

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), t.id, c.id,
       'PAN-002-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'NUMERO' AND t.codigo IN ('36', '38', '40', '42')
  AND c.nombre IN ('Blanco', 'Beige', 'Verde Oliva');

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), t.id, c.id,
       'PAN-003-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'NUMERO' AND t.codigo IN ('36', '38', '40', '42', '44')
  AND c.nombre IN ('Negro', 'Gris', 'Azul');

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'jean-wide-leg'), t.id, c.id,
       'PAN-004-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'NUMERO' AND t.codigo IN ('36', '38', '40', '42', '44')
  AND c.nombre IN ('Azul', 'Negro', 'Blanco');

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'legging-termico'), t.id, c.id,
       'PAN-005-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo IN ('XS', 'S', 'M', 'L', 'XL')
  AND c.nombre IN ('Negro', 'Gris', 'Azul');

-- ..... FALDAS (categoria nueva): FAL-001 a FAL-004 .....

INSERT INTO producto (categoria_id, marca_id, proveedor_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'faldas'),
    (SELECT id FROM marca WHERE nombre = 'FashionStore Esencial'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    'FAL-001', 'Falda Midi Plisada', 'falda-midi-plisada',
    'Falda midi plisada de cintura alta, combina con blusas y sweaters por igual.',
    'Poliester plisado', 'MUJER', 189.90, TRUE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'faldas'),
    (SELECT id FROM marca WHERE nombre = 'Andina Denim'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Llanura 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Primavera-Verano 2026'),
    'FAL-002', 'Falda de Jean Corta', 'falda-de-jean-corta',
    'Falda de jean corta con botones frontales, un basico del guardarropa.',
    'Denim 98% algodon 2% elastano', 'MUJER', 159.90, FALSE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'faldas'),
    (SELECT id FROM marca WHERE nombre = 'Valle Textil'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Llanura 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Primavera-Verano 2026'),
    'FAL-003', 'Falda Larga de Gasa', 'falda-larga-de-gasa',
    'Falda larga de gasa vaporosa, fresca y fluida para el verano.',
    'Gasa de poliester', 'MUJER', 209.90, FALSE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'faldas'),
    (SELECT id FROM marca WHERE nombre = 'Kantuta Boutique'),
    (SELECT id FROM proveedor WHERE nombre = 'Textiles Andinos SRL'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Altiplano 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Otonio-Invierno 2026'),
    'FAL-004', 'Falda Lapiz de Panio', 'falda-lapiz-de-panio',
    'Falda lapiz de pano de lana, entallada y formal, ideal para la oficina en invierno.',
    'Lana 80% poliester 20%', 'MUJER', 229.90, FALSE
);

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), t.id, c.id,
       'FAL-001-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'NUMERO' AND t.codigo IN ('36', '38', '40', '42')
  AND c.nombre IN ('Camel', 'Negro', 'Vino');

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), t.id, c.id,
       'FAL-002-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'NUMERO' AND t.codigo IN ('36', '38', '40', '42')
  AND c.nombre IN ('Azul', 'Negro', 'Blanco');

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), t.id, c.id,
       'FAL-003-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'NUMERO' AND t.codigo IN ('36', '38', '40')
  AND c.nombre IN ('Beige', 'Rosa Palo', 'Blanco');

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), t.id, c.id,
       'FAL-004-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'NUMERO' AND t.codigo IN ('36', '38', '40', '42')
  AND c.nombre IN ('Negro', 'Gris', 'Vino');

-- ..... ABRIGOS: ABR-002 a ABR-005 .....

INSERT INTO producto (categoria_id, marca_id, proveedor_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'abrigos'),
    (SELECT id FROM marca WHERE nombre = 'Andina Denim'),
    (SELECT id FROM proveedor WHERE nombre = 'Textiles Andinos SRL'),
    'ABR-002', 'Campera de Jean Oversize', 'campera-de-jean-oversize',
    'Campera de jean oversize, un basico atemporal para cualquier look.',
    'Denim 100% algodon', 'MUJER', 329.90, FALSE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'abrigos'),
    (SELECT id FROM marca WHERE nombre = 'Kantuta Boutique'),
    (SELECT id FROM proveedor WHERE nombre = 'Textiles Andinos SRL'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Altiplano 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Otonio-Invierno 2026'),
    'ABR-003', 'Cardigan de Punto Grueso', 'cardigan-de-punto-grueso',
    'Cardigan de punto grueso con botones, abrigado y facil de combinar.',
    'Acrilico 70% lana 30%', 'MUJER', 279.90, FALSE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'abrigos'),
    (SELECT id FROM marca WHERE nombre = 'Cordillera Urban'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    'ABR-004', 'Blazer Entallado', 'blazer-entallado',
    'Blazer entallado de un boton, la pieza clave para un look de oficina.',
    'Poliester 70% viscosa 30%', 'MUJER', 359.90, FALSE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'abrigos'),
    (SELECT id FROM marca WHERE nombre = 'Kantuta Boutique'),
    (SELECT id FROM proveedor WHERE nombre = 'Textiles Andinos SRL'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Altiplano 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Otonio-Invierno 2026'),
    'ABR-005', 'Campera Puffer Impermeable', 'campera-puffer-impermeable',
    'Campera puffer impermeable, acolchada para el frio intenso de altura.',
    'Poliester impermeable con relleno sintetico', 'MUJER', 419.90, FALSE
);

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), t.id, c.id,
       'ABR-002-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo IN ('S', 'M', 'L', 'XL')
  AND c.nombre IN ('Azul', 'Negro', 'Gris');

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), t.id, c.id,
       'ABR-003-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo IN ('S', 'M', 'L', 'XL')
  AND c.nombre IN ('Beige', 'Gris', 'Camel');

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'blazer-entallado'), t.id, c.id,
       'ABR-004-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo IN ('XS', 'S', 'M', 'L')
  AND c.nombre IN ('Negro', 'Beige', 'Azul');

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'campera-puffer-impermeable'), t.id, c.id,
       'ABR-005-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo IN ('S', 'M', 'L', 'XL')
  AND c.nombre IN ('Negro', 'Rojo', 'Verde Oliva');

-- ..... BOTAS: BOT-002 y BOT-003 .....

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'botas'),
    (SELECT id FROM marca WHERE nombre = 'Aurora Bolivia'),
    (SELECT id FROM proveedor WHERE nombre = 'Textiles Andinos SRL'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Altiplano 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Otonio-Invierno 2026'),
    'BOT-002', 'Bota Cania Alta de Gamuza', 'bota-cania-alta-de-gamuza',
    'Bota de cania alta en gamuza, calida y elegante para el invierno.',
    'Gamuza sintetica', 'MUJER', 519.90, FALSE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'botas'),
    (SELECT id FROM marca WHERE nombre = 'Aurora Bolivia'),
    (SELECT id FROM proveedor WHERE nombre = 'Textiles Andinos SRL'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Altiplano 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Otonio-Invierno 2026'),
    'BOT-003', 'Borcego Negro con Cordones', 'borcego-negro-con-cordones',
    'Borcego negro con cordones y suela de goma, resistente para el dia a dia.',
    'Cuero sintetico', 'MUJER', 349.90, FALSE
);

-- Bota Cania Alta de Gamuza: textura marcada, la IA la aplana (CATALOGO_DEMO.txt
-- punto 1). Colores reales de todos modos para el stock.
INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), t.id, c.id,
       'BOT-002-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'CALZADO' AND t.codigo IN ('35', '36', '37', '38', '39', '40')
  AND c.nombre IN ('Camel', 'Negro', 'Gris');

-- Borcego Negro: un solo color (lo dice el nombre).
INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), t.id, c.id,
       'BOT-003-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'CALZADO' AND t.codigo IN ('35', '36', '37', '38', '39', '40')
  AND c.nombre = 'Negro';

-- ..... SANDALIAS (categoria nueva): SAN-001 a SAN-003 .....

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'sandalias'),
    (SELECT id FROM marca WHERE nombre = 'Aurora Bolivia'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Llanura 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Primavera-Verano 2026'),
    'SAN-001', 'Sandalia de Plataforma', 'sandalia-de-plataforma',
    'Sandalia de plataforma con tiras, comoda y con altura para el verano.',
    'Cuero sintetico', 'MUJER', 249.90, TRUE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'sandalias'),
    (SELECT id FROM marca WHERE nombre = 'Aurora Bolivia'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Llanura 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Primavera-Verano 2026'),
    'SAN-002', 'Sandalia Baja de Cuero', 'sandalia-baja-de-cuero',
    'Sandalia baja de cuero genuino, simple y comoda para el dia a dia.',
    'Cuero vacuno', 'MUJER', 179.90, FALSE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'sandalias'),
    (SELECT id FROM marca WHERE nombre = 'Cordillera Urban'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Llanura 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Primavera-Verano 2026'),
    'SAN-003', 'Sandalia con Tiras y Taco', 'sandalia-con-tiras-y-taco',
    'Sandalia con tiras finas y taco medio, ideal para una salida de noche en verano.',
    'Cuero sintetico', 'MUJER', 289.90, FALSE
);

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'sandalia-de-plataforma'), t.id, c.id,
       'SAN-001-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'CALZADO' AND t.codigo IN ('35', '36', '37', '38', '39')
  AND c.nombre IN ('Blanco', 'Camel', 'Negro');

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'sandalia-baja-de-cuero'), t.id, c.id,
       'SAN-002-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'CALZADO' AND t.codigo IN ('35', '36', '37', '38', '39')
  AND c.nombre IN ('Camel', 'Negro', 'Beige');

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'sandalia-con-tiras-y-taco'), t.id, c.id,
       'SAN-003-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'CALZADO' AND t.codigo IN ('35', '36', '37', '38', '39')
  AND c.nombre IN ('Negro', 'Camel', 'Rojo');

-- ..... ZAPATOS (categoria nueva): ZAP-001 a ZAP-003 .....

INSERT INTO producto (categoria_id, marca_id, proveedor_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'zapatos'),
    (SELECT id FROM marca WHERE nombre = 'Cordillera Urban'),
    (SELECT id FROM proveedor WHERE nombre = 'Textiles Andinos SRL'),
    'ZAP-001', 'Zapato Stiletto de Charol', 'zapato-stiletto-de-charol',
    'Zapato stiletto de charol con taco fino, elegante para una ocasion formal.',
    'Charol sintetico', 'MUJER', 329.90, FALSE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'zapatos'),
    (SELECT id FROM marca WHERE nombre = 'Aurora Bolivia'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    'ZAP-002', 'Ballerina de Cuero', 'ballerina-de-cuero',
    'Ballerina de cuero suave, comoda para el uso diario.',
    'Cuero vacuno', 'MUJER', 219.90, FALSE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'zapatos'),
    (SELECT id FROM marca WHERE nombre = 'Cordillera Urban'),
    (SELECT id FROM proveedor WHERE nombre = 'Textiles Andinos SRL'),
    'ZAP-003', 'Zapatilla Urbana Blanca', 'zapatilla-urbana-blanca',
    'Zapatilla urbana blanca, comoda y facil de combinar con cualquier look casual.',
    'Cuero sintetico y textil', 'MUJER', 299.90, TRUE
);

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), t.id, c.id,
       'ZAP-001-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'CALZADO' AND t.codigo IN ('35', '36', '37', '38', '39')
  AND c.nombre IN ('Negro', 'Rojo', 'Vino');

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), t.id, c.id,
       'ZAP-002-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'CALZADO' AND t.codigo IN ('35', '36', '37', '38', '39')
  AND c.nombre IN ('Beige', 'Negro', 'Camel');

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'zapatilla-urbana-blanca'), t.id, c.id,
       'ZAP-003-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'CALZADO' AND t.codigo IN ('35', '36', '37', '38', '39', '40')
  AND c.nombre IN ('Blanco', 'Gris', 'Negro');

-- ..... ACCESORIOS: ACC-002 a ACC-006 .....

INSERT INTO producto (categoria_id, marca_id, proveedor_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'accesorios'),
    (SELECT id FROM marca WHERE nombre = 'Aurora Bolivia'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    'ACC-002', 'Cartera de Cuero Bandolera', 'cartera-de-cuero-bandolera',
    'Cartera bandolera de cuero con compartimentos internos, para el dia a dia.',
    'Cuero vacuno', 'MUJER', 349.90, TRUE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'accesorios'),
    (SELECT id FROM marca WHERE nombre = 'Valle Textil'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Llanura 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Primavera-Verano 2026'),
    'ACC-003', 'Sombrero de Ala Ancha', 'sombrero-de-ala-ancha',
    'Sombrero de paja de ala ancha, proteccion y estilo para el sol de verano.',
    'Paja natural', 'MUJER', 129.90, FALSE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'accesorios'),
    (SELECT id FROM marca WHERE nombre = 'Aurora Bolivia'),
    (SELECT id FROM proveedor WHERE nombre = 'Textiles Andinos SRL'),
    'ACC-004', 'Cinturon de Cuero Hebilla Dorada', 'cinturon-de-cuero-hebilla-dorada',
    'Cinturon de cuero con hebilla dorada, el detalle que termina cualquier outfit.',
    'Cuero vacuno', 'MUJER', 99.90, FALSE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'accesorios'),
    (SELECT id FROM marca WHERE nombre = 'Kantuta Boutique'),
    (SELECT id FROM proveedor WHERE nombre = 'Textiles Andinos SRL'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Altiplano 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Otonio-Invierno 2026'),
    'ACC-005', 'Gorro y Guantes de Lana', 'gorro-y-guantes-de-lana',
    'Set de gorro y guantes tejidos en lana, para el frio de altura.',
    'Lana 100%', 'MUJER', 119.90, FALSE
);

INSERT INTO producto (categoria_id, marca_id, proveedor_id, coleccion_id, temporada_id,
                       codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
VALUES (
    (SELECT id FROM categoria WHERE slug = 'accesorios'),
    (SELECT id FROM marca WHERE nombre = 'Valle Textil'),
    (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
    (SELECT id FROM coleccion WHERE nombre = 'Coleccion Llanura 2026'),
    (SELECT id FROM temporada WHERE nombre = 'Primavera-Verano 2026'),
    'ACC-006', 'Lentes de Sol Redondos', 'lentes-de-sol-redondos',
    'Lentes de sol redondos con proteccion UV, el accesorio infaltable del verano.',
    'Acetato y metal', 'MUJER', 149.90, FALSE
);

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'cartera-de-cuero-bandolera'), t.id, c.id,
       'ACC-002-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo = 'UNICA'
  AND c.nombre IN ('Camel', 'Negro', 'Vino');

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'sombrero-de-ala-ancha'), t.id, c.id,
       'ACC-003-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo = 'UNICA'
  AND c.nombre IN ('Beige', 'Camel', 'Negro');

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'cinturon-de-cuero-hebilla-dorada'), t.id, c.id,
       'ACC-004-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo = 'UNICA'
  AND c.nombre IN ('Negro', 'Camel', 'Vino');

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'gorro-y-guantes-de-lana'), t.id, c.id,
       'ACC-005-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo = 'UNICA'
  AND c.nombre IN ('Gris', 'Negro', 'Beige');

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT (SELECT id FROM producto WHERE slug = 'lentes-de-sol-redondos'), t.id, c.id,
       'ACC-006-' || t.codigo || '-' || left(c.nombre, 3)
FROM talla t CROSS JOIN color c
WHERE t.tipo = 'LETRA' AND t.codigo = 'UNICA'
  AND c.nombre IN ('Negro', 'Camel', 'Vino');

-- ---------------------------------------------------------------------
-- IMAGENES DE CATALOGO: una foto real (packshot) por producto, ya buscadas en
-- CATALOGO_DEMO.txt punto 2. Reemplaza el INSERT generico de picsum.photos que
-- habia antes. Los 3 productos sin URL confiable en ese archivo (BLU-005,
-- VES-006, SAN-003) quedan con un placeholder hasta conseguirles foto real.
-- ---------------------------------------------------------------------

INSERT INTO producto_imagen (producto_id, uso, url, formato, es_principal, orden) VALUES
    ((SELECT id FROM producto WHERE slug = 'blusa-de-lino-manga-corta'), 'CATALOGO',
     'https://media.istockphoto.com/id/2180698543/photo/white-shirt-isolated.jpg?s=612x612&w=0&k=20&c=ke_XcMkuV2IIOzI-6MQnUor-MJzQAdUKkYrnvemdUiM=', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), 'CATALOGO',
     'https://media.istockphoto.com/id/2255268145/photo/elegant-ivory-silk-blouse-with-long-sleeves-isolated-on-white-background.jpg?s=612x612&w=0&k=20&c=USdp1O2pH6U-R4lUpAq9Z5x1dvNftHMQ6IPH06NX5sg=', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'camisa-oversize-a-cuadros'), 'CATALOGO',
     'https://media.istockphoto.com/id/475162084/photo/shirt-isolated.jpg?s=612x612&w=0&k=20&c=HGq9q6NHPQYzimpvH7p6YjMttBLE8ylG5rMw1WsPieU=', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'top-de-tirantes-de-algodon'), 'CATALOGO',
     'https://media.istockphoto.com/id/528056874/photo/sport-top.jpg?s=612x612&w=0&k=20&c=eVyv4BrkAXlKJC-A9nVIoyb_e8tBzxuSXR5p0oFv4YM=', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'blusa-cropped-con-volados'), 'CATALOGO',
     'https://picsum.photos/seed/blusa-cropped-con-volados/1200/1600', 'JPG', TRUE, 0),

    ((SELECT id FROM producto WHERE slug = 'vestido-floral-manga-corta'), 'CATALOGO',
     'https://media.istockphoto.com/id/178851955/photo/flowery-evase-bateau-yellow-dress.jpg?s=612x612&w=0&k=20&c=EOJGCGC6dmFt0IQvbxq3PthCmNXO1flOpjYWC4KkcyQ=', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'vestido-midi-plisado'), 'CATALOGO',
     'https://media.istockphoto.com/id/2255268163/photo/modern-brown-v-neck-midi-dress-with-waist-tie-front-and-back-view.jpg?s=612x612&w=0&k=20&c=xwcEaLiKNUIZ4RwVHUZIPb0E5Ldla_wE_7zDGVpCQMU=', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'vestido-de-punto-manga-larga'), 'CATALOGO',
     'https://mikuta.com/cdn/shop/files/mikuta-the-striped-knitted-low-back-longsleeve-dress-product-shot.jpg?v=1776676381', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), 'CATALOGO',
     'https://media.mango.com/is/image/punto/87004786-10-900?wid=2048', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'vestido-negro-de-fiesta'), 'CATALOGO',
     'https://media.istockphoto.com/id/2254822072/photo/elegant-black-short-sleeve-pencil-dress-isolated-on-white-background.jpg?s=612x612&w=0&k=20&c=CnJyPXN0U0k85S9IoIDrKkkyg57hOfcN9dXChgTF8jo=', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'vestido-largo-estampado'), 'CATALOGO',
     'https://picsum.photos/seed/vestido-largo-estampado/1200/1600', 'JPG', TRUE, 0),

    ((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), 'CATALOGO',
     'https://guess.com.au/cdn/shop/files/W2YA46D4Q01-CLH1-ALTGHOST.jpg?v=1764817622&width=1100', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), 'CATALOGO',
     'https://www.morielheritage.com/cdn/shop/files/the-miela-linen-blend-pant-01.jpg?v=1785450152&width=1280', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), 'CATALOGO',
     'https://me.manieredevoir.com/cdn/shop/files/Wms-May-2-_0193_MDV1.jpg?v=1787650916&width=2000', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), 'CATALOGO',
     'https://veronicabeard.com/cdn/shop/files/J2603D411152WH_WHITE_FLAT.png?v=1771272212&width=3840', 'PNG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'legging-termico'), 'CATALOGO',
     'https://eu.icebreaker.com/cdn/shop/files/IB104476001-30.jpg?v=1756208754&width=1200', 'JPG', TRUE, 0),

    ((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), 'CATALOGO',
     'https://hrd-live.cdn.scayle.cloud/images/0ea61fecf7d1dcdc482a63ba76cbad35.jpg?brightness=1&width=922&height=1230&quality=75&bg=ffffff', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), 'CATALOGO',
     'https://c7.alamy.com/zooms/9/2f59a34500fc489fb866570967e4c329/3f8px56.jpg', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), 'CATALOGO',
     'https://www.na-kd.com/cdn-cgi/image/width=300,quality=80,sharpen=0.3/globalassets/low_waist_chiffon_maxi_skirt_1881-000007-0765_0019_flatlayf.jpg', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), 'CATALOGO',
     'https://www.vivienofholloway.com/images/pencil-skirt-black-wool-p4379-18473_image.jpg', 'JPG', TRUE, 0),

    ((SELECT id FROM producto WHERE slug = 'tapado-de-lana-largo'), 'CATALOGO',
     'https://www.coatcheckroom.com/cdn/shop/files/Long_Wool_Camel_Coat_1100x.jpg?v=1709073960', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), 'CATALOGO',
     'https://www.shoppriceless.com/cdn/shop/files/Susan-Denim-Jacket_CUTUT.jpg?v=1752697254&width=2000', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), 'CATALOGO',
     'https://ginatricot-pim.imgix.net/307011265/30701126505.jpg', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'blazer-entallado'), 'CATALOGO',
     'https://img.magnific.com/premium-psd/elegant-white-blazer-with-single-pocket_1296994-137380.jpg?semt=ais_hybrid&w=740&q=80', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'campera-puffer-impermeable'), 'CATALOGO',
     'https://img01.ztat.net/article/spp-media-p1/7c125863a40147ac8079023bcc9af6e8/343cec9a61e746aaa0cd02abb27eb90d.jpg?imwidth=1800&filter=packshot', 'JPG', TRUE, 0),

    ((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), 'CATALOGO',
     'https://www.jomercer.com.au/cdn/shop/files/TaylorHighAnkleBootsOffWhiteLeather2.jpg?v=1779084640', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), 'CATALOGO',
     'https://img.tkmaxx.com/medias/25299139-medium-wl-01.jpg', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), 'CATALOGO',
     'https://cdn.torrid.com/i/torrid/13573020_00133_hi?$pdp_hero_desktop_main$&fmt=auto', 'JPG', TRUE, 0),

    ((SELECT id FROM producto WHERE slug = 'sandalia-de-plataforma'), 'CATALOGO',
     'https://souliers-martinez.com/cdn/shop/files/souliers-martinez-summer-white-leather-sandals-women-design-shoes-packshot1_800x.jpg?v=1771000590', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'sandalia-baja-de-cuero'), 'CATALOGO',
     'https://img.magnific.com/premium-psd/elegant-brown-leather-flat-sandals-women_980117-18364.jpg?semt=ais_hybrid&w=740&q=80', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'sandalia-con-tiras-y-taco'), 'CATALOGO',
     'https://picsum.photos/seed/sandalia-con-tiras-y-taco/1200/1600', 'JPG', TRUE, 0),

    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), 'CATALOGO',
     'https://img.magnific.com/premium-photo/elegant-black-high-heels-with-pointed-toes-slim-stiletto-heels-emphasizing-classic-look-isolated-transparency-background_997534-75519.jpg?semt=ais_hybrid&w=740&q=80', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), 'CATALOGO',
     'https://bespokyshoes.com/cdn/shop/files/tulip-barefoot-ballet-flats-women-cream-calf-leather-95011_main.jpg?v=1780917337&width=2000', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'zapatilla-urbana-blanca'), 'CATALOGO',
     'https://i5.walmartimages.com/seo/Yolanda-Zula-Women-s-Slip-Resistant-Casual-Lace-Up-Flat-Round-Toe-Shoes-White-US-8_08f123ff-ca0e-4202-810f-0a4e70b6af73.789b9d4f846ffe41dc41492e1b796645.jpeg?odnHeight=768&odnWidth=768&odnBg=FFFFFF', 'JPG', TRUE, 0),

    ((SELECT id FROM producto WHERE slug = 'chalina-de-alpaca'), 'CATALOGO',
     'https://inismeain.ie/cdn/shop/files/A0251_Inis_Meain_Alpaca_Rib_Scarf_Grey_1x1_Product_1.jpg?v=1767716073&width=2000', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'cartera-de-cuero-bandolera'), 'CATALOGO',
     'https://img.magnific.com/free-psd/brown-leather-crossbody-bag-with-buckle_84443-87785.jpg?semt=ais_hybrid&w=740&q=80', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'sombrero-de-ala-ancha'), 'CATALOGO',
     'https://t3.ftcdn.net/jpg/18/55/79/38/360_F_1855793847_kHdGgySjrr5M3yopKX0U2TXRSxsyY2Gu.jpg', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'cinturon-de-cuero-hebilla-dorada'), 'CATALOGO',
     'https://www.hanksbelts.com/cdn/shop/files/Hanks_Womens_Leather_Belts_Addyson_-_1_Black__0002_GenerativeFill_600x.jpg?v=1754403106', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'gorro-y-guantes-de-lana'), 'CATALOGO',
     'https://menique.com/cdn/shop/files/Unisex-Beanie-Knit-Merino-_-Beanie-_-Gloves-Dark-Gray.jpg?crop=center&height=1200&v=1749801320&width=960', 'JPG', TRUE, 0),
    ((SELECT id FROM producto WHERE slug = 'lentes-de-sol-redondos'), 'CATALOGO',
     'https://i5.walmartimages.ca/asr/d2894267-9f43-4b2b-aa5e-d509f180a2fa.d0cbeb6930acbf63b99f46b02c37ae82.jpeg?odnHeight=2000&odnWidth=2000&odnBg=FFFFFF', 'JPG', TRUE, 0);

-- ---------------------------------------------------------------------
-- IMAGENES POR COLOR: una foto de stock por cada combinacion producto+color
-- (variantes de color reales) para que el selector de color en el detalle
-- de producto muestre la prenda en el color elegido en vez de repetir
-- siempre la foto generica de arriba. Igual que las de CATALOGO, son fotos
-- representativas (no del producto ficticio exacto), verificadas al
-- buscarlas. Quedan afuera 'borcego-negro-con-cordones', 'vestido-negro-de-fiesta'
-- y 'vestido-largo-estampado' porque solo tienen un color en este catalogo.
-- ---------------------------------------------------------------------

INSERT INTO producto_imagen (producto_id, color_id, uso, url, formato, es_principal, orden) VALUES
-- ballerina-de-cuero
((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM color WHERE nombre = 'Beige'), 'CATALOGO', 'https://media.istockphoto.com/id/601948490/photo/beige-ballet-flats.jpg?s=612x612&w=0&k=20&c=IXfrRLHCZNjdggWfk8xMW3cxGPaOmocIw_osrNaRtu4=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM color WHERE nombre = 'Camel'), 'CATALOGO', 'https://media.istockphoto.com/id/2282640315/photo/pair-of-elegant-brown-leather-womens-flat-shoes-on-white-background.jpg?s=612x612&w=0&k=20&c=ndUTpDdzU8pxU5FoO68aS5gxEYp2bph-_MGazzh2yFY=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/1554278910/photo/classy-black-pointed-toe-leather-ballet-flats-with-wrinkled-and-ruffle-details-isolated-on.jpg?s=612x612&w=0&k=20&c=YQwiBdwOH2xTGlKTqCP1i5gg4-h_2LHbTM8FMzlacb8=', 'JPG', FALSE, 1),

-- blazer-entallado
((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM color WHERE nombre = 'Azul'), 'CATALOGO', 'https://media.istockphoto.com/id/1421649170/photo/portrait-of-smiling-businesswoman-wearing-blue-blazer.jpg?s=612x612&w=0&k=20&c=DjbUCdSpK_gqczjvVZUfU5RtjofShs5YF5vIx3-H0P4=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM color WHERE nombre = 'Beige'), 'CATALOGO', 'https://media.istockphoto.com/id/1455867077/photo/studio-portrait-of-young-female-model-in-beige-tailored-blazer.jpg?s=612x612&w=0&k=20&c=ZJI5mpsieNf-VQwH1dOH_A0Ym5YxzKZhCmiVfnydYdA=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/1387254731/photo/female-model-wearing-black-tailored-blazer-and-short-pants-studio-shot.jpg', 'JPG', FALSE, 1),

-- blusa-cropped-con-volados
((SELECT id FROM producto WHERE slug = 'blusa-cropped-con-volados'), (SELECT id FROM color WHERE nombre = 'Beige'), 'CATALOGO', 'https://media.istockphoto.com/id/2219799990/photo/cheerful-young-woman-with-long-straight-hair-smiles-brightly-while-wearing-light-beige-ruched.jpg', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'blusa-cropped-con-volados'), (SELECT id FROM color WHERE nombre = 'Blanco'), 'CATALOGO', 'https://media.istockphoto.com/id/2257056161/photo/young-adult-woman-posing-in-white-ruffle-blouse-in-marrakech.jpg', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'blusa-cropped-con-volados'), (SELECT id FROM color WHERE nombre = 'Rosa Palo'), 'CATALOGO', 'https://media.istockphoto.com/id/532978360/photo/blouse.jpg', 'JPG', FALSE, 1),

-- blusa-de-lino-manga-corta
((SELECT id FROM producto WHERE slug = 'blusa-de-lino-manga-corta'), (SELECT id FROM color WHERE nombre = 'Blanco'), 'CATALOGO', 'https://media.istockphoto.com/id/2156880040/photo/woman-in-a-white-linen-shirt-touching-her-neck.jpg?s=612x612&w=0&k=20&c=QycjaSVNUlVIJIOuev0poIv6eYIUQDqXMFfzSmYV4s8=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'blusa-de-lino-manga-corta'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/2248853584/photo/female-model-wearing-comfortable-basic-smart-casual-black-viscose-boat-neckline-shirt.jpg?s=612x612&w=0&k=20&c=o7pQIHbPB9tAFnQvQQAsvm8WtXy2lqjiT1RAZ5yWSvg=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'blusa-de-lino-manga-corta'), (SELECT id FROM color WHERE nombre = 'Rosa Palo'), 'CATALOGO', 'https://media.istockphoto.com/id/1208524463/photo/portrait-of-content-confident-young-woman-in-pink-blouse-leaning-head-on-hand-against-white.jpg', 'JPG', FALSE, 1),

-- blusa-de-seda-manga-larga
((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM color WHERE nombre = 'Beige'), 'CATALOGO', 'https://media.istockphoto.com/id/1162703427/photo/folded-blouse-isolated.jpg?s=612x612&w=0&k=20&c=bQthMxtUbydAjB-z6VEN4SVQDUdAB6E-X2MFm5oZqDE=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM color WHERE nombre = 'Blanco'), 'CATALOGO', 'https://media.istockphoto.com/id/2132915391/photo/fashion-portrait-of-beautiful-female-model-wearing-elegant-black-trousers-and-white-silk.jpg?s=612x612&w=0&k=20&c=4m7kSYsWcIerYnXNzHrTUwJdN20YcmW4gEGDtngFvEM=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM color WHERE nombre = 'Vino'), 'CATALOGO', 'https://media.istockphoto.com/id/518175800/photo/blouse.jpg', 'JPG', FALSE, 1),

-- bota-cania-alta-de-gamuza
((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM color WHERE nombre = 'Camel'), 'CATALOGO', 'https://media.istockphoto.com/id/497025176/photo/womens-brown-suede-high-heeled-boots.jpg?s=612x612&w=0&k=20&c=DdgxJ7BDRgJRebQFqbY2bodht_ul15Ny-Q2QdMdtFfE=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'https://media.istockphoto.com/id/497025594/photo/womens-gray-suede-boots-with-low-heels.jpg?s=612x612&w=0&k=20&c=WBiGb6JD39Mi-pu7bFNVVl9qB8WgQEHWmPganr0IG3I=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/1332823809/photo/female-suede-high-boots.jpg?s=612x612&w=0&k=20&c=QyQGiS407QxINt1mXz13MItOQq6unzfVZ6iVbgxBIxY=', 'JPG', FALSE, 1),

-- botineta-de-cuero-con-taco
((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM color WHERE nombre = 'Camel'), 'CATALOGO', 'https://media.istockphoto.com/id/610254954/photo/camel-color-high-heel-women-boot.jpg?s=612x612&w=0&k=20&c=0m0mZ6OTqqU73vSekyXpr8MEdvNrtkptEUGwHHKZntI=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/467818698/photo/ankle-boots-women.jpg?s=612x612&w=0&k=20&c=xFNVrcUY1VP_e017ejVVs5haJutklmfpWfwhTAhAIGM=', 'JPG', FALSE, 1),

-- camisa-oversize-a-cuadros
((SELECT id FROM producto WHERE slug = 'camisa-oversize-a-cuadros'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'https://media.istockphoto.com/id/1288173750/photo/studio-portrait-of-19-year-old-woman.jpg?s=612x612&w=0&k=20&c=ZoCyVbz8Vv0O8JM6E6kwlO8ltWyxkjZuNLls4to__1I=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'camisa-oversize-a-cuadros'), (SELECT id FROM color WHERE nombre = 'Rojo'), 'CATALOGO', 'https://media.istockphoto.com/id/629155610/photo/young-attractive-fashionable-woman-posing-in-red-plaid-shirt.jpg?s=612x612&w=0&k=20&c=xLt1JVeGIyrrtz4RyrtkGp1UtFh2SDbu0SBHGEtNk7Y=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'camisa-oversize-a-cuadros'), (SELECT id FROM color WHERE nombre = 'Verde Oliva'), 'CATALOGO', 'https://media.istockphoto.com/id/1297073014/photo/nature-girl.jpg?s=612x612&w=0&k=20&c=tz5kns-fgQNTCZRuVROQOKvDaCSaaJJDN_KEciovQGQ=', 'JPG', FALSE, 1),

-- campera-de-jean-oversize
((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM color WHERE nombre = 'Azul'), 'CATALOGO', 'https://media.istockphoto.com/id/1341462542/photo/smiling-young-woman-against-pink-background.jpg?s=612x612&w=0&k=20&c=P5iJJ7n7c3jE2pkYbsLotTQtcttx1KjUNwTIrwBALRs=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'https://media.istockphoto.com/id/89221040/photo/jean-jacket-on-a-hanger.jpg?s=612x612&w=0&k=20&c=Soy9gXDu9-KcCy5Mtz6FYIe3BiOWMhrG_0_TUKEP730=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/924415054/photo/gorgeous-slim-woman.jpg?s=612x612&w=0&k=20&c=NyaKCTez1XVZo9ad2Q-C-7AZGrOI8eFr_ApZiJ4ZhVI=', 'JPG', FALSE, 1),

-- campera-puffer-impermeable
((SELECT id FROM producto WHERE slug = 'campera-puffer-impermeable'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/1351262761/photo/young-woman-in-black-down-jacket.jpg', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'campera-puffer-impermeable'), (SELECT id FROM color WHERE nombre = 'Rojo'), 'CATALOGO', 'https://media.istockphoto.com/id/1603174670/photo/taking-in-my-surroundings.jpg?s=612x612&w=0&k=20&c=g5v0AClNQHL6l-Fg1roqICRtdEP1glj-qXOd8lMSD2Q=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'campera-puffer-impermeable'), (SELECT id FROM color WHERE nombre = 'Verde Oliva'), 'CATALOGO', 'https://media.istockphoto.com/id/2252908830/photo/a-joyful-woman-wearing-a-green-puffer-jacket-and-a-beanie-stands-in-a-park-with-colorful.jpg?s=612x612&w=0&k=20&c=CmiLBvTn-xVf--WQG5Fa8sriGSRt9jMqqtq30UswSJw=', 'JPG', FALSE, 1),

-- cardigan-de-punto-grueso
((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM color WHERE nombre = 'Beige'), 'CATALOGO', 'https://media.istockphoto.com/id/1355437820/photo/oversized-cardigan-isolated.jpg?s=612x612&w=0&k=20&c=-z_rQtRMiuDOH4tI3hrcWj1-hgp8BlBoBzHb-n3T3tA=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM color WHERE nombre = 'Camel'), 'CATALOGO', 'https://media.istockphoto.com/id/935282290/photo/knitted-cardigan-isolated.jpg?s=612x612&w=0&k=20&c=EisVXfkj1U7Av7N07X1uLsEnbYgtHj_doqGCHvcvEcg=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'https://media.istockphoto.com/id/931123484/photo/knitted-cardigan-isolated.jpg?s=612x612&w=0&k=20&c=MJbLQpCx_1Hz8o7RrRqSNUYDa4za1JGmxvz4SdoskdA=', 'JPG', FALSE, 1),

-- cartera-de-cuero-bandolera
((SELECT id FROM producto WHERE slug = 'cartera-de-cuero-bandolera'), (SELECT id FROM color WHERE nombre = 'Camel'), 'CATALOGO', 'https://media.istockphoto.com/id/2180698594/photo/shoulder-bag-isolated.jpg?s=612x612&w=0&k=20&c=c_YsOT7J530bU7sHdTNv1YZK66BEBSqwW7YIeoXDBp0=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'cartera-de-cuero-bandolera'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/675623820/photo/black-leather-crossbody-bag-isolated-on-white-background.jpg?s=612x612&w=0&k=20&c=w2ukakFzMo1-XvP71zyGZXxTjtZ6-hAILTe9PI1bqFA=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'cartera-de-cuero-bandolera'), (SELECT id FROM color WHERE nombre = 'Vino'), 'CATALOGO', 'https://media.istockphoto.com/id/2191210304/photo/burgundy-shoulder-leather-bag-isolated-on-white-background.jpg?s=612x612&w=0&k=20&c=XpN2FK6AjlKrVbCSp13U7IVISQkucBiHPh7RxNBTjLU=', 'JPG', FALSE, 1),

-- chalina-de-alpaca
((SELECT id FROM producto WHERE slug = 'chalina-de-alpaca'), (SELECT id FROM color WHERE nombre = 'Beige'), 'CATALOGO', 'https://media.istockphoto.com/id/933583822/photo/knitted-scarf-isolated.jpg?s=612x612&w=0&k=20&c=j4nOOR_myIg3gA3PpUR-68VuW1ZE7Mcx6mWBS1dt0ys=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'chalina-de-alpaca'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'https://media.istockphoto.com/id/478337104/photo/wool-scarf.jpg?s=612x612&w=0&k=20&c=1OZ0y4qQyzo_tb-jqGMJT2pyJhNweAKmGSjA5lfM-xg=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'chalina-de-alpaca'), (SELECT id FROM color WHERE nombre = 'Vino'), 'CATALOGO', 'https://media.istockphoto.com/id/810118350/photo/warm-burgundy-red-woven-winter-scarf-isolated-on-white.jpg?s=612x612&w=0&k=20&c=SBBLbowboIGHxKX0o7F3sIEIHx7pqYvLXceiHr7_WE4=', 'JPG', FALSE, 1),

-- cinturon-de-cuero-hebilla-dorada
((SELECT id FROM producto WHERE slug = 'cinturon-de-cuero-hebilla-dorada'), (SELECT id FROM color WHERE nombre = 'Camel'), 'CATALOGO', 'https://media.istockphoto.com/id/2150314444/photo/womens-brown-leather-belt-with-golden-metal-buckle-isolated-on-white.jpg?s=612x612&w=0&k=20&c=GHBpeTYZa0rnMsbTKgcEjN7PwjL2oQD_vFjLVfKsfyg=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'cinturon-de-cuero-hebilla-dorada'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/824820428/photo/black-classic-leather-belt-with-gold-buckle-isolated-on-white-background.jpg?s=612x612&w=0&k=20&c=Xgn1EA2Ok5MGBplz4bJvGS7fExjT8adl8dc-EQ8qkEo=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'cinturon-de-cuero-hebilla-dorada'), (SELECT id FROM color WHERE nombre = 'Vino'), 'CATALOGO', 'https://media.istockphoto.com/id/500401884/photo/belt.jpg?s=612x612&w=0&k=20&c=WLVAmNZ7NZIqTdesv2LdTyd_Xw49SjCXcob58A6h0t8=', 'JPG', FALSE, 1),

-- falda-de-jean-corta
((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM color WHERE nombre = 'Azul'), 'CATALOGO', 'https://media.istockphoto.com/id/1162100585/photo/denim-skirt-isolated.jpg?s=612x612&w=0&k=20&c=M2SogfP0BCvTL0McNxsjrWpW34-9HBDY8GsceHpLfng=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM color WHERE nombre = 'Blanco'), 'CATALOGO', 'https://media.istockphoto.com/id/501231182/photo/women-skirt.jpg?s=612x612&w=0&k=20&c=rDf0154zTW__ZndOVEMsPM35lJoijTCB-ysSyQxqK64=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/579247922/photo/skirt.jpg?s=612x612&w=0&k=20&c=zefgV27MORmIyKmSHkHErG9BQxpoK47qEnRVLZZmdDk=', 'JPG', FALSE, 1),

-- falda-lapiz-de-panio
((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'https://media.istockphoto.com/id/508698106/photo/gray-skirt.jpg?s=612x612&w=0&k=20&c=GbZ9I0HHlreKI89jRUheOxaDoCEeU3eLZQ_kGm7rwXs=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/487419508/photo/empty-black-skirt-pencil-isolated-on-white-background.jpg?s=612x612&w=0&k=20&c=y96D-d0-L9boZNcGM4s1fzmGc11jzeGMvH-RZwXLdEs=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM color WHERE nombre = 'Vino'), 'CATALOGO', 'https://media.istockphoto.com/id/1085185608/photo/skirt-on-clothes-rack.jpg?s=612x612&w=0&k=20&c=2CilIYMwTrKzDEDQ4HWEkk3BTjwxZs4Wmk8QMXImclU=', 'JPG', FALSE, 1),

-- falda-larga-de-gasa
((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), (SELECT id FROM color WHERE nombre = 'Beige'), 'CATALOGO', 'https://media.istockphoto.com/id/878884780/photo/skirt-on-clothes-rack.jpg?s=612x612&w=0&k=20&c=snP8Z4tEbxW5nPAZkbl8Ms2sBDBs_61LzvcdWSKOHOA=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), (SELECT id FROM color WHERE nombre = 'Blanco'), 'CATALOGO', 'https://media.istockphoto.com/id/1220832641/photo/white-long-skirt-isolated-on-white-background.jpg?s=612x612&w=0&k=20&c=kO7K4sQmGn5bgxyD4qaDrzCsBFyGcWEHv_rs6lKMiwY=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), (SELECT id FROM color WHERE nombre = 'Rosa Palo'), 'CATALOGO', 'https://media.istockphoto.com/id/1003022524/photo/pink-long-skirt-on-a-white-background-isolate-fashionable-concept.jpg?s=612x612&w=0&k=20&c=WSdO4JE5DwYzq_FQadGmql4Sm8N0cfUKmWzrLO1GLHI=', 'JPG', FALSE, 1),

-- falda-midi-plisada
((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM color WHERE nombre = 'Camel'), 'CATALOGO', 'https://media.istockphoto.com/id/932389948/photo/brown-pleated-midi-skirt-isolated-on-white.jpg?s=612x612&w=0&k=20&c=Icnfj8V4lOV8eNhuL7NZSw-_RP04PoQyTZ3nEweEX88=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/618035600/photo/pleated-skirt-isolated.jpg?s=612x612&w=is&k=20&c=KgQe4xv-XweMDQmtQs0mxv8Ys_Ov8x7HeK1kWV_5SMM=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM color WHERE nombre = 'Vino'), 'CATALOGO', 'https://media.istockphoto.com/id/829249518/photo/burgundy-pleated-midi-skirt-isolated-on-white.jpg?s=612x612&w=0&k=20&c=A_jdk4RiAWjZD2b6lih7Rm4N2pToe7cTO4v50geTJr0=', 'JPG', FALSE, 1),

-- gorro-y-guantes-de-lana
((SELECT id FROM producto WHERE slug = 'gorro-y-guantes-de-lana'), (SELECT id FROM color WHERE nombre = 'Beige'), 'CATALOGO', 'https://media.istockphoto.com/id/638565010/photo/warm-winter-knitted-clothes-hat-scarf-gloves.jpg?s=612x612&w=0&k=20&c=nJx-gNz6vM09l3wMjzk6atkJ_sWr4zq_lXOsItMRzNw=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'gorro-y-guantes-de-lana'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'https://media.istockphoto.com/id/538828719/photo/woolen-cap-and-gloves-isolated-on-white-background.jpg?s=612x612&w=0&k=20&c=FFWsihpT9fDgv5HRgyu71au2zjeUfztQ2Xgf6HEJDss=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'gorro-y-guantes-de-lana'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/1151131211/photo/directly-above-shot-of-knit-hat-and-gloves-on-white-background.jpg?s=612x612&w=0&k=20&c=eI68L2Sv2-GAdxjnxhnL1o9eIU99dQljxjrXxUAaRKc=', 'JPG', FALSE, 1),

-- jean-tiro-alto-skinny
((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM color WHERE nombre = 'Azul'), 'CATALOGO', 'https://media.istockphoto.com/id/653138072/photo/blue-skinny-high-waist-jeans-pants-isolated-on-white-background.jpg?s=612x612&w=0&k=20&c=cb647JMtBzNTo0_C5KAMCiNBktY7_eNSQw0nVZTmEhU=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'https://media.istockphoto.com/id/653746718/photo/grey-skinny-high-waist-jeans-pants-isolated-on-white-background.jpg?s=612x612&w=0&k=20&c=5vKPzzkxUJjUAKbUth563q1EDzJ1wVDD1FI5Uumifbw=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/688358214/photo/black-jeans-isolated-on-white.jpg?s=612x612&w=0&k=20&c=KYWvF6PgStVUEg21gHtov5s5L0Pahs1KrF3RPMKvark=', 'JPG', FALSE, 1),

-- jean-wide-leg
((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM color WHERE nombre = 'Azul'), 'CATALOGO', 'https://media.istockphoto.com/id/2234625462/photo/blue-wide-leg-womens-jeans-isolated-on-white-female-trousers.jpg?s=612x612&w=0&k=20&c=vFtgIxe_OMYdm2zHeMibSTLP3tMvP2nic5Y_n0N7doE=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM color WHERE nombre = 'Blanco'), 'CATALOGO', 'https://media.istockphoto.com/id/1144761359/photo/portrait-beautiful-young-girl-wearing-white-crop-top-wide-leg-pants-and-shirt-posing-gm1144761359-307894362.jpg?s=612x612&w=0&k=20&c=BjeiXb9ych6GdEKZkPMRCno_xuvCwbMK649ryLW2spI=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/2177201933/photo/womens-black-wide-elegant-pants.jpg?s=612x612&w=0&k=20&c=7yXad8TaWXYAeaYzgGGX8MzIy4fgZYxux2h5jEEydh4=', 'JPG', FALSE, 1),

-- legging-termico
((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM color WHERE nombre = 'Azul'), 'CATALOGO', 'https://media.istockphoto.com/id/1049281514/photo/blue-leggings-pants-isolated-on-white-background.jpg?s=612x612&w=0&k=20&c=5HyG2GrfuRTa8otHQNRFL43bchjwF5zm35KXe_YCAIc=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'https://media.istockphoto.com/id/1152625688/photo/attractive-woman-practicing-yoga-standing-in-sumo-squat-goddess.jpg?s=612x612&w=0&k=20&c=CQRJTCeGYUK5snRgkkrpBLDnwzC6aQgbAoMZgyCb9zM=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/1329161340/photo/black-leggings-pants-isolated-on-white.jpg?s=612x612&w=0&k=20&c=WMuYzmz6ArI_E9dJOJgCh1qSEKXRrrTCDqv1_xZwp6Y=', 'JPG', FALSE, 1),

-- lentes-de-sol-redondos
((SELECT id FROM producto WHERE slug = 'lentes-de-sol-redondos'), (SELECT id FROM color WHERE nombre = 'Camel'), 'CATALOGO', 'https://media.istockphoto.com/id/1295848914/photo/round-sunglasses.jpg?s=612x612&w=0&k=20&c=fFYkQN-X2Iu7b1FSzMmce9oIbIQRZ6o5E3UDcrXYwRE=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'lentes-de-sol-redondos'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/1257326448/photo/gold-frame-round-black-sunglasses-isolated-on-white.jpg?s=612x612&w=0&k=20&c=UiLGnn87tbdqYc4fuNQVEgFooCrUKi1arTyQ0H4nfk4=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'lentes-de-sol-redondos'), (SELECT id FROM color WHERE nombre = 'Vino'), 'CATALOGO', 'https://media.istockphoto.com/id/976766282/photo/dark-red-sunglasses-on-white-background.jpg?s=612x612&w=0&k=20&c=QdK9VuqzaV4jCWijmrlaacHpzb_-UL3wk_AVKRsBN_0=', 'JPG', FALSE, 1),

-- pantalon-de-vestir-sastrero
((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM color WHERE nombre = 'Azul'), 'CATALOGO', 'https://media.istockphoto.com/id/1355466581/photo/fashion-model-in-elegant-navy-blue-suit-is-posing-on-one-leg.jpg?s=612x612&w=0&k=20&c=9j5ujBGhwitYU3NCnAsEPi6T-1Z4cIZ_FCLI4bUwHGg=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'https://media.istockphoto.com/id/1332743987/photo/modern-womens-business-suit.jpg?s=612x612&w=0&k=20&c=5Yi09o-CRw6Y8xocAYmgQf1If2nwqF0v16LZwAqPvi4=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/1396133681/photo/female-model-wearing-beige-camisole-cotton-top-and-black-trousers-classic-and-simple-summer.jpg?s=612x612&w=0&k=20&c=YpYkglz2quZzFbEIywB--qSw-qeW4soa2NkqmIL4Y1E=', 'JPG', FALSE, 1),

-- pantalon-palazzo-de-lino
((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM color WHERE nombre = 'Beige'), 'CATALOGO', 'https://media.istockphoto.com/id/2243925516/photo/woman-in-beige-linen-outfit-carrying-a-large-woven-tote-bag.jpg?s=612x612&w=0&k=20&c=LXp50d5j9Iwa68ZP_LoBCwvgAp4JEfr7AYBb2GIqArg=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM color WHERE nombre = 'Blanco'), 'CATALOGO', 'https://media.istockphoto.com/id/1914588620/photo/outdoor-portrait-of-young-woman-in-white-linen-outfit-summer-holiday-fashion-style.jpg?s=612x612&w=0&k=20&c=f3IDJ-ssaJMWjkH9UpU08W2AfcTURyz6xbaHqDXQc-c=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM color WHERE nombre = 'Verde Oliva'), 'CATALOGO', 'https://media.istockphoto.com/id/2286076098/photo/young-woman-in-an-olive-pleated-jumpsuit-soft-feminine-portrait.jpg?s=612x612&w=0&k=20&c=LKGPw2ZuIuks35uCPubEgRJEobGRrxozu4ZJvxdzNCQ=', 'JPG', FALSE, 1),

-- sandalia-baja-de-cuero
((SELECT id FROM producto WHERE slug = 'sandalia-baja-de-cuero'), (SELECT id FROM color WHERE nombre = 'Beige'), 'CATALOGO', 'https://media.istockphoto.com/id/1678375756/photo/leather-beige-sandals-birkenstocks-on-white-background-top-view-flat-lay-unisex-gm1678375756-536469147.jpg?s=612x612&w=0&k=20&c=yIdTQeR6xFPBGWNAx2h1LXh29ncH76pWRKia7A-Rrxg=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'sandalia-baja-de-cuero'), (SELECT id FROM color WHERE nombre = 'Camel'), 'CATALOGO', 'https://media.istockphoto.com/id/1154293398/photo/womens-brown-leather-sandals-isolated-gm1154293398-313837408.jpg?s=612x612&w=0&k=20&c=OxcMzGdkj8zxkiJZznbf5VctHjQ33dw2EUaPfeeJQMg=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'sandalia-baja-de-cuero'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/1678375745/photo/leather-black-sandals-birkenstocks-on-white-background-top-view-flat-lay-unisex-summer-shoes.jpg?s=612x612&w=0&k=20&c=UlNHzgiTeWqKnRO8T7V1oM4N9ElgYos6HhbZhjtrkL0=', 'JPG', FALSE, 1),

-- sandalia-con-tiras-y-taco
((SELECT id FROM producto WHERE slug = 'sandalia-con-tiras-y-taco'), (SELECT id FROM color WHERE nombre = 'Camel'), 'CATALOGO', 'https://media.istockphoto.com/id/1138093867/photo/pair-of-beige-woman-is-high-heeled-sandals-fashion-beautiful-luxury-cream-high-heels-shoes.jpg?s=612x612&w=0&k=20&c=bHIXj72Xpqz6eyyATIWezpdfMbyu4_EndxtCZIGiUWA=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'sandalia-con-tiras-y-taco'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/174779564/photo/black-sandals.jpg?s=612x612&w=0&k=20&c=JMcgfI6XQ1TJ4WiTDv4hg9_94BjTpmmaKKgfx8LqWRc=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'sandalia-con-tiras-y-taco'), (SELECT id FROM color WHERE nombre = 'Rojo'), 'CATALOGO', 'https://media.istockphoto.com/id/904285996/photo/red-strappy-heeled-sandals.jpg?s=612x612&w=0&k=20&c=zchwoP4Pydnwtolkmfqx5rGm5k3x4FNaG32omAn0xZ8=', 'JPG', FALSE, 1),

-- sandalia-de-plataforma
((SELECT id FROM producto WHERE slug = 'sandalia-de-plataforma'), (SELECT id FROM color WHERE nombre = 'Blanco'), 'CATALOGO', 'https://media.istockphoto.com/id/896768166/photo/fashionable-white-platform-sandals.jpg?s=612x612&w=0&k=20&c=a_hrr3CTzxfdVPNG3zA7gkL1kGUe-JqNVfIfnlQRaps=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'sandalia-de-plataforma'), (SELECT id FROM color WHERE nombre = 'Camel'), 'CATALOGO', 'https://media.istockphoto.com/id/619412092/photo/new-pair-of-stylish-brown-high-heels-with-cork-soles.jpg?s=612x612&w=0&k=20&c=1SNiI6BVY2ggO7snhyt5QaJAeLRx-6JTqvi3jfoC8nI=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'sandalia-de-plataforma'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/1239163115/photo/fashionable-platform-sandals-isolated-on-white-background.jpg?s=612x612&w=0&k=20&c=MEQAM8rM9e5wFOvA4YIaUyQH75XPQ9cLuNECe4fDZCw=', 'JPG', FALSE, 1),

-- sombrero-de-ala-ancha
((SELECT id FROM producto WHERE slug = 'sombrero-de-ala-ancha'), (SELECT id FROM color WHERE nombre = 'Beige'), 'CATALOGO', 'https://media.istockphoto.com/id/1190018231/photo/woman-is-wearing-straw-hat-looking-on-the-beautiful-lake.jpg?s=612x612&w=0&k=20&c=c7UylG7IVNPKk8S0beEJEOFDOJv7cIVQnKt3JsJ8eNU=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'sombrero-de-ala-ancha'), (SELECT id FROM color WHERE nombre = 'Camel'), 'CATALOGO', 'https://media.istockphoto.com/id/1324720282/photo/woman-in-straw-hat-at-the-beach.jpg?s=612x612&w=0&k=20&c=amSvr4vkgugndCzkZbOB2GJTDf2QqHDMadSbstibljw=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'sombrero-de-ala-ancha'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/2172952518/photo/elegant-lady-in-black-dress-wearing-pearl-jewelry-necklace-and-wide-brim-hat-fashion-woman-in.jpg?s=612x612&w=0&k=20&c=Yc8_g2hzRawkRL_-rjPVgRFZwJQ-xFYVzslhCcJr2RM=', 'JPG', FALSE, 1),

-- tapado-de-lana-largo
((SELECT id FROM producto WHERE slug = 'tapado-de-lana-largo'), (SELECT id FROM color WHERE nombre = 'Camel'), 'CATALOGO', 'https://media.istockphoto.com/id/1299263206/photo/girl-in-brown-coat-and-beige-dress-is-spinning-in-the-street.jpg?s=612x612&w=0&k=20&c=m1xo1_Cmjd3A7ydQCtO81lAlfzZx7z1JrbN8X1u3Ckg=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'tapado-de-lana-largo'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/2053286866/photo/brunette-young-woman-wearing-black-coat.jpg?s=612x612&w=0&k=20&c=FkOMLnMhpcKnqs7sWDxmiGV_UcmrhcwbYx8cunjAlK4=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'tapado-de-lana-largo'), (SELECT id FROM color WHERE nombre = 'Vino'), 'CATALOGO', 'https://media.istockphoto.com/id/2184769090/photo/stylish-woman-in-burgundy-coat-walks-city-street-wearing-fashionable-clothing-white.jpg?s=612x612&w=0&k=20&c=W2QNgcTv-u9nkoWgD1UtAwy_6GrZISDPJAMfjr_Roks=', 'JPG', FALSE, 1),

-- top-de-tirantes-de-algodon
((SELECT id FROM producto WHERE slug = 'top-de-tirantes-de-algodon'), (SELECT id FROM color WHERE nombre = 'Blanco'), 'CATALOGO', 'https://media.istockphoto.com/id/1245073333/photo/white-tank-top-isolated-on-white-background-plain-hollow-female-tank-top-shirt-isolated-on.jpg?s=612x612&w=0&k=20&c=lTMzlKG7OnRXcCGa-zUKmE3pnN8rLNwIhs5VEnIWcVc=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'top-de-tirantes-de-algodon'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/508456882/photo/black-tank-top.jpg?s=612x612&w=0&k=20&c=c2G-v_XawEE4iexsfOwpsNG9yDP7GWT51bDpcb8IQHw=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'top-de-tirantes-de-algodon'), (SELECT id FROM color WHERE nombre = 'Rosa Palo'), 'CATALOGO', 'https://media.istockphoto.com/id/912212344/photo/light-pink-women-summer-blank-sleeveless-t-shirt-with-flounce-isolated-on-white.jpg?s=612x612&w=0&k=20&c=FnuOcl3Pu3I9e6PJYMi_UcJevHC-mSJO4QqT8SA-hc4=', 'JPG', FALSE, 1),

-- vestido-camisero-de-lino
((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM color WHERE nombre = 'Azul'), 'CATALOGO', 'https://media.istockphoto.com/id/2156880017/photo/cool-woman-in-a-blue-linen-shirt.jpg?s=612x612&w=0&k=20&c=lO7P8iLXKPwsqfprLpKi5p6uhWAH2wd3sey81vBKNL8=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM color WHERE nombre = 'Beige'), 'CATALOGO', 'https://media.istockphoto.com/id/934089734/photo/young-eastern-woman-in-luxury-beige-dress.jpg?s=612x612&w=0&k=20&c=WkZcIUhKVN-33s9PfCAS2rK2LZnsMuhQTl4t_H8ZK4s=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM color WHERE nombre = 'Blanco'), 'CATALOGO', 'https://media.istockphoto.com/id/2158072551/photo/woman-in-white-linen-dress-minimal-fashion.jpg?s=612x612&w=0&k=20&c=o9hKFe5IleetVAxJvOcIwPnDW_L7tpyGCfBvG1lI9_A=', 'JPG', FALSE, 1),

-- vestido-de-punto-manga-larga
((SELECT id FROM producto WHERE slug = 'vestido-de-punto-manga-larga'), (SELECT id FROM color WHERE nombre = 'Camel'), 'CATALOGO', 'https://media.istockphoto.com/id/2208779697/photo/serie-of-studio-photos-of-female-model-in-knitted-beige-midi-dress-autumn-winter-fashion.jpg?s=612x612&w=is&k=20&c=bHC1GkmJAqZHnRIjbwCvKgR5x6pxQTDZ2gf0WDhjDw8=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'vestido-de-punto-manga-larga'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'https://media.istockphoto.com/id/2131326536/photo/serie-of-studio-photos-of-female-model-in-knitted-grey-set-autumn-winter-fashion-collection.jpg?s=612x612&w=is&k=20&c=67bzuI-ccdl74M0R42YrzteqTbwr_xV_qStUb73OtZQ=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'vestido-de-punto-manga-larga'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/858244638/photo/studio-shot-of-young-beautiful-woman-wearing-black-long-sleeved-dress-against-black-background.jpg?s=612x612&w=0&k=20&c=CGZKSfCnuEySiaHVEY2vh70I71a_oPaANdH5cvewg4Y=', 'JPG', FALSE, 1),

-- vestido-floral-manga-corta
((SELECT id FROM producto WHERE slug = 'vestido-floral-manga-corta'), (SELECT id FROM color WHERE nombre = 'Beige'), 'CATALOGO', 'https://media.istockphoto.com/id/658122144/photo/woman-stylish-summer-clothing-on-a-white-background.jpg?s=612x612&w=0&k=20&c=2KZu0h4t5GJC440qongBqBi2zDIQpooMDmDRHjzvjUk=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'vestido-floral-manga-corta'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/1243117312/photo/fashionable-mini-dress-isolated-on-white-background.jpg?s=612x612&w=0&k=20&c=V-eUTckAB7K9Fa4yBURJRbJVBM8zFkQjHCDcDoiqSFE=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'vestido-floral-manga-corta'), (SELECT id FROM color WHERE nombre = 'Rojo'), 'CATALOGO', 'https://media.istockphoto.com/id/518176602/photo/sundress.jpg?s=612x612&w=0&k=20&c=xXMweuPEwnFGNZTpav69QTz-S2CMyTUEaAks75ut05I=', 'JPG', FALSE, 1),

-- vestido-midi-plisado
((SELECT id FROM producto WHERE slug = 'vestido-midi-plisado'), (SELECT id FROM color WHERE nombre = 'Camel'), 'CATALOGO', 'https://media.istockphoto.com/id/1701785928/photo/serie-of-studio-photos-of-young-female-model-in-beige-silk-satin-wrap-midi-dress.jpg?s=612x612&w=0&k=20&c=LhvwtygGsWsnTkrE9px2pDi5LvtUw0Vz8w5RNF8muU8=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'vestido-midi-plisado'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/2248761645/photo/serie-of-studio-photos-of-young-female-model-in-black-v-neck-midi-dress.jpg?s=612x612&w=0&k=20&c=0HcbXFjg2yDh8Z15wYMNyWRiIOwuyFXodjdn5xgoJ6c=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'vestido-midi-plisado'), (SELECT id FROM color WHERE nombre = 'Vino'), 'CATALOGO', 'https://media.istockphoto.com/id/1336678976/photo/maroon-dress-isolated-in-white-background-invisible-mannequin.jpg?s=612x612&w=0&k=20&c=T_XK1hIsNUNoTwnehijP4Ok9aSXGDbT4Er2Y4OekIc0=', 'JPG', FALSE, 1),

-- zapatilla-urbana-blanca
((SELECT id FROM producto WHERE slug = 'zapatilla-urbana-blanca'), (SELECT id FROM color WHERE nombre = 'Blanco'), 'CATALOGO', 'https://media.istockphoto.com/id/1417090656/photo/white-leather-sneaker.jpg?s=612x612&w=0&k=20&c=mF0ZLSz0DKnuVgR1KEPhPnGV4xTvWB2R_zsWJIKoko0=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'zapatilla-urbana-blanca'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'https://media.istockphoto.com/id/982533598/photo/sneakers-isolated-on-white-background-with-clipping-path.jpg?s=612x612&w=0&k=20&c=Zmdz82LqSxVTbWoOhb7HO3u0zjkb1HehbVNoFIGHyt8=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'zapatilla-urbana-blanca'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/1358001285/photo/new-black-sneakers-isolated-on-white-background.jpg?s=612x612&w=0&k=20&c=wm70388salMk-oJJ_T1Nir9uEpTatBkwISS7MmBkc80=', 'JPG', FALSE, 1),

-- zapato-stiletto-de-charol
((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/1002026996/photo/black-high-heel-female-shoes.jpg?s=612x612&w=0&k=20&c=IF6XWbW8wnYSrH3P1swqM36L2Yofab6Jrqo8xDk5Kxs=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM color WHERE nombre = 'Rojo'), 'CATALOGO', 'https://media.istockphoto.com/id/155370078/photo/sexy-shiny-red-patent-leather-high-heels-stilettos-shoes.jpg?s=612x612&w=0&k=20&c=PxpXWAxJCUsfYbdEtDX5cmbcr1MuiW0IZ40ptLESENE=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM color WHERE nombre = 'Vino'), 'CATALOGO', 'https://media.istockphoto.com/id/2255390727/photo/luxury-burgundy-patent-leather-slingback-high-heel-shoes-isolated-on-white-background.jpg?s=612x612&w=0&k=20&c=0i50AmxHR-YrTGqvNG3Nahr-I1c07-lHRg5PqT91GkE=', 'JPG', FALSE, 1)
;

-- ---------------------------------------------------------------------
-- INVENTARIO: cada variante en cada sucursal, repartido SEGUN EL CLIMA
--
-- Las tres sucursales estan en tres climas distintos, asi que la misma
-- coleccion no se distribuye en partes iguales. Es la razon por la que el
-- stock vive por sucursal (tabla inventario) y no en un unico saldo global:
--
--   SANTA_CRUZ  llanura, calido todo el anio -> pesa Primavera-Verano
--   LA_PAZ      altura, frio todo el anio    -> pesa Otonio-Invierno
--   COCHABAMBA  valle templado               -> surtido equilibrado
--
-- Las prendas atemporales (sin temporada_id, como el jean) rotan parejo en
-- las tres. El stock_minimo acompania: lo que casi no rota en una ciudad se
-- repone recien cuando baja a 1, no a 5.
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
        ELSE 10 + random() * 8   -- prendas atemporales, en cualquier sucursal
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

-- Liquidacion de la temporada que acaba de cerrar: es como el rubro saca el
-- abrigo que quedo en Santa Cruz y Cochabamba cuando entra el calor.
INSERT INTO promocion (nombre, codigo_cupon, tipo, valor, alcance, temporada_id, fecha_inicio, fecha_fin)
VALUES (
    'Liquidacion invierno 30%', 'INVIERNO30', 'PORCENTAJE', 30, 'TEMPORADA',
    (SELECT id FROM temporada WHERE nombre = 'Otonio-Invierno 2026'),
    '2026-09-01', '2026-10-31'
);

-- ---------------------------------------------------------------------
-- PARAMETRIA
-- ---------------------------------------------------------------------

INSERT INTO configuracion (clave, valor, descripcion) VALUES
    ('reserva_horas_vigencia', '4', 'Horas antes de que una reserva pendiente expire automaticamente'),
    ('empresa_razon_social',   'FashionStore Bolivia S.R.L.', 'Razon social para comprobantes'),
    ('empresa_nit',            '1234567890', 'NIT para comprobantes');
