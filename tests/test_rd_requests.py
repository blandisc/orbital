"""Pedidos a Real-Debrid (propuesta RD, Fernando, 2 nov 2026): pedir lo que no tiene, seguir cuánto lleva y, ya bajado,
tenerlo como una versión que arranca al instante. Desde el corte S2, la libreta es la misma que la del iPhone
(design/addons-contract.json, «requests»): por huella, seis estados y la lápida, juntada campo por campo."""

import pytest

from orbital import rd_requests
from orbital.library import addons, realdebrid, streams

TORRENTIO = "https://torrentio.strem.fun/sort=seeders%7Clanguage=latino%7Crealdebrid=ABC123"
H1, H2 = "a" * 40, "b" * 40


class State:
    def __init__(self):
        self.data = {}

    def prefs(self, item):
        return dict(self.data.get(item, {}))

    def set_pref(self, item, key, value):
        bucket = self.data.setdefault(item, {})
        if value is None:
            bucket.pop(key, None)
        else:
            bucket[key] = value


class FakeRD:
    """Una cuenta de Real-Debrid de mentira: nada sale a internet."""

    def __init__(self, token="ABC123"):
        self.token, self.added, self.deleted, self.selected = token, [], [], []
        self.list = []  # lo que devuelve GET /torrents
        self.user_id = 7
        self.missing = set()  # rd_ids que dan 404
        self.fail_add = None
        self.room = (0, 25)  # GET /torrents/activeCount: (activas, cuántas deja tu cuenta)

    def user(self):
        return {"id": self.user_id}

    def add(self, info_hash, file_idx=None, pack=False):
        if self.fail_add:
            raise self.fail_add
        rd_id = f"RD{len(self.added) + 1}"
        self.added.append((info_hash, file_idx, pack))
        self.list.append({"id": rd_id, "hash": info_hash, "status": "queued", "progress": 0, "seeders": 4})
        return rd_id

    def select(self, rd_id, file_idx=None, pack=False):
        self.selected.append(rd_id)

    def torrents(self, limit=100):
        return [dict(t) for t in self.list]

    def info(self, rd_id):
        if rd_id in self.missing:
            raise realdebrid.RealDebridError("Ya no está en tu Real-Debrid", 404)
        found = next((t for t in self.list if t["id"] == rd_id), None)
        if found is None:
            raise realdebrid.RealDebridError("Ya no está en tu Real-Debrid", 404)
        return {**found, "links": ["https://rd/l1", "https://rd/l2"],
                "files": [{"id": 1, "selected": 1, "bytes": 9}, {"id": 2, "selected": 1, "bytes": 5}]}

    def link(self, info, file_idx=None):
        return (f"https://download.real-debrid.com/{file_idx}.mkv", "Nocturno.S01E01.1080p.Dual-Lat.mkv")

    def active_count(self):
        return self.room

    def delete(self, rd_id):
        self.deleted.append(rd_id)
        self.list = [t for t in self.list if t["id"] != rd_id]

    def set(self, info_hash, **change):
        for t in self.list:
            if t["hash"] == info_hash:
                t.update(change)


class Finder:
    timeout = 5

    def __init__(self):
        self.forgot = []

    def addons(self):
        return [type("A", (), {"base": TORRENTIO, "name": "Torrentio RD"})()]

    def forget(self, kind, video_id):
        self.forgot.append(video_id)


def stream(info_hash, idx=None):
    out = {"name": "Torrentio\n1080p", "title": "Nocturno.S01E01.2026.WEB-DL.1080p-Dual-Lat\n👤 3 💾 1.2 GB", "infoHash": info_hash}
    if idx is not None:
        out["fileIdx"] = idx
    return out


@pytest.fixture
def setup(monkeypatch):
    rd, events, state, finder = FakeRD(), [], State(), Finder()
    found = {"streams": [stream(H1)]}
    monkeypatch.setattr(addons, "fetch_json", lambda url, timeout: found)
    monkeypatch.setattr(rd_requests.RdRequests, "watch", lambda self: None)  # sin hilo: tick() a mano
    reqs = rd_requests.RdRequests(finder, state, events.append, rd_factory=lambda token: rd)
    return reqs, rd, events, state, finder, found


