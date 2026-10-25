-- #####################################################################
--  FashionStore - Plataforma SaaS de comercio electronico para moda femenina
--  BASE DE DATOS: documento SQL para el informe (Capitulo 8 - Diseno de Datos)
--  PostgreSQL 16  |  Sistemas II - S2-2026
--
--  Contenido (mismo orden que el indice del documento):
--    8.2.2  Script SQL ............ creacion de la base: extensiones, ENUM, 51 tablas, indices
--                                   y vistas (copia fiel de db/01_schema.sql y de las vistas de
--                                   db/02_logica.sql)
--    8.2.4  Poblacion
--           8.2.4.1 Insert ........ datos de ejemplo de las 3 empresas (tenants)
--           8.2.4.2 Update ........ modificaciones tipicas de la operacion
--           8.2.4.3 Delete ........ bajas fisicas, logicas y en cascada
--    8.2.5  Consultas
--           8.2.5.1 Simples ....... una sola tabla
--           8.2.5.2 Dobles ........ dos tablas (JOIN)
--           8.2.5.3 Multiples ..... tres o mas tablas
--           8.2.5.4 Subconsultas .. IN, EXISTS, escalares, correlacionadas y CTE
--    8.2.6  Procedimientos almacenados
--           8.2.6.1 Procedimientos  CREATE PROCEDURE (se invocan con CALL)
--           8.2.6.2 Funciones ..... CREATE FUNCTION (logica central del inventario, caja,
--                                   reservas y delivery; copia de db/02_logica.sql)
--           8.2.6.3 Triggers ...... disparadores que mueven el stock y llevan las bitacoras
--           8.2.6.4 Pruebas ....... ejecucion de procedimientos, funciones y triggers
--
--  Como ejecutarlo (base vacia, de punta a punta):
--      createdb fashionstore_doc
--      psql -d fashionstore_doc -f FASHIONSTORE_BD.sql
--
--  Nota sobre el orden: la poblacion (8.2.4) se carga ANTES de crear los triggers (8.2.6.3),
--  porque asi lo pide el orden del documento. Por eso en 8.2.4.1 el stock comprometido por las
--  reservas y el descontado por las ventas de ejemplo se refleja con un UPDATE explicito; en el
--  sistema real eso lo hacen los triggers, y en 8.2.6.4 se ve cada uno funcionando.
--
--  Password de todos los usuarios de ejemplo: demo1234 (se guarda con bcrypt via pgcrypto).
-- #####################################################################


-- =====================================================================
--  8.2.2  SCRIPT SQL - CREACION DE LA BASE DE DATOS
-- =====================================================================
-- Si se ejecuta desde psql como superusuario se puede crear la base primero:
--   CREATE DATABASE fashionstore ENCODING 'UTF8' TEMPLATE template0;
--   \c fashionstore

-- ---------------------------------------------------------------------
-- EXTENSIONES
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS unaccent;   -- busqueda del catalogo sin tildes
-- CREATE EXTENSION IF NOT EXISTS vector;  -- pgvector: descomentar para el recomendador
 
 
-- ---------------------------------------------------------------------
-- TIPOS ENUMERADOS
-- ---------------------------------------------------------------------
CREATE TYPE ciudad_bo         AS ENUM ('SANTA_CRUZ','LA_PAZ','EL_ALTO','COCHABAMBA','SUCRE',
                                       'ORURO','POTOSI','TARIJA','TRINIDAD','COBIJA');
CREATE TYPE tipo_usuario      AS ENUM ('CLIENTE','STAFF');
CREATE TYPE cargo_empleado    AS ENUM ('ENCARGADO','CAJERO','VENDEDOR','ALMACEN');
CREATE TYPE estado_caja       AS ENUM ('ABIERTA','CERRADA');
CREATE TYPE tipo_talla        AS ENUM ('LETRA','NUMERO','CALZADO');
CREATE TYPE tipo_temporada    AS ENUM ('PRIMAVERA_VERANO','OTONO_INVIERNO','ESCOLAR',
                                       'PROMOCION','NUEVA_COLECCION');
CREATE TYPE genero_prenda     AS ENUM ('HOMBRE','MUJER','UNISEX','NINO','NINA');
CREATE TYPE uso_imagen        AS ENUM ('CATALOGO','AR_OVERLAY','AR_MODELO');
CREATE TYPE formato_imagen    AS ENUM ('JPG','PNG','GLB','USDZ');
CREATE TYPE tipo_promocion    AS ENUM ('PORCENTAJE','MONTO_FIJO');
CREATE TYPE alcance_promocion AS ENUM ('TODO','CATEGORIA','TEMPORADA');
CREATE TYPE tipo_movimiento   AS ENUM ('ENTRADA','SALIDA','RESERVA','LIBERACION','AJUSTE',
                                       'DEVOLUCION','TRASPASO_ENT','TRASPASO_SAL');
CREATE TYPE estado_recepcion  AS ENUM ('BORRADOR','CONFIRMADA','ANULADA');
CREATE TYPE estado_traspaso   AS ENUM ('SOLICITADO','EN_TRANSITO','RECIBIDO','ANULADO');
CREATE TYPE estado_reserva    AS ENUM ('PENDIENTE','CONFIRMADA','PREPARADA','CLIENTE_PRESENTE',
                                       'ATENDIDA','CONVERTIDA','CANCELADA','EXPIRADA');
-- PROBADO no lo usa ningun flujo: al resolver la reserva (CU08) cada prenda PREPARADO pasa
-- directo a COMPRADO o DESCARTADO. Queda en el tipo porque Postgres no permite quitar un valor de
-- un ENUM sin recrearlo (y con el las columnas que lo usan).
CREATE TYPE estado_item_res   AS ENUM ('RESERVADO','PREPARADO','PROBADO','COMPRADO','DESCARTADO');
CREATE TYPE estado_carrito    AS ENUM ('ACTIVO','CONVERTIDO','ABANDONADO');
CREATE TYPE canal_venta       AS ENUM ('WEB','MOVIL','POS');
CREATE TYPE modo_entrega      AS ENUM ('RETIRO_SUCURSAL','DOMICILIO');
CREATE TYPE estado_venta      AS ENUM ('PENDIENTE','PAGADA','ENTREGADA','ANULADA');
CREATE TYPE estado_envio      AS ENUM ('PENDIENTE','DESPACHADO','ENTREGADO','FALLIDO','CANCELADO');
CREATE TYPE metodo_pago       AS ENUM ('EFECTIVO','TARJETA','QR','TRANSFERENCIA','PASARELA');
CREATE TYPE pasarela_pago     AS ENUM ('STRIPE','QR');
CREATE TYPE estado_pago       AS ENUM ('PENDIENTE','APROBADO','RECHAZADO','REEMBOLSADO');
CREATE TYPE tipo_comprobante  AS ENUM ('RECIBO','FACTURA');
CREATE TYPE estado_devolucion AS ENUM ('SOLICITADA','APROBADA','RECHAZADA');
-- Segundo parcial (PENDIENTES 5.8): por que vuelve la prenda. TALLA/COLOR son cambios (la clienta
-- se lleva otra variante de la misma prenda); el resto son devoluciones con reintegro.
CREATE TYPE motivo_devolucion AS ENUM ('TALLA','COLOR','DEFECTO','NO_GUSTO','OTRO');
-- Bloque 8 (SaaS): estado de la suscripcion de un tenant (empresa).
CREATE TYPE estado_suscripcion AS ENUM ('PRUEBA','ACTIVA','VENCIDA','CANCELADA');
CREATE TYPE tipo_notificacion AS ENUM ('RESERVA','VENTA','STOCK','PROMO','SUSCRIPCION');
CREATE TYPE accion_auditoria  AS ENUM ('CREAR','ACTUALIZAR','ELIMINAR','LOGIN');
-- Sincronizacion offline (PWA y Flutter): resultado de una operacion registrada sin conexion.
-- 'registrada localmente' y 'enviada' viven solo en el cliente; el servidor decide estos tres.
CREATE TYPE estado_operacion_sync AS ENUM ('CONFIRMADA','RECHAZADA','CONFLICTO');
CREATE TYPE tipo_operacion_sync   AS ENUM ('VENTA','RESERVA');
 
 
-- =====================================================================
--  BLOQUE 0 - TENANT
-- =====================================================================

-- La empresa contratante del SaaS. Todo dato de negocio cuelga de una (directo con empresa_id,
-- o a traves de su sucursal); la plataforma (SUPERADMIN) es la unica que ve todas.
CREATE TABLE empresa (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    slug         VARCHAR(40)  NOT NULL UNIQUE,   -- identifica la tienda publica (?empresa=slug)
    nombre       VARCHAR(120) NOT NULL,
    razon_social VARCHAR(180) NOT NULL,
    nit          VARCHAR(30)  NOT NULL,
    email        VARCHAR(150),
    telefono     VARCHAR(30),
    activa       BOOLEAN      NOT NULL DEFAULT TRUE,
    creada_en    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT ck_empresa_slug CHECK (slug ~ '^[a-z0-9][a-z0-9-]{1,38}$')
);
COMMENT ON TABLE empresa IS
    'Tenant del SaaS. Sus datos de facturacion (razon social, NIT) reemplazan a los que vivian '
    'en configuracion cuando el sistema era de una sola cadena.';


-- =====================================================================
--  BLOQUE 1 - USUARIOS Y ACCESO
-- =====================================================================

