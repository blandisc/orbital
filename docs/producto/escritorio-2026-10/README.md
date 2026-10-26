# Orbital Escritorio: mejoras y bugs (octubre 2026)

Rama: `claude/orbital-desktop-improvements-15b3e7`. Tablero (artefacto): https://claude.ai/artifact/YDfzgb77Yt5ooVnAUe6J6S
(fuente: `tablero.html`, aquí mismo; se actualiza publicándolo a esa misma URL).

**Regla de Fernando: nada se da por cerrado sin probarlo en la Lenovo y sin evidencia de antes y después** (capturas en `evidencia/`, también en el tablero). En la Mac solo corren las pruebas automáticas y el
demo; lo que depende de Windows y mpv se prueba allá. Nunca mandes teclas ni POST a la Orbital real (`127.0.0.1:8710`) sin
avisar: una tecla Enter abre juegos de verdad. Para la interfaz, `scripts/demo_server.py --port <puerto>`.

## Los 12 pedidos (en el orden de ataque)

| # | Pedido | Estado |
|---|---|---|
| 11 | Reproductor: al pausar no detecta bien los botones, o sale el logo y no la pantalla de pausa (lo más importante) | Código hecho (32afc70, 0089406). **Falta la prueba con mando en la TV** (esta sesión no tiene permiso de mandar el mando a la Orbital real) |
| 12 | «Qué pasó ayer» se trababa: revisar caché/configuración | Medido: la vista de hoy (12:50–14:39) sin trabas ni recargas. La causa vista (la A que recargaba) la arregla el #11 |
| 10 | Canal 24/7 de Los Simpson: al acabar un episodio no pone el siguiente solo (debe ser tele 24/7) | **Listo** (45484a2, 00e1d06): arrancaba en pausa en 0:00 (keep-open) y sin reintento ante un tropiezo de red. Probado con mpv de verdad |
| 9 | Fichas de películas y series: los botones «Ver» y «Guardar» se tocan | **Listo** (828f791) |
| 7 | «Ver más» en las descripciones de las fichas | **Listo** (943c9c3) |
| 1 | Buscador: que se note que está buscando (animación) | **Listo** (6de70a8) |
| 2 | Dictado: hoy siempre añade; si lo escrito tiene más de 2 min, que lo reemplace | **Listo** (828f4ef) |
| 3 | Banderitas en todos los lugares donde eliges idioma o subtítulo (mapear todos) | **Listo** (0d291d7): interfaz y reproductor, mapa del iPhone |
| 4 | Aparadores de temporadas y de géneros con icono y título bonito, alineado con el iPhone | **Listo** (8e0ed07): los íconos de la propuesta T4 del iPhone |
| 6 | Propuesta de animación de entrada elegante, minimalista y fluida, alineada con el iPhone | **Listo** (49df49d): aprobada; tiempos de OrbitalWordmark |
| 8 | Análisis UI/UX: cambiar rápido de subtítulo y probar varios con el video | **Hecho** (todo en una entrega, como se decidió): mantener X / S / botón, vuelta al final, sincronía por subtítulo, todo se guarda, salir deja el último, orden del iPhone con copia y descargas, LB/RB idioma, otra edición. Evidencia en mpv; **falta probarlo con mando en la TV** |
| 5 | Trakt: sincronizar el avance del iPhone aquí, y ¿dos sesiones de Trakt? | Investigación lista (abajo) |

## 11 · Reproductor: lo hecho

Causa: con el video a pantalla completa, Windows a veces deja el foco en Orbital (detrás). `shell.on_buttons` devolvía el
foco al video y **tiraba** esa pulsación (A no pausaba), y la interfaz, que tenía el foco, tomaba la A como «Ver» en la ficha
de atrás: salía la pantalla de carga con el logo del título y el servidor **volvía a abrir la película** desde lo último
guardado (hasta 1 min atrás), que se ve como «se trabó».

- `orbital/shell.py`: `video_holds_screen()`; con el video al frente y el foco en un navegador, el mando (pulsar y soltar) va
  al reproductor. Home publica `{"type": "returned"}`.
