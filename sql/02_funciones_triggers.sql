-- =====================================================================
-- 02_funciones_triggers.sql
-- Reglas de negocio que un CHECK no puede expresar porque miran otras
-- filas u otras tablas. Solo se exigen a capturas nuevas (fila_excel IS NULL)
-- para no rechazar el histórico, que ya viene con sus defectos documentados.
-- =====================================================================

SET search_path TO paros, public;

-- Regla RN-03: los códigos 01, 03 y 05 exigen subcódigo.
-- Regla RN-14: los minutos de paro de un turno no pueden superar sus horas trabajadas.
CREATE OR REPLACE FUNCTION paros.fn_validar_paro()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_requiere  boolean;
    v_horas     numeric;
    v_acumulado numeric;
BEGIN
    IF NEW.fila_excel IS NOT NULL THEN
        RETURN NEW;  -- dato histórico migrado: se respeta tal como venía
    END IF;

    SELECT requiere_subcodigo INTO v_requiere
    FROM paros.codigo_paro WHERE id_codigo = NEW.id_codigo;

    IF v_requiere AND NEW.id_subcodigo IS NULL THEN
        RAISE EXCEPTION 'El código % exige subcódigo (regla RN-03).', lpad(NEW.id_codigo::text, 2, '0')
            USING ERRCODE = 'check_violation';
    END IF;

    SELECT horas_trabajadas INTO v_horas
    FROM paros.registro_turno WHERE id_registro = NEW.id_registro;

    SELECT COALESCE(SUM(minutos), 0) INTO v_acumulado
    FROM paros.paro
    WHERE id_registro = NEW.id_registro
      AND id_paro IS DISTINCT FROM NEW.id_paro;

    IF v_acumulado + NEW.minutos > v_horas * 60 THEN
        RAISE EXCEPTION 'Los paros del turno sumarían % min y el turno solo tiene % min trabajados (regla RN-14).',
            v_acumulado + NEW.minutos, v_horas * 60
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_paro_validar
    BEFORE INSERT OR UPDATE ON paros.paro
    FOR EACH ROW EXECUTE FUNCTION paros.fn_validar_paro();

-- Regla: no se registran turnos en el futuro, y las horas no superan la duración del turno.
CREATE OR REPLACE FUNCTION paros.fn_validar_registro()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_duracion numeric;
BEGIN
    IF NEW.fila_excel IS NOT NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.fecha > current_date THEN
        RAISE EXCEPTION 'La fecha % es futura; un turno se registra cuando ya ocurrió.', NEW.fecha
            USING ERRCODE = 'check_violation';
    END IF;

    SELECT duracion_horas INTO v_duracion FROM paros.turno WHERE id_turno = NEW.id_turno;
    IF v_duracion IS NOT NULL AND NEW.horas_trabajadas > v_duracion THEN
        RAISE EXCEPTION 'El turno dura % h y se reportan % h trabajadas.', v_duracion, NEW.horas_trabajadas
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_registro_validar
    BEFORE INSERT OR UPDATE ON paros.registro_turno
    FOR EACH ROW EXECUTE FUNCTION paros.fn_validar_registro();

-- Función de apoyo para los indicadores: % de productividad (RN-09).
-- IMMUTABLE porque solo depende de sus argumentos.
CREATE OR REPLACE FUNCTION paros.fn_productividad(p_horas_trab numeric, p_horas_paro numeric)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE WHEN p_horas_trab > 0
                THEN round((p_horas_trab - p_horas_paro) / p_horas_trab * 100, 2)
           END;
$$;
COMMENT ON FUNCTION paros.fn_productividad(numeric, numeric) IS
    '% productividad = (horas trabajadas - horas de paro) / horas trabajadas × 100. Misma fórmula del campo calculado de las tablas dinámicas del Excel.';
