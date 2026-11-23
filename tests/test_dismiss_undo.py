"""«Quitar de Seguir viendo» con «Deshacer» (16 nov 2026, como el iPhone): sale ya de Seguir viendo y el aviso dice
«Quitada de Seguir viendo · Deshacer»; Trakt borra tu avance hasta que el aviso se fue."""

import time
from types import SimpleNamespace

import pytest

from orbital import watch
from orbital.watch import library as watch_library


class Prefs:
    def __init__(self):
        self.data = {}

    def prefs(self, key):
        return dict(self.data.get(key, {}))

    def set_pref(self, key, name, value):
        entry = self.data.setdefault(key, {})
        if value is None:
            entry.pop(name, None)
        else:
            entry[name] = value


def _fake():
    removed, published = [], []
    trakt = SimpleNamespace(remove_playback=removed.append)
    fake = SimpleNamespace(
        trakt_library=SimpleNamespace(client=lambda: trakt, channel=None, forget=lambda part: None,
                                      snapshot=lambda: ([{"meta_id": "tt1", "id": 42}], {}, {}, None)),
        credentials=SimpleNamespace(get=lambda key: None), state=Prefs(), _dismissing={},
        events=SimpleNamespace(publish=published.append), refresh_trakt=lambda: None, refresh_stremio=lambda: None,
        _publish_videos=lambda: published.append("videos"))
    for name in ("_dismiss_due", "_forget_progress", "undo_dismiss"):
        setattr(fake, name, getattr(watch.Watch, name).__get__(fake))
    return fake, removed, published


def test_dismiss_later_hides_now_and_forgets_on_trakt_when_the_notice_is_gone(monkeypatch):
    monkeypatch.setattr(watch_library, "DISMISS_UNDO_SECONDS", .05)
    fake, removed, published = _fake()
    watch.Watch.dismiss_continue(fake, "tt1", later=True)
    assert fake.state.prefs("stremio:tt1").get("dismissed")  # fuera de Seguir viendo ya
    assert "videos" in published and removed == []  # Trakt todavía no
    deadline = time.monotonic() + 2
    while not removed and time.monotonic() < deadline:
        time.sleep(.01)
    assert removed == [42] and fake._dismissing == {}
    with pytest.raises(LookupError):
        fake.undo_dismiss("tt1")  # el aviso ya se fue: ya no hay vuelta


def test_undo_puts_it_back_and_trakt_never_knew(monkeypatch):
    monkeypatch.setattr(watch_library, "DISMISS_UNDO_SECONDS", .2)
    fake, removed, _ = _fake()
    watch.Watch.dismiss_continue(fake, "tt1", later=True)
    fake.undo_dismiss("tt1")
    assert "dismissed" not in fake.state.prefs("stremio:tt1")
    time.sleep(.3)
    assert removed == []


def test_without_later_it_is_forgotten_at_once():
    fake, removed, _ = _fake()
    watch.Watch.dismiss_continue(fake, "tt1")
    assert removed == [42]