CREATE TABLE rol (
    id          SERIAL PRIMARY KEY,
    -- NULL = rol del sistema, compartido por todas las empresas (no se edita); con valor = rol
    -- propio que una empresa creo en CU13 y que solo ella ve.
    empresa_id  UUID         REFERENCES empresa(id) ON DELETE CASCADE,
    nombre      VARCHAR(60)  NOT NULL,
    descripcion VARCHAR(200),
    es_sistema  BOOLEAN      NOT NULL DEFAULT FALSE,
    CONSTRAINT ck_rol_sistema CHECK (NOT es_sistema OR empresa_id IS NULL)
);
-- el nombre no se repite dentro de una empresa; los del sistema son unicos entre si
CREATE UNIQUE INDEX ux_rol_nombre_empresa ON rol(empresa_id, nombre) WHERE empresa_id IS NOT NULL;
CREATE UNIQUE INDEX ux_rol_nombre_sistema ON rol(nombre) WHERE empresa_id IS NULL;
COMMENT ON TABLE rol IS 'SUPERADMIN (plataforma), ADMIN (de empresa), ENCARGADO, CAJERO, VENDEDOR, ALMACEN (los del sistema; CU13 puede crear otros por empresa). Solo aplica a usuarios STAFF.';
 
CREATE TABLE permiso (
    id          SERIAL PRIMARY KEY,
    codigo      VARCHAR(80) NOT NULL UNIQUE,
    modulo      VARCHAR(50) NOT NULL,
    descripcion VARCHAR(200)
);
 
CREATE TABLE rol_permiso (
    rol_id     INT NOT NULL REFERENCES rol(id)     ON DELETE CASCADE,
    permiso_id INT NOT NULL REFERENCES permiso(id) ON DELETE CASCADE,
    PRIMARY KEY (rol_id, permiso_id)
);
 
CREATE TABLE usuario (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    email            VARCHAR(150) NOT NULL UNIQUE,
    password_hash    VARCHAR(255) NOT NULL,
    nombre           VARCHAR(80)  NOT NULL,
    apellido         VARCHAR(80)  NOT NULL,
    telefono         VARCHAR(30),
    foto_url         TEXT,
    tipo             tipo_usuario NOT NULL DEFAULT 'CLIENTE',
    rol_id           INT REFERENCES rol(id) ON DELETE SET NULL,
    -- Tenant del personal. NULL para el SUPERADMIN de la plataforma y para las clientas: la
    -- cuenta de una clienta es de la plataforma (puede comprar en cualquier tienda) y la cartera
    -- de cada empresa vive en cliente_perfil_tenant.
    empresa_id       UUID REFERENCES empresa(id),
    email_verificado BOOLEAN      NOT NULL DEFAULT FALSE,
    activo           BOOLEAN      NOT NULL DEFAULT TRUE,
    ultimo_acceso    TIMESTAMPTZ,
    -- intentos maximos de login: intentos_fallidos cuenta contrasenas incorrectas
    -- consecutivas y se resetea en un login exitoso o al bloquear (bloqueado_hasta).
    -- Los umbrales (cuantos intentos, cuantos minutos) viven en `configuracion`
    -- (login_max_intentos / login_bloqueo_minutos), no hardcodeados en Python.
    intentos_fallidos SMALLINT    NOT NULL DEFAULT 0,
    bloqueado_hasta  TIMESTAMPTZ,
    creado_en        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    -- un STAFF sin rol no puede hacer nada; un CLIENTE no debe tener rol operativo
    CONSTRAINT ck_usuario_rol CHECK (
        (tipo = 'STAFF'   AND rol_id IS NOT NULL) OR
        (tipo = 'CLIENTE' AND rol_id IS NULL)
    )
);
CREATE INDEX ix_usuario_tipo ON usuario(tipo) WHERE activo;
CREATE INDEX ix_usuario_empresa ON usuario(empresa_id) WHERE empresa_id IS NOT NULL;
 
CREATE TABLE talla (
    id     SERIAL      PRIMARY KEY,
    codigo VARCHAR(10) NOT NULL,
    tipo   tipo_talla  NOT NULL,
    orden  INT         NOT NULL DEFAULT 0,
    UNIQUE (codigo, tipo)
);
 
CREATE TABLE color (
    id          SERIAL      PRIMARY KEY,
    nombre      VARCHAR(50) NOT NULL UNIQUE,
    codigo_hex  CHAR(7)     NOT NULL,
    CONSTRAINT ck_color_hex CHECK (codigo_hex ~ '^#[0-9A-Fa-f]{6}$')
);
 
CREATE TABLE perfil_cliente (
    usuario_id        UUID PRIMARY KEY REFERENCES usuario(id) ON DELETE CASCADE,
    talla_superior_id INT  REFERENCES talla(id),
    talla_inferior_id INT  REFERENCES talla(id),
    talla_calzado_id  INT  REFERENCES talla(id),
    color_favorito_id INT  REFERENCES color(id),
    fecha_nacimiento  DATE,
    puntos_fidelidad  INT     NOT NULL DEFAULT 0,
    acepta_marketing  BOOLEAN NOT NULL DEFAULT FALSE
);
COMMENT ON TABLE perfil_cliente IS
    'Preferencias declaradas. Junto con el historial de compras alimenta al recomendador.';
 
CREATE TABLE direccion (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id   UUID         NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    alias        VARCHAR(50)  NOT NULL,
    ciudad       ciudad_bo    NOT NULL,
    direccion    VARCHAR(250) NOT NULL,
    referencia   VARCHAR(250),
    latitud      NUMERIC(10,7),
    longitud     NUMERIC(10,7),
    es_principal BOOLEAN      NOT NULL DEFAULT FALSE
);
CREATE INDEX ix_direccion_usuario ON direccion(usuario_id);
-- una sola direccion principal por cliente
CREATE UNIQUE INDEX ux_direccion_principal ON direccion(usuario_id) WHERE es_principal;
 
CREATE TABLE sesion_token (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id UUID         NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    expira_en  TIMESTAMPTZ  NOT NULL,
    ip         INET,
    user_agent TEXT,
    revocado   BOOLEAN      NOT NULL DEFAULT FALSE
);
CREATE INDEX ix_sesion_usuario ON sesion_token(usuario_id) WHERE NOT revocado;
 
 
-- =====================================================================
--  BLOQUE 2 - ORGANIZACION
-- =====================================================================
 
CREATE TABLE sucursal (
    id                  UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id          UUID         NOT NULL REFERENCES empresa(id),
    codigo              VARCHAR(20)  NOT NULL UNIQUE,
    nombre              VARCHAR(120) NOT NULL,
    ciudad              ciudad_bo    NOT NULL,
    direccion           VARCHAR(250) NOT NULL,
    latitud             NUMERIC(10,7),
    longitud            NUMERIC(10,7),
    telefono            VARCHAR(30),
    hora_apertura       TIME,
    hora_cierre         TIME,
    cantidad_vestidores INT          NOT NULL DEFAULT 0,
    activa              BOOLEAN      NOT NULL DEFAULT TRUE
);
CREATE INDEX ix_sucursal_empresa ON sucursal(empresa_id) WHERE activa;
 
CREATE TABLE empleado (
    usuario_id    UUID           PRIMARY KEY REFERENCES usuario(id) ON DELETE CASCADE,
    sucursal_id   UUID           NOT NULL REFERENCES sucursal(id),
    ci            VARCHAR(20),
    cargo         cargo_empleado NOT NULL,
    fecha_ingreso DATE,
    activo        BOOLEAN        NOT NULL DEFAULT TRUE
);
CREATE INDEX ix_empleado_sucursal ON empleado(sucursal_id) WHERE activo;
COMMENT ON TABLE empleado IS 'Extiende al usuario STAFF y lo ata a una sucursal.';
 
CREATE TABLE caja (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    sucursal_id UUID        NOT NULL REFERENCES sucursal(id),
    codigo      VARCHAR(20) NOT NULL,
    nombre      VARCHAR(60) NOT NULL,
    activa      BOOLEAN     NOT NULL DEFAULT TRUE,
    UNIQUE (sucursal_id, codigo)
);
 
CREATE TABLE sesion_caja (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    caja_id         UUID          NOT NULL REFERENCES caja(id),
    empleado_id     UUID          NOT NULL REFERENCES empleado(usuario_id),
    abierta_en      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    monto_inicial   NUMERIC(12,2) NOT NULL DEFAULT 0,
    cerrada_en      TIMESTAMPTZ,
    monto_sistema   NUMERIC(12,2),
    monto_declarado NUMERIC(12,2),
    diferencia      NUMERIC(12,2) GENERATED ALWAYS AS (monto_declarado - monto_sistema) STORED,
    estado          estado_caja   NOT NULL DEFAULT 'ABIERTA',
    CONSTRAINT ck_sesion_cierre CHECK (
        (estado = 'ABIERTA' AND cerrada_en IS NULL) OR
        (estado = 'CERRADA' AND cerrada_en IS NOT NULL)
    )
);
-- una sola sesion abierta por caja
CREATE UNIQUE INDEX ux_sesion_caja_abierta ON sesion_caja(caja_id) WHERE estado = 'ABIERTA';
 
 
-- =====================================================================
--  BLOQUE 3 - CATALOGO
-- =====================================================================
 
-- Todo el bloque es por tenant: cada empresa arma su propio catalogo (empresa_id NOT NULL).
-- talla y color (bloque 1) son datos de referencia de la plataforma: la curva de tallas y la
-- paleta son las mismas para cualquier tienda de ropa, asi que se comparten.
CREATE TABLE proveedor (
    id       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID       NOT NULL REFERENCES empresa(id),
    nombre   VARCHAR(150) NOT NULL,
    nit      VARCHAR(30),
    contacto VARCHAR(120),
    email    VARCHAR(120),
    telefono VARCHAR(30),
    activo   BOOLEAN      NOT NULL DEFAULT TRUE
);
 
