-- =====================================================================
-- 10_seguridad.sql
-- Separación de acceso a datos personales (Ley 1581 de 2012):
--   rol_analista        lee todo el esquema paros (seudónimos), nada de privado
--   rol_talento_humano  además puede ver la identidad de las personas
--   rol_captura         registra turnos y paros nuevos (no borra)
-- Los roles son del servidor; se crean solo si no existen.
-- =====================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_analista') THEN
        CREATE ROLE rol_analista NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_talento_humano') THEN
        CREATE ROLE rol_talento_humano NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_captura') THEN
        CREATE ROLE rol_captura NOLOGIN;
    END IF;
END $$;

REVOKE ALL ON SCHEMA privado FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA privado FROM PUBLIC;

GRANT USAGE ON SCHEMA paros TO rol_analista, rol_talento_humano, rol_captura;
GRANT SELECT ON ALL TABLES IN SCHEMA paros TO rol_analista, rol_talento_humano, rol_captura;

GRANT USAGE ON SCHEMA privado TO rol_talento_humano;
GRANT SELECT, INSERT, UPDATE ON privado.persona_identidad TO rol_talento_humano;

GRANT INSERT, UPDATE ON paros.registro_turno, paros.paro TO rol_captura;
