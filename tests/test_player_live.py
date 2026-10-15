"""El reproductor en modo TV en vivo: caché corta, cambio de canal en el mismo mpv, sin progreso, sin episodios."""

import re
import threading

from test_player import make_player

from orbital import player, player_ui

URL = "https://tv.example.mx/a/playlist.m3u8"
CHANNELS = [{"id": f"c{i}", "name": f"Canal {i}", "number": i, "category": "Noticias", "quality": "720p"} for i in range(1, 5)]
META = {"kind": "tv", "live": True, "channel_id": "c2", "title": "Canal 2", "number": 2, "category": "Noticias", "quality": "720p"}


def live_player(**props):
    """Un reproductor con el canal 2 de 4 al aire (ya con imagen)."""
    p, mpv = make_player(**{"time-pos": 33.0, "duration": None, "path": URL, "idle-active": False, "mute": False, **props})
    p.current.meta = dict(META)
    p.current.title = "Canal 2"
    p.current.process = type("Proc", (), {"poll": lambda self: None})()
    p.segment = player.Segment(dict(META), "Canal 2", URL, live=True, playing=True)
    p.channels_provider = lambda meta, category=None: {
        "category": category or "todos", "channels": [{**c, "current": c["id"] == meta.get("channel_id")} for c in CHANNELS],
        "categories": [{"id": "todos", "label": "Todos", "current": True}, {"id": "noticias", "label": "Noticias"}]}
    return p, mpv


# --- el comando de mpv -----------------------------------------------------------------------
def test_comando_en_vivo_usa_cache_corta_y_reconexion_no_los_400_mib():
    cmd = player.build_command("mpv.exe", URL, "Canal 2", live=True, audio="es", subtitles="", start=900)
    assert "--demuxer-max-bytes=400MiB" not in cmd and "--demuxer-max-bytes=48MiB" in cmd
    assert "--cache-secs=8" in cmd and "--demuxer-readahead-secs=8" in cmd
    assert any(a.startswith("--stream-lavf-o=reconnect=1") for a in cmd) and "--network-timeout=10" in cmd
    assert not any(a.startswith("--start") for a in cmd)  # en vivo no hay punto donde seguir
    assert "--sid=no" in cmd and "--alang=es,spa,Spanish,es-419" in cmd
    assert cmd[-2:] == ["--", URL]


def test_comando_normal_no_cambia():
    cmd = player.build_command("mpv.exe", URL, "Peli")
    assert "--demuxer-max-bytes=400MiB" in cmd and not any("reconnect" in a for a in cmd)
    assert not any(a.startswith(("--user-agent", "--referrer")) for a in cmd)


def test_el_canal_trae_su_user_agent_y_referer_o_los_de_siempre():
    plain = player.build_command("mpv.exe", URL, "x", live=True)
    assert f"--user-agent={player.LIVE_USER_AGENT}" in plain and not any(a.startswith("--referrer") for a in plain)
    own = player.build_command("mpv.exe", URL, "x", live=True, user_agent="OrbitalTest/1", referrer="https://sitio.example.mx/")
    assert "--user-agent=OrbitalTest/1" in own and "--referrer=https://sitio.example.mx/" in own


# --- cambiar de canal ------------------------------------------------------------------------
def test_tune_usa_loadfile_replace_en_el_mismo_mpv_con_las_cabeceras_del_canal():
    p, mpv = live_player()
    old = p.segment
    new_meta = {**META, "channel_id": "c3", "title": "Canal 3", "number": 3}
    assert p.tune("https://tv.example.mx/c3.m3u8", "Canal 3", new_meta, user_agent="OrbitalTest/9", referrer="https://sitio.example.mx/")
    assert ("loadfile", "https://tv.example.mx/c3.m3u8", "replace", -1,
            {"user-agent": "OrbitalTest/9", "referrer": "https://sitio.example.mx/"}) in mpv.sent
    assert p.segment is not old and p.segment.live and not p.segment.playing and old.closed
    assert p.current.title == "Canal 3"
    assert "Canal 3" in mpv.overlays[1] and "Sintonizando" in mpv.overlays[1]


def test_tune_siguiente_canal_sin_cabeceras_borra_las_del_anterior():
    p, mpv = live_player()
    p.tune("https://tv.example.mx/c3.m3u8", "Canal 3", {**META, "channel_id": "c3"})
    load = next(c for c in mpv.sent if c[0] == "loadfile")
    assert load[4] == {"user-agent": player.LIVE_USER_AGENT, "referrer": ""}  # el Referer anterior no se hereda


def test_tune_sin_mpv_abierto_dice_que_no():
    p, _ = live_player()
    p.current.process = type("Proc", (), {"poll": lambda self: 0})()
    assert p.tune("u", "x", META) is False


