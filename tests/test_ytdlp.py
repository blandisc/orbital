import hashlib
import threading

import pytest

from orbital import playback, player, ytdlp
from orbital.player import OrbitalPlayer, Segment
from orbital.ytdlp import YtDlp, YtDlpError

EXE_BYTES = b"MZ-yt-dlp-de-mentira"
EXE_SHA = hashlib.sha256(EXE_BYTES).hexdigest()


def release(tag="2026.10.21"):
    return {"tag_name": tag, "assets": [
        {"name": "yt-dlp.exe", "browser_download_url": "https://github.com/yt-dlp/yt-dlp/releases/download/x/yt-dlp.exe"},
        {"name": "SHA2-256SUMS", "browser_download_url": "https://github.com/yt-dlp/yt-dlp/releases/download/x/SHA2-256SUMS"}]}


def service(tmp_path, tag="2026.10.21", sha=EXE_SHA, body=EXE_BYTES):
    fetched = []

    def fetch(url, dest):
        fetched.append(url)
        dest.write_bytes(body)
        return dest

    sums = f"{sha}  yt-dlp.exe\n{'0' * 64}  yt-dlp\n"
    svc = YtDlp(tmp_path / "tools", get_json=lambda url: release(tag), get_text=lambda url: sums, fetch=fetch)
    return svc, fetched


def test_only_a_youtube_id_becomes_an_address():
    assert ytdlp.watch_url("LY19rHKAaAg") == "https://www.youtube.com/watch?v=LY19rHKAaAg"
    for bad in ("", "corto", "con espacios!!", "x" * 12, "--version", "LY19rHKAaAg&list=x"):
        with pytest.raises(ValueError):
            ytdlp.watch_url(bad)


def test_the_format_asks_for_your_dub_and_falls_back_to_the_original():
    assert ytdlp.video_format("en") == "bv*[height<=1080]+ba/b[height<=1080]/b"
    assert ytdlp.video_format("es") == "bv*[height<=1080]+(ba[language^=es]/ba)/b[height<=1080]/b"
    assert ytdlp.video_format("es; rm -rf") == ytdlp.video_format("en")  # nada raro llega a yt-dlp


def test_the_checksum_is_read_from_the_release_list():
    text = f"{'a' * 64} *yt-dlp\n{'B' * 64} *yt-dlp.exe\n"
    assert ytdlp.parse_sums(text) == "b" * 64
    assert ytdlp.parse_sums("basura") is None


def test_it_downloads_checks_and_remembers_the_version(tmp_path):
    svc, fetched = service(tmp_path)
    assert svc.path() is None
    assert svc.ensure() == str(svc.exe)
    assert svc.exe.read_bytes() == EXE_BYTES and svc.version() == "2026.10.21"
    assert not (svc.dir / "yt-dlp.exe.new").exists()
    assert svc.ensure() == str(svc.exe) and len(fetched) == 1  # ya está: no vuelve a bajar


def test_a_damaged_download_is_never_installed(tmp_path):
    svc, _ = service(tmp_path, sha="f" * 64)
    with pytest.raises(YtDlpError, match="dañada"):
        svc.ensure()
    assert not svc.exe.exists() and not (svc.dir / "yt-dlp.exe.new").exists()


def test_no_internet_says_so_in_words(tmp_path):
    with pytest.raises(YtDlpError, match="conexión"):
        YtDlp(tmp_path / "tools").ensure()  # (las pruebas no tienen internet)


def test_a_new_release_replaces_the_old_one_and_the_same_one_does_nothing(tmp_path):
    old, _ = service(tmp_path, tag="2026.09.01")
    old.update()
    assert old.version() == "2026.09.01"
    new, fetched = service(tmp_path, tag="2026.10.21")
    assert new.update() == "2026.10.21" and new.version() == "2026.10.21" and len(fetched) == 1
    assert new.update() is None and len(fetched) == 1  # ya al día


def test_an_update_that_fails_keeps_the_old_one_and_never_raises(tmp_path):
    svc, _ = service(tmp_path, tag="2026.09.01")
    svc.update()
    broken, _ = service(tmp_path, tag="2026.10.21", sha="f" * 64)
    assert broken.update() is None
    assert broken.exe.read_bytes() == EXE_BYTES and broken.version() == "2026.09.01"


def test_the_system_ytdlp_is_used_when_orbital_has_none(tmp_path, monkeypatch):
    svc, fetched = service(tmp_path)
    monkeypatch.setattr(ytdlp, "which", lambda name: "C:/Tools/yt-dlp.exe")
    assert svc.ensure() == "C:/Tools/yt-dlp.exe" and fetched == []


