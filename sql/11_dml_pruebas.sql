-- =====================================================================
-- 11_dml_pruebas.sql
-- INSERT, UPDATE y DELETE que muestran cómo responden las restricciones.
-- Todo corre dentro de una transacción que termina en ROLLBACK: se puede
-- ejecutar las veces que se quiera sin dañar los datos.
--
-- Cada intento que DEBE fallar va en un bloque DO que atrapa el error e
-- imprime el mensaje de PostgreSQL (NOTICE). Así el script corre completo.
-- Para la sustentación en DBeaver, cada caso trae también la sentencia
-- "desnuda" comentada, para ejecutarla sola y ver el error en pantalla.
-- =====================================================================

SET search_path TO paros, public;

BEGIN;

-- ---------------------------------------------------------------------
-- A. INSERT válidos (los DEFAULT se llenan solos)
-- ---------------------------------------------------------------------

-- A1. Un turno nuevo. No se envían parte, requiere_revision ni registrado_en: toman su DEFAULT.
INSERT INTO paros.registro_turno (fecha, id_maquina, id_turno, id_operaria, id_referencia,
                                  pacas_producidas, horas_trabajadas, meta_por_hora)
SELECT DATE '2025-04-01',
       (SELECT id_maquina FROM paros.maquina WHERE nombre = 'Vinilos_3'),
       (SELECT id_turno FROM paros.turno WHERE nombre = '6am-2pm (Turno 1)'),
       (SELECT id_persona FROM paros.persona WHERE codigo = 'OPE-003'),
       (SELECT id_referencia FROM paros.referencia WHERE nombre = 'Parchesitos 22cc (6 col)'),
       85, 8, 12;

SELECT id_registro, fecha, parte, requiere_revision, registrado_en IS NOT NULL AS tiene_fecha_registro
FROM paros.registro_turno WHERE fecha = DATE '2025-04-01';

-- A2. Dos paros de ese turno: un ajuste operativo (05) con subcódigo y quien lo atendió, y una pausa activa (17).
INSERT INTO paros.paro (id_registro, id_codigo, id_subcodigo, minutos, id_area_agente, id_persona_atiende)
SELECT r.id_registro, 5,
       (SELECT id_subcodigo FROM paros.subcodigo WHERE id_codigo = 5 AND clave = '5.2'),
       25,
       (SELECT id_area_agente FROM paros.area_agente WHERE nombre = 'Personal de mantenimiento'),
       (SELECT id_persona FROM paros.persona WHERE codigo = 'MTO-002')
FROM paros.registro_turno r WHERE r.fecha = DATE '2025-04-01';

INSERT INTO paros.paro (id_registro, id_codigo, minutos)
SELECT r.id_registro, 17, 3 FROM paros.registro_turno r WHERE r.fecha = DATE '2025-04-01';

SELECT fecha, maquina, codigo, subcodigo, persona_atiende, minutos
FROM paros.v_paro_detalle WHERE fecha = DATE '2025-04-01';

-- ---------------------------------------------------------------------
-- B. INSERT rechazados
-- ---------------------------------------------------------------------

-- B1. CHECK: minutos negativos.
--   INSERT INTO paros.paro (id_registro, id_codigo, minutos)
--   SELECT id_registro, 6, -10 FROM paros.registro_turno WHERE fecha = '2025-04-01';
DO $$ BEGIN
    INSERT INTO paros.paro (id_registro, id_codigo, minutos)
    SELECT id_registro, 6, -10 FROM paros.registro_turno WHERE fecha = '2025-04-01';
    RAISE EXCEPTION 'NO DEBIÓ PASAR';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'B1 rechazado (CHECK minutos): %', SQLERRM;
END $$;

-- B2. FK compuesta: el subcódigo 1.2.A es del código 01, no del 03.
DO $$ BEGIN
    INSERT INTO paros.paro (id_registro, id_codigo, id_subcodigo, minutos)
    SELECT r.id_registro, 3, s.id_subcodigo, 15
    FROM paros.registro_turno r, paros.subcodigo s
    WHERE r.fecha = '2025-04-01' AND s.id_codigo = 1 AND s.clave = '1.2.A';
    RAISE EXCEPTION 'NO DEBIÓ PASAR';
EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'B2 rechazado (FK subcódigo-código): %', SQLERRM;
END $$;

