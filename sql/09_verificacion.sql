-- =====================================================================
-- 09_verificacion.sql
-- Prueba de que los datos llegaron íntegros. Cada bloque compara un total
-- calculado por el ETL sobre el Excel CRUDO (stg.control_excel) contra el
-- mismo total recalculado desde las tablas normalizadas.
-- Resultado esperado: la columna "estado" en OK en todas las filas.
-- =====================================================================

SET search_path TO paros, public;

-- V1. Conciliación fila por fila: toda fila del Excel terminó en algún lado.
SELECT 'V1 Conciliación de filas' AS prueba, destino, filas
FROM (
    SELECT 'Registro de turno (REG)' AS destino, COUNT(*) AS filas, 1 AS orden
    FROM stg.base_clasificada WHERE tipo_fila = 'REG'
    UNION ALL
    SELECT 'Paros de un turno existente (SUB)', COUNT(*), 2
    FROM stg.sub_padre WHERE nivel < 9
    UNION ALL
    SELECT 'Paros con registro creado (SUB huérfana)', COUNT(*), 3
    FROM stg.sub_padre WHERE nivel = 9
    UNION ALL
    SELECT 'No cargada: fila vacía', COUNT(*), 4
    FROM stg.base_clasificada WHERE tipo_fila = 'VACIA'
    UNION ALL
    SELECT 'TOTAL', COUNT(*), 5 FROM stg.base_clasificada
    UNION ALL
    SELECT 'Filas del Excel según el ETL', valor::bigint, 6 FROM stg.control_excel WHERE metrica = 'filas'
) x
ORDER BY orden;

-- V2. Ninguna fila con datos quedó sin destino (debe devolver 0).
SELECT 'V2 Filas con datos sin destino' AS prueba, COUNT(*) AS filas_perdidas
FROM stg.base_clasificada b
WHERE b.tipo_fila <> 'VACIA'
  AND NOT EXISTS (SELECT 1 FROM paros.registro_turno r WHERE r.fila_excel = b.fila_excel)
  AND NOT EXISTS (SELECT 1 FROM paros.paro p WHERE p.fila_excel = b.fila_excel);

-- V3. Totales de control: Excel crudo vs. base normalizada.
WITH bd AS (
    SELECT 'pacas' AS metrica, SUM(pacas_producidas)::numeric AS valor FROM paros.registro_turno
    UNION ALL SELECT 'horas_trabajadas', SUM(horas_trabajadas) FROM paros.registro_turno
    UNION ALL SELECT 'horas_no_trabajadas', SUM(horas_no_trabajadas) FROM paros.registro_turno
    UNION ALL SELECT 'tiempo_paro_horas', SUM(minutos) / 60 FROM paros.paro
    UNION ALL SELECT 'fecha_min', to_char(MIN(fecha), 'YYYYMMDD')::numeric FROM paros.registro_turno
    UNION ALL SELECT 'fecha_max', to_char(MAX(fecha), 'YYYYMMDD')::numeric FROM paros.registro_turno
    UNION ALL
    SELECT 'minutos_codigo_' || lpad(c.id_codigo::text, 2, '0'), COALESCE(SUM(p.minutos), 0)
    FROM paros.codigo_paro c LEFT JOIN paros.paro p ON p.id_codigo = c.id_codigo
    GROUP BY c.id_codigo
    UNION ALL
    SELECT 'pct_productividad_excel',
           paros.fn_productividad(SUM(horas_trabajadas), SUM(horas_paro))
    FROM paros.v_registro_horas
)
SELECT 'V3 Totales de control' AS prueba,
       c.metrica,
       round(c.valor, 4)  AS excel,
       round(bd.valor, 4) AS base_datos,
       CASE WHEN abs(c.valor - bd.valor) < 0.01 THEN 'OK' ELSE 'DIFERENCIA' END AS estado
FROM stg.control_excel c
JOIN bd ON bd.metrica = c.metrica
ORDER BY c.metrica;

-- V4. Productividad por año y máquina: tabla dinámica del Excel (fórmula sobre
--     el staging, fila a fila como lo hace Excel) vs. vista de la base.
WITH excel AS (
    SELECT EXTRACT(YEAR FROM fecha)::int AS anio, maquina,
           paros.fn_productividad(SUM(COALESCE(horas_trab, 0)), SUM(tiempo_paro_h)) AS pct
    FROM stg.base_excel
    GROUP BY 1, 2
),
bd AS (
    SELECT anio, maquina,
           paros.fn_productividad(SUM(horas_trabajadas), SUM(minutos_paro) / 60) AS pct
    FROM paros.v_productividad_mensual
    GROUP BY anio, maquina
)
SELECT 'V4 Productividad por año y máquina' AS prueba, e.anio, e.maquina,
       e.pct AS excel, b.pct AS base_datos,
       CASE WHEN e.pct IS NOT DISTINCT FROM b.pct THEN 'OK' ELSE 'DIFERENCIA' END AS estado
FROM excel e JOIN bd b USING (anio, maquina)
ORDER BY e.anio, e.maquina;

-- V5. Subcódigos del histórico que no encontraron su par en el catálogo (debe ser 0).
SELECT 'V5 Subcódigos sin resolver' AS prueba, COUNT(*) AS paros_sin_subcodigo_resuelto
FROM stg.base_clasificada b
JOIN paros.paro p ON p.fila_excel = b.fila_excel
WHERE p.id_subcodigo IS NULL
  AND ((p.id_codigo = 1 AND b.sub1 IS NOT NULL)
    OR (p.id_codigo = 3 AND b.sub3 IS NOT NULL)
    OR (p.id_codigo = 5 AND b.sub5 IS NOT NULL));

-- V6. Integridad referencial y reglas (todo debe ser 0).
SELECT 'V6 Reglas' AS prueba, regla, casos FROM (
    SELECT 'Paros sin registro' AS regla, COUNT(*) AS casos
    FROM paros.paro p WHERE NOT EXISTS (SELECT 1 FROM paros.registro_turno r WHERE r.id_registro = p.id_registro)
    UNION ALL
    SELECT 'Área/persona que atiende en código distinto de 05', COUNT(*)
    FROM paros.paro WHERE id_codigo <> 5 AND (id_area_agente IS NOT NULL OR id_persona_atiende IS NOT NULL)
    UNION ALL
    SELECT 'Nombres reales en el esquema público', COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = 'paros' AND column_name ILIKE '%nombre_completo%'
) x;

-- V7. Calidad de datos heredada: lo que quedó marcado para revisión.
SELECT 'V7 Marcados para revisión' AS prueba, motivo, COUNT(*) AS registros
FROM (
    SELECT CASE
               WHEN b.es_duplicada THEN 'Fila idéntica a otra en el Excel'
               WHEN r.horas_trabajadas + r.horas_no_trabajadas > 24 THEN 'Horas del día > 24'
               WHEN r.pacas_producidas > 3000 THEN 'Pacas atípicas (> 3.000)'
               WHEN r.horas_trabajadas = 0 AND b.tipo_fila = 'SUB' THEN 'Subcódigo sin turno padre'
               ELSE 'Paro mayor que horas trabajadas'
           END AS motivo
    FROM paros.registro_turno r
    JOIN stg.base_clasificada b ON b.fila_excel = r.fila_excel
    WHERE r.requiere_revision
) x
GROUP BY motivo
ORDER BY registros DESC;
