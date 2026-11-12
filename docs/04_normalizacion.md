# 4. Normalización: del Excel a 3FN

Se parte de la fila de `T_baseDeDatos` tal como está y se avanza forma por forma. En cada paso se dice qué dependencia o anomalía se elimina y por qué importa en esta planta.

## 4.0 Estructura original (0FN)

```
BASE( Fecha, Mes, Año, Maquina, Operario, Referencia,
      Unidades producidas cada minuto, Unidad por display, Display por paca,
      Pacas producidas, Horas trabajadas, Turno, Horas no trabajadas,
      Tipo de paro, Observaciones de paro,
      Codigo de paro 1, Sub Codigo de paro 1, Codigo 1 en horas,
      Codigo de paro 2, Codigo 2 en horas,
      Codigo de paro 3, Subcodigo 3, Codigo 3 en horas,
      Codigo de paro 4, Codigo 4 en horas,
      Codigo de paro 5, Subcodigo 5, Codigo 5 en horas, Área involucrada en subcodigo 5, Personal involucrado,
      Codigo de paro 6 … Codigo de paro 18 (cada uno con su "en horas"),
      Tiempo de Paro, Observaciones )
```

No tiene clave: hay 42 filas idénticas, y la combinación fecha + máquina + turno + operaria + referencia se repite en 1.073 grupos. Además, en la misma tabla conviven tres clases de fila (turno, fila de subcódigo y fila vacía).

### Anomalías que produce

| Tipo | Ejemplo concreto en este archivo |
| --- | --- |
| Inserción | Para registrar un paro nuevo, el código 19, hay que agregar dos columnas, cambiar la macro y rehacer seis tablas dinámicas. Para registrar dos ajustes operativos con distinto subcódigo en el mismo turno hay que inventar una fila sin horas (la "fila de subcódigo"). |
| Actualización | Corregir la descripción "1.2D RETENEDORES Y ORING" exige editar 66 celdas, y si se olvida una, el gráfico del P-MTO-22 muestra dos barras para el mismo subcódigo. Cambiar el área de impacto de un código no se puede hacer en un solo lugar. |
| Borrado | Hay técnicos que aparecen en muy pocas filas (uno, en solo 6). Si se borran esas filas, la base olvida que la persona existió, porque no hay una lista de personas independiente de los turnos. |

## 4.1 Primera forma normal (1FN)

**Regla:** valores atómicos y sin grupos repetitivos; cada fila identificable por una clave.

**Qué se elimina:**

1. **El grupo repetitivo de 18 códigos.** Los pares "Codigo de paro N / Codigo N en horas" se convierten en filas de una tabla nueva, una por paro. Las filas de subcódigo del Excel dejan de ser un truco y pasan a ser paros normales del mismo turno.
2. **Valores no atómicos.** "1.2.A Cambio de racores" mezcla clave y descripción en una celda: se separa en `clave = '1.2.A'` y `descripcion = 'Cambio de racores'`. Lo mismo con "[05] Ajuste operativo" → `id_codigo = 5`, `nombre = 'Ajuste operativo'`.
3. **Ausencia de clave.** Se agrega `parte` para distinguir filas que comparten fecha, máquina, turno, operaria y referencia.

**Resultado:**

```
REGISTRO( _fecha, maquina, turno, operario, referencia, parte_,
          mes, año, pacas, horas_trab, horas_no_trab, tipo_paro, observaciones_paro,
          colores, unidades_display, displays_paca, observaciones )

PARO( _fecha, maquina, turno, operario, referencia, parte, id_paro_,
      codigo, nombre_codigo, area_impacto, subcodigo, desc_subcodigo, sistema,
      minutos, horas, area_atiende, persona_atiende )
```

`id_paro` es necesario en la clave porque un turno puede tener varios paros con el mismo código y subcódigo.

## 4.2 Segunda forma normal (2FN)

**Regla:** estar en 1FN y que ningún atributo no clave dependa solo de **una parte** de la clave compuesta.

**Dependencias parciales encontradas:**

- En `REGISTRO`: `maquina, referencia → colores, unidades_display, displays_paca`. Los parámetros del producto dependen de la pareja máquina–referencia, no del turno entero.
- En `REGISTRO`: `fecha → mes, año`.
- En `PARO`: la clave incluye las seis columnas del turno, y ninguno de los atributos del código o del subcódigo depende de ellas. Pero no se trata solo de eso: `codigo → nombre_codigo, area_impacto` y `subcodigo → desc_subcodigo, sistema` dependen de atributos que ni siquiera son parte de la clave (eso se resuelve en 3FN). Lo que sí es parcial es que el turno completo se repita en cada paro.

**Qué se hace:**