CREATE TABLE categoria (
    id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id         UUID        NOT NULL REFERENCES empresa(id),
    categoria_padre_id UUID        REFERENCES categoria(id) ON DELETE SET NULL,
    nombre             VARCHAR(80) NOT NULL,
    slug               VARCHAR(80) NOT NULL,
    imagen_url         TEXT,
    orden              INT         NOT NULL DEFAULT 0,
    activa             BOOLEAN     NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_categoria_padre CHECK (categoria_padre_id <> id),
    UNIQUE (empresa_id, slug)
);
 
CREATE TABLE marca (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id UUID        NOT NULL REFERENCES empresa(id),
    nombre     VARCHAR(80) NOT NULL,
    logo_url   TEXT,
    UNIQUE (empresa_id, nombre)
);
 
CREATE TABLE temporada (
    id           UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id   UUID           NOT NULL REFERENCES empresa(id),
    nombre       VARCHAR(80)    NOT NULL,
    tipo         tipo_temporada NOT NULL,
    fecha_inicio DATE           NOT NULL,
    fecha_fin    DATE           NOT NULL,
    activa       BOOLEAN        NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_temporada_fechas CHECK (fecha_fin >= fecha_inicio)
);
 
CREATE TABLE coleccion (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id   UUID         NOT NULL REFERENCES empresa(id),
    temporada_id UUID         NOT NULL REFERENCES temporada(id),
    proveedor_id UUID         REFERENCES proveedor(id),
    nombre       VARCHAR(120) NOT NULL,
    descripcion  TEXT,
    anio         INT,
    imagen_url   TEXT,
    activa       BOOLEAN      NOT NULL DEFAULT TRUE
);
 
CREATE TABLE producto (
    id           UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id   UUID          NOT NULL REFERENCES empresa(id),
    categoria_id UUID          NOT NULL REFERENCES categoria(id),
    marca_id     UUID          REFERENCES marca(id),
    proveedor_id UUID          REFERENCES proveedor(id),
    temporada_id UUID          REFERENCES temporada(id),
    coleccion_id UUID          REFERENCES coleccion(id),
    codigo       VARCHAR(40)   NOT NULL,
    nombre       VARCHAR(180)  NOT NULL,
    slug         VARCHAR(180)  NOT NULL,
    descripcion  TEXT,
    material     VARCHAR(120),
    genero       genero_prenda,
    precio_base  NUMERIC(12,2) NOT NULL CHECK (precio_base >= 0),
    activo       BOOLEAN       NOT NULL DEFAULT TRUE,
    destacado    BOOLEAN       NOT NULL DEFAULT FALSE,
    -- embedding  vector(768),   -- descomentar junto con la extension vector
    creado_en    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    UNIQUE (empresa_id, codigo),
    UNIQUE (empresa_id, slug)
);
CREATE INDEX ix_producto_empresa   ON producto(empresa_id) WHERE activo;
CREATE INDEX ix_producto_categoria ON producto(categoria_id) WHERE activo;
CREATE INDEX ix_producto_temporada ON producto(temporada_id) WHERE activo;
CREATE INDEX ix_producto_busqueda  ON producto
    USING gin (to_tsvector('spanish', nombre || ' ' || coalesce(descripcion,'')));
COMMENT ON TABLE producto IS
    'El MODELO de prenda: lo descriptivo. El stock NO vive aca sino en producto_variante.';
 
CREATE TABLE producto_variante (
    id            UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    producto_id   UUID          NOT NULL REFERENCES producto(id) ON DELETE CASCADE,
    talla_id      INT           NOT NULL REFERENCES talla(id),
    color_id      INT           NOT NULL REFERENCES color(id),
    sku           VARCHAR(60)   NOT NULL UNIQUE,
    codigo_barras VARCHAR(60)   UNIQUE,
    precio        NUMERIC(12,2) CHECK (precio >= 0),
    precio_oferta NUMERIC(12,2) CHECK (precio_oferta >= 0),
    activa        BOOLEAN       NOT NULL DEFAULT TRUE,
    UNIQUE (producto_id, talla_id, color_id)
);
CREATE INDEX ix_variante_producto ON producto_variante(producto_id);
COMMENT ON TABLE producto_variante IS
    'La prenda fisica concreta (producto x talla x color). Es lo que se reserva, vende e inventaria.';
 
CREATE TABLE producto_imagen (
    id           UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    producto_id  UUID           NOT NULL REFERENCES producto(id) ON DELETE CASCADE,
    color_id     INT            REFERENCES color(id),
    uso          uso_imagen     NOT NULL DEFAULT 'CATALOGO',
    url          TEXT           NOT NULL,
    formato      formato_imagen,
    anclajes     JSONB,
    escala_base  NUMERIC(6,3),
    es_principal BOOLEAN        NOT NULL DEFAULT FALSE,
    orden        INT            NOT NULL DEFAULT 0
);
CREATE INDEX ix_imagen_producto ON producto_imagen(producto_id, uso);
COMMENT ON COLUMN producto_imagen.anclajes IS
    'Puntos de anclaje del overlay para el vestidor virtual (hombros, torso). Solo para uso = AR_*.';
 
CREATE TABLE promocion (
    id            UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id    UUID              NOT NULL REFERENCES empresa(id),
    nombre        VARCHAR(120)      NOT NULL,
    codigo_cupon  VARCHAR(40)       NOT NULL,
    tipo          tipo_promocion    NOT NULL,
    valor         NUMERIC(10,2)     NOT NULL CHECK (valor > 0),
    alcance       alcance_promocion NOT NULL DEFAULT 'TODO',
    categoria_id  UUID              REFERENCES categoria(id),
    temporada_id  UUID              REFERENCES temporada(id),
    monto_minimo  NUMERIC(12,2),
    fecha_inicio  DATE              NOT NULL,
    fecha_fin     DATE              NOT NULL,
    uso_maximo    INT,
    usos_actuales INT               NOT NULL DEFAULT 0,
    activa        BOOLEAN           NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_promo_fechas  CHECK (fecha_fin >= fecha_inicio),
    CONSTRAINT ck_promo_alcance CHECK (
        (alcance = 'TODO'      AND categoria_id IS NULL     AND temporada_id IS NULL) OR
        (alcance = 'CATEGORIA' AND categoria_id IS NOT NULL AND temporada_id IS NULL) OR
        (alcance = 'TEMPORADA' AND temporada_id IS NOT NULL AND categoria_id IS NULL)
    ),
    CONSTRAINT ck_promo_porcentaje CHECK (tipo <> 'PORCENTAJE' OR valor <= 100),
    UNIQUE (empresa_id, codigo_cupon)
);
 
 
-- =====================================================================
--  BLOQUE 4 - INVENTARIO
-- =====================================================================
 
CREATE TABLE inventario (
    id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    sucursal_id        UUID        NOT NULL REFERENCES sucursal(id),
    variante_id        UUID        NOT NULL REFERENCES producto_variante(id) ON DELETE CASCADE,
    cantidad_fisica    INT         NOT NULL DEFAULT 0,
    cantidad_reservada INT         NOT NULL DEFAULT 0,
    disponible         INT         GENERATED ALWAYS AS (cantidad_fisica - cantidad_reservada) STORED,
    stock_minimo       INT         NOT NULL DEFAULT 0,
    ubicacion          VARCHAR(40),
    actualizado_en     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (sucursal_id, variante_id),
    -- no se puede reservar mas de lo que hay, ni tener negativos
    CONSTRAINT ck_inventario_saldos CHECK (
        cantidad_reservada >= 0 AND cantidad_fisica >= cantidad_reservada
    )
);
CREATE INDEX ix_inventario_variante ON inventario(variante_id);
CREATE INDEX ix_inventario_bajo     ON inventario(sucursal_id)
    WHERE cantidad_fisica - cantidad_reservada <= stock_minimo;
 
CREATE TABLE movimiento_inventario (
    id              BIGSERIAL       PRIMARY KEY,
    sucursal_id     UUID            NOT NULL REFERENCES sucursal(id),
    variante_id     UUID            NOT NULL REFERENCES producto_variante(id),
    tipo            tipo_movimiento NOT NULL,
    cantidad        INT             NOT NULL,
    saldo_anterior  INT             NOT NULL,
    saldo_nuevo     INT             NOT NULL,
    motivo          VARCHAR(200),
    documento_tipo  VARCHAR(30),
    documento_id    UUID,
    usuario_id      UUID            REFERENCES usuario(id),
    fecha           TIMESTAMPTZ     NOT NULL DEFAULT now(),
    -- AJUSTE guarda el saldo fisico absoluto contado, que puede ser 0 (se perdio o se danio la
    -- ultima unidad); el resto de los movimientos son deltas y tienen que ser positivos
    CONSTRAINT ck_movimiento_cantidad CHECK (
        cantidad > 0 OR (tipo = 'AJUSTE' AND cantidad = 0)
    )
);
CREATE INDEX ix_movimiento_variante ON movimiento_inventario(variante_id, fecha DESC);
CREATE INDEX ix_movimiento_documento ON movimiento_inventario(documento_tipo, documento_id);
COMMENT ON TABLE movimiento_inventario IS
    'Kardex append-only: no se actualiza ni se borra. El saldo se puede reconstruir desde aca.';
 
CREATE TABLE recepcion (
    id           UUID             PRIMARY KEY DEFAULT gen_random_uuid(),
    sucursal_id  UUID             NOT NULL REFERENCES sucursal(id),
    proveedor_id UUID             NOT NULL REFERENCES proveedor(id),
    coleccion_id UUID             REFERENCES coleccion(id),
    numero       VARCHAR(40)      NOT NULL UNIQUE,
    fecha        DATE             NOT NULL DEFAULT CURRENT_DATE,
    total        NUMERIC(12,2),
    estado       estado_recepcion NOT NULL DEFAULT 'BORRADOR',
    usuario_id   UUID             REFERENCES usuario(id)
);
 
