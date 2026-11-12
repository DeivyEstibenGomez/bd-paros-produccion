-- =====================================================================
-- 01_esquema.sql
-- Esquema normalizado (3FN) para el registro de paros de producción.
-- Motor: PostgreSQL 16 (funciona desde la 15 por UNIQUE NULLS NOT DISTINCT).
-- Se puede ejecutar varias veces: borra y recrea los esquemas.
-- =====================================================================

DROP SCHEMA IF EXISTS paros   CASCADE;
DROP SCHEMA IF EXISTS stg     CASCADE;
DROP SCHEMA IF EXISTS privado CASCADE;

CREATE SCHEMA paros;    -- datos operativos (sin nombres de personas)
CREATE SCHEMA stg;      -- zona de aterrizaje de la migración desde Excel
CREATE SCHEMA privado;  -- datos personales, con acceso restringido

COMMENT ON SCHEMA paros   IS 'Modelo normalizado de producción y paros por turno.';
COMMENT ON SCHEMA stg     IS 'Staging: copia fiel del Excel antes de transformar. Se puede borrar tras la migración.';
COMMENT ON SCHEMA privado IS 'Identidad de las personas (Ley 1581 de 2012). Solo lo consulta el rol de talento humano.';

SET search_path TO paros, public;

-- ---------------------------------------------------------------------
-- CATÁLOGOS
-- ---------------------------------------------------------------------

CREATE TABLE paros.area_impacto (
    id_area      smallint GENERATED ALWAYS AS IDENTITY,
    nombre       varchar(40) NOT NULL,
    CONSTRAINT pk_area_impacto PRIMARY KEY (id_area),
    CONSTRAINT uq_area_impacto_nombre UNIQUE (nombre),
    CONSTRAINT ck_area_impacto_nombre CHECK (btrim(nombre) <> '')
);
COMMENT ON TABLE  paros.area_impacto IS 'Área de la empresa responsable de un código de paro (Mantenimiento, Producción, Calidad...).';
COMMENT ON COLUMN paros.area_impacto.id_area IS 'Identificador sustituto del área.';
COMMENT ON COLUMN paros.area_impacto.nombre  IS 'Nombre del área tal como aparece en la tabla de códigos del Excel.';

CREATE TABLE paros.codigo_paro (
    id_codigo          smallint     NOT NULL,
    nombre             varchar(120) NOT NULL,
    id_area            smallint     NOT NULL,
    requiere_subcodigo boolean      NOT NULL DEFAULT false,
    activo             boolean      NOT NULL DEFAULT true,
    CONSTRAINT pk_codigo_paro PRIMARY KEY (id_codigo),
    CONSTRAINT ck_codigo_paro_rango CHECK (id_codigo BETWEEN 1 AND 99),
    CONSTRAINT uq_codigo_paro_nombre UNIQUE (nombre),
    CONSTRAINT fk_codigo_paro_area FOREIGN KEY (id_area)
        REFERENCES paros.area_impacto (id_area)
        ON UPDATE CASCADE ON DELETE RESTRICT
);
COMMENT ON TABLE  paros.codigo_paro IS 'Catálogo oficial de códigos de paro del P-MTO-22 ([01] a [18]).';
COMMENT ON COLUMN paros.codigo_paro.id_codigo IS 'Número del código. Clave natural: es como lo conoce la planta.';
COMMENT ON COLUMN paros.codigo_paro.nombre IS 'Descripción del código sin el prefijo [NN].';
COMMENT ON COLUMN paros.codigo_paro.id_area IS 'Área de impacto a la que se carga el paro.';
COMMENT ON COLUMN paros.codigo_paro.requiere_subcodigo IS 'Verdadero para 01, 03 y 05: un paro nuevo de estos códigos debe traer subcódigo.';
COMMENT ON COLUMN paros.codigo_paro.activo IS 'Falso si el código deja de usarse; no se borra para no perder el histórico.';

