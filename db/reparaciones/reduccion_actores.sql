-- =====================================================================
--  Reparacion/migracion: reduccion de actores (PENDIENTES 2.19.1.d y 3.1)
--
--  Actores humanos que quedan: Cliente, Administrador, Encargado de sucursal y Cajero.
--    - El ENCARGADO absorbe lo que hacia ALMACEN (recepciones CU09, ajustes de stock) y
--      puede cubrir la caja (caja.* + ventas.crear).
--    - El CAJERO absorbe lo que hacia VENDEDOR (venta en piso) y verifica pagos QR/efectivo.
--    - El proveedor no es usuario: sus datos los carga el ADMIN en CU11 (sin cambios de datos).
--
--  Que hace, sobre una base YA desplegada (Railway) que no se puede recrear con
--  "docker compose down -v":
--    1. empleado.cargo  VENDEDOR -> CAJERO, ALMACEN -> ENCARGADO.
--    2. usuarios con rol VENDEDOR -> rol CAJERO, rol ALMACEN -> rol ENCARGADO; borra esos dos
--       roles y su rol_permiso.
--    3. Da al ENCARGADO caja.leer/caja.crear/caja.actualizar/ventas.crear (CU07 ahora se
--       autoriza por el permiso caja.crear y CU08 por reservas.actualizar, ver
--       get_cajero_actual/get_encargado_actual en backend/app/core/deps.py).
--    4. Actualiza las descripciones de caja.crear y reservas.actualizar (cosmetico).
--    5. Cuentas demo del seed: vendedor.scz -> cajera.scz (CAJERO, Equipetrol),
--       almacen.scz -> encargado.cbba (ENCARGADO, Cala Cala) y crea cajera.lapaz (CAJERO,
--       Sopocachi) si no existe. Solo si esas cuentas existen / faltan: en una base sin el
--       seed demo no hace nada.
--    6. Recrea el ENUM cargo_empleado como ('ENCARGADO','CAJERO') (Postgres no tiene
--       ALTER TYPE ... DROP VALUE).
--
--  Es re-ejecutable: cada paso se guarda por existencia (roles, emails, valores del ENUM).
--  Requisito: si la base todavia tiene el cargo REPARTIDOR, correr ANTES
--  cu20_delivery_simplificado.sql (ese script reasigna REPARTIDOR -> ALMACEN y, despues de
--  este, ALMACEN ya no existe).
--
--  Despues de correrlo: reiniciar el backend (asyncpg cachea el OID del tipo cargo_empleado
--  en sus sentencias preparadas y el tipo se recreo) y volver a iniciar sesion en web/movil
--  para que UsuarioOut traiga los permisos nuevos.
--
--  Uso:
--    docker run --rm -i postgres:16 psql "<DATABASE_PUBLIC_URL>" -v ON_ERROR_STOP=1 \
--      < db/reparaciones/reduccion_actores.sql
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. Cargos de empleado (comparando como texto: funciona aunque el ENUM ya no los tenga)
-- ---------------------------------------------------------------------

UPDATE empleado SET cargo = 'CAJERO'    WHERE cargo::text = 'VENDEDOR';
UPDATE empleado SET cargo = 'ENCARGADO' WHERE cargo::text = 'ALMACEN';

-- ---------------------------------------------------------------------
-- 2. Roles VENDEDOR y ALMACEN: sus usuarios pasan al rol equivalente y los roles se borran
-- ---------------------------------------------------------------------

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM rol WHERE nombre = 'VENDEDOR') THEN
        UPDATE usuario SET rol_id = (SELECT id FROM rol WHERE nombre = 'CAJERO')
         WHERE rol_id = (SELECT id FROM rol WHERE nombre = 'VENDEDOR');
        DELETE FROM rol_permiso WHERE rol_id = (SELECT id FROM rol WHERE nombre = 'VENDEDOR');
        DELETE FROM rol WHERE nombre = 'VENDEDOR';
    END IF;

    IF EXISTS (SELECT 1 FROM rol WHERE nombre = 'ALMACEN') THEN
        UPDATE usuario SET rol_id = (SELECT id FROM rol WHERE nombre = 'ENCARGADO')
         WHERE rol_id = (SELECT id FROM rol WHERE nombre = 'ALMACEN');
        DELETE FROM rol_permiso WHERE rol_id = (SELECT id FROM rol WHERE nombre = 'ALMACEN');
        DELETE FROM rol WHERE nombre = 'ALMACEN';
    END IF;
END
$$;

UPDATE rol SET descripcion = 'Maneja caja, ventas presenciales y verificacion de pagos'
 WHERE nombre = 'CAJERO';

-- ---------------------------------------------------------------------
-- 3. El ENCARGADO puede cubrir la caja. El ADMIN ya tiene todos los permisos, pero se
--    re-asegura por si su matriz se edito desde CU13.
-- ---------------------------------------------------------------------

INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id
  FROM rol r
  JOIN permiso p ON p.codigo IN ('caja.leer','caja.crear','caja.actualizar','ventas.crear')
 WHERE r.nombre IN ('ENCARGADO','ADMIN')
ON CONFLICT DO NOTHING;