CREATE TABLE recepcion_detalle (
    id             UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    recepcion_id   UUID          NOT NULL REFERENCES recepcion(id) ON DELETE CASCADE,
    variante_id    UUID          NOT NULL REFERENCES producto_variante(id),
    cantidad       INT           NOT NULL CHECK (cantidad > 0),
    costo_unitario NUMERIC(12,2) NOT NULL CHECK (costo_unitario >= 0)
);
 
CREATE TABLE traspaso (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    sucursal_origen_id  UUID            NOT NULL REFERENCES sucursal(id),
    sucursal_destino_id UUID            NOT NULL REFERENCES sucursal(id),
    numero              VARCHAR(40)     NOT NULL UNIQUE,
    fecha_solicitud     TIMESTAMPTZ     NOT NULL DEFAULT now(),
    fecha_recepcion     TIMESTAMPTZ,
    estado              estado_traspaso NOT NULL DEFAULT 'SOLICITADO',
    usuario_solicita_id UUID            REFERENCES usuario(id),
    usuario_recibe_id   UUID            REFERENCES usuario(id),
    -- Traspasos entre sucursales (PENDIENTES 2.7): fecha de salida del origen, quien hizo el
    -- ultimo cambio de estado (el trigger tg_traspaso_stock firma el kardex con el) y la nota
    -- del destino al recibir (p.ej. por que llego de menos).
    fecha_despacho      TIMESTAMPTZ,
    actualizado_por_id  UUID            REFERENCES usuario(id),
    observacion         VARCHAR(250),
    CONSTRAINT ck_traspaso_sucursales CHECK (sucursal_origen_id <> sucursal_destino_id)
);
COMMENT ON TABLE traspaso IS
    'Mercaderia que pasa de una sucursal a otra (las tres estan en climas distintos). '
    'SOLICITADO -> EN_TRANSITO (sale del origen) -> RECIBIDO (entra en destino lo recibido); '
    'ANULADO desde SOLICITADO o EN_TRANSITO. El stock lo mueve tg_traspaso_stock.';
 
CREATE TABLE traspaso_detalle (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    traspaso_id         UUID NOT NULL REFERENCES traspaso(id) ON DELETE CASCADE,
    variante_id         UUID NOT NULL REFERENCES producto_variante(id),
    cantidad_solicitada INT  NOT NULL CHECK (cantidad_solicitada > 0),
    cantidad_recibida   INT  CHECK (cantidad_recibida >= 0)
);
 
 
-- =====================================================================
--  BLOQUE 5 - RESERVAS (vestidor fisico)
-- =====================================================================
 
CREATE TABLE reserva (
    id                UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    operacion_id      UUID           UNIQUE,  -- reserva registrada sin conexion (ver venta)
    usuario_id        UUID           NOT NULL REFERENCES usuario(id),
    sucursal_id       UUID           NOT NULL REFERENCES sucursal(id),
    codigo            VARCHAR(20)    NOT NULL UNIQUE,
    creada_en         TIMESTAMPTZ    NOT NULL DEFAULT now(),
    fecha_visita      DATE           NOT NULL,
    hora_visita       TIME           NOT NULL,
    expira_en         TIMESTAMPTZ    NOT NULL,
    estado            estado_reserva NOT NULL DEFAULT 'PENDIENTE',
    vestidor_asignado VARCHAR(20),
    observaciones     TEXT,
    atendida_por_id   UUID           REFERENCES usuario(id),
    atendida_en       TIMESTAMPTZ
);
CREATE INDEX ix_reserva_sucursal ON reserva(sucursal_id, fecha_visita);
CREATE INDEX ix_reserva_usuario  ON reserva(usuario_id, creada_en DESC);
-- indice para el job que expira reservas vencidas
CREATE INDEX ix_reserva_vigentes ON reserva(expira_en)
    WHERE estado IN ('PENDIENTE','CONFIRMADA','PREPARADA');
COMMENT ON TABLE reserva IS
    'Compromete stock (sube cantidad_reservada) pero no lo descuenta. Vence en expira_en.';
 
CREATE TABLE reserva_detalle (
    id          UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    reserva_id  UUID            NOT NULL REFERENCES reserva(id) ON DELETE CASCADE,
    variante_id UUID            NOT NULL REFERENCES producto_variante(id),
    cantidad    INT             NOT NULL DEFAULT 1 CHECK (cantidad > 0),
    estado_item estado_item_res NOT NULL DEFAULT 'RESERVADO',
    UNIQUE (reserva_id, variante_id)
);
COMMENT ON COLUMN reserva_detalle.estado_item IS
    'Permite la conversion parcial: se prueban 5 prendas, se compran 2, el resto se libera.';
 
CREATE TABLE reserva_historial (
    id              BIGSERIAL   PRIMARY KEY,
    reserva_id      UUID        NOT NULL REFERENCES reserva(id) ON DELETE CASCADE,
    estado_anterior VARCHAR(30),
    estado_nuevo    VARCHAR(30) NOT NULL,
    usuario_id      UUID        REFERENCES usuario(id),
    comentario      VARCHAR(250),
    fecha           TIMESTAMPTZ NOT NULL DEFAULT now()
);
 
 
-- =====================================================================
--  BLOQUE 6 - VENTAS Y PAGOS
-- =====================================================================
 
CREATE TABLE carrito (
    id              UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id      UUID           REFERENCES usuario(id) ON DELETE CASCADE,
    session_anonima VARCHAR(80),
    reserva_id      UUID           REFERENCES reserva(id),
    estado          estado_carrito NOT NULL DEFAULT 'ACTIVO',
    creado_en       TIMESTAMPTZ    NOT NULL DEFAULT now(),
    actualizado_en  TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT ck_carrito_dueno CHECK (usuario_id IS NOT NULL OR session_anonima IS NOT NULL)
);
COMMENT ON COLUMN carrito.reserva_id IS
    'Si el carrito nace de "comprar lo que reserve", ancla la reserva de origen: al pagar, la '
    'venta libera y consume ese compromiso en vez de descontar contra stock libre.';
CREATE UNIQUE INDEX ux_carrito_activo ON carrito(usuario_id)
    WHERE estado = 'ACTIVO' AND usuario_id IS NOT NULL;
 
CREATE TABLE carrito_item (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    carrito_id      UUID          NOT NULL REFERENCES carrito(id) ON DELETE CASCADE,
    variante_id     UUID          NOT NULL REFERENCES producto_variante(id),
    cantidad        INT           NOT NULL CHECK (cantidad > 0),
    precio_unitario NUMERIC(12,2) NOT NULL CHECK (precio_unitario >= 0),
    agregado_en     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    UNIQUE (carrito_id, variante_id)
);
 
CREATE TABLE venta (
    id                UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    sucursal_id       UUID          NOT NULL REFERENCES sucursal(id),
    usuario_id        UUID          REFERENCES usuario(id),
    canal             canal_venta   NOT NULL,
    entrega           modo_entrega  NOT NULL DEFAULT 'RETIRO_SUCURSAL',
    direccion_id      UUID          REFERENCES direccion(id),
    reserva_id        UUID          REFERENCES reserva(id),
    carrito_id        UUID          REFERENCES carrito(id),
    sesion_caja_id    UUID          REFERENCES sesion_caja(id),
    promocion_id      UUID          REFERENCES promocion(id),
    numero            VARCHAR(40)   NOT NULL UNIQUE,
    fecha             TIMESTAMPTZ   NOT NULL DEFAULT now(),
    subtotal          NUMERIC(12,2) NOT NULL CHECK (subtotal >= 0),
    descuento         NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (descuento >= 0),
    -- CU20: tarifa del delivery cotizada al cerrar la compra. Entra en la base imponible junto
    -- con la mercaderia (el flete se factura con el mismo IVA 13%), por eso se guarda aparte
    -- del subtotal pero antes del iva.
    costo_envio       NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (costo_envio >= 0),
    iva               NUMERIC(12,2) NOT NULL DEFAULT 0,
    total             NUMERIC(12,2) NOT NULL CHECK (total >= 0),
    estado            estado_venta  NOT NULL DEFAULT 'PENDIENTE',
    registrada_por_id UUID          REFERENCES usuario(id),
    -- Venta registrada sin conexion (PWA / Flutter): el UUID que genero el cliente. UNIQUE es la
    -- ultima barrera de idempotencia (RN11): aunque dos reenvios lleguen a la vez, la base no
    -- deja crear dos ventas para la misma operacion.
    operacion_id      UUID          UNIQUE,
    -- una venta a domicilio necesita direccion; una en caja necesita sesion de caja, salvo que la
    -- venta nazca de una reserva atendida (CU08), donde el kardex de la reserva ya audita el cobro
    CONSTRAINT ck_venta_entrega CHECK (entrega <> 'DOMICILIO' OR direccion_id IS NOT NULL),
    CONSTRAINT ck_venta_pos     CHECK (canal <> 'POS' OR sesion_caja_id IS NOT NULL OR reserva_id IS NOT NULL)
);
CREATE INDEX ix_venta_sucursal ON venta(sucursal_id, fecha DESC);
CREATE INDEX ix_venta_usuario  ON venta(usuario_id, fecha DESC);
CREATE INDEX ix_venta_canal    ON venta(canal, fecha DESC);
COMMENT ON TABLE venta IS
    'Una sola entidad para los tres canales. reserva_id enlaza la venta nacida de una prueba en tienda.';
 
CREATE TABLE venta_detalle (
    id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    venta_id            UUID          NOT NULL REFERENCES venta(id) ON DELETE CASCADE,
    variante_id         UUID          NOT NULL REFERENCES producto_variante(id),
    cantidad            INT           NOT NULL CHECK (cantidad > 0),
    precio_unitario     NUMERIC(12,2) NOT NULL CHECK (precio_unitario >= 0),
    descuento_unitario  NUMERIC(12,2) NOT NULL DEFAULT 0,
    subtotal            NUMERIC(12,2) NOT NULL
);
CREATE INDEX ix_venta_detalle_variante ON venta_detalle(variante_id);
 
