# Diccionario de datos

Generado automáticamente desde el catálogo de PostgreSQL con `scripts/diccionario.sql`. Si cambia el esquema, se vuelve a generar; no se edita a mano.

Convenciones: **Nulo** = admite NULL. **IDENTITY** = número autogenerado. Las FK indican la tabla referenciada y sus políticas ON DELETE / ON UPDATE.


## paros.registro_turno

Un turno de una máquina con una operaria y una referencia: lo que producía y cuánto tiempo trabajó.

| Columna | Tipo | Nulo | Default | Restricciones | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id_registro` | bigint | NO | IDENTITY | PK | Identificador sustituto. |
| `fecha` | date | NO |  | CHECK ck_rt_fecha; UNIQUE uq_registro_turno_natural | Día del turno. Mes y año se derivan; no se guardan. |
| `id_maquina` | smallint | NO |  | FK → paros.maquina (DEL RESTRICT, UPD CASCADE); FK → paros.maquina_referencia (DEL RESTRICT, UPD CASCADE); UNIQUE uq_registro_turno_natural | Línea de envasado. |
| `id_turno` | smallint | NO |  | FK → paros.turno (DEL RESTRICT, UPD CASCADE); UNIQUE uq_registro_turno_natural | Turno; "No registrado" en el histórico sin dato. |
| `id_operaria` | integer | SÍ |  | FK → paros.persona (DEL RESTRICT, UPD CASCADE); UNIQUE uq_registro_turno_natural | Operaria (seudónimo). Nulo en días sin producción. |
| `id_referencia` | integer | SÍ |  | FK → paros.maquina_referencia (DEL RESTRICT, UPD CASCADE); UNIQUE uq_registro_turno_natural | Referencia envasada. Nula en días sin producción. |
| `parte` | smallint | NO | 1 | CHECK ck_rt_parte; UNIQUE uq_registro_turno_natural | Número de parte cuando el mismo turno, operaria y referencia se registró en varias filas. |
| `pacas_producidas` | integer | SÍ |  | CHECK ck_rt_pacas | Pacas producidas en el turno. |
| `horas_trabajadas` | numeric(5,2) | NO | 0 | CHECK ck_rt_horas_trab; CHECK ck_rt_dia_24h | Horas programadas y trabajadas. Base del % de productividad. |
| `horas_no_trabajadas` | numeric(5,2) | NO | 0 | CHECK ck_rt_horas_no_trab; CHECK ck_rt_dia_24h | Horas sin producción programada (fin de semana, sin demanda, etc.). |
| `meta_por_hora` | integer | SÍ |  | CHECK ck_rt_meta | Meta de unidades por hora. El Excel la pedía y no la guardaba; queda para capturas nuevas. |
| `id_tipo_paro` | smallint | SÍ |  | FK → paros.tipo_paro (DEL RESTRICT, UPD CASCADE) | Motivo de las horas no trabajadas. |
| `id_causa` | smallint | SÍ |  | FK → paros.causa_paro (DEL RESTRICT, UPD CASCADE) | Causa detallada de las horas no trabajadas. |
| `observaciones` | text | SÍ |  |  | Texto libre de la operaria o mantenimiento. |
| `requiere_revision` | boolean | NO | false |  | Marcado en la migración cuando el dato luce anómalo (pacas atípicas, horas > 24, paro > horas). |
| `fila_excel` | integer | SÍ |  | UNIQUE uq_registro_turno_fila | Fila de origen en T_baseDeDatos (trazabilidad). Nulo en capturas nuevas. |
| `registrado_en` | timestamp with time zone | NO | now() |  | Momento en que se grabó el registro en la base. |

**Restricciones de la tabla:**

- `ck_rt_dia_24h`: `CHECK (((horas_trabajadas + horas_no_trabajadas) <= (24)::numeric)) NOT VALID`
- `ck_rt_fecha`: `CHECK ((fecha >= '2020-01-01'::date))`
- `ck_rt_horas_no_trab`: `CHECK ((horas_no_trabajadas >= (0)::numeric))`
- `ck_rt_horas_trab`: `CHECK (((horas_trabajadas >= (0)::numeric) AND (horas_trabajadas <= (24)::numeric)))`
- `ck_rt_meta`: `CHECK (((meta_por_hora IS NULL) OR (meta_por_hora > 0)))`
- `ck_rt_pacas`: `CHECK (((pacas_producidas IS NULL) OR (pacas_producidas >= 0)))`
- `ck_rt_parte`: `CHECK (((parte >= 1) AND (parte <= 20)))`
- `fk_rt_causa`: `FOREIGN KEY (id_causa) REFERENCES paros.causa_paro(id_causa) ON UPDATE CASCADE ON DELETE RESTRICT`
- `fk_rt_maquina`: `FOREIGN KEY (id_maquina) REFERENCES paros.maquina(id_maquina) ON UPDATE CASCADE ON DELETE RESTRICT`
- `fk_rt_maquina_referencia`: `FOREIGN KEY (id_maquina, id_referencia) REFERENCES paros.maquina_referencia(id_maquina, id_referencia) ON UPDATE CASCADE ON DELETE RESTRICT`
- `fk_rt_operaria`: `FOREIGN KEY (id_operaria) REFERENCES paros.persona(id_persona) ON UPDATE CASCADE ON DELETE RESTRICT`
- `fk_rt_tipo_paro`: `FOREIGN KEY (id_tipo_paro) REFERENCES paros.tipo_paro(id_tipo_paro) ON UPDATE CASCADE ON DELETE RESTRICT`
- `fk_rt_turno`: `FOREIGN KEY (id_turno) REFERENCES paros.turno(id_turno) ON UPDATE CASCADE ON DELETE RESTRICT`
- `pk_registro_turno`: `PRIMARY KEY (id_registro)`
- `uq_registro_turno_fila`: `UNIQUE (fila_excel)`
- `uq_registro_turno_natural`: `UNIQUE NULLS NOT DISTINCT (fecha, id_maquina, id_turno, id_operaria, id_referencia, parte)`

## paros.paro

Cada paro de un turno: código, subcódigo y minutos. Reemplaza los 18 pares de columnas del Excel.

| Columna | Tipo | Nulo | Default | Restricciones | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id_paro` | bigint | NO | IDENTITY | PK | Identificador sustituto. |
| `id_registro` | bigint | NO |  | FK → paros.registro_turno (DEL CASCADE, UPD CASCADE) | Turno en el que ocurrió el paro. |
| `id_codigo` | smallint | NO |  | CHECK ck_paro_atiende_solo_05; FK → paros.codigo_paro (DEL RESTRICT, UPD CASCADE); FK → paros.subcodigo (DEL RESTRICT, UPD CASCADE) | Código de paro (01 a 18). |
| `id_subcodigo` | integer | SÍ |  | FK → paros.subcodigo (DEL RESTRICT, UPD CASCADE) | Subcódigo; obligatorio para 01, 03 y 05 en capturas nuevas. |
| `minutos` | numeric(7,2) | NO |  | CHECK ck_paro_minutos | Duración en minutos. Las horas se derivan (minutos / 60). |
| `id_area_agente` | smallint | SÍ |  | CHECK ck_paro_atiende_solo_05; FK → paros.area_agente (DEL RESTRICT, UPD CASCADE) | Solo código 05: área que atendió el ajuste. |
| `id_persona_atiende` | integer | SÍ |  | CHECK ck_paro_atiende_solo_05; FK → paros.persona (DEL RESTRICT, UPD CASCADE) | Solo código 05: persona que atendió el ajuste. |
| `fila_excel` | integer | SÍ |  |  | Fila de origen en el Excel (trazabilidad). |

