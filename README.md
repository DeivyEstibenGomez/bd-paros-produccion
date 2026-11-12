# Base de datos de paros de producción — Vinilos y témperas

Proyecto final de Bases de Datos I. Reemplaza el libro `SEGUIMIENTO TEMPERAS Y VINILOS Actividad.xlsm`, que hoy funciona como "base de datos" del registro de paros de las cuatro líneas de envasado (Vinilos_1 a Vinilos_4), por una base relacional normalizada en PostgreSQL.

   **AUTOR:** Deivy Estiben Gomez 

   **MOTOR:** PostgreSQL 16 o superior (probado en PostgreSQL 18)
## Qué se logró

- Un modelo en 3FN con 15 tablas que separa el turno (`registro_turno`) de cada paro (`paro`), en lugar de las 18 columnas repetidas del Excel.
- La migración completa del histórico: 8.208 filas de enero de 2022 a marzo de 2025 → 6.628 registros de turno y 16.532 paros.
- Verificación de integridad: los 25 totales de control del Excel (pacas, horas, minutos por cada código, % de productividad) coinciden con la base. La productividad por año y máquina cuadra al centésimo con la tabla dinámica actual (77,80 % global).
- Las reglas de negocio quedaron en la base: llaves foráneas compuestas (subcódigo del mismo código, referencia habilitada para la máquina), CHECK, UNIQUE y triggers.
- Datos personales protegidos: los informes usan seudónimos (`OPE-001`, `MTO-001`) y los nombres viven en un esquema aparte que no se sube a GitHub.
- 16 consultas que responden preguntas del negocio, incluidas las cuatro del enunciado.

## Estructura del repositorio

```
├── README.md
├── .gitignore
├── sql/                          scripts en orden de ejecución
│   ├── 00_crear_bd.sql           crea la base bd_paros
│   ├── 01_esquema.sql            esquemas, tablas, PK, FK, UNIQUE, CHECK, DEFAULT, comentarios
│   ├── 02_funciones_triggers.sql reglas RN-03 y RN-14, función de productividad
│   ├── 03_indices.sql            7 índices justificados por consulta
│   ├── 04_vistas.sql             4 vistas que reemplazan las tablas dinámicas
│   ├── 05_catalogos.sql          catálogos estables (códigos, subcódigos, máquinas, turnos…)
│   ├── 06_carga_catalogos_etl.sql  [generado] referencias, personas (seudónimos), causas
│   ├── 07_carga_staging.sql        [generado] copia del Excel fila a fila + totales de control
│   ├── 08_transformacion.sql     staging → modelo normalizado
│   ├── 09_verificacion.sql       prueba de que los datos llegaron íntegros
│   ├── 10_seguridad.sql          roles y permisos
│   ├── 11_dml_pruebas.sql        INSERT/UPDATE/DELETE que muestran las restricciones
│   ├── 12_consultas_negocio.sql  16 consultas de negocio
│   └── ejecutar_todo.sql         ejecuta 00 a 10 con psql
├── etl/
│   ├── extraer_excel.py          lee el .xlsm y genera 06 y 07
│   ├── requirements.txt
│   └── alias_personas.ejemplo.csv
├── scripts/
│   ├── reconstruir.sh / .ps1     reconstrucción en un paso (Linux/Mac / Windows)
│   └── diccionario.sql           genera docs/05_diccionario_datos.md desde el catálogo
├── docs/
│   ├── 01_diagnostico_excel.md   problemas del Excel y sus consecuencias
│   ├── 02_modelo_conceptual.md   MER (entidades, relaciones, cardinalidad, participación)
│   ├── 03_modelo_relacional.md   modelo lógico, llaves y políticas ON DELETE/UPDATE
│   ├── 04_normalizacion.md       de 0FN a 3FN (y FNBC), desnormalizaciones
│   ├── 05_diccionario_datos.md   [generado] cada columna con tipo, nulabilidad, default y restricciones
│   ├── 06_migracion.md           estrategia de carga y conciliación
│   ├── 07_privacidad.md          manejo de nombres de operarias y técnicos
│   ├── GUIA_GIT_GITHUB.md        cómo subir y mantener el repositorio
│   ├── reporte_etl.md            [generado] resumen de la extracción
│   └── evidencias/               salida real de 09, 11 y 12
├── datos/      (el Excel va aquí; no se sube)
└── privado/    (nombres reales; no se sube)
```

