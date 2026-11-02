-- Comprobante por correo + push al celular (aviso de compra aprobada).
-- Idempotente: se puede correr mas de una vez. Aplicar ANTES de desplegar el backend que trae
-- core/avisos.py (el job lee estas columnas).

ALTER TABLE comprobante
    ADD COLUMN IF NOT EXISTS correo_enviado_en TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS correo_intentos   SMALLINT NOT NULL DEFAULT 0;

-- Lo emitido hasta hoy no se manda: sin esto el job le mandaria un correo viejo a cada clienta.
UPDATE comprobante SET correo_enviado_en = now() WHERE correo_enviado_en IS NULL;

CREATE INDEX IF NOT EXISTS ix_comprobante_correo_pendiente
    ON comprobante(emitido_en) WHERE correo_enviado_en IS NULL;

ALTER TABLE notificacion ADD COLUMN IF NOT EXISTS push_enviado_en TIMESTAMPTZ;

-- Mismo motivo: las notificaciones existentes ya se vieron en la campana, no se mandan como push.
UPDATE notificacion SET push_enviado_en = now() WHERE push_enviado_en IS NULL;

CREATE INDEX IF NOT EXISTS ix_notificacion_push_pendiente
    ON notificacion(fecha) WHERE push_enviado_en IS NULL;

CREATE TABLE IF NOT EXISTS dispositivo_push (
    id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id     UUID         NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
    token          TEXT         NOT NULL UNIQUE,
    plataforma     VARCHAR(20)  NOT NULL DEFAULT 'ANDROID',
    creado_en      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    actualizado_en TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_dispositivo_push_usuario ON dispositivo_push(usuario_id);