CREATE TABLE paros.subcodigo (
    id_subcodigo   integer      GENERATED ALWAYS AS IDENTITY,
    id_codigo      smallint     NOT NULL,
    clave          varchar(10)  NOT NULL,
    descripcion    varchar(120) NOT NULL,
    id_padre       integer      NULL,
    id_equivalente integer      NULL,
    vigente        boolean      NOT NULL DEFAULT true,
    CONSTRAINT pk_subcodigo PRIMARY KEY (id_subcodigo),
    CONSTRAINT uq_subcodigo_clave UNIQUE (id_codigo, clave),
    -- Permite que paro y subcodigo.id_padre referencien el par (subcódigo, código)
    CONSTRAINT uq_subcodigo_par UNIQUE (id_subcodigo, id_codigo),
    CONSTRAINT ck_subcodigo_clave CHECK (clave ~ '^[0-9]{1,2}\.[0-9]{1,2}(\.[A-Z])?$'),
    CONSTRAINT ck_subcodigo_no_ciclo CHECK (id_padre IS DISTINCT FROM id_subcodigo),
    CONSTRAINT fk_subcodigo_codigo FOREIGN KEY (id_codigo)
        REFERENCES paros.codigo_paro (id_codigo)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    -- El padre debe pertenecer al MISMO código (FK compuesta)
    CONSTRAINT fk_subcodigo_padre FOREIGN KEY (id_padre, id_codigo)
        REFERENCES paros.subcodigo (id_subcodigo, id_codigo)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_subcodigo_equivalente FOREIGN KEY (id_equivalente)
        REFERENCES paros.subcodigo (id_subcodigo)
        ON UPDATE CASCADE ON DELETE SET NULL
);
COMMENT ON TABLE  paros.subcodigo IS 'Subcódigos de los códigos 01, 03 y 05. Jerarquía sistema → componente en el 01.';
COMMENT ON COLUMN paros.subcodigo.id_subcodigo IS 'Identificador sustituto.';
COMMENT ON COLUMN paros.subcodigo.id_codigo IS 'Código de paro al que pertenece.';
COMMENT ON COLUMN paros.subcodigo.clave IS 'Clave normalizada: 1.2, 1.2.A, 5.11. Las claves 4.x son del catálogo antiguo del código 05.';
COMMENT ON COLUMN paros.subcodigo.descripcion IS 'Texto oficial del catálogo, o el más frecuente si solo existe en el histórico.';
COMMENT ON COLUMN paros.subcodigo.id_padre IS 'Sistema al que pertenece un componente (1.2.A → 1.2). Nulo en el primer nivel.';
COMMENT ON COLUMN paros.subcodigo.id_equivalente IS 'Para subcódigos antiguos (4.x): subcódigo vigente equivalente (5.x).';
COMMENT ON COLUMN paros.subcodigo.vigente IS 'Falso para subcódigos que solo existen en el histórico.';

CREATE TABLE paros.maquina (
    id_maquina      smallint     GENERATED ALWAYS AS IDENTITY,
    nombre          varchar(20)  NOT NULL,
    unidades_minuto numeric(6,2) NULL,
    factor_ajuste   numeric(4,3) NOT NULL DEFAULT 1,
    activa          boolean      NOT NULL DEFAULT true,
    CONSTRAINT pk_maquina PRIMARY KEY (id_maquina),
    CONSTRAINT uq_maquina_nombre UNIQUE (nombre),
    CONSTRAINT ck_maquina_velocidad CHECK (unidades_minuto IS NULL OR unidades_minuto > 0),
    CONSTRAINT ck_maquina_factor CHECK (factor_ajuste > 0 AND factor_ajuste <= 1)
);
COMMENT ON TABLE  paros.maquina IS 'Líneas de envasado (Vinilos_1 a Vinilos_4).';
COMMENT ON COLUMN paros.maquina.nombre IS 'Nombre de la línea.';
COMMENT ON COLUMN paros.maquina.unidades_minuto IS 'Velocidad nominal (unidades por minuto) según las tablas de referencias.';
COMMENT ON COLUMN paros.maquina.factor_ajuste IS 'Factor aplicado a la producción ideal en la hoja Tiempos.';
COMMENT ON COLUMN paros.maquina.activa IS 'Falso si la línea sale de operación.';

