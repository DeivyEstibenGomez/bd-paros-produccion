-- =====================================================================
-- 03_indices.sql
-- PostgreSQL crea índice para PK y UNIQUE, pero NO para las FK.
-- Cada índice de abajo responde a una consulta concreta de 11_consultas_negocio.sql.
-- =====================================================================

SET search_path TO paros, public;

-- I1. Productividad por máquina y mes, comparativos entre años, filtros por rango de fechas
--     (consultas C01, C02, C08, C09, C14). La fecha va primero porque casi todas
--     las consultas filtran por rango; la máquina completa la agrupación.
CREATE INDEX ix_rt_fecha_maquina ON paros.registro_turno (fecha, id_maquina)
    INCLUDE (horas_trabajadas, pacas_producidas);

-- I2. Unión paro → registro_turno. Es la FK más usada (todas las consultas de paros)
--     y la que usa el ON DELETE CASCADE al borrar un registro.
CREATE INDEX ix_paro_registro ON paros.paro (id_registro);

-- I3. Participación por código y detalle por subcódigo (C03, C04, C05, C06, C13).
--     INCLUDE minutos permite responder solo con el índice (index-only scan).
CREATE INDEX ix_paro_codigo_subcodigo ON paros.paro (id_codigo, id_subcodigo) INCLUDE (minutos);

-- I4. Comparación entre turnos (C07).
CREATE INDEX ix_rt_turno_fecha ON paros.registro_turno (id_turno, fecha);

-- I5. Ajustes atendidos por persona (C10). Parcial: solo el ~25 % de los paros tiene persona.
CREATE INDEX ix_paro_persona ON paros.paro (id_persona_atiende)
    WHERE id_persona_atiende IS NOT NULL;

-- I6. Desempeño por operaria (C11). Parcial: excluye días sin producción.
CREATE INDEX ix_rt_operaria ON paros.registro_turno (id_operaria)
    WHERE id_operaria IS NOT NULL;

-- I7. Cola de revisión de calidad de datos (C12). Muy selectivo: pocas filas marcadas.
CREATE INDEX ix_rt_revision ON paros.registro_turno (fecha)
    WHERE requiere_revision;
