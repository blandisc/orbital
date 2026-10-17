"""«Continuar»: no solo donde ibas, también la misma fuente y los mismos subtítulos con los que lo dejaste."""

from test_player import make_player

from orbital.library import streams


def _source(index, info_hash=None, release="", size=0):
    stream = {"infoHash": info_hash, "fileIdx": 0} if info_hash else {"url": f"https://cdn/{index}.mkv"}
    return streams.Source(index=index, addon="Torrentio", stream=stream, transport_url="", release=release, size=size)


def test_a_source_keeps_its_fingerprint_between_searches():
    """El índice cambia de una búsqueda a otra; la huella no (el torrent y su archivo, o el nombre y el tamaño)."""
    assert _source(0, "ABC").key == _source(7, "abc").key
    assert _source(0, release="Show.S01E01.1080p", size=9).key == _source(3, release="Show.S01E01.1080p", size=9).key
    assert _source(0, "abc").key != _source(0, "def").key


def test_the_player_knows_your_subtitles_and_puts_the_same_ones_back():
    tracks = [{"type": "sub", "id": 1, "lang": "spa", "title": "España"},
              {"type": "sub", "id": 2, "lang": "spa", "title": "Latinoamérica", "selected": True}]
    p, mpv = make_player(**{"track-list": tracks})
    assert p.current_subtitle() == {"off": False, "lang": "spa", "title": "Latinoamérica", "url": ""}
    p._sub_pick = {"off": False, "lang": "spa", "title": "Latinoamérica", "url": ""}
    assert p._apply_sub_pick(tracks) and ("set_property", "sid", 2) in mpv.sent  # la de Latinoamérica, no la primera
    p._sub_pick = {"off": True}
    assert p._apply_sub_pick(tracks) and ("set_property", "sid", "no") in mpv.sent
    p._sub_pick = {"off": False, "lang": "spa", "title": "Subtítulos", "url": "https://subs/x.srt"}  # de tu complemento
    assert p._apply_sub_pick(tracks) and mpv.sent[-1][:2] == ("sub-add", "https://subs/x.srt")
    assert not p._apply_sub_pick(tracks)  # se usa una vez


def test_continue_uses_the_source_you_left_it_with(library, monkeypatch):
    watch = library.watch
    found = [_source(0, "best"), _source(1, "mine")]
    monkeypatch.setattr(watch, "stream_sources", lambda kind, video_id, prefs=None: found)
    monkeypatch.setattr(watch, "best_source", lambda kind, video_id, binge=None, skip=None, prefs=None: found[0])
    played = []
    monkeypatch.setattr(watch, "play_source", lambda kind, meta_id, video_id, index, title, **kw: played.append((index, kw.get("sub_pick"))))
    sub = {"off": False, "lang": "spa", "title": "Latinoamérica", "url": ""}
    library.state.set_pref("stremio:tt1", "resume", {"video_id": "tt1:1:2", "source": found[1].key, "sub": sub})
    watch.play_best("series", "tt1", "tt1:1:2", "Serie")
    assert played[-1] == (1, sub)  # la fuente y los subtítulos con los que lo dejaste
    watch.play_best("series", "tt1", "tt1:1:3", "Serie")  # otro episodio: lo de siempre
    assert played[-1] == (0, None)
    watch.play_best("series", "tt1", "tt1:1:2", "Serie", from_start=True)  # desde el principio: lo de siempre
    assert played[-1][0] == 0
    found[1] = _source(1, "otra")  # la fuente que tenías ya no está: la recomendada
    watch.play_best("series", "tt1", "tt1:1:2", "Serie")
    assert played[-1][0] == 0


def test_saving_progress_remembers_the_source(library):
    """Cada guardado del avance (cada minuto y al salir) anota la fuente y los subtítulos de ese episodio."""
    watch = library.watch
    meta = {"kind": "series", "meta_id": "tt1", "video_id": "tt1:1:2", "title": "Serie", "source_key": "Torrentio|abc|0"}
    watch._save_progress(meta, 30, 1500, 30, refresh=False)
    assert watch.resume_choice("tt1", "tt1:1:2") is None  # medio minuto: aún no
    watch._save_progress(meta, 600, 1500, 60, refresh=False)
    assert watch.resume_choice("tt1", "tt1:1:2")["source"] == "Torrentio|abc|0"
