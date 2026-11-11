# Revisión a fondo del 10 nov 2026: hallazgos y estado

Canvas con el resumen para Fernando: https://claude.ai/artifact/H6GJiFWAoCMejPkMuvTQTe

Siete revisiones independientes (arquitectura, velocidad y UX/UI del iPhone; servidor, interfaz y UX/UI de la TV; cruce entre
las dos apps). Fernando pidió el 10 nov corregir todo y aceptó las recomendaciones: **D1-B, D2-A, D3-A, D4-B, D5-A, D6-A,
D7-A, D8-A**.

Estado: `[ ]` pendiente · `[x]` hecho (con commit) · `[~]` a medias · `[-]` descartado (con motivo). Lo marca quien dirige,
no cada agente.

## Decisiones tomadas

- **D1-B** Versiones: un tipo `Edition`/capacidades inyectado en `Services` que diga qué puede cada versión (Ultra, Plus,
  Orbital). Sin targets nuevos ni cuenta de pago todavía. Hoy todo se decide en ejecución (`allowsOrbital` 24 usos,
  `debrid.hasToken` 16).
- **D2-A** iPhone: la pastilla de calificar («¿Qué tal Dune?») deja de flotar; es una tarjeta dentro del scroll de Inicio.
- **D3-A** TV: foco «la órbita»: lo enfocado se levanta y un filo de luz del color del arte (`--art-accent`) lo recorre una
  vez al llegar y se queda quieto. Misma pieza en pósters, tiles, canales y caras. Paridad: anotar el iPad en el registro.
- **D4-B** TV: Inicio suma las filas «Seguir viendo» y «Mi lista», y el arte de arriba sigue a lo enfocado (consolas
  incluidas: número de juegos, último jugado) en vez de quedarse con el juego anterior.
- **D5-A** TV: el menú ☰ queda solo para sistema (Panel rápido, Jugadores, Cómo se usa, Lo que puedes decir, Ajustes).
  Guardado es fila (D4-B) y entrada visible en Películas y series; «Decide por mí» y «¿Qué vemos hoy?» se juntan en una
  entrada de Explorar; Colecciones y Filtro avanzado van a Películas y series/Explorar. Todo atajo conserva camino visible.
- **D6-A** Retomar en el punto exacto en las dos apps (la TV ya lo hace, `orbital/library/trakt.py:125`; el iPhone regresa
  10 s en `ios/OrbitalCore/Sources/OrbitalCore/Watch.swift:109-110`). Meterlo al golden `resume.json`.
- **D7-A** iPhone: Historial como quinta pila en Guardado, borrar deslizando + «Editar», cielo de fondo, «hoy/ayer», aviso
  de repetidas al final.
- **D8-A** La CI manda: nadie construye sobre rojo; la TV se actualiza desde la etiqueta `tv-estable`, que la CI mueve
  cuando todo pasa en `main`. Asuntos de commit de 72 caracteres o menos, con el detalle en el cuerpo.

## Avance

- **Tanda 1 (10 nov), verificada:** pruebas web 311/311; servidor con los mismos 17 fallos propios de Windows que antes en la Mac;
  CI en verde tras A1. D6-A y D8-A (lado servidor) hechos (`bddcabb6`, `190c4005`). Pendiente de ver en la tele real: latido
  del vigilante, barrido de mpv, conexiones reutilizadas y la velocidad con tarjeta gráfica.
- **Tanda 2 (en curso):** diseño del iPhone, diseño y foco de la TV, contrato y reglas compartidas. iPad y Mac en rama aparte.

## A · Arreglos chicos

- [x] **A1** (`82f9bd0f`) CI en rojo: `ios/OrbitalCore/Sources/OrbitalCore/Trakt+Ratings.swift:19` («unable to type-check this
  expression in reasonable time»). Partir la suma en variables. Fijar la versión de Xcode en `.github/workflows/ci.yml`.
- [x] **A2** (`f84b3d37`) `ios/App/Sources/Screens/HomeView.swift:144-147`: `.orbitalRefreshable` quedó dentro de `#if DEBUG`.
- [x] **A3** (`25a66ffb`) `orbital/web/js/core/input.js:281-307`: si `onAction` lanza, no se llega a `next()` y el mando muere.
  `try/finally`; `main.js:2633` tampoco lo envuelve.
- [x] **A4** (`796ef998`) `orbital/web/js/core/curation.js:35-55` pide 19 géneros; `orbital/api/media.py:86` acepta 12. Una sola lista
  y una prueba que compare ambas.