**Restricciones de la tabla:**

- `ck_paro_atiende_solo_05`: `CHECK (((id_codigo = 5) OR ((id_area_agente IS NULL) AND (id_persona_atiende IS NULL))))`
- `ck_paro_minutos`: `CHECK (((minutos > (0)::numeric) AND (minutos <= (1440)::numeric)))`
- `fk_paro_area_agente`: `FOREIGN KEY (id_area_agente) REFERENCES paros.area_agente(id_area_agente) ON UPDATE CASCADE ON DELETE RESTRICT`
- `fk_paro_codigo`: `FOREIGN KEY (id_codigo) REFERENCES paros.codigo_paro(id_codigo) ON UPDATE CASCADE ON DELETE RESTRICT`
- `fk_paro_persona`: `FOREIGN KEY (id_persona_atiende) REFERENCES paros.persona(id_persona) ON UPDATE CASCADE ON DELETE RESTRICT`
- `fk_paro_registro`: `FOREIGN KEY (id_registro) REFERENCES paros.registro_turno(id_registro) ON UPDATE CASCADE ON DELETE CASCADE`
- `fk_paro_subcodigo`: `FOREIGN KEY (id_subcodigo, id_codigo) REFERENCES paros.subcodigo(id_subcodigo, id_codigo) ON UPDATE CASCADE ON DELETE RESTRICT`
- `pk_paro`: `PRIMARY KEY (id_paro)`

