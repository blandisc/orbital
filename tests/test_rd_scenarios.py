"""Los escenarios comunes de Real-Debrid con el iPhone (tests/fixtures/rd-scenarios, README): cada uno pasa por el código
de verdad de la TV (streams.find, Watch.availability, Watch.choose_source, rd_requests) con Torrentio, Real-Debrid, TMDB y
Cinemeta de mentira armados con lo capturado, y se compara con `expected`.

Se comparan las decisiones que se ven en la ficha: el botón principal, la causa, lo que pone «Ver» (huella e idioma) y
«Pedir a la nube en latino». Lo que es distinto a propósito en la TV va en TV_DIFFERS, con su porqué.
"""

from __future__ import annotations

import json
import time
from datetime import datetime
from pathlib import Path
from urllib.parse import quote

import pytest

from orbital import rd_requests, watch
from orbital.library import addons, streams

HERE = Path(__file__).parent / "fixtures" / "rd-scenarios"
SCENARIOS = sorted((HERE / "escenarios").glob("*.json"))
KEY = "K" * 52
TORRENTIO = f"https://torrentio.strem.fun/realdebrid={KEY}"

# Distinto a propósito en la TV (acordado con el iPhone, 4 nov): llave → (qué no se compara, por qué).
TV_DIFFERS = {
    # Sin clave, la TV reproduce los torrents con el servidor de Stremio («Necesita Stremio abierto»): no hay causa.
    "16-inception-sin-clave": ("primary cause recommended", "la TV ve torrents sin Real-Debrid con Stremio"),
    # «Ver en la TV» es del iPhone (FQ5-A); en la TV, lo de otra cuenta no se ve.
    "21-inception-lista-otra-cuenta": ("primary cause", "«Ver en la TV» solo existe en el iPhone"),
}


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def with_debrid(scn: dict) -> tuple[list[dict] | None, list[dict]]:
    """Lo que contesta Torrentio con tu Real-Debrid (la regla del README) y lo que existe para pedir (sin él)."""
    t, rd = scn["torrentio"], scn["rd"]
    captured = load(HERE / t["file"]).get("streams") or []
    if t["status"] == "down":
        return None, []
    if t["status"] == "rd_error":
        return [{"name": "[RD error] Torrentio", "title": "", "url": "https://torrentio.strem.fun/videos/failed_access_v2.mp4"}], captured
    if not rd.get("key"):
        return [dict(s) for s in captured], captured
    out = []
    for s in captured:
        h = str(s.get("infoHash") or "").lower()
        quality = str(s.get("name") or "").split("\n", 1)[1] if "\n" in str(s.get("name") or "") else ""
        cached = h in {x.lower() for x in rd.get("instant") or []}
        if t.get("options", {}).get("only_instant") and not cached:
            continue
        hints = s.get("behaviorHints") or {}
        idx = s.get("fileIdx")
        name = quote(str(hints.get("filename") or "video.mkv"))
        stream = {k: v for k, v in s.items() if k not in ("infoHash", "fileIdx")}
        stream["name"] = f"[RD{'+' if cached else ' download'}] Torrentio" + (f"\n{quality}" if quality else "")
        stream["url"] = f"https://torrentio.strem.fun/resolve/realdebrid/{KEY}/{h}/null/{idx if idx is not None else 'undefined'}/{name}"
        out.append(stream)
    return out, captured


class FakeRD:
    """Tu Real-Debrid de mentira: `GET /torrents/info` y `POST /unrestrict/link` con lo del escenario."""

    def __init__(self, rd: dict) -> None:
        self.torrents = {t["id"]: t for t in rd.get("torrents") or []}

    def info(self, rd_id):
        return self.torrents[rd_id]

    def link(self, info, file_idx=None):
        links = info.get("links") or []
        if not links:
            return None
        files = [f for f in info.get("files") or [] if f.get("selected")]
        pairs = list(zip(links, files, strict=False)) or [(links[0], {})]
        exact = [p for p in pairs if file_idx is not None and p[1].get("id") == file_idx + 1]
        best = exact[0] if exact else max(pairs, key=lambda p: p[1].get("bytes", 0))
        url = (info.get("unrestrict") or {}).get(best[0])
        return (url, str(best[1].get("path") or "").rsplit("/", 1)[-1]) if url else None


