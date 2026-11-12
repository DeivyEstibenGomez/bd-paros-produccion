# 1. Diagnóstico del Excel actual

Archivo analizado: `SEGUIMIENTO TEMPERAS Y VINILOS Actividad.xlsm` (21 hojas, 24 tablas, macros VBA) y el procedimiento P-MTO-22. La tabla que funciona como base de datos es `T_baseDeDatos` en la hoja *Base De Datos*: 8.208 filas, 58 columnas, del 1 de enero de 2022 al 28 de marzo de 2025.

El problema de fondo es de diseño. Una sola tabla guarda hechos de dos niveles (el turno y cada paro), catálogos escritos como texto libre y valores calculados. Casi todo lo demás se desprende de ahí.

## 1.1 Problemas de diseño y sus consecuencias

| ID | Problema | Evidencia en el archivo | Consecuencia para el negocio |
| --- | --- | --- | --- |
| D-01 | **Grupos repetitivos** (viola 1FN): 18 pares de columnas "Codigo de paro N" / "Codigo N en horas". | Columnas P a BD de `T_baseDeDatos`. | Agregar un código nuevo obliga a cambiar la tabla, las macros y las seis tablas dinámicas. Dos paros del mismo código en un turno solo caben sumados en una celda. |
| D-02 | **Dos tipos de fila en una tabla.** El botón "Ingreso subcódigo" inserta filas sin pacas ni horas, solo con un subcódigo y sus minutos. | 1.354 filas de este tipo y 231 completamente vacías. | Contar turnos o promediar horas da un resultado inflado si nadie filtra esas filas a mano. |
| D-03 | **Atributos derivados guardados.** Mes y Año (fórmulas `TEXT()`, guardadas como texto), las 18 columnas "en horas" (minutos / 60) y "Tiempo de Paro" (suma). | 21 de las 58 columnas son calculables. | Hoy cuadran, pero nada impide que se descuadren. El año como texto ordena mal y no permite rangos. |
| D-04 | **Dos catálogos de tipo de paro mezclados.** Conviven la numeración antigua ("17. PARO DE MAQUINA") y la vigente ("[18] Paro de maquina por ventas"). | 1.463 filas con el catálogo antiguo. | El informe de horas no trabajadas mezcla categorías que no son comparables entre 2023 y 2024. |
| D-05 | **Subcódigos sin integridad.** El mismo concepto aparece escrito de varias formas. | "1.2D  RETENEDORES Y ORING ", "1.2.C Cambio de Valvula", "1.6 VIDEO JET" vs. "1.6 SISTEMA VIDEO JET": 45 textos para 31 subcódigos del 01. | Un mismo subcódigo se reparte en varias barras de los gráficos del P-MTO-22. |
| D-06 | **Subcódigos del 05 con dos numeraciones que no coinciden.** El catálogo viejo usaba 4.x y el nuevo 5.x, pero 4.4 Transfer = 5.5, 4.6 Video Jet = 5.7. | 945 filas de 2022-2023 con 4.x. La tabla `Tabla10` todavía se titula "CÓDIGO DE PARO 4". | Comparar ajustes operativos entre años por número de subcódigo da resultados falsos. |
| D-07 | **Personas como texto libre.** Sin identificador; la misma persona escrita de varias formas. | Un mismo técnico aparece con el apellido escrito de dos formas; otro, a veces con nombre completo y a veces con nombre y un apellido. En total, 6 técnicos con variantes. | No se puede responder con confianza cuánto tiempo de ajuste atendió cada técnico. |
| D-08 | **"No aplica" como valor** en vez de vacío. | Operario (537), turno (336), tipo de paro (2.282), observaciones (2.248). | Contamina conteos y promedios; "No aplica" aparece como una operaria más en los filtros. |
| D-09 | **Turno sin registrar** en buena parte del histórico. | 3.912 filas (48 %) sin turno, casi todas de 2022-2023. | La comparación entre turnos solo es posible desde 2024. |
| D-10 | **Copia oculta de los datos.** La hoja oculta *Base de datos de Sub codigos* (`Base_de_datos_subcodigos`, 1.252 filas) repite filas de la base principal. | 1.018 de sus 1.022 filas con minutos están también en `T_baseDeDatos`. | Dos fuentes para el mismo hecho: si alguien corrige una, la otra queda desactualizada. |
| D-11 | **Filas idénticas.** | 42 filas son copia exacta de otra (50 filas involucradas). | Una parte puede ser doble digitación y otra, turnos distintos sin turno anotado. El Excel no permite distinguirlas. |
| D-12 | **Valores fuera de rango sin control.** | 9 filas suman más de 24 h en un día; 11 con más de 3.000 pacas en 8 h (la mediana es 54); 3 con más paro que horas trabajadas. | Esos registros mueven el indicador mensual y nadie los ve. |
| D-13 | **La macro no valida nada.** `InsertarRegistro` inserta en la fila 10 y empuja todo hacia abajo. | Código VBA del módulo. | No hay identificador, ni control de duplicados, ni transacción: si la macro falla a mitad, la fila queda incompleta. |
| D-14 | **Tablas dinámicas desactualizadas.** Su caché tenía 7.928 filas cuando la tabla tenía 8.208. | `pivotCacheDefinition`. | El informe a la alta dirección puede salir sin las últimas semanas si nadie pulsa "Actualizar". |
| D-15 | **Datos capturados que no se guardan.** La meta por hora y el tiempo faltante se piden en el formulario y se pierden. | Hoja Registro vs. columnas de la base. | No se puede reconstruir la eficiencia frente a la meta. |
| D-16 | **Catálogos duplicados y con errores.** Hasta tres versiones de la misma lista; celdas `#VALUE!`; erratas en referencias ("Alocdor"). | Hojas *Tablas Desplegables*, *Tiempos*, *TABLA CODIGOS*. | Cualquier cambio de catálogo hay que hacerlo en varios lugares. |
| D-17 | **Columna usada para otra cosa.** Entre octubre de 2023 y mayo de 2024, la columna "Unidad por display" guarda el nombre del turno. | 687 filas con valores como "2pm-10pm (Turno 2)"; las otras dos columnas de parámetros del producto están vacías en todo el histórico. | Es un dato repetido que puede contradecir a la columna Turno (3 filas ya difieren en el formato). Muestra que la macro escribió en la columna equivocada durante siete meses sin que nadie lo notara. |
| D-18 | **Nombres de trabajadores en un archivo que circula.** | Columnas Operario y Personal involucrado. | Riesgo frente a la Ley 1581 de 2012 de protección de datos personales. |

## 1.2 Diferencias entre el Excel y el procedimiento P-MTO-22

- El PDF lista 17 códigos; el Excel usa 18 y el catálogo de tipos de paro llega al [19] "No aplica".
- El P-MTO-22 menciona "códigos 1 al 18" en el numeral 4.1.4, contradiciendo su propia lista.
- El PDF no trae la fórmula de productividad. La única definición está en el campo calculado de las tablas dinámicas: `(horas trabajadas − tiempo de paro) / horas trabajadas`. La base de datos la reproduce y la deja escrita (`paros.fn_productividad`).
- El procedimiento no tiene firmas de aprobación (los campos "Aprobó" y "Cargo" conservan el texto de la plantilla).

## 1.3 Lo que se rescata del Excel

No todo es problema. La regla de los paros programados por turno (16 y 17, con 40/3 minutos o 70/6 en la jornada de 10,5 h) está bien pensada y se conserva en la tabla `paro_programado_turno`. La validación de referencias según la máquina (`INDIRECT(maquina & "[referencia]")`) también se conserva, ahora como una llave foránea compuesta.
