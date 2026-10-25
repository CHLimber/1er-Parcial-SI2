

-- =====================================================================
--  8.2.4  POBLACION
-- =====================================================================

-- ---------------------------------------------------------------------
--  8.2.4.1  INSERT
--  Orden de carga: primero lo que no depende de nada (planes, empresas, roles, permisos,
--  tallas, colores, parametria), despues la organizacion de cada empresa, el catalogo, el
--  inventario y al final los movimientos (caja, ventas, reservas, recepciones, traspasos...).
-- ---------------------------------------------------------------------

-- ===== Plataforma SaaS: planes y empresas contratantes (tenants) =====

INSERT INTO plan (codigo, nombre, descripcion, precio_mensual, max_sucursales, max_empleados,
                  max_cajas, perfiles_clientes, traspasos, operacion_offline, reportes,
                  ia_reportes, analitica_ml, orden) VALUES
    ('BASICO',      'Basico',
     'Hasta 2 sucursales: productos, ventas, reservas, operacion offline y reportes convencionales',
     350,  2, NULL, NULL, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, 1),
    ('PROFESIONAL', 'Profesional',
     'Hasta 10 sucursales: todo lo del Basico mas reportes generativos con IA y analitica de ML',
     900, 10, NULL, NULL, TRUE, TRUE, TRUE, TRUE, TRUE,  TRUE,  2);

INSERT INTO empresa (id, slug, nombre, razon_social, nit, email, telefono) VALUES
    ('e0000000-0000-4000-8000-000000000001', 'fashionstore', 'FashionStore',
     'FashionStore Bolivia S.R.L.', '1234567890', 'contacto@fashionstore.bo', '33400000'),
    ('e0000000-0000-4000-8000-000000000002', 'andina', 'Boutique Andina',
     'Boutique Andina Textiles S.R.L.', '4455667788', 'hola@andina.bo', '22790000'),
    ('e0000000-0000-4000-8000-000000000003', 'moda-urbana', 'Moda Urbana',
     'Moda Urbana Potosi S.R.L.', '9988776655', 'ventas@modaurbana.bo', '26220000');

-- FashionStore y Boutique Andina al dia; Moda Urbana con la suscripcion VENCIDA (sirve para
-- mostrar el bloqueo de funciones por falta de pago).
INSERT INTO suscripcion (empresa_id, plan_id, estado, inicio, vence_en) VALUES
    ('e0000000-0000-4000-8000-000000000001', (SELECT id FROM plan WHERE codigo = 'PROFESIONAL'),
     'ACTIVA',  now() - interval '90 days', now() + interval '30 days'),
    ('e0000000-0000-4000-8000-000000000002', (SELECT id FROM plan WHERE codigo = 'BASICO'),
     'ACTIVA',  now() - interval '40 days', now() + interval '20 days'),
    ('e0000000-0000-4000-8000-000000000003', (SELECT id FROM plan WHERE codigo = 'BASICO'),
     'VENCIDA', now() - interval '45 days', now() - interval '3 days');

-- Historial de pagos: el ultimo mes cobrado por transferencia a cada suscripcion
INSERT INTO pago_suscripcion (suscripcion_id, plan_id, meses, monto, metodo, estado,
                              periodo_desde, periodo_hasta, creado_en, confirmado_en)
SELECT su.id, su.plan_id, 1, p.precio_mensual, 'TRANSFERENCIA', 'APROBADO',
       su.vence_en - interval '1 month', su.vence_en,
       su.vence_en - interval '1 month', su.vence_en - interval '1 month'
  FROM suscripcion su
  JOIN plan p ON p.id = su.plan_id;


-- ===== Usuarios y acceso: roles del sistema, permisos y matriz rol-permiso =====

INSERT INTO rol (nombre, descripcion, es_sistema) VALUES
    ('SUPERADMIN', 'Administracion de la plataforma SaaS: empresas, planes y suscripciones', TRUE),
    ('ADMIN',      'Administracion de una empresa: todo lo de su tenant', TRUE),
    ('ENCARGADO',  'Responsable de una sucursal', TRUE),
    ('CAJERO',     'Maneja caja, ventas presenciales y verificacion de pagos', TRUE),
    ('VENDEDOR',   'Atiende clientes y reservas en tienda', TRUE),
    ('ALMACEN',    'Recibe mercaderia y controla existencias', TRUE);

-- Rol propio de una empresa (CU13): solo lo ve Boutique Andina
INSERT INTO rol (empresa_id, nombre, descripcion, es_sistema) VALUES
    ('e0000000-0000-4000-8000-000000000002', 'SUPERVISORA', 'Supervisa ventas y reservas de las dos tiendas', FALSE);

-- Codigo de permiso = "<modulo>.<accion>". La API autoriza por codigo, no por nombre de rol.
INSERT INTO permiso (codigo, modulo, descripcion) VALUES
    ('usuarios.leer',            'usuarios',      'Consultar el padron de usuarios'),
    ('usuarios.crear',           'usuarios',      'Dar de alta personal'),
    ('usuarios.actualizar',      'usuarios',      'Editar datos, rol, contrasenia o reactivar usuarios'),
    ('usuarios.eliminar',        'usuarios',      'Dar de baja usuarios'),
    ('roles.leer',               'roles',         'Consultar roles y sus permisos'),
    ('roles.crear',              'roles',         'Crear roles'),
    ('roles.actualizar',         'roles',         'Editar roles y reasignar sus permisos'),
    ('roles.eliminar',           'roles',         'Eliminar roles que no son del sistema'),
    ('catalogo.leer',            'catalogo',      'Consultar el catalogo completo, incluido lo inactivo'),
    ('catalogo.crear',           'catalogo',      'Alta de prendas, variantes, imagenes, categorias y marcas'),
    ('catalogo.actualizar',      'catalogo',      'Modificacion de prendas, variantes y categorias'),
    ('catalogo.eliminar',        'catalogo',      'Baja de prendas, variantes, categorias e imagenes'),
    ('proveedores.leer',         'proveedores',   'Consultar proveedores'),
    ('proveedores.crear',        'proveedores',   'Dar de alta proveedores'),
    ('proveedores.actualizar',   'proveedores',   'Editar o reactivar proveedores'),
    ('proveedores.eliminar',     'proveedores',   'Dar de baja proveedores'),
    ('sucursales.leer',          'sucursales',    'Consultar sucursales y cajas'),
    ('sucursales.crear',         'sucursales',    'Dar de alta sucursales y cajas'),
    ('sucursales.actualizar',    'sucursales',    'Editar o reactivar sucursales y cajas'),
    ('sucursales.eliminar',      'sucursales',    'Dar de baja sucursales y cajas'),
    ('inventario.leer',          'inventario',    'Consultar existencias y kardex'),
    ('inventario.actualizar',    'inventario',    'Registrar ajustes manuales de stock'),
    ('recepciones.leer',         'recepciones',   'Consultar recepciones de mercaderia'),
    ('recepciones.crear',        'recepciones',   'Crear una recepcion y cargar lineas al borrador'),
    ('recepciones.actualizar',   'recepciones',   'Editar lineas del borrador y confirmar la recepcion'),
    ('recepciones.eliminar',     'recepciones',   'Quitar lineas del borrador y anular una recepcion'),
    ('reservas.leer',            'reservas',      'Consultar la cola de reservas de la sucursal'),
    ('reservas.actualizar',      'reservas',      'Atender reservas de su sucursal: confirmar, rechazar, preparar, resolver'),
    ('caja.leer',                'caja',          'Consultar el estado de las cajas'),
    ('caja.crear',               'caja',          'Operar la caja: abrir sesion, vender, verificar pagos QR/efectivo'),
    ('caja.actualizar',          'caja',          'Cerrar una sesion de caja'),
    ('ventas.leer',              'ventas',        'Consultar ventas'),
    ('ventas.crear',             'ventas',        'Registrar ventas presenciales'),
    ('reportes.leer',            'reportes',      'Consultar los tableros de gestion'),
    ('auditoria.leer',           'auditoria',     'Consultar la bitacora de auditoria del sistema'),
    ('envios.leer',              'envios',        'Consultar los envios a domicilio y su estado de despacho'),
    ('envios.actualizar',        'envios',        'Marcar un envio como despachado, entregado o fallido'),
    ('devoluciones.leer',        'devoluciones',  'Consultar las devoluciones de ventas de la sucursal'),
    ('devoluciones.crear',       'devoluciones',  'Registrar una devolucion sobre una venta pagada'),
    ('devoluciones.actualizar',  'devoluciones',  'Aprobar (reingresa el stock) o rechazar una devolucion'),
    ('traspasos.leer',           'traspasos',     'Consultar los traspasos que salen o llegan a la sucursal'),
    ('traspasos.crear',          'traspasos',     'Solicitar un traspaso desde la propia sucursal a otra'),
    ('traspasos.actualizar',     'traspasos',     'Despachar un traspaso o recibirlo en destino'),
    ('traspasos.eliminar',       'traspasos',     'Anular un traspaso solicitado o en transito'),
    ('suscripciones.leer',       'suscripciones', 'Consultar el plan, la suscripcion y el uso de la empresa'),
    ('suscripciones.actualizar', 'suscripciones', 'Cambiar de plan y pagar la suscripcion de la empresa'),
    ('clientes.leer',            'clientes',      'Consultar la cartera de clientas de la empresa'),
    ('clientes.actualizar',      'clientes',      'Editar el perfil de una clienta en la empresa'),
    ('sincronizacion.leer',      'sincronizacion','Consultar las operaciones offline sincronizadas y sus conflictos'),
    ('sincronizacion.actualizar','sincronizacion','Resolver conflictos de sincronizacion'),
    ('analitica.leer',           'analitica',     'Consultar el dashboard analitico (machine learning)'),
    ('analitica.actualizar',     'analitica',     'Reentrenar los modelos de machine learning'),
    ('empresas.leer',            'empresas',      'Consultar las empresas contratantes de la plataforma'),
    ('empresas.crear',           'empresas',      'Registrar una empresa contratante con su administrador'),
    ('empresas.actualizar',      'empresas',      'Editar, suspender o reactivar una empresa y asignarle plan'),
    ('planes.actualizar',        'planes',        'Configurar precio, limites y funciones de los planes');

-- ADMIN de empresa: todo lo de su tenant menos lo de la plataforma
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'ADMIN' AND empresa_id IS NULL), p.id
  FROM permiso p
 WHERE p.modulo NOT IN ('empresas', 'planes');

-- SUPERADMIN: empresas, planes, suscripciones, bitacora y reentrenamiento de modelos
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'SUPERADMIN'), p.id
  FROM permiso p
 WHERE p.modulo IN ('empresas', 'planes')
    OR p.codigo IN ('suscripciones.leer', 'suscripciones.actualizar', 'auditoria.leer',
                    'analitica.leer', 'analitica.actualizar');

-- ENCARGADO: manda en su sucursal; tambien puede cubrir la caja
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'ENCARGADO'), p.id
  FROM permiso p
 WHERE p.codigo IN ('usuarios.leer','catalogo.leer','proveedores.leer','sucursales.leer',
                    'inventario.leer','inventario.actualizar',
                    'recepciones.leer','recepciones.crear','recepciones.actualizar','recepciones.eliminar',
                    'reservas.leer','reservas.actualizar',
                    'caja.leer','caja.crear','caja.actualizar','ventas.crear','reportes.leer',
                    'envios.leer','envios.actualizar',
                    'devoluciones.leer','devoluciones.crear','devoluciones.actualizar',
                    'traspasos.leer','traspasos.crear','traspasos.actualizar','traspasos.eliminar',
                    'suscripciones.leer','clientes.leer','clientes.actualizar',
                    'sincronizacion.leer','sincronizacion.actualizar','analitica.leer');

-- CAJERO: caja, punto de venta y verificacion de pagos online
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'CAJERO'), p.id
  FROM permiso p
 WHERE p.codigo IN ('catalogo.leer','inventario.leer','caja.leer','caja.crear','caja.actualizar',
                    'ventas.crear','clientes.leer','sincronizacion.leer');

-- ALMACEN: entrada de mercaderia
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'ALMACEN'), p.id
  FROM permiso p
 WHERE p.codigo IN ('catalogo.leer','proveedores.leer','inventario.leer','inventario.actualizar',
                    'recepciones.leer','recepciones.crear','recepciones.actualizar','recepciones.eliminar');

-- VENDEDOR: piso de venta y vestidores
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'VENDEDOR'), p.id
  FROM permiso p
 WHERE p.codigo IN ('catalogo.leer','inventario.leer','reservas.leer','reservas.actualizar',
                    'clientes.leer','sincronizacion.leer');

-- Rol propio SUPERVISORA de Boutique Andina
INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT (SELECT id FROM rol WHERE nombre = 'SUPERVISORA'), p.id
  FROM permiso p
 WHERE p.codigo IN ('catalogo.leer','reservas.leer','ventas.leer','reportes.leer');


-- ===== Datos de referencia de la plataforma: tallas, colores y parametria =====

