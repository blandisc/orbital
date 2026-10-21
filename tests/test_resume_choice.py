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


# --- Entre el iPhone y la TV: el mismo segundo, la misma fuente, el mismo audio y los mismos subtítulos -------------------

def test_the_player_matches_tracks_from_the_iphone_by_language():
    """El iPhone etiqueta las pistas distinto («es» y no «spa»): se usa la del mismo idioma (no la de forzados)."""
    tracks = [{"type": "audio", "id": 1, "lang": "eng", "selected": True}, {"type": "audio", "id": 2, "lang": "spa"},
              {"type": "sub", "id": 3, "lang": "spa", "title": "Forced"}, {"type": "sub", "id": 4, "lang": "spa", "title": "Full"}]
    p, mpv = make_player(**{"track-list": tracks})
    p._sub_pick = {"off": False, "lang": "es", "title": "Español", "audio": {"lang": "es-419", "title": ""}}
    assert p._apply_sub_pick(tracks)
    assert ("set_property", "aid", 2) in mpv.sent and ("set_property", "sid", 4) in mpv.sent
    p._sub_pick = {"audio": {"lang": "spa", "title": ""}}  # solo el audio: los subtítulos, con la regla de siempre
    assert not p._apply_sub_pick(tracks)


def test_from_the_iphone_the_tv_follows_the_same_second_source_and_tracks(library, monkeypatch):
    watch = library.watch
    found = [_source(0, "best"), _source(1, "phone")]
    monkeypatch.setattr(watch, "stream_sources", lambda kind, video_id, prefs=None: found)
    monkeypatch.setattr(watch, "best_source", lambda kind, video_id, binge=None, skip=None, prefs=None: found[0])
    played = []
    monkeypatch.setattr(watch, "play_source", lambda kind, meta_id, video_id, index, title, **kw: played.append((index, kw)))
    sub = {"off": False, "lang": "spa", "title": "Latino", "url": ""}
    watch.play_best("movie", "tt1", "tt1", "Dune", handoff={"position": 1234.5, "source": found[1].key,
                                                           "audio": {"lang": "eng", "title": "Original"}, "subtitle": sub})
    index, kw = played[-1]
    assert index == 1 and kw["start_at"] == 1234.5  # la fuente del iPhone, en su segundo
    assert kw["sub_pick"] == {**sub, "audio": {"lang": "eng", "title": "Original"}}
    assert kw["prefs"].audio == "en" and kw["subtitles"] == "es"
    watch.play_best("movie", "tt1", "tt1", "Dune", handoff={"position": 60, "source": "otra|x|0", "subtitle": {"off": True}})
    index, kw = played[-1]
    assert index == 0 and kw["subtitles"] == "" and kw["sub_pick"] == {"off": True}  # su fuente no está: la recomendada


def test_the_iphone_request_carries_what_it_was_playing():
    from orbital.api.media import PlayRequest
    body = PlayRequest(kind="movie", id="tt1", position=90, source_key="Torrentio|abc|0",
                       audio={"lang": "en", "title": "Main"}, subtitle={"lang": "es", "url": "file:///etc/passwd"})
    handoff = body.handoff()
    assert handoff is not None
    assert handoff["position"] == 90 and handoff["source"] == "Torrentio|abc|0" and handoff["audio"] == {"lang": "en", "title": "Main"}
    assert handoff["subtitle"]["url"] == ""  # solo direcciones web
    assert PlayRequest(kind="movie", id="tt1").handoff() is None  # «Ver en la TV» de una ficha: como siempre


def test_continue_on_iphone_sends_the_source_and_tracks(library, monkeypatch):
    from orbital import companion
    watch = library.watch
    monkeypatch.setattr(watch, "title_details", lambda kind, meta_id: {"title": "Dune", "poster": None})
    choice = {"source": "Torrentio|abc|0", "audio": {"lang": "eng", "title": ""}, "subtitle": {"off": True}}
    item = companion.send_to_phone(watch, library.config, "open", "movie", "tt1", position=600, connected=lambda c: True,
                                   choice=choice)
    assert item["position"] == 600 and item["source"] == "Torrentio|abc|0"
    assert item["audio"] == {"lang": "eng", "title": ""} and item["subtitle"] == {"off": True}
