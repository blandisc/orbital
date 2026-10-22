"""Lo que eliges para cada título (audio, latino o castellano, subtítulos) vale en la TV y en el iPhone: el iPhone manda lo
que cambió y recibe lo que cambió en la TV. Si los dos lo cambiaron, gana el último que la TV vio; nunca se pisa a ciegas."""

from test_alexa import public  # noqa: F401 - fixture

from orbital.state import State

AUTH = {"Authorization": "Bearer secreto"}


def test_la_tv_cuenta_cada_cambio_y_da_solo_lo_nuevo():
    s = State(None)
    assert s.choices_since(0) == (0, {})
    s.set_pref("stremio:tt0096697", "audio", "es")
    s.set_pref("stremio:tt0096697", "spanish", "es-419")
    s.set_pref("stremio:tt0096697", "resume", {"video_id": "x"})  # «Continuar» es de la TV: no cuenta
    rev, changed = s.choices_since(0)
    assert rev == 2 and changed == {"tt0096697": {"audio": "es", "spanish": "es-419", "rev": 2}}
    assert s.choices_since(2) == (2, {})
    s.set_pref("stremio:tt0096697", "spanish", "es-419")  # lo mismo: no es cambio
    assert s.choices_since(2) == (2, {})
    s.set_pref("stremio:tt0386676", "subtitles", "en")
    assert list(s.choices_since(2)[1]) == ["tt0386676"]


def test_lo_del_iphone_se_aplica_y_si_la_tv_cambio_despues_gana_la_tv():
    s = State(None)
    assert s.apply_choice("tt1", {"audio": "es", "spanish": "es-ES"}, base_rev=0)
    assert s.prefs("stremio:tt1")["spanish"] == "es-ES"
    rev = s.prefs("stremio:tt1")["rev"]
    s.set_pref("stremio:tt1", "spanish", "es-419")  # luego lo cambiaste en la TV
    assert not s.apply_choice("tt1", {"spanish": "es-ES"}, base_rev=rev)  # el iPhone no lo había visto: gana la TV
    assert s.prefs("stremio:tt1")["spanish"] == "es-419"
    assert s.apply_choice("tt1", {"spanish": "es-ES"}, base_rev=s.prefs("stremio:tt1")["rev"])
    # Valores raros no entran (ni rompen nada).
    s.apply_choice("tt1", {"audio": "<script>", "subtitles": "zzzzzz", "hidden": True}, base_rev=999)
    assert s.prefs("stremio:tt1")["audio"] == "es" and "hidden" not in s.prefs("stremio:tt1")


def test_olvidar_un_titulo_tambien_llega_al_iphone():
    s = State(None)
    s.set_pref("stremio:tt1", "audio", "en")
    s.set_pref("stremio:tt1", "subtitles", "es")
    rev = s.choices_since(0)[0]
    assert [m for m, _ in s.remembered_titles()] == ["tt1"]
    s.forget_choices("tt1")
    assert s.remembered_titles() == []
    assert s.choices_since(rev)[1] == {"tt1": {"rev": rev + 1}}  # sin campos: el iPhone lo olvida


def test_la_revision_sobrevive_al_reinicio(tmp_path):
    s = State(tmp_path / "state.json")
    s.set_pref("stremio:tt1", "audio", "es")
    assert State(tmp_path / "state.json").choices_since(0)[0] == 1


def test_el_iphone_sincroniza_por_la_app_publica(public):  # noqa: F811
    client, main = public
    state = main.state.catalog.state
    state.set_pref("stremio:tt0096697", "audio", "es")
    body = {"since": 0, "changes": {"tt0386676": {"audio": "en", "subtitles": "es", "base_rev": 0},
                                    "../etc": {"audio": "en"}}}
    assert client.post("/api/companion/choices", json=body).status_code == 401  # sin la llave, nada
    got = client.post("/api/companion/choices", json=body, headers=AUTH).json()
    assert got["rejected"] == [] and set(got["changed"]) == {"tt0096697", "tt0386676"}
    assert state.prefs("stremio:tt0386676") == {"audio": "en", "subtitles": "es", "rev": 2}
    assert "stremio:../etc" not in main.state.catalog.state._data["prefs"]
    # La TV lo cambia; el iPhone, sin haberlo visto, manda lo suyo: gana la TV y le llega su valor.
    state.set_pref("stremio:tt0386676", "subtitles", "")
    got = client.post("/api/companion/choices", json={"since": 2, "changes": {"tt0386676": {"subtitles": "en", "base_rev": 2}}},
                      headers=AUTH).json()
    assert got["rejected"] == ["tt0386676"] and got["changed"]["tt0386676"]["subtitles"] == ""
    forget = {"since": got["rev"], "changes": {"tt0386676": {"forget": ["subtitles"], "base_rev": got["rev"]}}}
    client.post("/api/companion/choices", json=forget, headers=AUTH)
    assert "subtitles" not in state.prefs("stremio:tt0386676")
    big = {"since": 0, "changes": {f"tt{i}": {"audio": "en"} for i in range(101)}}
    assert client.post("/api/companion/choices", json=big, headers=AUTH).status_code == 422  # no más de 100 a la vez
