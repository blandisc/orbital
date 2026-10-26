from orbital.foryou import Cache


def test_clear_is_persisted_to_disk(tmp_path):
    path = tmp_path / "foryou-cache.json"
    first = Cache(path=path)
    assert first.get("trakt:recs:series", 3600, lambda: [{"imdb": "tt1"}]) == [{"imdb": "tt1"}]
    first._save()
    first.clear("trakt:")
    again = Cache(path=path)
    assert again.peek("trakt:recs:series") is None
