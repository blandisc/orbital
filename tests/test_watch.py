

def test_a_trailer_youtube_removed_is_not_offered():
    """Cinemeta a veces trae el id de un tráiler borrado o privado: oEmbed dice 404/401 y «Tráiler» no sale."""
    import urllib.error

    from orbital import watch as watch_mod

    def answer(code):
        def open_url(url, timeout):
            raise urllib.error.HTTPError(url, code, "x", {}, None)
        return open_url

    watch_mod._YOUTUBE_SEEN.clear()
    assert not watch_mod.youtube_available("borrado", open_url=answer(404))
    assert not watch_mod.youtube_available("privado", open_url=answer(401))
    assert watch_mod.youtube_available("caido", open_url=answer(503))  # YouTube con problemas: no se esconde

    def offline(url, timeout):
        raise OSError("sin red")
    assert watch_mod.youtube_available("sinred", open_url=offline)
    assert "sinred" not in watch_mod._YOUTUBE_SEEN  # un tropiezo de red no se recuerda