CREATE TABLE pago (
    id             UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    venta_id       UUID          NOT NULL REFERENCES venta(id) ON DELETE CASCADE,
    metodo         metodo_pago   NOT NULL,
    pasarela       pasarela_pago,
    monto          NUMERIC(12,2) NOT NULL CHECK (monto > 0),
    estado         estado_pago   NOT NULL DEFAULT 'PENDIENTE',
    id_transaccion VARCHAR(120),
    creado_en      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    confirmado_en  TIMESTAMPTZ,
    -- 2.19.1.c: en QR la clienta solo INFORMA que ya pago (con una referencia opcional del
    -- deposito); quien aprueba o rechaza es el CAJERO de la sucursal desde caja. Lo mismo para
    -- EFECTIVO en el checkout online (2.19.1.b): verificado_por_id guarda que cajero lo resolvio.
    informado_en       TIMESTAMPTZ,
    referencia_cliente VARCHAR(200),
    verificado_por_id  UUID      REFERENCES usuario(id),
    CONSTRAINT ck_pago_pasarela CHECK (metodo <> 'PASARELA' OR pasarela IS NOT NULL)
);
CREATE INDEX ix_pago_venta ON pago(venta_id);
CREATE UNIQUE INDEX ux_pago_transaccion ON pago(pasarela, id_transaccion)
    WHERE id_transaccion IS NOT NULL;
 
CREATE TABLE evento_pasarela (
    evento_externo_id VARCHAR(120) PRIMARY KEY,
    pasarela          VARCHAR(30)  NOT NULL,
    pago_id           UUID         REFERENCES pago(id),
    recibido_en       TIMESTAMPTZ  NOT NULL DEFAULT now()
);
COMMENT ON TABLE evento_pasarela IS
    'Candado de idempotencia: antes de procesar un webhook se intenta insertar el id del evento. '
    'Si choca con la PK es un reintento de la pasarela y se descarta sin volver a cobrar.';
 
CREATE TABLE comprobante (
    id           UUID             PRIMARY KEY DEFAULT gen_random_uuid(),
    venta_id     UUID             NOT NULL UNIQUE REFERENCES venta(id) ON DELETE CASCADE,
    tipo         tipo_comprobante NOT NULL DEFAULT 'RECIBO',
    numero       VARCHAR(40)      NOT NULL UNIQUE,
    nit_cliente  VARCHAR(30),
    razon_social VARCHAR(180),
    url_pdf      TEXT,
    emitido_en   TIMESTAMPTZ      NOT NULL DEFAULT now()
);
 
-- ---------------------------------------------------------------------
-- CU20 - ENTREGA A DOMICILIO (DELIVERY)
-- Una venta con entrega = 'DOMICILIO' genera un envio recien cuando el pago queda APROBADO
-- (lo crea el webhook, ver app/modules/pagos/router.py). El envio congela la direccion en
-- texto y coordenadas porque la clienta puede editar o borrar su direccion despues, y el
-- seguimiento tiene que seguir mostrando a donde iba el paquete.
--
-- El reparto en si NO es una operacion propia de FashionStore: se contrata a un servicio de
-- delivery externo. La sucursal solo controla los dos momentos que le tocan a ella --
-- despachar el paquete y confirmar que el servicio lo entrego (o que fallo)-- por eso no hay
-- ni un cargo de empleado "repartidor" ni una hoja de ruta con asignacion/tramos intermedios.
-- ---------------------------------------------------------------------

CREATE TABLE envio (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    venta_id        UUID          NOT NULL UNIQUE REFERENCES venta(id) ON DELETE CASCADE,
    sucursal_id     UUID          NOT NULL REFERENCES sucursal(id),
    direccion_id    UUID          REFERENCES direccion(id) ON DELETE SET NULL,
    estado          estado_envio  NOT NULL DEFAULT 'PENDIENTE',
    -- lo que devolvio el proveedor de ruteo al cotizar (ORS = openrouteservice de HeiGIT,
    -- HAVERSINE = calculo propio de respaldo cuando no hay API key o el servicio no responde)
    proveedor_ruteo VARCHAR(20)   NOT NULL DEFAULT 'HAVERSINE',
    distancia_km    NUMERIC(8,3)  NOT NULL CHECK (distancia_km >= 0),
    duracion_min    INT           NOT NULL DEFAULT 0 CHECK (duracion_min >= 0),
    costo           NUMERIC(12,2) NOT NULL CHECK (costo >= 0),
    -- foto de la direccion al momento de comprar
    ciudad          ciudad_bo     NOT NULL,
    direccion_texto VARCHAR(250)  NOT NULL,
    referencia      VARCHAR(250),
    latitud         NUMERIC(10,7),
    longitud        NUMERIC(10,7),
    observacion     VARCHAR(250),
    -- quien hizo el ultimo cambio de estado; lo lee tg_envio_historial para firmar el evento
    -- (la base no conoce al usuario de la sesion HTTP, el backend lo escribe en el mismo UPDATE)
    actualizado_por_id UUID       REFERENCES usuario(id),
    creado_en       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    despachado_en   TIMESTAMPTZ,
    cerrado_en      TIMESTAMPTZ
);
CREATE INDEX ix_envio_sucursal ON envio(sucursal_id, estado, creado_en DESC);
COMMENT ON TABLE envio IS
    'CU20. Un envio por venta a domicilio, despachado a traves de un servicio de delivery '
    'externo. La tarifa ya cobrada vive en venta.costo_envio; aca se guarda ademas la '
    'distancia y la duracion que devolvio el proveedor de ruteo.';

