def test_a_non_ascii_remote_code_is_rejected_not_an_error():
    from orbital.remote_input import RemoteInput
    remote = RemoteInput()
    remote.start("A", [{"name": "x", "label": "X"}])
    assert remote.form("é") is None  # antes: TypeError (500)
    assert remote.submit("é", {"x": "v"}) is not None