-- B3. Trigger RN-03: un paro nuevo del código 01 sin subcódigo.
DO $$ BEGIN
    INSERT INTO paros.paro (id_registro, id_codigo, minutos)
    SELECT id_registro, 1, 20 FROM paros.registro_turno WHERE fecha = '2025-04-01';
    RAISE EXCEPTION 'NO DEBIÓ PASAR';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'B3 rechazado (trigger RN-03): %', SQLERRM;
END $$;

-- B4. Trigger RN-14: los paros superarían las 8 horas (480 min) trabajadas.
DO $$ BEGIN
    INSERT INTO paros.paro (id_registro, id_codigo, minutos)
    SELECT id_registro, 6, 470 FROM paros.registro_turno WHERE fecha = '2025-04-01';
    RAISE EXCEPTION 'NO DEBIÓ PASAR';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'B4 rechazado (trigger RN-14): %', SQLERRM;
END $$;

-- B5. UNIQUE: el mismo turno, máquina, operaria y referencia, otra vez.
DO $$ BEGIN
    INSERT INTO paros.registro_turno (fecha, id_maquina, id_turno, id_operaria, id_referencia, horas_trabajadas)
    SELECT fecha, id_maquina, id_turno, id_operaria, id_referencia, 8
    FROM paros.registro_turno WHERE fecha = '2025-04-01';
    RAISE EXCEPTION 'NO DEBIÓ PASAR';
EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'B5 rechazado (UNIQUE turno): %', SQLERRM;
END $$;

-- B6. FK compuesta máquina–referencia (RN-05): Vinilos_2 no envasa "Parchesitos 22cc (6 col)".
DO $$ BEGIN
    INSERT INTO paros.registro_turno (fecha, id_maquina, id_turno, id_referencia, horas_trabajadas)
    SELECT DATE '2025-04-01', m.id_maquina, t.id_turno, r.id_referencia, 8
    FROM paros.maquina m, paros.turno t, paros.referencia r
    WHERE m.nombre = 'Vinilos_2' AND t.nombre = '6am-2pm (Turno 1)' AND r.nombre = 'Parchesitos 22cc (6 col)';
    RAISE EXCEPTION 'NO DEBIÓ PASAR';
EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'B6 rechazado (FK máquina-referencia): %', SQLERRM;
END $$;

-- B7. CHECK NOT VALID: 20 h trabajadas + 10 h no trabajadas = 30 h en un día.
DO $$ BEGIN
    INSERT INTO paros.registro_turno (fecha, id_maquina, id_turno, horas_trabajadas, horas_no_trabajadas)
    SELECT DATE '2025-03-31', m.id_maquina, t.id_turno, 20, 10
    FROM paros.maquina m, paros.turno t WHERE m.nombre = 'Vinilos_4' AND t.nombre = 'No registrado';
    RAISE EXCEPTION 'NO DEBIÓ PASAR';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'B7 rechazado (CHECK 24 h): %', SQLERRM;
END $$;

-- B8. CHECK de formato: el seudónimo no corresponde al rol.
DO $$ BEGIN
    INSERT INTO paros.persona (codigo, rol) VALUES ('OPE-999', 'MTO');
    RAISE EXCEPTION 'NO DEBIÓ PASAR';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'B8 rechazado (CHECK código-rol): %', SQLERRM;
END $$;

-- B9. NOT NULL: un paro sin código.
DO $$ BEGIN
    INSERT INTO paros.paro (id_registro, minutos)
    SELECT id_registro, 10 FROM paros.registro_turno WHERE fecha = '2025-04-01';
    RAISE EXCEPTION 'NO DEBIÓ PASAR';
EXCEPTION WHEN not_null_violation THEN
    RAISE NOTICE 'B9 rechazado (NOT NULL): %', SQLERRM;
END $$;

-- B10. CHECK: área que atiende en un código distinto de 05.
DO $$ BEGIN
    INSERT INTO paros.paro (id_registro, id_codigo, minutos, id_area_agente)
    SELECT r.id_registro, 7, 10, a.id_area_agente
    FROM paros.registro_turno r, paros.area_agente a
    WHERE r.fecha = '2025-04-01' AND a.nombre = 'Operarios';
    RAISE EXCEPTION 'NO DEBIÓ PASAR';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'B10 rechazado (CHECK solo 05): %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------