def test_token_and_the_same_torrentio_without_real_debrid():
    assert realdebrid.token_in(TORRENTIO) == "ABC123"
    assert realdebrid.without_debrid(TORRENTIO) == "https://torrentio.strem.fun/sort=seeders%7Clanguage=latino"


def test_request_follow_and_ready_source(setup):
    reqs, rd, events, state, finder, _ = setup
    got = reqs.request("series", "tt1:1:1", "Nocturne · T1 E1", streams.Preferences(audio="es"), meta_id="tt1", season=1, episode=1)
    assert rd.added == [(H1, None, True)] and got["state"] == "queued" and got["message"] == "En cola"
    entry = state.data[rd_requests.STATE_ID][H1]
    assert entry["account"] == "7" and entry["by"] == "TV" and entry["video_ids"] == ["tt1:1:1"] and entry["rd_id"] == "RD1"
    rd.set(H1, status="downloading", progress=42)
    assert reqs.tick() is True and reqs.status("tt1:1:1")["message"] == "Bajando en la nube · 42 %"
    rd.set(H1, status="downloaded", progress=100)
    assert reqs.tick() is False and reqs.status("tt1:1:1")["state"] == "ready" and finder.forgot == ["tt1:1:1"]
    assert [e["message"] for e in events if e.get("type") == "toast"] == ["Ya está Nocturne · T1 E1"]
    assert reqs.tick() is False and len([e for e in events if e.get("type") == "toast"]) == 1  # avisa una sola vez
    source = reqs.ready_source("series", "tt1:1:1")
    assert source.cached and source.stream["url"].startswith("https://download.real-debrid.com/") and "es" in source.languages
    listed = reqs.listing()
    assert listed["version"] == 1 and listed["account"] == "7"
    assert "notified" not in listed["requests"][0] and "url" not in listed["requests"][0]  # lo que solo vive aquí no viaja
    assert "url" not in state.data[rd_requests.STATE_ID][H1]  # el enlace listo vive en memoria, no en el estado


def test_no_peers_and_the_stall_notice(setup):
    reqs, rd, events, state, *_ = setup
    reqs.request("movie", "tt9", "Midsommar", streams.Preferences())
    rd.set(H1, status="downloading", progress=3, seeders=0)
    reqs.tick()
    assert reqs.status("tt9")["message"] == "Sin gente que lo comparta"
    state.data[rd_requests.STATE_ID][H1]["progress_at"] -= rd_requests.STALL_AFTER + 1
    reqs.tick()
    assert any("sigue sin bajar" in e.get("message", "") for e in events)
    assert reqs.status("tt9")["detail"] == "Sigue sin bajar · ¿probar otra versión?"


def test_a_season_pack_is_asked_once_for_all_its_episodes(setup):
    reqs, rd, _, state, _, found = setup
    found["streams"] = [stream(H1, 0)]
    reqs.request("series", "tt1:1:1", "Nocturne · T1 E1", streams.Preferences(), meta_id="tt1")
    found["streams"] = [stream(H1, 1)]
    reqs.request("series", "tt1:1:2", "Nocturne · T1 E2", streams.Preferences(), meta_id="tt1")
    assert len(rd.added) == 1 and rd.added[0][2] is True  # todos sus videos, una sola vez
    entry = state.data[rd_requests.STATE_ID][H1]
    assert entry["video_ids"] == ["tt1:1:1", "tt1:1:2"] and entry["files"] == {"tt1:1:1": 0, "tt1:1:2": 1}
    rd.set(H1, status="downloaded", progress=100)
    reqs.tick()
    assert reqs.ready_source("series", "tt1:1:2").stream["url"].endswith("/1.mkv")  # el archivo de ese episodio


