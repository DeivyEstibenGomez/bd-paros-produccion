# 6. Migración del histórico

## 6.1 Estrategia: ETL en dos tiempos

Se separó la migración en dos partes con responsabilidades distintas:

1. **Extracción y limpieza de texto (Python, `etl/extraer_excel.py`).** Lee el `.xlsm` sin abrir Excel, limpia los textos y escribe archivos `.sql` con `INSERT` planos. No decide nada sobre los números ni borra filas.
2. **Transformación (SQL, `sql/08_transformacion.sql`).** Toma la copia fiel del Excel (`stg.base_excel`) y la convierte al modelo normalizado. Aquí están todas las reglas, a la vista de quien lea el script.

¿Por qué no cargar directo desde Python? Porque así el resultado del ETL es un archivo de texto que se versiona en Git. Cualquiera puede reconstruir la base sin tener el Excel ni Python, solo con PostgreSQL. Y si alguien pregunta "¿por qué esta fila quedó así?", la respuesta está en un script SQL que se puede leer, no dentro de un programa.

```
 Excel (.xlsm)
     │  etl/extraer_excel.py   (limpia textos, seudonimiza personas, calcula totales de control)
     ▼
 sql/06_carga_catalogos_etl.sql  +  sql/07_carga_staging.sql      ← se versionan en Git
     │  psql / DBeaver
     ▼
 stg.base_excel  (8.208 filas, igual que el Excel)
     │  sql/08_transformacion.sql
     ▼
 paros.registro_turno (6.628)  +  paros.paro (16.532)
     │  sql/09_verificacion.sql
     ▼
 Conciliación: 25 totales de control en OK
```

## 6.2 Qué limpia el ETL

| Campo | Regla | Ejemplo |
| --- | --- | --- |
| Todos los textos | Espacios sobrantes; "No aplica", "No" y vacío → nulo | `"1.2D  RETENEDORES "` → `"1.2D RETENEDORES"` |
| Subcódigos | Se extrae la clave y se normaliza | `1.2D` → `1.2.D`; `1.4.3 Sensor` → `1.4.C`; `Sin especificar` → nulo |
| Subcódigo con significado distinto | Excepción explícita | `1.7A CAMBIO DE ROSCADORES` (catálogo viejo) → `1.7.B Roscadores` |
| Tipo de paro | Formato único para cada catálogo | `9.FALTA DE PROGRAMACIÓN` → `9. FALTA DE PROGRAMACIÓN`; `[19] No aplica` → nulo |
| Turno | Celda vacía → "No registrado"; "No aplica" → "Sin turno" | |
| Referencias | Espacio antes de "col" y una errata | `(6col)` → `(6 col)`; `Alocdor` → `Alocolor` |
| Causas | Mayúsculas, tildes y tres erratas | 34 textos → 21 causas |
| Personas | Variantes del mismo nombre unidas; seudónimo por rol | Ver `07_privacidad.md` |

Si aparece un valor que ninguna regla reconoce (por ejemplo, un subcódigo nuevo con otro formato), el ETL **se detiene** y lista las filas. No adivina.

## 6.3 Reglas de la transformación

**Tipos de fila.** Cada fila del Excel se clasifica:

| Tipo | Cómo se reconoce | Destino | Filas |
| --- | --- | --- | --- |
| REG | Tiene pacas, horas trabajadas u horas no trabajadas | Un `registro_turno` y sus `paro` | 6.623 |
| SUB | No tiene nada de lo anterior, pero sí minutos de paro | `paro` del turno al que pertenece | 1.354 |
| VACIA | Ni horas, ni pacas, ni minutos | No se carga; queda en `stg.rechazo` | 231 |

**Turno padre de las filas SUB.** La macro del Excel inserta cada fila nueva arriba (fila 10) y empuja el resto hacia abajo. Por eso la fila de subcódigo, que se digita después del turno, queda encima de él. El padre se busca así:

| Nivel | Coincidencia | Filas SUB resueltas |
| --- | --- | --- |
| 1 | Misma fecha, máquina, turno, operaria y referencia; la fila REG más cercana por debajo | 1.302 |
| 2 | Misma fecha, máquina y turno | 32 |
| 3 | Misma fecha y máquina | 15 |
| — | Sin turno ese día en esa máquina: se crea un registro de 0 horas para no perder los minutos, marcado para revisión | 5 |

**Duplicados.** 42 filas son copia exacta de otra. **No se borraron.** 20 de ellas no tienen turno anotado, y bien pueden ser dos turnos distintos con las mismas cifras (por ejemplo, dos turnos de un domingo sin producción). Borrar habría sido decidir por la empresa. Se cargaron y quedaron con `requiere_revision = true`.

**Valores fuera de rango.** Tampoco se corrigieron. Se cargaron y se marcaron:

| Motivo | Registros |
| --- | --- |
| Fila idéntica a otra en el Excel | 50 |
| Pacas atípicas (más de 3.000 en un turno; la mediana es 54) | 11 |
| Horas del día > 24 | 9 |
| Paro mayor que horas trabajadas | 8 |
| Subcódigo sin turno padre | 5 |

La regla de las 24 horas quedó como `CHECK ... NOT VALID`: PostgreSQL no la exige a esas 9 filas históricas, pero sí a toda fila nueva y a esas mismas filas si alguien las edita. Cuando se corrijan, `ALTER TABLE paros.registro_turno VALIDATE CONSTRAINT ck_rt_dia_24h` la deja plenamente vigente.

**Lo que no se migró a propósito.**

- La hoja oculta *Base de datos de Sub codigos*: es una copia parcial de la base principal (1.018 de sus 1.022 filas con minutos ya están allí). Migrarla duplicaría paros.
- Las columnas calculadas (Mes, Año, "Codigo N en horas", Tiempo de Paro) y las tres columnas de parámetros del producto: dos están vacías en todo el histórico y la tercera, "Unidad por display", solo contiene una copia del turno (hallazgo D-17).
- 55 celdas de código con valor 0: no son paros. Quedan registradas en `stg.rechazo`.

## 6.4 Prueba de integridad

`sql/09_verificacion.sql` compara totales que el ETL calcula sobre el Excel **crudo**, antes de limpiar nada, contra los mismos totales recalculados desde las tablas normalizadas. La salida completa está en `docs/evidencias/salida_09_verificacion.txt`.

| Control | Excel | Base de datos |
| --- | --- | --- |
| Filas | 8.208 | 6.623 REG + 1.354 SUB + 231 vacías = 8.208 |
| Filas con datos sin destino | — | 0 |
| Pacas producidas | 378.778 | 378.778 |
| Horas trabajadas | 38.063,35 | 38.063,35 |
| Horas no trabajadas | 41.519,85 | 41.519,85 |
| Tiempo de paro (horas) | 8.449,6517 | 8.449,6517 |
| Minutos por código, del 01 al 18 | 18 totales | 18 totales idénticos |
| Primera y última fecha | 2022-01-01 / 2025-03-28 | 2022-01-01 / 2025-03-28 |
| % productividad global | 77,80 % | 77,80 % |
| % productividad por año y máquina | 16 valores | 16 valores idénticos al centésimo |
| Subcódigos del histórico sin par en el catálogo | — | 0 |

La conclusión es que los datos llegaron completos y que la base reproduce exactamente el indicador que hoy se presenta a la gerencia. Las diferencias de calidad que tenía el Excel siguen ahí, pero ahora están marcadas y se pueden consultar (consulta C16).
