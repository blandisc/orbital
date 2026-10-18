#!/usr/bin/env python3
"""Genera ios/OrbitalCore/Sources/OrbitalCore/AwardsData.swift de design/awards.json (la misma lista que lee la TV).

    python3 scripts/ios_awards.py           # escribe el archivo
    python3 scripts/ios_awards.py --check   # falla si el archivo no está al día
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "design" / "awards.json"
TARGET = ROOT / "ios" / "OrbitalCore" / "Sources" / "OrbitalCore" / "AwardsData.swift"


def swift_string(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render() -> str:
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    lines = ["// Generado de design/awards.json con scripts/ios_awards.py (ganadores comprobados contra Cinemeta: nombre y año). No editar a mano.",
             "public enum Awards {",
             "    public static let all: [AwardCollection] = ["]
    for award in data["awards"]:
        lines.append(f'        AwardCollection(id: {swift_string(award["id"])}, kind: {swift_string(award["kind"])}, winners: [')
        for w in award["winners"]:
            lines.append(f'            .init(imdb: {swift_string(w["imdb"])}, title: {swift_string(w["title"])}, year: {int(w["year"])}, awardYear: {int(w["award_year"])}),')
        lines.append("        ]),")
    lines += ["    ]", "}", ""]
    return "\n".join(lines)


def main() -> int:
    text = render()
    if "--check" in sys.argv:
        if TARGET.read_text(encoding="utf-8") != text:
            print("AwardsData.swift no está al día con design/awards.json: corre python3 scripts/ios_awards.py")
            return 1
        print("AwardsData.swift al día.")
        return 0
    TARGET.write_text(text, encoding="utf-8")
    print(f"Escrito {TARGET.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
