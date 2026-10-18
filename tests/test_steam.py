

def test_tools_servers_and_demos_are_not_games():
    from orbital.library.steam import _is_game

    for name in ("Left 4 Dead 2 Dedicated Server", "Halo MCC Mod Uploader", "Resident Evil 6 Benchmark Tool",
                 "Midnight Ghost Hunt Playtest", "Bad North Demo", "Age of Empires IV Technical Stress Test",
                 "Steam 360 Video Player", "Source Filmmaker"):
        assert not _is_game("1", name), name
    for name in ("Hades", "Demon's Souls", "Server Simulator Pro", "DOOM"):
        assert _is_game("1", name), name