-- C. UPDATE
-- ---------------------------------------------------------------------

-- C1. Corrección válida: la operaria reporta 90 pacas, no 85.
UPDATE paros.registro_turno SET pacas_producidas = 90 WHERE fecha = DATE '2025-04-01';

-- C2. Rechazado por CHECK: horas negativas (error de digitación con signo).
DO $$ BEGIN
    UPDATE paros.registro_turno SET horas_trabajadas = -2 WHERE fecha = DATE '2025-04-01';
    RAISE EXCEPTION 'NO DEBIÓ PASAR';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'C2 rechazado (CHECK horas 0-24): %', SQLERRM;
END $$;

-- C2b. Rechazado por trigger: 10 h en un turno de 8 h.
DO $$ BEGIN
    UPDATE paros.registro_turno SET horas_trabajadas = 10 WHERE fecha = DATE '2025-04-01';
    RAISE EXCEPTION 'NO DEBIÓ PASAR';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'C2b rechazado (trigger duración del turno): %', SQLERRM;
END $$;

-- C3. ON UPDATE CASCADE: si la empresa renumera el código 18 como 19, sus paros lo siguen.
SELECT COUNT(*) AS paros_codigo_18_antes FROM paros.paro WHERE id_codigo = 18;
UPDATE paros.codigo_paro SET id_codigo = 19 WHERE id_codigo = 18;
SELECT COUNT(*) AS paros_codigo_19_despues, (SELECT COUNT(*) FROM paros.paro WHERE id_codigo = 18) AS quedan_en_18
FROM paros.paro WHERE id_codigo = 19;

-- C4. Una fila histórica con más de 24 h: al editarla, la regla NOT VALID SÍ se exige.
DO $$ BEGIN
    UPDATE paros.registro_turno SET observaciones = 'revisado'
    WHERE horas_trabajadas + horas_no_trabajadas > 24 AND fila_excel IS NOT NULL;
    RAISE EXCEPTION 'NO DEBIÓ PASAR';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'C4 rechazado (CHECK NOT VALID al editar histórico): %', SQLERRM;
END $$;

-- ---------------------------------------------------------------------
-- D. DELETE
-- ---------------------------------------------------------------------

-- D1. RESTRICT: no se puede borrar un código que tiene paros registrados (06 Limpieza).
DO $$ BEGIN
    DELETE FROM paros.codigo_paro WHERE id_codigo = 6;
    RAISE EXCEPTION 'NO DEBIÓ PASAR';
EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'D1 rechazado (RESTRICT código con paros): %', SQLERRM;
END $$;

-- D2. RESTRICT: no se borra una persona con historial. Se desactiva.
DO $$ BEGIN
    DELETE FROM paros.persona WHERE codigo = 'OPE-003';
    RAISE EXCEPTION 'NO DEBIÓ PASAR';
EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'D2 rechazado (RESTRICT persona con turnos): %', SQLERRM;
END $$;
UPDATE paros.persona SET activo = false WHERE codigo = 'OPE-003';

-- D3. CASCADE: borrar un turno mal digitado borra sus paros.
SELECT COUNT(*) AS paros_antes FROM paros.paro p
JOIN paros.registro_turno r USING (id_registro) WHERE r.fecha = DATE '2025-04-01';
DELETE FROM paros.registro_turno WHERE fecha = DATE '2025-04-01';
SELECT COUNT(*) AS paros_despues FROM paros.paro p
JOIN paros.registro_turno r USING (id_registro) WHERE r.fecha = DATE '2025-04-01';

-- D4. SET NULL: se crea un subcódigo vigente de prueba (5.12) y uno antiguo (4.9) que lo
--     apunta como equivalente. Al borrar 5.12, el 4.9 se conserva con el enlace en NULL.
INSERT INTO paros.subcodigo (id_codigo, clave, descripcion) VALUES (5, '5.12', 'Prueba vigente');
INSERT INTO paros.subcodigo (id_codigo, clave, descripcion, vigente, id_equivalente)
SELECT 5, '4.9', 'Prueba antigua', false, id_subcodigo FROM paros.subcodigo WHERE clave = '5.12';
DELETE FROM paros.subcodigo WHERE clave = '5.12';
SELECT clave, descripcion, id_equivalente FROM paros.subcodigo WHERE clave = '4.9';

ROLLBACK;  -- deja la base exactamente como estaba