CREATE TABLE envio_evento (
    id         BIGSERIAL    PRIMARY KEY,
    envio_id   UUID         NOT NULL REFERENCES envio(id) ON DELETE CASCADE,
    estado     estado_envio NOT NULL,
    nota       VARCHAR(250),
    usuario_id UUID         REFERENCES usuario(id),
    fecha      TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX ix_envio_evento ON envio_evento(envio_id, fecha);
COMMENT ON TABLE envio_evento IS
    'Bitacora append-only del envio (mismo espiritu que movimiento_inventario y '
    'reserva_historial): nunca se actualiza ni se borra. La escribe el trigger '
    'tg_envio_historial, que firma el evento con envio.actualizado_por_id.';

-- Nota de devolucion (PENDIENTES 5.9): numero correlativo NDV-000001 de toda la cadena.
CREATE SEQUENCE seq_nota_devolucion;

CREATE TABLE devolucion (
    id             UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
    numero         VARCHAR(20)       NOT NULL UNIQUE
                       DEFAULT ('NDV-' || lpad(nextval('seq_nota_devolucion')::text, 6, '0')),
    venta_id       UUID              NOT NULL REFERENCES venta(id),
    sucursal_id    UUID              NOT NULL REFERENCES sucursal(id),
    motivo         VARCHAR(250)      NOT NULL,
    monto_devuelto NUMERIC(12,2)     NOT NULL CHECK (monto_devuelto >= 0),
    estado         estado_devolucion NOT NULL DEFAULT 'SOLICITADA',
    usuario_id     UUID              REFERENCES usuario(id),
    fecha          TIMESTAMPTZ       NOT NULL DEFAULT now(),
    -- Devoluciones (PENDIENTES 2.7): quien la aprobo/rechazo y cuando (el trigger
    -- tg_devolucion_stock firma el kardex con resuelta_por_id) y por que se rechazo.
    resuelta_por_id UUID             REFERENCES usuario(id),
    resuelta_en     TIMESTAMPTZ,
    motivo_rechazo  VARCHAR(250),
    -- Reintegro del dinero, fijado al aprobar segun como se pago la venta: STRIPE se devuelve
    -- por la API (reintegro_referencia = id del Refund `re_...`); EFECTIVO sale del cajon de la
    -- sesion de caja de quien aprueba (sesion_caja_id, lo descuenta fn_total_efectivo_sesion);
    -- TARJETA/QR/TRANSFERENCIA se devuelven fuera del sistema y aca queda el registro.
    reintegro_metodo     VARCHAR(20)  CHECK (reintegro_metodo IN
                             ('STRIPE','EFECTIVO','TARJETA','QR','TRANSFERENCIA')),
    reintegro_referencia VARCHAR(80),
    sesion_caja_id       UUID         REFERENCES sesion_caja(id),
    -- Cambio de prenda = devolucion + venta nueva cobrada en caja; esto las vincula.
    venta_cambio_id      UUID         REFERENCES venta(id),
    -- Segundo parcial (PENDIENTES 5.8): motivo estructurado y condiciones de la prenda que el
    -- personal verifica al recibirla. Las reglas (que condicion exige cada motivo y que plazo
    -- corre) estan en devoluciones/router.py: TALLA/COLOR usan configuracion.cambio_plazo_dias,
    -- el resto devolucion_plazo_dias; DEFECTO solo exige el comprobante.
    motivo_tipo     motivo_devolucion NOT NULL DEFAULT 'OTRO',
    con_etiqueta    BOOLEAN           NOT NULL DEFAULT TRUE,
    sin_uso         BOOLEAN           NOT NULL DEFAULT TRUE,
    con_comprobante BOOLEAN           NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_devolucion_cambio CHECK (venta_cambio_id <> venta_id)
);
CREATE INDEX ix_devolucion_fecha ON devolucion(fecha DESC);
CREATE INDEX ix_devolucion_venta ON devolucion(venta_id);
COMMENT ON TABLE devolucion IS
    'Devolucion de prendas de una venta PAGADA/ENTREGADA. Nace SOLICITADA; al pasar a APROBADA '
    'tg_devolucion_stock reingresa el stock (tipo DEVOLUCION). usuario_id = quien la registro.';
 
CREATE TABLE devolucion_detalle (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    devolucion_id    UUID NOT NULL REFERENCES devolucion(id) ON DELETE CASCADE,
    venta_detalle_id UUID NOT NULL REFERENCES venta_detalle(id),
    cantidad         INT  NOT NULL CHECK (cantidad > 0),
    -- Cambio por talla/color: la variante (misma prenda) que la clienta pide a cambio.
    variante_solicitada_id UUID REFERENCES producto_variante(id)
);
 
 
-- =====================================================================
--  BLOQUE 7 - PARAMETRIA Y TRAZABILIDAD
-- =====================================================================
 
CREATE TABLE configuracion (
    clave          VARCHAR(60)  PRIMARY KEY,
    valor          TEXT         NOT NULL,
    descripcion    VARCHAR(200),
    actualizado_en TIMESTAMPTZ  NOT NULL DEFAULT now()
);
COMMENT ON TABLE configuracion IS
    'Parametros operativos de la plataforma (horas de vigencia de una reserva, plazos, tarifa '
    'de delivery). Los datos de facturacion de cada tienda viven en empresa.';
 
CREATE TABLE notificacion (
    id           UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id   UUID              NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    tipo         tipo_notificacion NOT NULL,
    titulo       VARCHAR(120)      NOT NULL,
    mensaje      TEXT              NOT NULL,
    entidad_tipo VARCHAR(40),
    entidad_id   UUID,
    leida        BOOLEAN           NOT NULL DEFAULT FALSE,
    fecha        TIMESTAMPTZ       NOT NULL DEFAULT now()
);
CREATE INDEX ix_notificacion_pendiente ON notificacion(usuario_id, fecha DESC) WHERE NOT leida;
 
CREATE TABLE auditoria (
    id             BIGSERIAL        PRIMARY KEY,
    usuario_id     UUID             REFERENCES usuario(id),
    -- tenant del usuario que hizo la accion (NULL = plataforma o clienta); lo completa
    -- registrar_auditoria para que cada empresa vea solo su bitacora
    empresa_id     UUID             REFERENCES empresa(id),
    entidad        VARCHAR(60)      NOT NULL,
    entidad_id     VARCHAR(60)      NOT NULL,
    accion         accion_auditoria NOT NULL,
    datos_antes    JSONB,
    datos_despues  JSONB,
    ip             INET,
    fecha          TIMESTAMPTZ      NOT NULL DEFAULT now()
);
CREATE INDEX ix_auditoria_entidad ON auditoria(entidad, entidad_id, fecha DESC);
CREATE INDEX ix_auditoria_empresa ON auditoria(empresa_id, fecha DESC);


-- =====================================================================
--  BLOQUE 8 - SAAS: PLANES, SUSCRIPCIONES, CARTERA POR TENANT Y SINCRONIZACION
--
--  Tenant = empresa. Cada empresa tiene UNA suscripcion a un plan; el plan fija los topes
--  (sucursales activas, personal, cajas; NULL = sin limite) y que funciones habilita (columnas
--  booleanas que pide requiere_funcion_plan en backend/app/core/plan.py). Los topes y las
--  funciones se editan desde el backend (PUT /saas/planes/{codigo}, SUPERADMIN) sin redesplegar.
-- =====================================================================

CREATE TABLE plan (
    id                SERIAL        PRIMARY KEY,
    codigo            VARCHAR(20)   NOT NULL UNIQUE,
    nombre            VARCHAR(60)   NOT NULL,
    descripcion       VARCHAR(300),
    precio_mensual    NUMERIC(12,2) NOT NULL CHECK (precio_mensual >= 0),
    max_sucursales    INT           CHECK (max_sucursales > 0),  -- NULL = sin limite
    max_empleados     INT           CHECK (max_empleados > 0),
    max_cajas         INT           CHECK (max_cajas > 0),
    -- Funciones habilitadas por plan (los codigos que pide requiere_funcion_plan)
    perfiles_clientes BOOLEAN       NOT NULL DEFAULT TRUE,
    traspasos         BOOLEAN       NOT NULL DEFAULT TRUE,
    operacion_offline BOOLEAN       NOT NULL DEFAULT TRUE,
    reportes          BOOLEAN       NOT NULL DEFAULT TRUE,   -- reportes convencionales
    ia_reportes       BOOLEAN       NOT NULL DEFAULT FALSE,  -- reportes generativos con IA
    analitica_ml      BOOLEAN       NOT NULL DEFAULT FALSE,  -- dashboard de machine learning
    orden             INT           NOT NULL DEFAULT 0,
    activo            BOOLEAN       NOT NULL DEFAULT TRUE
);

-- Una suscripcion vigente por empresa: cambiar de plan o renovar actualiza esta fila; la
-- historia queda en pago_suscripcion.
CREATE TABLE suscripcion (
    id             UUID               PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_id     UUID               NOT NULL UNIQUE REFERENCES empresa(id) ON DELETE CASCADE,
    plan_id        INT                NOT NULL REFERENCES plan(id),
    estado         estado_suscripcion NOT NULL DEFAULT 'PRUEBA',
    inicio         TIMESTAMPTZ        NOT NULL DEFAULT now(),
    vence_en       TIMESTAMPTZ        NOT NULL,
    actualizado_en TIMESTAMPTZ        NOT NULL DEFAULT now()
);
COMMENT ON TABLE suscripcion IS
    'Suscripcion del tenant (empresa). Vigente = estado PRUEBA/ACTIVA y vence_en > now(); '
    'el backend la trata como VENCIDA aunque el estado no se haya actualizado todavia.';

CREATE TABLE pago_suscripcion (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    suscripcion_id  UUID          NOT NULL REFERENCES suscripcion(id) ON DELETE CASCADE,
    plan_id         INT           NOT NULL REFERENCES plan(id),
    meses           INT           NOT NULL CHECK (meses BETWEEN 1 AND 12),
    monto           NUMERIC(12,2) NOT NULL CHECK (monto > 0),
    -- STRIPE = Checkout Session (lo aprueba el webhook); EFECTIVO/TRANSFERENCIA = lo registra a
    -- mano el administrador de la plataforma y nace APROBADO.
    metodo          VARCHAR(20)   NOT NULL CHECK (metodo IN ('STRIPE','EFECTIVO','TRANSFERENCIA')),
    estado          estado_pago   NOT NULL DEFAULT 'PENDIENTE',
    id_transaccion  VARCHAR(120)  UNIQUE,
    periodo_desde   TIMESTAMPTZ,
    periodo_hasta   TIMESTAMPTZ,
    pagado_por_id   UUID          REFERENCES usuario(id),
    creado_en       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    confirmado_en   TIMESTAMPTZ
);
CREATE INDEX ix_pago_suscripcion ON pago_suscripcion(suscripcion_id, creado_en DESC);

-- Perfil de la clienta segun cada empresa: la administracion arma su propia ficha (segmento,
-- talla habitual, estilo, notas) sobre las clientas que compraron/reservaron en sus sucursales
-- o que dio de alta a mano. Distinto de perfil_cliente, que es lo que declara la clienta.
CREATE TABLE cliente_perfil_tenant (
    empresa_id         UUID         NOT NULL REFERENCES empresa(id) ON DELETE CASCADE,
    usuario_id         UUID         NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    segmento           VARCHAR(20)  NOT NULL DEFAULT 'NUEVA'
                           CHECK (segmento IN ('NUEVA','FRECUENTE','VIP','INACTIVA')),
    talla_habitual     VARCHAR(10),
    estilo_preferido   VARCHAR(60),
    telefono_contacto  VARCHAR(30),
    acepta_whatsapp    BOOLEAN      NOT NULL DEFAULT FALSE,
    notas              VARCHAR(500),
    actualizado_en     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    actualizado_por_id UUID         REFERENCES usuario(id),
    PRIMARY KEY (empresa_id, usuario_id)
);

-- Sincronizacion de operaciones offline (PWA / Flutter). Una fila por operacion que llego al
-- servidor, con el UUID que genero el cliente como PK: si el mismo id vuelve a llegar (el
-- cliente no recibio la respuesta y reintenta) se devuelve el resultado guardado y no se
-- procesa de nuevo (RN11). Tambien es el log de sincronizacion (RNF10): cuantos intentos hubo,
-- cuando y con que resultado, sin guardar datos de pago.
CREATE TABLE operacion_sync (
    id              UUID                  PRIMARY KEY,           -- generado en el cliente
    empresa_id      UUID                  NOT NULL REFERENCES empresa(id),
    -- NULL si la sucursal que mando el dispositivo no es de la empresa (quedo RECHAZADA)
    sucursal_id     UUID                  REFERENCES sucursal(id),
    usuario_id      UUID                  NOT NULL REFERENCES usuario(id),
    tipo            tipo_operacion_sync   NOT NULL,
    estado          estado_operacion_sync NOT NULL,
    codigo_motivo   VARCHAR(40),          -- STOCK_INSUFICIENTE, PRECIO_CAMBIADO, ...
    motivo          VARCHAR(300),         -- por que se rechazo o quedo en conflicto
    payload         JSONB                 NOT NULL,              -- la operacion tal como llego
    resultado       JSONB,                -- venta/reserva creada (id, numero, total)
    registrada_en   TIMESTAMPTZ           NOT NULL,              -- hora del dispositivo
    recibida_en     TIMESTAMPTZ           NOT NULL DEFAULT now(),
    intentos        INT                   NOT NULL DEFAULT 1,
    ultimo_intento  TIMESTAMPTZ           NOT NULL DEFAULT now(),
    resuelta_por_id UUID                  REFERENCES usuario(id), -- quien cerro el conflicto
    resuelta_en     TIMESTAMPTZ,
    resolucion      VARCHAR(300)
);
CREATE INDEX ix_operacion_sync_empresa ON operacion_sync(empresa_id, recibida_en DESC);
CREATE INDEX ix_operacion_sync_abiertas ON operacion_sync(empresa_id)
    WHERE estado = 'CONFLICTO' AND resuelta_en IS NULL;
COMMENT ON TABLE operacion_sync IS
    'Operaciones offline recibidas (idempotencia por id del cliente) y log de sincronizacion. '
    'CONFIRMADA = se creo la venta/reserva; RECHAZADA = no se puede aplicar nunca (suscripcion '
    'vencida, sucursal ajena, prenda de otra empresa); CONFLICTO = los datos locales quedaron '
    'viejos (stock, precio, prenda inactiva) y alguien del personal decide que hacer.';


-- ---------------------------------------------------------------------
--  8.2.2 (continuacion)  VISTAS
--  Copia de db/02_logica.sql. Son consultas guardadas que usan el catalogo, los reportes
--  (CU15) y el consolidado de existencias; se consultan en 8.2.5.4.
-- ---------------------------------------------------------------------
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
    END AS situacion,
    s.empresa_id
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
    COUNT(*) FILTER (WHERE i.disponible > 0) AS sucursales_con_stock,
    p.empresa_id
FROM producto_variante pv
JOIN producto p    ON p.id = pv.producto_id
LEFT JOIN inventario i ON i.variante_id = pv.id
GROUP BY pv.id, pv.sku, p.nombre, p.empresa_id;
 
-- Ventas por dia, sucursal y canal: base de los dashboards (RF24)
-- Neto de devoluciones: el monto resta lo reintegrado en devoluciones APROBADAS, y una venta
-- devuelta entera (su pago quedo REEMBOLSADO) no cuenta como venta. Mismo criterio que los
-- reportes de CU15 (reportes/router.py).
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
    AVG(v.total_neto)  AS ticket_promedio,
    s.empresa_id
FROM neta v
JOIN sucursal s ON s.id = v.sucursal_id
GROUP BY 1, 2, 3, s.empresa_id;

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
    END)::text                              AS situacion,
    s.empresa_id
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
    -- AJUSTE es un recuento absoluto y puede dejar la prenda en 0; el resto son deltas
    IF p_cantidad < 0 OR (p_cantidad = 0 AND p_tipo <> 'AJUSTE') THEN
        RAISE EXCEPTION 'La cantidad del movimiento debe ser positiva (recibido: %)', p_cantidad;
    END IF;

    -- Multi-tenant: la prenda tiene que ser del catalogo de la misma empresa que la sucursal.
    -- El backend ya lo valida al armar cada operacion; esto es la ultima barrera, asi ni una
    -- venta, ni una reserva, ni un traspaso, ni una recepcion pueden mover stock ajeno.
    IF NOT EXISTS (SELECT 1
                     FROM producto_variante pv
                     JOIN producto p ON p.id = pv.producto_id
                     JOIN sucursal s ON s.id = p_sucursal_id
                    WHERE pv.id = p_variante_id AND p.empresa_id = s.empresa_id) THEN
        RAISE EXCEPTION 'La prenda no pertenece a la empresa de la sucursal (variante %, sucursal %)',
                        p_variante_id, p_sucursal_id;
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
-- tocan el cajon fisico. Resta el efectivo que salio del cajon por devoluciones aprobadas en
-- esa sesion (devolucion.sesion_caja_id). Un pago en efectivo que una devolucion completa dejo
-- REEMBOLSADO se sigue sumando: la plata entro al cajon, y lo que salio lo resta la devolucion.
-- STABLE (no escribe nada) para que se pueda llamar tanto desde una consulta de solo lectura
-- (vista previa del arqueo) como adentro del UPDATE que cierra la sesion, sin abrir una
-- ventana entre "leer" el total y "escribirlo".
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