INSERT INTO rol_permiso (rol_id, permiso_id)
SELECT r.id, p.id
  FROM rol r
  JOIN permiso p ON p.codigo IN ('reservas.leer','reservas.actualizar')
 WHERE r.nombre IN ('ENCARGADO','ADMIN')
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 4. Descripciones (cosmetico)
-- ---------------------------------------------------------------------

UPDATE permiso
   SET descripcion = 'Operar la caja de su sucursal: abrir sesion, vender, verificar pagos QR/efectivo (CU07)'
 WHERE codigo = 'caja.crear';
UPDATE permiso
   SET descripcion = 'Atender reservas de su sucursal: confirmar, rechazar, preparar, resolver (CU08)'
 WHERE codigo = 'reservas.actualizar';

-- ---------------------------------------------------------------------
-- 5. Cuentas demo del seed (ver db/03_datos_iniciales.sql). Cada sucursal queda con al
--    menos un ENCARGADO y un CAJERO.
-- ---------------------------------------------------------------------

UPDATE usuario SET email = 'cajera.scz@fashionstore.bo'
 WHERE email = 'vendedor.scz@fashionstore.bo'
   AND NOT EXISTS (SELECT 1 FROM usuario WHERE email = 'cajera.scz@fashionstore.bo');

UPDATE usuario SET email = 'encargado.cbba@fashionstore.bo'
 WHERE email = 'almacen.scz@fashionstore.bo'
   AND NOT EXISTS (SELECT 1 FROM usuario WHERE email = 'encargado.cbba@fashionstore.bo');

-- Ruben (ex ALMACEN de Equipetrol) pasa a encargar Cala Cala, que no tenia encargado.
UPDATE empleado SET sucursal_id = (SELECT id FROM sucursal WHERE codigo = 'CB-01')
 WHERE usuario_id = (SELECT id FROM usuario WHERE email = 'encargado.cbba@fashionstore.bo')
   AND EXISTS (SELECT 1 FROM sucursal WHERE codigo = 'CB-01');

-- Sopocachi no tenia cajero. Solo se crea si la base trae el seed demo (existe LP-01 y la
-- encargada de La Paz) y la cuenta todavia no existe.
INSERT INTO usuario (email, password_hash, nombre, apellido, tipo, rol_id, email_verificado)
SELECT 'cajera.lapaz@fashionstore.bo', crypt('demo1234', gen_salt('bf')), 'Lucia', 'Condori',
       'STAFF', (SELECT id FROM rol WHERE nombre = 'CAJERO'), TRUE
 WHERE EXISTS (SELECT 1 FROM usuario WHERE email = 'encargada.lapaz@fashionstore.bo')
   AND EXISTS (SELECT 1 FROM sucursal WHERE codigo = 'LP-01')
   AND NOT EXISTS (SELECT 1 FROM usuario WHERE email = 'cajera.lapaz@fashionstore.bo');

INSERT INTO empleado (usuario_id, sucursal_id, cargo, fecha_ingreso)
SELECT u.id, (SELECT id FROM sucursal WHERE codigo = 'LP-01'), 'CAJERO', CURRENT_DATE
  FROM usuario u
 WHERE u.email = 'cajera.lapaz@fashionstore.bo'
   AND NOT EXISTS (SELECT 1 FROM empleado e WHERE e.usuario_id = u.id);

COMMIT;

-- ---------------------------------------------------------------------
-- 6. Recrear cargo_empleado sin VENDEDOR/ALMACEN. Fuera de la transaccion anterior, en su
--    propio bloque, igual que cu20_delivery_simplificado.sql.
-- ---------------------------------------------------------------------

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
                WHERE t.typname = 'cargo_empleado'
                  AND e.enumlabel NOT IN ('ENCARGADO','CAJERO')) THEN
        CREATE TYPE cargo_empleado_nuevo AS ENUM ('ENCARGADO','CAJERO');

        ALTER TABLE empleado ALTER COLUMN cargo TYPE cargo_empleado_nuevo
            USING cargo::text::cargo_empleado_nuevo;

        DROP TYPE cargo_empleado;
        ALTER TYPE cargo_empleado_nuevo RENAME TO cargo_empleado;
    END IF;
END
$$;

-- Resultado esperado: 0 roles viejos, cargos {ENCARGADO,CAJERO}, y cada sucursal activa con
-- su cantidad de encargados y cajeros (en la base demo: 1 y 1 en cada una de las 3).
SELECT (SELECT count(*) FROM rol WHERE nombre IN ('VENDEDOR','ALMACEN')) AS roles_viejos,
       (SELECT array_agg(enumlabel ORDER BY enumsortorder) FROM pg_enum e
          JOIN pg_type t ON t.oid = e.enumtypid
         WHERE t.typname = 'cargo_empleado')                             AS cargos_actuales;

SELECT s.codigo,
       count(*) FILTER (WHERE e.cargo = 'ENCARGADO') AS encargados,
       count(*) FILTER (WHERE e.cargo = 'CAJERO')    AS cajeros
  FROM sucursal s
  LEFT JOIN empleado e ON e.sucursal_id = s.id AND e.activo
 WHERE s.activa
 GROUP BY s.codigo
 ORDER BY s.codigo;

SELECT r.nombre, count(rp.permiso_id) AS permisos
  FROM rol r LEFT JOIN rol_permiso rp ON rp.rol_id = r.id
 GROUP BY r.nombre ORDER BY r.nombre;
