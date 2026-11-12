-- =====================================================================
-- 00_crear_bd.sql
-- Ejecutar conectado a la base "postgres" (no a bd_paros).
-- En DBeaver: clic derecho en la conexión > SQL Editor > ejecutar este script.
-- =====================================================================
DROP DATABASE IF EXISTS bd_paros;
CREATE DATABASE bd_paros
    WITH ENCODING = 'UTF8'
         TEMPLATE = template0;
COMMENT ON DATABASE bd_paros IS 'Registro de paros de producción - líneas Vinilos_1 a Vinilos_4';
