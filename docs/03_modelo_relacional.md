# 3. Modelo relacional (lógico)

Derivado del MER con las reglas habituales:

- Cada entidad fuerte es una tabla con su identificador como PK.
- Las relaciones 1:N se resuelven con una FK en el lado N.
- Las N:M (máquina–referencia, turno–código programado) son tablas con PK compuesta por las dos FK.
- Las recursivas de subcódigo (padre y equivalente) son FK a la misma tabla.
- La 1:1 persona–identidad comparte la PK (la PK de `persona_identidad` es también FK).
- Los atributos derivados del Excel (mes, año, horas por código, tiempo total de paro, unidades por paca) **no** se guardan; se calculan en las vistas o las consultas.

Notación: **subrayado** = PK, *cursiva* = FK.

```
area_impacto        (_id_area_, nombre)
codigo_paro         (_id_codigo_, nombre, *id_area*, requiere_subcodigo, activo)
subcodigo           (_id_subcodigo_, *id_codigo*, clave, descripcion, *id_padre*, *id_equivalente*, vigente)
                      UNIQUE (id_codigo, clave)
                      FK (id_padre, id_codigo) → subcodigo (id_subcodigo, id_codigo)
maquina             (_id_maquina_, nombre, unidades_minuto, factor_ajuste, activa)
turno               (_id_turno_, nombre, hora_inicio, hora_fin, duracion_horas)
paro_programado_turno (_*id_turno*, *id_codigo*_, minutos)
referencia          (_id_referencia_, nombre)
maquina_referencia  (_*id_maquina*, *id_referencia*_, num_colores, unidades_por_display,
                     displays_por_paca, en_catalogo)
persona             (_id_persona_, codigo, rol, activo)
privado.persona_identidad (_*id_persona*_, nombre_completo)
area_agente         (_id_area_agente_, nombre)
tipo_paro           (_id_tipo_paro_, descripcion, catalogo, *id_codigo*)
causa_paro          (_id_causa_, descripcion)
registro_turno      (_id_registro_, fecha, *id_maquina*, *id_turno*, *id_operaria*, *id_referencia*, parte,
                     pacas_producidas, horas_trabajadas, horas_no_trabajadas, meta_por_hora,
                     *id_tipo_paro*, *id_causa*, observaciones, requiere_revision, fila_excel, registrado_en)
                      UNIQUE NULLS NOT DISTINCT (fecha, id_maquina, id_turno, id_operaria, id_referencia, parte)
                      FK (id_maquina, id_referencia) → maquina_referencia
paro                (_id_paro_, *id_registro*, *id_codigo*, *id_subcodigo*, minutos,
                     *id_area_agente*, *id_persona_atiende*, fila_excel)
                      FK (id_subcodigo, id_codigo) → subcodigo (id_subcodigo, id_codigo)
```

## 3.1 Llaves: por qué natural o sustituta

| Tabla | PK | Motivo |
| --- | --- | --- |
| `codigo_paro` | Natural (`id_codigo` = 1..18) | La planta habla de "el código 05". Es estable, corto y lo usa el procedimiento. |
| `registro_turno`, `paro` | Sustituta `bigint IDENTITY` | La clave natural del turno tiene seis columnas y dos pueden ser nulas; usarla como FK en `paro` sería costoso y frágil. Se mantiene como `UNIQUE`. |
| `subcodigo` | Sustituta | La clave "5.2" no es única entre códigos ni estable (el 05 ya cambió de numeración una vez). `(id_codigo, clave)` queda como `UNIQUE`. |
| `persona` | Sustituta + `codigo` UNIQUE | El seudónimo es lo que ve el usuario; el id interno no cambia si se reasigna el seudónimo. |
| Catálogos pequeños | Sustituta `smallint` + nombre UNIQUE | Permite corregir un nombre sin tocar las filas que lo referencian. |

## 3.2 Dos llaves foráneas compuestas que hacen trabajo de negocio

1. `paro (id_subcodigo, id_codigo) → subcodigo (id_subcodigo, id_codigo)`. Impide registrar el subcódigo 1.2.A (falla de dosificación) en un paro del código 03 (potencia). En el Excel esto era posible y pasó.
2. `registro_turno (id_maquina, id_referencia) → maquina_referencia`. Reemplaza la validación `INDIRECT()` del formulario: Vinilos_2 no puede registrar una referencia que no envasa.

## 3.3 Políticas ON DELETE / ON UPDATE

| Caso | Política | Por qué |
| --- | --- | --- |
| `paro → registro_turno` | `ON DELETE CASCADE` | El paro depende de su turno (participación total). Si se anula un turno mal digitado, sus paros no tienen sentido solos. |
| `maquina_referencia → maquina / referencia` | `ON DELETE CASCADE` | Es solo una asociación. Pero si la referencia ya tiene turnos, el `RESTRICT` de `registro_turno` frena el borrado de todos modos. |
| `paro_programado_turno → turno` | `ON DELETE CASCADE` | Los minutos estándar son parte de la definición del turno. |
| `privado.persona_identidad → persona` | `ON DELETE CASCADE` | Si se elimina la persona (sin historial), su nombre debe desaparecer también. |
| `subcodigo.id_equivalente`, `tipo_paro.id_codigo` | `ON DELETE SET NULL` | Son enlaces informativos: si desaparece el destino, el subcódigo o tipo antiguo se conserva sin equivalencia. |
| Todo lo que apunta a catálogos y a `persona` desde los hechos | `ON DELETE RESTRICT` | Borrar un código, una máquina o una persona con historial destruiría el histórico. Se desactivan con `activo = false`. |
| Todas las FK | `ON UPDATE CASCADE` | Si se renumera un código (ya pasó con el 05 y el catálogo de tipos), los hechos lo siguen sin intervención manual. |