## paros.area_agente

Área que atendió un ajuste operativo (código 05): operarios, mantenimiento, calidad...

| Columna | Tipo | Nulo | Default | Restricciones | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id_area_agente` | smallint | NO | IDENTITY | PK |  |
| `nombre` | character varying(40) | NO |  | UNIQUE uq_area_agente_nombre | Nombre del área sin guiones bajos. |

**Restricciones de la tabla:**

- `pk_area_agente`: `PRIMARY KEY (id_area_agente)`
- `uq_area_agente_nombre`: `UNIQUE (nombre)`

## paros.area_impacto

Área de la empresa responsable de un código de paro (Mantenimiento, Producción, Calidad...).

| Columna | Tipo | Nulo | Default | Restricciones | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id_area` | smallint | NO | IDENTITY | PK | Identificador sustituto del área. |
| `nombre` | character varying(40) | NO |  | CHECK ck_area_impacto_nombre; UNIQUE uq_area_impacto_nombre | Nombre del área tal como aparece en la tabla de códigos del Excel. |

**Restricciones de la tabla:**

- `ck_area_impacto_nombre`: `CHECK ((btrim((nombre)::text) <> ''::text))`
- `pk_area_impacto`: `PRIMARY KEY (id_area)`
- `uq_area_impacto_nombre`: `UNIQUE (nombre)`

## paros.causa_paro

Causa detallada de las horas no trabajadas (lista "los porqué" del Excel), sin duplicados por mayúsculas.

| Columna | Tipo | Nulo | Default | Restricciones | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id_causa` | smallint | NO | IDENTITY | PK |  |
| `descripcion` | character varying(150) | NO |  | UNIQUE uq_causa_paro_descripcion |  |

**Restricciones de la tabla:**

- `pk_causa_paro`: `PRIMARY KEY (id_causa)`
- `uq_causa_paro_descripcion`: `UNIQUE (descripcion)`

## paros.codigo_paro

Catálogo oficial de códigos de paro del P-MTO-22 ([01] a [18]).

| Columna | Tipo | Nulo | Default | Restricciones | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id_codigo` | smallint | NO |  | CHECK ck_codigo_paro_rango; PK | Número del código. Clave natural: es como lo conoce la planta. |
| `nombre` | character varying(120) | NO |  | UNIQUE uq_codigo_paro_nombre | Descripción del código sin el prefijo [NN]. |
| `id_area` | smallint | NO |  | FK → paros.area_impacto (DEL RESTRICT, UPD CASCADE) | Área de impacto a la que se carga el paro. |
| `requiere_subcodigo` | boolean | NO | false |  | Verdadero para 01, 03 y 05: un paro nuevo de estos códigos debe traer subcódigo. |
| `activo` | boolean | NO | true |  | Falso si el código deja de usarse; no se borra para no perder el histórico. |

**Restricciones de la tabla:**

- `ck_codigo_paro_rango`: `CHECK (((id_codigo >= 1) AND (id_codigo <= 99)))`
- `fk_codigo_paro_area`: `FOREIGN KEY (id_area) REFERENCES paros.area_impacto(id_area) ON UPDATE CASCADE ON DELETE RESTRICT`
- `pk_codigo_paro`: `PRIMARY KEY (id_codigo)`
- `uq_codigo_paro_nombre`: `UNIQUE (nombre)`

## paros.maquina

Líneas de envasado (Vinilos_1 a Vinilos_4).

