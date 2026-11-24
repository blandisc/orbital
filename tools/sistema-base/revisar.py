#!/usr/bin/env python3
"""Revisor común del sistema base (D1-B · DB-A, Fernando, 20 nov 2026).

Lee las reglas comunes (reglas.json, junto a este archivo) y lo propio de cada repo (sistema-base.json en la raíz
del repo): dónde buscar, excepciones con su porqué y la cuenta de lo heredado. No compila nada: lee Swift, CSS,
JS y HTML como texto, así que corre igual en la Mac, en la Lenovo y en GitHub.

Trinquete: lo que ya había el día que se conectó queda anotado en `heredado` (por regla y por archivo). La revisión
falla solo si un archivo tiene más que lo anotado (o es nuevo y tiene alguno). Cuando arreglas algo, la cuenta baja
con `--anotar`; nunca sube sin `--primera`.

Uso (desde la raíz del repo):
    python3 tools/sistema-base/revisar.py              # revisa; sale con 1 si algo nuevo rompe una regla
    python3 tools/sistema-base/revisar.py --anotar     # baja las cuentas de lo heredado a lo que hay hoy
    python3 tools/sistema-base/revisar.py --primera    # primera vez: anota todo lo que hay hoy
    python3 tools/sistema-base/revisar.py --todo       # además lista todo lo heredado, archivo:línea

Para que una línea no cuente, ponle el comentario `sistema-base: ignora <porqué>` en esa línea o en la de arriba;
para algo que se repite, una entrada en `excepciones` de sistema-base.json, siempre con su porqué.
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

# En Windows la consola de GitHub escribe en cp1252 y se caía con «✓» (Orbital, 20 nov 2026): siempre UTF-8.
for _flujo in (sys.stdout, sys.stderr):
    if hasattr(_flujo, "reconfigure"):
        _flujo.reconfigure(encoding="utf-8", errors="replace")

AQUI = Path(__file__).resolve().parent
NUM = r"(-?(?:\d+(?:\.\d+)?|\.\d+))"
IGNORA = "sistema-base: ignora"


def cargar(ruta: Path) -> dict:
    with open(ruta, encoding="utf-8") as f:
        return json.load(f)


# ---------------------------------------------------------------- extracción
def literales(linea: str, tipo: str) -> list[str]:
    """Los textos entre comillas de una línea (sin interpolaciones)."""
    if tipo == "swift":
        return [m.group(1) for m in re.finditer(r'"((?:[^"\\]|\\.)*)"', linea) if "\\(" not in m.group(1)]
    if tipo == "js":
        out = []
        for m in re.finditer(r'"((?:[^"\\]|\\.)*)"|\'((?:[^\'\\]|\\.)*)\'|`([^`$]*)`', linea):
            out.append(next(g for g in m.groups() if g is not None))
        return out
    if tipo == "html":
        out = [m.group(1) for m in re.finditer(r">([^<>]+)<", linea)]
        out += [m.group(2) for m in re.finditer(r'(aria-label|title|value|placeholder)="([^"]*)"', linea)]
        return out
    return []


def norma(texto: str) -> str:
    return re.sub(r"\s+", " ", texto).strip().rstrip(".").strip()


def a_px(valor: str, unidad: str, rem_px: float | None) -> float | None:
    """Un valor CSS en px; los rem cuentan solo si el repo dice cuánto mide su rem (`css_rem_px`)."""
    if unidad == "px":
        return float(valor)
    return float(valor) * rem_px if rem_px else None


def numeros(texto: str) -> list[float]:
    return [float(n) for n in re.findall(NUM, texto)]


SWIFT_ESPACIO = [
    re.compile(r"\.padding\(\s*" + NUM + r"\s*\)"),
    re.compile(r"\.padding\(\s*\.[A-Za-z]+\s*,\s*" + NUM + r"\s*\)"),
    re.compile(r"\.padding\(\s*\[[^\]]*\]\s*,\s*" + NUM + r"\s*\)"),
    re.compile(r"\bspacing:\s*" + NUM + r"\b"),
]
SWIFT_LETRA = re.compile(r"(?:\.system|Font\.system|\.custom\([^)]*?,)\s*\(?\s*size:\s*" + NUM)
SWIFT_MARCO = re.compile(r"\.frame\(\s*width:\s*" + NUM + r"\s*,\s*height:\s*" + NUM + r"\s*[,)]")
SWIFT_TOQUE_OK = re.compile(r"contentShape|minWidth:\s*(4[4-9]|[5-9]\d)|minHeight:\s*(4[4-9]|[5-9]\d)|DS\.Touch|touchTarget|hitTarget")
CSS_ESPACIO = re.compile(r"(?:^|;)\s*(padding|margin|gap|row-gap|column-gap)(-[a-z-]+)?\s*:\s*([^;]+);?", re.M)
CSS_LETRA = re.compile(r"font-size\s*:\s*" + NUM + r"(px|rem)\b")
CSS_TOQUE_SELECTOR = re.compile(r"button|btn|chip|pill|tab|toggle|segment|icon-button|\[role=\"?button")
CSS_TOQUE_PROP = re.compile(r"(?<![-\w])(min-height|height)\s*:\s*" + NUM + r"(px|rem)\b")


def revisar_archivo(ruta: Path, rel: str, tipo: str, reglas: dict, cuales: set[str], rem_px: float | None = None) -> list[tuple[str, int, str]]:
    """Devuelve (regla, línea, detalle) por cada falta del archivo."""
    try:
        lineas = ruta.read_text(encoding="utf-8").splitlines()
    except (UnicodeDecodeError, OSError):
        return []
    faltas: list[tuple[str, int, str]] = []
    prohibidos = {norma(p) for p in reglas["SB-1"]["prohibidos"]}
    escala = set(reglas["SB-2"]["escala"])
    if tipo in ("css", "html"):
        escala |= set(reglas["SB-2"].get("escala_web_extra", []))
    letra_min = reglas["SB-3"]["minimo"]
    toque_min = reglas["SB-4"]["minimo"]

    def ignorada(i: int) -> bool:
        return IGNORA in lineas[i] or (i > 0 and IGNORA in lineas[i - 1])

    en_comentario = False
    for i, linea in enumerate(lineas):
        s = linea.strip()
        if tipo in ("swift", "js", "css"):
            if en_comentario:
                if "*/" in s:
                    en_comentario = False
                continue
            if s.startswith("/*") and "*/" not in s:
                en_comentario = True
                continue
            if s.startswith("//") or s.startswith("*") or s.startswith("/*"):
                continue
        if ignorada(i):
            continue
        n = i + 1
        if "SB-1" in cuales and tipo in ("swift", "js", "html"):
            for lit in literales(linea, tipo):
                if norma(lit) in prohibidos:
                    faltas.append(("SB-1", n, f"«{norma(lit)}»"))
        if tipo == "swift":
            if "SB-2" in cuales:
                for rx in SWIFT_ESPACIO:
                    for m in rx.finditer(linea):
                        v = abs(float(m.group(1)))
                        if v not in escala:
                            faltas.append(("SB-2", n, f"espacio {m.group(1)}"))
            if "SB-3" in cuales:
                for m in SWIFT_LETRA.finditer(linea):
                    if float(m.group(1)) < letra_min:
                        faltas.append(("SB-3", n, f"letra {m.group(1)}"))
            if "SB-4" in cuales:
                for m in SWIFT_MARCO.finditer(linea):
                    w, h = float(m.group(1)), float(m.group(2))
                    if min(w, h) >= toque_min:
                        continue
                    antes = "\n".join(lineas[max(0, i - 10):i + 1])
                    despues = "\n".join(lineas[i:i + 4])
                    if re.search(r"\bButton\b|onTapGesture", antes) and not SWIFT_TOQUE_OK.search(despues):
                        faltas.append(("SB-4", n, f"toque {m.group(1)}×{m.group(2)}"))
        if tipo in ("css", "html") and "SB-3" in cuales:
            for m in CSS_LETRA.finditer(linea):
                v = a_px(m.group(1), m.group(2), rem_px)
                if v is not None and v < letra_min:
                    faltas.append(("SB-3", n, f"letra {m.group(1)}{m.group(2)}"))
    if tipo in ("css", "html"):
        texto = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), "\n".join(lineas), flags=re.S)
        for bloque in re.finditer(r"([^{}]+)\{([^{}]*)\}", texto):
            selector, cuerpo = bloque.group(1), bloque.group(2)
            base = texto[:bloque.start(2)].count("\n")
            for m in CSS_ESPACIO.finditer(cuerpo) if "SB-2" in cuales else []:
                n = base + cuerpo[:m.start()].count("\n") + 1
                if ignorada(n - 1):
                    continue
                valor = m.group(3)
                while re.search(r"\([^()]*\)", valor):  # lo que va dentro de calc() o var() es cuenta, no un paso
                    valor = re.sub(r"[\w-]*\([^()]*\)", "", valor)
                for v, unidad in re.findall(NUM + r"(px|rem)\b", valor):
                    px = a_px(v, unidad, rem_px)
                    if px is not None and round(abs(px), 2) not in escala:
                        faltas.append(("SB-2", n, f"{m.group(1)}{m.group(2) or ''} {v}{unidad}"))
            if "SB-4" in cuales and CSS_TOQUE_SELECTOR.search(selector):
                for m in CSS_TOQUE_PROP.finditer(cuerpo):
                    n = base + cuerpo[:m.start()].count("\n") + 1
                    px = a_px(m.group(2), m.group(3), rem_px)
                    if px is not None and px < toque_min and not ignorada(n - 1):
                        faltas.append(("SB-4", n, f"{m.group(1)} {m.group(2)}{m.group(3)} en «{selector.strip()[:40]}»"))
    return faltas


# ---------------------------------------------------------------- recorrido
def archivos(raiz: Path, fuente: dict, excluir: list[str]):
    exts = {"swift": [".swift"], "css": [".css"], "js": [".js", ".mjs", ".jsx", ".ts", ".tsx"], "html": [".html"]}[fuente["tipo"]]
    for base in fuente["rutas"]:
        p = raiz / base
        candidatos = [p] if p.is_file() else sorted(p.rglob("*")) if p.exists() else []
        for f in candidatos:
            if not f.is_file() or f.suffix not in exts:
                continue
            rel = f.relative_to(raiz).as_posix()
            if any(fnmatch.fnmatch(rel, pat) for pat in excluir + fuente.get("excluir", [])):
                continue
            yield f, rel


def exceptuada(regla: str, rel: str, detalle: str, linea: str, excepciones: list[dict]) -> bool:
    for e in excepciones:
        if e.get("regla", regla) != regla:
            continue
        if "archivo" in e and not fnmatch.fnmatch(rel, e["archivo"]):
            continue
        if "contiene" in e and e["contiene"] not in linea and e["contiene"] not in detalle:
            continue
        return True
    return False


def huella(carpeta: Path) -> str:
    h = hashlib.sha256()
    for nombre in ("reglas.json", "revisar.py"):
        h.update((carpeta / nombre).read_bytes())
    return h.hexdigest()[:12]


def avisar_si_vieja(raiz: Path) -> None:
    casa = Path(os.environ.get("SISTEMA_BASE_CASA", Path.home() / "code/interoperabilidad/sistema-base"))
    if casa.resolve() == AQUI or not (casa / "reglas.json").exists():
        return
    if huella(casa) != huella(AQUI):
        print("⚠️  La copia de tools/sistema-base/ es más vieja que la de la casa: corre "
              f"{casa}/copiar.sh {raiz}", file=sys.stderr)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--raiz", default=".", help="raíz del repo (donde está sistema-base.json)")
    ap.add_argument("--anotar", action="store_true", help="baja las cuentas de lo heredado a lo que hay hoy")
    ap.add_argument("--primera", action="store_true", help="anota todo lo que hay hoy (solo la primera vez)")
    ap.add_argument("--todo", action="store_true", help="lista también lo heredado")
    a = ap.parse_args()

    raiz = Path(a.raiz).resolve()
    reglas = cargar(AQUI / "reglas.json")
    conf_ruta = raiz / "sistema-base.json"
    conf = cargar(conf_ruta)
    avisar_si_vieja(raiz)

    cuenta: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    detalle: dict[tuple[str, str], list[str]] = defaultdict(list)
    for fuente in conf["fuentes"]:
        cuales = set(fuente.get("reglas", ["SB-1", "SB-2", "SB-3", "SB-4"]))
        for f, rel in archivos(raiz, fuente, conf.get("excluir", [])):
            lineas = f.read_text(encoding="utf-8", errors="replace").splitlines()
            for regla, n, det in revisar_archivo(f, rel, fuente["tipo"], reglas, cuales, conf.get("css_rem_px")):
                linea = lineas[n - 1] if n - 1 < len(lineas) else ""
                if exceptuada(regla, rel, det, linea, conf.get("excepciones", [])):
                    continue
                cuenta[regla][rel] += 1
                detalle[(regla, rel)].append(f"{rel}:{n}  {det}")

    for t in conf.get("tokens", []):
        # Valores de tokens que no pasan por un patrón de código (p. ej. `static let xs: CGFloat = 11`).
        regla, rel = t["regla"], t["archivo"]
        ruta = raiz / rel
        if not ruta.exists():
            continue
        minimo = {"SB-3": reglas["SB-3"]["minimo"], "SB-4": reglas["SB-4"]["minimo"]}.get(regla)
        escala = set(reglas["SB-2"]["escala"])
        for n, linea in enumerate(ruta.read_text(encoding="utf-8").splitlines(), 1):
            if IGNORA in linea or ("en_linea" in t and t["en_linea"] not in linea):
                continue
            for m in re.finditer(t["patron"], linea):
                v = float(m.group(1)) * t.get("factor", 1)
                mala = (v < minimo) if minimo is not None else (abs(v) not in escala)
                if mala and not exceptuada(regla, rel, m.group(0), linea, conf.get("excepciones", [])):
                    cuenta[regla][rel] += 1
                    detalle[(regla, rel)].append(f"{rel}:{n}  token {m.group(0).strip()}")

    heredado: dict[str, dict[str, int]] = conf.get("heredado", {})
    if a.primera or a.anotar:
        nuevo: dict[str, dict[str, int]] = {}
        for regla in ("SB-1", "SB-2", "SB-3", "SB-4"):
            antes = heredado.get(regla, {})
            hoy = cuenta.get(regla, {})
            fila = {}
            for rel in sorted(set(antes) | set(hoy)):
                v = hoy.get(rel, 0) if a.primera else min(hoy.get(rel, 0), antes.get(rel, 0))
                if v:
                    fila[rel] = v
            nuevo[regla] = fila
        conf["heredado"] = nuevo
        with open(conf_ruta, "w", encoding="utf-8") as f:
            json.dump(conf, f, ensure_ascii=False, indent=2)
            f.write("\n")
        heredado = nuevo
        total = {r: sum(v.values()) for r, v in nuevo.items()}
        print("Anotado en sistema-base.json:", ", ".join(f"{r} {t}" for r, t in total.items()))

    malas, bajaron = [], []
    for regla in ("SB-1", "SB-2", "SB-3", "SB-4"):
        hoy, antes = cuenta.get(regla, {}), heredado.get(regla, {})
        for rel in sorted(set(hoy) | set(antes)):
            h, b = hoy.get(rel, 0), antes.get(rel, 0)
            if h > b:
                malas.append((regla, rel, h, b))
            elif h < b:
                bajaron.append((regla, rel, h, b))

    print(f"Sistema base (reglas v{reglas['version']}):")
    for regla in ("SB-1", "SB-2", "SB-3", "SB-4"):
        hoy = sum(cuenta.get(regla, {}).values())
        antes = sum(heredado.get(regla, {}).values())
        print(f"  {regla} {reglas[regla]['nombre']}: {hoy} (heredado {antes})")
        if a.todo:
            for rel in sorted(cuenta.get(regla, {})):
                for d in detalle[(regla, rel)]:
                    print("      " + d)
    if bajaron and not (a.anotar or a.primera):
        print(f"✓ Bajó en {len(bajaron)} archivo(s): corre `--anotar` para que la cuenta no vuelva a subir.")
    if malas:
        print("\n✗ Algo nuevo rompe el sistema base:")
        vista = set()
        for regla, rel, h, b in malas:
            if regla not in vista:
                vista.add(regla)
                print(f"  {regla} · {reglas[regla]['porque']}")
            print(f"    {rel}: {h} (antes {b})")
            for d in detalle[(regla, rel)]:
                print("      " + d)
        print("\nArréglalo con la regla, o si es a propósito, marca la línea con "
              f"`{IGNORA} <porqué>` o agrégalo a `excepciones` de sistema-base.json con su porqué.")
        return 1
    print("✓ Nada nuevo rompe el sistema base.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
