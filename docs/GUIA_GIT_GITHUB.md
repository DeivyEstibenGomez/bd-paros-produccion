# Guía para subir el proyecto a Git y GitHub

Esta guía es para el equipo. Se puede borrar del repositorio antes de la entrega o dejarla como documentación.

El enunciado pide un historial con aportes visibles de los dos integrantes, no uno o dos commits al final. La forma honesta de lograrlo es que **cada integrante suba desde su propio computador y su propia cuenta** la parte que trabajó, a medida que la trabaja. El plan de la sección 5 reparte el trabajo para eso.

---

## 1. Preparar el computador (cada integrante)

1. Instalar Git: <https://git-scm.com/downloads>. En Windows, aceptar las opciones por defecto: incluye *Git Credential Manager*, que abre el navegador para iniciar sesión en GitHub y evita lidiar con tokens.
2. Crear una cuenta en <https://github.com> si no la tienen.
3. Decirle a Git quién es usted. El correo debe ser el mismo de su cuenta de GitHub; si no, los commits no aparecen a su nombre:

```bash
git config --global user.name  "Nombre Apellido"
git config --global user.email "correo-de-su-cuenta@ejemplo.com"
git config --global init.defaultBranch main
git config --global core.autocrlf true      # solo en Windows
git config --global core.autocrlf input     # solo en Mac/Linux
```

Comprobar con `git config --global --list`.

## 2. Crear el repositorio en GitHub (lo hace un integrante)

1. En GitHub: botón **New repository**.
2. Nombre: `bd-paros-produccion`. Visibilidad: **Public**.
3. **No** marcar "Add a README", ".gitignore" ni licencia: el proyecto ya los trae y, si GitHub crea otros, el primer `push` fallará por historias distintas.
4. Crear. Copiar la URL que aparece, del estilo `https://github.com/USUARIO/bd-paros-produccion.git`.
5. Agregar al compañero: **Settings → Collaborators → Add people**. El compañero acepta la invitación desde su correo.

## 3. Primer commit (integrante que creó el repositorio)

```bash
cd ruta/donde/descomprimió/bd-paros-produccion
git init
git status
```

**Antes de agregar nada, revise la salida de `git status`.** No deben aparecer `privado/identidades.sql`, `privado/mapa_personas.csv`, `privado/alias_personas.csv` ni ningún `.xlsm`. Para confirmarlo:

```bash
git check-ignore -v privado/identidades.sql "datos/SEGUIMIENTO TEMPERAS Y VINILOS Actividad.xlsm"
```

Debe responder con la línea del `.gitignore` que los excluye. Si no responde nada, **no siga**: el archivo se subiría.

Luego, el primer commit con la base del proyecto (ver el plan de la sección 5) y la conexión con GitHub:

```bash
git add .gitignore README.md datos/LEEME.md privado/LEEME.md
git commit -m "chore: estructura inicial del repositorio y .gitignore"
git remote add origin https://github.com/USUARIO/bd-paros-produccion.git
git push -u origin main
```

La primera vez se abrirá el navegador para autorizar. Si usa Mac/Linux sin Credential Manager y le pide contraseña, GitHub ya no acepta la contraseña de la cuenta: genere un *token* en **Settings → Developer settings → Personal access tokens → Fine-grained tokens**, con permiso *Contents: Read and write* sobre este repositorio, y péguelo como contraseña.

## 4. El compañero se une

```bash
git clone https://github.com/USUARIO/bd-paros-produccion.git
cd bd-paros-produccion
```

Como `privado/` y `datos/` no viajan por GitHub, el compañero debe copiar el Excel a `datos/` por su cuenta y, si va a correr el ETL, crear `privado/alias_personas.csv` (se lo pasan por un medio privado, no por el repositorio).

### La rutina de trabajo de ambos

Siempre en este orden:

```bash
git pull                      # 1. traer lo último del compañero
# ... trabajar, probar que los scripts corren ...
git status                    # 2. ver qué cambió
git add archivo1 archivo2     # 3. agregar SOLO lo que corresponde a este cambio
git commit -m "tipo: qué hizo"   # 4. un commit por cambio con sentido
git push                      # 5. subirlo
```

Mensajes de commit: verbo en presente o infinitivo, y qué cambió, no "avances" ni "cambios". Prefijos sugeridos: `feat:` (algo nuevo), `fix:` (corrección), `docs:` (documentación), `refactor:` (reorganizar sin cambiar el resultado), `test:` (pruebas), `chore:` (configuración).

Si `git push` es rechazado porque el compañero subió algo antes, haga `git pull`, resuelva si hay conflicto (Git marca las líneas con `<<<<<<<` y `>>>>>>>`; deje la versión correcta, borre las marcas, `git add` y `git commit`) y vuelva a `git push`.

## 5. Plan de commits sugerido

La idea es que el historial cuente cómo se construyó el proyecto. Repartan los archivos según lo que cada uno realmente trabajó y estudió; en la sustentación les pueden preguntar por cualquier parte. Este reparto es solo una propuesta equilibrada:

