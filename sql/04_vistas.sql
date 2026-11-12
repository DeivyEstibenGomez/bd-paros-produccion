-- =====================================================================
-- 04_vistas.sql
-- Vistas que reemplazan las tablas dinámicas del Excel. Nadie tiene que
-- "actualizar" nada: se calculan cada vez sobre los datos vigentes.
-- =====================================================================

SET search_path TO paros, public;

-- V1. Paro con todo su contexto, listo para filtrar o exportar.
CREATE OR REPLACE VIEW paros.v_paro_detalle AS
SELECT p.id_paro,
       r.id_registro,
       r.fecha,
       EXTRACT(YEAR  FROM r.fecha)::int AS anio,
       EXTRACT(MONTH FROM r.fecha)::int AS mes,
       m.nombre                          AS maquina,
       t.nombre                          AS turno,
       op.codigo                         AS operaria,
       ref.nombre                        AS referencia,
       a.nombre                          AS area_impacto,
       c.id_codigo,
       '[' || lpad(c.id_codigo::text, 2, '0') || '] ' || c.nombre AS codigo,
       s.clave                           AS subcodigo_clave,
       s.descripcion                     AS subcodigo,
       -- Para informes: el subcódigo antiguo se reporta con su equivalente vigente
       COALESCE(eq.clave, s.clave)       AS subcodigo_vigente_clave,
       COALESCE(eq.descripcion, s.descripcion) AS subcodigo_vigente,
       padre.clave                       AS sistema_clave,
       padre.descripcion                 AS sistema,
       ag.nombre                         AS area_atiende,
       pa.codigo                         AS persona_atiende,
       p.minutos,
       round(p.minutos / 60.0, 4)        AS horas
FROM paros.paro p
JOIN paros.registro_turno r   ON r.id_registro = p.id_registro
JOIN paros.maquina m          ON m.id_maquina = r.id_maquina
JOIN paros.turno t            ON t.id_turno = r.id_turno
JOIN paros.codigo_paro c      ON c.id_codigo = p.id_codigo
JOIN paros.area_impacto a     ON a.id_area = c.id_area
LEFT JOIN paros.persona op    ON op.id_persona = r.id_operaria
LEFT JOIN paros.referencia ref ON ref.id_referencia = r.id_referencia
LEFT JOIN paros.subcodigo s   ON s.id_subcodigo = p.id_subcodigo
LEFT JOIN paros.subcodigo eq  ON eq.id_subcodigo = s.id_equivalente
LEFT JOIN paros.subcodigo padre ON padre.id_subcodigo = COALESCE(s.id_padre, s.id_subcodigo)
LEFT JOIN paros.area_agente ag ON ag.id_area_agente = p.id_area_agente
LEFT JOIN paros.persona pa    ON pa.id_persona = p.id_persona_atiende;
COMMENT ON VIEW paros.v_paro_detalle IS 'Un renglón por paro con máquina, turno, código, subcódigo (y su sistema) y quién lo atendió.';

-- V2. Horas trabajadas y de paro por registro. Base de todos los indicadores.
--     Agrega los paros ANTES de unir, para no multiplicar horas trabajadas
--     por el número de paros (error clásico al hacer JOIN + SUM).
CREATE OR REPLACE VIEW paros.v_registro_horas AS
SELECT r.id_registro,
       r.fecha,
       EXTRACT(YEAR  FROM r.fecha)::int AS anio,
       EXTRACT(MONTH FROM r.fecha)::int AS mes,
       r.id_maquina,
       r.id_turno,
       r.id_operaria,
       r.pacas_producidas,
       r.horas_trabajadas,
       r.horas_no_trabajadas,
       COALESCE(pp.minutos_paro, 0)        AS minutos_paro,
       COALESCE(pp.minutos_paro, 0) / 60.0 AS horas_paro
FROM paros.registro_turno r
LEFT JOIN (
    SELECT id_registro, SUM(minutos) AS minutos_paro
    FROM paros.paro
    GROUP BY id_registro
) pp ON pp.id_registro = r.id_registro;
COMMENT ON VIEW paros.v_registro_horas IS 'Horas trabajadas y horas de paro por registro de turno.';

-- V3. % de productividad por máquina, año y mes (gráfico "producción por máquina").
CREATE OR REPLACE VIEW paros.v_productividad_mensual AS
SELECT m.nombre AS maquina,
       h.anio,
       h.mes,
       COUNT(*)                          AS registros,
       SUM(h.horas_trabajadas)           AS horas_trabajadas,
       round(SUM(h.horas_paro), 2)       AS horas_paro,
       SUM(h.minutos_paro)               AS minutos_paro,   -- exacto: úsese para re-agregar
       paros.fn_productividad(SUM(h.horas_trabajadas), SUM(h.horas_paro)) AS pct_productividad
FROM paros.v_registro_horas h
JOIN paros.maquina m ON m.id_maquina = h.id_maquina
GROUP BY m.nombre, h.anio, h.mes;
COMMENT ON VIEW paros.v_productividad_mensual IS '% productividad = (Σ horas trabajadas − Σ horas de paro) / Σ horas trabajadas, por máquina y mes.';

-- V4. Participación de cada código sobre el tiempo de paro y sobre las horas trabajadas, por año.
CREATE OR REPLACE VIEW paros.v_participacion_codigo_anual AS
WITH horas_anio AS (
    SELECT anio, SUM(horas_trabajadas) AS horas_trabajadas
    FROM paros.v_registro_horas
    GROUP BY anio
),
paro_anio AS (
    SELECT anio, id_codigo, codigo, area_impacto, SUM(horas) AS horas_paro
    FROM paros.v_paro_detalle
    GROUP BY anio, id_codigo, codigo, area_impacto
)
SELECT p.anio,
       p.id_codigo,
       p.codigo,
       p.area_impacto,
       round(p.horas_paro, 2) AS horas_paro,
       round(100 * p.horas_paro / SUM(p.horas_paro) OVER (PARTITION BY p.anio), 2) AS pct_del_paro,
       round(100 * p.horas_paro / NULLIF(h.horas_trabajadas, 0), 2)               AS pct_de_horas_trabajadas
FROM paro_anio p
JOIN horas_anio h ON h.anio = p.anio;
COMMENT ON VIEW paros.v_participacion_codigo_anual IS 'Peso de cada código: sobre el total de paro y sobre las horas trabajadas (como la tabla dinámica TD_prodCodigo).';