def test_no_guarda_progreso_ni_seguir_viendo():
    p, mpv = live_player()
    saved = []
    p.on_progress = p.on_finished = lambda *a: saved.append(a)
    p.segment.watched, p.segment.duration = 600, 6000
    p._save_progress(p.segment)
    p._close_segment(p.segment)
    p.finish(p.current)
    assert saved == []


# --- zapping con ▲▼ y LT/RT ------------------------------------------------------------------
def test_arriba_abajo_y_lt_rt_cambian_de_canal_y_la_barra_enseña_a_donde_vas():
    p, mpv = live_player()
    loaded = []
    done = threading.Event()
    p.on_play_channel = lambda meta, cid, category: (loaded.append((meta["channel_id"], cid, category)), done.set())
    p.ZAP_WAIT = 0.05
    p.press("up")
    assert "Canal 3" in mpv.overlays[1] and "Sintonizando" in mpv.overlays[1]  # al instante, antes de cargar
    p.press("rt")  # dos seguidos: solo se carga el último
    assert "Canal 4" in mpv.overlays[1]
    assert done.wait(2) and loaded == [("c2", "c4", None)]
    assert not any(c[0] == "set_property" and c[1] == "volume" for c in mpv.sent)  # ▲▼ no son volumen aquí


def test_la_rueda_de_canales_se_salta_los_dudosos_pero_la_guia_los_enseña():
    p, mpv = live_player()
    shaky = [{**c, "shaky": c["id"] == "c3"} for c in CHANNELS]  # c3 ya falló una vez
    p.channels_provider = lambda meta, category=None: {"category": "todos", "channels": [{**c, "current": c["id"] == meta["channel_id"]} for c in shaky],
                                                       "categories": []}
    got = []
    done = threading.Event()
    p.on_play_channel = lambda meta, cid, category: (got.append(cid), done.set())
    p.ZAP_WAIT = 0.05
    p.press("up")  # de c2: el siguiente sería c3, pero es dudoso → c4
    assert done.wait(2) and got == ["c4"]
    p.press("y")
    assert "Canal 3" in mpv.overlays[2]  # en la guía sí está


def test_lt_y_abajo_van_al_anterior_y_la_lista_da_la_vuelta():
    p, mpv = live_player()
    got = []
    done = threading.Event()
    p.on_play_channel = lambda meta, cid, category: (got.append(cid), done.set())
    p.ZAP_WAIT = 0.05
    p.press("lt")
    p.press("down")
    assert done.wait(2) and got == ["c4"]  # de 2: 1, luego 4 (la lista da la vuelta)


def test_dar_la_vuelta_completa_no_recarga_el_mismo_canal():
    p, mpv = live_player()
    called = []
    p.on_play_channel = lambda *a: called.append(a)
    p.ZAP_WAIT = 0.05
    for _ in range(4):
        p.press("up")
    p._zap_timer and p._zap_timer.join(0.5)
    assert called == []


def test_con_un_solo_canal_avisa_en_vez_de_recargar():
    p, mpv = live_player()
    p.channels_provider = lambda meta, category=None: {"category": "x", "channels": [CHANNELS[1]], "categories": []}
    p.press("up")
    assert "No hay otro canal" in mpv.overlays[3]


def test_izquierda_derecha_son_volumen_y_a_es_silencio():
    p, mpv = live_player(volume=60)
    p.press("right")
    p.press("left")
    p.press("left")
    assert [c[2] for c in mpv.sent if c[:2] == ("set_property", "volume")] == [65, 60, 55]
    assert not any(c[0] == "seek" for c in mpv.sent)  # en vivo no hay a dónde adelantar
    p.press("a")
    assert ("set_property", "mute", True) in mpv.sent and not any(c == ("set_property", "pause", True) for c in mpv.sent)
    assert "Sin sonido" in mpv.overlays[8]


# --- la guía de canales (Y) ------------------------------------------------------------------
def test_y_abre_la_guia_con_categorias_y_canales_y_elegir_sintoniza():
    p, mpv = live_player()
    p.press("y")
    assert p.menu.kind == "channels" and [c.key for c in p.menu.columns] == ["category", "channels"]
    assert p.menu.col == 1 and p.menu.column.index == 1  # el canal que ves, enfocado
    assert "Canales" in mpv.overlays[2] and "Categoría" in mpv.overlays[2] and "Canal 4" in mpv.overlays[2]
    chosen = []
    done = threading.Event()
    p.on_play_channel = lambda meta, cid, category: (chosen.append((cid, category)), done.set())
    p.press("down")
    p.press("a")
    assert done.wait(2) and chosen == [("c3", "todos")] and p.menu is None


