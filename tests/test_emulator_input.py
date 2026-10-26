"""Los controles de Switch, como en una consola: el que abre el juego es el Jugador 1 y A es A (emulator_input)."""

import json

from orbital import emulator_input, gamepad

LEGION = (0x17EF, 0x61EB)
GAMESIR = (0x3537, 0x1040)
XBOX = (0x045E, 0x0B12)
LEGION_GUID = "03000000ef170000eb61000000017801"
GAMESIR_GUID = "03000000373500004010000000017801"


def eden_block(n: int, guid: str, abxy=(0, 1, 3, 2), connected="true") -> str:
    a, b, x, y = abxy
    lines = [f"player_{n}_type\\default=true", f"player_{n}_type=0",
             f"player_{n}_connected\\default={'true' if n == 0 else 'false'}", f"player_{n}_connected={connected}"]
    for key, button in (("a", a), ("b", b), ("x", x), ("y", y), ("l", 4)):
        lines += [f"player_{n}_button_{key}\\default=false", f'player_{n}_button_{key}="engine:sdl,port:0,guid:{guid},button:{button}"']
    lines += [f"player_{n}_lstick\\default=false", f'player_{n}_lstick="engine:sdl,port:0,guid:{guid},axis_x:0,axis_y:1"']
    return "\n".join(lines)


def eden_config(tmp_path, *blocks: str):
    path = tmp_path / "qt-config.ini"
    others = "\n".join(f"player_{n}_connected\\default=true\nplayer_{n}_connected=false" for n in range(len(blocks), 10))
    path.write_text("[UI]\nx=1\n[Controls]\nenable_raw_input=false\n" + "\n".join(blocks) + "\n" + others + "\n[Core]\ny=2\n",
                    encoding="utf-8")
    return path


def values(path) -> dict:
    return dict(line.split("=", 1) for line in path.read_text(encoding="utf-8").splitlines() if "=" in line)


def test_eden_the_controller_that_opened_the_game_is_player_one_and_a_is_a(tmp_path):
    """Como estaba: Legion de Jugador 1 (X/Y cruzados) y GameSir de 2 (A/B cruzados). Abres con el GameSir: él es el 1, la
    Legion el 2, y en los dos A es A."""
    path = eden_config(tmp_path, eden_block(0, LEGION_GUID, (0, 1, 3, 2)), eden_block(1, GAMESIR_GUID, (1, 0, 3, 2)))
    assert emulator_input.arrange_eden(path, [GAMESIR, LEGION])
    v = values(path)
    assert GAMESIR_GUID in v["player_0_button_a"] and LEGION_GUID in v["player_1_button_a"]
    for n in (0, 1):
        assert [v[f"player_{n}_button_{k}"][-9:] for k in "abxy"] == ['button:0"', 'button:1"', 'button:2"', 'button:3"']
        assert v[f"player_{n}_connected"] == "true" and v[f"player_{n}_connected\\default"] == "false"
        assert "button:4" in v[f"player_{n}_button_l"] and "axis_x:0" in v[f"player_{n}_lstick"]  # lo demás, igual
    assert v["player_2_connected"] == "false"
    assert v["x"] == "1" and v["y"] == "2" and v["enable_raw_input"] == "false"  # las otras secciones, intactas
    assert (tmp_path / "qt-config.ini.antes-de-orbital").exists()
    assert not emulator_input.arrange_eden(path, [GAMESIR, LEGION])  # ya estaba así: no se reescribe


def test_eden_only_one_controller_on_leaves_the_others_disconnected(tmp_path):
    path = eden_config(tmp_path, eden_block(0, LEGION_GUID), eden_block(1, GAMESIR_GUID))
    assert emulator_input.arrange_eden(path, [LEGION])
    v = values(path)
    assert LEGION_GUID in v["player_0_button_a"] and v["player_1_connected"] == "false"