- [x] **A5** (`f47b3c4e`) `orbital/remote_art.py:95` `prune` no se llama nunca; `sized/` tampoco se purga; tope por cantidad, no tamaño.
- [x] **A6** (`64a09baa`) Sin reintento ni `Retry-After` en 429/5xx: `orbital/library/trakt.py:437`, `tmdb.py:279`; va en `net.http_json`.
- [x] **A7** (`63f5276f`) `orbital/supervisor.py:58-69` solo detecta cierres. Latido a `/api/ping` cada 30 s; tras 3 fallos, matar y reabrir.
- [x] **A8** (`4a95c6a4`) `orbital/state.py:130-131`, `credentials.py:90-93`: sin `fsync`. Un `atomic_write()` único (el patrón está
  copiado ~17 veces) y recuperar del `.bak`.
- [x] **A9** (`a2199683`) `orbital/web/js/core/api.js:7`: `timeout = 0` por defecto. 10–15 s.
- [x] **A10** (`6081d5c1`) `ios/OrbitalCore/Sources/OrbitalCore/Settings.swift:515`: manda todo lo pendiente junto y se traga el error;
  la TV corta en 16 KB (`orbital/server.py:641`) y 100 cambios (`server.py:381-406`). Lotes de 100; registrar 413/422.
- [x] **A11** (`6081d5c1`) `ios/OrbitalCore/Sources/OrbitalModels/TVNowModel.swift:78,108-113,176-183`: sondeo cada 5 s sin freno.
  5 → 15 → 60 s si no contesta; pausa con el reproductor local abierto.
- [x] **A12** (`6081d5c1`) Pósters: `ios/App/Sources/Platform/ImagePipeline.swift:169-171`, `PosterSource.swift:49-63,69` (`/find` sin
  `TmdbDetailsGate`, dos tamaños preguntan dos veces, salto al hilo principal en `AppEnvironment.swift:240`);
  `PosterSource.swift:56-62,19` guarda y lee el mapa entero en UserDefaults. Fila + una consulta por título + archivo en
  Caches con escritura retrasada.
- [x] **A13** (`f84b3d37`) `ios/App/Sources/Screens/HistoryScreen.swift:25,122-131`: `repeats` y `months` se recalculan en cada pintado.
- [x] **A14** (`07335b1e`) Peso: Release sin quitar símbolos (`DEPLOYMENT_POSTPROCESSING`, `STRIP_INSTALLED_PRODUCT`,
  `STRIP_STYLE=non-global` en `ios/App/project.yml`); el widget empaca todo el arte (`project.yml:133`);
  `simpsons.donut.svg` 323 KB.
- [ ] **A15** Códigos de Real-Debrid distintos: `orbital/library/realdebrid.py:46-51` vs
  `ios/OrbitalCore/Sources/OrbitalAddons/RealDebridTorrents.swift:98-100`. Tabla código → causa en
  `design/addons-contract.json`, leída por ambos.
- [x] **A16** (`f84b3d37`) Control del iPhone: quitar LB/RB/LT/RT/A/B/X/Y y «A · desliza para moverte»; «De 5 en 5» → «−5 min / +5 min».

## I · Diseño y uso en el iPhone

- [ ] **I1** = D2-A.
- [ ] **I2** Inicio sin margen izquierdo en el SE; con letra grande ~8 pt.
- [ ] **I3** Letra grande: «y 1 más» partido letra por letra; en el control «De 5 en…», «Películas y seri…». `ViewThatFits`.
- [ ] **I4** = D7-A (`Screens/LibrarySavedView.swift:363`, `Screens/HistoryScreen.swift:108`).
- [ ] **I5** Vistas e Historial: fondo sin cielo, encabezados de mes distintos, fechas largas en vez de «hoy/ayer».
- [ ] **I6** Hoja «Versión»: jerga («se supone», «(no dice cuál)»), «¿Otro título?» amarillo en cada renglón, rompecabezas
  sin explicar. Idioma y tamaño por renglón, dudas tras ⓘ, amarillo solo con riesgo real.
- [ ] **I7** Ficha: dos «guardar» (corazón y «Mi lista») → una sola puerta; «Versión» dentro del renglón «🇲🇽 · 1080p».
- [ ] **I8** Un solo control para «Todo/Películas/Series» (hoy tres: Inicio, Explorar/Buscar, Top 10).
- [ ] **I9** Encabezado de Inicio con seis cosas; la dona a Canales.
- [ ] **I10** Explorar sin datos (abanicos vacíos, «Disney +» partido) → esqueleto o esconder; velo superior para los
  íconos; el botón de cuadrícula suelto al encabezado.