CREATE TABLE paros.turno (
    id_turno       smallint     GENERATED ALWAYS AS IDENTITY,
    nombre         varchar(30)  NOT NULL,
    hora_inicio    time         NULL,
    hora_fin       time         NULL,
    duracion_horas numeric(4,2) NULL,
    CONSTRAINT pk_turno PRIMARY KEY (id_turno),
    CONSTRAINT uq_turno_nombre UNIQUE (nombre),
    CONSTRAINT ck_turno_horas_par CHECK ((hora_inicio IS NULL) = (hora_fin IS NULL)),
    CONSTRAINT ck_turno_duracion CHECK (duracion_horas IS NULL OR (duracion_horas > 0 AND duracion_horas <= 24))
);
COMMENT ON TABLE  paros.turno IS 'Turnos de trabajo. Incluye "No registrado" para el histórico sin turno.';
COMMENT ON COLUMN paros.turno.nombre IS 'Nombre tal como se usa en planta, por ejemplo 6am-2pm (Turno 1).';
COMMENT ON COLUMN paros.turno.hora_inicio IS 'Hora de inicio del turno.';
COMMENT ON COLUMN paros.turno.hora_fin IS 'Hora de fin; puede ser menor que el inicio si el turno cruza la medianoche.';
COMMENT ON COLUMN paros.turno.duracion_horas IS 'Duración nominal. Se guarda porque no es trivial derivarla en turnos nocturnos.';

CREATE TABLE paros.paro_programado_turno (
    id_turno  smallint     NOT NULL,
    id_codigo smallint     NOT NULL,
    minutos   numeric(5,1) NOT NULL,
    CONSTRAINT pk_paro_programado_turno PRIMARY KEY (id_turno, id_codigo),
    CONSTRAINT ck_ppt_minutos CHECK (minutos > 0),
    CONSTRAINT fk_ppt_turno FOREIGN KEY (id_turno)
        REFERENCES paros.turno (id_turno) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_ppt_codigo FOREIGN KEY (id_codigo)
        REFERENCES paros.codigo_paro (id_codigo) ON UPDATE CASCADE ON DELETE RESTRICT
);
COMMENT ON TABLE  paros.paro_programado_turno IS 'Minutos estándar de los paros programados 16 y 17 según el turno (fórmulas I18 e I19 de la hoja Registro).';
COMMENT ON COLUMN paros.paro_programado_turno.minutos IS 'Minutos que se asignan automáticamente por turno.';

CREATE TABLE paros.referencia (
    id_referencia integer     GENERATED ALWAYS AS IDENTITY,
    nombre        varchar(80) NOT NULL,
    CONSTRAINT pk_referencia PRIMARY KEY (id_referencia),
    CONSTRAINT uq_referencia_nombre UNIQUE (nombre)
);
COMMENT ON TABLE  paros.referencia IS 'Producto envasado, por ejemplo Parchesitos 22cc (6 col).';
COMMENT ON COLUMN paros.referencia.nombre IS 'Nombre comercial de la referencia.';

CREATE TABLE paros.maquina_referencia (
    id_maquina          smallint NOT NULL,
    id_referencia       integer  NOT NULL,
    num_colores         smallint NULL,
    unidades_por_display smallint NULL,
    displays_por_paca   smallint NULL,
    en_catalogo         boolean  NOT NULL DEFAULT true,
    CONSTRAINT pk_maquina_referencia PRIMARY KEY (id_maquina, id_referencia),
    CONSTRAINT ck_mr_valores CHECK (
        (num_colores IS NULL OR num_colores > 0) AND
        (unidades_por_display IS NULL OR unidades_por_display > 0) AND
        (displays_por_paca IS NULL OR displays_por_paca > 0)),
    CONSTRAINT fk_mr_maquina FOREIGN KEY (id_maquina)
        REFERENCES paros.maquina (id_maquina) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_mr_referencia FOREIGN KEY (id_referencia)
        REFERENCES paros.referencia (id_referencia) ON UPDATE CASCADE ON DELETE CASCADE
);
COMMENT ON TABLE  paros.maquina_referencia IS 'Qué referencias puede envasar cada máquina y con qué parámetros (antes, tablas Tabla8/14/15/16).';
COMMENT ON COLUMN paros.maquina_referencia.num_colores IS 'Número de colores del estuche.';
COMMENT ON COLUMN paros.maquina_referencia.unidades_por_display IS 'Unidades (frascos) por display.';
COMMENT ON COLUMN paros.maquina_referencia.displays_por_paca IS 'Displays por paca. Unidades por paca = colores × unidades por display × displays (se calcula, no se guarda).';
COMMENT ON COLUMN paros.maquina_referencia.en_catalogo IS 'Falso si la combinación solo aparece en el histórico y no en el catálogo vigente.';