def test_elegir_otra_categoria_cambia_la_lista_sin_cerrar_la_guia():
    p, mpv = live_player()
    asked = []
    inner = p.channels_provider
    p.channels_provider = lambda meta, category=None: asked.append(category) or inner(meta, category)
    p.press("y")
    p.press("left")  # columna Categoría
    p.press("down")
    p.press("a")
    assert asked[-1] == "noticias" and p.menu is not None and p.menu.col == 1


def test_y_sin_canales_no_abre_nada():
    p, mpv = live_player()
    p.channels_provider = lambda meta, category=None: {"channels": [], "categories": []}
    p.press("y")
    assert p.menu is None and "No hay canales" in mpv.overlays[3]


# --- vigilancia: imagen, señal cortada, sin señal ------------------------------------------------
def tuning_player(**props):
    p, mpv = live_player(**props)
    p.segment = player.Segment(dict(META), "Canal 2", URL, live=True)
    return p, mpv


def test_hay_imagen_cuando_mpv_ya_reporta_la_posicion_de_este_canal():
    p, mpv = tuning_player()
    ok = []
    p.on_channel_ok = ok.append
    s = p.segment
    p.tick(s, s.loaded + 0.2, False)
    assert not s.playing and ok == []  # recién sintonizado: aún pueden ser las propiedades del canal anterior
    mpv.props["path"] = "https://tv.example.mx/otro.m3u8"
    p.tick(s, s.loaded + 1, False)
    assert not s.playing and ok == []  # la posición es de otro archivo
    mpv.props["path"] = URL
    p.tick(s, s.loaded + 1.5, False)
    assert s.playing and ok == [META] and "En vivo" in mpv.overlays[1]


def test_un_canal_que_no_abre_se_marca_y_se_pasa_al_siguiente():
    p, mpv = tuning_player(**{"time-pos": None, "idle-active": True})
    failed = []
    p.on_channel_failed = lambda meta, playing: failed.append((meta["channel_id"], playing)) or True
    s = p.segment
    p.tick(s, s.loaded + 0.5, False)
    assert failed == []  # un momento de gracia
    p.tick(s, s.loaded + 1.5, False)
    assert failed == [("c2", False)] and s.failed
    p.tick(s, s.loaded + 2.5, False)
    assert len(failed) == 1  # no se reporta dos veces


def test_sin_respuesta_en_el_plazo_es_sin_senal():
    p, mpv = tuning_player(**{"time-pos": None})
    failed = []
    p.on_channel_failed = lambda meta, playing: failed.append(playing) or True
    p.tick(p.segment, p.segment.loaded + player.LIVE_STARTUP_TIMEOUT - 1, False)
    assert failed == []
    p.tick(p.segment, p.segment.loaded + player.LIVE_STARTUP_TIMEOUT + 1, False)
    assert failed == [False]


def test_se_corta_la_senal_a_media_vista():
    p, mpv = live_player()
    failed = []
    p.on_channel_failed = lambda meta, playing: failed.append(playing) or True
    mpv.props["idle-active"] = True
    p.tick(p.segment, p.segment.loaded + 90, False)
    assert failed == [True]  # estaba al aire: tv.py primero reintenta el mismo canal


def test_si_no_hay_a_donde_pasar_se_queda_con_sin_senal_a_la_vista():
    p, mpv = tuning_player(**{"time-pos": None, "idle-active": True})
    p.on_channel_failed = lambda *a: False
    p.tick(p.segment, p.segment.loaded + 2, False)
    assert "Sin señal" in mpv.overlays[1] and "Sin señal en este canal" in mpv.overlays[3]
    assert p._hud_timer is None  # la barra no se va sola


def test_el_final_del_archivo_en_vivo_es_una_senal_cortada_no_un_final():
    p, mpv = live_player(**{"eof-reached": True})
    failed = []
    p.on_channel_failed = lambda meta, playing: failed.append(playing) or True
    p.tick(p.segment, p.segment.loaded + 10, False)
    assert failed == [True]


# --- Home, salir ----------------------------------------------------------------------------
def test_home_deja_el_canal_sin_sonido_en_vez_de_pausarlo_y_al_volver_suena():
    p, mpv = live_player()
    p.pause()
    assert ("set_property", "mute", True) in mpv.sent and ("set_property", "pause", True) not in mpv.sent
    assert p._away
    p.show_progress()
    assert ("set_property", "mute", False) in mpv.sent and not p._away


def test_si_ya_lo_habias_silenciado_home_no_te_devuelve_el_sonido():
    p, mpv = live_player()
    p.press("a")  # silencio tuyo
    mpv.sent.clear()
    p.pause()
    p.show_progress()
    assert ("set_property", "mute", False) not in mpv.sent  # sigue como lo dejaste