def test_a_controller_never_set_up_is_left_out_not_invented(tmp_path):
    """Un control que el emulador nunca vio (un Xbox nuevo) no se inventa: juegan los que sí tienen mapeo."""
    path = eden_config(tmp_path, eden_block(0, LEGION_GUID), eden_block(1, GAMESIR_GUID))
    assert emulator_input.arrange_eden(path, [XBOX, GAMESIR])
    v = values(path)
    assert GAMESIR_GUID in v["player_0_button_a"] and v["player_1_connected"] == "false"
    assert not emulator_input.arrange_eden(eden_config(tmp_path, eden_block(0, LEGION_GUID)), [XBOX])  # nada conocido: no se toca


def ryujinx_pad(device_id: str, player: str, a="A", b="B") -> dict:
    return {"left_joycon": {"button_l": "LeftShoulder"}, "right_joycon": {"button_a": a, "button_b": b, "button_x": "Y", "button_y": "X"},
            "backend": "GamepadSDL2", "id": device_id, "name": "pad", "controller_type": "ProController", "player_index": player}


def test_ryujinx_takes_the_legion_mapping_from_a_game_config_and_puts_the_one_you_used_first(tmp_path):
    """Como estaba: la global con el GameSir de Jugador 1 y de 2 (la Legion no hacía nada); la Legion solo estaba en la de
    un juego. Abres con la Legion: es el 1 en la global, el GameSir el 2, y A es A."""
    legion_id, gamesir_id = "0-00000003-17ef-0000-eb61-000000007200", "0-00000003-3537-0000-4010-000000007200"
    glob = tmp_path / "Config.json"
    glob.write_text(json.dumps({"version": 70, "input_config": [ryujinx_pad(gamesir_id, "Player1"), ryujinx_pad(gamesir_id, "Player2"),
                                                                {"backend": "WindowKeyboard", "id": "0", "player_index": "Player5"}]}),
                    encoding="utf-8")
    game = tmp_path / "games" / "0100" / "Config.json"
    game.parent.mkdir(parents=True)
    game.write_text(json.dumps({"input_config": [ryujinx_pad(legion_id, "Player1", a="B", b="A")]}), encoding="utf-8")
    assert emulator_input.ryujinx_device({"backend": "GamepadSDL2", "id": legion_id}) == LEGION
    profiles = emulator_input.ryujinx_profiles([glob, game])
    assert set(profiles) == {LEGION, GAMESIR}
    assert emulator_input.arrange_ryujinx(glob, [LEGION, GAMESIR], profiles)
    pads = json.loads(glob.read_text(encoding="utf-8"))["input_config"]
    assert [(p["id"], p["player_index"]) for p in pads] == [(legion_id, "Player1"), (gamesir_id, "Player2"), ("0", "Player5")]
    assert all(p["right_joycon"]["button_a"] == "A" and p["right_joycon"]["button_x"] == "X" for p in pads[:2])
    assert emulator_input.arrange_ryujinx(game, [LEGION, GAMESIR], profiles)  # el del juego también (no usa la global)
    assert not emulator_input.arrange_ryujinx(glob, [LEGION, GAMESIR], profiles)


def test_two_identical_controllers_get_their_own_number():
    assert emulator_input.assign([GAMESIR, GAMESIR, LEGION], {GAMESIR, LEGION}) == [(GAMESIR, 0), (GAMESIR, 1), (LEGION, 0)]


def test_play_order_puts_the_last_controller_used_first():
    watcher = gamepad.GamepadWatcher(lambda event: None)
    watcher.devices = {0: LEGION, 1: GAMESIR, 2: XBOX}
    watcher.last_used = 1
    gamepad._watcher = watcher
    try:
        assert gamepad.play_order() == [GAMESIR, LEGION, XBOX]
        watcher.last_used = 3  # ya se apagó: el orden de siempre
        assert gamepad.play_order() == [LEGION, GAMESIR, XBOX]
    finally:
        gamepad._watcher = None
    assert gamepad.play_order() == []
