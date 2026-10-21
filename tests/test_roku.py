"""La tele (Roku TV): «Alexa, abre Orbital» la prende y la pone en la entrada de Orbital. Una Roku de mentira."""

import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

from orbital import roku
from orbital.config import TvConfig, parse_config
from orbital.voice import VoiceController


class FakeRoku:
    """Contesta como la ECP de una Roku: device-info, active-app, keypress y launch."""

    def __init__(self, power="Ready", app='<app id="562859" type="home">Roku</app>'):
        self.power, self.app, self.posts = power, app, []
        fake = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def _send(self, body: str):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(body.encode())

            def do_GET(self):
                if self.path == "/query/device-info":
                    self._send(f"<device-info><friendly-device-name>Sala</friendly-device-name><serial-number>X1"
                               f"</serial-number><network-type>wifi</network-type><wifi-mac>aa:bb:cc:dd:ee:ff"
                               f"</wifi-mac><power-mode>{fake.power}</power-mode></device-info>")
                else:
                    self._send(f"<active-app>{fake.app}</active-app>")

            def do_POST(self):
                fake.posts.append(self.path)
                if self.path == "/keypress/PowerOn":
                    fake.power = "PowerOn"
                self._send("")

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    @property
    def port(self):
        return self.server.server_address[1]


@pytest.fixture
def fake(monkeypatch):
    tv = FakeRoku()
    monkeypatch.setattr(roku, "PORT", tv.port)
    yield tv
    tv.server.shutdown()


def test_turn_on_powers_and_switches_input(fake):
    assert roku.RokuTv(TvConfig(host="127.0.0.1", input="hdmi2")).turn_on()
    assert fake.posts == ["/keypress/PowerOn", "/launch/tvinput.hdmi2"]


def test_already_on_only_switches_input(fake):
    fake.power = "PowerOn"
    assert roku.RokuTv(TvConfig(host="127.0.0.1")).turn_on()
    assert fake.posts == ["/launch/tvinput.hdmi1"]


def test_without_host_does_nothing(fake):
    assert not roku.RokuTv(TvConfig()).turn_on()
    assert fake.posts == []


def test_describe_finds_the_input_being_watched(fake):
    fake.power, fake.app = "PowerOn", '<app id="tvinput.hdmi1" type="tvin">Lenovo</app>'
    found = roku.describe(roku.Found("127.0.0.1"))
    assert (found.name, found.power, found.input, found.serial, found.mac) == (
        "Sala", "PowerOn", "hdmi1", "X1", "aa:bb:cc:dd:ee:ff")


def test_open_orbital_turns_on_the_tv():
    class Tv:
        enabled, calls = True, 0

        def turn_on_soon(self):
            self.calls += 1

    class Kiosk:
        opened = False

        def open(self):
            self.opened = True

    tv, kiosk = Tv(), Kiosk()
    voice = VoiceController(catalog=None, kiosk=kiosk, tv=tv)  # type: ignore[arg-type] - no hace falta el catálogo
    result = voice.handle_intent("OpenOrbitalIntent")
    assert result.ok and kiosk.opened and tv.calls == 1


def test_save_replaces_the_tv_section_and_keeps_the_rest(tmp_path):
    path = tmp_path / "config.yaml"
    path.write_text("server:\n  port: 8710  # comentario\n\ntv:\n  host: 10.0.0.1\n  input: hdmi3\n\nui:\n  mode: browser\n",
                    encoding="utf-8")
    roku.save(path, roku.Found("192.168.1.177", "X1", "aa:bb:cc:dd:ee:ff", input="hdmi1"))
    text = path.read_text(encoding="utf-8")
    assert "# comentario" in text and "mode: browser" in text and "10.0.0.1" not in text
    import yaml
    cfg = parse_config(yaml.safe_load(text))
    assert (cfg.tv.host, cfg.tv.serial, cfg.tv.mac, cfg.tv.input) == ("192.168.1.177", "X1", "aa:bb:cc:dd:ee:ff", "hdmi1")


def test_config_rejects_unknown_input():
    assert parse_config({"tv": {"input": "tvinput.HDMI2"}}).tv.input == "hdmi2"
    with pytest.raises(ValueError):
        parse_config({"tv": {"input": "netflix"}})
