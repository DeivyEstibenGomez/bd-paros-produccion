-- =====================================================================
-- 08_transformacion.sql
-- Pasa stg.base_excel (una fila del Excel por renglón, 18 columnas de
-- minutos) al modelo normalizado. Aquí ocurre la 1FN en la práctica:
-- las columnas m1..m18 se convierten en filas de paros.paro.
--
-- Tipos de fila del Excel (ver docs/04_normalizacion.md):
--   REG   fila con pacas, horas trabajadas u horas no trabajadas → registro_turno
--   SUB   fila de "Ingreso subcódigo": sin horas ni pacas, con subcódigo → paros del turno padre
--   VACIA fila sin horas, pacas ni minutos → no se carga; queda en stg.rechazo con motivo
-- =====================================================================

SET search_path TO paros, public;

BEGIN;

-- 1. Clasificar cada fila -------------------------------------------------
DROP TABLE IF EXISTS stg.base_clasificada;
CREATE TABLE stg.base_clasificada AS
SELECT b.*,
       CASE
           WHEN b.pacas IS NOT NULL OR b.horas_trab IS NOT NULL OR b.horas_no_trab IS NOT NULL THEN 'REG'
           WHEN COALESCE(b.m1, 0) + COALESCE(b.m2, 0) + COALESCE(b.m3, 0) + COALESCE(b.m4, 0) + COALESCE(b.m5, 0)
              + COALESCE(b.m6, 0) + COALESCE(b.m7, 0) + COALESCE(b.m8, 0) + COALESCE(b.m9, 0) + COALESCE(b.m10, 0)
              + COALESCE(b.m11, 0) + COALESCE(b.m12, 0) + COALESCE(b.m13, 0) + COALESCE(b.m14, 0) + COALESCE(b.m15, 0)
              + COALESCE(b.m16, 0) + COALESCE(b.m17, 0) + COALESCE(b.m18, 0) > 0 THEN 'SUB'
           ELSE 'VACIA'
       END AS tipo_fila,
       -- Fila idéntica a otra (todas las columnas iguales salvo la posición)
       COUNT(*) OVER (PARTITION BY b.fecha, b.maquina, b.operario, b.referencia, b.turno, b.pacas, b.horas_trab,
                      b.horas_no_trab, b.tipo_paro, b.causa, b.sub1, b.sub3, b.sub5, b.area5, b.personal5,
                      b.observaciones, b.m1, b.m2, b.m3, b.m4, b.m5, b.m6, b.m7, b.m8, b.m9, b.m10, b.m11,
                      b.m12, b.m13, b.m14, b.m15, b.m16, b.m17, b.m18) > 1 AS es_duplicada
FROM stg.base_excel b;

ALTER TABLE stg.base_clasificada ADD PRIMARY KEY (fila_excel);

-- 2. Registros de turno (filas REG) ----------------------------------------
--    "parte" numera las filas que comparten fecha, máquina, turno, operaria y
--    referencia (frecuente en 2022-2023, cuando no se anotaba el turno).
INSERT INTO paros.registro_turno
      (fecha, id_maquina, id_turno, id_operaria, id_referencia, parte, pacas_producidas,
       horas_trabajadas, horas_no_trabajadas, id_tipo_paro, id_causa, observaciones,
       requiere_revision, fila_excel)
SELECT b.fecha,
       m.id_maquina,
       t.id_turno,
       op.id_persona,
       r.id_referencia,
       ROW_NUMBER() OVER (PARTITION BY b.fecha, m.id_maquina, t.id_turno, op.id_persona, r.id_referencia
                          ORDER BY b.fila_excel DESC),          -- la fila más antigua es la parte 1
       b.pacas,
       COALESCE(b.horas_trab, 0),
       COALESCE(b.horas_no_trab, 0),
       tp.id_tipo_paro,
       ca.id_causa,
       b.observaciones,
       b.es_duplicada
         OR COALESCE(b.horas_trab, 0) + COALESCE(b.horas_no_trab, 0) > 24
         OR COALESCE(b.pacas, 0) > 3000,
       b.fila_excel