| Columna | Tipo | Nulo | Default | Restricciones | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id_maquina` | smallint | NO | IDENTITY | PK |  |
| `nombre` | character varying(20) | NO |  | UNIQUE uq_maquina_nombre | Nombre de la línea. |
| `unidades_minuto` | numeric(6,2) | SÍ |  | CHECK ck_maquina_velocidad | Velocidad nominal (unidades por minuto) según las tablas de referencias. |
| `factor_ajuste` | numeric(4,3) | NO | 1 | CHECK ck_maquina_factor | Factor aplicado a la producción ideal en la hoja Tiempos. |
| `activa` | boolean | NO | true |  | Falso si la línea sale de operación. |

**Restricciones de la tabla:**

- `ck_maquina_factor`: `CHECK (((factor_ajuste > (0)::numeric) AND (factor_ajuste <= (1)::numeric)))`
- `ck_maquina_velocidad`: `CHECK (((unidades_minuto IS NULL) OR (unidades_minuto > (0)::numeric)))`
- `pk_maquina`: `PRIMARY KEY (id_maquina)`
- `uq_maquina_nombre`: `UNIQUE (nombre)`

## paros.maquina_referencia

Qué referencias puede envasar cada máquina y con qué parámetros (antes, tablas Tabla8/14/15/16).

| Columna | Tipo | Nulo | Default | Restricciones | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id_maquina` | smallint | NO |  | FK → paros.maquina (DEL CASCADE, UPD CASCADE); PK |  |
| `id_referencia` | integer | NO |  | FK → paros.referencia (DEL CASCADE, UPD CASCADE); PK |  |
| `num_colores` | smallint | SÍ |  | CHECK ck_mr_valores | Número de colores del estuche. |
| `unidades_por_display` | smallint | SÍ |  | CHECK ck_mr_valores | Unidades (frascos) por display. |
| `displays_por_paca` | smallint | SÍ |  | CHECK ck_mr_valores | Displays por paca. Unidades por paca = colores × unidades por display × displays (se calcula, no se guarda). |
| `en_catalogo` | boolean | NO | true |  | Falso si la combinación solo aparece en el histórico y no en el catálogo vigente. |

**Restricciones de la tabla:**

- `ck_mr_valores`: `CHECK ((((num_colores IS NULL) OR (num_colores > 0)) AND ((unidades_por_display IS NULL) OR (unidades_por_display > 0)) AND ((displays_por_paca IS NULL) OR (displays_por_paca > 0))))`
- `fk_mr_maquina`: `FOREIGN KEY (id_maquina) REFERENCES paros.maquina(id_maquina) ON UPDATE CASCADE ON DELETE CASCADE`
- `fk_mr_referencia`: `FOREIGN KEY (id_referencia) REFERENCES paros.referencia(id_referencia) ON UPDATE CASCADE ON DELETE CASCADE`
- `pk_maquina_referencia`: `PRIMARY KEY (id_maquina, id_referencia)`

## paros.paro_programado_turno

Minutos estándar de los paros programados 16 y 17 según el turno (fórmulas I18 e I19 de la hoja Registro).

| Columna | Tipo | Nulo | Default | Restricciones | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id_turno` | smallint | NO |  | FK → paros.turno (DEL CASCADE, UPD CASCADE); PK |  |
| `id_codigo` | smallint | NO |  | FK → paros.codigo_paro (DEL RESTRICT, UPD CASCADE); PK |  |
| `minutos` | numeric(5,1) | NO |  | CHECK ck_ppt_minutos | Minutos que se asignan automáticamente por turno. |

**Restricciones de la tabla:**

- `ck_ppt_minutos`: `CHECK ((minutos > (0)::numeric))`
- `fk_ppt_codigo`: `FOREIGN KEY (id_codigo) REFERENCES paros.codigo_paro(id_codigo) ON UPDATE CASCADE ON DELETE RESTRICT`
- `fk_ppt_turno`: `FOREIGN KEY (id_turno) REFERENCES paros.turno(id_turno) ON UPDATE CASCADE ON DELETE CASCADE`
- `pk_paro_programado_turno`: `PRIMARY KEY (id_turno, id_codigo)`

## paros.persona

Personas que operan o atienden paros, identificadas con un seudónimo. El nombre vive en privado.persona_identidad.

| Columna | Tipo | Nulo | Default | Restricciones | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id_persona` | integer | NO | IDENTITY | PK |  |
| `codigo` | character varying(10) | NO |  | CHECK ck_persona_codigo; UNIQUE uq_persona_codigo | Seudónimo estable: OPE-001 operaria, MTO-001 mantenimiento, OTR-001 otra área. |
| `rol` | character(3) | NO |  | CHECK ck_persona_rol; CHECK ck_persona_codigo | OPE operaria, MTO personal de mantenimiento, OTR otra área. |
| `activo` | boolean | NO | true |  | Falso cuando la persona se retira; nunca se borra si tiene registros. |

