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
-- IMAGENES DE CATALOGO: una foto real (packshot) por producto. Los 40 archivos
-- viven versionados en backend/app/media_semilla/catalogo/<slug>.jpg -- app/main.py
-- los copia a MEDIA_DIR en cada arranque del backend, asi que existen en disco
-- antes de este INSERT. Reemplaza tanto los hotlinks externos como los
-- placeholders de picsum.photos que habia antes (PENDIENTES.txt 2.9): esos
-- links de terceros dejaban de cargar sin aviso, y encima un
-- `docker compose down -v` se llevaba puesto cualquier foto real que se
-- hubiera subido a mano por el panel de CU10, porque esa subida vive en el
-- volumen Docker `backend_media` y nunca estuvo en este archivo.
--
-- color_id de la fila es_principal: para 26 de los 40 productos, la foto real
-- de arriba muestra con claridad uno de los colores que el producto ya tiene
-- como variante -- ahi se carga ese color_id, para que producto-detalle.page.ts
-- (`colorDeCatalogo`) preseleccione ese color en vez del primero alfabetico.
-- Los otros 14 quedan con color_id NULL a proposito porque la foto no
-- corresponde a ninguna variante (blanca/marfil/estampada/de un color que el
-- producto no tiene) o es ambigua entre dos tonos parecidos -- forzar un color
-- ahi haria que el circulito del selector no coincida con la foto.
-- ---------------------------------------------------------------------