FROM stg.base_clasificada b
JOIN paros.maquina m          ON m.nombre = b.maquina
JOIN paros.turno t            ON t.nombre = b.turno
LEFT JOIN paros.persona op    ON op.codigo = b.operario
LEFT JOIN paros.referencia r  ON r.nombre = b.referencia
LEFT JOIN paros.tipo_paro tp  ON tp.descripcion = b.tipo_paro
LEFT JOIN paros.causa_paro ca ON ca.descripcion = b.causa
WHERE b.tipo_fila = 'REG';

-- 3. Turno padre de cada fila SUB -----------------------------------------
--    La macro inserta arriba (fila 10) y empuja todo hacia abajo, así que la fila
--    de subcódigo queda ENCIMA de su turno: el padre es la fila REG más cercana
--    por debajo con la misma fecha, máquina, turno, operaria y referencia.
--    Si no hay coincidencia exacta se relaja a fecha + máquina + turno, y luego
--    a fecha + máquina.
DROP TABLE IF EXISTS stg.sub_padre;
CREATE TABLE stg.sub_padre AS
WITH sub AS (
    SELECT * FROM stg.base_clasificada WHERE tipo_fila = 'SUB'
),
reg AS (
    SELECT b.*, rt.id_registro
    FROM stg.base_clasificada b
    JOIN paros.registro_turno rt ON rt.fila_excel = b.fila_excel
),
candidatos AS (
    SELECT s.fila_excel, r.id_registro, 1 AS nivel, r.fila_excel AS fila_reg
    FROM sub s JOIN reg r
      ON r.fecha = s.fecha AND r.maquina = s.maquina AND r.turno = s.turno
     AND r.operario IS NOT DISTINCT FROM s.operario
     AND r.referencia IS NOT DISTINCT FROM s.referencia
    UNION ALL
    SELECT s.fila_excel, r.id_registro, 2, r.fila_excel
    FROM sub s JOIN reg r ON r.fecha = s.fecha AND r.maquina = s.maquina AND r.turno = s.turno
    UNION ALL
    SELECT s.fila_excel, r.id_registro, 3, r.fila_excel
    FROM sub s JOIN reg r ON r.fecha = s.fecha AND r.maquina = s.maquina
)
SELECT DISTINCT ON (fila_excel) fila_excel, id_registro, nivel
FROM candidatos
ORDER BY fila_excel, nivel,
         (fila_reg < fila_excel),          -- primero las filas REG de abajo (fila mayor)
         abs(fila_reg - fila_excel);

-- 3b. Filas SUB sin ningún turno ese día en esa máquina: se crea un registro
--     de 0 horas para no perder sus minutos de paro (quedan para revisión).
INSERT INTO paros.registro_turno (fecha, id_maquina, id_turno, id_operaria, id_referencia, parte,
                                  horas_trabajadas, requiere_revision, fila_excel)
SELECT b.fecha, m.id_maquina, t.id_turno, op.id_persona, r.id_referencia,
       COALESCE((SELECT MAX(x.parte) FROM paros.registro_turno x
                 WHERE x.fecha = b.fecha AND x.id_maquina = m.id_maquina AND x.id_turno = t.id_turno
                   AND x.id_operaria IS NOT DISTINCT FROM op.id_persona
                   AND x.id_referencia IS NOT DISTINCT FROM r.id_referencia), 0)
       + ROW_NUMBER() OVER (PARTITION BY b.fecha, m.id_maquina, t.id_turno, op.id_persona, r.id_referencia
                            ORDER BY b.fila_excel DESC),
       0, true, b.fila_excel
FROM stg.base_clasificada b
JOIN paros.maquina m ON m.nombre = b.maquina
JOIN paros.turno t   ON t.nombre = b.turno
LEFT JOIN paros.persona op   ON op.codigo = b.operario
LEFT JOIN paros.referencia r ON r.nombre = b.referencia
WHERE b.tipo_fila = 'SUB'
  AND NOT EXISTS (SELECT 1 FROM stg.sub_padre sp WHERE sp.fila_excel = b.fila_excel);

INSERT INTO stg.sub_padre (fila_excel, id_registro, nivel)
SELECT rt.fila_excel, rt.id_registro, 9
FROM paros.registro_turno rt
JOIN stg.base_clasificada b ON b.fila_excel = rt.fila_excel AND b.tipo_fila = 'SUB';

