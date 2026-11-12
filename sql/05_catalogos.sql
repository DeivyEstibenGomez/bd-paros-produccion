-- =====================================================================
-- 05_catalogos.sql
-- Catálogos estables, transcritos de las tablas del Excel:
--   Tabla2 (códigos y áreas), Tabla19 (tipos de paro), Sin_programación (sub 01),
--   Tabla9 (sub 03), Tabla10 (sub 05), Tabla7 (máquinas), Tabla18 (turnos),
--   Tabla12 (agentes) y las fórmulas I18/I19 de la hoja Registro.
-- Los catálogos que dependen de los datos (referencias, personas, causas)
-- los genera el ETL en 06_carga_catalogos_etl.sql.
-- =====================================================================

SET search_path TO paros, public;

-- Áreas de impacto (Tabla2, columna ÁREA DE IMPACTO) -------------------
INSERT INTO paros.area_impacto (nombre) VALUES
    ('Mantenimiento'),
    ('Producción'),
    ('Calidad'),
    ('Almacén de materias primas'),
    ('Paro programado'),
    ('Ventas');

-- Códigos de paro (Tabla2) ---------------------------------------------
INSERT INTO paros.codigo_paro (id_codigo, nombre, id_area, requiere_subcodigo)
SELECT v.id, v.nombre, a.id_area, v.req
FROM (VALUES
    ( 1, 'Falla del sistema electromecánico y/o de control', 'Mantenimiento', true),
    ( 2, 'Espera de soporte de mantenimiento', 'Mantenimiento', false),
    ( 3, 'Novedad en los sistemas de potencia (Aire, energía, vapor)', 'Mantenimiento', true),
    ( 4, 'Mantenimiento preventivo', 'Mantenimiento', false),
    ( 5, 'Ajuste operativo', 'Producción', true),
    ( 6, 'Limpieza por derrame operativo', 'Producción', false),
    ( 7, 'Alistamiento de máquina / Cambio de referencia', 'Producción', false),
    ( 8, 'Capacitación / Reunión', 'Producción', false),
    ( 9, 'Falta de operario', 'Producción', false),
    (10, 'Paro por ventaja/evacuación', 'Producción', false),
    (11, 'Reproceso', 'Producción', false),
    (12, 'Materia prima defectuosa o material de empaque no conforme', 'Calidad', false),
    (13, 'En espera por el aval del laboratorio de microbiología', 'Calidad', false),
    (14, 'Falta de materia prima', 'Almacén de materias primas', false),
    (15, 'Cambio de insumos (Roscadores, O''ring, Etiquetas)', 'Paro programado', false),
    (16, 'Alimentación y aseo de la zona de trabajo y la máquina', 'Paro programado', false),
    (17, 'Pausa activa', 'Paro programado', false),
    (18, 'Paro de máquina por ventas', 'Ventas', false)
) AS v(id, nombre, area, req)
JOIN paros.area_impacto a ON a.nombre = v.area;

-- Subcódigos ---------------------------------------------------------
-- Primer nivel (sistemas del 01, y los del 03 y 05)
INSERT INTO paros.subcodigo (id_codigo, clave, descripcion) VALUES
    (1, '1.1', 'Sistema alimentador de envases'),
    (1, '1.2', 'Sistema de dosificación'),
    (1, '1.3', 'Sistema de banda de entrada'),
    (1, '1.4', 'Sistema de tapado'),
    (1, '1.5', 'Sistema de alimentación de tapa'),
    (1, '1.6', 'Sistema Video Jet'),
    (1, '1.7', 'Sistema de sujeción y roscadores'),
    (1, '1.8', 'Sistema etiquetadora'),
    (3, '3.1', 'Fallo en la subestación'),
    (3, '3.2', 'Fallo en la red pública'),
    (3, '3.3', 'Falla en la red neumática o el compresor'),
    (3, '3.4', 'Falla en la red de enfriamiento o el chiller'),
    (3, '3.5', 'Falla en la red de vapor o la caldera'),
    (5, '5.1', 'Sistema alimentador de envases'),
    (5, '5.2', 'Sistema de dosificación de pintura, frontal posterior'),
    (5, '5.3', 'Banda transportadora de entrada'),
    (5, '5.4', 'Banda transportadora de salida'),
    (5, '5.5', 'Transfer y pisador de tapa'),
    (5, '5.6', 'Sistema alimentador de tapa y tobogán'),
    (5, '5.7', 'Video Jet'),
    (5, '5.8', 'Banda de sujeción y roscadores'),
    (5, '5.9', 'Sistema de etiquetado'),
    (5, '5.10', 'Purga de color'),
    (5, '5.11', 'Lavado de boquilla');

-- Segundo nivel del 01 (componentes). El padre se resuelve por la clave.
INSERT INTO paros.subcodigo (id_codigo, clave, descripcion, id_padre)
SELECT 1, v.clave, v.descripcion, p.id_subcodigo
FROM (VALUES
    ('1.1.A', 'Banda'), ('1.1.B', 'Motor'), ('1.1.C', 'Sensor'),
    ('1.2.A', 'Cambio de racores'), ('1.2.B', 'Ajuste de sensor'), ('1.2.C', 'Cambio de válvula'),
    ('1.2.D', 'Retenedores'), ('1.2.E', 'O''Ring'),
    ('1.3.A', 'Banda'), ('1.3.B', 'Motor'),
    ('1.4.A', 'Motor del transfer'), ('1.4.B', 'Pisador de tapa'), ('1.4.C', 'Sensor'),
    ('1.5.A', 'Banda'), ('1.5.B', 'Motor'), ('1.5.C', 'Sensor'),
    ('1.6.A', 'Fotocelda'), ('1.6.B', 'Sensor'),
    ('1.7.A', 'Banda de sujeción'), ('1.7.B', 'Roscadores'),
    ('1.8.A', 'Banda'), ('1.8.B', 'Motor'), ('1.8.C', 'Sensor')
) AS v(clave, descripcion)
JOIN paros.subcodigo p
  ON p.id_codigo = 1 AND p.clave = substring(v.clave FROM '^[0-9]+\.[0-9]+');