COMMENT ON FUNCTION fn_total_efectivo_sesion IS
    'CU07: total EFECTIVO cobrado en una sesion de caja, para el arqueo y el cierre.';

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
--  8.2.6.3  TRIGGERS
--  Copia de db/02_logica.sql. El backend solo inserta movimientos o cambia estados; estos
--  disparadores mueven el stock con fn_mover_inventario y escriben las bitacoras.
-- ---------------------------------------------------------------------

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

CREATE TRIGGER tg_traspaso_stock
    AFTER UPDATE OF estado ON traspaso
    FOR EACH ROW EXECUTE FUNCTION fn_traspaso_stock();

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
--  8.2.6.4  PRUEBAS DE EJECUCION
--  Cada bloque muestra el estado antes, ejecuta y muestra el estado despues. Los casos de
--  error se envuelven en un bloque DO con EXCEPTION para que el script siga corriendo y el
--  mensaje quede como NOTICE.
-- ---------------------------------------------------------------------

-- ===== a) Procedimientos =====

-- sp_venta_pos: vende 1 vestido y 2 blusas en la caja abierta de Santa Cruz
SELECT pv.sku, i.cantidad_fisica, i.disponible
  FROM inventario i JOIN producto_variante pv ON pv.id = i.variante_id
 WHERE i.sucursal_id = (SELECT id FROM sucursal WHERE codigo = 'SC-01')
   AND pv.sku IN ('VES-001-M-Bei', 'BLU-001-L-Neg');

CALL sp_venta_pos('d1000000-0000-4000-8000-000000000003',
                  '[{"sku": "VES-001-M-Bei", "cantidad": 1}, {"sku": "BLU-001-L-Neg", "cantidad": 2}]',
                  'EFECTIVO');

SELECT pv.sku, i.cantidad_fisica, i.disponible
  FROM inventario i JOIN producto_variante pv ON pv.id = i.variante_id
 WHERE i.sucursal_id = (SELECT id FROM sucursal WHERE codigo = 'SC-01')
   AND pv.sku IN ('VES-001-M-Bei', 'BLU-001-L-Neg');

-- sp_venta_pos con stock insuficiente: la venta entera se deshace (no queda venta a medias)
DO $$
DECLARE
    v_numero VARCHAR;
BEGIN
    CALL sp_venta_pos('d1000000-0000-4000-8000-000000000003',
                      '[{"sku": "BLU-001-L-Neg", "cantidad": 1}, {"sku": "ABR-001-S-Neg", "cantidad": 50}]',
                      'EFECTIVO', v_numero);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Venta rechazada y revertida: %', SQLERRM;
END;
$$;

-- sp_cerrar_sesion_caja: arqueo de la caja de hoy en Santa Cruz (la cajera cuenta Bs 1070,
-- un faltante de Bs 3.60 frente a lo que dice el sistema)
SELECT fn_total_efectivo_sesion('d1000000-0000-4000-8000-000000000003') AS efectivo_cobrado;
CALL sp_cerrar_sesion_caja('d1000000-0000-4000-8000-000000000003', 1070.00);
SELECT estado, monto_inicial, monto_sistema, monto_declarado, diferencia
  FROM sesion_caja WHERE id = 'd1000000-0000-4000-8000-000000000003';

-- sp_ajustar_stock: el recuento encontro 21 blusas XS blancas en Santa Cruz (el sistema dice 22)
CALL sp_ajustar_stock('SC-01', 'BLU-001-XS-Bla', 21, 'Recuento semanal: una prenda danada',
                      'almacen.scz@fashionstore.bo');
SELECT tipo, cantidad, saldo_anterior, saldo_nuevo, motivo
  FROM movimiento_inventario
 WHERE documento_tipo = 'AJUSTE'
 ORDER BY id DESC LIMIT 1;

-- sp_expirar_reservas: se registra una reserva que ya vencio y el job la expira
INSERT INTO reserva (id, usuario_id, sucursal_id, codigo, fecha_visita, hora_visita, expira_en, estado)
VALUES ('c1000000-0000-4000-8000-000000000004',
        (SELECT id FROM usuario WHERE email = 'cliente2@fashionstore.bo'),
        (SELECT id FROM sucursal WHERE codigo = 'OR-01'), 'RES-0000000004',
        CURRENT_DATE - 1, '10:00', now() - interval '1 hour', 'CONFIRMADA');
INSERT INTO reserva_detalle (reserva_id, variante_id, cantidad)
VALUES ('c1000000-0000-4000-8000-000000000004',
        (SELECT id FROM producto_variante WHERE sku = 'ABR-001-S-Neg'), 1);

CALL sp_expirar_reservas();
SELECT r.codigo, r.estado, rd.estado_item
  FROM reserva r JOIN reserva_detalle rd ON rd.reserva_id = r.id
 WHERE r.id = 'c1000000-0000-4000-8000-000000000004';

-- sp_renovar_suscripcion: Moda Urbana paga un mes y vuelve a quedar ACTIVA
CALL sp_renovar_suscripcion('moda-urbana', 1);
SELECT e.nombre, su.estado, su.vence_en::date
  FROM suscripcion su JOIN empresa e ON e.id = su.empresa_id
 WHERE e.slug = 'moda-urbana';


-- ===== b) Funciones =====

-- fn_cotizar_envio: domicilio a 2.5 km por una compra de Bs 305.82 (la tarifa por km ya es 4)
SELECT * FROM fn_cotizar_envio(2.5, 305.82);
-- Compra desde Bs 800: el envio sale gratis
SELECT * FROM fn_cotizar_envio(5.0, 950.00);
-- 15 km: fuera del radio de reparto de la sucursal
SELECT costo, dentro_cobertura FROM fn_cotizar_envio(15.0, 200.00);

-- fn_total_efectivo_sesion: efectivo de la sesion de ayer en La Paz (cerrada con faltante)
SELECT fn_total_efectivo_sesion('d1000000-0000-4000-8000-000000000002') AS efectivo_la_paz;

