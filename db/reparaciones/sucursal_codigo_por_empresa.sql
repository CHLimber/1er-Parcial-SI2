-- El codigo de sucursal era unico en toda la plataforma: dos empresas no podian tener cada una su
-- "SC-01" y el autoregistro de empresas chocaba con codigos ajenos. Ahora es unico por empresa.
-- Idempotente.
ALTER TABLE sucursal DROP CONSTRAINT IF EXISTS sucursal_codigo_key;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sucursal_empresa_codigo_key') THEN
        ALTER TABLE sucursal ADD CONSTRAINT sucursal_empresa_codigo_key UNIQUE (empresa_id, codigo);
    END IF;
END $$;
