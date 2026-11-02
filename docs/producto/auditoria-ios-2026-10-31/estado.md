# Estado de los arreglos (31 oct 2026)

## Tanda 1 · Estabilidad y núcleo

**Núcleo: terminado.** Commits 475f89b8 … 35feea77.
- A1 Tmdb.swift:217 (`Tmdb.posterRanksBelow`), más tres arreglos para el compilador de la CI, que es más viejo
  (2cd10a2b, 11befeb7, 35feea77: cierres asíncronos como valor por omisión → `AsyncDefaults`, `Trakt.sleep`).
- B3 `CacheStore`: archivos en Caches/Orbital-SWR/models, con migración desde UserDefaults (CacheStoreTests, CacheMigrationTests).
- B4 `Interleave` y `ShelfFetcher`; B5 15 piezas sin uso borradas; B6 sin `Tmdb.detailsMemo` ni `TmdbDetailsGate.shared`
  (los da Services), `ParaTiModel.coverWall`; B9 la fila de TMDB cancela si todos se van.
- C1 `StoredFile` (archivo dañado → `.corrupt`), `LocalLibrary` escribe fuera del candado; C2 `Log` por tema, `Perf` solo
  en Debug; C3 `Tmdb.url`/`Trakt.url` sin «!» (URLSafetyTests); C4 `NotificationTokens`; C8 `DebouncedWrite`.
- T `YearRulerLogic` y `CoverWall` en OrbitalModels; 38 pruebas para siete modelos; arreglado: premios sin clave de TMDB daba 0.

**Estabilidad: terminado.** Commits 987e925d, cc1749e3, b1247e5a, 10978552, ba2af6fb, 214ec152, cb110385.
- R1 el cierre era `TitleView` armado sin `AppEnvironment` al abrir la ficha desde la fila sin menú: la ficha y la barra
  (`ProfileButton`, `AppMark`) leen el entorno como opcional y la fila «Sugerencias para ti» tiene su menú
  (ToolbarEnvironmentTests; `ChaosRegressionUITests` con 10 escenarios confiables, banda `-demo-free-tabs`).
- R2 letra XXXL: Inicio, Buscar, Descargas y ficha (testLetraMaximaSinSalirseDeLaPantalla). PENDIENTE: el botón «Pasear
  por el mosaico» de Explorar (Design/ParaTiB.swift) se sale por la derecha (fallo esperado no estricto en la prueba).
- R4 pruebas viejas al día (la del Wrapped se salta con motivo). A1 ruff, prueba de NYT y RemoteSheet bajo el tope
  (`RemoteStatusCard`): CI de macOS verde en cb110385.
- D1 filtros activos con `DS.primary`/`DS.onPrimary`. D2 «Hoy» con `DesignTokens.PhoneRole.success/onSuccess` (solo
  iPhone, fuera de design/tokens.json), ≥4.5:1 en claro, oscuro y aumentar contraste.
- Para después: el «No me interesa» de Inicio vive en HomeView (pasarlo a HomeModel); en inglés «Cargando» se traduce
  «Charging» (scripts/ios_strings.py:620; revisar si es la batería del control o un error); la CI de Windows falla en la
  prueba de humo de la TV (`DemoTrakt` sin `public_list_items`), que es del lado de la TV.

Página con el antes y el después: https://claude.ai/artifact/NUSkqvxm26CctNuUHHkFRR

## Tanda 2 · Rendimiento y arquitectura: TERMINADA salvo B1 y parte de B2 (31 oct)

Commits 0ec0af48 … 6abd316f (13). `swift test` completo verde en cada tema; la app compila en Debug y Release; CI de GitHub
verde en main. Lo que se ve no cambió (comprobado en «Orbital QA»: Inicio, Canales, reproductor, Explorar, «Tu año»).

**Cifras de CPU** («Orbital QA», iOS 26.3, app en reposo 20 s, sin -demo-no-idle, medido con `ps`):
- Inicio quieto: antes 17.8 % y 18.1 % → después 6.5 % y 6.1 %. Memoria igual (~415–440 MB).
- Inicio con Canales a la vista: 16.5 % → 13.3 % (el simulador va a 60 Hz; en un iPhone ProMotion la ganancia es mayor).
- Diagnóstico: con el cielo quieto y sin el acercamiento de los canales, Inicio gasta 0.2 %; el acercamiento costaba ~18 % aun
  fuera de pantalla y el cielo ~15 % a 12 cuadros (proporcional: a 6 cuadros, 7 %).

