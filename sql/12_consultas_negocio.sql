-- =====================================================================
-- 12_consultas_negocio.sql
-- Preguntas reales del negocio. Cada consulta indica qué pregunta responde
-- y qué técnica SQL usa. Los rangos de fechas se pueden cambiar.
-- =====================================================================

SET search_path TO paros, public;

-- ---------------------------------------------------------------------
-- C01. % de productividad por máquina y por mes de 2024.
--      Técnicas: INNER JOIN, subconsulta en FROM, SUM, GROUP BY, rango de fechas.
--      Los paros se agregan por registro ANTES del JOIN para no duplicar horas.
-- ---------------------------------------------------------------------
SELECT m.nombre                                     AS maquina,
       to_char(date_trunc('month', r.fecha), 'YYYY-MM') AS mes,
       SUM(r.horas_trabajadas)                      AS horas_trabajadas,
       round(SUM(COALESCE(p.minutos, 0)) / 60, 2)   AS horas_paro,
       paros.fn_productividad(SUM(r.horas_trabajadas), SUM(COALESCE(p.minutos, 0)) / 60) AS pct_productividad
FROM paros.registro_turno r
JOIN paros.maquina m ON m.id_maquina = r.id_maquina
LEFT JOIN (SELECT id_registro, SUM(minutos) AS minutos
           FROM paros.paro GROUP BY id_registro) p ON p.id_registro = r.id_registro
WHERE r.fecha >= DATE '2024-01-01' AND r.fecha < DATE '2025-01-01'
GROUP BY m.nombre, date_trunc('month', r.fecha)
ORDER BY maquina, mes;

-- ---------------------------------------------------------------------
-- C02. Comparativo 2024 vs 2025 por máquina y mes (enero a marzo, lo que hay de 2025).
--      Técnicas: vista, agregación condicional con FILTER, diferencia en puntos.
-- ---------------------------------------------------------------------
SELECT maquina,
       mes,
       paros.fn_productividad(SUM(horas_trabajadas) FILTER (WHERE anio = 2024),
                              SUM(minutos_paro) FILTER (WHERE anio = 2024) / 60) AS pct_2024,
       paros.fn_productividad(SUM(horas_trabajadas) FILTER (WHERE anio = 2025),
                              SUM(minutos_paro) FILTER (WHERE anio = 2025) / 60) AS pct_2025,
       paros.fn_productividad(SUM(horas_trabajadas) FILTER (WHERE anio = 2025),
                              SUM(minutos_paro) FILTER (WHERE anio = 2025) / 60)
     - paros.fn_productividad(SUM(horas_trabajadas) FILTER (WHERE anio = 2024),
                              SUM(minutos_paro) FILTER (WHERE anio = 2024) / 60) AS variacion_puntos
FROM paros.v_productividad_mensual
WHERE anio IN (2024, 2025) AND mes BETWEEN 1 AND 3
GROUP BY maquina, mes
ORDER BY maquina, mes;

-- ---------------------------------------------------------------------
-- C03. Participación porcentual de cada código de paro (todo el histórico).
--      Técnicas: LEFT JOIN desde el catálogo (muestra códigos sin uso), función de ventana.
-- ---------------------------------------------------------------------
SELECT '[' || lpad(c.id_codigo::text, 2, '0') || '] ' || c.nombre AS codigo,
       a.nombre                                    AS area_impacto,
       COUNT(p.id_paro)                            AS eventos,
       round(COALESCE(SUM(p.minutos), 0) / 60, 1)  AS horas,
       round(100 * COALESCE(SUM(p.minutos), 0) / SUM(SUM(p.minutos)) OVER (), 2) AS pct_participacion
FROM paros.codigo_paro c
JOIN paros.area_impacto a ON a.id_area = c.id_area
LEFT JOIN paros.paro p    ON p.id_codigo = c.id_codigo
GROUP BY c.id_codigo, c.nombre, a.nombre
ORDER BY horas DESC;

-- ---------------------------------------------------------------------
-- C04. Código 01 (falla electromecánica): horas por sistema y componente, 2024-2025.
--      Técnicas: auto-JOIN de subcodigo (jerarquía), RIGHT JOIN para ver sistemas sin fallas,
--      GROUPING SETS para subtotal por sistema.
-- ---------------------------------------------------------------------
SELECT COALESCE(sistema.clave || ' ' || sistema.descripcion, '(sin subcódigo)') AS sistema,
       CASE WHEN GROUPING(comp.clave) = 1 THEN '— subtotal sistema —'
            ELSE COALESCE(comp.clave || ' ' || comp.descripcion, '(sistema, sin componente)') END AS componente,
       COUNT(f.id_paro)                         AS eventos,
       round(COALESCE(SUM(f.minutos), 0) / 60, 2) AS horas