def test_after_a_restart_the_pending_ones_are_followed_again(monkeypatch):
    started = []
    monkeypatch.setattr(rd_requests.RdRequests, "watch", lambda self: started.append(True))
    state = State()
    state.set_pref(rd_requests.STATE_ID, H1, {"hash": H1, "state": "downloading", "video_ids": ["tt9"]})
    rd_requests.RdRequests(Finder(), state, lambda e: None, rd_factory=FakeRD).start()
    assert started == [True]
    idle = State()
    idle.set_pref(rd_requests.STATE_ID, H1, {"hash": H1, "state": "ready", "video_ids": ["tt9"]})
    rd_requests.RdRequests(Finder(), idle, lambda e: None, rd_factory=FakeRD).start()
    assert started == [True]


def test_old_entries_by_video_get_their_hash(setup):
    reqs, rd, events, state, *_ = setup
    rd.list.append({"id": "OLD1", "hash": H2.upper(), "status": "downloaded", "progress": 100})
    state.set_pref(rd_requests.STATE_ID, "tt5:1:3", {"kind": "series", "title": "Severance · T1 E3", "rd_id": "OLD1",
                                                     "state": "downloading", "percent": 80, "since": 1.0})
    assert reqs.status("tt5:1:3")["message"] == "En cola" or reqs.status("tt5:1:3")["state"] == "downloading"
    reqs.tick()
    book = state.data[rd_requests.STATE_ID]
    assert "tt5:1:3" not in book and book[H2]["video_ids"] == ["tt5:1:3"] and book[H2]["state"] == "ready"


def test_what_the_iphone_sends_is_merged_and_never_announced_here(setup):
    reqs, rd, events, state, *_ = setup
    rd.list.append({"id": "RDX", "hash": H2, "status": "downloading", "progress": 10, "seeders": 3})
    sent = {"hash": H2.upper(), "account": "7", "rd_id": "RDX", "title": "Severance · T2 E1", "kind": "series",
            "meta_id": "tt5", "video_ids": ["tt5:2:1"], "files": {"tt5:2:1": 0}, "by": "iPhone de Fernando",
            "since": 100.0, "updated": 1.0, "percent": 10, "state": "downloading", "notified": False, "url": "https://x"}
    saved = reqs.receive(sent)
    assert saved["hash"] == H2 and "notified" not in saved and "url" not in saved and saved["updated"] > 1.0
    reqs.receive({**sent, "video_ids": ["tt5:2:2"], "files": {"tt5:2:2": 1}, "percent": 5, "state": "queued"})
    entry = state.data[rd_requests.STATE_ID][H2]
    assert entry["video_ids"] == ["tt5:2:1", "tt5:2:2"] and entry["percent"] == 10 and entry["state"] == "downloading"
    rd.set(H2, status="downloaded", progress=100)
    reqs.tick()
    assert reqs.status("tt5:2:1")["state"] == "ready" and not [e for e in events if e.get("type") == "toast"]  # avisa el iPhone


def test_a_tombstone_wins_but_a_new_rd_id_starts_over(setup):
    reqs, *_ = setup
    base = {"hash": H2, "rd_id": "R1", "video_ids": ["tt5"], "by": "iPhone", "state": "downloading", "percent": 40}
    reqs.receive(base)
    reqs.receive({**base, "state": "gone"})
    assert reqs.listing()["requests"][0]["state"] == "gone"
    reqs.receive({**base, "state": "queued", "percent": 0})  # el mismo rd_id con un estado menor: sigue la lápida
    assert reqs.listing()["requests"][0]["state"] == "gone"
    reqs.receive({**base, "rd_id": "R2", "state": "queued", "percent": 0})  # lo volvieron a pedir: otro rd_id
    assert reqs.listing()["requests"][0]["state"] == "queued" and reqs.listing()["requests"][0]["rd_id"] == "R2"


def test_deleted_in_real_debrid_becomes_a_tombstone(setup):
    reqs, rd, *_ = setup
    reqs.request("movie", "tt9", "Midsommar", streams.Preferences())
    rd.list.clear()
    rd.missing.add("RD1")
    assert reqs.tick() is False and reqs.listing()["requests"][0]["state"] == "gone" and reqs.status("tt9") is None


def test_cancel_deletes_it_and_leaves_the_tombstone(setup):
    reqs, rd, *_ = setup
    reqs.request("movie", "tt9", "Midsommar", streams.Preferences())
    reqs.cancel(H1)
    assert rd.deleted == ["RD1"] and reqs.listing()["requests"][0]["state"] == "gone"


