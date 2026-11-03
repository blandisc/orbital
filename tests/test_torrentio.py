"""Torrentio con tus opciones («La TV sin Stremio», corte S3): la TV arma la misma dirección que el iPhone
(tests/fixtures/torrentio-config.json, compartido con TorrentioConfigTests.swift)."""

import json
from pathlib import Path

from orbital.library import torrentio

FIXTURE = json.loads((Path(__file__).parent / "fixtures" / "torrentio-config.json").read_text(encoding="utf-8"))


def test_the_same_address_as_the_iphone():
    for case in FIXTURE["cases"]:
        got = torrentio.manifest_url(case["options"], "{CLAVE}", FIXTURE["base"])
        assert got is not None
        assert got.replace("%7BCLAVE%7D", "{CLAVE}") == case["url"], case["name"]


def test_read_back_from_stremio():
    for case in [c for c in FIXTURE["cases"] if c["parse"]]:
        options, key = torrentio.parse(case["url"].replace("{CLAVE}", "ABC"))
        assert key == "ABC", case["name"]
        for name, value in case["options"].items():
            assert options[name] == value, (case["name"], name)


def test_unknown_parts_are_kept_and_other_keys_never():
    options, key = torrentio.parse("https://torrentio.strem.fun/sort=seeders|foo=bar|premiumize=SECRETO|realdebrid=K/manifest.json")
    assert key == "K" and options["verbatim"] == ["foo=bar"]
    assert torrentio.manifest_url(options, "K") == "https://torrentio.strem.fun/sort=seeders|foo=bar|realdebrid=K/manifest.json"
    assert torrentio.parse("https://comet.elfhosted.com/x/manifest.json") is None
    assert torrentio.manifest_url(torrentio.RECOMMENDED, None) is None  # sin clave no hay dirección


def test_sizes():
    assert torrentio.sizes("10GB,2GB") == ("10GB", "2GB")
    assert torrentio.sizes("5GB") == ("5GB", "5GB")
    assert torrentio.sizes(None) == (None, None)
    assert torrentio.sizefilter(None, "2GB") == "1000GB,2GB"
    assert torrentio.sizefilter("5GB", "5GB") == "5GB"