def test_sin_sonido_deja_una_pildora_fija_que_se_va_al_volver_a_oir_o_cambiar_de_canal():
    p, mpv = live_player()
    p.press("a")
    assert "Sin sonido" in mpv.overlays[8]  # fuera de la barra del canal, que se esconde sola
    p.press("a")
    assert mpv.overlays[8] is None
    p.press("a")
    p.tune("https://tv.example.mx/c3.m3u8", "Canal 3", {**META, "channel_id": "c3"})
    assert mpv.overlays[8] is None and ("set_property", "mute", False) in mpv.sent


def test_lt_rt_saltan_una_pagina_en_la_guia_de_canales():
    p, mpv = live_player()
    many = [{"id": f"c{i}", "name": f"Canal {i}", "number": i, "category": "General", "current": i == 1} for i in range(1, 41)]
    p.channels_provider = lambda meta, category=None: {"category": "todos", "categories": [], "channels": many}
    p.press("y")
    assert p.menu.column.index == 0
    p.press("rt")
    assert p.menu.column.index == player_ui.PANEL_ROWS
    p.press("rt")
    p.press("lt")
    assert p.menu.column.index == player_ui.PANEL_ROWS
    for _ in range(10):
        p.press("rt")
    assert p.menu.column.index == 39  # el último, sin pasarse


def test_la_guia_dice_que_canales_ya_fallaron():
    ass = player_ui.panel_ass(player_ui.channels_panel(
        [], [{"id": "a", "name": "Uno", "number": 1, "category": "General", "shaky": True, "current": True},
             {"id": "b", "name": "Dos", "number": 2, "category": "General", "current": False}]))
    assert "Sin señal reciente" in ass and "General" in ass


def test_un_canal_olvidado_tras_home_se_cierra_solo_y_el_aviso_no_promete_seguir_donde_ibas():
    p, mpv = live_player()
    p.current.process = type("Proc", (), {"poll": lambda self: 0 if ("quit",) in mpv.sent else None})()
    p.POLL, p.idle_seconds = 0.01, 0.05
    told = []
    p.on_idle = lambda title, minutes, live=False: told.append((title, live))
    p.pause()  # Home: sin sonido, y desde aquí cuenta como olvidado
    p._watch(p.current)
    assert ("quit",) in mpv.sent and told == [("Canal 2", True)]


def test_un_video_normal_sigue_pausandose_con_home():
    p, mpv = make_player()
    p.pause()
    assert ("set_property", "pause", True) in mpv.sent


def test_salir_anota_que_era_la_tele_en_vivo():
    p, mpv = live_player()
    p._quit()
    assert p.last_end == {"title": "Canal 2", "finished": False, "kind": "tv", "live": True}


def test_la_sexta_fila_de_un_panel_no_se_enciman_con_los_botones_ni_en_16_10():
    """En la Legion Go (1728 de ancho) la sexta fila quedaba debajo de «Columna · Elegir · Cerrar»."""
    ys = []
    panel = player_ui.channels_panel([], [{"id": f"c{n}", "name": f"Canal {n}", "number": n, "category": "General", "current": n == 1}
                                          for n in range(1, 10)])
    for width in (1920, 1728, 1440):
        player_ui.set_canvas(width, 1080)
        ass = player_ui.panel_ass(panel)
        rows = [int(y) for y in re.findall(r"pos\(\d+,(\d+)\)[^}]*\}\d · Canal", ass)]
        assert len(rows) == 6  # las seis filas a la vista
        ys.append(max(rows))
    player_ui.set_canvas(1920, 1080)
    assert all(y + 27 < 1022 - 17 for y in ys)  # el centro de la fila + media fila (27) queda sobre los botones (centro 1022, alto 34)


def test_la_barra_en_vivo_dice_numero_nombre_categoria_y_calidad():
    ass = player_ui.live_hud_ass(player_ui.LiveHud("Azteca 7", 12, "Noticias", "720p", "live", now="21:05"))
    for text in ("12", "Azteca 7", "En vivo", "Noticias", "720p", "21:05", "Canal", "Canales", "Volumen", "Silencio", "Mantén: salir"):
        assert text in ass
    assert "Sin señal" in player_ui.live_hud_ass(player_ui.LiveHud("X", None, status="nosignal"))
    assert "Sin sonido" not in player_ui.live_hud_ass(player_ui.LiveHud("X", 1, muted=True))  # lo dice la píldora fija
    ass = player_ui.live_hud_ass(player_ui.LiveHud("Canal {raro}"))  # las llaves abren etiquetas ASS: se cambian
    assert "Canal (raro)" in ass and "{raro}" not in ass
