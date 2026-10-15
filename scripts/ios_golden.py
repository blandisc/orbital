"""Valores de referencia para las pruebas de OrbitalCore (Swift): salen de las funciones de Python de Orbital.

    python scripts/ios_golden.py

Escribe tests/fixtures/ios/*.json. Si cambia la lógica de Python, se regeneran y las pruebas de Swift
deben seguir dando lo mismo (o se cambia a propósito en los dos lados).
"""

from __future__ import annotations

import base64
import json
import zlib
from pathlib import Path

from orbital.library import cinemeta, localize, streams, stremio_api, tmdb, trakt

OUT = Path(__file__).resolve().parent.parent / "tests" / "fixtures" / "ios"
NOW = 1_760_000_000.0  # 2025-10-09T08:53:20Z: fijo, para que el resultado no dependa del reloj


def write(name: str, data) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / f"{name}.json").write_text(json.dumps(data, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")


def zlib_cases() -> list[dict]:
    blobs = [b"", b"a", bytes(range(256)), b"hello hello hello hello", bytes([0b10100101] * 40), b"\x00" * 3000]
    return [{"raw_b64": base64.b64encode(b).decode(), "zlib_b64": base64.b64encode(zlib.compress(b)).decode(),
             "zlib0_b64": base64.b64encode(zlib.compress(b, 0)).decode(),
             "zlib9_b64": base64.b64encode(zlib.compress(b, 9)).decode()} for b in blobs]


def watched_cases() -> list[dict]:
    ids = [f"tt0386676:1:{i}" for i in range(1, 11)] + [f"tt0386676:2:{i}" for i in range(1, 9)]
    cases = []
    for seen in ([], [ids[0]], [ids[2], ids[5]], ids[:10], [ids[17]], [ids[1], ids[16]]):
        encoded = stremio_api.encode_watched(set(seen), ids)
        cases.append({"video_ids": ids, "seen": sorted(seen), "encoded": encoded,
                      "parsed": sorted(stremio_api.parse_watched(encoded, ids)) if encoded else []})
    # El catálogo cambió de largo después de marcar: el ancla alinea.
    shifted = ["tt0386676:0:1"] + ids
    encoded = stremio_api.encode_watched({ids[2]}, ids)
    cases.append({"video_ids": shifted, "seen": [], "encoded": encoded, "parsed": sorted(stremio_api.parse_watched(encoded, shifted))})
    return cases


def progress_cases() -> list[dict]:
    ids = ["tt1:1:1", "tt1:1:2", "tt1:1:3"]
    base = {"meta_id": "tt1", "kind": "series", "name": "Serie Original", "poster": "https://p/x.jpg", "now": NOW, "video_ids": ids}
    existing = stremio_api.with_progress(None, video_id="tt1:1:1", position=60, duration=3000, watched=60, next_video="tt1:1:2", **base)
    runs = [
        dict(raw=None, video_id="tt1:1:1", position=600.5, duration=3000, watched=120, next_video="tt1:1:2"),
        dict(raw=None, video_id="tt1:1:1", position=2750, duration=3000, watched=2700, next_video="tt1:1:2"),
        dict(raw=None, video_id="tt1:1:3", position=2800, duration=3000, watched=2800, next_video=None),
        dict(raw=existing, video_id="tt1:1:1", position=900, duration=3000, watched=30, next_video="tt1:1:2"),
        dict(raw=existing, video_id="tt1:1:2", position=10, duration=3000, watched=10, next_video="tt1:1:3"),
    ]
    out = []
    for run in runs:
        raw = run.pop("raw")
        result = stremio_api.with_progress(raw, **run, **base)
        out.append({"raw": raw, "args": {**run, **{k: v for k, v in base.items() if k != "video_ids"}, "video_ids": ids}, "result": result})
    return out


def resume_cases() -> list[dict]:
    raw = {"state": {"video_id": "tt1:1:2", "timeOffset": 600000, "duration": 3000000}}
    done = {"state": {"video_id": "tt1:1:2", "timeOffset": 2800000, "duration": 3000000}}
    return [{"raw": r, "video_id": v, "seconds": stremio_api.resume_seconds(r, v)}
            for r, v in ((raw, "tt1:1:2"), (raw, "tt1:1:3"), (done, "tt1:1:2"), (None, "x"), ({"state": "raro"}, "x"))]


def toggle_cases() -> list[dict]:
    args = dict(meta_id="tt9", kind="movie", name="Peli", poster=None, now=NOW)
    added = stremio_api.library_toggled(None, add=True, **args)
    return [{"raw": None, "add": True, "args": args, "result": added},
            {"raw": added, "add": False, "args": args, "result": stremio_api.library_toggled(added, add=False, **args)},
            {"raw": added, "now": NOW, "result": stremio_api.dismissed({**added, "state": {"timeOffset": 5000}}, NOW),
             "dismiss_input": {**added, "state": {"timeOffset": 5000}}}]


def parse_item_cases() -> list[dict]:
    raws = [
        {"_id": "tt1", "name": "Uno", "type": "series", "poster": "http://p", "state": {"video_id": "tt1:2:5", "timeOffset": 1000, "duration": 4000, "lastWatched": "2025-01-02T03:04:05.000Z"}},
        {"_id": "tt2", "name": 1917, "type": "movie", "state": {}},
        {"_id": "tt3", "name": "Quitada", "type": "movie", "removed": True, "temp": False},
        {"_id": "tt4", "name": "Temp", "type": "movie", "removed": True, "temp": True, "state": {"video_id": "tt4", "timeOffset": 5}},
        {"_id": "kitsu:1", "name": "Anime", "type": "series", "state": {"video_id": "kitsu:1:7", "timeOffset": 1, "duration": 0}},
        {"_id": "", "name": "sin id"},
        {"_id": "other", "name": "Otro", "type": "other", "state": {"timeOffset": 10}},
    ]
    out = []
    for raw in raws:
        w = stremio_api.parse_item(raw)
        out.append({"raw": raw, "result": None if w is None else {
            "id": w.id, "type": w.type, "name": w.name, "poster": w.poster, "video_id": w.video_id, "time_offset": w.time_offset,
            "duration": w.duration, "last_watched": w.last_watched, "in_continue": w.in_continue, "in_library": w.in_library,
            "progress": w.progress, "season": w.episode[0], "episode": w.episode[1]}})
    return out


SAMPLE_STREAMS = [
    {"name": "Torrentio\n4k DV | HDR", "title": "Dune.Part.Two.2024.2160p.UHD.BluRay.REMUX.DV.HDR10.HEVC.TrueHD.Atmos-FraMeSToR\n👤 120 💾 58.4 GB ⚙️ ThePirateBay\nMulti Audio / 🇬🇧 / 🇪🇸", "url": "https://rd.example/resolve/realdebrid/KEY/a"},
    {"name": "Torrentio\n1080p [RD+]", "title": "Dune Part Two 2024 1080p WEB-DL x265 Latino\n👤 300 💾 2,1 GB ⚙️ YTS\n🇲🇽", "url": "https://rd.example/resolve/realdebrid/KEY/b"},
    {"name": "Torrentio\n720p [RD download]", "title": "Dune.Part.Two.2024.720p.HDCAM\n👤 12 💾 900 MB", "url": "https://rd.example/resolve/realdebrid/KEY/c"},
    {"name": "Torrentio\n1080p", "title": "Dune 2024 1080p BluRay x264 DTS 5.1\n👤 5 💾 1.234,5 MB", "infoHash": "abcdef0123456789abcdef0123456789abcdef01", "fileIdx": 2},
    {"name": "Otro\n4K", "description": "Show S01E01 2160p WEB-DL HDR10+ DDP5.1 Atmos\n💾 3.4 GB", "url": "https://x.example/v.mkv", "behaviorHints": {"bingeGroup": "otro-4k", "filename": "Show.S01E01.2160p.mkv"}},
]


def streams_cases() -> dict:
    prefs = [("es", "1080p"), ("en", "4K"), ("en", "1080p")]
    parsed = []
    for i, s in enumerate(SAMPLE_STREAMS):
        src = streams.parse(s, "Torrentio Lite", "https://torrentio.example/KEY/manifest.json", i)
        parsed.append({"stream": s, "result": {
            "addon": src.addon, "resolution": src.resolution, "hdr": src.hdr, "size": src.size, "seeders": src.seeders,
            "site": src.site, "cached": src.cached, "debrid": src.debrid, "languages": src.languages, "release": src.release,
            "tags": src.tags, "binge": src.binge}})
    ranked = []
    for audio, quality in prefs:
        sources = [streams.parse(s, "Torrentio", "https://t.example/manifest.json", i) for i, s in enumerate(SAMPLE_STREAMS)]
        for kind in ("movie", "series"):
            order = streams.rank(sources, streams.Preferences(audio=audio, quality=quality), kind)
            ranked.append({"audio": audio, "quality": quality, "kind": kind,
                           "order": [s.index for s in order], "scores": {str(s.index): s.score for s in order}})
    hashes = [{"addon_url": "https://t.example/manifest.json", "stream": s, "index": streams.stable_index("https://t.example/manifest.json", s)} for s in SAMPLE_STREAMS]
    sizes = [{"text": t, "value": streams._size_number(t)} for t in ("1,5", "1.5", "1,234.5", "1.234,5", "0,750", "1.234.567", "abc", "2,5")]
    return {"parsed": parsed, "ranked": ranked, "hashes": hashes, "sizes": sizes}


def cinemeta_cases() -> dict:
    fx = Path(__file__).resolve().parent.parent / "tests" / "fixtures" / "cinemeta"
    meta = json.loads((fx / "meta_series_tt0386676.json").read_text(encoding="utf-8"))
    movie = json.loads((fx / "meta_movie_tt0816692.json").read_text(encoding="utf-8"))
    movies = json.loads((fx / "search_movie_dune.json").read_text(encoding="utf-8"))
    series = json.loads((fx / "search_series_dune.json").read_text(encoding="utf-8"))
    seasons = cinemeta.seasons(meta)
    ids = [e["id"] for s in seasons if s["season"] != 0 for e in s["episodes"]]
    nexts = {i: cinemeta.next_episode(meta, i) for i in ids[:3] + ids[-2:] + ["no-existe"]}
    results = {q: [{"kind": r["kind"], "meta_id": r["meta_id"], "title": r["title"]} for r in cinemeta.search_results(q, movies, series)]
               for q in ("dune", "Dune", "du")}
    return {"seasons": seasons, "next": nexts, "describe_series": cinemeta.describe_meta(meta),
            "describe_movie": cinemeta.describe_meta(movie), "credits": cinemeta.credits(meta), "search": results,
            "catalog_usable": [cinemeta._usable(m) for m in movies[:5]]}


def localize_cases() -> dict:
    fx = Path(__file__).resolve().parent.parent / "tests" / "fixtures" / "cinemeta"
    meta = json.loads((fx / "meta_series_tt0386676.json").read_text(encoding="utf-8"))
    found = {"title": "La Oficina", "overview": "Un falso documental.", "genres": ["Comedia"],
             "episodes": {(1, 1): {"name": "Piloto", "overview": "Michael presenta."},
                          (1, 2): {"name": "Episodio 2", "overview": ""},
                          (1, 3): {"name": "", "overview": "Solo sinopsis."}}}
    partial = {"title": "", "overview": "", "genres": [], "episodes": {}}
    rows = [{"provider_id": 8, "provider_name": "Netflix", "logo_path": "/n.jpg"}, {"provider_id": 337, "provider_name": "Disney Plus", "logo_path": "/d.jpg"},
            {"provider_id": 1899, "provider_name": "Max", "logo_path": "/m.jpg"}, {"provider_id": 9, "provider_name": "Otro"}, "raro", {"provider_name": "Netflix"}]
    return {"apply": {"found": [{"season": k[0], "episode": k[1], **v} for k, v in found["episodes"].items()],
                      "title": found["title"], "overview": found["overview"], "genres": found["genres"],
                      "result": localize.apply(meta, found), "partial": localize.apply(meta, partial)},
            "languages": {str(x): localize.tmdb_language(x) for x in ("es", "en", "en-US", "pt", "fr", "", None, "ES")},
            "platforms": tmdb.match_platforms(rows),
            "generic": {t: bool(localize.GENERIC_EPISODE.match(t)) for t in ("Episodio 3", "Episode 12", "Folge 1", "Piloto", "Episodio 3 y 4")}}


def trakt_cases() -> dict:
    raws = [
        ({"title": " Severance ", "year": 2022, "runtime": 50, "aired_episodes": 19, "overview": " Sinopsis ", "ids": {"imdb": "tt11280740", "trakt": 1234}}, "series"),
        ({"title": "Sin imdb", "ids": {"trakt": 1}}, "movie"),
        ({"title": "", "ids": {"imdb": "tt1"}}, "movie"),
        ({"title": "Dune", "year": "2021", "runtime": -5, "ids": {"imdb": "tt1160419", "trakt": "x"}}, "movie"),
        ("raro", "movie"),
    ]
    rows = [{"type": "movie", "movie": raws[3][0]}, {"type": "show", "show": raws[0][0]}, {"type": "show", "show": raws[0][0]},
            {"type": "episode", "episode": {}}, {"type": "movie", "movie": raws[1][0]}, "raro"]
    return {"entry": [{"raw": r, "kind": k, "result": trakt.entry(r, k)} for r, k in raws],
            "typed": {"rows": rows, "result": trakt._typed(rows)}}


def main() -> None:
    write("zlib", zlib_cases())
    write("watched", watched_cases())
    write("progress", progress_cases())
    write("resume", resume_cases())
    write("toggle", toggle_cases())
    write("parse_item", parse_item_cases())
    write("streams", streams_cases())
    write("cinemeta", cinemeta_cases())
    write("localize", localize_cases())
    write("trakt", trakt_cases())
    print(f"Escritos en {OUT}")


if __name__ == "__main__":
    main()