- `orbital/api/deps.py`: `/api/status` lleva `running.front` para el reproductor.
- `orbital/web/js/main.js`: `videoInFront()` — la interfaz no hace caso del mando ni del teclado mientras `front`.
- `orbital/player.py` `showing()` + `orbital/watch.py`: «Ver» de lo que ya se ve lo trae al frente en vez de recargarlo.

Probar en la Lenovo: abrir una película, pausar con A varias veces (también tras hacer clic en Orbital para quitarle el foco
al video), mantener B para salir, Home → en pequeño → Home, y que la interfaz responda normal tras Home.

## 12 · Trabas: lo que hay que medir

Caché de hoy (`orbital/playback.py` `build_command`): `--cache=yes --demuxer-max-bytes=400MiB --demuxer-max-back-bytes=50MiB`,
`--hwdec=auto-safe`, `--d3d11-flip=no`. Sospechas a comprobar con el registro de la Lenovo (`%LOCALAPPDATA%\orbital`):
1. Recargas por la A perdida (arriba): ya corregido; ver si el registro tenía «Sintonizando/abriendo» repetidos.
2. `paused-for-cache` con `cache-pause-wait` de fábrica (1 s): con fuentes lentas pausa y sigue a cada rato. Probar
   `--cache-pause-wait=4` y anotar en el registro cada espera con `cache-speed` y `demuxer-cache-duration`.
3. `--d3d11-flip=no` (se puso por fuga de memoria del DWM): puede afectar la cadencia de cuadros en 4K; medir cuadros perdidos
   (`frame-drop-count`, `vo-delayed-frame-count`) con y sin.

## 5 · Trakt (informe)

- Hoy el avance entre iPhone y escritorio ya se comparte **por Stremio** (`timeOffset` en segundos): escritorio
  `orbital/watch.py:1322/1334`, iPhone `Watch.swift:189/282`. Trakt solo recibe scrobbles (`orbital/scrobble.py:58-92`,
  `Watch.swift:220-250`); nadie lee `/sync/playback`.
- Trakt guarda avance en **porcentaje** (`/sync/playback`, 6 meses; `stop` >80 % = visto, 1–79 % = pausa, `start` borra el
  avance). Distintas versiones con otra duración caen en otro segundo (1 % de 2 h ≈ 72 s). No avisa: se consulta
  `/sync/last_activities` y solo si cambió se baja `/sync/playback`. Límites: 1 escritura/s, 1000 lecturas/5 min.
- Propuesta: Stremio sigue como fuente principal; Trakt de respaldo (cuando Stremio no tenga posición o la de Trakt sea más
  nueva: gana la fecha más reciente), convertir % × duración − 10 s; borrar la entrada de playback al terminar; respetar
  1 escritura/s en escritorio.
- **¿Dos sesiones? Sí, recomendado.** Con el mismo Client ID, cada autorización por código crea su propio token y su propio
  refresh token. Compartir un refresh token rompe (se usa una sola vez); por eso hoy el iPhone recibe una sesión «prestada»
  sin refresh (`orbital/companion.py:69-77`, `Trakt.swift:221/300-372`) y depende de que la TV esté prendida. El iPhone ya
  sabe conectarse solo (`Trakt.swift:262/278`): que use su propia sesión y deje la prestada solo como arranque.
  Detalle: en escritorio un 401 al leer borra la sesión sin intentar renovar (`orbital/library/trakt.py:261-265`).

## 8 · Cambio rápido de subtítulo (análisis)

