#!/usr/bin/env python3
"""
extraer_excel.py
----------------
Lee el libro SEGUIMIENTO TEMPERAS Y VINILOS Actividad.xlsm y genera los
scripts SQL de carga:

  sql/06_carga_catalogos_etl.sql   referencias, parámetros por máquina, personas (seudónimos), causas
  sql/07_carga_staging.sql         copia fila a fila de T_baseDeDatos + totales de control
  privado/identidades.sql          nombre real de cada seudónimo (NO se sube a GitHub)
  privado/mapa_personas.csv        tabla de correspondencia nombre → seudónimo (NO se sube)
  docs/reporte_etl.md              resumen de la extracción (sin nombres)

Qué hace con los datos (y qué NO hace):
  * Limpia textos: espacios sobrantes, "No aplica" → nulo, claves de subcódigo
    normalizadas (1.2D → 1.2.D), tipos de paro con formato único.
  * Reemplaza los nombres de personas por seudónimos (OPE-001, MTO-001).
  * NO corrige números ni borra filas: eso lo decide la transformación SQL
    (08_transformacion.sql), donde queda a la vista.

Uso:
    python -I etl/extraer_excel.py "datos/SEGUIMIENTO TEMPERAS Y VINILOS Actividad.xlsm"

Requisitos: Python 3.10+ y openpyxl (pip install -r etl/requirements.txt).
"""
from __future__ import annotations

import argparse
import collections
import csv
import datetime as dt
import posixpath
import re
import sys
import unicodedata
import warnings
import zipfile
from pathlib import Path

import openpyxl
from openpyxl.utils import range_boundaries

warnings.filterwarnings("ignore")  # openpyxl avisa de extensiones (slicers) que no usa

RAIZ = Path(__file__).resolve().parent.parent
LOTE = 500  # filas por INSERT

# ---------------------------------------------------------------------------
# Utilidades de texto
# ---------------------------------------------------------------------------

