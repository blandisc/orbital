# TV en vivo

Los canales de México (lista pública de [iptv-org](https://iptv-org.github.io/iptv/countries/mx.m3u)) dentro de
Orbital, con el mando. Qué se decidió, cómo está armado y lo que se midió antes de construirlo.

> El documento del spike (`docs/spike-tv-en-vivo.md`) y `spike/tv-en-vivo/iptv.py` **no estaban** en `main` ni en
> ninguna rama ni en `origin`: el lector M3U y el verificador se escribieron de nuevo a partir de lo decidido
> (motor mpv, fuente de iptv-org, sin EPG ni Xtream Codes). Las cifras del spike que se citan (83 de 174 con señal)
> son las que dio la persona que lo hizo; no se pudo comparar canal por canal.

## Decisiones

- **Motor: mpv**, con el `Player`/`Mpv` que ya existen (no hls.js ni VLC).
- **Fuente:** la lista M3U de México, bajada con `net.py` y con **copia en disco** (`%LOCALAPPDATA%\orbital\cache\tv-mx.m3u`)
  para cuando no hay Internet.
- **Fuera de la v1:** guía de programación (EPG), Xtream Codes y listas M3U propias (mejora aparte, en Ajustes).

## Cómo está armado

| Pieza | Qué hace |
|---|---|
| `orbital/library/iptv.py` | Lee el M3U (`#EXTINF`: nombre, calidad, etiquetas, logo, categorías separadas por «;»; `#EXTVLCOPT`: Referer y User-Agent), traduce las categorías al español («Undefined» → «Otros»), solo acepta `http(s)` y nunca muestra adultos. |
| `orbital/library/iptv_health.py` | ¿Abre de verdad? Manifiesto → variante → un segmento real. Guarda el resultado en disco (`tv-health.json`) y **oculta un canal solo tras 2 fallos seguidos**. Sin Internet durante la revisión, ningún fallo cuenta. Cada canal conserva su número. |
| `orbital/tv.py` (`LiveTV`) | Junta lo anterior con el reproductor: pestañas (las categorías de menos de 3 canales pasan a «Otros»), la lista por la que se salta con ↑↓, la revisión en segundo plano (al arrancar, 20 s después, y cada ~6 h), qué hacer cuando un canal falla. |
| `orbital/api/tv.py` | `GET /api/tv` · `POST /api/tv/play` · `POST /api/tv/refresh`. Nunca expone direcciones ni cabeceras. |
| `orbital/player.py`, `playback.py`, `player_screen.py`, `player_ui.py`, `mpv.py` | El **modo en vivo**: caché corta y reconexión, Referer/User-Agent por canal, cambio de canal con `loadfile … replace` en el mismo mpv, sin progreso ni episodios, y la barra del canal. |
| `orbital/web/js/components/tv.js` (+ `core/tv.js`, `styles/components/tv.css`) | La sección en la interfaz (catálogo del sistema de diseño). |

El modo en vivo de mpv (`playback.LIVE_ARGS`): `--cache-secs=8 --demuxer-readahead-secs=8 --demuxer-max-bytes=48MiB
--demuxer-max-back-bytes=8MiB --network-timeout=10 --tls-verify=no` y `--stream-lavf-o=reconnect=1,reconnect_streamed=1,
reconnect_at_eof=1,reconnect_delay_max=4`, en lugar de `--demuxer-max-bytes=400MiB`. El User-Agent por defecto es el
mismo con el que se verifica cada canal: **lo que se prueba es lo que se reproduce**. `--tls-verify=no` es el valor de
fábrica de mpv; se pone explícito para que la verificación no sea más estricta que el reproductor (hay canales, como
Unison TV, con el certificado vencido que sí se ven).

## Lo que se midió (Paso 0, Monterrey, mpv 0.41-dev, 2026-10-15)

**¿Cuántos canales abren desde México?** De 174 canales en la lista: **124 abren** (el spike midió 83). Los 50 que no:

| Motivo | Canales |
|---|---|
| HTTP 404 (el canal ya no existe) | 27 |
| HTTP 403 (bloqueo; no cambia con el User-Agent: es de región o pide una clave) | 12 |
| Sin conexión / servidor caído / DNS | 8 |
| Otros (400, 414, página web en lugar de video) | 3 |

Solo 7 canales se marcan `[Geo-blocked]` en su nombre y 4 de ellos abren desde aquí. Que el spike midiera 83 sugiere que se
hizo desde fuera de México o con una prueba más estricta (7 canales tienen el certificado TLS vencido o inválido; mpv no
lo valida y uno de ellos, Unison TV, sí se ve: una prueba que sí validara lo ocultaría sin motivo).

**¿Cuánto tarda en cambiar de canal?** Un solo mpv, `loadfile … replace`, hasta la primera imagen (`playback-restart`), 10
canales vivos × 2 vueltas × 4 configuraciones (80 muestras):

| Configuración | Mediana | p90 | Máximo |
|---|---|---|---|
| mpv de fábrica | 1,77 s | 2,82 s | 22,1 s |
| `--cache-secs=5 --demuxer-readahead-secs=5` | 1,67 s | 4,30 s | 16,7 s |
| + `--demuxer-lavf-analyzeduration=1 --demuxer-lavf-probesize=500000` | 1,80 s | 2,54 s | 2,78 s |
| + `--hls-bitrate=min` | 1,67 s | 2,61 s | 3,05 s |

- **~1,7 s de mediana y ~2,6 s en el p90**, sin pasar de ~3 s en lo normal: no hizo falta precargar el canal siguiente.
- Ninguno de los ajustes de arranque cambia la mediana: el tiempo es del servidor de cada canal (Azteca 7 abre en 0,5 s; ADN 40,
  siempre ~2,8 s). Los de caché corta sirven para acotar la memoria, no para ir más rápido.
- 4 de 80 intentos (5 %) tardaron de 4 a 22 s: colas del servidor de ese canal, no de mpv. Por eso un canal que no da imagen
  en **12 s** (`LIVE_STARTUP_TIMEOUT`) se da por caído y se pasa al siguiente; uno que contesta 404 se detecta en ~1 s.
- Desde cero (proceso nuevo → primera imagen) fue de **1,4 s**.

Prueba de integración con mpv real (sin ventana ni audio): el `OrbitalPlayer` sintonizó un canal vivo, saltó solo de un canal
caído al siguiente (detectado a ~1 s), ▲▲ seguidos cargaron solo el último, y silencio y volumen llegaron a mpv.

## Pendiente

- Probar todo con el mando en la TV (ver `docs/pruebas-y-configuracion.md` → «TV en vivo»).
- Listas M3U propias en Ajustes (mejora aparte).
- Logos: se cargan directo de internet (imgur y otros); sin Internet salen las letras del nombre. Un caché local los haría
  funcionar sin conexión.
- Voz (Alexa): «pon el canal 5» / «pon Azteca 7».
- Guía de programación (EPG) y Xtream Codes: fuera de la v1.
