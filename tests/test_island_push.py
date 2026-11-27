"""LA-B: la TV mantiene al día la isla «Viendo en la TV» del iPhone (orbital/island_push.py)."""

import base64
import json

import pytest

from orbital import island_push as ip


def _pem(d: int) -> str:
    """Una llave .p8 de mentira con la forma de las de Apple (PKCS#8 con ECPrivateKey)."""
    der = bytes.fromhex("308187020100301306072a8648ce3d020106082a8648ce3d030107046d306b0201010420") + d.to_bytes(32, "big")
    return "-----BEGIN PRIVATE KEY-----\n" + base64.b64encode(der).decode() + "\n-----END PRIVATE KEY-----\n"


def test_signature_is_valid_es256():
    d = 0x1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDE
    assert ip.private_key(_pem(d)) == d
    token = ip.provider_token("ABC123DEFG", d, now=1_800_000_000)
    head, claims, sig = token.split(".")
    pad = lambda s: base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))  # noqa: E731
    assert json.loads(pad(head)) == {"alg": "ES256", "kid": "ABC123DEFG"}
    assert json.loads(pad(claims)) == {"iss": ip.TEAM_ID, "iat": 1_800_000_000}
    assert ip.verify(ip._mul(d), f"{head}.{claims}".encode(), pad(sig))
    assert not ip.verify(ip._mul(d + 1), f"{head}.{claims}".encode(), pad(sig))


def test_status_reads_indexed_and_huffman():
    assert ip._status(b"\x88") == 200
    assert ip._status(b"\x48\x03403") == 403
    assert ip._status(b"\x48\x83\x68\x20\x7f") == 410  # en Huffman


def _now(**over):
    base = {"kind": "series", "live": False, "meta_id": "tt5753856", "title": "Dark", "episode_title": "Secretos",
            "season": 1, "episode": 1, "position": 100.0, "duration": 3000.0, "paused": False}
    return {**base, **over}


def _island(tmp_path, playing, sent):
    (tmp_path / "AuthKey_ABC123DEFG.p8").write_text(_pem(12345), "utf-8")
    clock = {"t": 1_800_000_000.0}

    def send(host, path, headers, body):
        sent.append((host, path, headers, json.loads(body)))
        return 200, b""
    island = ip.IslandPush(tmp_path, lambda: playing["now"], send=send, clock=lambda: clock["t"])
    island.start = lambda: None  # sin hilo en la prueba
    island.register("ab" * 32, "es", sandbox=True)
    return island, clock


def test_tells_the_island_when_the_episode_changes(tmp_path):
    playing, sent = {"now": _now()}, []
    island, clock = _island(tmp_path, playing, sent)
    assert island.tick()
    host, path, headers, body = sent[-1]
    assert host == "api.sandbox.push.apple.com" and path == "/3/device/" + "ab" * 32
    assert headers["apns-push-type"] == "liveactivity" and headers["apns-topic"] == ip.TOPIC
    state = body["aps"]["content-state"]
    assert state["title"] == "Secretos" and state["detail"] == "T1 E1" and state["poster"] == "tv-tt5753856.jpg"
    assert state["measuredAt"] == pytest.approx(1_800_000_000 - ip.APPLE_EPOCH)
    clock["t"] += 2
    playing["now"] = _now(position=102.0)
    assert not island.tick()  # la barra sigue sola: nada que avisar
    playing["now"] = _now(episode=2, episode_title="Mentiras", position=0.0)
    assert island.tick() and sent[-1][3]["aps"]["content-state"]["detail"] == "T1 E2"
    playing["now"] = _now(episode=2, episode_title="Mentiras", position=2.0, paused=True)
    assert island.tick() and sent[-1][3]["aps"]["content-state"]["paused"] is True
    playing["now"] = None
    assert island.tick() and sent[-1][3]["aps"]["event"] == "end"
    assert not island.tick()  # ya terminó: no se repite


def test_without_the_apple_key_nothing_is_sent(tmp_path):
    playing, sent = {"now": _now()}, []
    island, _ = _island(tmp_path, playing, sent)
    (tmp_path / "AuthKey_ABC123DEFG.p8").unlink()
    assert not island.tick() and sent == []


def test_a_gone_activity_forgets_its_mailbox(tmp_path):
    playing = {"now": _now()}
    island, _ = _island(tmp_path, playing, [])
    island.send = lambda *a: (410, b'{"reason":"Unregistered"}')
    assert not island.tick()
    assert island.registration() is None


def test_bad_mailbox_is_refused(tmp_path):
    island = ip.IslandPush(tmp_path, lambda: None)
    with pytest.raises(ValueError):
        island.register("no es hex", "es", sandbox=False)