**Restricciones de la tabla:**

- `ck_persona_codigo`: `CHECK ((((codigo)::text ~ '^(OPE\|MTO\|OTR)-[0-9]{3}$'::text) AND ("left"((codigo)::text, 3) = (rol)::text)))`
- `ck_persona_rol`: `CHECK ((rol = ANY (ARRAY['OPE'::bpchar, 'MTO'::bpchar, 'OTR'::bpchar])))`
- `pk_persona`: `PRIMARY KEY (id_persona)`
- `uq_persona_codigo`: `UNIQUE (codigo)`

## paros.referencia

Producto envasado, por ejemplo Parchesitos 22cc (6 col).

| Columna | Tipo | Nulo | Default | Restricciones | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id_referencia` | integer | NO | IDENTITY | PK |  |
| `nombre` | character varying(80) | NO |  | UNIQUE uq_referencia_nombre | Nombre comercial de la referencia. |

**Restricciones de la tabla:**

- `pk_referencia`: `PRIMARY KEY (id_referencia)`
- `uq_referencia_nombre`: `UNIQUE (nombre)`

## paros.subcodigo

Subcódigos de los códigos 01, 03 y 05. Jerarquía sistema → componente en el 01.

| Columna | Tipo | Nulo | Default | Restricciones | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id_subcodigo` | integer | NO | IDENTITY | CHECK ck_subcodigo_no_ciclo; PK; UNIQUE uq_subcodigo_par | Identificador sustituto. |
| `id_codigo` | smallint | NO |  | FK → paros.codigo_paro (DEL RESTRICT, UPD CASCADE); FK → paros.subcodigo (DEL RESTRICT, UPD CASCADE); UNIQUE uq_subcodigo_clave; UNIQUE uq_subcodigo_par | Código de paro al que pertenece. |
| `clave` | character varying(10) | NO |  | CHECK ck_subcodigo_clave; UNIQUE uq_subcodigo_clave | Clave normalizada: 1.2, 1.2.A, 5.11. Las claves 4.x son del catálogo antiguo del código 05. |
| `descripcion` | character varying(120) | NO |  |  | Texto oficial del catálogo, o el más frecuente si solo existe en el histórico. |
| `id_padre` | integer | SÍ |  | CHECK ck_subcodigo_no_ciclo; FK → paros.subcodigo (DEL RESTRICT, UPD CASCADE) | Sistema al que pertenece un componente (1.2.A → 1.2). Nulo en el primer nivel. |
| `id_equivalente` | integer | SÍ |  | FK → paros.subcodigo (DEL SET NULL, UPD CASCADE) | Para subcódigos antiguos (4.x): subcódigo vigente equivalente (5.x). |
| `vigente` | boolean | NO | true |  | Falso para subcódigos que solo existen en el histórico. |

**Restricciones de la tabla:**

- `ck_subcodigo_clave`: `CHECK (((clave)::text ~ '^[0-9]{1,2}\.[0-9]{1,2}(\.[A-Z])?$'::text))`
- `ck_subcodigo_no_ciclo`: `CHECK ((id_padre IS DISTINCT FROM id_subcodigo))`
- `fk_subcodigo_codigo`: `FOREIGN KEY (id_codigo) REFERENCES paros.codigo_paro(id_codigo) ON UPDATE CASCADE ON DELETE RESTRICT`
- `fk_subcodigo_equivalente`: `FOREIGN KEY (id_equivalente) REFERENCES paros.subcodigo(id_subcodigo) ON UPDATE CASCADE ON DELETE SET NULL`
- `fk_subcodigo_padre`: `FOREIGN KEY (id_padre, id_codigo) REFERENCES paros.subcodigo(id_subcodigo, id_codigo) ON UPDATE CASCADE ON DELETE RESTRICT`
- `pk_subcodigo`: `PRIMARY KEY (id_subcodigo)`
- `uq_subcodigo_clave`: `UNIQUE (id_codigo, clave)`
- `uq_subcodigo_par`: `UNIQUE (id_subcodigo, id_codigo)`