def sin_tildes(s: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")


def clave(s: str) -> str:
    """Clave de comparación: sin tildes, minúsculas, espacios simples, sin punto final."""
    s = sin_tildes(s).lower().replace("_", " ")
    s = re.sub(r"\s+", " ", s).strip()
    return s.rstrip(".").strip()


def limpio(v):
    """Texto sin espacios sobrantes; vacío, 'No aplica' o 'No' → None."""
    if v is None:
        return None
    if isinstance(v, str):
        v = re.sub(r"\s+", " ", v).strip()
        if v == "" or clave(v) in ("no aplica", "no"):
            return None
    return v


def numero(v):
    """Número o None. Los textos no numéricos se reportan como error."""
    if v is None or v == "":
        return None
    if isinstance(v, bool):
        raise ValueError(f"valor booleano inesperado: {v}")
    if isinstance(v, (int, float)):
        return v
    if isinstance(v, str) and v.strip() == "":
        return None
    raise ValueError(f"valor no numérico: {v!r}")


def sql(v) -> str:
    """Literal SQL."""
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        if isinstance(v, float) and v.is_integer():
            return str(int(v))
        return repr(round(v, 6)) if isinstance(v, float) else str(v)
    if isinstance(v, (dt.date, dt.datetime)):
        return f"DATE '{v:%Y-%m-%d}'"
    return "'" + str(v).replace("'", "''") + "'"


# ---------------------------------------------------------------------------
# Normalizaciones de negocio
# ---------------------------------------------------------------------------

RE_SUB = re.compile(r"^\s*(\d{1,2})\.(\d{1,2})(?:\.(\d)|\.?([A-Za-z]))?(?=[\s.]|$)")

# Casos donde la clave del histórico no coincide con el concepto del catálogo vigente.
# El texto "1.7A CAMBIO DE ROSCADORES" (catálogo viejo) corresponde a 1.7.B Roscadores.
SUB_EXCEPCIONES = {
    "1.7a cambio de roscadores": "1.7.B",
}


def subcodigo(v):
    """'1.2D  RETENEDORES' → '1.2.D'; '1.4.3 Sensor' → '1.4.C'; 'Sin especificar' → None."""
    v = limpio(v)
    if v is None or clave(v) == "sin especificar":
        return None
    if clave(v) in SUB_EXCEPCIONES:
        return SUB_EXCEPCIONES[clave(v)]
    m = RE_SUB.match(v)
    if not m:
        raise ValueError(f"subcódigo no reconocido: {v!r}")
    a, b, num, letra = m.groups()
    if num:                              # 1.4.3 = tercer componente = C
        letra = chr(64 + int(num))
    return f"{a}.{b}" + (f".{letra.upper()}" if letra else "")


def turno(v):
    if v is None or (isinstance(v, str) and v.strip() == ""):
        return "No registrado"
    v = limpio(v)
    return "Sin turno" if v is None else v


TIPOS_VIGENTES = {
    1: "Falla del sistema electromecánico y/o de control",
    2: "Espera de soporte de mantenimiento",
    3: "Novedad en los sistemas de potencia (Aire, energía, vapor)",
    4: "Mantenimiento preventivo",
    5: "Ajuste operativo",
    6: "Limpieza por derrame operativo",
    7: "Alistamiento de máquina / Cambio de referencia",
    8: "Capacitación / Reunión",
    9: "Falta de operario",
    10: "Paro por ventaja/evacuación",
    11: "Reproceso",
    12: "Materia prima defectuosa o material de empaque no conforme",
    13: "En espera por el aval del laboratorio de microbiología",
    14: "Falta de materia prima",
    15: "Cambio de insumos (Roscadores, O'ring, Etiquetas)",
    16: "Alimentación y aseo de la zona de trabajo y la máquina",
    17: "Pausa activa",
    18: "Paro de máquina por ventas",
}
TIPOS_ANTIGUOS = {
    "3. AJUSTE ELECTRICO O DE SERVICIOS (AIRE, CALDERA, GAS)",
    "4. AJUSTE DE OPERACIÓN",
    "5. AISLAMIENTO/CAMBIO DE PRODUCTO",
    "6. FALTA DE MATERIALES O MATERIAS PRIMAS",
    "9. FALTA DE PROGRAMACIÓN (PLANEACIÓN)",
    "10. PARO POR MATERIA PRIMA O MATERIAL DE EMPAQUE NO CONFORME",
    "11. LIMPIEZA NO PROGRAMADA",
    "15. APROBACION DE LABORATORIO (MICROBIOLOGIA)",
    "16. PARO POR PROCESO ANTERIOR",
    "17. PARO DE MAQUINA",
}


def tipo_paro(v):
    v = limpio(v)
    if v is None:
        return None
    m = re.match(r"^\[(\d{1,2})\]", v)
    if m:
        n = int(m.group(1))
        if n == 19:                      # [19] No aplica
            return None
        return f"[{n:02d}] {TIPOS_VIGENTES[n]}"
    m = re.match(r"^(\d{1,2})\.\s*(.+)$", v)
    if m:
        texto = f"{int(m.group(1))}. {m.group(2).strip()}"
        if texto in TIPOS_ANTIGUOS:
            return texto
    raise ValueError(f"tipo de paro no reconocido: {v!r}")


# Erratas evidentes en las causas (no son datos personales).
CAUSA_ERRATAS = {
    "faltade adictivo y/o tinta": "falta de adictivo y/o tinta",
    "no se programos el fin de semana por demanda": "no se programo el fin de semana por demanda",
    "cambio de probedor de energia en la subestacion": "cambio de proveedor de energia en la subestacion",
    "se fue la luz": "se fue la luz / agua",
}


def clave_causa(v: str) -> str:
    k = clave(v)
    return CAUSA_ERRATAS.get(k, k)


# Referencias: espacio uniforme antes de "col" y una errata evidente.
REF_ERRATAS = {"Alocdor 22cc (6 col)": "Alocolor 22cc (6 col)"}


def referencia(v):
    v = limpio(v)
    if v is None:
        return None
    v = re.sub(r"\((\d+)\s*col\)", r"(\1 col)", v)
    return REF_ERRATAS.get(v, v)


def area_agente(v):
    v = limpio(v)
    if v is None:
        return None
    v = v.replace("_", " ")
    return v[0].upper() + v[1:].lower()


# ---------------------------------------------------------------------------
# Lectura del libro
# ---------------------------------------------------------------------------

def mapa_tablas(path: Path) -> dict[str, tuple[str, str]]:
    """{nombre_tabla: (hoja, rango)} leyendo el XML del .xlsm (más rápido y fiable que openpyxl)."""
    with zipfile.ZipFile(path) as z:
        wb = z.read("xl/workbook.xml").decode("utf8")
        rels = z.read("xl/_rels/workbook.xml.rels").decode("utf8")
        rid_a_archivo = dict(re.findall(r'<Relationship [^>]*Id="([^"]+)"[^>]*Target="([^"]+)"', rels))
        rid_a_archivo.update({b: a for a, b in re.findall(r'<Relationship [^>]*Target="([^"]+)"[^>]*Id="([^"]+)"', rels)})
        hojas = {}
        for tag in re.findall(r"<sheet [^>]*/>", wb):
            nombre = re.search(r'name="([^"]+)"', tag).group(1)
            rid = re.search(r'r:id="([^"]+)"', tag).group(1)
            destino = rid_a_archivo[rid].lstrip("/")
            hojas[posixpath.normpath(posixpath.join("xl", destino) if not destino.startswith("xl/") else destino)] = (
                nombre.replace("&amp;", "&"))
        tablas = {}
        for hoja_xml, nombre_hoja in hojas.items():
            rel = posixpath.join(posixpath.dirname(hoja_xml), "_rels", posixpath.basename(hoja_xml) + ".rels")
            if rel not in z.namelist():
                continue
            for destino in re.findall(r'Target="([^"]*tables/[^"]+)"', z.read(rel).decode("utf8")):
                xml_tabla = posixpath.normpath(posixpath.join(posixpath.dirname(hoja_xml), destino))
                t = z.read(xml_tabla).decode("utf8")
                nombre = re.search(r'displayName="([^"]+)"', t).group(1)
                ref = re.search(r' ref="([^"]+)"', t).group(1)
                tablas[nombre] = (nombre_hoja, ref)
    return tablas


def leer_tabla(wb, tablas, nombre) -> list[dict]:
    """Filas de una tabla de Excel como diccionarios {encabezado: valor}, con el número de fila."""
    hoja, ref = tablas[nombre]
    c1, r1, c2, r2 = range_boundaries(ref)
    filas = list(wb[hoja].iter_rows(min_row=r1, max_row=r2, min_col=c1, max_col=c2, values_only=True))
    enc = [re.sub(r"\s+", " ", str(h).replace("_x000a_", " ")).strip() for h in filas[0]]
    salida = []
    for i, f in enumerate(filas[1:], start=r1 + 1):
        d = dict(zip(enc, f))
        d["__fila"] = i
        salida.append(d)
    return salida


# ---------------------------------------------------------------------------
# Personas y seudónimos
# ---------------------------------------------------------------------------

class Personas:
    """Une variantes de un mismo nombre y asigna seudónimos estables por rol."""

    def __init__(self, alias_csv: Path):
        self.alias: dict[str, str] = {}
        if alias_csv.exists():
            with alias_csv.open(encoding="utf8") as f:
                for fila in csv.DictReader(f):
                    self.alias[clave(fila["variante"])] = fila["canonico"].strip()
        self.nombres: dict[str, str] = {}       # clave canónica → nombre a mostrar
        self.rol: dict[str, str] = {}
        self.variantes: dict[str, set] = collections.defaultdict(set)
        self.codigo: dict[str, str] = {}

    def canon(self, nombre: str) -> str:
        return clave(self.alias.get(clave(nombre), nombre))

    def agregar(self, nombre, rol: str) -> str | None:
        nombre = limpio(nombre)
        if nombre is None:
            return None
        k = self.canon(nombre)
        self.variantes[k].add(nombre)
        self.nombres.setdefault(k, self.alias.get(clave(nombre), nombre))
        # Prioridad de rol: MTO > OPE > OTR (quien figura en la lista de mantenimiento es MTO).
        orden = {"MTO": 3, "OPE": 2, "OTR": 1}
        if orden[rol] > orden.get(self.rol.get(k), 0):
            self.rol[k] = rol
        return k

    def asignar_codigos(self):
        for rol in ("OPE", "MTO", "OTR"):
            ks = sorted(k for k, r in self.rol.items() if r == rol)
            for i, k in enumerate(ks, start=1):
                self.codigo[k] = f"{rol}-{i:03d}"

    def seudonimo(self, nombre):
        nombre = limpio(nombre)
        return None if nombre is None else self.codigo[self.canon(nombre)]

    def anonimizar_texto(self, texto):
        """Reemplaza nombres conocidos dentro de texto libre por su seudónimo."""
        if texto is None:
            return None, 0
        n = 0
        # Del nombre más largo al más corto, para que "Pedro P." se reemplace antes que "Pedro" (ejemplo ficticio).
        todas = sorted(((v, k) for k, vs in self.variantes.items() for v in vs), key=lambda x: -len(x[0]))
        for v, k in todas:
            partes = v.split()
            if len(partes) > 1:
                patron = re.compile(r"\b" + r"\s+".join(map(re.escape, partes)) + r"(?!\w)", re.I)
            else:
                patron = re.compile(r"\b" + re.escape(v) + r"\b")   # nombre suelto: sensible a mayúsculas
            texto, c = patron.subn(self.codigo[k], texto)
            n += c
        return texto, n


# ---------------------------------------------------------------------------
# Programa principal
# ---------------------------------------------------------------------------

COLS_BASE = {
    "fecha": "Fecha", "mes": "Mes", "anio": "Año", "maquina": "Maquina", "operario": "Operario",
    "referencia": "Referencia", "pacas": "Pacas producidas", "horas_trab": "Horas trabajadas",
    "turno": "Turno", "horas_no_trab": "Horas no trabajadas", "tipo_paro": "Tipo de paro",
    "causa": "Observaciones de paro", "sub1": "Sub Codigo de paro 1", "sub3": "Subcodigo 3",
    "sub5": "Subcodigo 5", "area5": "Área involucrada en subcodigo 5",
    "personal5": "Personal involucrado", "tiempo_paro": "Tiempo de Paro", "obs": "Observaciones",
}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("excel", type=Path, help="ruta del .xlsm")
    ap.add_argument("--repo", type=Path, default=RAIZ, help="raíz del repositorio (por defecto, la del script)")
    args = ap.parse_args()

    repo: Path = args.repo
    privado = repo / "privado"
    privado.mkdir(exist_ok=True)

    print(f"Leyendo estructura de {args.excel.name} ...")
    tablas = mapa_tablas(args.excel)
    faltan = [t for t in ("T_baseDeDatos", "Tabla8", "Tabla14", "Tabla15", "Tabla16", "Tabla11",
                          "Tabla_Operarios", "personalDeMantenimiento27") if t not in tablas]
    if faltan:
        sys.exit(f"ERROR: el libro no tiene las tablas {faltan}")

    wb = openpyxl.load_workbook(args.excel, read_only=True, data_only=True)

    print("Leyendo la base histórica (T_baseDeDatos) ...")
    base = leer_tabla(wb, tablas, "T_baseDeDatos")
    cols = set(base[0].keys())
    faltan = [c for c in list(COLS_BASE.values()) + [f"Codigo de paro {i}" for i in range(1, 19)] if c not in cols]
    if faltan:
        sys.exit(f"ERROR: faltan columnas en T_baseDeDatos: {faltan}")
    base = [f for f in base if f["Fecha"] is not None]

    print("Leyendo catálogos ...")
    ref_cat = []
    for t in ("Tabla8", "Tabla14", "Tabla15", "Tabla16"):
        ref_cat += leer_tabla(wb, tablas, t)
    operarios_cat = [f["Operarios"] for f in leer_tabla(wb, tablas, "Tabla_Operarios")]
    mto_cat = [f["PERSONAL DE MANTENIMIENTO"] for f in leer_tabla(wb, tablas, "personalDeMantenimiento27")]
    causas_cat = [f["los porque porque"] for f in leer_tabla(wb, tablas, "Tabla11")]

    # --- Totales de control sobre el dato CRUDO ------------------------------
    def suma(col):
        return sum(numero(f[col]) or 0 for f in base)

    control = {
        "filas": len(base),
        "pacas": suma("Pacas producidas"),
        "horas_trabajadas": suma("Horas trabajadas"),
        "horas_no_trabajadas": suma("Horas no trabajadas"),
        "tiempo_paro_horas": suma("Tiempo de Paro"),
        "fecha_min": int(min(f["Fecha"] for f in base).strftime("%Y%m%d")),
        "fecha_max": int(max(f["Fecha"] for f in base).strftime("%Y%m%d")),
        "filas_duplicadas_exactas": sum(v - 1 for v in collections.Counter(
            tuple(v for k, v in f.items() if k != "__fila") for f in base).values() if v > 1),
    }
    for i in range(1, 19):
        control[f"minutos_codigo_{i:02d}"] = suma(f"Codigo de paro {i}")
    ht, tp = control["horas_trabajadas"], control["tiempo_paro_horas"]
    control["pct_productividad_excel"] = round((ht - tp) / ht * 100, 4)

    # --- Personas ------------------------------------------------------------
    personas = Personas(privado / "alias_personas.csv")
    for n in mto_cat:
        personas.agregar(n, "MTO")
    for n in operarios_cat:
        personas.agregar(n, "OPE")
    for f in base:
        personas.agregar(f["Operario"], "OPE")
    for f in base:
        area = area_agente(f["Área involucrada en subcodigo 5"])
        rol = {"Personal de mantenimiento": "MTO", "Operarios": "OPE"}.get(area, "OTR")
        personas.agregar(f["Personal involucrado"], rol)
    personas.asignar_codigos()

    # --- Referencias y parámetros por máquina ----------------------------------
    mr = {}   # (maquina, referencia) → parámetros
    for f in ref_cat:
        ref = referencia(f.get("Nombre de referencia"))
        maq = limpio(f.get("maquina"))
        if ref is None or maq is None:
            continue
        def pos(v):
            v = numero(v) if not isinstance(v, str) else None
            return int(v) if v and v > 0 else None
        mr[(maq, ref)] = dict(colores=pos(f.get("# colores")), display=pos(f.get("Display")),
                             pacas=pos(f.get("Pacas")), en_catalogo=True)
        # "Unidades * paca" no se carga: es colores × display × pacas (atributo derivado).
        unidades = pos(f.get("Unidades * paca"))
        if unidades and None not in (mr[(maq, ref)]["colores"], mr[(maq, ref)]["display"], mr[(maq, ref)]["pacas"]):
            if unidades != mr[(maq, ref)]["colores"] * mr[(maq, ref)]["display"] * mr[(maq, ref)]["pacas"]:
                print(f"AVISO: {maq} / {ref}: unidades por paca {unidades} no es colores × display × pacas")
    for f in base:
        ref = referencia(f["Referencia"])
        if ref is not None:
            mr.setdefault((f["Maquina"], ref), dict(colores=None, display=None, pacas=None,
                                                    en_catalogo=False))

    # --- Causas -----------------------------------------------------------------
    causas = {}
    for c in causas_cat:
        c = limpio(c)
        if c:
            causas.setdefault(clave_causa(c), c)
    variantes_causa = collections.Counter(limpio(f["Observaciones de paro"]) for f in base)
    for c, _ in variantes_causa.most_common():
        if c:
            causas.setdefault(clave_causa(c), c[0].upper() + c[1:].lower())

    # --- Filas de staging -------------------------------------------------------
    staging, errores, nombres_en_texto = [], [], 0
    for f in base:
        try:
            obs, n = personas.anonimizar_texto(limpio(f["Observaciones"]))
            nombres_en_texto += n
            causa = limpio(f["Observaciones de paro"])
            fila = {
                "fila_excel": f["__fila"],
                "fecha": f["Fecha"].date() if isinstance(f["Fecha"], dt.datetime) else f["Fecha"],
                "mes_texto": limpio(f["Mes"]),
                "anio_texto": limpio(str(f["Año"])) if f["Año"] is not None else None,
                "maquina": limpio(f["Maquina"]),
                "operario": personas.seudonimo(f["Operario"]),
                "referencia": referencia(f["Referencia"]),
                "turno": turno(f["Turno"]),
                "pacas": numero(f["Pacas producidas"]),
                "horas_trab": numero(f["Horas trabajadas"]),
                "horas_no_trab": numero(f["Horas no trabajadas"]),
                "tipo_paro": tipo_paro(f["Tipo de paro"]),
                "causa": causas[clave_causa(causa)] if causa else None,
                "sub1": subcodigo(f["Sub Codigo de paro 1"]),
                "sub3": subcodigo(f["Subcodigo 3"]),
                "sub5": subcodigo(f["Subcodigo 5"]),
                "area5": area_agente(f["Área involucrada en subcodigo 5"]),
                "personal5": personas.seudonimo(f["Personal involucrado"]),
                "tiempo_paro_h": numero(f["Tiempo de Paro"]),
                "observaciones": obs,
            }
            for i in range(1, 19):
                fila[f"m{i}"] = numero(f[f"Codigo de paro {i}"])
            staging.append(fila)
        except (ValueError, KeyError) as e:
            errores.append(f"fila {f['__fila']}: {e}")
    if errores:
        print("\n".join(errores[:30]))
        sys.exit(f"ERROR: {len(errores)} filas con valores no reconocidos. Revise las reglas de normalización.")

    # --- Escritura: catálogos ETL ----------------------------------------------
    sql_dir = repo / "sql"
    with (sql_dir / "06_carga_catalogos_etl.sql").open("w", encoding="utf8", newline="\n") as out:
        out.write("-- GENERADO POR etl/extraer_excel.py. No editar a mano.\n")
        out.write(f"-- Origen: {args.excel.name}\n\n")  # sin fecha: misma entrada → mismo archivo (diff limpio en git)
        out.write("SET search_path TO paros, public;\n\n")

        refs = sorted({r for _, r in mr})
        out.write(f"-- Referencias ({len(refs)})\nINSERT INTO paros.referencia (nombre) VALUES\n")
        out.write(",\n".join(f"    ({sql(r)})" for r in refs) + ";\n\n")

        out.write(f"-- Parámetros por máquina y referencia ({len(mr)})\n")
        out.write("INSERT INTO paros.maquina_referencia (id_maquina, id_referencia, num_colores, "
                  "unidades_por_display, displays_por_paca, en_catalogo)\n"
                  "SELECT m.id_maquina, r.id_referencia, v.colores, v.display, v.pacas, v.cat\nFROM (VALUES\n")
        out.write(",\n".join(
            f"    ({sql(maq)}, {sql(ref)}, {sql(p['colores'])}::smallint, {sql(p['display'])}::smallint, "
            f"{sql(p['pacas'])}::smallint, {sql(p['en_catalogo'])})"
            for (maq, ref), p in sorted(mr.items())))
        out.write("\n) AS v(maquina, referencia, colores, display, pacas, cat)\n"
                  "JOIN paros.maquina m ON m.nombre = v.maquina\n"
                  "JOIN paros.referencia r ON r.nombre = v.referencia;\n\n")

        out.write(f"-- Personas seudonimizadas ({len(personas.codigo)}). Los nombres están en privado/identidades.sql\n")
        out.write("INSERT INTO paros.persona (codigo, rol) VALUES\n")
        out.write(",\n".join(f"    ({sql(c)}, {sql(c[:3])})" for c in sorted(personas.codigo.values())) + ";\n\n")

        out.write(f"-- Causas de horas no trabajadas ({len(causas)})\nINSERT INTO paros.causa_paro (descripcion) VALUES\n")
        out.write(",\n".join(f"    ({sql(c)})" for c in sorted(causas.values())) + ";\n")

    # --- Escritura: staging ------------------------------------------------------
    columnas = list(staging[0].keys())
    with (sql_dir / "07_carga_staging.sql").open("w", encoding="utf8", newline="\n") as out:
        out.write("-- GENERADO POR etl/extraer_excel.py. No editar a mano.\n")
        out.write(f"-- {len(staging)} filas de T_baseDeDatos. Personas seudonimizadas.\n\n")
        out.write("TRUNCATE stg.base_excel, stg.control_excel, stg.rechazo;\n\n")
        for i in range(0, len(staging), LOTE):
            out.write(f"INSERT INTO stg.base_excel ({', '.join(columnas)}) VALUES\n")
            out.write(",\n".join("(" + ", ".join(sql(f[c]) for c in columnas) + ")" for f in staging[i:i + LOTE]))
            out.write(";\n\n")
        out.write("-- Totales de control calculados sobre el Excel crudo\nINSERT INTO stg.control_excel (metrica, valor) VALUES\n")
        out.write(",\n".join(f"    ({sql(k)}, {sql(v)})" for k, v in control.items()) + ";\n")

    # --- Escritura: datos privados ---------------------------------------------
    with (privado / "identidades.sql").open("w", encoding="utf8", newline="\n") as out:
        out.write("-- CONFIDENCIAL. Generado por el ETL. Este archivo está en .gitignore.\n")
        out.write("INSERT INTO privado.persona_identidad (id_persona, nombre_completo)\n"
                  "SELECT p.id_persona, v.nombre FROM (VALUES\n")
        out.write(",\n".join(f"    ({sql(personas.codigo[k])}, {sql(personas.nombres[k])})"
                             for k in sorted(personas.codigo, key=personas.codigo.get)))
        out.write("\n) AS v(codigo, nombre)\nJOIN paros.persona p ON p.codigo = v.codigo;\n")
    with (privado / "mapa_personas.csv").open("w", encoding="utf8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["codigo", "rol", "nombre", "variantes_en_excel"])
        for k in sorted(personas.codigo, key=personas.codigo.get):
            w.writerow([personas.codigo[k], personas.rol[k], personas.nombres[k], " | ".join(sorted(personas.variantes[k]))])

    # --- Reporte ---------------------------------------------------------------
    roles = collections.Counter(personas.rol.values())
    with (repo / "docs" / "reporte_etl.md").open("w", encoding="utf8", newline="\n") as out:
        out.write("# Reporte de extracción del Excel\n\n")
        out.write(f"Generado por `etl/extraer_excel.py` a partir de `{args.excel.name}`.\n\n")
        out.write("| Concepto | Valor |\n| --- | --- |\n")
        out.write(f"| Filas leídas de T_baseDeDatos | {len(base):,} |\n")
        out.write(f"| Referencias distintas | {len(refs)} |\n")
        out.write(f"| Combinaciones máquina–referencia | {len(mr)} ({sum(1 for p in mr.values() if not p['en_catalogo'])} solo en el histórico) |\n")
        out.write(f"| Personas | {len(personas.codigo)} (OPE {roles['OPE']}, MTO {roles['MTO']}, OTR {roles['OTR']}) |\n")
        out.write(f"| Causas tras unificar mayúsculas y erratas | {len(causas)} (de {len([c for c in variantes_causa if c])} textos) |\n")
        out.write(f"| Nombres reemplazados dentro de observaciones | {nombres_en_texto} |\n\n")
        out.write("## Totales de control (Excel crudo)\n\n| Métrica | Valor |\n| --- | --- |\n")
        for k, v in control.items():
            if k.startswith("fecha"):
                out.write(f"| {k} | {v} |\n")
            else:
                out.write(f"| {k} | {v:,} |\n" if isinstance(v, int) else f"| {k} | {v:,.4f} |\n")

    print(f"Listo: {len(staging)} filas, {len(personas.codigo)} personas, {len(refs)} referencias.")
    print("Archivos: sql/06_carga_catalogos_etl.sql, sql/07_carga_staging.sql, privado/identidades.sql, docs/reporte_etl.md")


if __name__ == "__main__":
    main()