- [ ] **I11** Logo ancho choca con la cápsula al recoger la ficha (`Screens/TitleScrollChrome.swift:45`).
- [ ] **I12** Regla y prueba: cada pasada de diseño también en SE, letra grande y modo claro.
- [ ] **I13** Menores: pestañas de Biblioteca pierden el texto en SE; «Hoy» repetido en «Lo nuevo de lo tuyo»; modo claro
  (puntos del cielo, «más» pálido en `Screens/TitleView+Detalles.swift:18`); buscar teñido de amarillo con historias;
  estados vacíos desiguales (Descargas centrado, Historial arriba); «▲ 2» sin explicar; «Un Simpson al azar» en Ajustes y
  grupo sin título; «T… E…» fijo en `HistoryScreen.swift:116-119` (usar `episodeLabel`).

## T · Diseño y uso en la TV

- [ ] **T1** = D3-A (`tokens.css:301`, `themes/orbital.css:207`).
- [ ] **T2** Letra chica: `caption`/`footnote`/`secondary` 18,6–21 px (`tokens.css:68-70`) → tres pasos 21/24/26; piso de
  `--root-size` más alto en pantallas chicas (Legion Go).
- [ ] **T3** = D5-A. **T4** = D4-B.
- [ ] **T5** «Todo · Películas · Series» enfocables con ↑ como los filtros de Juegos (`main.js:1124,1768`).
- [ ] **T6** «Tu consola» tapa Inicio en la primera carga → aviso o tarjeta en Ajustes › Resumen.
- [ ] **T7** Buscar: fondo del sistema, resultados a la derecha en vivo, teclado compacto, más sugerencias.
- [ ] **T8** Ficha abajo: mantener el fondo desenfocado; `--layout-title-to-content` de verdad; foco del reparto.
- [ ] **T9** Íconos de estado de la nube al doble y estado en el pie; «Real-Debrid · bajando para ti» → «Lo que pediste».
- [ ] **T10** Clasificación «B» sin caja de glifo; sinopsis cortada a media palabra; píldora que empieza con « · »; héroe
  de Películas y series con datos y fondo; Ajustes (un solo título grande, columna de ancho fijo).
- [ ] **T11** Sistema: 312 medidas rem sueltas (60 valores) vs 9 pasos; 45 duraciones, 15 curvas; 7 nombres de radio para
  2 valores; dos clases de foco (`--focused` e `.is-focused`); faltan «foco sobre superficie oscura», estados
  deshabilitados y contador de fila único (hoy «6», «3 / 6», «1 / 16» y puntos).
- [ ] **T12** Menores: «1 de 9» sin velo; aviso de error tapa el selector de consolas; con algo abierto Inicio dice
  «Stremio» (verificar); «S» de teclado en modo touch; «Recomendada» tapa un ícono; estrella pisa el logo.

## V · Velocidad

- [x] **V1** (`30df7c64`) `backdrop.js:49-52` escribe `--art-tint`/`--art-accent` en `<html>` con `inherits: true`
  (`tokens.css:345-354`). Medido a 4x: p95 292 → 80 ms sin tinte. Ponerlas solo donde se usan.
- [~] **V2** (296af40c: falta el margen animado de la tarjeta) `shelf.js:206-228` (`setFocus` recorre todo), `hero.js:37-53`, `shelf.js:270-289` (lecturas y escrituras
  mezcladas, ~9 layouts por tecla); `main.js:1006` `void view.offsetWidth` al cambiar de sección; `card.css:12-14` margen animado.
- [ ] **V3** `backdrop.js:31` `getImageData` (~15 ms por título): que el servidor mande el tono.
- [ ] **V4** Rejillas sin virtualizar (`list-screen.js`, `games.js`, `browse.js`).
- [x] **V5** (`64a09baa`) `orbital/net.py:76`: conexión nueva por petición; sin cortacircuitos (`api/foryou.py:163-166`).
- [x] **V6** (`9ce00186`) `orbital/foryou.py:167-300`: caché sin tope; serializa todo dos veces por cambio (`:217`, `:225`).
- [x] **V7** (`7e640bf9`) `ios/App/Sources/Design/Posters.swift:153-171`, `Platform/FocalPoint.swift:10,27-39`: punto focal a disco,
  Vision sobre miniatura.
- [x] **V8** (`7e640bf9`) `ios/App/Sources/Screens/RootView.swift:178-189`: 7–8 tareas al activarse; `syncLibrary` doble
  (`RootView.swift:145`, `HomeModel.swift:246`).
- [ ] **V9** Un solo contador por modelo (`OrbitalModels/ObservableModel.swift:17-19,54-58`; `AppEnvironment.swift:13`).
  `@Observable` real empezando por `Services`, `TitleModel`, `HomeModel`. Grande.