## Cómo reproducir la base desde cero

### Opción A: una línea con psql (recomendada)

Desde la raíz del repositorio:

```bash
psql -U postgres -f sql/ejecutar_todo.sql
```

En Windows (PowerShell), con `psql` en el PATH:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\reconstruir.ps1
```

Tarda unos segundos. Al final imprime la verificación: todas las filas de `V3` y `V4` deben decir `OK` y `V2` debe dar 0.

> Si DBeaver u otro programa está conectado a `bd_paros`, PostgreSQL no deja borrarla. Desconéctelo antes.

### Opción B: DBeaver

1. Conectarse a la base `postgres` y ejecutar `sql/00_crear_bd.sql` (Alt+X, *Execute SQL Script*).
2. Crear una conexión a `bd_paros` (o refrescar y cambiar la base activa).
3. Abrir y ejecutar con Alt+X, en orden, los scripts `01` a `10`. El `07` es grande (2,4 MB) y tarda un poco más.
4. Para la demostración: `11_dml_pruebas.sql` (los rechazos salen en la pestaña *Output*) y `12_consultas_negocio.sql`.

### Opción C: regenerar los scripts de carga desde el Excel

Solo hace falta si cambia el Excel o las reglas de limpieza.

```bash
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r etl/requirements.txt
python -I etl/extraer_excel.py "datos/SEGUIMIENTO TEMPERAS Y VINILOS Actividad.xlsm"
```

Genera `sql/06`, `sql/07`, `docs/reporte_etl.md` y los archivos de `privado/`. Si la entrada es la misma, los archivos generados salen idénticos byte a byte, así que Git solo mostrará cambios reales.

### Nombres reales (solo equipo del proyecto)

```bash
psql -U postgres -d bd_paros -f privado/identidades.sql
```

## Consultas incluidas

| # | Pregunta |
| --- | --- |
| C01 | % de productividad por máquina y mes |
| C02 | Comparativo 2024 vs 2025 por máquina y mes |
| C03 | Participación porcentual de cada código de paro |
| C04 | Código 01 por sistema y componente (con subtotales) |
| C05 | Código 03 por subcódigo y año |
| C06 | Código 05 por subcódigo vigente y área que atendió |
| C07 | Desempeño por turno |
| C08 | Top 3 de causas de ajuste por máquina en un trimestre |
| C09 | Meses en que una máquina quedó bajo el promedio de la planta |
| C10 | Ajustes atendidos por cada técnico |
| C11 | Productividad por operaria |
| C12 | Horas no trabajadas por motivo (catálogo antiguo y vigente) |
| C13 | Pareto de códigos de paro |
| C14 | Tendencia mensual con variación frente al mes anterior |
| C15 | Referencias del catálogo nunca producidas y producciones fuera de catálogo |
| C16 | Cola de revisión de datos sospechosos |

Entre todas usan INNER, LEFT, RIGHT, FULL OUTER y CROSS JOIN, funciones de agregación, GROUP BY / HAVING, GROUPING SETS, subconsultas (en FROM, en WHERE y correlacionadas), CTE, funciones de ventana y filtros por rango de fechas.

## Decisiones y supuestos

Las decisiones que la empresa debería confirmar están marcadas en los documentos. Las principales:

- La fórmula oficial de productividad es la del campo calculado de las tablas dinámicas: `(Σ horas trabajadas − Σ horas de paro) / Σ horas trabajadas`.
- Los subcódigos antiguos 4.x del código 05 equivalen a los 5.x **por descripción**, no por número (4.4 → 5.5, 4.6 → 5.7).
- Tres tipos de paro del catálogo antiguo ("17. PARO DE MAQUINA", "9. FALTA DE PROGRAMACIÓN", "16. PARO POR PROCESO ANTERIOR") no tienen equivalencia clara y quedan sin código vigente.
- Ninguna fila del Excel se borró ni se corrigió: las dudosas se cargaron y quedaron marcadas con `requiere_revision`.