def test_another_account_is_shown_but_never_followed(setup):
    reqs, rd, *_ = setup
    reqs.account()
    reqs.receive({"hash": H2, "account": "99", "rd_id": "THEIRS", "video_ids": ["tt5"], "by": "iPhone", "state": "downloading"})
    rd.missing.add("THEIRS")
    reqs.tick()
    assert reqs.listing()["requests"][0]["state"] == "downloading"  # no se sondea: no es de tu cuenta
    assert reqs.status("tt5")["mine"] is False and reqs.ready_source("movie", "tt5") is None
    with pytest.raises(realdebrid.RealDebridError):
        reqs.cancel(H2)


def test_bad_entries_are_refused(setup):
    reqs, *_ = setup
    for bad in [{"hash": "nope"}, {"hash": H1, "title": "x" * 121}, {"hash": H1, "video_ids": ["v"] * 51},
                {"hash": H1, "kind": "game"}, {"hash": H1, "percent": 300}, "texto", None]:
        with pytest.raises(ValueError):
            reqs.receive(bad)
    assert rd_requests.clean({"hash": H1, "state": "failed"})["state"] == "refused"  # el «failed» de antes
    assert rd_requests.clean({"hash": H1, "state": "paused_by_tv"})["state"] == "queued"  # lo desconocido: se vuelve a preguntar


def test_a_refused_version_is_skipped_and_too_many_is_kept(setup):
    reqs, rd, _, state, _, found = setup
    found["streams"] = [stream(H1), stream(H2)]
    rd.fail_add = realdebrid.RealDebridError("Real-Debrid no lo dejó bajar", 403, 35)
    got = reqs.request("movie", "tt9", "Midsommar", streams.Preferences())
    assert got["state"] == "refused" and got["message"] == "Real-Debrid no lo dejó bajar"
    rd.fail_add = realdebrid.RealDebridError("Muchas descargas activas", 503, 21)
    got = reqs.request("movie", "tt9", "Midsommar", streams.Preferences())
    assert got["state"] == "too_many" and state.data[rd_requests.STATE_ID][H2]["state"] == "too_many"  # «Prueba otra versión»
    rd.fail_add = None
    assert reqs.request("movie", "tt9", "Midsommar", streams.Preferences())["state"] == "queued"
    assert rd.added == [(H2, None, False)]


def test_finished_ones_are_forgotten_after_a_week(setup):
    reqs, _, _, state, *_ = setup
    reqs.receive({"hash": H2, "video_ids": ["tt5"], "by": "iPhone", "state": "ready"})
    state.data[rd_requests.STATE_ID][H2]["updated"] -= rd_requests.FORGET_AFTER + 1
    assert reqs.listing()["requests"] == []
    with pytest.raises(ValueError):  # un POST no lo reaviva
        reqs.receive({"hash": H2, "video_ids": ["tt5"], "by": "iPhone", "state": "ready", "updated": 1.0})


def test_nothing_to_request_says_so(setup):
    reqs, _, _, _, _, found = setup
    found["streams"] = []
    with pytest.raises(realdebrid.RealDebridError, match="Nadie lo tiene todavía en internet"):
        reqs.request("series", "tt1:1:1", "x", streams.Preferences())


def test_what_the_iphone_sends_with_unknowns_numbers_and_all_files(setup):
    reqs, rd, _, state, _, found = setup
    sent = {"hash": H2, "account": 7, "rd_id": None, "title": "Severance · T2 E1", "kind": "series", "meta_id": "tt5",
            "video_ids": ["tt5:2:1"], "files": {"tt5:2:1": 0}, "season": None, "episode": None, "seeders": None,
            "language": "", "release": "", "rd_status": "", "by": "iPhone de Fernando", "state": "queued", "all_files": True}
    saved = reqs.receive(sent)  # null y "" no son error; la cuenta llega como número
    assert saved["account"] == "7" and saved["all_files"] is True
    found["streams"] = [stream(H2, 1)]
    reqs.account()
    reqs.request("series", "tt5:2:2", "Severance · T2 E2", streams.Preferences(), meta_id="tt5")
    assert rd.added == [] and state.data[rd_requests.STATE_ID][H2]["video_ids"] == ["tt5:2:1", "tt5:2:2"]  # el mismo paquete