-- Catálogo antiguo del 05 (numeración 4.x, usado hasta 2023). Se conserva
-- para no reescribir el histórico y se enlaza a su equivalente vigente.
-- La equivalencia es por DESCRIPCIÓN, no por número (4.4 → 5.5, 4.6 → 5.7...).
INSERT INTO paros.subcodigo (id_codigo, clave, descripcion, vigente, id_equivalente)
SELECT 5, v.clave, v.descripcion, false, e.id_subcodigo
FROM (VALUES
    ('4.1', 'Sistema alimentación de envase', '5.1'),
    ('4.2', 'Sistema dosificador de pintura, frontal y posterior', '5.2'),
    ('4.3', 'Banda transportadora de entrada', '5.3'),
    ('4.4', 'Transfer y pisador de tapado', '5.5'),
    ('4.5', 'Sistema alimentador de tapa y tobogán', '5.6'),
    ('4.6', 'Video Jet', '5.7'),
    ('4.7', 'Banda sujeción y roscadores', '5.8'),
    ('4.8', 'Sistema de etiquetado', '5.9')
) AS v(clave, descripcion, equivale)
JOIN paros.subcodigo e ON e.id_codigo = 5 AND e.clave = v.equivale;

-- Máquinas (Tabla7 y velocidades de la hoja Tiempos) --------------------
INSERT INTO paros.maquina (nombre, unidades_minuto, factor_ajuste) VALUES
    ('Vinilos_1', 86, 0.93),
    ('Vinilos_2', 48, 0.96),
    ('Vinilos_3', 80, 1),
    ('Vinilos_4', 81, 1);

-- Turnos (Tabla18) -------------------------------------------------------
INSERT INTO paros.turno (nombre, hora_inicio, hora_fin, duracion_horas) VALUES
    ('6am-2pm (Turno 1)',  '06:00', '14:00', 8),
    ('2pm-10pm (Turno 2)', '14:00', '22:00', 8),
    ('10pm-6am (Turno 3)', '22:00', '06:00', 8),
    ('6am-6pm',            '06:00', '18:00', 12),
    ('6pm-6am',            '18:00', '06:00', 12),
    ('6am-4:30pm',         '06:00', '16:30', 10.5),
    ('Sin turno',          NULL, NULL, NULL),     -- "No aplica" del Excel: día sin producción
    ('No registrado',      NULL, NULL, NULL);     -- celda vacía en el histórico 2022-2024

-- Minutos estándar de los paros programados 16 y 17 (fórmulas I18 e I19)
INSERT INTO paros.paro_programado_turno (id_turno, id_codigo, minutos)
SELECT t.id_turno, c.id_codigo,
       CASE WHEN t.nombre = '6am-4:30pm' THEN CASE c.id_codigo WHEN 16 THEN 70 ELSE 6 END
            ELSE CASE c.id_codigo WHEN 16 THEN 40 ELSE 3 END END
FROM paros.turno t
CROSS JOIN paros.codigo_paro c
WHERE c.id_codigo IN (16, 17)
  AND t.duracion_horas IS NOT NULL;

-- Áreas que atienden un ajuste operativo (Tabla12) ------------------------
INSERT INTO paros.area_agente (nombre) VALUES
    ('Personal de mantenimiento'),
    ('Operarios'),
    ('Auxiliar de piso'),
    ('Personal de despachos'),
    ('Personal de calidad'),
    ('Supervisor');

-- Tipos de paro (Tabla19 + catálogo antiguo encontrado en el histórico) ---
INSERT INTO paros.tipo_paro (descripcion, catalogo, id_codigo)
SELECT '[' || lpad(id_codigo::text, 2, '0') || '] ' || nombre, 'VIGENTE', id_codigo
FROM paros.codigo_paro;

-- Equivalencias propuestas (supuesto S-03). Las que no tienen par claro quedan en NULL:
-- "17. PARO DE MAQUINA" agrupa causas de ventas y de mantenimiento preventivo;
-- "9. FALTA DE PROGRAMACIÓN" y "16. PARO POR PROCESO ANTERIOR" no tienen código vigente.
INSERT INTO paros.tipo_paro (descripcion, catalogo, id_codigo) VALUES
    ('3. AJUSTE ELECTRICO O DE SERVICIOS (AIRE, CALDERA, GAS)', 'ANTIGUO', 3),
    ('4. AJUSTE DE OPERACIÓN', 'ANTIGUO', 5),
    ('5. AISLAMIENTO/CAMBIO DE PRODUCTO', 'ANTIGUO', 7),
    ('6. FALTA DE MATERIALES O MATERIAS PRIMAS', 'ANTIGUO', 14),
    ('9. FALTA DE PROGRAMACIÓN (PLANEACIÓN)', 'ANTIGUO', NULL),
    ('10. PARO POR MATERIA PRIMA O MATERIAL DE EMPAQUE NO CONFORME', 'ANTIGUO', 12),
    ('11. LIMPIEZA NO PROGRAMADA', 'ANTIGUO', 6),
    ('15. APROBACION DE LABORATORIO (MICROBIOLOGIA)', 'ANTIGUO', 13),
    ('16. PARO POR PROCESO ANTERIOR', 'ANTIGUO', NULL),
    ('17. PARO DE MAQUINA', 'ANTIGUO', NULL);