- Se crea `MAQUINA_REFERENCIA(maquina, referencia, colores, unidades_display, displays_paca)`.
- Mes y año se eliminan: son derivables de la fecha con `EXTRACT()`. Esto, de paso, corrige el año guardado como texto.
- Se introduce `id_registro` como clave sustituta de `REGISTRO`, y `PARO` pasa a referenciarlo: `PARO(_id_paro_, id_registro, codigo, …)`. Con una clave simple en `PARO`, ya no puede haber dependencias parciales.

**Anomalía que desaparece:** si mañana Vinilos_3 cambia la cantidad de displays por paca de "Kids 22cc", se corrige una fila y no cientos.

## 4.3 Tercera forma normal (3FN)

**Regla:** estar en 2FN y que ningún atributo no clave dependa de otro atributo no clave (sin dependencias transitivas).

**Dependencias transitivas encontradas y tabla que se crea para cada una:**

| Dependencia transitiva | Tabla nueva |
| --- | --- |
| `id_paro → codigo → nombre_codigo, area_impacto` | `codigo_paro`, `area_impacto` |
| `id_paro → subcodigo → descripcion, sistema (padre), equivalente` | `subcodigo` (con FK a sí misma) |
| `id_paro → persona_atiende → nombre` | `persona` (+ `privado.persona_identidad`) |
| `id_paro → area_atiende → nombre` | `area_agente` |
| `id_registro → maquina → nombre, velocidad, factor` | `maquina` |
| `id_registro → turno → hora inicio, hora fin, duración` | `turno` |
| `id_registro → operario → nombre` | `persona` |
| `id_registro → referencia → nombre` | `referencia` |
| `id_registro → tipo_paro → descripción, código equivalente` | `tipo_paro` |
| `id_registro → observaciones_paro → texto` | `causa_paro` |
| `paro.minutos → paro.horas` y `Σ minutos → Tiempo de Paro` | Se eliminan; se calculan en las vistas |
| `colores, unidades_display, displays_paca → unidades_paca` (columna "Unidades * paca" de las tablas de referencias) | Se elimina: se verificó que las 130 filas del catálogo cumplen la multiplicación |

**Anomalía que desaparece:** cambiar "Ajuste operativo" de área, o corregir la descripción de un subcódigo, se hace en una sola fila y todos los informes lo reflejan.

**¿Y la Forma Normal de Boyce-Codd?** Se revisaron las dependencias de las tablas con más de una clave candidata:

- `subcodigo`: claves candidatas `id_subcodigo` y `(id_codigo, clave)`. Todo determinante es superclave. Cumple FNBC.
- `registro_turno`: claves candidatas `id_registro` y `(fecha, id_maquina, id_turno, id_operaria, id_referencia, parte)`. Cumple FNBC.
- `persona`: `id_persona` y `codigo`. Hay una regla `codigo → rol` (el prefijo OPE/MTO indica el rol), pero `codigo` es clave candidata, así que no rompe FNBC; se protege con un CHECK para que no se contradigan.

## 4.4 Desnormalizaciones intencionales

| Qué | Dónde | Por qué se acepta |
| --- | --- | --- |
| `duracion_horas` se guarda aunque se podría calcular con las horas | `turno` | En turnos que cruzan la medianoche la resta da negativo, y "No registrado" no tiene horas. Es un catálogo de 8 filas que casi no cambia. |
| `fila_excel` | `registro_turno`, `paro` | No es un dato del negocio; es trazabilidad de la migración. Permite volver al Excel y demostrar de dónde salió cada fila. Puede quedar nulo para capturas nuevas. |
| `requiere_revision` | `registro_turno` | Bandera de calidad de datos, calculable en parte, pero se guarda porque refleja una decisión humana pendiente (alguien tiene que revisar y desmarcar). |
| Esquema `stg` | — | Copia sin normalizar del Excel. Existe solo para migrar y verificar; se puede borrar después. |
| `nombre_completo` en otro esquema | `privado.persona_identidad` | No es desnormalización sino lo contrario (una partición vertical 1:1). Se menciona aquí porque se aparta del diseño "una entidad, una tabla" por una razón de seguridad. |

## 4.5 Evidencia: del Excel a las tablas, con datos reales

Un turno real del Excel, fila 10 (25-mar-2025, Vinilos_3), tenía en una sola fila: 9,5 horas trabajadas, 25 pacas, minutos en siete códigos (05, 06, 07, 08, 15, 16 y 17) y el subcódigo 5.8 del ajuste operativo. En la base queda así:

```sql
SELECT r.id_registro, r.fecha, m.nombre AS maquina, r.horas_trabajadas, r.pacas_producidas
FROM paros.registro_turno r JOIN paros.maquina m USING (id_maquina)
WHERE r.fila_excel = 10;

SELECT codigo, subcodigo, area_atiende, minutos
FROM paros.v_paro_detalle
WHERE id_registro = (SELECT id_registro FROM paros.registro_turno WHERE fila_excel = 10);
```

Una fila de 58 columnas se convierte en un registro y siete paros, uno por código con minutos. Las columnas "en horas", Mes, Año y Tiempo de Paro desaparecen porque la vista las calcula.