CREATE TABLE paros.persona (
    id_persona integer     GENERATED ALWAYS AS IDENTITY,
    codigo     varchar(10) NOT NULL,
    rol        char(3)     NOT NULL,
    activo     boolean     NOT NULL DEFAULT true,
    CONSTRAINT pk_persona PRIMARY KEY (id_persona),
    CONSTRAINT uq_persona_codigo UNIQUE (codigo),
    CONSTRAINT ck_persona_rol CHECK (rol IN ('OPE', 'MTO', 'OTR')),
    CONSTRAINT ck_persona_codigo CHECK (codigo ~ '^(OPE|MTO|OTR)-[0-9]{3}$' AND left(codigo, 3) = rol)
);
COMMENT ON TABLE  paros.persona IS 'Personas que operan o atienden paros, identificadas con un seudónimo. El nombre vive en privado.persona_identidad.';
COMMENT ON COLUMN paros.persona.codigo IS 'Seudónimo estable: OPE-001 operaria, MTO-001 mantenimiento, OTR-001 otra área.';
COMMENT ON COLUMN paros.persona.rol IS 'OPE operaria, MTO personal de mantenimiento, OTR otra área.';
COMMENT ON COLUMN paros.persona.activo IS 'Falso cuando la persona se retira; nunca se borra si tiene registros.';

CREATE TABLE privado.persona_identidad (
    id_persona      integer      NOT NULL,
    nombre_completo varchar(120) NOT NULL,
    CONSTRAINT pk_persona_identidad PRIMARY KEY (id_persona),
    CONSTRAINT fk_persona_identidad FOREIGN KEY (id_persona)
        REFERENCES paros.persona (id_persona) ON UPDATE CASCADE ON DELETE CASCADE
);
COMMENT ON TABLE  privado.persona_identidad IS 'Nombre real de cada persona. Relación 1:1 con paros.persona, separada por seguridad.';
COMMENT ON COLUMN privado.persona_identidad.nombre_completo IS 'Nombre como figura en el Excel (o el canónico si había variantes).';

CREATE TABLE paros.area_agente (
    id_area_agente smallint    GENERATED ALWAYS AS IDENTITY,
    nombre         varchar(40) NOT NULL,
    CONSTRAINT pk_area_agente PRIMARY KEY (id_area_agente),
    CONSTRAINT uq_area_agente_nombre UNIQUE (nombre)
);
COMMENT ON TABLE  paros.area_agente IS 'Área que atendió un ajuste operativo (código 05): operarios, mantenimiento, calidad...';
COMMENT ON COLUMN paros.area_agente.nombre IS 'Nombre del área sin guiones bajos.';

