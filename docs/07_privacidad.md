# 7. Manejo de los datos personales

## 7.1 El problema

El Excel tiene 58 personas identificadas por nombre: 43 operarias y 15 personas de mantenimiento. Aparecen en las columnas Operario y Personal involucrado, y la base se usa para medir desempeño. El proyecto exige además un repositorio **público** en GitHub.

En Colombia, la Ley 1581 de 2012 y el Decreto 1377 de 2013 exigen que los datos personales se traten solo para la finalidad autorizada, con acceso restringido y con medidas de seguridad. Un nombre asociado a "cuántos paros tuvo en su turno" es un dato personal que, publicado, podría usarse para señalar a una trabajadora. No hay motivo de negocio para que un analista de productividad vea el nombre: le basta con distinguir a una persona de otra.

## 7.2 La solución: seudonimización + separación + permisos

**1. Seudónimos en el esquema operativo.** Cada persona recibe un código estable según su rol: `OPE-001` … `OPE-043` para operarias y `MTO-001` … `MTO-015` para mantenimiento. Todas las tablas de hechos y todos los informes usan ese código. La tabla `paros.persona` no tiene ninguna columna con el nombre.

**2. La identidad vive aparte.** El nombre está en `privado.persona_identidad`, una tabla 1:1 con `persona` en un esquema distinto. Así se le pueden dar permisos diferentes sin tocar el modelo.

**3. Permisos por rol (`sql/10_seguridad.sql`).**

| Rol | Qué puede hacer |
| --- | --- |
| `rol_analista` | Leer todo el esquema `paros`. No ve el esquema `privado`. |
| `rol_captura` | Registrar y corregir turnos y paros. No borra. |
| `rol_talento_humano` | Además de leer, puede consultar y mantener la identidad de las personas. |

Para saber quién es `MTO-010`, alguien con `rol_talento_humano` ejecuta:

```sql
SELECT p.codigo, i.nombre_completo
FROM paros.persona p JOIN privado.persona_identidad i USING (id_persona)
WHERE p.codigo = 'MTO-010';
```

**4. Nada de nombres en el repositorio.** El ETL escribe los nombres solo en la carpeta `privado/`, que está en `.gitignore`:

| Archivo | Contenido | ¿Se sube a GitHub? |
| --- | --- | --- |
| `sql/06_carga_catalogos_etl.sql` | Seudónimos y rol | Sí |
| `sql/07_carga_staging.sql` | Histórico con seudónimos | Sí |
| `privado/identidades.sql` | Seudónimo → nombre | **No** |
| `privado/mapa_personas.csv` | Seudónimo, nombre y variantes encontradas | **No** |
| `privado/alias_personas.csv` | Variantes que el equipo decidió unir | **No** |
| `datos/*.xlsm` | El Excel original | **No** |

La verificación `V6` de `09_verificacion.sql` comprueba que no haya columnas de nombre en el esquema público.

**5. Nombres dentro del texto libre.** Las observaciones a veces mencionan personas. El ETL reemplaza cualquier nombre conocido por su seudónimo antes de escribir el staging (en este histórico encontró 1 caso).

## 7.3 Unificación de identidades

El mismo técnico aparece escrito de varias formas (un apellido con y sin diéresis, una vez con nombre completo y otra solo con nombre y un apellido). El ETL une automáticamente las variantes que solo cambian en tildes, mayúsculas o espacios. Las demás se unen con el archivo `privado/alias_personas.csv` (columnas `variante,canonico`), que el equipo revisa a mano. En este histórico se unieron 6 técnicos. En la carpeta `etl/` hay un ejemplo con nombres ficticios del formato del archivo.

Hay casos que **no** se unieron a propósito: una operaria registrada solo con el nombre y una técnica de mantenimiento con el mismo nombre y apellido completo. El área que atendió el ajuste indica que son personas distintas.

## 7.4 Lo que queda pendiente para la empresa

- Obtener la autorización de tratamiento de datos de las trabajadoras si la base se usa para evaluar desempeño individual.
- Definir quién tendrá `rol_talento_humano`.
- Fijar cuánto tiempo se conserva la identidad de una persona que se retira. Con `ON DELETE CASCADE` desde `persona`, borrar a alguien sin historial también borra su nombre. Si tiene historial, se marca `activo = false` y se puede borrar solo su fila de `privado.persona_identidad`: los registros quedan anónimos para siempre.