- [~] **V10** (7e640bf9, c4015560: faltan listeners por tarjeta y gzip) Menores: formateadores de fecha por llamada (`TraktTypes.swift:195-199`, `Trakt+History.swift:105-111`);
  pantalla bloqueada cada segundo (`PlayerScreen.swift:392`, `PictureInPicture.swift:116-136`); bitácora de descargas en
  Release (`DownloadTimeline.swift:15-40`); `POST /api/ui/state` casi por tecla (`main.js:454-465`); ficha sin caché de un
  minuto; fotos de consola pesadas (`img/consoles/xbox360.png` 322 KB); un listener por tarjeta; estáticos sin gzip.

## F · Arquitectura y cimientos

- [ ] **F1** Contrato TV ↔ iPhone: `api: N` y capacidades en `/api/ping` y `/api/companion`; fixtures que escribe una
  prueba de Python (`tests/fixtures/contract/*.json`) y decodifica Swift. `OrbitalRemote.swift:106-108,576-583`.
- [ ] **F2** Reglas compartidas como datos (`design/streams-rules.json`…): banderas e idiomas
  (`Streams+Language.swift:16-23` vs `orbital/library/streams.py:41`), topes (25 GB vs 15 GB en 1440p: `streams.py:692,697`
  / `Streams.swift:533`), esperas (15 s vs 8 s), mosaico de Explorar (96 vs 48: `foryou.py:72-73` / `ForYou.swift:10`).
- [ ] **F3** Tokens generados desde `design/tokens.json` hacia CSS y Swift; sumar curvas, sombras y tamaño real de letra.
  El vocabulario se compara por subcadena (`tests/web/design-parity.test.mjs:218-226`).
- [~] **F4** (85e2282b: hecho en la TV; falta la cola única del iPhone) iPhone: una sola cola para Trakt (`TraktOutbox.swift:81-127` vs `WatchService.swift:89-95`,
  `WatchService+Queue.swift:10-12,123-154`); descartes con bitácora. TV: scrobble por `trakt_outbox.py`
  (`orbital/scrobble.py:144-151`).
- [ ] **F5** iPhone: `HistoryModel`/`ViewingsModel` en OrbitalModels con pruebas (`HistoryScreen.swift:133-185`,
  `TitleView+TusVistas.swift:123,206`).
- [ ] **F6** Partir gigantes: `orbital/watch.py` (2525, clase `Watch` con 120 métodos), `foryou.py`, `Catalog` como
  localizador; `orbital/web/js/main.js` (2798) y `core/menus.js` (2207); `PlayerScreen*` (43 `@State`), `RootView`.
- [ ] **F7** CI completa: `xcodegen` + `xcodebuild build` Debug y Release sin firma; humo de la TV; `scripts/ios_golden.py`
  con `git diff --exit-code`; etiqueta `tv-estable` (D8-A).
- [ ] **F8** Limpieza: Stremio muerto en el iPhone (`authKey: { nil }` en `Services.swift:287,482`; `StremioAPI.swift`);
  README aún con Stremio como base (líneas 4, 32, 140); docs con Multica/CEN-; `docs/ios-companera.md:37`; `.gitignore`
  para `.playwright-mcp/`, `orbital/mpv-input.conf`, `orbital/orbital-mouse.lua`; `opentelemetry-api` sin uso.
- [~] **F9** (43a4d524: falta la actualización con versiones mezcladas) Servidor, estabilidad: mpv huérfano (`player.py:1423-1431`, Job Object o barrido); `SERVICE_ERRORS` con
  `OSError`/`ValueError` (`net.py:19`, `foryou.py:54`) → `NetError`; un hilo por comando a mpv (`mpv.py:66-69`); SSE que
  descarta eventos (`api/live.py:49-52`); actualización con versiones mezcladas (`updater.py:113-121`).
- [~] **F10** (9af65644: índice de descargas y topes; falta lo demás) iPhone, estabilidad y deuda: índice de descargas que se traga la corrupción (`Platform/FileStores.swift:35-37`);
  UserDefaults sin tope (`IntroDB.swift:28-31`, `Services.swift:70-76`, `ForYou.swift:416-420`); AetherEngine fijado por
  etiqueta y `Package.resolved` sin versionar; errores como texto traducidos por regex (`Support/Strings.swift:26-73`);
  banderas de demo regadas (leer `ProcessInfo` una sola vez); `NSAllowsArbitraryLoads` y `com.example…` en `project.yml`.
- [~] **F11** (40351dca: captura de errores; faltan pruebas con DOM y modelo de foco) Web, estabilidad: captura global de `error`/`unhandledrejection` hacia `ui/trace`; pruebas de `main.js` y
  componentes con DOM; un solo modelo de foco.