-- 4. Paros: de 18 columnas a filas (unpivot con LATERAL VALUES) -----------
INSERT INTO paros.paro (id_registro, id_codigo, id_subcodigo, minutos, id_area_agente, id_persona_atiende, fila_excel)
SELECT COALESCE(rt.id_registro, sp.id_registro),
       u.id_codigo,
       sc.id_subcodigo,
       u.minutos,
       CASE WHEN u.id_codigo = 5 THEN ag.id_area_agente END,
       CASE WHEN u.id_codigo = 5 THEN pe.id_persona END,
       b.fila_excel
FROM stg.base_clasificada b
LEFT JOIN paros.registro_turno rt ON rt.fila_excel = b.fila_excel AND b.tipo_fila = 'REG'
LEFT JOIN stg.sub_padre sp        ON sp.fila_excel = b.fila_excel AND b.tipo_fila = 'SUB'
CROSS JOIN LATERAL (VALUES
    ( 1, b.m1), ( 2, b.m2), ( 3, b.m3), ( 4, b.m4), ( 5, b.m5), ( 6, b.m6),
    ( 7, b.m7), ( 8, b.m8), ( 9, b.m9), (10, b.m10), (11, b.m11), (12, b.m12),
    (13, b.m13), (14, b.m14), (15, b.m15), (16, b.m16), (17, b.m17), (18, b.m18)
) AS u(id_codigo, minutos)
LEFT JOIN paros.subcodigo sc
       ON sc.id_codigo = u.id_codigo
      AND sc.clave = CASE u.id_codigo WHEN 1 THEN b.sub1 WHEN 3 THEN b.sub3 WHEN 5 THEN b.sub5 END
LEFT JOIN paros.area_agente ag ON ag.nombre = b.area5
LEFT JOIN paros.persona pe     ON pe.codigo = b.personal5
WHERE b.tipo_fila IN ('REG', 'SUB')
  AND u.minutos > 0;

-- 5. Marcar turnos cuyo paro supera las horas trabajadas ----------------
UPDATE paros.registro_turno rt
SET requiere_revision = true
FROM paros.v_registro_horas h
WHERE h.id_registro = rt.id_registro
  AND rt.horas_trabajadas > 0
  AND h.horas_paro > rt.horas_trabajadas;

-- 6. Lo que no se cargó, con su motivo ----------------------------------
INSERT INTO stg.rechazo (fila_excel, motivo)
SELECT fila_excel, 'Fila vacía: sin pacas, horas ni minutos de paro'
FROM stg.base_clasificada
WHERE tipo_fila = 'VACIA';

INSERT INTO stg.rechazo (fila_excel, motivo)
SELECT b.fila_excel, 'Código ' || u.id_codigo || ' con 0 minutos (celda en cero, no es un paro)'
FROM stg.base_clasificada b
CROSS JOIN LATERAL (VALUES
    ( 1, b.m1), ( 2, b.m2), ( 3, b.m3), ( 4, b.m4), ( 5, b.m5), ( 6, b.m6),
    ( 7, b.m7), ( 8, b.m8), ( 9, b.m9), (10, b.m10), (11, b.m11), (12, b.m12),
    (13, b.m13), (14, b.m14), (15, b.m15), (16, b.m16), (17, b.m17), (18, b.m18)
) AS u(id_codigo, minutos)
WHERE u.minutos = 0;

COMMIT;

-- 7. Regla "un día tiene 24 horas" -----------------------------------------
--    Se crea DESPUÉS de cargar el histórico y con NOT VALID: PostgreSQL no revisa
--    las filas existentes (9 del Excel la violan y quedaron con requiere_revision),
--    pero sí la exige en todo INSERT nuevo y en todo UPDATE de esas filas.
--    Cuando el negocio las corrija: ALTER TABLE ... VALIDATE CONSTRAINT ck_rt_dia_24h;
ALTER TABLE paros.registro_turno
    ADD CONSTRAINT ck_rt_dia_24h CHECK (horas_trabajadas + horas_no_trabajadas <= 24) NOT VALID;

-- Estadísticas frescas para el planificador después de la carga masiva
ANALYZE paros.registro_turno;
ANALYZE paros.paro;
