-- =====================================================================
-- ejecutar_todo.sql  —  reconstruye la base de datos desde cero con psql.
--
--   psql -U postgres -f sql/ejecutar_todo.sql
--
-- (ejecutar desde la raíz del repositorio)
-- =====================================================================
\set ON_ERROR_STOP on
\encoding UTF8

\echo '>> 00 Crear base de datos'
\i sql/00_crear_bd.sql
\c bd_paros

\echo '>> 01 Esquema'
\i sql/01_esquema.sql
\echo '>> 02 Funciones y triggers'
\i sql/02_funciones_triggers.sql
\echo '>> 03 Índices'
\i sql/03_indices.sql
\echo '>> 04 Vistas'
\i sql/04_vistas.sql
\echo '>> 05 Catálogos estables'
\i sql/05_catalogos.sql
\echo '>> 06 Catálogos generados por el ETL'
\i sql/06_carga_catalogos_etl.sql
\echo '>> 07 Staging (copia del Excel)'
\i sql/07_carga_staging.sql
\echo '>> 08 Transformación al modelo normalizado'
\i sql/08_transformacion.sql
\echo '>> 09 Verificación de integridad'
\i sql/09_verificacion.sql
\echo '>> 10 Seguridad (roles)'
\i sql/10_seguridad.sql

\echo 'Base reconstruida. Pruebas de restricciones: sql/11_dml_pruebas.sql. Consultas: sql/12_consultas_negocio.sql'
