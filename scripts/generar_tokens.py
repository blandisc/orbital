"""Los valores de diseño que comparten la TV y el iPhone salen de un solo lugar: design/tokens.json.

Escribe el bloque compartido de las dos copias, entre sus marcas («generado: inicio» … «generado: fin»):

- orbital/web/styles/tokens.css (la TV): la paleta, el espaciado, las dos esquinas, los grosores y las duraciones
  compartidas. Lo que es solo de la TV queda fuera del bloque, escrito a mano.
- ios/OrbitalCore/Sources/OrbitalCore/DesignTokens.swift (el iPhone): la paleta, los colores de las plataformas, el
  espaciado, las esquinas y las duraciones. Lo demás (papeles, medidas solo del iPhone) queda fuera, escrito a mano.

    python scripts/generar_tokens.py            # reescribe los dos bloques
    python scripts/generar_tokens.py --check    # solo revisa: sale con 1 si alguno no está al día

tests/test_generated_tokens.py corre la revisión. Solo usa la biblioteca estándar.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOKENS = ROOT / "design" / "tokens.json"
CSS = ROOT / "orbital" / "web" / "styles" / "tokens.css"
SWIFT = ROOT / "ios" / "OrbitalCore" / "Sources" / "OrbitalCore" / "DesignTokens.swift"

CSS_MARKS = ("  /* generado: inicio */\n", "  /* generado: fin */\n")
SWIFT_MARKS = ("    // generado: inicio\n", "    // generado: fin\n")

# Las duraciones de la TV que comparte con el iPhone (las demás de tokens.json › duration son las mismas: todas).
WEIGHT_NOTES = {"heavy": "la cifra grande (stat), como el .heavy del iPhone"}
DURATION_NOTES = {
    "tint": "lo lento que se ve: el color del arte, la órbita que recorre lo enfocado, la revelación al abrir un juego",
    "enter": "algo que aparece: tarjetas, textos, insignias",
}
RADIUS_NOTES = {
    "sm": "esquina chica: botones cuadrados, teclas, insignias y lo diminuto (el cursor, la batería)",
    "lg": "esquina de tarjeta: pósters, tarjetas, hojas, menús",
}


def _items(section: dict) -> list[tuple[str, object]]:
    return [(k, v) for k, v in section.items() if k != "_"]


def _num(value: float) -> str:
    """Un número como lo escribe CSS a mano: «.25», «1», «1.25» (sin cero a la izquierda ni decimales de más)."""
    text = f"{value:.4f}".rstrip("0").rstrip(".")
    return text[1:] if text.startswith("0.") else text


def _swift_num(value: float) -> str:
    return repr(float(value))


def _wrap(pieces: list[str], indent: int, width: int = 128) -> str:
    """«a, b, c» en renglones de a lo más `width` columnas; los que siguen, alineados a `indent`."""
    lines, line = [], ""
    for piece in pieces:
        if line and indent + len(line) + len(piece) + 3 > width:
            lines.append(line + ",")
            line = ""
        line = f"{line}, {piece}" if line else piece
    lines.append(line)
    return ("\n" + " " * indent).join(lines)


def css_block(tokens: dict) -> str:
    out = [CSS_MARKS[0],
           "  /* Lo de aquí hasta «generado: fin» lo escribe scripts/generar_tokens.py desde design/tokens.json (lo que comparte\n"
           "     con el iPhone): se cambia allá y se vuelve a generar, no aquí. */\n",
           "  /* Paleta: grafitos neutros (la interfaz no tiene color propio; el color lo pone el juego) */\n"]
    pad = False
    for name, value in _items(tokens["palette"]):
        if name.startswith("pad-") and not pad:
            out.append("  /* Botones de cara del mando (convención Xbox, la del GameSir y la Legion Go) */\n")
            pad = True
        out.append(f"  --palette-{name}: {value};\n")
    out += ["\n", "  /* Espaciado (múltiplos de 4 px a 16 px/rem) */\n"]
    out += [f"  --space-{n}: {_num(px / 16)}rem;\n" for n, px in _items(tokens["space"])]
    out += ["\n", "  /* Radios: rectángulos suaves, no burbujas */\n",
            "  /* Dos esquinas y la cápsula (ritmo del 5 nov 2026; T11, 10 nov: antes siete nombres para estos dos valores). Las del\n"
            "     iPhone (DS.Radius.xs … .xxl) se mapean a estas dos en design/tokens.json. */\n"]
    corners: dict[str, int] = {}
    for _, spec in _items(tokens["radius"]):
        assert isinstance(spec, dict)
        seen = corners.setdefault(spec["tv"], spec["value"])
        if seen != spec["value"]:
            raise SystemExit(f"design/tokens.json › radius: --radius-{spec['tv']} vale {seen} y {spec['value']}")
    for suffix, px in corners.items():
        note = f" /* {RADIUS_NOTES[suffix]} */" if suffix in RADIUS_NOTES else ""
        out.append(f"  --radius-{suffix}: {_num(px / 16)}rem;{note}\n")
    out += ["\n", "  /* Grosores: los del iPhone (Font.Weight), con el mismo nombre */\n"]
    for name, value in _items(tokens["weight"]):
        note = f" /* {WEIGHT_NOTES[name]} */" if name in WEIGHT_NOTES else ""
        out.append(f"  --weight-{name}: {value};{note}\n")
    out += ["\n", "  /* Duraciones que comparte con el iPhone (DS.Motion, allá en segundos) */\n"]
    for name, ms in _items(tokens["duration"]):
        note = f" /* {DURATION_NOTES[name]} */" if name in DURATION_NOTES else ""
        out.append(f"  --duration-{name}: {ms}ms;{note}\n")
    out.append(CSS_MARKS[1])
    return "".join(out)


def swift_block(tokens: dict) -> str:
    palette = _items(tokens["palette"])
    rows, row, width = [], [], 8
    for name, value in palette:  # renglones de a lo más ~120 columnas, como estaba a mano
        piece = f'"{name}": "{value}",'
        if row and width + len(piece) + 1 > 128:
            rows.append(" ".join(row))
            row, width = [], 8
        row.append(piece)
        width += len(piece) + 1
    rows.append(" ".join(row))
    lead = "        public static let hex: [String: String] = ["
    platforms = _wrap([f'"{k}": "{v}"' for k, v in _items(tokens["platforms"])], len(lead))
    space = _items(tokens["space"])
    radius = [(name, spec["value"]) for name, spec in _items(tokens["radius"]) if isinstance(spec, dict)]
    motion = ", ".join(f"{k} = {_swift_num(ms / 1000)}" for k, ms in _items(tokens["duration"]))
    return "".join([
        SWIFT_MARKS[0],
        "    // Lo de aquí hasta «generado: fin» lo escribe scripts/generar_tokens.py desde design/tokens.json (lo que comparte con la\n"
        "    // TV): se cambia allá y se vuelve a generar, no aquí.\n",
        "    /// Paleta única: los mismos valores que `orbital/web/styles/palette.json`.\n",
        "    public static let palette: [String: String] = [\n",
        *(f"        {r}\n" for r in rows),
        "    ]\n",
        "\n",
        "    /// El color de cada plataforma («otra»: Apple TV+ y las demás, plata). Igual que `platforms` en design/tokens.json.\n",
        "    public enum Platform {\n",
        f"{lead}{platforms}]\n",
        '        public static func color(_ brand: String) -> String { hex[brand] ?? hex["otra"]! }\n',
        "    }\n",
        "\n",
        f"    /// Espacio (puntos): {', '.join(str(px) for _, px in space)}.\n",
        f"    public enum Space {{ public static let {', '.join(f's{n} = {_swift_num(px)}' for n, px in space)} }}\n",
        "    /// Las esquinas (puntos); la cápsula, `pill`, vive abajo (`extension DesignTokens.Radius`).\n",
        f"    public enum Radius {{ public static let {', '.join(f'{n} = {_swift_num(v)}' for n, v in radius)} }}\n",
        "    /// Duraciones en segundos (las de la TV: `design/tokens.json`); con «Reducir movimiento» valen 0.\n",
        f"    public enum Motion {{ public static let {motion} }}\n",
        SWIFT_MARKS[1],
    ])


def splice(text: str, block: str, marks: tuple[str, str], where: Path) -> str:
    start, end = text.find(marks[0]), text.find(marks[1])
    if start < 0 or end < start:
        raise SystemExit(f"{where.relative_to(ROOT)}: no encuentro las marcas «generado: inicio» / «generado: fin»")
    return text[:start] + block + text[end + len(marks[1]):]


def expected() -> dict[Path, str]:
    tokens = json.loads(TOKENS.read_text(encoding="utf-8"))
    css = CSS.read_text(encoding="utf-8")
    swift = SWIFT.read_text(encoding="utf-8")
    return {CSS: splice(css, css_block(tokens), CSS_MARKS, CSS), SWIFT: splice(swift, swift_block(tokens), SWIFT_MARKS, SWIFT)}


def stale() -> list[Path]:
    """Los archivos cuyo bloque generado no coincide con design/tokens.json."""
    return [path for path, text in expected().items() if path.read_text(encoding="utf-8") != text]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="solo revisar; sale con 1 si algo no está al día")
    args = parser.parse_args(argv)
    if args.check:
        old = stale()
        for path in old:
            print(f"{path.relative_to(ROOT)} no está al día: corre python scripts/generar_tokens.py")
        return 1 if old else 0
    for path, text in expected().items():
        if path.read_text(encoding="utf-8") != text:
            path.write_bytes(text.encode("utf-8"))  # sin traducir los saltos de línea (en Windows también \n)
            print(f"escrito {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