def test_the_mpv_command_gets_ytdlp_only_when_asked():
    plain = playback.build_command("mpv.exe", "http://x/v.mkv", "Peli")
    assert not any("ytdl" in arg for arg in plain)
    cmd = playback.build_command("mpv.exe", "https://www.youtube.com/watch?v=LY19rHKAaAg", "Tráiler",
                                 ytdl="C:/o/tools/yt-dlp.exe", ytdl_format=ytdlp.video_format("es"))
    assert "--ytdl=yes" in cmd and "--script-opts=ytdl_hook-ytdl_path=C:/o/tools/yt-dlp.exe" in cmd
    assert "--ytdl-format=bv*[height<=1080]+(ba[language^=es]/ba)/b[height<=1080]/b" in cmd
    assert cmd[-2:] == ["--", "https://www.youtube.com/watch?v=LY19rHKAaAg"]  # la dirección, siempre después de «--»


# ---------------------------------------------------------------- abrir el tráiler
class FakePlayer:
    def __init__(self):
        self.played, self.segment, self.playing, self.released = [], None, False, 0

    def release_start(self):
        self.released += 1

    def play(self, run, mpv_exe, url, title, meta, **options):
        self.played.append((mpv_exe, url, title, meta, options))
        options["started"](object())


@pytest.fixture
def trailers(library, monkeypatch, tmp_path):
    fake = FakePlayer()
    library.player = fake
    watch = library.watch
    monkeypatch.setattr(player, "find_mpv", lambda: "mpv.exe")
    monkeypatch.setattr(watch.cinemeta, "meta", lambda kind, meta_id, **kw: {"name": "Interstellar", "trailerStreams": [{"ytId": "LY19rHKAaAg"}]})
    watch.trailer_available = lambda video: True
    watch.ytdlp = service(tmp_path)[0]
    library.sessions.revealing = False
    monkeypatch.setattr(library.sessions, "to_front", lambda *a, **k: True)
    monkeypatch.setattr(library.sessions, "pin", lambda: None)
    return watch, fake


def test_the_trailer_opens_in_orbitals_player_not_in_the_browser(trailers, library):
    watch, fake = trailers
    closed = []
    library.sessions.before_launch = closed.append
    opened = []
    library.launcher.open_uri = opened.append
    assert watch.play_trailer("movie", "tt0816692") is True
    mpv_exe, url, title, meta, options = fake.played[0]
    assert (mpv_exe, url, title) == ("mpv.exe", "https://www.youtube.com/watch?v=LY19rHKAaAg", "Interstellar · Tráiler")
    assert opened == [] and closed == ["media:player"]  # ni una página de YouTube
    assert meta["clip"] == "LY19rHKAaAg" and meta["kind"] == "trailer" and meta["detail"] == "Tráiler"
    assert options["ytdl"] == str(watch.ytdlp.exe) and options["subtitles"] == ""
    assert options["ytdl_format"] == ytdlp.video_format(options["audio"])
    # Abre en pausa y empieza cuando se va la pantalla de carga (antes arrancaba uno o dos segundos antes de verse).
    assert options["paused"] is True


def test_the_trailer_starts_when_the_loading_screen_leaves(trailers, library, monkeypatch):
    watch, fake = trailers
    reveals = []
    monkeypatch.setattr(library.sessions, "to_front", lambda *a, **k: reveals.append(k["on_reveal"]) or True)
    watch.play_trailer("movie", "tt0816692")
    assert fake.released == 0  # todavía con la pantalla de carga
    reveals[0]()
    assert fake.released == 1


def test_keep_leaves_what_was_open(trailers, library):
    watch, _ = trailers
    library.sessions.before_launch = lambda *a: pytest.fail("no se cierra nada")
    watch.play_trailer("movie", "tt0816692", keep=True)


def test_the_same_trailer_is_not_opened_twice(trailers):
    watch, fake = trailers
    fake.playing = True
    fake.segment = Segment({"clip": "LY19rHKAaAg"}, "Interstellar · Tráiler", "u")
    watch.play_trailer("movie", "tt0816692")
    assert fake.played == []  # solo se trae al frente