CREATE TABLE paros.tipo_paro (
    id_tipo_paro smallint     GENERATED ALWAYS AS IDENTITY,
    descripcion  varchar(100) NOT NULL,
    catalogo     varchar(8)   NOT NULL DEFAULT 'VIGENTE',
    id_codigo    smallint     NULL,
    CONSTRAINT pk_tipo_paro PRIMARY KEY (id_tipo_paro),
    CONSTRAINT uq_tipo_paro_descripcion UNIQUE (descripcion),
    CONSTRAINT ck_tipo_paro_catalogo CHECK (catalogo IN ('VIGENTE', 'ANTIGUO')),
    CONSTRAINT fk_tipo_paro_codigo FOREIGN KEY (id_codigo)
        REFERENCES paros.codigo_paro (id_codigo) ON UPDATE CASCADE ON DELETE SET NULL
);
COMMENT ON TABLE  paros.tipo_paro IS 'Motivo de las horas no trabajadas de un turno. Conserva el catálogo antiguo (2022-2023) y lo enlaza al código vigente cuando la equivalencia es clara.';
COMMENT ON COLUMN paros.tipo_paro.descripcion IS 'Texto del tipo de paro tal como se usó.';
COMMENT ON COLUMN paros.tipo_paro.catalogo IS 'VIGENTE (formato [NN]) o ANTIGUO (numeración anterior).';
COMMENT ON COLUMN paros.tipo_paro.id_codigo IS 'Código de paro equivalente. Nulo si no hay equivalencia clara.';

CREATE TABLE paros.causa_paro (
    id_causa    smallint     GENERATED ALWAYS AS IDENTITY,
    descripcion varchar(150) NOT NULL,
    CONSTRAINT pk_causa_paro PRIMARY KEY (id_causa),
    CONSTRAINT uq_causa_paro_descripcion UNIQUE (descripcion)
);
COMMENT ON TABLE  paros.causa_paro IS 'Causa detallada de las horas no trabajadas (lista "los porqué" del Excel), sin duplicados por mayúsculas.';

-- ---------------------------------------------------------------------
-- HECHOS
-- ---------------------------------------------------------------------

CREATE TABLE paros.registro_turno (
    id_registro         bigint       GENERATED ALWAYS AS IDENTITY,
    fecha               date         NOT NULL,
    id_maquina          smallint     NOT NULL,
    id_turno            smallint     NOT NULL,
    id_operaria         integer      NULL,
    id_referencia       integer      NULL,
    parte               smallint     NOT NULL DEFAULT 1,
    pacas_producidas    integer      NULL,
    horas_trabajadas    numeric(5,2) NOT NULL DEFAULT 0,
    horas_no_trabajadas numeric(5,2) NOT NULL DEFAULT 0,
    meta_por_hora       integer      NULL,
    id_tipo_paro        smallint     NULL,
    id_causa            smallint     NULL,
    observaciones       text         NULL,
    requiere_revision   boolean      NOT NULL DEFAULT false,
    fila_excel          integer      NULL,
    registrado_en       timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_registro_turno PRIMARY KEY (id_registro),
    CONSTRAINT uq_registro_turno_natural UNIQUE NULLS NOT DISTINCT
        (fecha, id_maquina, id_turno, id_operaria, id_referencia, parte),
    CONSTRAINT uq_registro_turno_fila UNIQUE (fila_excel),
    CONSTRAINT ck_rt_fecha CHECK (fecha >= DATE '2020-01-01'),
    CONSTRAINT ck_rt_parte CHECK (parte BETWEEN 1 AND 20),
    CONSTRAINT ck_rt_pacas CHECK (pacas_producidas IS NULL OR pacas_producidas >= 0),
    CONSTRAINT ck_rt_horas_trab CHECK (horas_trabajadas BETWEEN 0 AND 24),
    CONSTRAINT ck_rt_horas_no_trab CHECK (horas_no_trabajadas >= 0),
    CONSTRAINT ck_rt_meta CHECK (meta_por_hora IS NULL OR meta_por_hora > 0),
    CONSTRAINT fk_rt_maquina FOREIGN KEY (id_maquina)
        REFERENCES paros.maquina (id_maquina) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_rt_turno FOREIGN KEY (id_turno)
        REFERENCES paros.turno (id_turno) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_rt_operaria FOREIGN KEY (id_operaria)
        REFERENCES paros.persona (id_persona) ON UPDATE CASCADE ON DELETE RESTRICT,
    -- La referencia debe estar habilitada para esa máquina (regla RN-05)
    CONSTRAINT fk_rt_maquina_referencia FOREIGN KEY (id_maquina, id_referencia)
        REFERENCES paros.maquina_referencia (id_maquina, id_referencia)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_rt_tipo_paro FOREIGN KEY (id_tipo_paro)
        REFERENCES paros.tipo_paro (id_tipo_paro) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_rt_causa FOREIGN KEY (id_causa)
        REFERENCES paros.causa_paro (id_causa) ON UPDATE CASCADE ON DELETE RESTRICT
);
COMMENT ON TABLE  paros.registro_turno IS 'Un turno de una máquina con una operaria y una referencia: lo que producía y cuánto tiempo trabajó.';
COMMENT ON COLUMN paros.registro_turno.id_registro IS 'Identificador sustituto.';
COMMENT ON COLUMN paros.registro_turno.fecha IS 'Día del turno. Mes y año se derivan; no se guardan.';
COMMENT ON COLUMN paros.registro_turno.id_maquina IS 'Línea de envasado.';
COMMENT ON COLUMN paros.registro_turno.id_turno IS 'Turno; "No registrado" en el histórico sin dato.';
COMMENT ON COLUMN paros.registro_turno.id_operaria IS 'Operaria (seudónimo). Nulo en días sin producción.';
COMMENT ON COLUMN paros.registro_turno.id_referencia IS 'Referencia envasada. Nula en días sin producción.';
COMMENT ON COLUMN paros.registro_turno.parte IS 'Número de parte cuando el mismo turno, operaria y referencia se registró en varias filas.';
COMMENT ON COLUMN paros.registro_turno.pacas_producidas IS 'Pacas producidas en el turno.';
COMMENT ON COLUMN paros.registro_turno.horas_trabajadas IS 'Horas programadas y trabajadas. Base del % de productividad.';
COMMENT ON COLUMN paros.registro_turno.horas_no_trabajadas IS 'Horas sin producción programada (fin de semana, sin demanda, etc.).';
COMMENT ON COLUMN paros.registro_turno.meta_por_hora IS 'Meta de unidades por hora. El Excel la pedía y no la guardaba; queda para capturas nuevas.';
COMMENT ON COLUMN paros.registro_turno.id_tipo_paro IS 'Motivo de las horas no trabajadas.';
COMMENT ON COLUMN paros.registro_turno.id_causa IS 'Causa detallada de las horas no trabajadas.';
COMMENT ON COLUMN paros.registro_turno.observaciones IS 'Texto libre de la operaria o mantenimiento.';
COMMENT ON COLUMN paros.registro_turno.requiere_revision IS 'Marcado en la migración cuando el dato luce anómalo (pacas atípicas, horas > 24, paro > horas).';
COMMENT ON COLUMN paros.registro_turno.fila_excel IS 'Fila de origen en T_baseDeDatos (trazabilidad). Nulo en capturas nuevas.';
COMMENT ON COLUMN paros.registro_turno.registrado_en IS 'Momento en que se grabó el registro en la base.';