FROM (SELECT p.*
      FROM paros.paro p
      JOIN paros.registro_turno r ON r.id_registro = p.id_registro
      WHERE p.id_codigo = 1 AND r.fecha BETWEEN DATE '2024-01-01' AND DATE '2025-12-31') f
JOIN paros.subcodigo s_paro ON s_paro.id_subcodigo = f.id_subcodigo
LEFT JOIN paros.subcodigo comp ON comp.id_subcodigo = s_paro.id_subcodigo AND comp.id_padre IS NOT NULL
RIGHT JOIN paros.subcodigo sistema
       ON sistema.id_subcodigo = COALESCE(s_paro.id_padre, s_paro.id_subcodigo)
WHERE sistema.id_codigo = 1 AND sistema.id_padre IS NULL
GROUP BY GROUPING SETS ((sistema.clave, sistema.descripcion, comp.clave, comp.descripcion),
                        (sistema.clave, sistema.descripcion))
ORDER BY sistema.clave, GROUPING(comp.clave), horas DESC;

-- ---------------------------------------------------------------------
-- C05. Código 03 (sistemas de potencia): horas por subcódigo y año.
--      Técnicas: CROSS JOIN catálogo × años (para mostrar ceros), LEFT JOIN, COALESCE.
-- ---------------------------------------------------------------------
WITH anios AS (SELECT DISTINCT EXTRACT(YEAR FROM fecha)::int AS anio FROM paros.registro_turno),
reales AS (
    SELECT id_subcodigo, anio, SUM(minutos) AS minutos
    FROM paros.paro p
    JOIN paros.v_registro_horas h USING (id_registro)
    WHERE p.id_codigo = 3
    GROUP BY id_subcodigo, anio
)
SELECT s.clave || ' ' || s.descripcion AS subcodigo,
       a.anio,
       round(COALESCE(r.minutos, 0) / 60, 2) AS horas
FROM paros.subcodigo s
CROSS JOIN anios a
LEFT JOIN reales r ON r.id_subcodigo = s.id_subcodigo AND r.anio = a.anio
WHERE s.id_codigo = 3
ORDER BY s.clave, a.anio;

-- ---------------------------------------------------------------------
-- C06. Código 05 (ajuste operativo): horas por subcódigo VIGENTE (los 4.x antiguos se
--      suman a su equivalente 5.x) y por área que atendió.
--      Técnicas: vista, COALESCE para la equivalencia, pivote con FILTER, HAVING.
-- ---------------------------------------------------------------------
SELECT COALESCE(subcodigo_vigente_clave || ' ' || subcodigo_vigente, '(sin especificar)') AS subcodigo,
       round(SUM(horas), 1)                                               AS horas_total,
       round(SUM(horas) FILTER (WHERE area_atiende = 'Operarios'), 1)     AS horas_operarios,
       round(SUM(horas) FILTER (WHERE area_atiende = 'Personal de mantenimiento'), 1) AS horas_mantenimiento,
       round(100 * SUM(horas) / SUM(SUM(horas)) OVER (), 1)                AS pct
FROM paros.v_paro_detalle
WHERE id_codigo = 5
GROUP BY subcodigo_vigente_clave, subcodigo_vigente
HAVING SUM(horas) > 0
ORDER BY horas_total DESC;

-- ---------------------------------------------------------------------
-- C07. Desempeño por turno (2024-2025, solo turnos con producción y nombre conocido).
--      Técnicas: JOIN, agregados, HAVING para descartar turnos con poca muestra.
-- ---------------------------------------------------------------------
SELECT t.nombre                                   AS turno,
       COUNT(*)                                   AS registros,
       round(AVG(h.pacas_producidas), 1)          AS pacas_promedio,
       round(SUM(h.pacas_producidas) / NULLIF(SUM(h.horas_trabajadas - h.horas_paro), 0), 2) AS pacas_por_hora_efectiva,
       paros.fn_productividad(SUM(h.horas_trabajadas), SUM(h.horas_paro)) AS pct_productividad
FROM paros.v_registro_horas h
JOIN paros.turno t ON t.id_turno = h.id_turno
WHERE h.fecha BETWEEN DATE '2024-01-01' AND DATE '2025-12-31'
  AND h.horas_trabajadas > 0
  AND t.duracion_horas IS NOT NULL
