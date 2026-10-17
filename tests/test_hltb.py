from __future__ import annotations

import io
import json
import urllib.error

from orbital.library import hltb


class FakeHltb:
    """HowLongToBeat de mentiras: token en /init y resultados en la búsqueda."""

    def __init__(self, results, expire_first=False):
        self.results, self.calls, self.expire = results, [], expire_first

    def __call__(self, url, body=None, extra=None, timeout=12):
        self.calls.append((url, body, extra))
        if url.endswith("/init?t=0") or "/init?" in url:
            return io.BytesIO(json.dumps({"token": "tok", "hpKey": "k1", "hpVal": "v1"}).encode())
        if self.expire:
            self.expire = False
            raise urllib.error.HTTPError(url, 403, "caducó", {}, None)
        return io.BytesIO(json.dumps({"data": self.results}).encode())


def game(name, year, main, plus, count=100):
    return {"game_id": 1, "game_name": name, "release_world": year, "comp_main": main, "comp_plus": plus, "comp_100": plus * 2,
            "comp_all_count": count}


def test_times_come_in_hours_and_the_year_breaks_ties(tmp_path):
    fake = FakeHltb([game("Star Wars Battlefront II", 2017, 23400, 36000, 900), game("Star Wars: Battlefront II", 2005, 30600, 50400, 300)])
    h = hltb.Hltb(tmp_path / "hltb.json", request=fake, clock=lambda: 0)
    assert h.lookup("Star Wars: Battlefront II", "2005") == {"main": 8.5, "plus": 14.0, "all": 28.0}
    url, body, extra = fake.calls[-1]
    assert url.endswith("/api/search/site") and body["searchTerms"] == ["Star", "Wars:", "Battlefront", "II"]
    assert extra == {"x-auth-token": "tok", "x-hp-key": "v1", "x-hp-val": "v1"} or extra["x-auth-token"] == "tok"
    # Guardado en disco: otra instancia no vuelve a preguntar.
    again = hltb.Hltb(tmp_path / "hltb.json", request=lambda *a, **k: (_ for _ in ()).throw(AssertionError("no debía salir")), clock=lambda: 10)
    assert again.cached("Star Wars: Battlefront II", "2005")["main"] == 8.5
    assert again.lookup("Star Wars: Battlefront II", "2005")["main"] == 8.5


def test_an_expired_token_is_renewed_and_unknown_games_are_remembered(tmp_path):
    fake = FakeHltb([game("Hades", 2020, 84600, 174600)], expire_first=True)
    h = hltb.Hltb(None, request=fake, clock=lambda: 0)
    assert h.lookup("Hades")["main"] == 23.5
    assert h.lookup("Un juego que no existe") is None
    calls = len(fake.calls)
    assert h.lookup("Un juego que no existe") is None and len(fake.calls) == calls  # no insiste


def test_offline_is_nothing_not_a_crash():
    assert hltb.Hltb(None).lookup("Hades") is None  # conftest: sin internet


def test_the_library_carries_what_is_already_known(library, monkeypatch):
    item = next(i for i in library.store.all() if i.category == "steam" and i.title == "Hades")
    monkeypatch.setattr(library.hltb, "cached", lambda title, year=None: {"main": 23.5, "plus": 48.5, "all": 95.5} if title == "Hades" else None)
    monkeypatch.setattr(library.hltb, "warm", lambda games, pause=1.5: 1)
    library.warm_hltb()
    assert library.get(item.id).extra["hltb"]["main"] == 23.5