def test_a_title_without_trailer_or_without_ytdlp_says_why(trailers, monkeypatch):
    watch, fake = trailers
    watch.trailer_available = lambda video: False
    with pytest.raises(LookupError, match="no tiene tráiler"):
        watch.play_trailer("movie", "tt0816692")
    watch.trailer_available = lambda video: True
    watch.ytdlp = YtDlp(watch.ytdlp.dir)  # sin internet ni yt-dlp
    with pytest.raises(LookupError, match="conexión"):
        watch.play_trailer("movie", "tt0816692")
    monkeypatch.setattr(player, "find_mpv", lambda: None)
    with pytest.raises(LookupError, match="mpv"):
        watch.play_trailer("movie", "tt0816692")
    assert fake.played == []


# ---------------------------------------------------------------- un tráiler no deja rastro
class Mpv:
    def __init__(self):
        self.props = {"pause": False, "volume": 80, "track-list": []}

    def command(self, *args):
        pass

    def command_named(self, **args):
        pass

    def get(self, prop):
        return self.props.get(prop)


class Script:
    def __init__(self, mpv, steps):
        self.mpv, self.steps = mpv, list(steps)

    def poll(self):
        if not self.steps:
            return 0
        self.mpv.props.update(self.steps.pop(0))
        return None


def watched(meta):
    """Lo que el reproductor guarda, avisa a Trakt y cierra al ver 60 s de un video de 150 s con una pausa en medio."""
    mpv, saved, scrobbled, finished = Mpv(), [], [], []
    p = OrbitalPlayer(mpv=mpv)
    p.POLL = 0
    p.on_progress = lambda *a: saved.append(a)
    p.on_scrobble = lambda *a: scrobbled.append(a)
    p.on_finished = lambda *a: finished.append(a)
    p.current = playback_ = player.Playback("Video", Script(mpv, [
        {"time-pos": 10.0, "duration": 150.0}, {"time-pos": 11.0}, {"time-pos": 12.0, "pause": True}, {"time-pos": 60.0}]), 0, meta)
    p.segment = Segment(meta, "Video", "u")
    p.segment.watched = 30.0  # lo ya visto: el guardado de la pausa tiene algo que guardar
    p._watch(playback_)
    threading.Event().wait(.2)
    return saved, scrobbled, finished


def test_a_trailer_never_saves_progress_nor_tells_trakt():
    movie = {"kind": "movie", "meta_id": "tt0816692", "video_id": "tt0816692", "title": "Interstellar"}
    saved, scrobbled, finished = watched(movie)
    assert saved and scrobbled and finished  # el control: una película sí deja rastro
    saved, scrobbled, finished = watched({**movie, "kind": "trailer", "clip": "LY19rHKAaAg", "trailer_of": "tt0816692"})
    assert saved == [] and scrobbled == [] and finished == []


def test_a_trailer_that_fails_does_not_look_for_another_version(trailers, library):
    watch, _ = trailers
    toasts = []
    library.events.subscribe(toasts.append)
    assert watch._source_failed({"clip": "LY19rHKAaAg", "title": "Interstellar · Tráiler", "kind": "trailer"}, 0.0, False) is False
    assert toasts and "tráiler" in toasts[-1]["message"]


def test_the_more_panel_does_not_open_on_a_trailer():
    p = OrbitalPlayer(mpv=Mpv())
    p.current = type("Cur", (), {"meta": {"clip": "LY19rHKAaAg"}, "title": "T"})()
    p.sources_provider = lambda meta: pytest.fail("un tráiler no tiene versiones")
    p.open_more()
    assert p.menu is None


def test_the_bar_of_a_trailer_does_not_offer_versions_on_any_surface(monkeypatch):
    from orbital import player_ui

    movie = player_ui.Hud(title="Interstellar", position=30, duration=150)
    clip = player_ui.Hud(title="Interstellar · Tráiler", position=30, duration=150, clip=True)
    paused = lambda hud: player_ui.paused_ass(player_ui.Hud(**{**hud.__dict__, "paused": True}))  # noqa: E731
    for draw, main_button in ((player_ui.hud_ass, "Pausa"), (paused, "Continuar")):
        assert "Versión" in draw(movie)
        assert "Versión" not in draw(clip) and main_button in draw(clip)  # el tráiler conserva lo demás
    monkeypatch.setattr(player_ui, "TOUCH", True)
    labels = [label for label, _ in player_ui._touch_items(clip, paused=False)]
    assert "Versión" not in labels and labels[:2] == ["−10 s", "Pausa"] and labels[-1] == "Salir"
    assert "Versión" in [label for label, _ in player_ui._touch_items(movie, paused=False)]