**Hecho.**
- R3 + C7 (0ec0af48): el acercamiento de cada canal solo corre si la tarjeta y la fila se ven y la app está al frente, a 30
  cuadros (TimelineView en vez de `phaseAnimator`); el cielo pinta 6 cuadros quieto y 12 al inclinar el teléfono
  (`SkyPace`, `DS.Sky.calmFrame`). Sin prueba unitaria (es dibujo); medido antes y después.
- A2 (9e0a96d5): `PlayerTime` (posición y duración) aparte del `PlayerModel`; el `snapshot` solo avisa a la pantalla si cambió
  algo más que la posición; la barra, sus tiempos, la pantalla del iPod y el «ya llegó» leen el reloj en `PlayerTimeReader`.
  Los `didSet` de PlayerModel comparan antes de avisar (menos `request`, que no es Equatable). PlayerTimeTests.
- A3 (a408ccd1): el marco del póster en `FrameBox`, que SwiftUI no observa. Lo demás de A3 ya estaba en 5cae2625.
  No se probó en el simulador del iPad (cambio chico: el marco solo se lee al tocar).
- C5 (322934a7): `ForegroundRefresh`: al abrir, todo menos la biblioteca; de regreso de segundo plano, todo si pasaron 2 min;
  con el Centro de control, nada. ForegroundRefreshTests.
- C6 (0832c92b): `visibleShelves` y `platformHubs` guardados en ParaTiModel hasta que cambie de lo que salen. ShelfPlanTests.
- B7 (fe1d7f48): `reconfigure()` junta sus avisos en uno; `SettingsModel.update` avisa una vez (antes 7 al cambiar el idioma).
  ScreenModelsTests.testCambiarElIdiomaAvisaUnaSolaVez.
- B8 (8aad3437): el controlador de cada columna del muro se cuelga con `addChild` al entrar a la ventana; `rootView` ya solo
  cambiaba con el orden.
- C4 (35b19d0c): `AVPlayerEngine` quita `endObserver` en `deinit`.
- B2, primera parte (3a998414): `PersonModel` (PersonView ya no llama a TMDB) y `YearReviewModel` (YearView ya no llama a
  Para ti). PersonModelTests, YearReviewModelTests.
- Núcleo (ab9470eb): ReleaseCalendarModel guarda el problema (`Degraded`) y el día enseña el aviso del modo degradado con
  «Reintentar» en vez de «no sale nada». ReleaseCalendarModelTests.
- Núcleo (6abd316f): CollectionsModel recuerda los estudios sin logo (si TMDB no contestó, sí reintenta). CollectionsModelTests.
- 9278d3ea: DebouncedWriteTests falló una vez con la Mac ocupada (200 ms fijos); ahora espera hasta 2 s.

**No hecho (por qué).**
- B1 (PlayerScreen, TitleView, SettingsView y PlayerModel en subvistas con estado propio): no alcanzó. Es reestructurar
  ~2,400 líneas del reproductor con 43 `@State` y gestos encadenados; hacerlo con prisa arriesga romper gestos y el candado.
  A2 ya quitó lo que más costaba (repintar todo cuatro veces por segundo). Propuesta para la siguiente sesión, por
  responsabilidad: capa de gestos (`PlayerScreen+Gestos` + `PlayerDragState`), controles (`+Controles` + barra), panel de
  subtítulos/audio (`+Panel` + `PlayerDockState`) y el iPod, cada una con sus entradas estrechas y su estado.
- B2, el resto: PlayerScreen (+Controles 169/317/323) y DecideView:272 siguen llamando servicios; `DownloadsModel` se arma en
  AppEnvironment y en PlayerScreen+CicloDeVida; ~60 `AppEnvironment.shared` en vistas (casi todos para armar su modelo en
  `init`, que es el patrón de la app). Lo del reproductor conviene hacerlo junto con B1.
- B7, la otra mitad: `AppEnvironment.services` registra lectura en cada vista; con un solo aviso por ajuste ya no se nota.

## Tanda 3 · Sistema de diseño: TERMINADA (31 oct)

Commits 73328f33 … cb8a9421 (16). CI de GitHub verde en cb8a9421. `swift test` completo verde; la app compila en Debug y
Release. Capturas antes/después (11 pantallas, oscuro y claro, «Orbital QA»): /tmp/orbital-evidencia/diseno/ y
antes-despues.html (fuera del repo).

