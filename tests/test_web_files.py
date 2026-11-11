"""La interfaz viaja comprimida y se revalida (R3-7, 11 nov 2026): `WebFiles` manda el JS, el CSS, el SVG y el HTML con gzip
cuando el navegador lo acepta, contesta 304 si no cambió y, tras una actualización (otra fecha u otro tamaño), trae lo nuevo."""

from __future__ import annotations

import gzip
import os

from starlette.applications import Starlette
from starlette.routing import Mount
from starlette.testclient import TestClient

from orbital.server import WEB_DIR, WebFiles

BIG_JS = "export const hola = " + repr("orbital " * 400) + ";\n"


def client(tmp_path):
    (tmp_path / "app.js").write_bytes(BIG_JS.encode())  # bytes: en Windows write_text pondría \r\n
    (tmp_path / "tiny.css").write_bytes(b"a{}")
    (tmp_path / "art.png").write_bytes(b"\x89PNG" + b"0" * 4000)
    (tmp_path / "index.html").write_bytes(("<!doctype html><title>Orbital</title>" + "<p>hola</p>" * 200).encode())
    app = Starlette(routes=[Mount("/", WebFiles(directory=tmp_path, html=True))])
    return TestClient(app)


def raw(c, path, **headers):
    """Sin que el cliente descomprima: lo que viaja de verdad."""
    with c.stream("GET", path, headers=headers) as res:
        return res, b"".join(res.iter_raw())


def test_js_travels_gzipped_and_is_the_same_file(tmp_path):
    c = client(tmp_path)
    res, body = raw(c, "/app.js", **{"accept-encoding": "gzip, deflate, br"})
    assert res.status_code == 200
    assert res.headers["content-encoding"] == "gzip"
    assert res.headers["cache-control"] == "no-cache"
    assert res.headers["vary"] == "Accept-Encoding"
    assert res.headers["etag"].endswith('-gz"')
    assert "javascript" in res.headers["content-type"]
    assert gzip.decompress(body).decode() == BIG_JS
    assert len(body) < len(BIG_JS.encode()) / 5


def test_the_home_page_is_gzipped_too(tmp_path):
    res, body = raw(client(tmp_path), "/", **{"accept-encoding": "gzip"})
    assert res.headers["content-encoding"] == "gzip"
    assert gzip.decompress(body).startswith(b"<!doctype html>")


def test_unchanged_file_answers_304_with_either_validator(tmp_path):
    c = client(tmp_path)
    first, _ = raw(c, "/app.js", **{"accept-encoding": "gzip"})
    again, body = raw(c, "/app.js", **{"accept-encoding": "gzip", "if-none-match": first.headers["etag"]})
    assert again.status_code == 304 and body == b""
    assert again.headers["etag"] == first.headers["etag"]
    since, _ = raw(c, "/app.js", **{"accept-encoding": "gzip", "if-modified-since": first.headers["last-modified"]})
    assert since.status_code == 304


def test_after_an_update_the_reload_brings_the_new_file(tmp_path):
    c = client(tmp_path)
    old, _ = raw(c, "/app.js", **{"accept-encoding": "gzip"})
    newer = BIG_JS.replace("hola", "adios")
    path = tmp_path / "app.js"
    path.write_bytes(newer.encode())
    st = path.stat()
    os.utime(path, ns=(st.st_atime_ns, st.st_mtime_ns + 2_000_000_000))  # la actualización deja otra fecha
    res, body = raw(c, "/app.js", **{"accept-encoding": "gzip", "if-none-match": old.headers["etag"]})
    assert res.status_code == 200
    assert res.headers["etag"] != old.headers["etag"]
    assert gzip.decompress(body).decode() == newer


def test_without_gzip_small_files_and_images_go_as_they_are(tmp_path):
    c = client(tmp_path)
    plain, body = raw(c, "/app.js", **{"accept-encoding": "identity"})  # el cliente de pruebas pide gzip si no se le dice
    assert "content-encoding" not in plain.headers and body.decode() == BIG_JS
    assert not plain.headers["etag"].endswith('-gz"')
    assert plain.headers["vary"] == "Accept-Encoding" and plain.headers["cache-control"] == "no-cache"
    for path in ("/tiny.css", "/art.png"):
        res, _ = raw(c, path, **{"accept-encoding": "gzip"})
        assert res.status_code == 200 and "content-encoding" not in res.headers, path
    plain_304, _ = raw(c, "/app.js", **{"accept-encoding": "identity", "if-none-match": plain.headers["etag"]})
    assert plain_304.status_code == 304


def test_the_real_interface_files_compress(tmp_path):
    """Con la interfaz de verdad: main.js y el tema viajan comprimidos (y bastante)."""
    c = TestClient(Starlette(routes=[Mount("/", WebFiles(directory=WEB_DIR, html=True))]))
    for path in ("/js/main.js", "/styles/themes/orbital.css"):
        res, body = raw(c, path, **{"accept-encoding": "gzip"})
        assert res.headers.get("content-encoding") == "gzip", path
        assert len(body) < (WEB_DIR / path.lstrip("/")).stat().st_size / 2.5, path