INSERT INTO producto_imagen (producto_id, color_id, uso, url, formato, es_principal, orden)
SELECT p.id, c.id, 'CATALOGO', 'http://localhost:8081/media/catalogo/' || p.slug || '.jpg', 'JPG', TRUE, 0
FROM producto p
LEFT JOIN (VALUES
    ('tapado-de-lana-largo', 'Camel'),
    ('campera-de-jean-oversize', 'Azul'),
    ('cardigan-de-punto-grueso', 'Beige'),
    ('chalina-de-alpaca', 'Gris'),
    ('cartera-de-cuero-bandolera', 'Camel'),
    ('sombrero-de-ala-ancha', 'Beige'),
    ('cinturon-de-cuero-hebilla-dorada', 'Negro'),
    ('gorro-y-guantes-de-lana', 'Gris'),
    ('lentes-de-sol-redondos', 'Negro'),
    ('blusa-de-lino-manga-corta', 'Blanco'),
    ('top-de-tirantes-de-algodon', 'Negro'),
    ('blusa-cropped-con-volados', 'Blanco'),
    ('borcego-negro-con-cordones', 'Negro'),
    ('falda-de-jean-corta', 'Azul'),
    ('falda-lapiz-de-panio', 'Negro'),
    ('jean-tiro-alto-skinny', 'Azul'),
    ('pantalon-palazzo-de-lino', 'Beige'),
    ('pantalon-de-vestir-sastrero', 'Negro'),
    ('jean-wide-leg', 'Blanco'),
    ('legging-termico', 'Negro'),
    ('sandalia-de-plataforma', 'Blanco'),
    ('sandalia-baja-de-cuero', 'Camel'),
    ('vestido-negro-de-fiesta', 'Negro'),
    ('zapato-stiletto-de-charol', 'Negro'),
    ('ballerina-de-cuero', 'Beige'),
    ('zapatilla-urbana-blanca', 'Blanco')
) AS m(slug, color_nombre) ON m.slug = p.slug
LEFT JOIN color c ON c.nombre = m.color_nombre;

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
((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM color WHERE nombre = 'Azul'), 'CATALOGO', 'http://localhost:8081/media/variantes/blazer-entallado-azul.jpg', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM color WHERE nombre = 'Beige'), 'CATALOGO', 'http://localhost:8081/media/variantes/blazer-entallado-beige.jpg', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'http://localhost:8081/media/variantes/blazer-entallado-negro.jpg', 'JPG', FALSE, 1),

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
((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM color WHERE nombre = 'Camel'), 'CATALOGO', 'http://localhost:8081/media/variantes/bota-cania-alta-de-gamuza-camel.jpg', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'https://media.istockphoto.com/id/497025594/photo/womens-gray-suede-boots-with-low-heels.jpg?s=612x612&w=0&k=20&c=WBiGb6JD39Mi-pu7bFNVVl9qB8WgQEHWmPganr0IG3I=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'http://localhost:8081/media/variantes/bota-cania-alta-de-gamuza-negro.jpg', 'JPG', FALSE, 1),

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
((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'http://localhost:8081/media/variantes/campera-de-jean-oversize-negro.jpg', 'JPG', FALSE, 1),

-- campera-puffer-impermeable
((SELECT id FROM producto WHERE slug = 'campera-puffer-impermeable'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'http://localhost:8081/media/variantes/campera-puffer-impermeable-negro.jpg', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'campera-puffer-impermeable'), (SELECT id FROM color WHERE nombre = 'Rojo'), 'CATALOGO', 'https://media.istockphoto.com/id/1603174670/photo/taking-in-my-surroundings.jpg?s=612x612&w=0&k=20&c=g5v0AClNQHL6l-Fg1roqICRtdEP1glj-qXOd8lMSD2Q=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'campera-puffer-impermeable'), (SELECT id FROM color WHERE nombre = 'Verde Oliva'), 'CATALOGO', 'http://localhost:8081/media/variantes/campera-puffer-impermeable-verde-oliva.jpg', 'JPG', FALSE, 1),

-- cardigan-de-punto-grueso
((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM color WHERE nombre = 'Beige'), 'CATALOGO', 'https://media.istockphoto.com/id/1355437820/photo/oversized-cardigan-isolated.jpg?s=612x612&w=0&k=20&c=-z_rQtRMiuDOH4tI3hrcWj1-hgp8BlBoBzHb-n3T3tA=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM color WHERE nombre = 'Camel'), 'CATALOGO', 'https://media.istockphoto.com/id/935282290/photo/knitted-cardigan-isolated.jpg?s=612x612&w=0&k=20&c=EisVXfkj1U7Av7N07X1uLsEnbYgtHj_doqGCHvcvEcg=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'http://localhost:8081/media/variantes/cardigan-de-punto-grueso-gris.jpg', 'JPG', FALSE, 1),

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
((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'http://localhost:8081/media/variantes/falda-lapiz-de-panio-gris.jpg', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/487419508/photo/empty-black-skirt-pencil-isolated-on-white-background.jpg?s=612x612&w=0&k=20&c=y96D-d0-L9boZNcGM4s1fzmGc11jzeGMvH-RZwXLdEs=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM color WHERE nombre = 'Vino'), 'CATALOGO', 'http://localhost:8081/media/variantes/falda-lapiz-de-panio-vino.jpg', 'JPG', FALSE, 1),

-- falda-larga-de-gasa
((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), (SELECT id FROM color WHERE nombre = 'Beige'), 'CATALOGO', 'http://localhost:8081/media/variantes/falda-larga-de-gasa-beige.jpg', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), (SELECT id FROM color WHERE nombre = 'Blanco'), 'CATALOGO', 'https://media.istockphoto.com/id/1220832641/photo/white-long-skirt-isolated-on-white-background.jpg?s=612x612&w=0&k=20&c=kO7K4sQmGn5bgxyD4qaDrzCsBFyGcWEHv_rs6lKMiwY=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), (SELECT id FROM color WHERE nombre = 'Rosa Palo'), 'CATALOGO', 'https://media.istockphoto.com/id/1003022524/photo/pink-long-skirt-on-a-white-background-isolate-fashionable-concept.jpg?s=612x612&w=0&k=20&c=WSdO4JE5DwYzq_FQadGmql4Sm8N0cfUKmWzrLO1GLHI=', 'JPG', FALSE, 1),

-- falda-midi-plisada
((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM color WHERE nombre = 'Camel'), 'CATALOGO', 'https://media.istockphoto.com/id/932389948/photo/brown-pleated-midi-skirt-isolated-on-white.jpg?s=612x612&w=0&k=20&c=Icnfj8V4lOV8eNhuL7NZSw-_RP04PoQyTZ3nEweEX88=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'http://localhost:8081/media/variantes/falda-midi-plisada-negro.jpg', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM color WHERE nombre = 'Vino'), 'CATALOGO', 'http://localhost:8081/media/variantes/falda-midi-plisada-vino.jpg', 'JPG', FALSE, 1),

-- gorro-y-guantes-de-lana
((SELECT id FROM producto WHERE slug = 'gorro-y-guantes-de-lana'), (SELECT id FROM color WHERE nombre = 'Beige'), 'CATALOGO', 'https://media.istockphoto.com/id/638565010/photo/warm-winter-knitted-clothes-hat-scarf-gloves.jpg?s=612x612&w=0&k=20&c=nJx-gNz6vM09l3wMjzk6atkJ_sWr4zq_lXOsItMRzNw=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'gorro-y-guantes-de-lana'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'https://media.istockphoto.com/id/538828719/photo/woolen-cap-and-gloves-isolated-on-white-background.jpg?s=612x612&w=0&k=20&c=FFWsihpT9fDgv5HRgyu71au2zjeUfztQ2Xgf6HEJDss=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'gorro-y-guantes-de-lana'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/1151131211/photo/directly-above-shot-of-knit-hat-and-gloves-on-white-background.jpg?s=612x612&w=0&k=20&c=eI68L2Sv2-GAdxjnxhnL1o9eIU99dQljxjrXxUAaRKc=', 'JPG', FALSE, 1),

-- jean-tiro-alto-skinny
((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM color WHERE nombre = 'Azul'), 'CATALOGO', 'https://media.istockphoto.com/id/653138072/photo/blue-skinny-high-waist-jeans-pants-isolated-on-white-background.jpg?s=612x612&w=0&k=20&c=cb647JMtBzNTo0_C5KAMCiNBktY7_eNSQw0nVZTmEhU=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'https://media.istockphoto.com/id/653746718/photo/grey-skinny-high-waist-jeans-pants-isolated-on-white-background.jpg?s=612x612&w=0&k=20&c=5vKPzzkxUJjUAKbUth563q1EDzJ1wVDD1FI5Uumifbw=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/688358214/photo/black-jeans-isolated-on-white.jpg?s=612x612&w=0&k=20&c=KYWvF6PgStVUEg21gHtov5s5L0Pahs1KrF3RPMKvark=', 'JPG', FALSE, 1),

-- jean-wide-leg
((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM color WHERE nombre = 'Azul'), 'CATALOGO', 'http://localhost:8081/media/variantes/jean-wide-leg-azul.jpg', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM color WHERE nombre = 'Blanco'), 'CATALOGO', 'https://media.istockphoto.com/id/1144761359/photo/portrait-beautiful-young-girl-wearing-white-crop-top-wide-leg-pants-and-shirt-posing-gm1144761359-307894362.jpg?s=612x612&w=0&k=20&c=BjeiXb9ych6GdEKZkPMRCno_xuvCwbMK649ryLW2spI=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'http://localhost:8081/media/variantes/jean-wide-leg-negro.jpg', 'JPG', FALSE, 1),

-- legging-termico
((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM color WHERE nombre = 'Azul'), 'CATALOGO', 'https://media.istockphoto.com/id/1049281514/photo/blue-leggings-pants-isolated-on-white-background.jpg?s=612x612&w=0&k=20&c=5HyG2GrfuRTa8otHQNRFL43bchjwF5zm35KXe_YCAIc=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'http://localhost:8081/media/variantes/legging-termico-gris.jpg', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/1329161340/photo/black-leggings-pants-isolated-on-white.jpg?s=612x612&w=0&k=20&c=WMuYzmz6ArI_E9dJOJgCh1qSEKXRrrTCDqv1_xZwp6Y=', 'JPG', FALSE, 1),

-- lentes-de-sol-redondos
((SELECT id FROM producto WHERE slug = 'lentes-de-sol-redondos'), (SELECT id FROM color WHERE nombre = 'Camel'), 'CATALOGO', 'https://media.istockphoto.com/id/1295848914/photo/round-sunglasses.jpg?s=612x612&w=0&k=20&c=fFYkQN-X2Iu7b1FSzMmce9oIbIQRZ6o5E3UDcrXYwRE=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'lentes-de-sol-redondos'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/1257326448/photo/gold-frame-round-black-sunglasses-isolated-on-white.jpg?s=612x612&w=0&k=20&c=UiLGnn87tbdqYc4fuNQVEgFooCrUKi1arTyQ0H4nfk4=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'lentes-de-sol-redondos'), (SELECT id FROM color WHERE nombre = 'Vino'), 'CATALOGO', 'https://media.istockphoto.com/id/976766282/photo/dark-red-sunglasses-on-white-background.jpg?s=612x612&w=0&k=20&c=QdK9VuqzaV4jCWijmrlaacHpzb_-UL3wk_AVKRsBN_0=', 'JPG', FALSE, 1),

-- pantalon-de-vestir-sastrero
((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM color WHERE nombre = 'Azul'), 'CATALOGO', 'http://localhost:8081/media/variantes/pantalon-de-vestir-sastrero-azul.jpg', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'http://localhost:8081/media/variantes/pantalon-de-vestir-sastrero-gris.jpg', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'https://media.istockphoto.com/id/1396133681/photo/female-model-wearing-beige-camisole-cotton-top-and-black-trousers-classic-and-simple-summer.jpg?s=612x612&w=0&k=20&c=YpYkglz2quZzFbEIywB--qSw-qeW4soa2NkqmIL4Y1E=', 'JPG', FALSE, 1),

-- pantalon-palazzo-de-lino
((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM color WHERE nombre = 'Beige'), 'CATALOGO', 'https://media.istockphoto.com/id/2243925516/photo/woman-in-beige-linen-outfit-carrying-a-large-woven-tote-bag.jpg?s=612x612&w=0&k=20&c=LXp50d5j9Iwa68ZP_LoBCwvgAp4JEfr7AYBb2GIqArg=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM color WHERE nombre = 'Blanco'), 'CATALOGO', 'https://media.istockphoto.com/id/1914588620/photo/outdoor-portrait-of-young-woman-in-white-linen-outfit-summer-holiday-fashion-style.jpg?s=612x612&w=0&k=20&c=f3IDJ-ssaJMWjkH9UpU08W2AfcTURyz6xbaHqDXQc-c=', 'JPG', FALSE, 1),
((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM color WHERE nombre = 'Verde Oliva'), 'CATALOGO', 'http://localhost:8081/media/variantes/pantalon-palazzo-de-lino-verde-oliva.jpg', 'JPG', FALSE, 1),

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
-- VARIANTES DE COLOR ADICIONALES (backend/3x4/variantes, ver PENDIENTES.txt):
-- fotos por color generadas para (casi) todos los productos, con nombres de
-- color mas especificos que los 10 fijos originales (p.ej. 'Azul Marino',
-- 'Borgona Profundo'). Se agregan como colores nuevos en `color` salvo que el
-- nombre coincida exactamente con uno ya existente (Azul, Beige, Blanco, Gris,
-- Negro, Rojo, Verde Oliva). No crean variantes de producto/stock nuevas -- son
-- solo fotos de catalogo (uso='CATALOGO', es_principal=FALSE); no importa que
-- el color de la foto no tenga stock real, es demostrativo. Los archivos viven
-- en backend/app/media_semilla/variantes, igual que el resto de /media/variantes.
-- ---------------------------------------------------------------------

INSERT INTO color (nombre, codigo_hex) VALUES
    ('Amanecer Suave', '#F2C9A1'),
    ('Azul Lavado Claro', '#7A9CC6'),
    ('Azul Marino', '#1B2A4A'),
    ('Azul Marino Elegante', '#17264A'),
    ('Azul Marino Intenso', '#132140'),
    ('Azul Marino Profundo', '#0E1B36'),
    ('Azul Pizarra', '#3B4A5A'),
    ('Azul y Blanco', '#3B5998'),
    ('Azul Índigo Clásico', '#283593'),
    ('Beige Camel', '#CBB088'),
    ('Blanco Óptico', '#FDFEFF'),
    ('Borgoña', '#6E0B24'),
    ('Borgoña Intenso', '#5A0E1F'),
    ('Borgoña Profundo', '#4E0A1B'),
    ('Burdeos', '#6D071A'),
    ('Café', '#6F4E37'),
    ('Café Miel', '#8A5A2B'),
    ('Camel Beige', '#C8A97E'),
    ('Camel Clásico', '#C19A6B'),
    ('Camello', '#C19A6B'),
    ('Caqui Oliva', '#6B6E3A'),
    ('Celeste Pastel', '#AEDFF7'),
    ('Cielo Monocromático', '#A9B7C6'),
    ('Ciruela Oscuro', '#4B2E48'),
    ('Crema', '#F5EEDC'),
    ('Crepúsculo Dramático', '#4B3B5A'),
    ('Cálido', '#C97C4A'),
    ('Cálido Oliva', '#77812F'),
    ('Dorado', '#D4AF37'),
    ('Frío', '#7B93A8'),
    ('Greige', '#B7AC9C'),
    ('Gris Antracita', '#383B3F'),
    ('Gris Carbón', '#3A3B3C'),
    ('Gris Jaspeado', '#8A8D91'),
    ('Lavado Claro Ácido', '#B9D46A'),
    ('Lavado Ligero', '#A9C4DE'),
    ('Lavado Medio', '#6E93B7'),
    ('Lavado Oscuro', '#33496B'),
    ('Lavanda Pastel', '#C9B6E4'),
    ('Marfil', '#FFF8E7'),
    ('Marino', '#1B2A4A'),
    ('Marino y Amarillo', '#26428B'),
    ('Marrón', '#7B4B2A'),
    ('Marrón Chocolate', '#4A2C13'),
    ('Mate Carbón', '#2B2B2B'),
    ('Miel', '#C68E3F'),
    ('Natural', '#E8DFC8'),
    ('Negro Carbón', '#1C1C1C'),
    ('Negro Clásico', '#0A0A0A'),
    ('Negro Elegante', '#101010'),
    ('Negro Intenso', '#070707'),
    ('Negro Plateado', '#3A3A3D'),
    ('Negro Sólido', '#050505'),
    ('Neutro', '#B9AF9E'),
    ('Nude Clásico', '#E2C1A6'),
    ('Plata', '#C0C0C0'),
    ('Rojo Rubí', '#9B111E'),
    ('Rojo y Blanco', '#C8102E'),
    ('Rosa', '#F5A9C0'),
    ('Rosa Chicle', '#FF77A9'),
    ('Rosa Claro', '#F4C2C2'),
    ('Rosa Empolvado', '#DFB8B0'),
    ('Taupe', '#8B7D6B'),
    ('Tweed Gris', '#8D8A82'),
    ('Verde Bosque', '#1F4B3F'),
    ('Verde Bosque y Beige', '#3B5249'),
    ('Verde Esmeralda', '#0F5132'),
    ('Verde Sabio', '#A9B58C'),
    ('Verde Salvia', '#9CAF88'),
    ('Índigo Clásico', '#2C3E77'),
    ('Índigo Oscuro', '#1F2A57')
ON CONFLICT (nombre) DO NOTHING;

-- Reemplaza la foto "por color" (es_principal=FALSE) de los pares
-- producto+color que ahora tienen una foto generada especifica; la foto
-- principal (es_principal=TRUE) de cada producto queda intacta.
DELETE FROM producto_imagen
WHERE es_principal = FALSE
  AND (producto_id, color_id) IN (
    ((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM color WHERE nombre = 'Negro')),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM color WHERE nombre = 'Negro')),
    ((SELECT id FROM producto WHERE slug = 'campera-puffer-impermeable'), (SELECT id FROM color WHERE nombre = 'Negro')),
    ((SELECT id FROM producto WHERE slug = 'campera-puffer-impermeable'), (SELECT id FROM color WHERE nombre = 'Verde Oliva')),
    ((SELECT id FROM producto WHERE slug = 'cartera-de-cuero-bandolera'), (SELECT id FROM color WHERE nombre = 'Negro')),
    ((SELECT id FROM producto WHERE slug = 'chalina-de-alpaca'), (SELECT id FROM color WHERE nombre = 'Beige')),
    ((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM color WHERE nombre = 'Negro')),
    ((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM color WHERE nombre = 'Negro')),
    ((SELECT id FROM producto WHERE slug = 'gorro-y-guantes-de-lana'), (SELECT id FROM color WHERE nombre = 'Beige')),
    ((SELECT id FROM producto WHERE slug = 'gorro-y-guantes-de-lana'), (SELECT id FROM color WHERE nombre = 'Gris')),
    ((SELECT id FROM producto WHERE slug = 'gorro-y-guantes-de-lana'), (SELECT id FROM color WHERE nombre = 'Negro')),
    ((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM color WHERE nombre = 'Negro')),
    ((SELECT id FROM producto WHERE slug = 'sandalia-con-tiras-y-taco'), (SELECT id FROM color WHERE nombre = 'Negro')),
    ((SELECT id FROM producto WHERE slug = 'sandalia-con-tiras-y-taco'), (SELECT id FROM color WHERE nombre = 'Rojo')),
    ((SELECT id FROM producto WHERE slug = 'top-de-tirantes-de-algodon'), (SELECT id FROM color WHERE nombre = 'Blanco')),
    ((SELECT id FROM producto WHERE slug = 'zapatilla-urbana-blanca'), (SELECT id FROM color WHERE nombre = 'Blanco')),
    ((SELECT id FROM producto WHERE slug = 'zapatilla-urbana-blanca'), (SELECT id FROM color WHERE nombre = 'Gris')),
    ((SELECT id FROM producto WHERE slug = 'zapatilla-urbana-blanca'), (SELECT id FROM color WHERE nombre = 'Negro')),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM color WHERE nombre = 'Negro'))
  );

INSERT INTO producto_imagen (producto_id, color_id, uso, url, formato, es_principal, orden) VALUES
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM color WHERE nombre = 'Azul Marino'), 'CATALOGO', 'http://localhost:8081/media/variantes/ballerina-de-cuero-azul-marino.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM color WHERE nombre = 'Café'), 'CATALOGO', 'http://localhost:8081/media/variantes/ballerina-de-cuero-cafe.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM color WHERE nombre = 'Marfil'), 'CATALOGO', 'http://localhost:8081/media/variantes/ballerina-de-cuero-marfil.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM color WHERE nombre = 'Miel'), 'CATALOGO', 'http://localhost:8081/media/variantes/ballerina-de-cuero-miel.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM color WHERE nombre = 'Verde Oliva'), 'CATALOGO', 'http://localhost:8081/media/variantes/ballerina-de-cuero-verde-oliva.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM color WHERE nombre = 'Azul Marino'), 'CATALOGO', 'http://localhost:8081/media/variantes/blazer-entallado-azul-marino.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM color WHERE nombre = 'Camel Beige'), 'CATALOGO', 'http://localhost:8081/media/variantes/blazer-entallado-camel-beige.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'http://localhost:8081/media/variantes/blazer-entallado-negro.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM color WHERE nombre = 'Verde Salvia'), 'CATALOGO', 'http://localhost:8081/media/variantes/blazer-entallado-verde-salvia.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'blusa-cropped-con-volados'), (SELECT id FROM color WHERE nombre = 'Azul Marino'), 'CATALOGO', 'http://localhost:8081/media/variantes/blusa-cropped-con-volados-azul-marino.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'blusa-cropped-con-volados'), (SELECT id FROM color WHERE nombre = 'Lavanda Pastel'), 'CATALOGO', 'http://localhost:8081/media/variantes/blusa-cropped-con-volados-lavanda-pastel.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'blusa-cropped-con-volados'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'http://localhost:8081/media/variantes/blusa-cropped-con-volados-negro.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-lino-manga-corta'), (SELECT id FROM color WHERE nombre = 'Azul Marino'), 'CATALOGO', 'http://localhost:8081/media/variantes/blusa-de-lino-manga-corta-azul-marino.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-lino-manga-corta'), (SELECT id FROM color WHERE nombre = 'Celeste Pastel'), 'CATALOGO', 'http://localhost:8081/media/variantes/blusa-de-lino-manga-corta-celeste-pastel.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-lino-manga-corta'), (SELECT id FROM color WHERE nombre = 'Gris Antracita'), 'CATALOGO', 'http://localhost:8081/media/variantes/blusa-de-lino-manga-corta-gris-antracita.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM color WHERE nombre = 'Azul Marino'), 'CATALOGO', 'http://localhost:8081/media/variantes/blusa-de-seda-manga-larga-azul-marino.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'http://localhost:8081/media/variantes/blusa-de-seda-manga-larga-negro.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM color WHERE nombre = 'Rojo'), 'CATALOGO', 'http://localhost:8081/media/variantes/blusa-de-seda-manga-larga-rojo.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM color WHERE nombre = 'Rosa Claro'), 'CATALOGO', 'http://localhost:8081/media/variantes/blusa-de-seda-manga-larga-rosa-claro.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), (SELECT id FROM color WHERE nombre = 'Beige'), 'CATALOGO', 'http://localhost:8081/media/variantes/borcego-negro-con-cordones-beige.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), (SELECT id FROM color WHERE nombre = 'Marrón'), 'CATALOGO', 'http://localhost:8081/media/variantes/borcego-negro-con-cordones-marron.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'http://localhost:8081/media/variantes/borcego-negro-con-cordones-negro.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), (SELECT id FROM color WHERE nombre = 'Verde Oliva'), 'CATALOGO', 'http://localhost:8081/media/variantes/borcego-negro-con-cordones-verde-oliva.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM color WHERE nombre = 'Azul Marino'), 'CATALOGO', 'http://localhost:8081/media/variantes/bota-cania-alta-de-gamuza-azul-marino.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM color WHERE nombre = 'Burdeos'), 'CATALOGO', 'http://localhost:8081/media/variantes/bota-cania-alta-de-gamuza-burdeos.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'http://localhost:8081/media/variantes/bota-cania-alta-de-gamuza-negro.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM color WHERE nombre = 'Taupe'), 'CATALOGO', 'http://localhost:8081/media/variantes/bota-cania-alta-de-gamuza-taupe.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM color WHERE nombre = 'Marrón Chocolate'), 'CATALOGO', 'http://localhost:8081/media/variantes/botineta-de-cuero-con-taco-marron-chocolate.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM color WHERE nombre = 'Negro Clásico'), 'CATALOGO', 'http://localhost:8081/media/variantes/botineta-de-cuero-con-taco-negro-clasico.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM color WHERE nombre = 'Verde Salvia'), 'CATALOGO', 'http://localhost:8081/media/variantes/botineta-de-cuero-con-taco-verde-salvia.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'camisa-oversize-a-cuadros'), (SELECT id FROM color WHERE nombre = 'Azul y Blanco'), 'CATALOGO', 'http://localhost:8081/media/variantes/camisa-oversize-a-cuadros-azul-y-blanco.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'camisa-oversize-a-cuadros'), (SELECT id FROM color WHERE nombre = 'Marino y Amarillo'), 'CATALOGO', 'http://localhost:8081/media/variantes/camisa-oversize-a-cuadros-marino-y-amarillo.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'camisa-oversize-a-cuadros'), (SELECT id FROM color WHERE nombre = 'Verde Bosque y Beige'), 'CATALOGO', 'http://localhost:8081/media/variantes/camisa-oversize-a-cuadros-verde-bosque-y-beige.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'campera-puffer-impermeable'), (SELECT id FROM color WHERE nombre = 'Azul Marino'), 'CATALOGO', 'http://localhost:8081/media/variantes/campera-puffer-impermeable-azul-marino.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'campera-puffer-impermeable'), (SELECT id FROM color WHERE nombre = 'Camello'), 'CATALOGO', 'http://localhost:8081/media/variantes/campera-puffer-impermeable-camello.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'campera-puffer-impermeable'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'http://localhost:8081/media/variantes/campera-puffer-impermeable-negro.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'campera-puffer-impermeable'), (SELECT id FROM color WHERE nombre = 'Verde Oliva'), 'CATALOGO', 'http://localhost:8081/media/variantes/campera-puffer-impermeable-verde-oliva.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM color WHERE nombre = 'Azul Índigo Clásico'), 'CATALOGO', 'http://localhost:8081/media/variantes/campera-de-jean-oversize-azul-indigo-clasico.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM color WHERE nombre = 'Azul Lavado Claro'), 'CATALOGO', 'http://localhost:8081/media/variantes/campera-de-jean-oversize-azul-lavado-claro.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM color WHERE nombre = 'Negro Carbón'), 'CATALOGO', 'http://localhost:8081/media/variantes/campera-de-jean-oversize-negro-carbon.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM color WHERE nombre = 'Verde Oliva'), 'CATALOGO', 'http://localhost:8081/media/variantes/campera-de-jean-oversize-verde-oliva.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM color WHERE nombre = 'Azul Marino Intenso'), 'CATALOGO', 'http://localhost:8081/media/variantes/cardigan-de-punto-grueso-azul-marino-intenso.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM color WHERE nombre = 'Gris Jaspeado'), 'CATALOGO', 'http://localhost:8081/media/variantes/cardigan-de-punto-grueso-gris-jaspeado.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM color WHERE nombre = 'Rosa Empolvado'), 'CATALOGO', 'http://localhost:8081/media/variantes/cardigan-de-punto-grueso-rosa-empolvado.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM color WHERE nombre = 'Verde Bosque'), 'CATALOGO', 'http://localhost:8081/media/variantes/cardigan-de-punto-grueso-verde-bosque.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'cartera-de-cuero-bandolera'), (SELECT id FROM color WHERE nombre = 'Café'), 'CATALOGO', 'http://localhost:8081/media/variantes/cartera-de-cuero-bandolera-cafe.png', 'PNG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'cartera-de-cuero-bandolera'), (SELECT id FROM color WHERE nombre = 'Greige'), 'CATALOGO', 'http://localhost:8081/media/variantes/cartera-de-cuero-bandolera-greige.png', 'PNG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'cartera-de-cuero-bandolera'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'http://localhost:8081/media/variantes/cartera-de-cuero-bandolera-negro.png', 'PNG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'cartera-de-cuero-bandolera'), (SELECT id FROM color WHERE nombre = 'Verde Oliva'), 'CATALOGO', 'http://localhost:8081/media/variantes/cartera-de-cuero-bandolera-verde-oliva.png', 'PNG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'chalina-de-alpaca'), (SELECT id FROM color WHERE nombre = 'Azul Marino'), 'CATALOGO', 'http://localhost:8081/media/variantes/chalina-de-alpaca-azul-marino.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'chalina-de-alpaca'), (SELECT id FROM color WHERE nombre = 'Beige'), 'CATALOGO', 'http://localhost:8081/media/variantes/chalina-de-alpaca-beige.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'chalina-de-alpaca'), (SELECT id FROM color WHERE nombre = 'Negro Carbón'), 'CATALOGO', 'http://localhost:8081/media/variantes/chalina-de-alpaca-negro-carbon.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM color WHERE nombre = 'Borgoña Intenso'), 'CATALOGO', 'http://localhost:8081/media/variantes/falda-lapiz-de-panio-borgona-intenso.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM color WHERE nombre = 'Camel Clásico'), 'CATALOGO', 'http://localhost:8081/media/variantes/falda-lapiz-de-panio-camel-clasico.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'http://localhost:8081/media/variantes/falda-lapiz-de-panio-negro.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM color WHERE nombre = 'Tweed Gris'), 'CATALOGO', 'http://localhost:8081/media/variantes/falda-lapiz-de-panio-tweed-gris.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), (SELECT id FROM color WHERE nombre = 'Azul Marino'), 'CATALOGO', 'http://localhost:8081/media/variantes/falda-larga-de-gasa-azul-marino.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), (SELECT id FROM color WHERE nombre = 'Beige Camel'), 'CATALOGO', 'http://localhost:8081/media/variantes/falda-larga-de-gasa-beige-camel.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), (SELECT id FROM color WHERE nombre = 'Marrón Chocolate'), 'CATALOGO', 'http://localhost:8081/media/variantes/falda-larga-de-gasa-marron-chocolate.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'http://localhost:8081/media/variantes/falda-larga-de-gasa-negro.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM color WHERE nombre = 'Borgoña'), 'CATALOGO', 'http://localhost:8081/media/variantes/falda-midi-plisada-borgona.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM color WHERE nombre = 'Marfil'), 'CATALOGO', 'http://localhost:8081/media/variantes/falda-midi-plisada-marfil.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM color WHERE nombre = 'Marino'), 'CATALOGO', 'http://localhost:8081/media/variantes/falda-midi-plisada-marino.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'http://localhost:8081/media/variantes/falda-midi-plisada-negro.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM color WHERE nombre = 'Lavado Ligero'), 'CATALOGO', 'http://localhost:8081/media/variantes/falda-de-jean-corta-lavado-ligero.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM color WHERE nombre = 'Lavado Medio'), 'CATALOGO', 'http://localhost:8081/media/variantes/falda-de-jean-corta-lavado-medio.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM color WHERE nombre = 'Lavado Oscuro'), 'CATALOGO', 'http://localhost:8081/media/variantes/falda-de-jean-corta-lavado-oscuro.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM color WHERE nombre = 'Verde Oliva'), 'CATALOGO', 'http://localhost:8081/media/variantes/falda-de-jean-corta-verde-oliva.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'gorro-y-guantes-de-lana'), (SELECT id FROM color WHERE nombre = 'Azul Marino'), 'CATALOGO', 'http://localhost:8081/media/variantes/gorro-y-guantes-de-lana-azul-marino.png', 'PNG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'gorro-y-guantes-de-lana'), (SELECT id FROM color WHERE nombre = 'Beige'), 'CATALOGO', 'http://localhost:8081/media/variantes/gorro-y-guantes-de-lana-beige.png', 'PNG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'gorro-y-guantes-de-lana'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'http://localhost:8081/media/variantes/gorro-y-guantes-de-lana-gris.png', 'PNG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'gorro-y-guantes-de-lana'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'http://localhost:8081/media/variantes/gorro-y-guantes-de-lana-negro.png', 'PNG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM color WHERE nombre = 'Blanco Óptico'), 'CATALOGO', 'http://localhost:8081/media/variantes/jean-tiro-alto-skinny-blanco-optico.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM color WHERE nombre = 'Índigo Oscuro'), 'CATALOGO', 'http://localhost:8081/media/variantes/jean-tiro-alto-skinny-indigo-oscuro.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM color WHERE nombre = 'Negro Sólido'), 'CATALOGO', 'http://localhost:8081/media/variantes/jean-tiro-alto-skinny-negro-solido.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM color WHERE nombre = 'Caqui Oliva'), 'CATALOGO', 'http://localhost:8081/media/variantes/jean-wide-leg-caqui-oliva.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM color WHERE nombre = 'Índigo Clásico'), 'CATALOGO', 'http://localhost:8081/media/variantes/jean-wide-leg-indigo-clasico.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM color WHERE nombre = 'Lavado Claro Ácido'), 'CATALOGO', 'http://localhost:8081/media/variantes/jean-wide-leg-lavado-claro-acido.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM color WHERE nombre = 'Negro Intenso'), 'CATALOGO', 'http://localhost:8081/media/variantes/jean-wide-leg-negro-intenso.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM color WHERE nombre = 'Azul Pizarra'), 'CATALOGO', 'http://localhost:8081/media/variantes/legging-termico-azul-pizarra.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM color WHERE nombre = 'Borgoña'), 'CATALOGO', 'http://localhost:8081/media/variantes/legging-termico-borgona.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM color WHERE nombre = 'Crema'), 'CATALOGO', 'http://localhost:8081/media/variantes/legging-termico-crema.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'http://localhost:8081/media/variantes/legging-termico-negro.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'lentes-de-sol-redondos'), (SELECT id FROM color WHERE nombre = 'Mate Carbón'), 'CATALOGO', 'http://localhost:8081/media/variantes/lentes-de-sol-redondos-mate-carbon.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'lentes-de-sol-redondos'), (SELECT id FROM color WHERE nombre = 'Negro Plateado'), 'CATALOGO', 'http://localhost:8081/media/variantes/lentes-de-sol-redondos-negro-plateado.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'lentes-de-sol-redondos'), (SELECT id FROM color WHERE nombre = 'Plata'), 'CATALOGO', 'http://localhost:8081/media/variantes/lentes-de-sol-redondos-plata.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'lentes-de-sol-redondos'), (SELECT id FROM color WHERE nombre = 'Dorado'), 'CATALOGO', 'http://localhost:8081/media/variantes/lentes-de-sol-redondos-dorado.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM color WHERE nombre = 'Azul Marino'), 'CATALOGO', 'http://localhost:8081/media/variantes/pantalon-palazzo-de-lino-azul-marino.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM color WHERE nombre = 'Gris Carbón'), 'CATALOGO', 'http://localhost:8081/media/variantes/pantalon-palazzo-de-lino-gris-carbon.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM color WHERE nombre = 'Natural'), 'CATALOGO', 'http://localhost:8081/media/variantes/pantalon-palazzo-de-lino-natural.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM color WHERE nombre = 'Verde Salvia'), 'CATALOGO', 'http://localhost:8081/media/variantes/pantalon-palazzo-de-lino-verde-salvia.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM color WHERE nombre = 'Azul Marino Profundo'), 'CATALOGO', 'http://localhost:8081/media/variantes/pantalon-de-vestir-sastrero-azul-marino-profundo.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM color WHERE nombre = 'Camel Beige'), 'CATALOGO', 'http://localhost:8081/media/variantes/pantalon-de-vestir-sastrero-camel-beige.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM color WHERE nombre = 'Gris Antracita'), 'CATALOGO', 'http://localhost:8081/media/variantes/pantalon-de-vestir-sastrero-gris-antracita.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM color WHERE nombre = 'Negro Clásico'), 'CATALOGO', 'http://localhost:8081/media/variantes/pantalon-de-vestir-sastrero-negro-clasico.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'sandalia-con-tiras-y-taco'), (SELECT id FROM color WHERE nombre = 'Dorado'), 'CATALOGO', 'http://localhost:8081/media/variantes/sandalia-con-tiras-y-taco-dorado.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'sandalia-con-tiras-y-taco'), (SELECT id FROM color WHERE nombre = 'Marfil'), 'CATALOGO', 'http://localhost:8081/media/variantes/sandalia-con-tiras-y-taco-marfil.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'sandalia-con-tiras-y-taco'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'http://localhost:8081/media/variantes/sandalia-con-tiras-y-taco-negro.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'sandalia-con-tiras-y-taco'), (SELECT id FROM color WHERE nombre = 'Rojo'), 'CATALOGO', 'http://localhost:8081/media/variantes/sandalia-con-tiras-y-taco-rojo.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'tapado-de-lana-largo'), (SELECT id FROM color WHERE nombre = 'Azul Marino Elegante'), 'CATALOGO', 'http://localhost:8081/media/variantes/tapado-de-lana-largo-azul-marino-elegante.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'tapado-de-lana-largo'), (SELECT id FROM color WHERE nombre = 'Gris Antracita'), 'CATALOGO', 'http://localhost:8081/media/variantes/tapado-de-lana-largo-gris-antracita.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'tapado-de-lana-largo'), (SELECT id FROM color WHERE nombre = 'Borgoña Profundo'), 'CATALOGO', 'http://localhost:8081/media/variantes/tapado-de-lana-largo-borgona-profundo.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'top-de-tirantes-de-algodon'), (SELECT id FROM color WHERE nombre = 'Azul'), 'CATALOGO', 'http://localhost:8081/media/variantes/top-de-tirantes-de-algodon-azul.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'top-de-tirantes-de-algodon'), (SELECT id FROM color WHERE nombre = 'Blanco'), 'CATALOGO', 'http://localhost:8081/media/variantes/top-de-tirantes-de-algodon-blanco.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'top-de-tirantes-de-algodon'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'http://localhost:8081/media/variantes/top-de-tirantes-de-algodon-gris.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'top-de-tirantes-de-algodon'), (SELECT id FROM color WHERE nombre = 'Rosa'), 'CATALOGO', 'http://localhost:8081/media/variantes/top-de-tirantes-de-algodon-rosa.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM color WHERE nombre = 'Azul Marino'), 'CATALOGO', 'http://localhost:8081/media/variantes/vestido-camisero-de-lino-azul-marino.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM color WHERE nombre = 'Negro Elegante'), 'CATALOGO', 'http://localhost:8081/media/variantes/vestido-camisero-de-lino-negro-elegante.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM color WHERE nombre = 'Rojo Rubí'), 'CATALOGO', 'http://localhost:8081/media/variantes/vestido-camisero-de-lino-rojo-rubi.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM color WHERE nombre = 'Verde Sabio'), 'CATALOGO', 'http://localhost:8081/media/variantes/vestido-camisero-de-lino-verde-sabio.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'vestido-floral-manga-corta'), (SELECT id FROM color WHERE nombre = 'Azul y Blanco'), 'CATALOGO', 'http://localhost:8081/media/variantes/vestido-floral-manga-corta-azul-y-blanco.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'vestido-floral-manga-corta'), (SELECT id FROM color WHERE nombre = 'Café Miel'), 'CATALOGO', 'http://localhost:8081/media/variantes/vestido-floral-manga-corta-cafe-miel.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'vestido-floral-manga-corta'), (SELECT id FROM color WHERE nombre = 'Rojo y Blanco'), 'CATALOGO', 'http://localhost:8081/media/variantes/vestido-floral-manga-corta-rojo-y-blanco.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'vestido-largo-estampado'), (SELECT id FROM color WHERE nombre = 'Amanecer Suave'), 'CATALOGO', 'http://localhost:8081/media/variantes/vestido-largo-estampado-amanecer-suave.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'vestido-largo-estampado'), (SELECT id FROM color WHERE nombre = 'Cálido Oliva'), 'CATALOGO', 'http://localhost:8081/media/variantes/vestido-largo-estampado-calido-oliva.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'vestido-largo-estampado'), (SELECT id FROM color WHERE nombre = 'Cielo Monocromático'), 'CATALOGO', 'http://localhost:8081/media/variantes/vestido-largo-estampado-cielo-monocromatico.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'vestido-largo-estampado'), (SELECT id FROM color WHERE nombre = 'Crepúsculo Dramático'), 'CATALOGO', 'http://localhost:8081/media/variantes/vestido-largo-estampado-crepusculo-dramatico.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'vestido-midi-plisado'), (SELECT id FROM color WHERE nombre = 'Azul Marino'), 'CATALOGO', 'http://localhost:8081/media/variantes/vestido-midi-plisado-azul-marino.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'vestido-midi-plisado'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'http://localhost:8081/media/variantes/vestido-midi-plisado-gris.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'vestido-midi-plisado'), (SELECT id FROM color WHERE nombre = 'Rojo'), 'CATALOGO', 'http://localhost:8081/media/variantes/vestido-midi-plisado-rojo.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'vestido-midi-plisado'), (SELECT id FROM color WHERE nombre = 'Verde Oliva'), 'CATALOGO', 'http://localhost:8081/media/variantes/vestido-midi-plisado-verde-oliva.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'vestido-negro-de-fiesta'), (SELECT id FROM color WHERE nombre = 'Azul Marino'), 'CATALOGO', 'http://localhost:8081/media/variantes/vestido-negro-de-fiesta-azul-marino.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'vestido-negro-de-fiesta'), (SELECT id FROM color WHERE nombre = 'Borgoña Profundo'), 'CATALOGO', 'http://localhost:8081/media/variantes/vestido-negro-de-fiesta-borgona-profundo.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'vestido-negro-de-fiesta'), (SELECT id FROM color WHERE nombre = 'Ciruela Oscuro'), 'CATALOGO', 'http://localhost:8081/media/variantes/vestido-negro-de-fiesta-ciruela-oscuro.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'vestido-negro-de-fiesta'), (SELECT id FROM color WHERE nombre = 'Verde Esmeralda'), 'CATALOGO', 'http://localhost:8081/media/variantes/vestido-negro-de-fiesta-verde-esmeralda.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'vestido-de-punto-manga-larga'), (SELECT id FROM color WHERE nombre = 'Cálido'), 'CATALOGO', 'http://localhost:8081/media/variantes/vestido-de-punto-manga-larga-calido.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'vestido-de-punto-manga-larga'), (SELECT id FROM color WHERE nombre = 'Frío'), 'CATALOGO', 'http://localhost:8081/media/variantes/vestido-de-punto-manga-larga-frio.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'vestido-de-punto-manga-larga'), (SELECT id FROM color WHERE nombre = 'Neutro'), 'CATALOGO', 'http://localhost:8081/media/variantes/vestido-de-punto-manga-larga-neutro.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'zapatilla-urbana-blanca'), (SELECT id FROM color WHERE nombre = 'Azul Marino'), 'CATALOGO', 'http://localhost:8081/media/variantes/zapatilla-urbana-blanca-azul-marino.png', 'PNG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'zapatilla-urbana-blanca'), (SELECT id FROM color WHERE nombre = 'Blanco'), 'CATALOGO', 'http://localhost:8081/media/variantes/zapatilla-urbana-blanca-blanco.png', 'PNG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'zapatilla-urbana-blanca'), (SELECT id FROM color WHERE nombre = 'Gris'), 'CATALOGO', 'http://localhost:8081/media/variantes/zapatilla-urbana-blanca-gris.png', 'PNG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'zapatilla-urbana-blanca'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'http://localhost:8081/media/variantes/zapatilla-urbana-blanca-negro.png', 'PNG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM color WHERE nombre = 'Rosa Chicle'), 'CATALOGO', 'http://localhost:8081/media/variantes/zapato-stiletto-de-charol-rosa-chicle.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM color WHERE nombre = 'Borgoña Profundo'), 'CATALOGO', 'http://localhost:8081/media/variantes/zapato-stiletto-de-charol-borgona-profundo.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM color WHERE nombre = 'Azul Marino'), 'CATALOGO', 'http://localhost:8081/media/variantes/zapato-stiletto-de-charol-azul-marino.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM color WHERE nombre = 'Nude Clásico'), 'CATALOGO', 'http://localhost:8081/media/variantes/zapato-stiletto-de-charol-nude-clasico.jpg', 'JPG', FALSE, 1),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM color WHERE nombre = 'Negro'), 'CATALOGO', 'http://localhost:8081/media/variantes/zapato-stiletto-de-charol-negro.jpg', 'JPG', FALSE, 1)
;

-- ---------------------------------------------------------------------
-- VARIANTES NUEVAS PARA LOS COLORES ADICIONALES: crea producto_variante
-- para cada color agregado arriba que todavia no tenia variante compra-
-- ble, con las mismas tallas que ya tiene el producto. Asi dejan de apa-
-- recer como "Mas colores (solo referencia)" en el detalle y se pueden
-- reservar/comprar como cualquier otra variante. El inventario para estas
-- variantes nuevas lo llena el mismo INSERT INTO inventario de mas abajo
-- (no filtra por variante, y tiene ON CONFLICT DO NOTHING).
-- ---------------------------------------------------------------------

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku) VALUES
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '35'), 13, 'ZAP-002-35-C13'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '36'), 13, 'ZAP-002-36-C13'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '37'), 13, 'ZAP-002-37-C13'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '38'), 13, 'ZAP-002-38-C13'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '39'), 13, 'ZAP-002-39-C13'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '35'), 26, 'ZAP-002-35-C26'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '36'), 26, 'ZAP-002-36-C26'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '37'), 26, 'ZAP-002-37-C26'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '38'), 26, 'ZAP-002-38-C26'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '39'), 26, 'ZAP-002-39-C26'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '35'), 50, 'ZAP-002-35-C50'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '36'), 50, 'ZAP-002-36-C50'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '37'), 50, 'ZAP-002-37-C50'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '38'), 50, 'ZAP-002-38-C50'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '39'), 50, 'ZAP-002-39-C50'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '35'), 56, 'ZAP-002-35-C56'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '36'), 56, 'ZAP-002-36-C56'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '37'), 56, 'ZAP-002-37-C56'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '38'), 56, 'ZAP-002-38-C56'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '39'), 56, 'ZAP-002-39-C56'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '35'), 7, 'ZAP-002-35-C7'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '36'), 7, 'ZAP-002-36-C7'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '37'), 7, 'ZAP-002-37-C7'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '38'), 7, 'ZAP-002-38-C7'),
    ((SELECT id FROM producto WHERE slug = 'ballerina-de-cuero'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '39'), 7, 'ZAP-002-39-C7'),
    ((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 13, 'ABR-004-L-C13'),
    ((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 13, 'ABR-004-M-C13'),
    ((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 13, 'ABR-004-S-C13'),
    ((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 13, 'ABR-004-XS-C13'),
    ((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 28, 'ABR-004-L-C28'),
    ((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 28, 'ABR-004-M-C28'),
    ((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 28, 'ABR-004-S-C28'),
    ((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 28, 'ABR-004-XS-C28'),
    ((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 79, 'ABR-004-L-C79'),
    ((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 79, 'ABR-004-M-C79'),
    ((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 79, 'ABR-004-S-C79'),
    ((SELECT id FROM producto WHERE slug = 'blazer-entallado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 79, 'ABR-004-XS-C79'),
    ((SELECT id FROM producto WHERE slug = 'blusa-cropped-con-volados'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 13, 'BLU-005-M-C13'),
    ((SELECT id FROM producto WHERE slug = 'blusa-cropped-con-volados'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 13, 'BLU-005-S-C13'),
    ((SELECT id FROM producto WHERE slug = 'blusa-cropped-con-volados'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 13, 'BLU-005-XS-C13'),
    ((SELECT id FROM producto WHERE slug = 'blusa-cropped-con-volados'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 49, 'BLU-005-M-C49'),
    ((SELECT id FROM producto WHERE slug = 'blusa-cropped-con-volados'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 49, 'BLU-005-S-C49'),
    ((SELECT id FROM producto WHERE slug = 'blusa-cropped-con-volados'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 49, 'BLU-005-XS-C49'),
    ((SELECT id FROM producto WHERE slug = 'blusa-cropped-con-volados'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 1, 'BLU-005-M-C1'),
    ((SELECT id FROM producto WHERE slug = 'blusa-cropped-con-volados'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 1, 'BLU-005-S-C1'),
    ((SELECT id FROM producto WHERE slug = 'blusa-cropped-con-volados'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 1, 'BLU-005-XS-C1'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-lino-manga-corta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 13, 'BLU-001-L-C13'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-lino-manga-corta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 13, 'BLU-001-M-C13'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-lino-manga-corta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 13, 'BLU-001-S-C13'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-lino-manga-corta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 13, 'BLU-001-XS-C13'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-lino-manga-corta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 32, 'BLU-001-L-C32'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-lino-manga-corta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 32, 'BLU-001-M-C32'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-lino-manga-corta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 32, 'BLU-001-S-C32'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-lino-manga-corta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 32, 'BLU-001-XS-C32'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-lino-manga-corta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 42, 'BLU-001-L-C42'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-lino-manga-corta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 42, 'BLU-001-M-C42'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-lino-manga-corta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 42, 'BLU-001-S-C42'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-lino-manga-corta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 42, 'BLU-001-XS-C42'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 13, 'BLU-002-L-C13'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 13, 'BLU-002-M-C13'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 13, 'BLU-002-S-C13'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 13, 'BLU-002-XS-C13'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 1, 'BLU-002-L-C1'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 1, 'BLU-002-M-C1'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 1, 'BLU-002-S-C1'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 1, 'BLU-002-XS-C1'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 4, 'BLU-002-L-C4'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 4, 'BLU-002-M-C4'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 4, 'BLU-002-S-C4'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 4, 'BLU-002-XS-C4'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 71, 'BLU-002-L-C71'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 71, 'BLU-002-M-C71'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 71, 'BLU-002-S-C71'),
    ((SELECT id FROM producto WHERE slug = 'blusa-de-seda-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 71, 'BLU-002-XS-C71'),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '35'), 6, 'BOT-003-35-C6'),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '36'), 6, 'BOT-003-36-C6'),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '37'), 6, 'BOT-003-37-C6'),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '38'), 6, 'BOT-003-38-C6'),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '39'), 6, 'BOT-003-39-C6'),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '40'), 6, 'BOT-003-40-C6'),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '35'), 53, 'BOT-003-35-C53'),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '36'), 53, 'BOT-003-36-C53'),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '37'), 53, 'BOT-003-37-C53'),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '38'), 53, 'BOT-003-38-C53'),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '39'), 53, 'BOT-003-39-C53'),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '40'), 53, 'BOT-003-40-C53'),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '35'), 7, 'BOT-003-35-C7'),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '36'), 7, 'BOT-003-36-C7'),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '37'), 7, 'BOT-003-37-C7'),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '38'), 7, 'BOT-003-38-C7'),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '39'), 7, 'BOT-003-39-C7'),
    ((SELECT id FROM producto WHERE slug = 'borcego-negro-con-cordones'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '40'), 7, 'BOT-003-40-C7'),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '35'), 13, 'BOT-002-35-C13'),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '36'), 13, 'BOT-002-36-C13'),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '37'), 13, 'BOT-002-37-C13'),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '38'), 13, 'BOT-002-38-C13'),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '39'), 13, 'BOT-002-39-C13'),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '40'), 13, 'BOT-002-40-C13'),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '35'), 25, 'BOT-002-35-C25'),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '36'), 25, 'BOT-002-36-C25'),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '37'), 25, 'BOT-002-37-C25'),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '38'), 25, 'BOT-002-38-C25'),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '39'), 25, 'BOT-002-39-C25'),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '40'), 25, 'BOT-002-40-C25'),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '35'), 73, 'BOT-002-35-C73'),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '36'), 73, 'BOT-002-36-C73'),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '37'), 73, 'BOT-002-37-C73'),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '38'), 73, 'BOT-002-38-C73'),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '39'), 73, 'BOT-002-39-C73'),
    ((SELECT id FROM producto WHERE slug = 'bota-cania-alta-de-gamuza'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '40'), 73, 'BOT-002-40-C73'),
    ((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '35'), 54, 'BOT-001-35-C54'),
    ((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '36'), 54, 'BOT-001-36-C54'),
    ((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '37'), 54, 'BOT-001-37-C54'),
    ((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '38'), 54, 'BOT-001-38-C54'),
    ((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '39'), 54, 'BOT-001-39-C54'),
    ((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '40'), 54, 'BOT-001-40-C54'),
    ((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '35'), 59, 'BOT-001-35-C59'),
    ((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '36'), 59, 'BOT-001-36-C59'),
    ((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '37'), 59, 'BOT-001-37-C59'),
    ((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '38'), 59, 'BOT-001-38-C59'),
    ((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '39'), 59, 'BOT-001-39-C59'),
    ((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '40'), 59, 'BOT-001-40-C59'),
    ((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '35'), 79, 'BOT-001-35-C79'),
    ((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '36'), 79, 'BOT-001-36-C79'),
    ((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '37'), 79, 'BOT-001-37-C79'),
    ((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '38'), 79, 'BOT-001-38-C79'),
    ((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '39'), 79, 'BOT-001-39-C79'),
    ((SELECT id FROM producto WHERE slug = 'botineta-de-cuero-con-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '40'), 79, 'BOT-001-40-C79'),
    ((SELECT id FROM producto WHERE slug = 'camisa-oversize-a-cuadros'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 18, 'BLU-003-L-C18'),
    ((SELECT id FROM producto WHERE slug = 'camisa-oversize-a-cuadros'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 18, 'BLU-003-M-C18'),
    ((SELECT id FROM producto WHERE slug = 'camisa-oversize-a-cuadros'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 18, 'BLU-003-S-C18'),
    ((SELECT id FROM producto WHERE slug = 'camisa-oversize-a-cuadros'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XL'), 18, 'BLU-003-XL-C18'),
    ((SELECT id FROM producto WHERE slug = 'camisa-oversize-a-cuadros'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 52, 'BLU-003-L-C52'),
    ((SELECT id FROM producto WHERE slug = 'camisa-oversize-a-cuadros'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 52, 'BLU-003-M-C52'),
    ((SELECT id FROM producto WHERE slug = 'camisa-oversize-a-cuadros'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 52, 'BLU-003-S-C52'),
    ((SELECT id FROM producto WHERE slug = 'camisa-oversize-a-cuadros'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XL'), 52, 'BLU-003-XL-C52'),
    ((SELECT id FROM producto WHERE slug = 'camisa-oversize-a-cuadros'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 76, 'BLU-003-L-C76'),
    ((SELECT id FROM producto WHERE slug = 'camisa-oversize-a-cuadros'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 76, 'BLU-003-M-C76'),
    ((SELECT id FROM producto WHERE slug = 'camisa-oversize-a-cuadros'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 76, 'BLU-003-S-C76'),
    ((SELECT id FROM producto WHERE slug = 'camisa-oversize-a-cuadros'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XL'), 76, 'BLU-003-XL-C76'),
    ((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 19, 'ABR-002-L-C19'),
    ((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 19, 'ABR-002-M-C19'),
    ((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 19, 'ABR-002-S-C19'),
    ((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XL'), 19, 'ABR-002-XL-C19'),
    ((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 12, 'ABR-002-L-C12'),
    ((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 12, 'ABR-002-M-C12'),
    ((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 12, 'ABR-002-S-C12'),
    ((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XL'), 12, 'ABR-002-XL-C12'),
    ((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 58, 'ABR-002-L-C58'),
    ((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 58, 'ABR-002-M-C58'),
    ((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 58, 'ABR-002-S-C58'),
    ((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XL'), 58, 'ABR-002-XL-C58'),
    ((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 7, 'ABR-002-L-C7'),
    ((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 7, 'ABR-002-M-C7'),
    ((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 7, 'ABR-002-S-C7'),
    ((SELECT id FROM producto WHERE slug = 'campera-de-jean-oversize'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XL'), 7, 'ABR-002-XL-C7'),
    ((SELECT id FROM producto WHERE slug = 'campera-puffer-impermeable'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 13, 'ABR-005-L-C13'),
    ((SELECT id FROM producto WHERE slug = 'campera-puffer-impermeable'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 13, 'ABR-005-M-C13'),
    ((SELECT id FROM producto WHERE slug = 'campera-puffer-impermeable'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 13, 'ABR-005-S-C13'),
    ((SELECT id FROM producto WHERE slug = 'campera-puffer-impermeable'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XL'), 13, 'ABR-005-XL-C13'),
    ((SELECT id FROM producto WHERE slug = 'campera-puffer-impermeable'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 30, 'ABR-005-L-C30'),
    ((SELECT id FROM producto WHERE slug = 'campera-puffer-impermeable'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 30, 'ABR-005-M-C30'),
    ((SELECT id FROM producto WHERE slug = 'campera-puffer-impermeable'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 30, 'ABR-005-S-C30'),
    ((SELECT id FROM producto WHERE slug = 'campera-puffer-impermeable'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XL'), 30, 'ABR-005-XL-C30'),
    ((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 15, 'ABR-003-L-C15'),
    ((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 15, 'ABR-003-M-C15'),
    ((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 15, 'ABR-003-S-C15'),
    ((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XL'), 15, 'ABR-003-XL-C15'),
    ((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 44, 'ABR-003-L-C44'),
    ((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 44, 'ABR-003-M-C44'),
    ((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 44, 'ABR-003-S-C44'),
    ((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XL'), 44, 'ABR-003-XL-C44'),
    ((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 72, 'ABR-003-L-C72'),
    ((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 72, 'ABR-003-M-C72'),
    ((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 72, 'ABR-003-S-C72'),
    ((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XL'), 72, 'ABR-003-XL-C72'),
    ((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 75, 'ABR-003-L-C75'),
    ((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 75, 'ABR-003-M-C75'),
    ((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 75, 'ABR-003-S-C75'),
    ((SELECT id FROM producto WHERE slug = 'cardigan-de-punto-grueso'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XL'), 75, 'ABR-003-XL-C75'),
    ((SELECT id FROM producto WHERE slug = 'cartera-de-cuero-bandolera'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'UNICA'), 26, 'ACC-002-UNICA-C26'),
    ((SELECT id FROM producto WHERE slug = 'cartera-de-cuero-bandolera'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'UNICA'), 41, 'ACC-002-UNICA-C41'),
    ((SELECT id FROM producto WHERE slug = 'cartera-de-cuero-bandolera'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'UNICA'), 7, 'ACC-002-UNICA-C7'),
    ((SELECT id FROM producto WHERE slug = 'chalina-de-alpaca'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'UNICA'), 13, 'ACC-001-UNICA-C13'),
    ((SELECT id FROM producto WHERE slug = 'chalina-de-alpaca'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'UNICA'), 58, 'ACC-001-UNICA-C58'),
    ((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 46, 'FAL-002-36-C46'),
    ((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 46, 'FAL-002-38-C46'),
    ((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 46, 'FAL-002-40-C46'),
    ((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 46, 'FAL-002-42-C46'),
    ((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 47, 'FAL-002-36-C47'),
    ((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 47, 'FAL-002-38-C47'),
    ((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 47, 'FAL-002-40-C47'),
    ((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 47, 'FAL-002-42-C47'),
    ((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 48, 'FAL-002-36-C48'),
    ((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 48, 'FAL-002-38-C48'),
    ((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 48, 'FAL-002-40-C48'),
    ((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 48, 'FAL-002-42-C48'),
    ((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 7, 'FAL-002-36-C7'),
    ((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 7, 'FAL-002-38-C7'),
    ((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 7, 'FAL-002-40-C7'),
    ((SELECT id FROM producto WHERE slug = 'falda-de-jean-corta'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 7, 'FAL-002-42-C7'),
    ((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 23, 'FAL-004-36-C23'),
    ((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 23, 'FAL-004-38-C23'),
    ((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 23, 'FAL-004-40-C23'),
    ((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 23, 'FAL-004-42-C23'),
    ((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 29, 'FAL-004-36-C29'),
    ((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 29, 'FAL-004-38-C29'),
    ((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 29, 'FAL-004-40-C29'),
    ((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 29, 'FAL-004-42-C29'),
    ((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 74, 'FAL-004-36-C74'),
    ((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 74, 'FAL-004-38-C74'),
    ((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 74, 'FAL-004-40-C74'),
    ((SELECT id FROM producto WHERE slug = 'falda-lapiz-de-panio'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 74, 'FAL-004-42-C74'),
    ((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 13, 'FAL-003-36-C13'),
    ((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 13, 'FAL-003-38-C13'),
    ((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 13, 'FAL-003-40-C13'),
    ((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 20, 'FAL-003-36-C20'),
    ((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 20, 'FAL-003-38-C20'),
    ((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 20, 'FAL-003-40-C20'),
    ((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 54, 'FAL-003-36-C54'),
    ((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 54, 'FAL-003-38-C54'),
    ((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 54, 'FAL-003-40-C54'),
    ((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 1, 'FAL-003-36-C1'),
    ((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 1, 'FAL-003-38-C1'),
    ((SELECT id FROM producto WHERE slug = 'falda-larga-de-gasa'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 1, 'FAL-003-40-C1'),
    ((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 22, 'FAL-001-36-C22'),
    ((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 22, 'FAL-001-38-C22'),
    ((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 22, 'FAL-001-40-C22'),
    ((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 22, 'FAL-001-42-C22'),
    ((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 50, 'FAL-001-36-C50'),
    ((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 50, 'FAL-001-38-C50'),
    ((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 50, 'FAL-001-40-C50'),
    ((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 50, 'FAL-001-42-C50'),
    ((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 51, 'FAL-001-36-C51'),
    ((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 51, 'FAL-001-38-C51'),
    ((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 51, 'FAL-001-40-C51'),
    ((SELECT id FROM producto WHERE slug = 'falda-midi-plisada'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 51, 'FAL-001-42-C51'),
    ((SELECT id FROM producto WHERE slug = 'gorro-y-guantes-de-lana'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'UNICA'), 13, 'ACC-005-UNICA-C13'),
    ((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 21, 'PAN-001-36-C21'),
    ((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 21, 'PAN-001-38-C21'),
    ((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 21, 'PAN-001-40-C21'),
    ((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 21, 'PAN-001-42-C21'),
    ((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '44'), 21, 'PAN-001-44-C21'),
    ((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 81, 'PAN-001-36-C81'),
    ((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 81, 'PAN-001-38-C81'),
    ((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 81, 'PAN-001-40-C81'),
    ((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 81, 'PAN-001-42-C81'),
    ((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '44'), 81, 'PAN-001-44-C81'),
    ((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 63, 'PAN-001-36-C63'),
    ((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 63, 'PAN-001-38-C63'),
    ((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 63, 'PAN-001-40-C63'),
    ((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 63, 'PAN-001-42-C63'),
    ((SELECT id FROM producto WHERE slug = 'jean-tiro-alto-skinny'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '44'), 63, 'PAN-001-44-C63'),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 31, 'PAN-004-36-C31'),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 31, 'PAN-004-38-C31'),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 31, 'PAN-004-40-C31'),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 31, 'PAN-004-42-C31'),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '44'), 31, 'PAN-004-44-C31'),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 80, 'PAN-004-36-C80'),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 80, 'PAN-004-38-C80'),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 80, 'PAN-004-40-C80'),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 80, 'PAN-004-42-C80'),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '44'), 80, 'PAN-004-44-C80'),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 45, 'PAN-004-36-C45'),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 45, 'PAN-004-38-C45'),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 45, 'PAN-004-40-C45'),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 45, 'PAN-004-42-C45'),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '44'), 45, 'PAN-004-44-C45'),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 61, 'PAN-004-36-C61'),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 61, 'PAN-004-38-C61'),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 61, 'PAN-004-40-C61'),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 61, 'PAN-004-42-C61'),
    ((SELECT id FROM producto WHERE slug = 'jean-wide-leg'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '44'), 61, 'PAN-004-44-C61'),
    ((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 17, 'PAN-005-L-C17'),
    ((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 17, 'PAN-005-M-C17'),
    ((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 17, 'PAN-005-S-C17'),
    ((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XL'), 17, 'PAN-005-XL-C17'),
    ((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 17, 'PAN-005-XS-C17'),
    ((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 22, 'PAN-005-L-C22'),
    ((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 22, 'PAN-005-M-C22'),
    ((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 22, 'PAN-005-S-C22'),
    ((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XL'), 22, 'PAN-005-XL-C22'),
    ((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 22, 'PAN-005-XS-C22'),
    ((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 35, 'PAN-005-L-C35'),
    ((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 35, 'PAN-005-M-C35'),
    ((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 35, 'PAN-005-S-C35'),
    ((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XL'), 35, 'PAN-005-XL-C35'),
    ((SELECT id FROM producto WHERE slug = 'legging-termico'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 35, 'PAN-005-XS-C35'),
    ((SELECT id FROM producto WHERE slug = 'lentes-de-sol-redondos'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'UNICA'), 39, 'ACC-006-UNICA-C39'),
    ((SELECT id FROM producto WHERE slug = 'lentes-de-sol-redondos'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'UNICA'), 55, 'ACC-006-UNICA-C55'),
    ((SELECT id FROM producto WHERE slug = 'lentes-de-sol-redondos'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'UNICA'), 62, 'ACC-006-UNICA-C62'),
    ((SELECT id FROM producto WHERE slug = 'lentes-de-sol-redondos'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'UNICA'), 66, 'ACC-006-UNICA-C66'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 16, 'PAN-003-36-C16'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 16, 'PAN-003-38-C16'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 16, 'PAN-003-40-C16'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 16, 'PAN-003-42-C16'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '44'), 16, 'PAN-003-44-C16'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 28, 'PAN-003-36-C28'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 28, 'PAN-003-38-C28'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 28, 'PAN-003-40-C28'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 28, 'PAN-003-42-C28'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '44'), 28, 'PAN-003-44-C28'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 42, 'PAN-003-36-C42'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 42, 'PAN-003-38-C42'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 42, 'PAN-003-40-C42'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 42, 'PAN-003-42-C42'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '44'), 42, 'PAN-003-44-C42'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 59, 'PAN-003-36-C59'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 59, 'PAN-003-38-C59'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 59, 'PAN-003-40-C59'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 59, 'PAN-003-42-C59'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-de-vestir-sastrero'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '44'), 59, 'PAN-003-44-C59'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 13, 'PAN-002-36-C13'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 13, 'PAN-002-38-C13'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 13, 'PAN-002-40-C13'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 13, 'PAN-002-42-C13'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 43, 'PAN-002-36-C43'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 43, 'PAN-002-38-C43'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 43, 'PAN-002-40-C43'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 43, 'PAN-002-42-C43'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 57, 'PAN-002-36-C57'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 57, 'PAN-002-38-C57'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 57, 'PAN-002-40-C57'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 57, 'PAN-002-42-C57'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '36'), 79, 'PAN-002-36-C79'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '38'), 79, 'PAN-002-38-C79'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '40'), 79, 'PAN-002-40-C79'),
    ((SELECT id FROM producto WHERE slug = 'pantalon-palazzo-de-lino'), (SELECT id FROM talla WHERE tipo = 'NUMERO' AND codigo = '42'), 79, 'PAN-002-42-C79'),
    ((SELECT id FROM producto WHERE slug = 'sandalia-con-tiras-y-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '35'), 39, 'SAN-003-35-C39'),
    ((SELECT id FROM producto WHERE slug = 'sandalia-con-tiras-y-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '36'), 39, 'SAN-003-36-C39'),
    ((SELECT id FROM producto WHERE slug = 'sandalia-con-tiras-y-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '37'), 39, 'SAN-003-37-C39'),
    ((SELECT id FROM producto WHERE slug = 'sandalia-con-tiras-y-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '38'), 39, 'SAN-003-38-C39'),
    ((SELECT id FROM producto WHERE slug = 'sandalia-con-tiras-y-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '39'), 39, 'SAN-003-39-C39'),
    ((SELECT id FROM producto WHERE slug = 'sandalia-con-tiras-y-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '35'), 50, 'SAN-003-35-C50'),
    ((SELECT id FROM producto WHERE slug = 'sandalia-con-tiras-y-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '36'), 50, 'SAN-003-36-C50'),
    ((SELECT id FROM producto WHERE slug = 'sandalia-con-tiras-y-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '37'), 50, 'SAN-003-37-C50'),
    ((SELECT id FROM producto WHERE slug = 'sandalia-con-tiras-y-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '38'), 50, 'SAN-003-38-C50'),
    ((SELECT id FROM producto WHERE slug = 'sandalia-con-tiras-y-taco'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '39'), 50, 'SAN-003-39-C50'),
    ((SELECT id FROM producto WHERE slug = 'tapado-de-lana-largo'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 14, 'ABR-001-L-C14'),
    ((SELECT id FROM producto WHERE slug = 'tapado-de-lana-largo'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 14, 'ABR-001-M-C14'),
    ((SELECT id FROM producto WHERE slug = 'tapado-de-lana-largo'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 14, 'ABR-001-S-C14'),
    ((SELECT id FROM producto WHERE slug = 'tapado-de-lana-largo'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XL'), 14, 'ABR-001-XL-C14'),
    ((SELECT id FROM producto WHERE slug = 'tapado-de-lana-largo'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 24, 'ABR-001-L-C24'),
    ((SELECT id FROM producto WHERE slug = 'tapado-de-lana-largo'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 24, 'ABR-001-M-C24'),
    ((SELECT id FROM producto WHERE slug = 'tapado-de-lana-largo'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 24, 'ABR-001-S-C24'),
    ((SELECT id FROM producto WHERE slug = 'tapado-de-lana-largo'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XL'), 24, 'ABR-001-XL-C24'),
    ((SELECT id FROM producto WHERE slug = 'tapado-de-lana-largo'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 42, 'ABR-001-L-C42'),
    ((SELECT id FROM producto WHERE slug = 'tapado-de-lana-largo'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 42, 'ABR-001-M-C42'),
    ((SELECT id FROM producto WHERE slug = 'tapado-de-lana-largo'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 42, 'ABR-001-S-C42'),
    ((SELECT id FROM producto WHERE slug = 'tapado-de-lana-largo'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XL'), 42, 'ABR-001-XL-C42'),
    ((SELECT id FROM producto WHERE slug = 'top-de-tirantes-de-algodon'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 3, 'BLU-004-L-C3'),
    ((SELECT id FROM producto WHERE slug = 'top-de-tirantes-de-algodon'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 3, 'BLU-004-M-C3'),
    ((SELECT id FROM producto WHERE slug = 'top-de-tirantes-de-algodon'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 3, 'BLU-004-S-C3'),
    ((SELECT id FROM producto WHERE slug = 'top-de-tirantes-de-algodon'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 3, 'BLU-004-XS-C3'),
    ((SELECT id FROM producto WHERE slug = 'top-de-tirantes-de-algodon'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 5, 'BLU-004-L-C5'),
    ((SELECT id FROM producto WHERE slug = 'top-de-tirantes-de-algodon'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 5, 'BLU-004-M-C5'),
    ((SELECT id FROM producto WHERE slug = 'top-de-tirantes-de-algodon'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 5, 'BLU-004-S-C5'),
    ((SELECT id FROM producto WHERE slug = 'top-de-tirantes-de-algodon'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 5, 'BLU-004-XS-C5'),
    ((SELECT id FROM producto WHERE slug = 'top-de-tirantes-de-algodon'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 69, 'BLU-004-L-C69'),
    ((SELECT id FROM producto WHERE slug = 'top-de-tirantes-de-algodon'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 69, 'BLU-004-M-C69'),
    ((SELECT id FROM producto WHERE slug = 'top-de-tirantes-de-algodon'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 69, 'BLU-004-S-C69'),
    ((SELECT id FROM producto WHERE slug = 'top-de-tirantes-de-algodon'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 69, 'BLU-004-XS-C69'),
    ((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 13, 'VES-004-L-C13'),
    ((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 13, 'VES-004-M-C13'),
    ((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 13, 'VES-004-S-C13'),
    ((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 13, 'VES-004-XS-C13'),
    ((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 60, 'VES-004-L-C60'),
    ((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 60, 'VES-004-M-C60'),
    ((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 60, 'VES-004-S-C60'),
    ((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 60, 'VES-004-XS-C60'),
    ((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 67, 'VES-004-L-C67'),
    ((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 67, 'VES-004-M-C67'),
    ((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 67, 'VES-004-S-C67'),
    ((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 67, 'VES-004-XS-C67'),
    ((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 78, 'VES-004-L-C78'),
    ((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 78, 'VES-004-M-C78'),
    ((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 78, 'VES-004-S-C78'),
    ((SELECT id FROM producto WHERE slug = 'vestido-camisero-de-lino'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 78, 'VES-004-XS-C78'),
    ((SELECT id FROM producto WHERE slug = 'vestido-de-punto-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 37, 'VES-003-L-C37'),
    ((SELECT id FROM producto WHERE slug = 'vestido-de-punto-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 37, 'VES-003-M-C37'),
    ((SELECT id FROM producto WHERE slug = 'vestido-de-punto-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 37, 'VES-003-S-C37'),
    ((SELECT id FROM producto WHERE slug = 'vestido-de-punto-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XL'), 37, 'VES-003-XL-C37'),
    ((SELECT id FROM producto WHERE slug = 'vestido-de-punto-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 40, 'VES-003-L-C40'),
    ((SELECT id FROM producto WHERE slug = 'vestido-de-punto-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 40, 'VES-003-M-C40'),
    ((SELECT id FROM producto WHERE slug = 'vestido-de-punto-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 40, 'VES-003-S-C40'),
    ((SELECT id FROM producto WHERE slug = 'vestido-de-punto-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XL'), 40, 'VES-003-XL-C40'),
    ((SELECT id FROM producto WHERE slug = 'vestido-de-punto-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 64, 'VES-003-L-C64'),
    ((SELECT id FROM producto WHERE slug = 'vestido-de-punto-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 64, 'VES-003-M-C64'),
    ((SELECT id FROM producto WHERE slug = 'vestido-de-punto-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 64, 'VES-003-S-C64'),
    ((SELECT id FROM producto WHERE slug = 'vestido-de-punto-manga-larga'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XL'), 64, 'VES-003-XL-C64'),
    ((SELECT id FROM producto WHERE slug = 'vestido-floral-manga-corta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 18, 'VES-001-L-C18'),
    ((SELECT id FROM producto WHERE slug = 'vestido-floral-manga-corta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 18, 'VES-001-M-C18'),
    ((SELECT id FROM producto WHERE slug = 'vestido-floral-manga-corta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 18, 'VES-001-S-C18'),
    ((SELECT id FROM producto WHERE slug = 'vestido-floral-manga-corta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 27, 'VES-001-L-C27'),
    ((SELECT id FROM producto WHERE slug = 'vestido-floral-manga-corta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 27, 'VES-001-M-C27'),
    ((SELECT id FROM producto WHERE slug = 'vestido-floral-manga-corta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 27, 'VES-001-S-C27'),
    ((SELECT id FROM producto WHERE slug = 'vestido-floral-manga-corta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 68, 'VES-001-L-C68'),
    ((SELECT id FROM producto WHERE slug = 'vestido-floral-manga-corta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 68, 'VES-001-M-C68'),
    ((SELECT id FROM producto WHERE slug = 'vestido-floral-manga-corta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 68, 'VES-001-S-C68'),
    ((SELECT id FROM producto WHERE slug = 'vestido-largo-estampado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 11, 'VES-006-L-C11'),
    ((SELECT id FROM producto WHERE slug = 'vestido-largo-estampado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 11, 'VES-006-M-C11'),
    ((SELECT id FROM producto WHERE slug = 'vestido-largo-estampado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 11, 'VES-006-S-C11'),
    ((SELECT id FROM producto WHERE slug = 'vestido-largo-estampado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 38, 'VES-006-L-C38'),
    ((SELECT id FROM producto WHERE slug = 'vestido-largo-estampado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 38, 'VES-006-M-C38'),
    ((SELECT id FROM producto WHERE slug = 'vestido-largo-estampado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 38, 'VES-006-S-C38'),
    ((SELECT id FROM producto WHERE slug = 'vestido-largo-estampado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 33, 'VES-006-L-C33'),
    ((SELECT id FROM producto WHERE slug = 'vestido-largo-estampado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 33, 'VES-006-M-C33'),
    ((SELECT id FROM producto WHERE slug = 'vestido-largo-estampado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 33, 'VES-006-S-C33'),
    ((SELECT id FROM producto WHERE slug = 'vestido-largo-estampado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 36, 'VES-006-L-C36'),
    ((SELECT id FROM producto WHERE slug = 'vestido-largo-estampado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 36, 'VES-006-M-C36'),
    ((SELECT id FROM producto WHERE slug = 'vestido-largo-estampado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 36, 'VES-006-S-C36'),
    ((SELECT id FROM producto WHERE slug = 'vestido-midi-plisado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 13, 'VES-002-L-C13'),
    ((SELECT id FROM producto WHERE slug = 'vestido-midi-plisado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 13, 'VES-002-M-C13'),
    ((SELECT id FROM producto WHERE slug = 'vestido-midi-plisado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 13, 'VES-002-S-C13'),
    ((SELECT id FROM producto WHERE slug = 'vestido-midi-plisado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 5, 'VES-002-L-C5'),
    ((SELECT id FROM producto WHERE slug = 'vestido-midi-plisado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 5, 'VES-002-M-C5'),
    ((SELECT id FROM producto WHERE slug = 'vestido-midi-plisado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 5, 'VES-002-S-C5'),
    ((SELECT id FROM producto WHERE slug = 'vestido-midi-plisado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 4, 'VES-002-L-C4'),
    ((SELECT id FROM producto WHERE slug = 'vestido-midi-plisado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 4, 'VES-002-M-C4'),
    ((SELECT id FROM producto WHERE slug = 'vestido-midi-plisado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 4, 'VES-002-S-C4'),
    ((SELECT id FROM producto WHERE slug = 'vestido-midi-plisado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 7, 'VES-002-L-C7'),
    ((SELECT id FROM producto WHERE slug = 'vestido-midi-plisado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 7, 'VES-002-M-C7'),
    ((SELECT id FROM producto WHERE slug = 'vestido-midi-plisado'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 7, 'VES-002-S-C7'),
    ((SELECT id FROM producto WHERE slug = 'vestido-negro-de-fiesta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 13, 'VES-005-L-C13'),
    ((SELECT id FROM producto WHERE slug = 'vestido-negro-de-fiesta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 13, 'VES-005-M-C13'),
    ((SELECT id FROM producto WHERE slug = 'vestido-negro-de-fiesta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 13, 'VES-005-S-C13'),
    ((SELECT id FROM producto WHERE slug = 'vestido-negro-de-fiesta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 13, 'VES-005-XS-C13'),
    ((SELECT id FROM producto WHERE slug = 'vestido-negro-de-fiesta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 24, 'VES-005-L-C24'),
    ((SELECT id FROM producto WHERE slug = 'vestido-negro-de-fiesta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 24, 'VES-005-M-C24'),
    ((SELECT id FROM producto WHERE slug = 'vestido-negro-de-fiesta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 24, 'VES-005-S-C24'),
    ((SELECT id FROM producto WHERE slug = 'vestido-negro-de-fiesta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 24, 'VES-005-XS-C24'),
    ((SELECT id FROM producto WHERE slug = 'vestido-negro-de-fiesta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 34, 'VES-005-L-C34'),
    ((SELECT id FROM producto WHERE slug = 'vestido-negro-de-fiesta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 34, 'VES-005-M-C34'),
    ((SELECT id FROM producto WHERE slug = 'vestido-negro-de-fiesta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 34, 'VES-005-S-C34'),
    ((SELECT id FROM producto WHERE slug = 'vestido-negro-de-fiesta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 34, 'VES-005-XS-C34'),
    ((SELECT id FROM producto WHERE slug = 'vestido-negro-de-fiesta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'L'), 77, 'VES-005-L-C77'),
    ((SELECT id FROM producto WHERE slug = 'vestido-negro-de-fiesta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'M'), 77, 'VES-005-M-C77'),
    ((SELECT id FROM producto WHERE slug = 'vestido-negro-de-fiesta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'S'), 77, 'VES-005-S-C77'),
    ((SELECT id FROM producto WHERE slug = 'vestido-negro-de-fiesta'), (SELECT id FROM talla WHERE tipo = 'LETRA' AND codigo = 'XS'), 77, 'VES-005-XS-C77'),
    ((SELECT id FROM producto WHERE slug = 'zapatilla-urbana-blanca'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '35'), 13, 'ZAP-003-35-C13'),
    ((SELECT id FROM producto WHERE slug = 'zapatilla-urbana-blanca'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '36'), 13, 'ZAP-003-36-C13'),
    ((SELECT id FROM producto WHERE slug = 'zapatilla-urbana-blanca'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '37'), 13, 'ZAP-003-37-C13'),
    ((SELECT id FROM producto WHERE slug = 'zapatilla-urbana-blanca'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '38'), 13, 'ZAP-003-38-C13'),
    ((SELECT id FROM producto WHERE slug = 'zapatilla-urbana-blanca'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '39'), 13, 'ZAP-003-39-C13'),
    ((SELECT id FROM producto WHERE slug = 'zapatilla-urbana-blanca'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '40'), 13, 'ZAP-003-40-C13'),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '35'), 13, 'ZAP-001-35-C13'),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '36'), 13, 'ZAP-001-36-C13'),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '37'), 13, 'ZAP-001-37-C13'),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '38'), 13, 'ZAP-001-38-C13'),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '39'), 13, 'ZAP-001-39-C13'),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '35'), 24, 'ZAP-001-35-C24'),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '36'), 24, 'ZAP-001-36-C24'),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '37'), 24, 'ZAP-001-37-C24'),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '38'), 24, 'ZAP-001-38-C24'),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '39'), 24, 'ZAP-001-39-C24'),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '35'), 65, 'ZAP-001-35-C65'),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '36'), 65, 'ZAP-001-36-C65'),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '37'), 65, 'ZAP-001-37-C65'),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '38'), 65, 'ZAP-001-38-C65'),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '39'), 65, 'ZAP-001-39-C65'),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '35'), 70, 'ZAP-001-35-C70'),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '36'), 70, 'ZAP-001-36-C70'),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '37'), 70, 'ZAP-001-37-C70'),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '38'), 70, 'ZAP-001-38-C70'),
    ((SELECT id FROM producto WHERE slug = 'zapato-stiletto-de-charol'), (SELECT id FROM talla WHERE tipo = 'CALZADO' AND codigo = '39'), 70, 'ZAP-001-39-C70')
;

-- El inventario de estas variantes nuevas lo llena la seccion INVENTARIO de
-- mas abajo: su INSERT ya recorre TODO producto_variante sin filtrar, asi
-- que las incluye solo con que existan antes de que corra.

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