| # | Integrante | Archivos | Mensaje sugerido |
| --- | --- | --- | --- |
| 1 | A | `.gitignore`, `README.md`, `datos/LEEME.md`, `privado/LEEME.md` | `chore: estructura inicial del repositorio y .gitignore` |
| 2 | A | `docs/01_diagnostico_excel.md` | `docs: diagnóstico del Excel actual (D-01 a D-18)` |
| 3 | B | `docs/02_modelo_conceptual.md` | `docs: modelo entidad-relación con cardinalidad y participación` |
| 4 | B | `docs/03_modelo_relacional.md` | `docs: modelo relacional y políticas de llaves foráneas` |
| 5 | A | `docs/04_normalizacion.md` | `docs: proceso de normalización de 0FN a 3FN` |
| 6 | A | `sql/00_crear_bd.sql`, `sql/01_esquema.sql` | `feat: esquema normalizado con PK, FK, UNIQUE y CHECK` |
| 7 | B | `sql/02_funciones_triggers.sql` | `feat: triggers para reglas RN-03 y RN-14` |
| 8 | B | `sql/03_indices.sql`, `sql/04_vistas.sql` | `feat: índices y vistas de indicadores` |
| 9 | A | `sql/05_catalogos.sql` | `feat: carga de catálogos de códigos, subcódigos, máquinas y turnos` |
| 10 | B | `etl/` | `feat: ETL que extrae el Excel y seudonimiza personas` |
| 11 | B | `sql/06_carga_catalogos_etl.sql`, `sql/07_carga_staging.sql`, `docs/reporte_etl.md` | `feat: scripts de carga generados por el ETL` |
| 12 | A | `sql/08_transformacion.sql` | `feat: transformación del staging al modelo normalizado` |
| 13 | A | `sql/09_verificacion.sql`, `docs/06_migracion.md` | `test: conciliación de totales Excel vs base de datos` |
| 14 | B | `sql/10_seguridad.sql`, `docs/07_privacidad.md` | `feat: roles y separación de datos personales` |
| 15 | B | `sql/11_dml_pruebas.sql` | `test: pruebas de restricciones con INSERT, UPDATE y DELETE` |
| 16 | A | `sql/12_consultas_negocio.sql` | `feat: 16 consultas de negocio` |
| 17 | B | `scripts/`, `docs/05_diccionario_datos.md` | `docs: diccionario de datos generado desde el catálogo` |
| 18 | A | `sql/ejecutar_todo.sql`, `docs/evidencias/` | `chore: script de reconstrucción completa y evidencias` |
| 19 | B | `README.md` | `docs: instrucciones de reproducción` |

Cada paso, antes de hacer commit: ejecutar `psql -U postgres -f sql/ejecutar_todo.sql` (o los scripts que ya existan) y confirmar que no hay errores. Un commit que deja la base sin poder construirse es justo lo que el historial no debería mostrar.

**Lo que no deben hacer:** cambiar fechas de commits, hacer commits a nombre del otro o subir todo en un único commit final. Los profesores suelen revisar las fechas y los autores en la pestaña *Insights → Contributors*.

### Ramas y pull requests (opcional, suma puntos de buenas prácticas)

```bash
git switch -c feat/consultas        # crear una rama para el trabajo
# ... commits ...
git push -u origin feat/consultas
```

En GitHub aparece el botón **Compare & pull request**. El compañero revisa, comenta y aprueba; luego **Merge**. Al terminar, ambos vuelven a `main` y hacen `git pull`.

## 6. Comprobar el resultado en GitHub

- [ ] El README se ve con formato en la página principal del repositorio.
- [ ] `docs/02_modelo_conceptual.md` muestra el diagrama (GitHub dibuja Mermaid).
- [ ] No existe `privado/identidades.sql` ni ningún `.xlsm` en el repositorio. Búsqueda rápida: tecla `t` en la página del repositorio y escribir `identidades`.
- [ ] *Insights → Contributors* muestra a los dos integrantes.
- [ ] Clonar el repositorio en una carpeta nueva y ejecutar `psql -U postgres -f sql/ejecutar_todo.sql`: debe funcionar sin el Excel.

## 7. Si por error se subió un archivo con nombres

Borrarlo en un commit nuevo **no basta**: sigue en el historial. Si pasó:

1. Si el repositorio es reciente: lo más simple es borrar el repositorio en GitHub (**Settings → Danger zone**), borrar la carpeta `.git` local (`rm -rf .git`), revisar el `.gitignore` y empezar de nuevo desde la sección 3.
2. Si ya hay mucho historial: usar `git filter-repo --path privado/identidades.sql --invert-paths` (se instala con `pip install git-filter-repo`) y luego `git push --force`. El compañero debe volver a clonar.

## 8. Entrega

Cuando todo esté listo:

```bash
git tag -a v1.0 -m "Entrega final Bases de Datos I"
git push origin v1.0
```

El enlace para la portada del PDF es `https://github.com/USUARIO/bd-paros-produccion`.