-- La regla "un día tiene 24 horas" (ck_rt_dia_24h) se agrega al final de
-- 08_transformacion.sql con NOT VALID: ver la explicación allí.

CREATE TABLE paros.paro (
    id_paro            bigint       GENERATED ALWAYS AS IDENTITY,
    id_registro        bigint       NOT NULL,
    id_codigo          smallint     NOT NULL,
    id_subcodigo       integer      NULL,
    minutos            numeric(7,2) NOT NULL,
    id_area_agente     smallint     NULL,
    id_persona_atiende integer      NULL,
    fila_excel         integer      NULL,
    CONSTRAINT pk_paro PRIMARY KEY (id_paro),
    CONSTRAINT ck_paro_minutos CHECK (minutos > 0 AND minutos <= 1440),
    -- Área y persona que atienden solo tienen sentido en el ajuste operativo (05)
    CONSTRAINT ck_paro_atiende_solo_05 CHECK (id_codigo = 5 OR (id_area_agente IS NULL AND id_persona_atiende IS NULL)),
    CONSTRAINT fk_paro_registro FOREIGN KEY (id_registro)
        REFERENCES paros.registro_turno (id_registro) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_paro_codigo FOREIGN KEY (id_codigo)
        REFERENCES paros.codigo_paro (id_codigo) ON UPDATE CASCADE ON DELETE RESTRICT,
    -- El subcódigo debe ser del MISMO código del paro (FK compuesta)
    CONSTRAINT fk_paro_subcodigo FOREIGN KEY (id_subcodigo, id_codigo)
        REFERENCES paros.subcodigo (id_subcodigo, id_codigo) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_paro_area_agente FOREIGN KEY (id_area_agente)
        REFERENCES paros.area_agente (id_area_agente) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_paro_persona FOREIGN KEY (id_persona_atiende)
        REFERENCES paros.persona (id_persona) ON UPDATE CASCADE ON DELETE RESTRICT
);
COMMENT ON TABLE  paros.paro IS 'Cada paro de un turno: código, subcódigo y minutos. Reemplaza los 18 pares de columnas del Excel.';
COMMENT ON COLUMN paros.paro.id_paro IS 'Identificador sustituto.';
COMMENT ON COLUMN paros.paro.id_registro IS 'Turno en el que ocurrió el paro.';
COMMENT ON COLUMN paros.paro.id_codigo IS 'Código de paro (01 a 18).';
COMMENT ON COLUMN paros.paro.id_subcodigo IS 'Subcódigo; obligatorio para 01, 03 y 05 en capturas nuevas.';
COMMENT ON COLUMN paros.paro.minutos IS 'Duración en minutos. Las horas se derivan (minutos / 60).';
COMMENT ON COLUMN paros.paro.id_area_agente IS 'Solo código 05: área que atendió el ajuste.';
COMMENT ON COLUMN paros.paro.id_persona_atiende IS 'Solo código 05: persona que atendió el ajuste.';
COMMENT ON COLUMN paros.paro.fila_excel IS 'Fila de origen en el Excel (trazabilidad).';