-- Curva de tallas femenina: LETRA (superior y vestidos), NUMERO (pantalones), CALZADO
INSERT INTO talla (codigo, tipo, orden) VALUES
    ('XS', 'LETRA', 0), ('S', 'LETRA', 1), ('M', 'LETRA', 2), ('L', 'LETRA', 3),
    ('XL', 'LETRA', 4), ('XXL', 'LETRA', 5), ('UNICA', 'LETRA', 0),
    ('36', 'NUMERO', 1), ('38', 'NUMERO', 2), ('40', 'NUMERO', 3), ('42', 'NUMERO', 4),
    ('44', 'NUMERO', 5), ('46', 'NUMERO', 6),
    ('35', 'CALZADO', 1), ('36', 'CALZADO', 2), ('37', 'CALZADO', 3), ('38', 'CALZADO', 4),
    ('39', 'CALZADO', 5), ('40', 'CALZADO', 6);

INSERT INTO color (nombre, codigo_hex) VALUES
    ('Negro', '#000000'), ('Blanco', '#FFFFFF'), ('Azul', '#1E3A8A'), ('Rojo', '#DC2626'),
    ('Gris', '#6B7280'), ('Beige', '#D2B48C'), ('Verde Oliva', '#556B2F'),
    ('Rosa Palo', '#E8B4B8'), ('Camel', '#C19A6B'), ('Vino', '#722F37');

INSERT INTO configuracion (clave, valor, descripcion) VALUES
    ('reserva_horas_vigencia',        '4',   'Horas antes de que una reserva pendiente expire automaticamente'),
    ('pago_pendiente_horas_vigencia', '48',  'Horas antes de anular un pedido online en efectivo/QR sin pagar'),
    ('devolucion_plazo_dias',         '30',  'Dias desde la venta para aceptar una devolucion'),
    ('cambio_plazo_dias',             '15',  'Dias desde la venta para aceptar un cambio por talla o color'),
    ('delivery_tarifa_base',          '8',   'Bs fijos por salida de reparto'),
    ('delivery_precio_km',            '3.5', 'Bs por kilometro de ruta entre la sucursal y el domicilio'),
    ('delivery_costo_minimo',         '10',  'Piso de la tarifa de delivery en Bs'),
    ('delivery_radio_km',             '12',  'Radio maximo de reparto de una sucursal, en km'),
    ('delivery_gratis_desde',         '800', 'Monto de compra en Bs desde el que el envio es gratis'),
    ('login_max_intentos',            '5',   'Intentos fallidos de login antes de bloquear la cuenta'),
    ('login_bloqueo_minutos',         '15',  'Minutos que la cuenta queda bloqueada');


-- ===== Organizacion: sucursales y cajas de cada empresa =====

-- FashionStore: 6 sucursales en climas distintos (de ahi que el stock viva por sucursal)
INSERT INTO sucursal (empresa_id, codigo, nombre, ciudad, direccion, latitud, longitud,
                      hora_apertura, hora_cierre, cantidad_vestidores) VALUES
    ('e0000000-0000-4000-8000-000000000001', 'SC-01', 'FashionStore Equipetrol', 'SANTA_CRUZ',
     'Av. San Martin #100', -17.7620000, -63.1970000, '09:00', '20:00', 3),
    ('e0000000-0000-4000-8000-000000000001', 'LP-01', 'FashionStore Sopocachi', 'LA_PAZ',
     'Av. 6 de Agosto #2050', -16.5090000, -68.1290000, '09:30', '19:30', 2),
    ('e0000000-0000-4000-8000-000000000001', 'CB-01', 'FashionStore Cala Cala', 'COCHABAMBA',
     'Av. America Este #480', -17.3660000, -66.1540000, '09:00', '20:00', 2),
    ('e0000000-0000-4000-8000-000000000001', 'SU-01', 'FashionStore Sucre Centro', 'SUCRE',
     'Calle Arenales #45', -19.0476000, -65.2600000, '09:00', '19:30', 1),
    ('e0000000-0000-4000-8000-000000000001', 'TJ-01', 'FashionStore Tarija Las Panosas', 'TARIJA',
     'Av. Las Americas #310', -21.5355000, -64.7296000, '09:00', '20:00', 2),
    ('e0000000-0000-4000-8000-000000000001', 'OR-01', 'FashionStore Oruro Bolivar', 'ORURO',
     'Calle Bolivar #620', -17.9667000, -67.1060000, '09:30', '19:00', 1),
-- Boutique Andina: 2 sucursales (el tope del plan Basico)
    ('e0000000-0000-4000-8000-000000000002', 'AN-LP1', 'Andina San Miguel', 'LA_PAZ',
     'Calle 21 de Calacoto #8050', -16.5410000, -68.0790000, '10:00', '20:00', 2),
    ('e0000000-0000-4000-8000-000000000002', 'AN-EA1', 'Andina Ceja El Alto', 'EL_ALTO',
     'Av. 6 de Marzo #1200', -16.5050000, -68.1630000, '09:00', '19:00', 1),
-- Moda Urbana: 1 sucursal
    ('e0000000-0000-4000-8000-000000000003', 'MU-PT1', 'Moda Urbana Potosi', 'POTOSI',
     'Calle Sucre #30', -19.5890000, -65.7530000, '09:30', '19:30', 1);

INSERT INTO caja (sucursal_id, codigo, nombre)
SELECT s.id, 'CAJA-01', 'Caja principal ' || s.nombre
  FROM sucursal s;


-- ===== Usuarios: personal (STAFF) de cada empresa, SUPERADMIN y clientas =====

INSERT INTO usuario (email, password_hash, nombre, apellido, tipo, rol_id, empresa_id, email_verificado)
SELECT x.email, crypt('demo1234', gen_salt('bf')), x.nombre, x.apellido, 'STAFF',
       (SELECT id FROM rol WHERE nombre = x.rol AND empresa_id IS NULL), x.empresa::uuid, TRUE
  FROM (VALUES
    ('admin@fashionstore.bo',            'Admin',    'Sistema',   'ADMIN',     'e0000000-0000-4000-8000-000000000001'),
    ('cajera.scz@fashionstore.bo',       'Camila',   'Rocha',     'CAJERO',    'e0000000-0000-4000-8000-000000000001'),
    ('vendedor.scz@fashionstore.bo',     'Daniela',  'Vargas',    'VENDEDOR',  'e0000000-0000-4000-8000-000000000001'),
    ('almacen.scz@fashionstore.bo',      'Marco',    'Gutierrez', 'ALMACEN',   'e0000000-0000-4000-8000-000000000001'),
    ('encargada.lapaz@fashionstore.bo',  'Mariana',  'Quispe',    'ENCARGADO', 'e0000000-0000-4000-8000-000000000001'),
    ('cajera.lapaz@fashionstore.bo',     'Lucia',    'Condori',   'CAJERO',    'e0000000-0000-4000-8000-000000000001'),
    ('encargado.cbba@fashionstore.bo',   'Ruben',    'Mamani',    'ENCARGADO', 'e0000000-0000-4000-8000-000000000001'),
    ('cajero.cbba@fashionstore.bo',      'Jorge',    'Fernandez', 'CAJERO',    'e0000000-0000-4000-8000-000000000001'),
    ('encargada.sucre@fashionstore.bo',  'Paola',    'Arancibia', 'ENCARGADO', 'e0000000-0000-4000-8000-000000000001'),
    ('cajero.sucre@fashionstore.bo',     'Diego',    'Salazar',   'CAJERO',    'e0000000-0000-4000-8000-000000000001'),
    ('encargada.tarija@fashionstore.bo', 'Natalia',  'Arce',      'ENCARGADO', 'e0000000-0000-4000-8000-000000000001'),
    ('cajera.tarija@fashionstore.bo',    'Gabriela', 'Paz',       'CAJERO',    'e0000000-0000-4000-8000-000000000001'),
    ('encargado.oruro@fashionstore.bo',  'Hugo',     'Choque',    'ENCARGADO', 'e0000000-0000-4000-8000-000000000001'),
    ('cajera.oruro@fashionstore.bo',     'Rosa',     'Mamani',    'CAJERO',    'e0000000-0000-4000-8000-000000000001'),
    ('admin@andina.bo',                  'Ximena',   'Apaza',     'ADMIN',     'e0000000-0000-4000-8000-000000000002'),
    ('encargada.sanmiguel@andina.bo',    'Carla',    'Mendoza',   'ENCARGADO', 'e0000000-0000-4000-8000-000000000002'),
    ('cajero.sanmiguel@andina.bo',       'Iver',     'Quisbert',  'CAJERO',    'e0000000-0000-4000-8000-000000000002'),
    ('cajera.elalto@andina.bo',          'Wara',     'Ticona',    'CAJERO',    'e0000000-0000-4000-8000-000000000002'),
    ('admin@modaurbana.bo',              'Sergio',   'Flores',    'ADMIN',     'e0000000-0000-4000-8000-000000000003')
  ) AS x(email, nombre, apellido, rol, empresa);

-- El administrador de la PLATAFORMA no pertenece a ninguna empresa (empresa_id NULL)
INSERT INTO usuario (email, password_hash, nombre, apellido, tipo, rol_id, email_verificado)
VALUES ('superadmin@fashionstore.bo', crypt('demo1234', gen_salt('bf')), 'Plataforma', 'SaaS',
        'STAFF', (SELECT id FROM rol WHERE nombre = 'SUPERADMIN'), TRUE);

-- Clientas: su cuenta es de la plataforma (empresa_id NULL), compran en cualquier tienda
INSERT INTO usuario (email, password_hash, nombre, apellido, telefono, tipo, email_verificado) VALUES
    ('cliente@fashionstore.bo',  crypt('demo1234', gen_salt('bf')), 'Cliente', 'Demo',    '70012345', 'CLIENTE', TRUE),
    ('cliente2@fashionstore.bo', crypt('demo1234', gen_salt('bf')), 'Valeria', 'Rojas',   '70067890', 'CLIENTE', TRUE),
    ('andrea.lopez@gmail.com',   crypt('demo1234', gen_salt('bf')), 'Andrea',  'Lopez',   '71234567', 'CLIENTE', FALSE);

-- Cada usuario STAFF de empresa queda atado a una sucursal
INSERT INTO empleado (usuario_id, sucursal_id, ci, cargo, fecha_ingreso)
SELECT u.id, s.id, x.ci, x.cargo::cargo_empleado, CURRENT_DATE - x.antiguedad
  FROM (VALUES
    ('admin@fashionstore.bo',            'SC-01',  '6543210', 'ENCARGADO', 400),
    ('cajera.scz@fashionstore.bo',       'SC-01',  '7123456', 'CAJERO',    300),
    ('vendedor.scz@fashionstore.bo',     'SC-01',  '7234567', 'VENDEDOR',  200),
    ('almacen.scz@fashionstore.bo',      'SC-01',  '7345678', 'ALMACEN',   250),
    ('encargada.lapaz@fashionstore.bo',  'LP-01',  '4456789', 'ENCARGADO', 380),
    ('cajera.lapaz@fashionstore.bo',     'LP-01',  '4567890', 'CAJERO',    150),
    ('encargado.cbba@fashionstore.bo',   'CB-01',  '5678901', 'ENCARGADO', 360),
    ('cajero.cbba@fashionstore.bo',      'CB-01',  '5789012', 'CAJERO',    120),
    ('encargada.sucre@fashionstore.bo',  'SU-01',  '3890123', 'ENCARGADO', 90),
    ('cajero.sucre@fashionstore.bo',     'SU-01',  '3901234', 'CAJERO',    90),
    ('encargada.tarija@fashionstore.bo', 'TJ-01',  '5012345', 'ENCARGADO', 90),
    ('cajera.tarija@fashionstore.bo',    'TJ-01',  '5123456', 'CAJERO',    90),
    ('encargado.oruro@fashionstore.bo',  'OR-01',  '4234567', 'ENCARGADO', 90),
    ('cajera.oruro@fashionstore.bo',     'OR-01',  '4345678', 'CAJERO',    90),
    ('admin@andina.bo',                  'AN-LP1', '2345678', 'ENCARGADO', 60),
    ('encargada.sanmiguel@andina.bo',    'AN-LP1', '2456789', 'ENCARGADO', 60),
    ('cajero.sanmiguel@andina.bo',       'AN-LP1', '2567890', 'CAJERO',    60),
    ('cajera.elalto@andina.bo',          'AN-EA1', '2678901', 'CAJERO',    60),
    ('admin@modaurbana.bo',              'MU-PT1', '8789012', 'ENCARGADO', 45)
  ) AS x(email, sucursal, ci, cargo, antiguedad)
  JOIN usuario  u ON u.email  = x.email
  JOIN sucursal s ON s.codigo = x.sucursal;

-- Preferencias declaradas por la clienta (alimentan las recomendaciones)
INSERT INTO perfil_cliente (usuario_id, talla_superior_id, talla_inferior_id, talla_calzado_id,
                            color_favorito_id, fecha_nacimiento, puntos_fidelidad, acepta_marketing)