def facts_of(scn: dict) -> dict:
    tmdb = scn.get("tmdb") or {}
    detail = tmdb.get("detail") or {}
    titles = [x for x in (detail.get("title") or detail.get("name"), detail.get("original_title") or detail.get("original_name")) if x]
    meta = load(HERE / scn["cinemeta"]) if scn.get("cinemeta") else {}
    meta = meta.get("meta", meta)
    if meta.get("name"):
        titles.append(meta["name"])
    original = detail.get("original_language")
    if original == "es":
        original = "es-ES" if (detail.get("origin_country") or [""])[0] == "ES" else "es-419"
    if not original and str(scn["title"]["id"]).startswith("kitsu:"):
        original = "ja"
    year = str(meta.get("year") or meta.get("releaseInfo") or "")[:4]
    return {"original": original, "titles": titles, **({"year": int(year)} if year.isdigit() else {})}


@pytest.fixture
def run(library, monkeypatch):
    """Arma la TV para un escenario y devuelve lo que decide."""
    def go(scn: dict) -> dict:
        w = library.watch
        now = datetime.fromisoformat(scn["now"].replace("Z", "+00:00")).timestamp()
        monkeypatch.setattr(time, "time", lambda: now)
        app, title, rd = scn["app"], scn["title"], scn["rd"]
        prefs = streams.Preferences(audio=app["audio"], quality=app.get("quality", "1080p"), spanish=app.get("spanish", ""))
        found, existing = with_debrid(scn)
        torrentio_on = "torrentio" in scn["addons"]
        addon = addons.Addon("Torrentio RD", f"{TORRENTIO}/manifest.json",
                             rules={"stream": addons.Rule(types=["movie", "series"], id_prefixes=None)})
        monkeypatch.setattr(type(w), "has_addons", property(lambda self: True))
        monkeypatch.setattr(w.streams, "addons", lambda: [addon] if torrentio_on else [])
        monkeypatch.setattr(w.streams, "_fetch", lambda a, k, v: found)
        monkeypatch.setattr(w.streams, "facts", lambda k, v: facts_of(scn))
        w.streams.forget_all()
        monkeypatch.setattr(addons, "fetch_json", lambda url, timeout=None: {"streams": existing})
        monkeypatch.setattr(type(w), "asked_language", lambda self, meta: (prefs, ""))
        monkeypatch.setattr(w, "language_for", lambda meta_id: (prefs, ""))
        account = rd.get("account") or {}
        client = FakeRD(rd)
        monkeypatch.setattr(w.rd, "client", lambda: client if rd.get("key") else None)
        monkeypatch.setattr(w.rd, "account", lambda: str(account.get("id")) if account.get("id") else None)
        monkeypatch.setattr(w.rd, "_account", (now + 10**9, None, str(account.get("id")) if account.get("id") else None))
        monkeypatch.setattr(w.rd, "_debrid_addon", lambda: addon if rd.get("key") and torrentio_on else None)
        monkeypatch.setattr(w, "debrid_status", lambda fresh=False: {"problem": account.get("problem")})
        monkeypatch.setattr(rd_requests.RdRequests, "watch", lambda self: None)
        for entry in rd.get("book") or []:
            # Las horas: relativas a `now` si son chicas (segundos), si no, tal cual.
            w.rd.receive({k: (now + v if k in ("since", "updated", "progress_at") and isinstance(v, (int, float)) and abs(v) < 10**9
                              else v) for k, v in entry.items()})
        meta = load(HERE / scn["cinemeta"]) if scn.get("cinemeta") else {}
        meta = meta.get("meta", meta)
        monkeypatch.setattr(w.cinemeta, "meta", lambda kind, meta_id, localized=True: meta)
        got = w.availability(title["kind"], title["id"], title["video_id"])
        chosen = w.choose_source(title["kind"], title["video_id"], prefs) if got["why"] != "no-addons" else None
        return {"availability": got, "chosen": chosen, "prefs": prefs}
    return go


