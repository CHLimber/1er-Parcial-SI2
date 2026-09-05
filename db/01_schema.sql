-- =====================================================================
--  FashionStore - Plataforma Inteligente de Comercio Electronico
--  Esquema de base de datos  |  PostgreSQL 16
--  Sistemas II - S2-2026  |  MSc. Ing. Angelica Garzon Cuellar
--
--  Alcance: una empresa con multiples sucursales en Bolivia.
--  Moneda BOB e IVA 13% fijos en la aplicacion, no se parametrizan.
--  43 tablas en 7 bloques.
-- =====================================================================
 
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
CREATE TYPE estado_item_res   AS ENUM ('RESERVADO','PREPARADO','PROBADO','COMPRADO','DESCARTADO');
CREATE TYPE estado_carrito    AS ENUM ('ACTIVO','CONVERTIDO','ABANDONADO');
CREATE TYPE canal_venta       AS ENUM ('WEB','MOVIL','POS');
CREATE TYPE modo_entrega      AS ENUM ('RETIRO_SUCURSAL','DOMICILIO');
CREATE TYPE estado_venta      AS ENUM ('PENDIENTE','PAGADA','ENTREGADA','ANULADA');
CREATE TYPE metodo_pago       AS ENUM ('EFECTIVO','TARJETA','QR','TRANSFERENCIA','PASARELA');
CREATE TYPE pasarela_pago     AS ENUM ('STRIPE','LIBELULA');
CREATE TYPE estado_pago       AS ENUM ('PENDIENTE','APROBADO','RECHAZADO','REEMBOLSADO');
CREATE TYPE tipo_comprobante  AS ENUM ('RECIBO','FACTURA');
CREATE TYPE estado_devolucion AS ENUM ('SOLICITADA','APROBADA','RECHAZADA');
CREATE TYPE tipo_notificacion AS ENUM ('RESERVA','VENTA','STOCK','PROMO');
CREATE TYPE accion_auditoria  AS ENUM ('CREAR','ACTUALIZAR','ELIMINAR','LOGIN');
 
 
-- =====================================================================
--  BLOQUE 1 - USUARIOS Y ACCESO
-- =====================================================================
 
CREATE TABLE rol (
    id          SERIAL PRIMARY KEY,
    nombre      VARCHAR(60)  NOT NULL UNIQUE,
    descripcion VARCHAR(200),
    es_sistema  BOOLEAN      NOT NULL DEFAULT FALSE
);
COMMENT ON TABLE rol IS 'ADMIN, ENCARGADO, CAJERO, VENDEDOR. Solo aplica a usuarios STAFF.';
 
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
    email_verificado BOOLEAN      NOT NULL DEFAULT FALSE,
    activo           BOOLEAN      NOT NULL DEFAULT TRUE,
    ultimo_acceso    TIMESTAMPTZ,
    creado_en        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    -- un STAFF sin rol no puede hacer nada; un CLIENTE no debe tener rol operativo
    CONSTRAINT ck_usuario_rol CHECK (
        (tipo = 'STAFF'   AND rol_id IS NOT NULL) OR
        (tipo = 'CLIENTE' AND rol_id IS NULL)
    )
);
CREATE INDEX ix_usuario_tipo ON usuario(tipo) WHERE activo;
 
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
 
CREATE TABLE proveedor (
    id       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre   VARCHAR(150) NOT NULL,
    nit      VARCHAR(30),
    contacto VARCHAR(120),
    email    VARCHAR(120),
    telefono VARCHAR(30),
    activo   BOOLEAN      NOT NULL DEFAULT TRUE
);
 
CREATE TABLE categoria (
    id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    categoria_padre_id UUID        REFERENCES categoria(id) ON DELETE SET NULL,
    nombre             VARCHAR(80) NOT NULL,
    slug               VARCHAR(80) NOT NULL UNIQUE,
    imagen_url         TEXT,
    orden              INT         NOT NULL DEFAULT 0,
    activa             BOOLEAN     NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_categoria_padre CHECK (categoria_padre_id <> id)
);
 
CREATE TABLE marca (
    id       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre   VARCHAR(80) NOT NULL UNIQUE,
    logo_url TEXT
);
 