VALUES
    ((SELECT id FROM usuario WHERE email = 'cliente@fashionstore.bo'),
     (SELECT id FROM talla WHERE codigo = 'M'  AND tipo = 'LETRA'),
     (SELECT id FROM talla WHERE codigo = '40' AND tipo = 'NUMERO'),
     (SELECT id FROM talla WHERE codigo = '37' AND tipo = 'CALZADO'),
     (SELECT id FROM color WHERE nombre = 'Azul'), '1998-05-14', 120, TRUE),
    ((SELECT id FROM usuario WHERE email = 'cliente2@fashionstore.bo'),
     (SELECT id FROM talla WHERE codigo = 'S'  AND tipo = 'LETRA'),
     (SELECT id FROM talla WHERE codigo = '38' AND tipo = 'NUMERO'),
     (SELECT id FROM talla WHERE codigo = '36' AND tipo = 'CALZADO'),
     (SELECT id FROM color WHERE nombre = 'Negro'), '2001-11-02', 40, FALSE);

-- Libreta de direcciones con coordenadas (CU20: base de la tarifa del delivery)
INSERT INTO direccion (usuario_id, alias, ciudad, direccion, referencia, latitud, longitud, es_principal) VALUES
    ((SELECT id FROM usuario WHERE email = 'cliente@fashionstore.bo'),
     'Casa', 'SANTA_CRUZ', 'Calle Beni #345', 'Porton verde, frente a la plaza',
     -17.7810000, -63.1790000, TRUE),
    ((SELECT id FROM usuario WHERE email = 'cliente@fashionstore.bo'),
     'Trabajo', 'SANTA_CRUZ', 'Av. Cristobal de Mendoza #1200', 'Edificio Torre Sur, piso 4',
     -17.7745000, -63.1846000, FALSE),
    ((SELECT id FROM usuario WHERE email = 'cliente2@fashionstore.bo'),
     'Oficina', 'LA_PAZ', 'Calle Sagarnaga #220', 'A media cuadra de la iglesia',
     -16.4970000, -68.1380000, TRUE);

-- Ficha de la clienta segun cada empresa (cartera por tenant)
INSERT INTO cliente_perfil_tenant (empresa_id, usuario_id, segmento, talla_habitual,
                                   estilo_preferido, acepta_whatsapp, notas) VALUES
    ('e0000000-0000-4000-8000-000000000001', (SELECT id FROM usuario WHERE email = 'cliente@fashionstore.bo'),
     'FRECUENTE', 'M', 'Casual / oficina', TRUE,
     'Prefiere colores claros; avisarle cuando entren vestidos de la coleccion Llanura.'),
    ('e0000000-0000-4000-8000-000000000001', (SELECT id FROM usuario WHERE email = 'cliente2@fashionstore.bo'),
     'NUEVA', 'S', 'Urbano', FALSE, NULL),
    ('e0000000-0000-4000-8000-000000000002', (SELECT id FROM usuario WHERE email = 'cliente2@fashionstore.bo'),
     'NUEVA', 'S', 'Tejidos', TRUE, 'Pregunto por ponchos de alpaca en color vino.');

-- Sesion de acceso registrada (token revocado al cerrar sesion)
INSERT INTO sesion_token (usuario_id, token_hash, expira_en, ip, user_agent, revocado) VALUES
    ((SELECT id FROM usuario WHERE email = 'cliente@fashionstore.bo'),
     encode(digest('token-demo-1', 'sha256'), 'hex'), now() + interval '7 days',
     '181.115.10.20', 'Mozilla/5.0 (Android 14)', TRUE);


-- ===== Catalogo: proveedores, categorias, marcas, temporadas y colecciones =====

INSERT INTO proveedor (empresa_id, nombre, nit, contacto, email, telefono) VALUES
    ('e0000000-0000-4000-8000-000000000001', 'Textiles Andinos SRL', '890111222', 'Rene Choque',
     'ventas@textilesandinos.bo', '70011122'),
    ('e0000000-0000-4000-8000-000000000001', 'Urban Import Bolivia', '890333444', 'Diego Salazar',
     'contacto@urbanimport.bo', '70033344'),
    ('e0000000-0000-4000-8000-000000000002', 'Tejidos Altiplano', '330011223', 'Felix Mamani',
     'pedidos@tejidosaltiplano.bo', '71122334');

-- Categorias raiz y subcategorias (relacion recursiva categoria_padre_id)
INSERT INTO categoria (empresa_id, nombre, slug, orden) VALUES
    ('e0000000-0000-4000-8000-000000000001', 'Ropa',       'ropa',       1),
    ('e0000000-0000-4000-8000-000000000001', 'Calzado',    'calzado',    2),
    ('e0000000-0000-4000-8000-000000000001', 'Accesorios', 'accesorios', 3);

INSERT INTO categoria (empresa_id, categoria_padre_id, nombre, slug, orden)
SELECT 'e0000000-0000-4000-8000-000000000001', padre.id, x.nombre, x.slug, x.orden
  FROM (VALUES ('ropa', 'Blusas', 'blusas', 1), ('ropa', 'Pantalones', 'pantalones', 2),
               ('ropa', 'Vestidos', 'vestidos', 3), ('ropa', 'Abrigos', 'abrigos', 4),
               ('ropa', 'Faldas', 'faldas', 5), ('calzado', 'Botas', 'botas', 1),
               ('calzado', 'Sandalias', 'sandalias', 2)) AS x(padre, nombre, slug, orden)
  JOIN categoria padre ON padre.slug = x.padre
                      AND padre.empresa_id = 'e0000000-0000-4000-8000-000000000001';

-- Mismo slug que en FashionStore: la unicidad es (empresa_id, slug)
INSERT INTO categoria (empresa_id, nombre, slug) VALUES
    ('e0000000-0000-4000-8000-000000000002', 'Abrigos',    'abrigos'),
    ('e0000000-0000-4000-8000-000000000002', 'Tejidos',    'tejidos'),
    ('e0000000-0000-4000-8000-000000000002', 'Accesorios', 'accesorios');

INSERT INTO marca (empresa_id, nombre) VALUES
    ('e0000000-0000-4000-8000-000000000001', 'FashionStore Esencial'),
    ('e0000000-0000-4000-8000-000000000001', 'Andina Denim'),
    ('e0000000-0000-4000-8000-000000000001', 'Aurora Bolivia'),
    ('e0000000-0000-4000-8000-000000000002', 'Andina Alpaca');

INSERT INTO temporada (empresa_id, nombre, tipo, fecha_inicio, fecha_fin, activa) VALUES
    ('e0000000-0000-4000-8000-000000000001', 'Otonio-Invierno 2026',  'OTONO_INVIERNO',   '2026-03-01', '2026-08-31', FALSE),
    ('e0000000-0000-4000-8000-000000000001', 'Primavera-Verano 2026', 'PRIMAVERA_VERANO', '2026-09-01', '2027-02-28', TRUE),
    ('e0000000-0000-4000-8000-000000000002', 'Invierno Andino 2026',  'OTONO_INVIERNO',   '2026-04-01', '2026-12-31', TRUE);