WHY = {"ok": "play", "requested": "requested", "debrid": "request", "unreleased": "fix", "offline": "fix",
       "no-addons": "fix", "debrid-account": "fix", "none": "fix"}
MESSAGES = {"Tu Real-Debrid venció": "expired", "Tu cuenta no tiene Premium": "no_premium",
            "Vuelve a conectar Real-Debrid": "bad_key", "Real-Debrid no lo dejó bajar": "refused",
            "No pude conectar con tus complementos": "addons_offline", "No tienes complementos prendidos": "no_addons",
            "Todavía no está en la nube": "not_in_rd", "Nadie lo tiene todavía en internet": "nobody_has_it",
            "No puedo buscar versiones": "cannot_search"}


def primary_of(got: dict) -> str:
    """El botón principal de la TV, en la clave común. «Real-Debrid no lo dejó bajar» y un pedido atorado 24 h abren
    «Probar otra versión» (fix), como en el iPhone."""
    if got["why"] == "debrid" and got["message"] == "Real-Debrid no lo dejó bajar":
        return "fix"
    if got["why"] == "requested" and str(got.get("detail") or "").startswith("Sigue sin bajar"):
        return "fix"
    return WHY.get(got["why"], got["why"])


def cause_of(got: dict) -> str | None:
    msg = got["message"]
    if got["why"] == "requested" and str(got.get("detail") or "").startswith("Sigue sin bajar"):
        return None
    if got["why"] in ("ok",):
        return None
    if msg.startswith("Aún no se estrena"):
        return "unreleased"
    if msg.startswith("Bajando en la nube"):
        return "downloading"
    return MESSAGES.get(msg, msg)


@pytest.mark.parametrize("path", SCENARIOS, ids=[p.stem for p in SCENARIOS])
def test_escenario(path, run):
    scn = load(path)
    if scn.get("act"):
        pytest.skip("con «act» (pedir antes de mirar): todavía no")
    exp = scn["expected"]
    skip = TV_DIFFERS.get(scn["id"], ("", ""))[0].split()
    out = run(scn)
    got, chosen = out["availability"], out["chosen"]
    problems = []
    if "primary" not in skip:
        primary = primary_of(got)
        if primary != exp["primary"]:
            problems.append(f"botón: {primary} ({got['message']!r}), se esperaba {exp['primary']}")
    # En camino, «Bajando en la nube · 40 %» es el botón (no una causa aparte), como en el iPhone.
    if "cause" not in skip and exp["primary"] not in ("play", "requested") and cause_of(got) != exp["cause"]:
        problems.append(f"causa: {cause_of(got)!r}, se esperaba {exp['cause']!r}")
    rec = exp.get("recommended")
    if "recommended" not in skip and rec and exp["primary"] == "play":
        have = (chosen.info_hash if chosen else None, watch.version_lang(chosen, out["prefs"]) if chosen else None)
        lang = rec["language"]
        want_lang = lang if lang in ("en", "ja") else "es"
        if have[0] != rec["hash"] or have[1] != want_lang:
            problems.append(f"«Ver»: {have}, se esperaba {(rec['hash'], lang)} ({chosen.release if chosen else None})")
    aside = exp.get("request_aside")
    offer = got.get("offer")
    if (aside or {}).get("hash") != (offer or {}).get("hash"):
        problems.append(f"«Pedir a la nube en latino»: {offer}, se esperaba {aside}")
    assert not problems, "\n".join(problems)