-- ---------------------------------------------------------------------
-- STAGING (copia fiel del Excel, una fila por fila de T_baseDeDatos)
-- ---------------------------------------------------------------------

CREATE TABLE stg.base_excel (
    fila_excel     integer PRIMARY KEY,
    fecha          date,
    mes_texto      varchar(15),
    anio_texto     varchar(4),
    maquina        varchar(40),
    operario       varchar(15),     -- ya seudonimizado (OPE-001)
    referencia     varchar(80),
    turno          varchar(30),
    pacas          integer,
    horas_trab     numeric(6,2),
    horas_no_trab  numeric(6,2),
    tipo_paro      varchar(100),
    causa          varchar(150),
    sub1           varchar(10),     -- clave normalizada (1.2.A)
    sub3           varchar(10),
    sub5           varchar(10),
    area5          varchar(40),
    personal5      varchar(15),     -- seudónimo
    tiempo_paro_h  numeric(10,6),   -- columna calculada del Excel, solo para control
    observaciones  text,
    m1 numeric(7,2), m2 numeric(7,2), m3 numeric(7,2), m4 numeric(7,2), m5 numeric(7,2), m6 numeric(7,2),
    m7 numeric(7,2), m8 numeric(7,2), m9 numeric(7,2), m10 numeric(7,2), m11 numeric(7,2), m12 numeric(7,2),
    m13 numeric(7,2), m14 numeric(7,2), m15 numeric(7,2), m16 numeric(7,2), m17 numeric(7,2), m18 numeric(7,2)
);
COMMENT ON TABLE stg.base_excel IS 'Copia de T_baseDeDatos con textos limpios (espacios, "No aplica" → nulo) y personas seudonimizadas. m1..m18 = minutos por código.';

CREATE TABLE stg.control_excel (
    metrica varchar(60) PRIMARY KEY,
    valor   numeric(14,4) NOT NULL
);
COMMENT ON TABLE stg.control_excel IS 'Totales de control calculados por el ETL directamente sobre el Excel, antes de cualquier limpieza.';

CREATE TABLE stg.rechazo (
    fila_excel integer NOT NULL,
    motivo     varchar(200) NOT NULL,
    CONSTRAINT pk_rechazo PRIMARY KEY (fila_excel, motivo)
);
COMMENT ON TABLE stg.rechazo IS 'Filas del Excel que no se cargaron, con el motivo. Ninguna fila se pierde sin explicación.';