INSERT INTO coleccion (empresa_id, temporada_id, proveedor_id, nombre, descripcion, anio) VALUES
    ('e0000000-0000-4000-8000-000000000001',
     (SELECT id FROM temporada WHERE nombre = 'Otonio-Invierno 2026'),
     (SELECT id FROM proveedor WHERE nombre = 'Textiles Andinos SRL'),
     'Coleccion Altiplano 2026', 'Abrigo y tejidos para el frio de altura; su peso esta en La Paz.', 2026),
    ('e0000000-0000-4000-8000-000000000001',
     (SELECT id FROM temporada WHERE nombre = 'Primavera-Verano 2026'),
     (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
     'Coleccion Llanura 2026', 'Prendas livianas para clima calido; su peso esta en Santa Cruz.', 2026);


-- ===== Productos (la prenda descriptiva) =====

-- FashionStore: 2 prendas de Primavera-Verano, 3 de Otonio-Invierno y 1 atemporal (sin temporada)
INSERT INTO producto (empresa_id, categoria_id, marca_id, proveedor_id, temporada_id, coleccion_id,
                      codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
SELECT 'e0000000-0000-4000-8000-000000000001', c.id, m.id, pr.id, t.id, co.id,
       x.codigo, x.nombre, x.slug, x.descripcion, x.material, 'MUJER', x.precio, x.destacado
  FROM (VALUES
    ('BLU-001', 'Blusa de Lino Manga Corta', 'blusa-de-lino-manga-corta', 'blusas',
     'Aurora Bolivia', 'Urban Import Bolivia', 'Primavera-Verano 2026', 'Coleccion Llanura 2026',
     'Blusa fresca de lino, corte holgado y escote en V.', 'Lino 100%', 159.90, TRUE),
    ('VES-001', 'Vestido Floral Manga Corta', 'vestido-floral-manga-corta', 'vestidos',
     'FashionStore Esencial', NULL, 'Primavera-Verano 2026', 'Coleccion Llanura 2026',
     'Vestido liviano estampado floral, ideal para clima calido.', 'Viscosa', 179.90, TRUE),
    ('PAN-001', 'Jean Tiro Alto Skinny', 'jean-tiro-alto-skinny', 'pantalones',
     'Andina Denim', 'Textiles Andinos SRL', NULL, NULL,
     'Jean de tiro alto con elastano, corte skinny que estiliza la silueta.',
     'Denim 98% algodon 2% elastano', 249.90, TRUE),
    ('ABR-001', 'Tapado de Lana Largo', 'tapado-de-lana-largo', 'abrigos',
     'FashionStore Esencial', 'Textiles Andinos SRL', 'Otonio-Invierno 2026', 'Coleccion Altiplano 2026',
     'Tapado largo de pano de lana con cinturon, pensado para el frio de altura.',
     'Lana 70% poliester 30%', 449.90, TRUE),
    ('BOT-001', 'Botineta de Cuero con Taco', 'botineta-de-cuero-con-taco', 'botas',
     'Aurora Bolivia', 'Urban Import Bolivia', 'Otonio-Invierno 2026', 'Coleccion Altiplano 2026',
     'Botineta de cuero con taco bajo y cierre lateral.', 'Cuero vacuno', 389.90, TRUE),
    ('ACC-001', 'Chalina de Alpaca', 'chalina-de-alpaca', 'accesorios',
     'FashionStore Esencial', NULL, 'Otonio-Invierno 2026', 'Coleccion Altiplano 2026',
     'Chalina tejida en mezcla de alpaca, talla unica.', 'Alpaca 50% acrilico 50%', 89.90, FALSE)
  ) AS x(codigo, nombre, slug, cat, marca, proveedor, temporada, coleccion, descripcion, material, precio, destacado)
  JOIN categoria c       ON c.slug = x.cat AND c.empresa_id = 'e0000000-0000-4000-8000-000000000001'
  JOIN marca m           ON m.nombre = x.marca
  LEFT JOIN proveedor pr ON pr.nombre = x.proveedor
  LEFT JOIN temporada t  ON t.nombre = x.temporada
  LEFT JOIN coleccion co ON co.nombre = x.coleccion;

-- Boutique Andina: catalogo propio de tejidos de altura
INSERT INTO producto (empresa_id, categoria_id, marca_id, proveedor_id, temporada_id,
                      codigo, nombre, slug, descripcion, material, genero, precio_base, destacado)
SELECT 'e0000000-0000-4000-8000-000000000002', c.id, m.id, pr.id, t.id,
       x.codigo, x.nombre, x.slug, x.descripcion, x.material, 'MUJER', x.precio, x.destacado
  FROM (VALUES
    ('AND-001', 'Poncho de Alpaca Tejido', 'poncho-de-alpaca-tejido', 'abrigos',
     'Poncho tejido a mano con guarda andina, abrigado y liviano.', 'Alpaca 100%', 420.00, TRUE),
    ('AND-002', 'Chompa de Alpaca Cuello Alto', 'chompa-de-alpaca-cuello-alto', 'tejidos',
     'Chompa de punto grueso con cuello alto, ideal para El Alto.', 'Alpaca 70% lana 30%', 290.00, TRUE),
    ('AND-004', 'Chalina Andina con Flecos', 'chalina-andina-con-flecos', 'accesorios',
     'Chalina con flecos y diseno de aguayo.', 'Alpaca 50% acrilico 50%', 120.00, FALSE)
  ) AS x(codigo, nombre, slug, cat, descripcion, material, precio, destacado)
  JOIN categoria c  ON c.slug = x.cat AND c.empresa_id = 'e0000000-0000-4000-8000-000000000002'
  JOIN marca m      ON m.empresa_id  = 'e0000000-0000-4000-8000-000000000002'
  JOIN proveedor pr ON pr.empresa_id = 'e0000000-0000-4000-8000-000000000002'
  JOIN temporada t  ON t.empresa_id  = 'e0000000-0000-4000-8000-000000000002';


-- ===== Variantes (producto x talla x color): la unidad que se reserva, vende e inventaria =====
-- SKU = codigo del producto - talla - 3 primeras letras del color (ej. BLU-001-M-Bla)

INSERT INTO producto_variante (producto_id, talla_id, color_id, sku)
SELECT p.id, t.id, c.id, p.codigo || '-' || t.codigo || '-' || left(c.nombre, 3)
  FROM (VALUES
    ('BLU-001', 'LETRA',   ARRAY['XS','S','M','L'],               ARRAY['Blanco','Rosa Palo','Negro']),
    ('VES-001', 'LETRA',   ARRAY['S','M','L'],                    ARRAY['Rojo','Negro','Beige']),
    ('PAN-001', 'NUMERO',  ARRAY['36','38','40','42','44'],       ARRAY['Azul','Negro','Gris']),
    ('ABR-001', 'LETRA',   ARRAY['S','M','L','XL'],               ARRAY['Negro','Camel','Vino']),
    ('BOT-001', 'CALZADO', ARRAY['35','36','37','38','39','40'],  ARRAY['Negro','Camel']),
    ('ACC-001', 'LETRA',   ARRAY['UNICA'],                        ARRAY['Gris','Beige','Vino']),
    ('AND-001', 'LETRA',   ARRAY['S','M','L'],                    ARRAY['Gris','Camel','Vino']),
    ('AND-002', 'LETRA',   ARRAY['S','M','L'],                    ARRAY['Gris','Camel','Vino']),
    ('AND-004', 'LETRA',   ARRAY['UNICA'],                        ARRAY['Gris','Camel','Vino'])
  ) AS x(codigo, tipo_talla, tallas, colores)
  JOIN producto p ON p.codigo = x.codigo
  JOIN talla t    ON t.tipo = x.tipo_talla::tipo_talla AND t.codigo = ANY (x.tallas)
  JOIN color c    ON c.nombre = ANY (x.colores);

-- Precio de oferta puntual en una variante (el resto usa el precio_base del producto)
UPDATE producto_variante SET precio_oferta = 69.90 WHERE sku = 'ACC-001-UNICA-Vin';

-- Una foto de catalogo por producto y el overlay del vestidor virtual (RA) de la blusa
INSERT INTO producto_imagen (producto_id, uso, url, formato, es_principal, orden)
SELECT p.id, 'CATALOGO', 'http://localhost:8081/media/catalogo/' || p.slug || '.jpg', 'JPG', TRUE, 0
  FROM producto p;

INSERT INTO producto_imagen (producto_id, color_id, uso, url, formato, anclajes, escala_base, es_principal, orden)
VALUES ((SELECT id FROM producto WHERE codigo = 'BLU-001'),
        (SELECT id FROM color WHERE nombre = 'Blanco'), 'AR_OVERLAY',
        'http://localhost:8081/media/ar/blu-001-overlay.png', 'PNG',
        '{"hombro_izq": [0.18, 0.12], "hombro_der": [0.82, 0.12]}', 1.000, FALSE, 1);


-- ===== Inventario inicial por sucursal, repartido segun el clima de cada ciudad =====
--   CALIDO (Santa Cruz) pesa Primavera-Verano, FRIO (La Paz, El Alto, Oruro, Potosi) pesa
--   Otonio-Invierno, TEMPLADO (Cochabamba, Sucre, Tarija) va equilibrado; lo atemporal rota parejo.

INSERT INTO inventario (sucursal_id, variante_id, cantidad_fisica, stock_minimo, ubicacion)
SELECT s.id, pv.id,
       CASE
           WHEN cl.clima = 'CALIDO'   AND t.tipo = 'PRIMAVERA_VERANO' THEN 22
           WHEN cl.clima = 'CALIDO'   AND t.tipo = 'OTONO_INVIERNO'   THEN 3
           WHEN cl.clima = 'FRIO'     AND t.tipo = 'OTONO_INVIERNO'   THEN 20
           WHEN cl.clima = 'FRIO'     AND t.tipo = 'PRIMAVERA_VERANO' THEN 3
           WHEN cl.clima = 'TEMPLADO' AND t.tipo IS NOT NULL          THEN 10
           ELSE 12
       END,
       CASE
           WHEN cl.clima = 'CALIDO' AND t.tipo = 'OTONO_INVIERNO'   THEN 1
           WHEN cl.clima = 'FRIO'   AND t.tipo = 'PRIMAVERA_VERANO' THEN 1
           ELSE 5
       END,
       'Estante ' || upper(left(p.codigo, 3))
  FROM producto_variante pv
  JOIN producto p ON p.id = pv.producto_id
  JOIN sucursal s ON s.empresa_id = p.empresa_id      -- cada empresa solo en sus sucursales
  CROSS JOIN LATERAL (SELECT CASE
          WHEN s.ciudad IN ('SANTA_CRUZ','TRINIDAD','COBIJA')    THEN 'CALIDO'
          WHEN s.ciudad IN ('LA_PAZ','EL_ALTO','ORURO','POTOSI') THEN 'FRIO'
          ELSE 'TEMPLADO' END AS clima) cl
  LEFT JOIN temporada t ON t.id = p.temporada_id;


-- ===== Promociones =====

INSERT INTO promocion (empresa_id, nombre, codigo_cupon, tipo, valor, alcance, temporada_id,
                       monto_minimo, fecha_inicio, fecha_fin, uso_maximo) VALUES
    ('e0000000-0000-4000-8000-000000000001', 'Bienvenida 10%', 'BIENVENIDA10', 'PORCENTAJE', 10,
     'TODO', NULL, NULL, '2026-01-01', '2026-12-31', 500),
    ('e0000000-0000-4000-8000-000000000001', 'Verano 15% en coleccion de temporada', 'VERANO15',
     'PORCENTAJE', 15, 'TEMPORADA', (SELECT id FROM temporada WHERE nombre = 'Primavera-Verano 2026'),
     NULL, '2026-09-01', '2027-02-28', NULL),
    ('e0000000-0000-4000-8000-000000000001', 'Liquidacion invierno 30%', 'INVIERNO30',
     'PORCENTAJE', 30, 'TEMPORADA', (SELECT id FROM temporada WHERE nombre = 'Otonio-Invierno 2026'),
     NULL, '2026-09-01', '2026-10-31', NULL),
    ('e0000000-0000-4000-8000-000000000001', 'Bs 50 en compras desde Bs 500', 'MENOS50',
     'MONTO_FIJO', 50, 'TODO', NULL, 500, '2026-10-01', '2026-11-30', 100),
    ('e0000000-0000-4000-8000-000000000002', 'Bienvenida Andina 10%', 'BIENVENIDA10',
     'PORCENTAJE', 10, 'TODO', NULL, NULL, '2026-01-01', '2026-12-31', NULL);

INSERT INTO promocion (empresa_id, nombre, codigo_cupon, tipo, valor, alcance, categoria_id,
                       fecha_inicio, fecha_fin) VALUES
    ('e0000000-0000-4000-8000-000000000001', 'Jeans 20%', 'JEANS20', 'PORCENTAJE', 20, 'CATEGORIA',
     (SELECT id FROM categoria WHERE slug = 'pantalones'
         AND empresa_id = 'e0000000-0000-4000-8000-000000000001'),
     '2026-10-15', '2026-11-15');


-- ===== Caja: sesiones de caja (ayer cerradas, hoy abiertas) =====

INSERT INTO sesion_caja (id, caja_id, empleado_id, abierta_en, monto_inicial, cerrada_en,
                         monto_sistema, monto_declarado, estado) VALUES
    -- Santa Cruz, ayer: cerrada con el arqueo cuadrado (300 iniciales + 361.37 en efectivo)
    ('d1000000-0000-4000-8000-000000000001',
     (SELECT c.id FROM caja c JOIN sucursal s ON s.id = c.sucursal_id WHERE s.codigo = 'SC-01'),
     (SELECT id FROM usuario WHERE email = 'cajera.scz@fashionstore.bo'),
     date_trunc('day', now()) - interval '1 day' + interval '9 hours', 300.00,
     date_trunc('day', now()) - interval '1 day' + interval '20 hours', 661.37, 661.37, 'CERRADA'),
    -- La Paz, ayer: cerrada con un faltante de Bs 10 (300 iniciales + 440.59 en efectivo)
    ('d1000000-0000-4000-8000-000000000002',
     (SELECT c.id FROM caja c JOIN sucursal s ON s.id = c.sucursal_id WHERE s.codigo = 'LP-01'),
     (SELECT id FROM usuario WHERE email = 'cajera.lapaz@fashionstore.bo'),
     date_trunc('day', now()) - interval '1 day' + interval '9 hours 30 minutes', 300.00,
     date_trunc('day', now()) - interval '1 day' + interval '19 hours 30 minutes', 740.59, 730.59, 'CERRADA');

INSERT INTO sesion_caja (id, caja_id, empleado_id, abierta_en, monto_inicial) VALUES
    ('d1000000-0000-4000-8000-000000000003',
     (SELECT c.id FROM caja c JOIN sucursal s ON s.id = c.sucursal_id WHERE s.codigo = 'SC-01'),
     (SELECT id FROM usuario WHERE email = 'cajera.scz@fashionstore.bo'),
     date_trunc('day', now()) + interval '9 hours', 300.00),
    ('d1000000-0000-4000-8000-000000000004',
     (SELECT c.id FROM caja c JOIN sucursal s ON s.id = c.sucursal_id WHERE s.codigo = 'CB-01'),
     (SELECT id FROM usuario WHERE email = 'cajero.cbba@fashionstore.bo'),
     date_trunc('day', now()) + interval '9 hours', 200.00);


-- ===== Ventas: cabecera, detalle, pago y comprobante =====
-- Formula del sistema: iva = 13% de (subtotal - descuento); total = subtotal - descuento + iva
-- + costo_envio (el flete no lleva IVA).

INSERT INTO venta (id, sucursal_id, usuario_id, canal, entrega, direccion_id, sesion_caja_id,
                   promocion_id, numero, fecha, subtotal, descuento, costo_envio, iva, total,
                   estado, registrada_por_id) VALUES
    -- Ventas presenciales (POS) de ayer
    ('b1000000-0000-4000-8000-000000000001', (SELECT id FROM sucursal WHERE codigo = 'SC-01'), NULL,
     'POS', 'RETIRO_SUCURSAL', NULL, 'd1000000-0000-4000-8000-000000000001', NULL, 'V-SC00000001',
     date_trunc('day', now()) - interval '1 day' + interval '11 hours',
     319.80, 0, 0, 41.57, 361.37, 'ENTREGADA', (SELECT id FROM usuario WHERE email = 'cajera.scz@fashionstore.bo')),
    ('b1000000-0000-4000-8000-000000000002', (SELECT id FROM sucursal WHERE codigo = 'SC-01'),
     (SELECT id FROM usuario WHERE email = 'cliente2@fashionstore.bo'),
     'POS', 'RETIRO_SUCURSAL', NULL, 'd1000000-0000-4000-8000-000000000001', NULL, 'V-SC00000002',
     date_trunc('day', now()) - interval '1 day' + interval '16 hours',
     429.80, 0, 0, 55.87, 485.67, 'ENTREGADA', (SELECT id FROM usuario WHERE email = 'cajera.scz@fashionstore.bo')),
    ('b1000000-0000-4000-8000-000000000003', (SELECT id FROM sucursal WHERE codigo = 'LP-01'), NULL,
     'POS', 'RETIRO_SUCURSAL', NULL, 'd1000000-0000-4000-8000-000000000002', NULL, 'V-LP00000001',
     date_trunc('day', now()) - interval '1 day' + interval '12 hours',
     539.80, 0, 0, 70.17, 609.97, 'ENTREGADA', (SELECT id FROM usuario WHERE email = 'cajera.lapaz@fashionstore.bo')),
    ('b1000000-0000-4000-8000-000000000004', (SELECT id FROM sucursal WHERE codigo = 'LP-01'), NULL,
     'POS', 'RETIRO_SUCURSAL', NULL, 'd1000000-0000-4000-8000-000000000002', NULL, 'V-LP00000002',
     date_trunc('day', now()) - interval '1 day' + interval '17 hours',
     389.90, 0, 0, 50.69, 440.59, 'ENTREGADA', (SELECT id FROM usuario WHERE email = 'cajera.lapaz@fashionstore.bo')),
    -- Ventas presenciales de hoy (sesiones abiertas)
    ('b1000000-0000-4000-8000-000000000005', (SELECT id FROM sucursal WHERE codigo = 'SC-01'), NULL,
     'POS', 'RETIRO_SUCURSAL', NULL, 'd1000000-0000-4000-8000-000000000003', NULL, 'V-SC00000003',
     date_trunc('day', now()) + interval '10 hours',
     159.90, 0, 0, 20.79, 180.69, 'ENTREGADA', (SELECT id FROM usuario WHERE email = 'cajera.scz@fashionstore.bo')),
    ('b1000000-0000-4000-8000-000000000008', (SELECT id FROM sucursal WHERE codigo = 'CB-01'), NULL,
     'POS', 'RETIRO_SUCURSAL', NULL, 'd1000000-0000-4000-8000-000000000004', NULL, 'V-CB00000001',
     date_trunc('day', now()) + interval '10 hours 30 minutes',
     249.90, 0, 0, 32.49, 282.39, 'ENTREGADA', (SELECT id FROM usuario WHERE email = 'cajero.cbba@fashionstore.bo')),
    -- Compra web con delivery, cupon BIENVENIDA10 y pago con Stripe (ya aprobado)
    ('b1000000-0000-4000-8000-000000000006', (SELECT id FROM sucursal WHERE codigo = 'SC-01'),
     (SELECT id FROM usuario WHERE email = 'cliente@fashionstore.bo'),
     'WEB', 'DOMICILIO',
     (SELECT id FROM direccion WHERE alias = 'Casa'), NULL,
     (SELECT id FROM promocion WHERE codigo_cupon = 'BIENVENIDA10'
         AND empresa_id = 'e0000000-0000-4000-8000-000000000001'),
     'V-WEB0000001', now() - interval '5 hours',
     339.80, 33.98, 16.75, 39.76, 362.33, 'PAGADA', NULL),
    -- Pedido desde la app con retiro en tienda, en efectivo: queda PENDIENTE hasta que cobre caja
    -- (el detalle se inserta recien al aprobar el pago, por eso esta venta no tiene lineas)
    ('b1000000-0000-4000-8000-000000000007', (SELECT id FROM sucursal WHERE codigo = 'LP-01'),
     (SELECT id FROM usuario WHERE email = 'cliente2@fashionstore.bo'),
     'MOVIL', 'RETIRO_SUCURSAL', NULL, NULL, NULL, 'V-MOV0000001', now() - interval '2 hours',
     249.90, 0, 0, 32.49, 282.39, 'PENDIENTE', NULL);

INSERT INTO venta_detalle (id, venta_id, variante_id, cantidad, precio_unitario, descuento_unitario, subtotal)
SELECT x.id::uuid, x.venta::uuid, pv.id, x.cantidad, x.precio, x.descuento, x.cantidad * (x.precio - x.descuento)
  FROM (VALUES
    ('b3000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001', 'BLU-001-M-Bla',     2, 159.90, 0),
    ('b3000000-0000-4000-8000-000000000002', 'b1000000-0000-4000-8000-000000000002', 'VES-001-M-Roj',     1, 179.90, 0),
    ('b3000000-0000-4000-8000-000000000003', 'b1000000-0000-4000-8000-000000000002', 'PAN-001-38-Azu',    1, 249.90, 0),
    ('b3000000-0000-4000-8000-000000000004', 'b1000000-0000-4000-8000-000000000003', 'ABR-001-M-Neg',     1, 449.90, 0),
    ('b3000000-0000-4000-8000-000000000005', 'b1000000-0000-4000-8000-000000000003', 'ACC-001-UNICA-Gri', 1,  89.90, 0),
    ('b3000000-0000-4000-8000-000000000006', 'b1000000-0000-4000-8000-000000000004', 'BOT-001-37-Neg',    1, 389.90, 0),
    ('b3000000-0000-4000-8000-000000000007', 'b1000000-0000-4000-8000-000000000005', 'BLU-001-S-Ros',     1, 159.90, 0),
    ('b3000000-0000-4000-8000-000000000008', 'b1000000-0000-4000-8000-000000000006', 'VES-001-S-Bei',     1, 179.90, 17.99),
    ('b3000000-0000-4000-8000-000000000009', 'b1000000-0000-4000-8000-000000000006', 'BLU-001-M-Neg',     1, 159.90, 15.99),
    ('b3000000-0000-4000-8000-000000000010', 'b1000000-0000-4000-8000-000000000008', 'PAN-001-42-Gri',    1, 249.90, 0)
  ) AS x(id, venta, sku, cantidad, precio, descuento)
  JOIN producto_variante pv ON pv.sku = x.sku;

INSERT INTO pago (id, venta_id, metodo, pasarela, monto, estado, id_transaccion, creado_en, confirmado_en) VALUES
    ('b2000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001', 'EFECTIVO', NULL,     361.37, 'APROBADO', NULL,
     date_trunc('day', now()) - interval '1 day' + interval '11 hours', date_trunc('day', now()) - interval '1 day' + interval '11 hours'),
    ('b2000000-0000-4000-8000-000000000002', 'b1000000-0000-4000-8000-000000000002', 'TARJETA',  NULL,     485.67, 'APROBADO', NULL,
     date_trunc('day', now()) - interval '1 day' + interval '16 hours', date_trunc('day', now()) - interval '1 day' + interval '16 hours'),
    ('b2000000-0000-4000-8000-000000000003', 'b1000000-0000-4000-8000-000000000003', 'QR',       NULL,     609.97, 'APROBADO', NULL,
     date_trunc('day', now()) - interval '1 day' + interval '12 hours', date_trunc('day', now()) - interval '1 day' + interval '12 hours'),
    ('b2000000-0000-4000-8000-000000000004', 'b1000000-0000-4000-8000-000000000004', 'EFECTIVO', NULL,     440.59, 'APROBADO', NULL,
     date_trunc('day', now()) - interval '1 day' + interval '17 hours', date_trunc('day', now()) - interval '1 day' + interval '17 hours'),
    ('b2000000-0000-4000-8000-000000000005', 'b1000000-0000-4000-8000-000000000005', 'EFECTIVO', NULL,     180.69, 'APROBADO', NULL,
     date_trunc('day', now()) + interval '10 hours', date_trunc('day', now()) + interval '10 hours'),
    ('b2000000-0000-4000-8000-000000000008', 'b1000000-0000-4000-8000-000000000008', 'EFECTIVO', NULL,     282.39, 'APROBADO', NULL,
     date_trunc('day', now()) + interval '10 hours 30 minutes', date_trunc('day', now()) + interval '10 hours 30 minutes'),
    ('b2000000-0000-4000-8000-000000000006', 'b1000000-0000-4000-8000-000000000006', 'PASARELA', 'STRIPE', 362.33, 'APROBADO',
     'cs_test_a1B2c3D4e5F6g7H8', now() - interval '5 hours', now() - interval '5 hours' + interval '2 minutes'),
    ('b2000000-0000-4000-8000-000000000007', 'b1000000-0000-4000-8000-000000000007', 'EFECTIVO', NULL,     282.39, 'PENDIENTE', NULL,
     now() - interval '2 hours', NULL);

-- Candado de idempotencia del webhook de Stripe que aprobo el pago web
INSERT INTO evento_pasarela (evento_externo_id, pasarela, pago_id, recibido_en) VALUES
    ('evt_1QdemoCheckoutCompleted', 'STRIPE', 'b2000000-0000-4000-8000-000000000006',
     now() - interval '5 hours' + interval '2 minutes');

INSERT INTO comprobante (venta_id, tipo, numero, nit_cliente, razon_social) VALUES
    ('b1000000-0000-4000-8000-000000000001', 'RECIBO',  'C-0000000001', NULL, NULL),
    ('b1000000-0000-4000-8000-000000000002', 'FACTURA', 'C-0000000002', '7654321', 'Valeria Rojas'),
    ('b1000000-0000-4000-8000-000000000003', 'RECIBO',  'C-0000000003', NULL, NULL),
    ('b1000000-0000-4000-8000-000000000004', 'RECIBO',  'C-0000000004', NULL, NULL),
    ('b1000000-0000-4000-8000-000000000005', 'RECIBO',  'C-0000000005', NULL, NULL),
    ('b1000000-0000-4000-8000-000000000006', 'FACTURA', 'C-0000000006', '9876543', 'Cliente Demo'),
    ('b1000000-0000-4000-8000-000000000008', 'RECIBO',  'C-0000000007', NULL, NULL);

UPDATE promocion SET usos_actuales = usos_actuales + 1 WHERE codigo_cupon = 'BIENVENIDA10'
   AND empresa_id = 'e0000000-0000-4000-8000-000000000001';

-- Envio a domicilio de la compra web (nace al aprobarse el pago) y su primer evento
INSERT INTO envio (id, venta_id, sucursal_id, direccion_id, estado, proveedor_ruteo, distancia_km,
                   duracion_min, costo, ciudad, direccion_texto, referencia, latitud, longitud, creado_en)
SELECT 'f5000000-0000-4000-8000-000000000001', v.id, v.sucursal_id, d.id, 'PENDIENTE', 'HAVERSINE',
       2.500, 9, v.costo_envio, d.ciudad, d.direccion, d.referencia, d.latitud, d.longitud,
       now() - interval '5 hours'
  FROM venta v
  JOIN direccion d ON d.id = v.direccion_id
 WHERE v.id = 'b1000000-0000-4000-8000-000000000006';

INSERT INTO envio_evento (envio_id, estado, nota, fecha) VALUES
    ('f5000000-0000-4000-8000-000000000001', 'PENDIENTE',
     'Envio generado por el pago aprobado, pendiente de despacho', now() - interval '5 hours');


-- ===== Carrito activo de una clienta =====

INSERT INTO carrito (id, usuario_id, estado) VALUES
    ('f4000000-0000-4000-8000-000000000001', (SELECT id FROM usuario WHERE email = 'cliente2@fashionstore.bo'), 'ACTIVO');

INSERT INTO carrito_item (carrito_id, variante_id, cantidad, precio_unitario) VALUES
    ('f4000000-0000-4000-8000-000000000001', (SELECT id FROM producto_variante WHERE sku = 'BLU-001-M-Ros'), 1, 159.90),
    ('f4000000-0000-4000-8000-000000000001', (SELECT id FROM producto_variante WHERE sku = 'PAN-001-38-Neg'), 1, 249.90);


-- ===== Reservas de vestidor (comprometen stock, no lo descuentan) =====

INSERT INTO reserva (id, usuario_id, sucursal_id, codigo, creada_en, fecha_visita, hora_visita,
                     expira_en, estado, vestidor_asignado, observaciones, atendida_por_id) VALUES
    -- Pendiente de confirmar por la encargada, visita manana a las 16:00
    ('c1000000-0000-4000-8000-000000000001', (SELECT id FROM usuario WHERE email = 'cliente@fashionstore.bo'),
     (SELECT id FROM sucursal WHERE codigo = 'SC-01'), 'RES-0000000001', now() - interval '1 hour',
     CURRENT_DATE + 1, '16:00', (CURRENT_DATE + 1) + time '16:00' + interval '4 hours',
     'PENDIENTE', NULL, 'Quiero probarme dos tallas', NULL),
    -- Ya confirmada, visita hoy a las 18:00 en La Paz
    ('c1000000-0000-4000-8000-000000000002', (SELECT id FROM usuario WHERE email = 'cliente2@fashionstore.bo'),
     (SELECT id FROM sucursal WHERE codigo = 'LP-01'), 'RES-0000000002', now() - interval '6 hours',
     CURRENT_DATE, '18:00', CURRENT_DATE + time '18:00' + interval '4 hours',
     'CONFIRMADA', 'V-1', NULL, (SELECT id FROM usuario WHERE email = 'encargada.lapaz@fashionstore.bo'));

INSERT INTO reserva_detalle (reserva_id, variante_id, cantidad) VALUES
    ('c1000000-0000-4000-8000-000000000001', (SELECT id FROM producto_variante WHERE sku = 'BLU-001-L-Bla'), 1),
    ('c1000000-0000-4000-8000-000000000001', (SELECT id FROM producto_variante WHERE sku = 'VES-001-L-Neg'), 1),
    ('c1000000-0000-4000-8000-000000000002', (SELECT id FROM producto_variante WHERE sku = 'ABR-001-L-Cam'), 1);

INSERT INTO reserva_historial (reserva_id, estado_anterior, estado_nuevo, usuario_id, comentario, fecha) VALUES
    ('c1000000-0000-4000-8000-000000000002', 'PENDIENTE', 'CONFIRMADA',
     (SELECT id FROM usuario WHERE email = 'encargada.lapaz@fashionstore.bo'), 'Vestidor 1 asignado',
     now() - interval '5 hours');


-- ===== Reflejo en el inventario de las ventas y reservas cargadas arriba =====
-- En el sistema esto lo hacen tg_venta_descuenta_stock y tg_reserva_compromete_stock (8.2.6.3);
-- como la poblacion se carga antes de crear los triggers, se aplica aca de forma explicita.

UPDATE inventario i
   SET cantidad_fisica = i.cantidad_fisica - x.vendidas
  FROM (SELECT v.sucursal_id, vd.variante_id, SUM(vd.cantidad) AS vendidas
          FROM venta_detalle vd JOIN venta v ON v.id = vd.venta_id
         GROUP BY v.sucursal_id, vd.variante_id) x
 WHERE i.sucursal_id = x.sucursal_id AND i.variante_id = x.variante_id;

UPDATE inventario i
   SET cantidad_reservada = i.cantidad_reservada + x.reservadas
  FROM (SELECT r.sucursal_id, rd.variante_id, SUM(rd.cantidad) AS reservadas
          FROM reserva_detalle rd JOIN reserva r ON r.id = rd.reserva_id
         GROUP BY r.sucursal_id, rd.variante_id) x
 WHERE i.sucursal_id = x.sucursal_id AND i.variante_id = x.variante_id;


-- ===== Recepcion de mercaderia (borrador: el stock entra recien al confirmarla) =====

INSERT INTO recepcion (id, sucursal_id, proveedor_id, coleccion_id, numero, fecha, total, estado, usuario_id) VALUES
    ('f1000000-0000-4000-8000-000000000001', (SELECT id FROM sucursal WHERE codigo = 'SC-01'),
     (SELECT id FROM proveedor WHERE nombre = 'Urban Import Bolivia'),
     (SELECT id FROM coleccion WHERE nombre = 'Coleccion Llanura 2026'),
     'REC-SC-0001', CURRENT_DATE, 1380.00, 'BORRADOR',
     (SELECT id FROM usuario WHERE email = 'almacen.scz@fashionstore.bo'));

INSERT INTO recepcion_detalle (recepcion_id, variante_id, cantidad, costo_unitario) VALUES
    ('f1000000-0000-4000-8000-000000000001', (SELECT id FROM producto_variante WHERE sku = 'BLU-001-XS-Neg'), 10, 70.00),
    ('f1000000-0000-4000-8000-000000000001', (SELECT id FROM producto_variante WHERE sku = 'VES-001-S-Roj'),   8, 85.00);


-- ===== Traspaso entre sucursales (solicitado: todavia no salio del origen) =====
-- Entra el calor: Cochabamba manda vestidos a Santa Cruz.

INSERT INTO traspaso (id, sucursal_origen_id, sucursal_destino_id, numero, estado, usuario_solicita_id) VALUES
    ('f2000000-0000-4000-8000-000000000001',
     (SELECT id FROM sucursal WHERE codigo = 'CB-01'), (SELECT id FROM sucursal WHERE codigo = 'SC-01'),
     'TRP-0000000001', 'SOLICITADO', (SELECT id FROM usuario WHERE email = 'admin@fashionstore.bo'));

INSERT INTO traspaso_detalle (traspaso_id, variante_id, cantidad_solicitada) VALUES
    ('f2000000-0000-4000-8000-000000000001', (SELECT id FROM producto_variante WHERE sku = 'VES-001-M-Neg'), 3),
    ('f2000000-0000-4000-8000-000000000001', (SELECT id FROM producto_variante WHERE sku = 'VES-001-L-Bei'), 2);


-- ===== Devolucion solicitada (cambio de talla del vestido de la venta V-SC00000002) =====

INSERT INTO devolucion (id, venta_id, sucursal_id, motivo, monto_devuelto, estado, usuario_id,
                        reintegro_metodo, motivo_tipo, con_etiqueta, sin_uso, con_comprobante) VALUES
    ('f3000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000002',
     (SELECT id FROM sucursal WHERE codigo = 'SC-01'), 'Le queda chico, pide talla L',
     203.29, 'SOLICITADA', (SELECT id FROM usuario WHERE email = 'cajera.scz@fashionstore.bo'),
     'TARJETA', 'TALLA', TRUE, TRUE, TRUE);

INSERT INTO devolucion_detalle (devolucion_id, venta_detalle_id, cantidad, variante_solicitada_id) VALUES
    ('f3000000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000002', 1,
     (SELECT id FROM producto_variante WHERE sku = 'VES-001-L-Roj'));


-- ===== Notificaciones, auditoria y sincronizacion offline =====

INSERT INTO notificacion (usuario_id, tipo, titulo, mensaje, entidad_tipo, entidad_id, leida, fecha) VALUES
    ((SELECT id FROM usuario WHERE email = 'cliente@fashionstore.bo'), 'VENTA', 'Pago aprobado',
     'Tu pedido V-WEB0000001 fue pagado y se prepara para el envio.', 'VENTA',
     'b1000000-0000-4000-8000-000000000006', TRUE, now() - interval '5 hours'),
    ((SELECT id FROM usuario WHERE email = 'cliente@fashionstore.bo'), 'RESERVA', 'Reserva recibida',
     'Tu reserva RES-0000000001 espera la confirmacion de la tienda.', 'RESERVA',
     'c1000000-0000-4000-8000-000000000001', FALSE, now() - interval '1 hour'),
    ((SELECT id FROM usuario WHERE email = 'admin@fashionstore.bo'), 'RESERVA', 'Nueva reserva',
     'Cliente Demo reservo 2 prendas para manana a las 16:00.', 'RESERVA',
     'c1000000-0000-4000-8000-000000000001', FALSE, now() - interval '1 hour'),
    ((SELECT id FROM usuario WHERE email = 'cajera.lapaz@fashionstore.bo'), 'VENTA', 'Pedido para cobrar',
     'Pedido V-MOV0000001 por Bs 282.39 a pagar en efectivo (retira en tienda).', 'VENTA',
     'b1000000-0000-4000-8000-000000000007', FALSE, now() - interval '2 hours'),
    ((SELECT id FROM usuario WHERE email = 'admin@modaurbana.bo'), 'SUSCRIPCION', 'Suscripcion vencida',
     'Tu plan Basico vencio. Renova para seguir usando la gestion de la tienda.', NULL, NULL,
     FALSE, now() - interval '3 days');

INSERT INTO auditoria (usuario_id, empresa_id, entidad, entidad_id, accion, datos_antes, datos_despues, ip, fecha) VALUES
    ((SELECT id FROM usuario WHERE email = 'admin@fashionstore.bo'), 'e0000000-0000-4000-8000-000000000001',
     'usuario', (SELECT id::text FROM usuario WHERE email = 'admin@fashionstore.bo'), 'LOGIN',
     NULL, NULL, '181.115.20.5', now() - interval '8 hours'),
    ((SELECT id FROM usuario WHERE email = 'admin@fashionstore.bo'), 'e0000000-0000-4000-8000-000000000001',
     'producto', (SELECT id::text FROM producto WHERE codigo = 'ACC-001'), 'ACTUALIZAR',
     '{"precio_oferta": null}', '{"precio_oferta": 69.90}', '181.115.20.5', now() - interval '7 hours'),
    ((SELECT id FROM usuario WHERE email = 'admin@fashionstore.bo'), 'e0000000-0000-4000-8000-000000000001',
     'promocion', (SELECT id::text FROM promocion WHERE codigo_cupon = 'JEANS20'), 'CREAR',
     NULL, '{"codigo_cupon": "JEANS20", "valor": 20}', '181.115.20.5', now() - interval '7 hours'),
    ((SELECT id FROM usuario WHERE email = 'superadmin@fashionstore.bo'), NULL,
     'empresa', 'e0000000-0000-4000-8000-000000000003', 'ACTUALIZAR',
     '{"estado": "ACTIVA"}', '{"estado": "VENCIDA"}', '10.0.0.1', now() - interval '3 days');

-- Venta registrada sin conexion que llego con un precio viejo: queda en CONFLICTO
INSERT INTO operacion_sync (id, empresa_id, sucursal_id, usuario_id, tipo, estado, codigo_motivo,
                            motivo, payload, registrada_en) VALUES
    ('a1000000-0000-4000-8000-000000000001', 'e0000000-0000-4000-8000-000000000001',
     (SELECT id FROM sucursal WHERE codigo = 'SC-01'),
     (SELECT id FROM usuario WHERE email = 'cajera.scz@fashionstore.bo'),
     'VENTA', 'CONFLICTO', 'PRECIO_CAMBIADO',
     'El precio de ACC-001-UNICA-Vin cambio de 89.90 a 69.90 desde que se bajo el catalogo',
     '{"items": [{"sku": "ACC-001-UNICA-Vin", "cantidad": 1, "precio": 89.90}], "metodo_pago": "EFECTIVO"}',
     now() - interval '3 hours');


-- ---------------------------------------------------------------------
--  8.2.4.2  UPDATE
-- ---------------------------------------------------------------------

-- 1. Subir 5% el precio base de las prendas de la temporada activa de FashionStore
UPDATE producto
   SET precio_base = ROUND(precio_base * 1.05, 2)
 WHERE empresa_id = 'e0000000-0000-4000-8000-000000000001'
   AND temporada_id = (SELECT id FROM temporada
                        WHERE activa AND empresa_id = 'e0000000-0000-4000-8000-000000000001');

-- 2. Marcar como destacada la chalina (aparece en la vitrina de la tienda)
UPDATE producto SET destacado = TRUE WHERE codigo = 'ACC-001';

-- 3. Santa Cruz pide tener al menos 4 tapados por talla y color para los surazos (frentes
--    frios): sube el stock minimo y esas variantes pasan a figurar como "a reponer"
UPDATE inventario i
   SET stock_minimo = 4
  FROM producto_variante pv
  JOIN producto p ON p.id = pv.producto_id
 WHERE i.variante_id = pv.id
   AND p.codigo = 'ABR-001'
   AND i.sucursal_id = (SELECT id FROM sucursal WHERE codigo = 'SC-01');

-- 4. La clienta actualiza su telefono y verifica su correo
UPDATE usuario
   SET telefono = '70099887', email_verificado = TRUE
 WHERE email = 'andrea.lopez@gmail.com';

-- 5. Cambiar la tarifa del delivery sin redesplegar el backend (la lee fn_cotizar_envio)
UPDATE configuracion
   SET valor = '4', actualizado_en = now()
 WHERE clave = 'delivery_precio_km';

-- 6. Segmentar a la clienta como VIP en la cartera de FashionStore
UPDATE cliente_perfil_tenant
   SET segmento = 'VIP', actualizado_en = now(),
       actualizado_por_id = (SELECT id FROM usuario WHERE email = 'admin@fashionstore.bo')
 WHERE empresa_id = 'e0000000-0000-4000-8000-000000000001'
   AND usuario_id = (SELECT id FROM usuario WHERE email = 'cliente@fashionstore.bo');

-- 7. Desactivar la promocion de invierno (baja logica: la venta historica sigue apuntandola)
UPDATE promocion SET activa = FALSE WHERE codigo_cupon = 'INVIERNO30';

-- 8. Marcar como leidas las notificaciones de la clienta demo
UPDATE notificacion
   SET leida = TRUE
 WHERE usuario_id = (SELECT id FROM usuario WHERE email = 'cliente@fashionstore.bo')
   AND NOT leida;

-- 9. Bloquear una cuenta por 15 minutos tras 5 intentos fallidos de login
UPDATE usuario
   SET intentos_fallidos = 0, bloqueado_hasta = now() + interval '15 minutes'
 WHERE email = 'andrea.lopez@gmail.com';


-- ---------------------------------------------------------------------
--  8.2.4.3  DELETE
--  El kardex, las ventas, los pagos y las bitacoras NUNCA se borran (son append-only o
--  respaldan dinero): lo que se da de baja ahi se hace con un estado o con activo = FALSE.
--  Se borra fisicamente solo lo que no tiene historia: items de carrito, direcciones sin uso,
--  sesiones vencidas, categorias vacias, etc.
-- ---------------------------------------------------------------------

-- 1. Quitar un item del carrito
DELETE FROM carrito_item
 WHERE carrito_id = 'f4000000-0000-4000-8000-000000000001'
   AND variante_id = (SELECT id FROM producto_variante WHERE sku = 'PAN-001-38-Neg');

-- 2. Borrar una direccion que ninguna venta ni envio usa
DELETE FROM direccion d
 WHERE d.alias = 'Trabajo'
   AND d.usuario_id = (SELECT id FROM usuario WHERE email = 'cliente@fashionstore.bo')
   AND NOT EXISTS (SELECT 1 FROM venta v WHERE v.direccion_id = d.id)
   AND NOT EXISTS (SELECT 1 FROM envio e WHERE e.direccion_id = d.id);

-- 3. Limpiar los tokens de sesion revocados o vencidos
DELETE FROM sesion_token WHERE revocado OR expira_en < now();

-- 4. Borrar las notificaciones ya leidas
DELETE FROM notificacion WHERE leida;

-- 5. Borrar una subcategoria que no tiene productos ni promociones (Faldas)
DELETE FROM categoria c
 WHERE c.slug = 'faldas'
   AND c.empresa_id = 'e0000000-0000-4000-8000-000000000001'
   AND NOT EXISTS (SELECT 1 FROM producto p  WHERE p.categoria_id = c.id)
   AND NOT EXISTS (SELECT 1 FROM promocion pr WHERE pr.categoria_id = c.id);

-- 6. Borrado en cascada: un rol propio de empresa se borra junto con su matriz de permisos
--    (rol_permiso tiene ON DELETE CASCADE). Los roles del sistema no se borran.
DELETE FROM rol WHERE nombre = 'SUPERVISORA' AND NOT es_sistema;

-- 7. Baja LOGICA de una prenda: no se borra porque sus variantes tienen inventario (y podrian
--    tener ventas); desaparece del catalogo pero su historia se conserva
UPDATE producto SET activo = FALSE WHERE codigo = 'AND-004';


-- =====================================================================
--  8.2.5  CONSULTAS
-- =====================================================================

-- ---------------------------------------------------------------------
--  8.2.5.1  CONSULTAS SIMPLES (una sola tabla)
-- ---------------------------------------------------------------------

-- 1. Sucursales activas de FashionStore ordenadas por ciudad
SELECT codigo, nombre, ciudad, direccion, hora_apertura, hora_cierre, cantidad_vestidores
  FROM sucursal
 WHERE empresa_id = 'e0000000-0000-4000-8000-000000000001' AND activa
 ORDER BY ciudad, nombre;

-- 2. Prendas activas entre Bs 150 y Bs 300, de la mas barata a la mas cara
SELECT codigo, nombre, material, precio_base
  FROM producto
 WHERE activo AND precio_base BETWEEN 150 AND 300
 ORDER BY precio_base;

-- 3. Busqueda en el catalogo por texto, sin importar mayusculas
SELECT codigo, nombre, descripcion
  FROM producto
 WHERE nombre ILIKE '%lana%' OR descripcion ILIKE '%frio%';

-- 4. Cantidad de ventas y monto vendido por canal (solo ventas cobradas)
SELECT canal, COUNT(*) AS ventas, SUM(total) AS monto_bs, ROUND(AVG(total), 2) AS ticket_promedio
  FROM venta
 WHERE estado IN ('PAGADA', 'ENTREGADA')
 GROUP BY canal
 ORDER BY monto_bs DESC;

-- 5. Promociones vigentes hoy
SELECT codigo_cupon, nombre, tipo, valor, alcance, fecha_inicio, fecha_fin,
       usos_actuales, uso_maximo
  FROM promocion
 WHERE activa AND CURRENT_DATE BETWEEN fecha_inicio AND fecha_fin
 ORDER BY fecha_fin;

-- 6. Reservas que vencen en las proximas 48 horas y siguen vivas
SELECT codigo, fecha_visita, hora_visita, expira_en, estado
  FROM reserva
 WHERE estado IN ('PENDIENTE', 'CONFIRMADA', 'PREPARADA')
   AND expira_en BETWEEN now() AND now() + interval '48 hours'
 ORDER BY expira_en;

-- 7. Parametros de la tarifa del delivery
SELECT clave, valor, descripcion
  FROM configuracion
 WHERE clave LIKE 'delivery_%'
 ORDER BY clave;


-- ---------------------------------------------------------------------
--  8.2.5.2  CONSULTAS DOBLES (dos tablas)
-- ---------------------------------------------------------------------

-- 1. Personal de cada sucursal con su cargo
SELECT s.codigo AS sucursal, e.cargo, e.ci, e.fecha_ingreso, e.activo
  FROM empleado e
  JOIN sucursal s ON s.id = e.sucursal_id
 ORDER BY s.codigo, e.cargo;

-- 2. Usuarios con su rol (LEFT JOIN: las clientas no tienen rol)
SELECT u.email, u.nombre || ' ' || u.apellido AS nombre_completo, u.tipo,
       COALESCE(r.nombre, '-') AS rol
  FROM usuario u
  LEFT JOIN rol r ON r.id = u.rol_id
 ORDER BY u.tipo DESC, r.nombre, u.email;

-- 3. Cantidad de variantes (talla x color) por producto
SELECT p.codigo, p.nombre, COUNT(pv.id) AS variantes
  FROM producto p
  JOIN producto_variante pv ON pv.producto_id = p.id
 GROUP BY p.codigo, p.nombre
 ORDER BY variantes DESC;

-- 4. Ventas por sucursal (cantidad y monto), solo las que vendieron algo
SELECT s.nombre AS sucursal, COUNT(v.id) AS ventas, SUM(v.total) AS monto_bs
  FROM venta v
  JOIN sucursal s ON s.id = v.sucursal_id
 WHERE v.estado IN ('PAGADA', 'ENTREGADA')
 GROUP BY s.nombre
HAVING SUM(v.total) > 0
 ORDER BY monto_bs DESC;

-- 5. Pagos por metodo y estado de cada venta
SELECT v.numero, v.canal, p.metodo, p.pasarela, p.monto, p.estado, p.confirmado_en
  FROM pago p
  JOIN venta v ON v.id = p.venta_id
 ORDER BY v.fecha;

-- 6. Plan contratado por cada empresa y dias que le quedan a su suscripcion
SELECT e.nombre AS empresa, su.estado,
       su.vence_en::date AS vence,
       GREATEST(EXTRACT(DAY FROM su.vence_en - now()), 0)::int AS dias_restantes
  FROM empresa e
  JOIN suscripcion su ON su.empresa_id = e.id
 ORDER BY su.vence_en;

-- 7. Subcategorias con su categoria padre (autorrelacion de categoria)
SELECT padre.nombre AS categoria, hija.nombre AS subcategoria
  FROM categoria hija
  JOIN categoria padre ON padre.id = hija.categoria_padre_id
 ORDER BY padre.orden, hija.orden;


-- ---------------------------------------------------------------------
--  8.2.5.3  CONSULTAS MULTIPLES (tres o mas tablas)
-- ---------------------------------------------------------------------

-- 1. Existencias de una prenda en todas las sucursales, por talla y color
SELECT p.nombre AS prenda, t.codigo AS talla, c.nombre AS color, s.codigo AS sucursal,
       i.cantidad_fisica, i.cantidad_reservada, i.disponible
  FROM inventario i
  JOIN producto_variante pv ON pv.id = i.variante_id
  JOIN producto p           ON p.id  = pv.producto_id
  JOIN talla t              ON t.id  = pv.talla_id
  JOIN color c              ON c.id  = pv.color_id
  JOIN sucursal s           ON s.id  = i.sucursal_id
 WHERE p.codigo = 'ABR-001'
 ORDER BY s.codigo, t.orden, c.nombre;

-- 2. Detalle de cada venta: que prenda, talla y color se vendio y a que precio
SELECT v.numero, s.codigo AS sucursal, v.canal, p.nombre AS prenda, t.codigo AS talla,
       c.nombre AS color, vd.cantidad, vd.precio_unitario, vd.subtotal
  FROM venta_detalle vd
  JOIN venta v              ON v.id  = vd.venta_id
  JOIN sucursal s           ON s.id  = v.sucursal_id
  JOIN producto_variante pv ON pv.id = vd.variante_id
  JOIN producto p           ON p.id  = pv.producto_id
  JOIN talla t              ON t.id  = pv.talla_id
  JOIN color c              ON c.id  = pv.color_id
 ORDER BY v.fecha, v.numero;

-- 3. Top de prendas mas vendidas por unidades, con su categoria
SELECT cat.nombre AS categoria, p.nombre AS prenda, SUM(vd.cantidad) AS unidades,
       SUM(vd.subtotal) AS monto_bs
  FROM venta_detalle vd
  JOIN venta v              ON v.id   = vd.venta_id
  JOIN producto_variante pv ON pv.id  = vd.variante_id
  JOIN producto p           ON p.id   = pv.producto_id
  JOIN categoria cat        ON cat.id = p.categoria_id
 WHERE v.estado IN ('PAGADA', 'ENTREGADA')
 GROUP BY cat.nombre, p.nombre
 ORDER BY unidades DESC, monto_bs DESC
 LIMIT 5;

-- 4. Cola de reservas de cada sucursal con la clienta y las prendas a preparar
SELECT s.codigo AS sucursal, r.codigo AS reserva, r.estado,
       r.fecha_visita, r.hora_visita, u.nombre || ' ' || u.apellido AS clienta,
       pv.sku, rd.cantidad, rd.estado_item
  FROM reserva r
  JOIN sucursal s           ON s.id  = r.sucursal_id
  JOIN usuario u            ON u.id  = r.usuario_id
  JOIN reserva_detalle rd   ON rd.reserva_id = r.id
  JOIN producto_variante pv ON pv.id = rd.variante_id
 WHERE r.estado IN ('PENDIENTE', 'CONFIRMADA', 'PREPARADA')
 ORDER BY r.fecha_visita, r.hora_visita;

-- 5. Seguimiento de los envios a domicilio: clienta, sucursal, costo y ultimo evento
SELECT v.numero, u.email AS clienta, s.nombre AS sucursal, en.estado, en.distancia_km,
       en.costo, en.direccion_texto, ev.fecha AS ultimo_evento, ev.nota
  FROM envio en
  JOIN venta v    ON v.id = en.venta_id
  JOIN usuario u  ON u.id = v.usuario_id
  JOIN sucursal s ON s.id = en.sucursal_id
  JOIN envio_evento ev ON ev.envio_id = en.id
 WHERE ev.fecha = (SELECT MAX(fecha) FROM envio_evento WHERE envio_id = en.id);

-- 6. Matriz de permisos: cuantos permisos tiene cada rol por modulo
SELECT r.nombre AS rol, pe.modulo, COUNT(*) AS permisos,
       string_agg(split_part(pe.codigo, '.', 2), ', ' ORDER BY pe.codigo) AS acciones
  FROM rol r
  JOIN rol_permiso rp ON rp.rol_id = r.id
  JOIN permiso pe     ON pe.id = rp.permiso_id
 GROUP BY r.nombre, pe.modulo
 ORDER BY r.nombre, pe.modulo;

-- 7. Arqueo de las sesiones de caja: cajero, sucursal, montos y diferencia
SELECT s.codigo AS sucursal, c.codigo AS caja, u.nombre || ' ' || u.apellido AS cajero,
       sc.abierta_en, sc.cerrada_en, sc.monto_inicial, sc.monto_sistema, sc.monto_declarado,
       sc.diferencia, sc.estado
  FROM sesion_caja sc
  JOIN caja c     ON c.id = sc.caja_id
  JOIN sucursal s ON s.id = c.sucursal_id
  JOIN usuario u  ON u.id = sc.empleado_id
 ORDER BY sc.abierta_en;


-- ---------------------------------------------------------------------
--  8.2.5.4  SUBCONSULTAS
-- ---------------------------------------------------------------------

-- 1. (IN) Clientas que compraron alguna vez en FashionStore
SELECT email, nombre, apellido
  FROM usuario
 WHERE tipo = 'CLIENTE'
   AND id IN (SELECT v.usuario_id
                FROM venta v
                JOIN sucursal s ON s.id = v.sucursal_id
               WHERE s.empresa_id = 'e0000000-0000-4000-8000-000000000001'
                 AND v.estado IN ('PAGADA', 'ENTREGADA'));

-- 2. (NOT EXISTS) Variantes que nunca se vendieron en ninguna sucursal
SELECT pv.sku
  FROM producto_variante pv
 WHERE NOT EXISTS (SELECT 1 FROM venta_detalle vd WHERE vd.variante_id = pv.id)
 ORDER BY pv.sku
 LIMIT 10;

-- 3. (Escalar) Prendas mas caras que el precio promedio de su propia empresa (correlacionada)
SELECT p.codigo, p.nombre, p.precio_base,
       (SELECT ROUND(AVG(p2.precio_base), 2) FROM producto p2
         WHERE p2.empresa_id = p.empresa_id) AS promedio_empresa
  FROM producto p
 WHERE p.precio_base > (SELECT AVG(p2.precio_base) FROM producto p2
                         WHERE p2.empresa_id = p.empresa_id)
 ORDER BY p.precio_base DESC;

-- 4. (En el FROM) Sucursal que mas vendio en monto
SELECT x.sucursal, x.monto_bs
  FROM (SELECT s.nombre AS sucursal, SUM(v.total) AS monto_bs
          FROM venta v
          JOIN sucursal s ON s.id = v.sucursal_id
         WHERE v.estado IN ('PAGADA', 'ENTREGADA')
         GROUP BY s.nombre) x
 WHERE x.monto_bs = (SELECT MAX(t.monto)
                       FROM (SELECT SUM(total) AS monto FROM venta
                              WHERE estado IN ('PAGADA', 'ENTREGADA')
                              GROUP BY sucursal_id) t);

-- 5. (Correlacionada) Inventario en o bajo el stock minimo: lo que hay que reponer o traspasar
SELECT s.codigo AS sucursal, pv.sku, i.disponible, i.stock_minimo,
       (SELECT MAX(i2.disponible) FROM inventario i2
         WHERE i2.variante_id = i.variante_id AND i2.sucursal_id <> i.sucursal_id) AS max_en_otra_sucursal
  FROM inventario i
  JOIN sucursal s           ON s.id  = i.sucursal_id
  JOIN producto_variante pv ON pv.id = i.variante_id
 WHERE i.disponible <= i.stock_minimo
 ORDER BY s.codigo, pv.sku
 LIMIT 15;

-- 6. (CTE) Ticket promedio de cada clienta comparado con el promedio general
WITH por_clienta AS (
    SELECT v.usuario_id, COUNT(*) AS compras, SUM(v.total) AS gastado
      FROM venta v
     WHERE v.usuario_id IS NOT NULL AND v.estado IN ('PAGADA', 'ENTREGADA')
     GROUP BY v.usuario_id
)
SELECT u.email, pc.compras, pc.gastado,
       ROUND(pc.gastado / pc.compras, 2) AS ticket_promedio,
       (SELECT ROUND(AVG(total), 2) FROM venta WHERE estado IN ('PAGADA', 'ENTREGADA')) AS ticket_general
  FROM por_clienta pc
  JOIN usuario u ON u.id = pc.usuario_id
 ORDER BY pc.gastado DESC;

-- 7. (EXISTS) Empresas con suscripcion vigente que tienen al menos una reserva activa
SELECT e.nombre
  FROM empresa e
 WHERE EXISTS (SELECT 1 FROM suscripcion su
                WHERE su.empresa_id = e.id AND su.estado IN ('PRUEBA', 'ACTIVA')
                  AND su.vence_en > now())
   AND EXISTS (SELECT 1 FROM reserva r
                 JOIN sucursal s ON s.id = r.sucursal_id
                WHERE s.empresa_id = e.id
                  AND r.estado IN ('PENDIENTE', 'CONFIRMADA', 'PREPARADA'));

-- 8. Consultas sobre las vistas del sistema (8.2.2)
SELECT * FROM v_ventas_diarias ORDER BY dia, sucursal, canal;

SELECT producto, sku, total_fisico, total_reservado, total_disponible, sucursales_con_stock
  FROM v_stock_global
 WHERE empresa_id = 'e0000000-0000-4000-8000-000000000001'
 ORDER BY total_disponible
 LIMIT 10;

SELECT situacion, COUNT(*) AS variantes_por_sucursal
  FROM v_existencias_consolidadas
 GROUP BY situacion;


-- =====================================================================
--  8.2.6  PROCEDIMIENTOS ALMACENADOS
--  La regla de oro del diseno: el stock se escribe en UN solo lugar, fn_mover_inventario
--  (8.2.6.2). Los procedimientos y los triggers no tocan cantidad_fisica/cantidad_reservada:
--  insertan en las tablas de movimientos o llaman a esa funcion.
-- =====================================================================

-- ---------------------------------------------------------------------
--  8.2.6.1  PROCEDIMIENTOS (CREATE PROCEDURE, se invocan con CALL)
--  Empaquetan como una sola operacion atomica lo que el backend hace en varios pasos. Si
--  cualquier paso falla (por ejemplo, falta stock), se deshace todo.
-- ---------------------------------------------------------------------

-- 1. Venta presencial en caja (CU07). Equivale a POST /ventas/pos: valida la sesion de caja,
--    toma el precio vigente de cada prenda, inserta el detalle (el trigger
--    tg_venta_descuenta_stock descuenta el stock), calcula IVA y total, registra el pago
--    aprobado y emite el comprobante. Devuelve el numero de venta en p_numero.
CREATE OR REPLACE PROCEDURE sp_venta_pos(
    p_sesion_caja_id UUID,
    p_items          JSONB,          -- [{"sku": "BLU-001-M-Bla", "cantidad": 2}, ...]
    p_metodo         metodo_pago,
    INOUT p_numero   VARCHAR DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_sesion   sesion_caja%ROWTYPE;
    v_sucursal UUID;
    v_empresa  UUID;
    v_venta    UUID;
    v_item     JSONB;
    v_variante UUID;
    v_precio   NUMERIC(12,2);
    v_cantidad INT;
    v_subtotal NUMERIC(12,2) := 0;
    v_iva      NUMERIC(12,2);
    v_total    NUMERIC(12,2);
BEGIN
    SELECT * INTO v_sesion FROM sesion_caja WHERE id = p_sesion_caja_id;
    IF NOT FOUND OR v_sesion.estado <> 'ABIERTA' THEN
        RAISE EXCEPTION 'La sesion de caja % no existe o no esta abierta', p_sesion_caja_id;
    END IF;
    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'La venta no tiene prendas';
    END IF;

    SELECT s.id, s.empresa_id INTO v_sucursal, v_empresa
      FROM caja c JOIN sucursal s ON s.id = c.sucursal_id
     WHERE c.id = v_sesion.caja_id;

    p_numero := 'V-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 10));

    INSERT INTO venta (sucursal_id, canal, entrega, sesion_caja_id, numero,
                       subtotal, descuento, iva, total, registrada_por_id)
    VALUES (v_sucursal, 'POS', 'RETIRO_SUCURSAL', p_sesion_caja_id, p_numero,
            0, 0, 0, 0, v_sesion.empleado_id)
    RETURNING id INTO v_venta;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_cantidad := (v_item ->> 'cantidad')::int;

        SELECT pv.id, COALESCE(pv.precio_oferta, pv.precio, p.precio_base)
          INTO v_variante, v_precio
          FROM producto_variante pv
          JOIN producto p ON p.id = pv.producto_id
         WHERE pv.sku = v_item ->> 'sku'
           AND pv.activa AND p.activo
           AND p.empresa_id = v_empresa;     -- una prenda de otra empresa no se puede vender
        IF v_variante IS NULL THEN
            RAISE EXCEPTION 'La prenda % no esta disponible en el catalogo', v_item ->> 'sku';
        END IF;

        -- el trigger tg_venta_descuenta_stock descuenta el stock (o aborta si no alcanza)
        INSERT INTO venta_detalle (venta_id, variante_id, cantidad, precio_unitario, subtotal)
        VALUES (v_venta, v_variante, v_cantidad, v_precio, v_precio * v_cantidad);

        v_subtotal := v_subtotal + v_precio * v_cantidad;
    END LOOP;

    v_iva   := ROUND(v_subtotal * 0.13, 2);
    v_total := v_subtotal + v_iva;

    UPDATE venta SET subtotal = v_subtotal, iva = v_iva, total = v_total, estado = 'ENTREGADA'
     WHERE id = v_venta;

    INSERT INTO pago (venta_id, metodo, monto, estado, confirmado_en)
    VALUES (v_venta, p_metodo, v_total, 'APROBADO', now());

    INSERT INTO comprobante (venta_id, numero)
    VALUES (v_venta, 'C-' || upper(substr(md5(v_venta::text), 1, 10)));

    RAISE NOTICE 'Venta % registrada: subtotal %, IVA %, total Bs %', p_numero, v_subtotal, v_iva, v_total;
END;
$$;

COMMENT ON PROCEDURE sp_venta_pos IS
    'CU07: venta presencial atomica (detalle, IVA 13%, pago aprobado y comprobante).';


-- 2. Cierre de caja con arqueo (CU07). El monto del sistema se calcula con
--    fn_total_efectivo_sesion DENTRO del mismo UPDATE, asi no queda una ventana entre leer el
--    total y guardarlo. La diferencia (declarado - sistema) es una columna calculada.
CREATE OR REPLACE PROCEDURE sp_cerrar_sesion_caja(
    p_sesion_caja_id  UUID,
    p_monto_declarado NUMERIC
)
LANGUAGE plpgsql AS $$
DECLARE
    v_estado     estado_caja;
    v_sistema    NUMERIC(12,2);
    v_diferencia NUMERIC(12,2);
BEGIN
    SELECT estado INTO v_estado FROM sesion_caja WHERE id = p_sesion_caja_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe la sesion de caja %', p_sesion_caja_id;
    END IF;
    IF v_estado = 'CERRADA' THEN
        RAISE EXCEPTION 'La sesion de caja ya esta cerrada';
    END IF;
    IF p_monto_declarado < 0 THEN
        RAISE EXCEPTION 'El monto declarado no puede ser negativo';
    END IF;

    UPDATE sesion_caja sc
       SET monto_sistema   = sc.monto_inicial + fn_total_efectivo_sesion(sc.id),
           monto_declarado = p_monto_declarado,
           cerrada_en      = now(),
           estado          = 'CERRADA'
     WHERE sc.id = p_sesion_caja_id
    RETURNING monto_sistema, diferencia INTO v_sistema, v_diferencia;

    RAISE NOTICE 'Caja cerrada. Sistema: Bs %, declarado: Bs %, diferencia: Bs %',
                 v_sistema, p_monto_declarado, v_diferencia;
END;
$$;

COMMENT ON PROCEDURE sp_cerrar_sesion_caja IS
    'CU07: cierra la sesion de caja y deja el arqueo (sistema vs declarado).';


-- 3. Ajuste manual de stock por recuento fisico (CU10, inventario). AJUSTE fija el saldo
--    fisico al numero contado; exige motivo porque el kardex lo muestra en la auditoria.
CREATE OR REPLACE PROCEDURE sp_ajustar_stock(
    p_sucursal_codigo  VARCHAR,
    p_sku              VARCHAR,
    p_cantidad_contada INT,
    p_motivo           VARCHAR,
    p_usuario_email    VARCHAR DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_sucursal UUID;
    v_variante UUID;
    v_usuario  UUID;
    v_mov      BIGINT;
BEGIN
    IF p_motivo IS NULL OR btrim(p_motivo) = '' THEN
        RAISE EXCEPTION 'El ajuste de stock exige un motivo';
    END IF;

    SELECT id INTO v_sucursal FROM sucursal WHERE codigo = p_sucursal_codigo;
    IF v_sucursal IS NULL THEN
        RAISE EXCEPTION 'No existe la sucursal %', p_sucursal_codigo;
    END IF;

    SELECT id INTO v_variante FROM producto_variante WHERE sku = p_sku;
    IF v_variante IS NULL THEN
        RAISE EXCEPTION 'No existe la variante %', p_sku;
    END IF;

    SELECT id INTO v_usuario FROM usuario WHERE email = p_usuario_email;

    v_mov := fn_mover_inventario(v_sucursal, v_variante, 'AJUSTE', p_cantidad_contada,
                                 p_motivo, 'AJUSTE', NULL, v_usuario);

    RAISE NOTICE 'Ajuste de % en % registrado en el kardex (movimiento %)', p_sku, p_sucursal_codigo, v_mov;
END;
$$;

COMMENT ON PROCEDURE sp_ajustar_stock IS
    'Ajuste por recuento fisico: fija cantidad_fisica al valor contado via fn_mover_inventario.';


-- 4. Expiracion de reservas vencidas. Es lo que ejecuta el job periodico del backend
--    (app/core/jobs.py); devuelve en p_expiradas cuantas reservas expiro.
CREATE OR REPLACE PROCEDURE sp_expirar_reservas(INOUT p_expiradas INT DEFAULT 0)
LANGUAGE plpgsql AS $$
BEGIN
    p_expiradas := fn_expirar_reservas();
    RAISE NOTICE 'Reservas expiradas: %', p_expiradas;
END;
$$;

COMMENT ON PROCEDURE sp_expirar_reservas IS
    'Job de expiracion de reservas: libera el stock comprometido de las vencidas.';


-- 5. Renovacion de la suscripcion de una empresa (SaaS). El periodo nuevo arranca al vencer
--    el actual o, si ya vencio, hoy. Deja el pago en el historial y reactiva la suscripcion.
CREATE OR REPLACE PROCEDURE sp_renovar_suscripcion(
    p_empresa_slug VARCHAR,
    p_meses        INT,
    p_metodo       VARCHAR DEFAULT 'TRANSFERENCIA'
)
LANGUAGE plpgsql AS $$
DECLARE
    v_sus    suscripcion%ROWTYPE;
    v_precio NUMERIC(12,2);
    v_desde  TIMESTAMPTZ;
    v_hasta  TIMESTAMPTZ;
BEGIN
    IF p_meses NOT BETWEEN 1 AND 12 THEN
        RAISE EXCEPTION 'Se puede renovar de 1 a 12 meses (recibido: %)', p_meses;
    END IF;

    SELECT su.* INTO v_sus
      FROM suscripcion su
      JOIN empresa e ON e.id = su.empresa_id
     WHERE e.slug = p_empresa_slug
       FOR UPDATE OF su;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La empresa % no tiene suscripcion', p_empresa_slug;
    END IF;

    SELECT precio_mensual INTO v_precio FROM plan WHERE id = v_sus.plan_id;
    v_desde := GREATEST(v_sus.vence_en, now());
    v_hasta := v_desde + make_interval(months => p_meses);

    INSERT INTO pago_suscripcion (suscripcion_id, plan_id, meses, monto, metodo, estado,
                                  periodo_desde, periodo_hasta, confirmado_en)
    VALUES (v_sus.id, v_sus.plan_id, p_meses, v_precio * p_meses, p_metodo, 'APROBADO',
            v_desde, v_hasta, now());

    UPDATE suscripcion
       SET estado = 'ACTIVA', vence_en = v_hasta, actualizado_en = now()
     WHERE id = v_sus.id;

    RAISE NOTICE 'Suscripcion de % renovada hasta % (Bs %)', p_empresa_slug, v_hasta::date, v_precio * p_meses;
END;
$$;

COMMENT ON PROCEDURE sp_renovar_suscripcion IS
    'SaaS: renueva la suscripcion de una empresa N meses y registra el pago.';


-- ---------------------------------------------------------------------
--  8.2.6.2  FUNCIONES
--  Copia de db/02_logica.sql: es el codigo que corre en produccion.
-- ---------------------------------------------------------------------