**Hecho.**
- Piezas y tokens (Design/Surfaces.swift, Buttons.swift, Tokens.swift): .dsCard(.row/.card, translucent:), DSCard,
  DSSheetHeader, DSInlineProgress, .dsSelectionRing, DSGroupLabel, .glow, DSSeasonPicker, DSIconButton(size:),
  dsPrimaryButton(size:), dsGlassButton, dsOnSolidButton(primary:); DS.Stroke, DS.Opacity, DS.Motion.fade/snap/reveal/appear,
  DS.Glow, DS.Elevation.floating, DS.Radius.tag/logo(lado), DS.Sheet.maxShare; recetas label, labelLarge, badge, groupLabel, stat.
- D3 HeroSkeleton (medida de la portada, DS.HomeHero.current). D4 cajas → dsCard. D5 lo elegido con dsSelectionRing en el
  color del texto. D6 DSSheetHeader en Guardar, Versión, glosario, subtítulos de Descargas, Decide, mazo y control (iPad/Mac).
  D7 cerrar y círculos → DSIconButton. D8 DSSeasonPicker (cápsulas «T1, T2…») en la ficha, Mi media, la hoja de episodios y el
  reproductor; se borraron DSOptionMenu, DSChipRow y SeasonChip. D9 botones nativos (reproductor, voz, subtítulos, Toast,
  plataformas). D10 «Nuevo» listón en Mi media; «En Mi lista» ícono en el mosaico. D11 DSGroupLabel; «Te escucho»,
  «Preguntándole a tu Orbital», «✓ En la TV», «Mi lista»/«Paso», «Top» escritos normal. D12 ~200 recetas torcidas → recetas
  con nombre. D13 radios de logos y placas. D14 pointerHover(_:radius:). D15 DS.Layout en el primer stack de cada pantalla.
  D16 DS.Opacity. D17 DS.Motion (12 animaciones que se movían con «Reducir movimiento» ahora solo funden; HomeView usa
  appear). D18 préstamos quitados (salvo los de abajo). D19 cargas y vacíos con su pieza. D20 placa sin vidrio. D21 sombras
  DS.Elevation/.glow. D22 51 tokens sin uso borrados (y el carrusel `Deck` salvo veilStart). D23 docs/ios-proyeccion.md y la
  tabla de Tokens.swift. D24 tokens de pieza en la escala (excepciones con motivo).
- Las 13 reglas en ios/OrbitalCore/Tests/OrbitalCoreTests/DesignRulesTests.swift (no en DesignTests: lo pasaría del tope de
  600 líneas). Escanean Design/ y Screens/ recursivas. Excepciones legítimas con `ds-exception: motivo` en su renglón.
- Pendiente de la tanda 1: botón «Pasear por el mosaico» con letra XXXL (ParaTiB): tope al glifo y se quitó el
  XCTExpectFailure de ChaosRegressionUITests.testLetraMaximaSinSalirseDeLaPantalla. La causa de verdad era otra: el rótulo de
  sección (`DSChapterLabel`, «LO QUE SE VE HOY») tenía `fixedSize` y con letra AX5 ensanchaba toda la página de Explorar;
  ahora baja a dos renglones. Además «¿Qué vemos hoy?» pone el abanico arriba del texto con letra de accesibilidad. La prueba
  pasa en «Orbital QA» (6 pantallas, 0 fuera de la orilla).

**Cambios a la vista a propósito (para igualar).** Lo elegido ya no es turquesa (Decide, plataforma del Top 10, respuesta
correcta del Wrapped: anillo en el color del texto); «✓ En la TV» pasa a verde; pies de Explorar y la Repisa de 32 a 56 pt;
bajo el título 12 pt en Colecciones, Decide, Más filtros, listas y calendario; la tarjeta Desde la TV con esquina 18 (antes 22);
opacidades de «apagado» a 0.6/0.35/0.4; algunas sombras y brillos a la escala (±4 pt).

**No hecho / a medias (por qué).**
- D18: DS.Size.statScale sigue como factor de escala genérico en varios textos (no hay un token mejor; queda documentado).
- Opacidad 0.10 de VoiceRow pasó a selectedFill (0.12): no hay token de «relleno tenue».
- Duraciones de `Task.sleep` con DesignTokens.Motion en TitlePanel y el candado del reproductor: no hay duración en DS.
- Curvas aproximadas: salida de la carta del mazo (era easeIn) y el destello de la repisa (más corto) ahora con DS.Motion.
- Falta un lugar para la línea de arriba (eyebrow) en DSSheetHeader: en el mazo queda sobre el encabezado.
- `PlatformLogoTile(glow:)` recibe un número que solo se usa como sí/no (cualquier valor da .strong).

## Tanda 4 · Auditor autónomo
Lo lanza la sesión de la tanda 3 al terminar: revisa las tandas 1 y 3 y vuelve a intentar romper la app (R5).

## Tanda 6 · Arreglos de las verificaciones (1 nov 2026)

