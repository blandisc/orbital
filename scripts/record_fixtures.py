"""Graba respuestas reales del catálogo público de Stremio (Cinemeta) para las pruebas.

Solo Cinemeta: es público y no lleva claves. Nunca grabes respuestas de addons con Real-Debrid
(sus URLs llevan tu clave). Se recortan para que los archivos sean chicos.

    python scripts/record_fixtures.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from orbital.library.cinemeta import Cinemeta  # noqa: E402

OUT = Path(__file__).resolve().parents[1] / "tests" / "fixtures" / "cinemeta"
KEEP_META = ("id", "type", "name", "year", "releaseInfo", "description", "genres", "imdbRating", "runtime",
             "poster", "background", "logo", "cast", "director", "writer", "links", "trailerStreams")
KEEP_VIDEO = ("id", "season", "episode", "title", "name", "released", "thumbnail", "overview")


def trim_meta(meta: dict, max_videos: int = 40) -> dict:
    out = {k: meta[k] for k in KEEP_META if k in meta}
    if "videos" in meta:
        out["videos"] = [{k: v[k] for k in KEEP_VIDEO if k in v} for v in meta["videos"][:max_videos]]
    return out


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    client = Cinemeta()
    files = {
        "search_movie_dune.json": [trim_meta(m) for m in client.search("movie", "dune")[:8]],
        "search_series_dune.json": [trim_meta(m) for m in client.search("series", "dune")[:8]],
        "meta_series_tt0386676.json": trim_meta(client.meta("series", "tt0386676")),  # The Office
        "meta_movie_tt0816692.json": trim_meta(client.meta("movie", "tt0816692")),  # Interstellar
    }
    for name, data in files.items():
        (OUT / name).write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
        print("grabado", name)


if __name__ == "__main__":
    main()
