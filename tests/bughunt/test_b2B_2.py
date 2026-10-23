def test_state_save_does_not_raise_on_a_lone_surrogate(tmp_path):
    from orbital.state import State
    state = State(tmp_path / "state.json")
    state.dismiss("game:\ud800")  # antes: UnicodeEncodeError (500) y el estado no se guardaba
