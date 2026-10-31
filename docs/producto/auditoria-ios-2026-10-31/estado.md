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

## Tanda 2 · Rendimiento y arquitectura: PENDIENTE (otra sesión)
A2 reloj del reproductor aparte y `didSet` que comparan; A3 marco de los pósters y valores del entorno en iPad/Mac;
B1 PlayerScreen en subvistas con estado propio (también TitleView, SettingsView, PlayerModel); B2 vistas que llaman
servicios directo → modelos; B7 un solo aviso al cambiar ajustes; B8 CoreDrift (`addChild`, `rootView` solo si cambia el
orden); C5 tareas al volver a la app; C6 `visibleShelves`/`platformHubs`; C7 `phaseAnimator` de HomeChannels;
R3 Inicio quieto 14–19 % de CPU; C4 `endObserver` de AVPlayerEngine (PlayerEngines.swift).
Detalles de núcleo para después: ReleaseCalendarModel sin estado de error (sin red se ve como «sin estrenos»);
CollectionsModel vuelve a preguntar por logos de estudio que no existen.

## Tanda 3 · Sistema de diseño: EN OTRA SESIÓN («Orbital iOS · tanda 3 de diseño»)
D3–D24 de `hallazgos.md` y las 13 reglas nuevas de DesignTests. D1 y D2 (modo claro) se hicieron en la tanda 1.

## Tanda 4 · Auditor autónomo
Lo lanza la sesión de la tanda 3 al terminar: revisa las tandas 1 y 3 y vuelve a intentar romper la app (R5).