-- fn_mover_inventario: entrada directa de 5 unidades y su asiento en el kardex
SELECT fn_mover_inventario((SELECT id FROM sucursal WHERE codigo = 'TJ-01'),
                           (SELECT id FROM producto_variante WHERE sku = 'BLU-001-M-Bla'),
                           'ENTRADA', 5, 'Prueba de la funcion', NULL, NULL, NULL) AS movimiento_id;
SELECT tipo, cantidad, saldo_anterior, saldo_nuevo FROM movimiento_inventario ORDER BY id DESC LIMIT 1;

-- fn_mover_inventario rechaza una salida mayor al disponible
DO $$
BEGIN
    PERFORM fn_mover_inventario((SELECT id FROM sucursal WHERE codigo = 'TJ-01'),
                                (SELECT id FROM producto_variante WHERE sku = 'BLU-001-M-Bla'),
                                'SALIDA', 999, 'Prueba de error', NULL, NULL, NULL);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Rechazado: %', SQLERRM;
END;
$$;

-- fn_mover_inventario rechaza mover stock de una prenda de OTRA empresa (multi-tenant)
DO $$
BEGIN
    PERFORM fn_mover_inventario((SELECT id FROM sucursal WHERE codigo = 'SC-01'),
                                (SELECT id FROM producto_variante WHERE sku = 'AND-001-M-Gri'),
                                'ENTRADA', 1, 'Prueba de aislamiento', NULL, NULL, NULL);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Rechazado: %', SQLERRM;
END;
$$;


-- ===== c) Triggers =====

-- tg_reserva_compromete_stock: una reserva nueva sube cantidad_reservada (no toca lo fisico)
SELECT cantidad_fisica, cantidad_reservada, disponible FROM inventario
 WHERE sucursal_id = (SELECT id FROM sucursal WHERE codigo = 'CB-01')
   AND variante_id = (SELECT id FROM producto_variante WHERE sku = 'PAN-001-40-Azu');

INSERT INTO reserva (id, usuario_id, sucursal_id, codigo, fecha_visita, hora_visita, expira_en)
VALUES ('c1000000-0000-4000-8000-000000000003',
        (SELECT id FROM usuario WHERE email = 'andrea.lopez@gmail.com'),
        (SELECT id FROM sucursal WHERE codigo = 'CB-01'), 'RES-0000000003',
        CURRENT_DATE + 2, '11:00', (CURRENT_DATE + 2) + time '11:00' + interval '4 hours');
INSERT INTO reserva_detalle (reserva_id, variante_id, cantidad)
VALUES ('c1000000-0000-4000-8000-000000000003',
        (SELECT id FROM producto_variante WHERE sku = 'PAN-001-40-Azu'), 2);

SELECT cantidad_fisica, cantidad_reservada, disponible FROM inventario
 WHERE sucursal_id = (SELECT id FROM sucursal WHERE codigo = 'CB-01')
   AND variante_id = (SELECT id FROM producto_variante WHERE sku = 'PAN-001-40-Azu');

-- tg_reserva_historial: la encargada confirma la reserva y queda el asiento en el historial
UPDATE reserva
   SET estado = 'CONFIRMADA', vestidor_asignado = 'V-2',
       atendida_por_id = (SELECT id FROM usuario WHERE email = 'admin@fashionstore.bo')
 WHERE id = 'c1000000-0000-4000-8000-000000000001';
SELECT estado_anterior, estado_nuevo, fecha FROM reserva_historial
 WHERE reserva_id = 'c1000000-0000-4000-8000-000000000001';

-- tg_venta_descuenta_stock: la clienta de La Paz se prueba el tapado reservado y lo compra.
-- Como la venta nace de la reserva, el trigger primero LIBERA el compromiso y despues descuenta.
INSERT INTO venta (id, sucursal_id, usuario_id, canal, entrega, reserva_id, numero,
                   subtotal, descuento, iva, total, estado, registrada_por_id)
VALUES ('b1000000-0000-4000-8000-000000000009', (SELECT id FROM sucursal WHERE codigo = 'LP-01'),
        (SELECT id FROM usuario WHERE email = 'cliente2@fashionstore.bo'), 'POS', 'RETIRO_SUCURSAL',
        'c1000000-0000-4000-8000-000000000002', 'V-LP00000003', 449.90, 0, 58.49, 508.39, 'ENTREGADA',
        (SELECT id FROM usuario WHERE email = 'encargada.lapaz@fashionstore.bo'));
INSERT INTO venta_detalle (venta_id, variante_id, cantidad, precio_unitario, subtotal)
VALUES ('b1000000-0000-4000-8000-000000000009',
        (SELECT id FROM producto_variante WHERE sku = 'ABR-001-L-Cam'), 1, 449.90, 449.90);
INSERT INTO pago (venta_id, metodo, monto, estado, confirmado_en)
VALUES ('b1000000-0000-4000-8000-000000000009', 'TARJETA', 508.39, 'APROBADO', now());
UPDATE reserva_detalle SET estado_item = 'COMPRADO' WHERE reserva_id = 'c1000000-0000-4000-8000-000000000002';
UPDATE reserva SET estado = 'CONVERTIDA', atendida_en = now()
 WHERE id = 'c1000000-0000-4000-8000-000000000002';

SELECT tipo, cantidad, saldo_anterior, saldo_nuevo, motivo
  FROM movimiento_inventario
 WHERE documento_id = 'b1000000-0000-4000-8000-000000000009'
 ORDER BY id;

-- tg_confirmar_recepcion: al confirmar la recepcion entra el stock de cada linea
UPDATE recepcion SET estado = 'CONFIRMADA' WHERE id = 'f1000000-0000-4000-8000-000000000001';
SELECT pv.sku, m.tipo, m.cantidad, m.saldo_anterior, m.saldo_nuevo
  FROM movimiento_inventario m JOIN producto_variante pv ON pv.id = m.variante_id
 WHERE m.documento_id = 'f1000000-0000-4000-8000-000000000001';

-- tg_traspaso_stock: sale del origen al despachar y entra en destino lo que llego
UPDATE traspaso
   SET estado = 'EN_TRANSITO', fecha_despacho = now(),
       actualizado_por_id = (SELECT id FROM usuario WHERE email = 'encargado.cbba@fashionstore.bo')
 WHERE id = 'f2000000-0000-4000-8000-000000000001';

UPDATE traspaso_detalle
   SET cantidad_recibida = CASE WHEN variante_id = (SELECT id FROM producto_variante WHERE sku = 'VES-001-M-Neg')
                                THEN 3 ELSE 1 END     -- de los vestidos beige llego 1 de 2
 WHERE traspaso_id = 'f2000000-0000-4000-8000-000000000001';

UPDATE traspaso
   SET estado = 'RECIBIDO', fecha_recepcion = now(), observacion = 'Llego un vestido beige de menos',
       usuario_recibe_id = (SELECT id FROM usuario WHERE email = 'admin@fashionstore.bo'),
       actualizado_por_id = (SELECT id FROM usuario WHERE email = 'admin@fashionstore.bo')
 WHERE id = 'f2000000-0000-4000-8000-000000000001';

SELECT s.codigo AS sucursal, pv.sku, m.tipo, m.cantidad
  FROM movimiento_inventario m
  JOIN sucursal s           ON s.id  = m.sucursal_id
  JOIN producto_variante pv ON pv.id = m.variante_id
 WHERE m.documento_id = 'f2000000-0000-4000-8000-000000000001'
 ORDER BY m.id;

-- Un traspaso RECIBIDO no puede volver a cambiar de estado
DO $$
BEGIN
    UPDATE traspaso SET estado = 'ANULADO' WHERE id = 'f2000000-0000-4000-8000-000000000001';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Rechazado: %', SQLERRM;
END;
$$;

-- tg_devolucion_stock: al aprobar la devolucion el vestido vuelve al stock de Santa Cruz
UPDATE devolucion
   SET estado = 'APROBADA', resuelta_en = now(),
       resuelta_por_id = (SELECT id FROM usuario WHERE email = 'admin@fashionstore.bo')
 WHERE id = 'f3000000-0000-4000-8000-000000000001';
SELECT d.numero, m.tipo, m.cantidad, m.saldo_anterior, m.saldo_nuevo
  FROM movimiento_inventario m JOIN devolucion d ON d.id = m.documento_id
 WHERE m.documento_id = 'f3000000-0000-4000-8000-000000000001';

-- Una devolucion ya resuelta no cambia mas de estado
DO $$
BEGIN
    UPDATE devolucion SET estado = 'RECHAZADA' WHERE id = 'f3000000-0000-4000-8000-000000000001';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Rechazado: %', SQLERRM;
END;
$$;

-- tg_envio_historial: cada cambio de estado del envio deja un evento firmado
UPDATE envio
   SET estado = 'DESPACHADO', despachado_en = now(), observacion = 'Entregado al delivery externo',
       actualizado_por_id = (SELECT id FROM usuario WHERE email = 'admin@fashionstore.bo')
 WHERE id = 'f5000000-0000-4000-8000-000000000001';
UPDATE envio
   SET estado = 'ENTREGADO', cerrado_en = now(), observacion = 'El delivery confirmo la entrega',
       actualizado_por_id = (SELECT id FROM usuario WHERE email = 'admin@fashionstore.bo')
 WHERE id = 'f5000000-0000-4000-8000-000000000001';
SELECT estado, nota, fecha FROM envio_evento
 WHERE envio_id = 'f5000000-0000-4000-8000-000000000001'
 ORDER BY fecha;

-- Kardex completo generado por los triggers y las funciones en estas pruebas
SELECT m.id, s.codigo AS sucursal, pv.sku, m.tipo, m.cantidad, m.saldo_anterior,
       m.saldo_nuevo, m.documento_tipo, m.motivo
  FROM movimiento_inventario m
  JOIN sucursal s           ON s.id  = m.sucursal_id
  JOIN producto_variante pv ON pv.id = m.variante_id
 ORDER BY m.id;
