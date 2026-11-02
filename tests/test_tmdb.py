

def test_a_persons_jobs_and_roles_come_in_spanish():
    """TMDB da los cargos en inglés aunque se pida en español: la filmografía de una persona los dice en español."""
    from orbital.library.tmdb import role_es
    assert role_es({"job": "Producer"}, False) == "Producción"
    assert role_es({"job": "Thanks"}, False) == "Agradecimientos"
    assert role_es({"job": "Gaffer", "department": "Lighting"}, False) == "Iluminación"
    assert role_es({"character": "Self"}, True) == "Como sí mismo"
    assert role_es({"character": "Bart Simpson (voice)"}, True) == "Bart Simpson (voz)"
    assert role_es({"character": ""}, True) is None