CREATE TABLE temporada (
    id           UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre       VARCHAR(80)    NOT NULL,
    tipo         tipo_temporada NOT NULL,
    fecha_inicio DATE           NOT NULL,
    fecha_fin    DATE           NOT NULL,
    activa       BOOLEAN        NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_temporada_fechas CHECK (fecha_fin >= fecha_inicio)
);
 
CREATE TABLE coleccion (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
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
    categoria_id UUID          NOT NULL REFERENCES categoria(id),
    marca_id     UUID          REFERENCES marca(id),
    proveedor_id UUID          REFERENCES proveedor(id),
    temporada_id UUID          REFERENCES temporada(id),
    coleccion_id UUID          REFERENCES coleccion(id),
    codigo       VARCHAR(40)   NOT NULL UNIQUE,
    nombre       VARCHAR(180)  NOT NULL,
    slug         VARCHAR(180)  NOT NULL UNIQUE,
    descripcion  TEXT,
    material     VARCHAR(120),
    genero       genero_prenda,
    precio_base  NUMERIC(12,2) NOT NULL CHECK (precio_base >= 0),
    activo       BOOLEAN       NOT NULL DEFAULT TRUE,
    destacado    BOOLEAN       NOT NULL DEFAULT FALSE,
    -- embedding  vector(768),   -- descomentar junto con la extension vector
    creado_en    TIMESTAMPTZ   NOT NULL DEFAULT now()
);
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
    nombre        VARCHAR(120)      NOT NULL,
    codigo_cupon  VARCHAR(40)       NOT NULL UNIQUE,
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
    CONSTRAINT ck_promo_porcentaje CHECK (tipo <> 'PORCENTAJE' OR valor <= 100)
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
    cantidad        INT             NOT NULL CHECK (cantidad > 0),
    saldo_anterior  INT             NOT NULL,
    saldo_nuevo     INT             NOT NULL,
    motivo          VARCHAR(200),
    documento_tipo  VARCHAR(30),
    documento_id    UUID,
    usuario_id      UUID            REFERENCES usuario(id),
    fecha           TIMESTAMPTZ     NOT NULL DEFAULT now()
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
    CONSTRAINT ck_traspaso_sucursales CHECK (sucursal_origen_id <> sucursal_destino_id)
);
 
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
    iva               NUMERIC(12,2) NOT NULL DEFAULT 0,
    total             NUMERIC(12,2) NOT NULL CHECK (total >= 0),
    estado            estado_venta  NOT NULL DEFAULT 'PENDIENTE',
    registrada_por_id UUID          REFERENCES usuario(id),
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
 
CREATE TABLE devolucion (
    id             UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
    venta_id       UUID              NOT NULL REFERENCES venta(id),
    sucursal_id    UUID              NOT NULL REFERENCES sucursal(id),
    motivo         VARCHAR(250)      NOT NULL,
    monto_devuelto NUMERIC(12,2)     NOT NULL CHECK (monto_devuelto >= 0),
    estado         estado_devolucion NOT NULL DEFAULT 'SOLICITADA',
    usuario_id     UUID              REFERENCES usuario(id),
    fecha          TIMESTAMPTZ       NOT NULL DEFAULT now()
);
 
CREATE TABLE devolucion_detalle (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    devolucion_id    UUID NOT NULL REFERENCES devolucion(id) ON DELETE CASCADE,
    venta_detalle_id UUID NOT NULL REFERENCES venta_detalle(id),
    cantidad         INT  NOT NULL CHECK (cantidad > 0)
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
    'Datos de la tienda (razon social, NIT, logo) y parametros operativos como las horas '
    'de vigencia de una reserva. Reemplaza a la tabla empresa del modelo multiempresa.';
 
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
    entidad        VARCHAR(60)      NOT NULL,
    entidad_id     VARCHAR(60)      NOT NULL,
    accion         accion_auditoria NOT NULL,
    datos_antes    JSONB,
    datos_despues  JSONB,
    ip             INET,
    fecha          TIMESTAMPTZ      NOT NULL DEFAULT now()
);
CREATE INDEX ix_auditoria_entidad ON auditoria(entidad, entidad_id, fecha DESC);