Commits 6701e2e3 … 22d5d7c0 (8). `swift test` completo verde sobre main 56380150 (938: 461 OrbitalModels + 467 OrbitalCore +
10 Addons); la app compila en Debug y Release. Se probó en una copia aparte (/tmp) porque otras sesiones tenían archivos a
medias en el mismo checkout. CI de GitHub: macOS (las pruebas del iPhone) verde; Windows rojo por pyright en el Python de la
TV (`orbital/library/trakt.py`), de otra sesión, fuera de este alcance.

**Hecho.**
1. iPad de pie, Top 10 de Buscar: **ya lo había arreglado otra sesión** (f9ac5bb3 quitó el gesto de toque del zoom que se
   comía el toque). `IPadLayoutUITests.testTitleOpensInTheSidePanel` verde en «Orbital QA iPad» (vertical y horizontal).
2. «Siguiente · T1 E2» al cruzar el 90 % (c0da04fb): `PlayerModel.pastNextMark` avisa una vez al cruzar la marca
   (`PlaybackRules.nextEpisodeAt`). PlayerTimeTests.testCruzarElNoventaPorCientoAvisaUnaVez. Lo demás que lee la posición fuera
   del reloj son toques y gestos (leen al momento) y la bitácora.
3. Temporadas (7742de92 y la regla en db5cd8f2): `DSSeasonMenu` (menú nativo) en la ficha, Mi media y la hoja de episodios;
   las cápsulas `DSSeasonPicker` solo en el reproductor. DesignRulesTests.testSeasonChipsOnlyInThePlayer. README, D8,
   docs/ios-proyeccion.md y el registro de paridad (TV pendiente: su ficha usa pestañas «T1…»). Sin captura de la lista: hay
   que bajar por la ficha con una prueba de interfaz (más de 2 min).
4. Carrera de «Mi lista» (6701e2e3): una lectura de lo tuyo que salió antes de un toque ya no pisa el botón
   (`TitleModel.libraryEdits`). ScreenModelsTests.testMyListToggleIsNotUndoneByARefreshInFlight (fallaba 6 de 20 vueltas).
5. «Charging» (2672173c): «Cargando» → «Loading»; la batería tiene su clave («Cargando la batería» → «Charging»).
6. testMosaicoEnRafaga (22d5d7c0): busca el mosaico en cualquier tipo y arrastra en vertical y diagonal (un arrastre de lado
   es el gesto que regresa a Explorar). Verde en «Orbital QA».
7. Regla 13 (db5cd8f2): palabra completa y tipos genéricos, de 287 s a 0.4 s. Borrados: PlayerPanel.portraitCenterRange y
   portraitTop, DS.Motion.lockShrink, Collections.weight, Mosaic.idle/alive/buffer y DSChipText.
8. Reglas 5, 6, 8 y 12 (db5cd8f2): sin la exención `Remote*`; la 6 ve ternarios, fillStrong, esquinas desparejas, `in: shape`
   y la caja como forma (`.dsCard(fill:)`); la 8 ve curvas sin paréntesis (`DS.Motion.steady`); la 12 ve el ✕ en
   `Button("Cerrar", systemImage:)` y las mayúsculas fuera de la pieza `.dsCaps()`. Limpieza: D4 (9 cajas a dsCard), D5
   (anillos de Decide y del mapa del año), D9 (dos cápsulas del control), D11 (7 mayúsculas a `.dsCaps()`).
9. Menús contextuales (50a719c5): `SuggestionActions` lee el entorno opcional y ToolbarEnvironmentTests revisa cada
   `.contextMenu` (y ahora lee el bloque completo de `.toolbar`, que antes se saltaba al primer bloque de adentro).
10. Colecciones (108c6e43): «La más reciente que te falta» sale de lo filtrado. Sin prueba unitaria (es la vista).

**Cambios a la vista a propósito.** Temporadas en lista desplegable; las casillas chicas de versiones, filtros, premios y
calificación pasan de esquina 10 a 13 (dsCard); el anillo de la elegida en Decide va en el color del texto (antes, el acento);
«Mapa de sustos» y «Reintentar» del control son botones secundarios nativos; la batería dice «Cargando la batería».

**No hecho / queda.**
- `TitleWatchedWhen` (TitleView+Watched.swift) sigue con entorno obligatorio; hoy no va en barra ni menú, así que la prueba
  no lo marca.
- La regla 6 no revisa casillas con `Circle`/`Capsule` (son controles, no cajas), y no hay regla para anillos de selección
  a mano (los dos que había ya se fueron).
- R5 en SE y Pro Max sigue sin pasarse.