GROUP BY t.nombre
HAVING COUNT(*) >= 30
ORDER BY pct_productividad DESC;

-- ---------------------------------------------------------------------
-- C08. Top 3 de subcódigos del 05 por máquina en el primer trimestre de 2025.
--      Técnicas: rango de fechas, ventana ROW_NUMBER con PARTITION BY.
-- ---------------------------------------------------------------------
SELECT maquina, puesto, subcodigo, horas
FROM (
    SELECT maquina,
           COALESCE(subcodigo_vigente_clave || ' ' || subcodigo_vigente, '(sin especificar)') AS subcodigo,
           round(SUM(horas), 2) AS horas,
           ROW_NUMBER() OVER (PARTITION BY maquina ORDER BY SUM(horas) DESC) AS puesto
    FROM paros.v_paro_detalle
    WHERE id_codigo = 5 AND fecha BETWEEN DATE '2025-01-01' AND DATE '2025-03-31'
    GROUP BY maquina, subcodigo_vigente_clave, subcodigo_vigente
) x
WHERE puesto <= 3
ORDER BY maquina, puesto;

-- ---------------------------------------------------------------------
-- C09. Meses en que una máquina quedó por debajo del promedio de productividad de la planta en ese año.
--      Técnicas: subconsulta correlacionada en el WHERE.
-- ---------------------------------------------------------------------
SELECT v.maquina, v.anio, v.mes, v.pct_productividad,
       (SELECT paros.fn_productividad(SUM(x.horas_trabajadas), SUM(x.minutos_paro) / 60)
        FROM paros.v_productividad_mensual x WHERE x.anio = v.anio) AS pct_planta_anio
FROM paros.v_productividad_mensual v
WHERE v.pct_productividad < (SELECT paros.fn_productividad(SUM(x.horas_trabajadas), SUM(x.minutos_paro) / 60)
                             FROM paros.v_productividad_mensual x WHERE x.anio = v.anio)
  AND v.anio = 2024
ORDER BY v.maquina, v.mes;

-- ---------------------------------------------------------------------
-- C10. Ajustes operativos atendidos por cada técnico de mantenimiento (seudónimo).
--      Técnicas: LEFT JOIN desde persona (incluye técnicos sin registros), agregados.
-- ---------------------------------------------------------------------
SELECT pe.codigo                           AS tecnico,
       pe.activo,
       COUNT(p.id_paro)                    AS ajustes_atendidos,
       round(COALESCE(SUM(p.minutos), 0) / 60, 1) AS horas,
       round(AVG(p.minutos), 1)            AS minutos_promedio,
       MAX(r.fecha)                        AS ultimo_ajuste
FROM paros.persona pe
LEFT JOIN paros.paro p           ON p.id_persona_atiende = pe.id_persona AND p.id_codigo = 5
LEFT JOIN paros.registro_turno r ON r.id_registro = p.id_registro
WHERE pe.rol = 'MTO'
GROUP BY pe.codigo, pe.activo
ORDER BY ajustes_atendidos DESC;

-- ---------------------------------------------------------------------
-- C11. Operarias con más de 50 turnos en 2024 y su productividad.
--      Técnicas: JOIN, GROUP BY, HAVING.
-- ---------------------------------------------------------------------
SELECT pe.codigo AS operaria,
       COUNT(*) AS turnos,
       SUM(h.pacas_producidas) AS pacas,
       paros.fn_productividad(SUM(h.horas_trabajadas), SUM(h.horas_paro)) AS pct_productividad
FROM paros.v_registro_horas h
JOIN paros.persona pe ON pe.id_persona = h.id_operaria
WHERE h.anio = 2024 AND h.horas_trabajadas > 0
GROUP BY pe.codigo
HAVING COUNT(*) > 50
ORDER BY pct_productividad DESC;

-- ---------------------------------------------------------------------
-- C12. Horas no trabajadas por motivo, separando el catálogo antiguo del vigente.
--      Técnicas: LEFT JOIN encadenado (tipo → código equivalente), agregados.
-- ---------------------------------------------------------------------
SELECT tp.catalogo,
       tp.descripcion                         AS tipo_paro,
       COALESCE('[' || lpad(c.id_codigo::text, 2, '0') || '] ' || c.nombre, '(sin equivalencia)') AS codigo_equivalente,
       COUNT(*)                               AS registros,
       SUM(r.horas_no_trabajadas)             AS horas_no_trabajadas