## paros.tipo_paro

Motivo de las horas no trabajadas de un turno. Conserva el catálogo antiguo (2022-2023) y lo enlaza al código vigente cuando la equivalencia es clara.

| Columna | Tipo | Nulo | Default | Restricciones | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id_tipo_paro` | smallint | NO | IDENTITY | PK |  |
| `descripcion` | character varying(100) | NO |  | UNIQUE uq_tipo_paro_descripcion | Texto del tipo de paro tal como se usó. |
| `catalogo` | character varying(8) | NO | 'VIGENTE'::character varying | CHECK ck_tipo_paro_catalogo | VIGENTE (formato [NN]) o ANTIGUO (numeración anterior). |
| `id_codigo` | smallint | SÍ |  | FK → paros.codigo_paro (DEL SET NULL, UPD CASCADE) | Código de paro equivalente. Nulo si no hay equivalencia clara. |

**Restricciones de la tabla:**

- `ck_tipo_paro_catalogo`: `CHECK (((catalogo)::text = ANY ((ARRAY['VIGENTE'::character varying, 'ANTIGUO'::character varying])::text[])))`
- `fk_tipo_paro_codigo`: `FOREIGN KEY (id_codigo) REFERENCES paros.codigo_paro(id_codigo) ON UPDATE CASCADE ON DELETE SET NULL`
- `pk_tipo_paro`: `PRIMARY KEY (id_tipo_paro)`
- `uq_tipo_paro_descripcion`: `UNIQUE (descripcion)`

## paros.turno

Turnos de trabajo. Incluye "No registrado" para el histórico sin turno.

| Columna | Tipo | Nulo | Default | Restricciones | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id_turno` | smallint | NO | IDENTITY | PK |  |
| `nombre` | character varying(30) | NO |  | UNIQUE uq_turno_nombre | Nombre tal como se usa en planta, por ejemplo 6am-2pm (Turno 1). |
| `hora_inicio` | time without time zone | SÍ |  | CHECK ck_turno_horas_par | Hora de inicio del turno. |
| `hora_fin` | time without time zone | SÍ |  | CHECK ck_turno_horas_par | Hora de fin; puede ser menor que el inicio si el turno cruza la medianoche. |
| `duracion_horas` | numeric(4,2) | SÍ |  | CHECK ck_turno_duracion | Duración nominal. Se guarda porque no es trivial derivarla en turnos nocturnos. |

**Restricciones de la tabla:**

- `ck_turno_duracion`: `CHECK (((duracion_horas IS NULL) OR ((duracion_horas > (0)::numeric) AND (duracion_horas <= (24)::numeric))))`
- `ck_turno_horas_par`: `CHECK (((hora_inicio IS NULL) = (hora_fin IS NULL)))`
- `pk_turno`: `PRIMARY KEY (id_turno)`
- `uq_turno_nombre`: `UNIQUE (nombre)`

## privado.persona_identidad

Nombre real de cada persona. Relación 1:1 con paros.persona, separada por seguridad.

| Columna | Tipo | Nulo | Default | Restricciones | Descripción |
| --- | --- | --- | --- | --- | --- |
| `id_persona` | integer | NO |  | FK → paros.persona (DEL CASCADE, UPD CASCADE); PK |  |
| `nombre_completo` | character varying(120) | NO |  |  | Nombre como figura en el Excel (o el canónico si había variantes). |

**Restricciones de la tabla:**

- `fk_persona_identidad`: `FOREIGN KEY (id_persona) REFERENCES paros.persona(id_persona) ON UPDATE CASCADE ON DELETE CASCADE`
- `pk_persona_identidad`: `PRIMARY KEY (id_persona)`
