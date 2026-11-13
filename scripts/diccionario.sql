-- Genera el diccionario de datos en Markdown a partir del catálogo de PostgreSQL
-- (tipos, nulabilidad, DEFAULT, restricciones y los COMMENT del esquema).
-- Uso:  psql -d bd_paros -At -f scripts/diccionario.sql > docs/05_diccionario_datos.md
WITH tablas AS (
    SELECT c.oid, n.nspname AS esquema, c.relname AS tabla,
           obj_description(c.oid, 'pg_class') AS descripcion
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'r' AND n.nspname IN ('paros', 'privado')
),
columnas AS (
    SELECT t.oid, t.esquema, t.tabla, a.attnum, a.attname AS columna,
           format_type(a.atttypid, a.atttypmod) AS tipo,
           CASE WHEN a.attnotnull THEN 'NO' ELSE 'SÍ' END AS nulo,
           CASE WHEN a.attidentity <> '' THEN 'IDENTITY'
                ELSE pg_get_expr(d.adbin, d.adrelid) END AS defecto,
           col_description(t.oid, a.attnum) AS descripcion,
           (SELECT string_agg(
                       CASE con.contype WHEN 'p' THEN 'PK' WHEN 'u' THEN 'UNIQUE' WHEN 'c' THEN 'CHECK'
                                        WHEN 'f' THEN 'FK → ' || confrelid::regclass::text
                                             || ' (' || CASE con.confdeltype WHEN 'c' THEN 'DEL CASCADE' WHEN 'r' THEN 'DEL RESTRICT'
                                                         WHEN 'n' THEN 'DEL SET NULL' WHEN 'a' THEN 'DEL NO ACTION' ELSE '' END
                                             || ', ' || CASE con.confupdtype WHEN 'c' THEN 'UPD CASCADE' WHEN 'r' THEN 'UPD RESTRICT' ELSE 'UPD NO ACTION' END
                                             || ')' END
                       || CASE WHEN con.contype IN ('c','u') THEN ' ' || con.conname ELSE '' END,
                       '; ' ORDER BY con.contype)
            FROM pg_constraint con
            WHERE con.conrelid = t.oid AND a.attnum = ANY (con.conkey)) AS restricciones
    FROM tablas t
    JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum > 0 AND NOT a.attisdropped
    LEFT JOIN pg_attrdef d ON d.adrelid = t.oid AND d.adnum = a.attnum
)
SELECT '# Diccionario de datos' || E'\n\n'
    || 'Generado automáticamente desde el catálogo de PostgreSQL con `scripts/diccionario.sql`. '
    || 'Si cambia el esquema, se vuelve a generar; no se edita a mano.' || E'\n\n'
    || 'Convenciones: **Nulo** = admite NULL. **IDENTITY** = número autogenerado. '
    || 'Las FK indican la tabla referenciada y sus políticas ON DELETE / ON UPDATE.' || E'\n'
UNION ALL
SELECT * FROM (
    SELECT E'\n## ' || t.esquema || '.' || t.tabla || E'\n\n' || COALESCE(t.descripcion, '') || E'\n\n'
        || '| Columna | Tipo | Nulo | Default | Restricciones | Descripción |' || E'\n'
        || '| --- | --- | --- | --- | --- | --- |' || E'\n'
        || string_agg('| `' || c.columna || '` | ' || c.tipo || ' | ' || c.nulo || ' | '
                      || COALESCE(replace(c.defecto, '|', '\|'), '') || ' | '
                      || COALESCE(replace(c.restricciones, '|', '\|'), '') || ' | '
                      || COALESCE(replace(c.descripcion, '|', '\|'), '') || ' |', E'\n' ORDER BY c.attnum)
        || E'\n\n**Restricciones de la tabla:**\n\n'
        || (SELECT string_agg('- `' || con.conname || '`: `' || replace(pg_get_constraintdef(con.oid), '|', '\|') || '`', E'\n' ORDER BY con.contype, con.conname)
            FROM pg_constraint con WHERE con.conrelid = t.oid)
    FROM tablas t
    JOIN columnas c ON c.oid = t.oid
    GROUP BY t.oid, t.esquema, t.tabla, t.descripcion
    ORDER BY CASE t.tabla WHEN 'registro_turno' THEN 0 WHEN 'paro' THEN 1 ELSE 2 END, t.esquema, t.tabla
) x;