Hoy: entrar a «Probar otros» cuesta ~8 pulsaciones (X → Subtítulos → ↓×5 → A; está al final de la columna,
`player_ui.py:711-721`); probar 3 ≈ 11. Fricciones: no da la vuelta al final (`player_subs.py:153-157`), la sincronía se
arrastra de un subtítulo al siguiente (`player_subs.py:173-179`), solo se recuerda con A, los de internet llegan sin nombre de
copia ni descargas (`library/streams.py:342-357`, todos dicen «de tu addon»), y no hay orden por parecido con tu copia.
El iPhone ya resolvió: el mejor primero (`SubtitleVersions.swift:130-163`), huella OpenSubtitles del archivo, «Coincide con
tu copia», vuelta al final, cada cambio se recuerda, sincronía por `archivo|versión`.
Propuesta para el mando, primero: mantener X entra directo a «Probar otros»; «Probar otros» primero en la columna; dar la
vuelta; sincronía por subtítulo y guardar en cada paso. Después: detalle de cada subtítulo y orden como el iPhone con chips
(«Hecho para tu copia», descargas), huella del archivo, recordar la copia por serie, LB/RB cambia de idioma, aviso de «otra
edición» con `sub-speed`.

## 8 · Cambio rápido de subtítulo: lo hecho

- Entrar: **mantener X** (anillo de 0.6 s; un toque sigue abriendo Audio y subtítulos, al soltar), **S** en el teclado,
  el botón **«Probar subtítulos»** en pausa con dedo y mouse, o X › Subtítulos › «Probar otros» (ahora la primera fila,
  con «Mantén X» / «Tecla S»). La barra de pausa lo dice y, la primera vez que abres el panel, un aviso de 4 s.
- En la franja: ◀ ▶ / ← → / rueda / ‹ › cambian y **dan la vuelta**; LB RB / RePág AvPág / «Otro idioma» cambian de
  idioma; ↑ ↓ sincronía **de ese subtítulo**; A «Este va bien» (en series recuerda la copia buena: el siguiente episodio
  pone primero los del mismo grupo); B / Esc / «Listo» **deja el último que probaste**. Cada cambio se guarda al momento.
- Orden del iPhone (`orbital/library/subtitles.py`): tus complementos + OpenSubtitles siempre, con la **huella** del
  archivo (dos pedidos de 64 KB) si el servidor la da; luego «Hecho para tu copia» (grupo y tipo), «Misma versión», más
  descargas. Sordos y forzados fuera. Si el subtítulo sigue después del final del video, Y ajusta `sub-speed` (otra edición).
- Archivos: `player_subs.py`, `player_ui.py` (franja, pausa, panel), `player_screen.py` (mantener X, S, rueda, botón),
  `playback.py` (X avisa al soltar; S y rueda), `library/streams.py` (`subtitle_options`), `watch.py`.
- Evidencia: `evidencia/08-franja.jpg`, `08-pausa.jpg`, `08-panel.jpg` (dibujado por el reproductor en un mpv de verdad).
- Probar en la TV: mantener X en pausa y reproduciendo; un toque de X; ◀ ▶ hasta dar la vuelta; LB/RB; B y ver que se
  queda; siguiente episodio de la misma serie tras A.

## 6 · Animación de entrada (propuesta)

Hoy (`orbital/web/index.html:14-23`, `styles/components/boot.css`, `js/app/boot.js`): estrellas, planeta relleno, órbita
inclinada con satélite rojo, «orbital» con interletrado; mínimo 1100 ms y salida con zoom ×9; luego la barra vuelve a animar
la marca (dos entradas). El iPhone usa `OrbitalWordmark(animated:)` (`ios/App/Sources/Design/Brand.swift:6-92`): planeta de
contorno, anillo que se dibuja (0.76 s, easeOut) y la luna turquesa que cae con resorte.
Propuesta: la misma marca del iPhone: T1 planeta 0–520 ms (`--ease-spring`), T2 anillo 170–930, T3 palabra 260–780,
T4 luna 1292–1812 (resorte), T5 la marca viaja y se encoge hasta la barra (FLIP, token nuevo `--ease-glide`) mientras el fondo
se funde. Si tarda: la luna respira y a los 2.4 s «Preparando tu biblioteca…». Movimiento reducido: marca quieta y corte.
Maqueta: `entrada-propuesta.html` (aquí mismo). Decisión de gusto: el mínimo sube de 1100 a ~1800 ms.
