

def test_online_asks_once_and_remembers(monkeypatch):
    """«Sin Internet» en la barra: una conexión de salida por IP, recordada 20 s (sin red en la prueba)."""
    import importlib

    from orbital import system as real

    module = importlib.reload(real)  # la de verdad (conftest la sustituye por True)
    tried = []

    def refuse(host, timeout):
        tried.append(host)
        raise OSError("sin red")

    monkeypatch.setattr(module.socket, "create_connection", refuse)
    monkeypatch.setattr(module, "_online_cache", (0.0, True))
    assert module.online() is False and len(tried) == 2
    assert module.online() is False and len(tried) == 2  # recordado: no vuelve a preguntar