def test_t8a_the_version_you_chose_is_the_one_requested(setup):
    """T8-A (plan v5): en «Versión», «Pedirlo y avisarme» pide justo esa versión (su huella), no la mejor que encuentre;
    si ya no aparece, se dice. La huella sale de la dirección de Real-Debrid de Torrentio."""
    reqs, rd, _, _, _, found = setup
    other = "b" * 40
    found["streams"] = [stream(H1), stream(other)]
    got = reqs.request("movie", "tt9", "Midsommar", streams.Preferences(), want=other.upper())
    assert rd.added[-1][0] == other and got["state"] == "queued"
    with pytest.raises(realdebrid.RealDebridError, match="ya no aparece"):
        reqs.request("movie", "tt8", "Otra", streams.Preferences(), want="c" * 40)
    src = streams.Source(stream={"url": f"https://torrentio.strem.fun/resolve/realdebrid/KEY/{other.upper()}/null/0/x.mkv"},
                         addon="Torrentio", transport_url="", index=0)
    src.debrid, src.cached = True, False
    assert src.info_hash == other and src.public()["hash"] == other
    src.cached = True
    assert "hash" not in src.public()  # lo que ya arranca no se pide


def test_a_finished_request_is_instant_and_first_and_one_from_the_iphone_refreshes_the_search(setup):
    """«El viento tiene miedo» (3 nov): con Real-Debrid ya terminado, Torrentio seguía marcando ese torrent «[RD download]»:
    «Ya está» pero no arrancaba. Un pedido listo cuenta como al instante y va primero; uno que llega listo desde el iPhone
    vuelve a buscar las versiones."""
    reqs, rd, events, state, finder, _ = setup
    entry = {"hash": H2, "account": "7", "rd_id": "R9", "title": "El viento", "kind": "movie", "meta_id": "tt0061752",
             "video_ids": ["tt0061752"], "files": {}, "by": "iPhone de Fernando", "state": "downloading", "percent": 50}
    reqs.receive(entry)
    assert finder.forgot == []
    reqs.receive({**entry, "state": "ready", "percent": 100})
    assert finder.forgot == ["tt0061752"]


def test_n3_too_many_is_asked_again_once_when_there_is_room(setup):
    """N3-A (Fernando, 4 nov): «Muchas descargas activas» se vuelve a pedir solo, una vez, cuando haya lugar."""
    reqs, rd, events, state, _, _ = setup
    rd.fail_add = realdebrid.RealDebridError("Muchas descargas activas", 503, 21)
    got = reqs.request("movie", "tt9", "Midsommar", streams.Preferences())
    assert got["state"] == "too_many" and got["detail"] == "Lo vuelvo a pedir cuando se libere un lugar"
    rd.fail_add, rd.room = None, (25, 25)
    assert reqs.tick() is True and rd.added == []  # sigue lleno: espera, sin dejar de seguirlo
    rd.room = (24, 25)
    assert reqs.tick() is True and rd.added == [(H1, None, False)]
    assert reqs.status("tt9")["state"] == "queued" and state.data[rd_requests.STATE_ID][H1]["retried"] is True
    assert any(e.get("message") == "Volví a pedir Midsommar" for e in events)
    state.data[rd_requests.STATE_ID][H1]["state"] = "too_many"
    reqs.tick()
    assert len(rd.added) == 1  # una sola vez


def test_finished_and_deleted_in_real_debrid_leaves_the_row(setup):
    """Fernando, 4 nov: lo terminado que borraste en real-debrid.com ya no se queda en la fila una semana."""
    reqs, rd, *_ = setup
    reqs.request("movie", "tt9", "Midsommar", streams.Preferences())
    rd.list[0].update(status="downloaded", progress=100)
    reqs.tick()
    assert reqs.status("tt9")["state"] == "ready"
    rd.list.clear()
    rd.missing.add("RD1")
    assert reqs.tick() is False and reqs.status("tt9") is None