FROM paros.registro_turno r
JOIN paros.tipo_paro tp        ON tp.id_tipo_paro = r.id_tipo_paro
LEFT JOIN paros.codigo_paro c  ON c.id_codigo = tp.id_codigo
GROUP BY tp.catalogo, tp.descripcion, c.id_codigo, c.nombre
ORDER BY horas_no_trabajadas DESC;

-- ---------------------------------------------------------------------
-- C13. Pareto: códigos que acumulan el 80 % del tiempo de paro en 2024.
--      Técnicas: CTE, ventana con acumulado (ROWS UNBOUNDED PRECEDING).
-- ---------------------------------------------------------------------
WITH por_codigo AS (
    SELECT codigo, SUM(horas) AS horas
    FROM paros.v_paro_detalle
    WHERE anio = 2024
    GROUP BY codigo
),
acumulado AS (
    SELECT codigo, horas,
           100 * SUM(horas) OVER (ORDER BY horas DESC ROWS UNBOUNDED PRECEDING) / SUM(horas) OVER () AS pct_acumulado
    FROM por_codigo
)
SELECT codigo, round(horas, 1) AS horas, round(pct_acumulado, 1) AS pct_acumulado
FROM acumulado
WHERE pct_acumulado - 100 * horas / (SELECT SUM(horas) FROM por_codigo) < 80   -- incluye el código que cruza el 80 %
ORDER BY horas DESC;

-- ---------------------------------------------------------------------
-- C14. Tendencia mensual de la planta con variación frente al mes anterior.
--      Técnicas: generate_series + LEFT JOIN (meses sin datos), ventana LAG.
-- ---------------------------------------------------------------------
WITH meses AS (
    SELECT generate_series(DATE '2024-01-01', DATE '2025-03-01', INTERVAL '1 month')::date AS mes
),
planta AS (
    SELECT date_trunc('month', fecha)::date AS mes,
           paros.fn_productividad(SUM(horas_trabajadas), SUM(horas_paro)) AS pct
    FROM paros.v_registro_horas
    GROUP BY 1
)
SELECT to_char(m.mes, 'YYYY-MM') AS mes,
       p.pct                     AS pct_productividad,
       p.pct - LAG(p.pct) OVER (ORDER BY m.mes) AS variacion_vs_mes_anterior
FROM meses m
LEFT JOIN planta p ON p.mes = m.mes
ORDER BY m.mes;

-- ---------------------------------------------------------------------
-- C15. Referencias del catálogo que nunca se han producido y producciones fuera de catálogo.
--      Técnicas: FULL OUTER JOIN entre el catálogo y lo producido.
-- ---------------------------------------------------------------------
WITH producido AS (
    SELECT DISTINCT id_maquina, id_referencia
    FROM paros.registro_turno
    WHERE id_referencia IS NOT NULL AND horas_trabajadas > 0
),
catalogo AS (
    SELECT id_maquina, id_referencia FROM paros.maquina_referencia WHERE en_catalogo
)
SELECT m.nombre AS maquina,
       r.nombre AS referencia,
       CASE WHEN c.id_referencia IS NULL THEN 'Producida pero no está en el catálogo'
            ELSE 'En catálogo, nunca producida' END AS situacion
FROM catalogo c
FULL OUTER JOIN producido p ON p.id_maquina = c.id_maquina AND p.id_referencia = c.id_referencia
JOIN paros.maquina m    ON m.id_maquina = COALESCE(c.id_maquina, p.id_maquina)
JOIN paros.referencia r ON r.id_referencia = COALESCE(c.id_referencia, p.id_referencia)
WHERE c.id_referencia IS NULL OR p.id_referencia IS NULL
ORDER BY situacion, maquina, referencia;

-- ---------------------------------------------------------------------
-- C16. Cola de revisión: registros con datos sospechosos heredados del Excel.
--      Técnicas: EXISTS / subconsulta, filtro sobre índice parcial.
-- ---------------------------------------------------------------------
SELECT r.fila_excel, r.fecha, m.nombre AS maquina, t.nombre AS turno,
       r.pacas_producidas, r.horas_trabajadas, r.horas_no_trabajadas,
       (SELECT round(SUM(p.minutos) / 60, 2) FROM paros.paro p WHERE p.id_registro = r.id_registro) AS horas_paro
FROM paros.registro_turno r
JOIN paros.maquina m ON m.id_maquina = r.id_maquina
JOIN paros.turno t   ON t.id_turno = r.id_turno
WHERE r.requiere_revision
  AND NOT EXISTS (SELECT 1 FROM stg.base_clasificada b
                  WHERE b.fila_excel = r.fila_excel AND b.es_duplicada)   -- los duplicados se revisan aparte
ORDER BY r.fecha;
