# Verificación de la auditoría iOS · tanda 4 (31 oct 2026)

Auditor autónomo sobre `4b4b6c9a` (main). No arregla nada: revisa en el código lo que estado.md da por hecho, corre las
pruebas y vuelve a intentar romper la app en el simulador.

## Resumen para decidir (5 líneas)

1. **La app no se cayó ni una vez** en unos 45 minutos de maltrato en dos simuladores (iOS 26.3 y 27): ráfagas, «atrás» a media
   animación, reproductor abrir y cerrar de golpe, hojas encimadas, menú largo en Inicio, Explorar y Buscar. El cuelgue R1 quedó arreglado.
2. **Lo grande de las tandas 1 y 3 está hecho de verdad**: 26 de 39 hallazgos cumplen completos y 13 quedan a medias con restos chicos. Ninguno «no se hizo».
3. **Un error que se ve en inglés**: el botón principal de la ficha dice «Charging» (batería) en vez de «Loading» mientras carga.
4. **La CI de GitHub no es confiable todavía**: una prueba de «Mi lista» falla a ratos (3 de las últimas 12 corridas de main), por una carrera en el código, no en la prueba.
5. **Las 13 reglas de diseño existen, pero varias son flojas**: dejan pasar casos reales (3 tokens sin uso, cajas y anillos a mano). Conviene apretarlas en la próxima tanda.

## Pruebas corridas

| Qué | Resultado |
|---|---|
| `swift test` completo (ios/OrbitalCore) | **Verde**: 899 pruebas (435 OrbitalModels + 454 OrbitalCore + 10 Addons), 0 fallas, ~57 s. |
| App Debug (`xcodebuild build`, Orbital QA) | **BUILD SUCCEEDED**. |
| App Release (`generic/platform=iOS Simulator`) | **BUILD SUCCEEDED** (el primer intento chocó con la base de datos de `/tmp/dd-orbital`, ocupada por otra sesión que compilaba para el iPhone; se repitió en su turno). |
| CI de GitHub (`gh run list`, main) | macOS roja en 3 de las últimas 12 corridas terminadas de main (41247493992, 41247021899, 41245721828) y antes en 41244245461, todas por `ScreenModelsTests.testMyListToggleIsLocalTravelsToTraktAndCopiesToStremio` (ScreenModelsTests.swift:286). La de 4b4b6c9a (41249406489) terminó verde en Windows y macOS. La CI de macOS solo corre `swift test`: no compila la app ni corre pruebas de interfaz. |
| La prueba inestable, 20 veces en local | 20/20 verde (en la Mac es rápida; en la CI, más lenta, pierde la carrera). |
| `ChaosRegressionUITests`, Orbital QA (iOS 26.3) | **9/10**. Falla `testMosaicoEnRafaga`: busca `app.otherElements["mosaic"]` y el mosaico ya no aparece con ese tipo. Repetida 2/2. La app está bien: buscado como `descendants(.any)["mosaic"]` está, con 18 piezas, y aguanta 10 arrastres (prueba temporal `testMosaicoPasoAPaso`). Es la prueba la que quedó vieja. |
| `ChaosRegressionUITests`, iPhone 17 Pro (iOS 27) | **9/10**, igual que en 26.3: solo falla `testMosaicoEnRafaga`, por la misma razón (y `testMosaicoPasoAPaso` pasa). |
| Escenarios R5 del auditor (temporal, ver abajo), iOS 26.3 | 3/6 en verde; los 3 rojos eran de la prueba (ver «Lo que intenté romper»). Ningún cierre. |
| Escenarios R5 del auditor, iOS 27 (prueba corregida) | **6/7**. Pasan giro (13 pantallas, con fondo y regreso), fichas en ráfaga, «atrás» a media animación, hojas apiladas, menú largo en Explorar, Buscar e Inicio, y mosaico paso a paso. «Reproductor de golpe» se cortó en la 2.ª o 3.ª vuelta por una carrera de la prueba («Cerrar» se esconde entre encontrarlo y tocarlo), sin que la app se cayera: ese escenario quedó cubierto solo en parte. |
| Bitácoras de cierre `~/Library/Logs/DiagnosticReports/Orbital-*.ips` | **Ninguna nueva**: la última es la de R1 (`Orbital-2026-10-31-120343.ips`, de antes del arreglo). |

## Lo que intenté romper (R5)

Archivo temporal `AuditorR5UITests.swift`, en una copia de trabajo en /tmp (no se commitea), con `-demo` y los mismos
argumentos que la suite de caos. Capturas: `/tmp/orbital-evidencia/auditor/qa263/` y `/tmp/orbital-evidencia/auditor/ios27/`.

| Escenario | Qué hice | Resultado |
|---|---|---|
| Giro a horizontal | 13 pantallas (Inicio, Explorar, Buscar, Descargas, ficha, Guardar, Versión, Ajustes, Lo que ves, mazo, Decide, filtro, control): girar izquierda, desplazar, girar derecha, volver a vertical, ir al fondo y regresar. | **Sin cierres ni pantallas vacías.** En el iPhone la app se queda en vertical a propósito y solo gira el reproductor (`Platform/Orientation.swift:11-13`); el giro del reproductor lo cubre `PlayerRotationUITests`. En 26.3 «fondo y regreso» salió rojo porque la prueba no esperaba; en iOS 27, con espera, las 13 vuelven al frente. Lo que la medición marcó «fuera de la orilla» en Lo que ves son los días del calendario, que se desplaza de lado (falso positivo). |
| Fichas en ráfaga | Seis toques seguidos al mismo póster; luego cinco fichas encadenadas sin esperar a que carguen. | Sin cierres. Seis toques apilan **2** pantallas en vez de 1 (menor). El primer póster bajo la portada era «Seguir viendo», que abre el reproductor directo (`qa263/Orbital_QA-rafaga-fichas.png`). |
| «Atrás» a media animación | Ocho veces: tocar póster y a los 0.15 s «atrás» (botón o gesto desde la orilla). | Sin cierres; la pantalla final tiene contenido. |
| Reproductor entrar y salir de golpe | Seis veces «Ver» → cerrar a los 0.3 s o 1.5 s, una vez girando a mitad. | Sin cierres, pero **cubierto a medias**: en los dos simuladores la prueba se cortó en la 2.ª o 3.ª vuelta porque los controles se escondieron entre encontrar «Cerrar» y tocarlo (falla de la prueba, no de la app). |
| Hojas apiladas | «Guardar» y «Versión» casi a la vez, alerta «Nueva lista» encima de la hoja con giro, y cinco ráfagas Versión/Guardar con cierre por gesto. | Sin cierres. iOS no deja abrir la segunda hoja encima (el botón queda tapado), como debe ser. |
| R1 en Explorar, Buscar e Inicio | Mantener presionado 1.3 s un póster en tres alturas y tocar la vista previa. | **Sin cierres.** El menú sale completo (Ver, Guardar, Descargar, Ver en la TV, No me interesa; `qa263/Orbital_QA-menu-explorar-1.png`). |
| Letra máxima (R2) | La prueba de caos en 6 pantallas. | Verde en 26.3 (0 fuera de la orilla). |
| SE y Pro Max | No alcanzó el tiempo: quedan para la próxima pasada. | — |

Observación sin prueba: en la barra de la ficha de *Severance*, el logo del título sale oscuro sobre el fondo café y casi no
se lee (`qa263/Orbital_QA-fichas-encadenadas.png`). Probablemente es el arte del logo, que viene negro de TMDB.

## Veredicto por hallazgo

Rutas relativas a `ios/App/Sources` salvo que digan otra cosa.

### Tanda 1 · Estabilidad

| Hallazgo | Veredicto | Evidencia |
|---|---|---|
| R1 cuelgue del menú | **cumple** | La ficha lee el entorno como opcional (`Screens/TitleView.swift:11-12`), y también `ProfileButton` (`Screens/Shared.swift:8`) y `AppMark` (`Screens/HomeMark.swift:7`). «Sugerencias para ti» tiene su menú (`Screens/HomeView.swift:112-114`). `ToolbarEnvironmentTests` vigila la barra. `testInicioMantenerPresionadoSugerencia` está verde y en el simulador no hubo cierres. **Riesgo que queda**: `SuggestionActions` (`Screens/ParaTiPieces.swift:9`) sigue leyendo el entorno obligatorio dentro de 5 menús (HomeView:114, :210, :417, ParaTiPieces:68, ListsView:145), y `TitleWatchedWhen` (`TitleView+Watched.swift:20-23`) también. Ninguna prueba revisa `.contextMenu` ni los archivos `TitleView+*.swift`. |
| R2 letra máxima | **cumple** | `DSChapterLabel` ya no tiene ancho fijo (`Design/Collections.swift:111`). El botón del mosaico tiene tope (`Design/ParaTiB.swift:49-61`). `testLetraMaximaSinSalirseDeLaPantalla` está verde, sin `XCTExpectFailure`. Solo mide Explorar arriba, sin desplazar. |
| R4 pruebas viejas | **cumple** | `HomeNewUITests.swift:33-39` usa los botones; `NewFlowsRegressionUITests.swift:155` se salta con motivo; `SkyUITests.swift:34` espera `watching-period`. |
| A1 CI | **a medias** | Se arregló lo que la tenía roja: Tmdb.swift:231-244, RemoteSheet en 576 líneas y la prueba NYT con `Canon.lists` (MatchDeckModelTests.swift:102). Pero la CI de macOS sigue roja a ratos por `testMyListToggleIsLocalTravelsToTraktAndCopiesToStremio`. Causa probable: `TitleModel.load` lanza una tarea suelta (`OrbitalModels/TitleModel.swift:179`: `pullShow` y luego `refreshState`) que puede terminar después del segundo toque y regresar `inLibrary` al valor viejo (`:254`). En la app eso sería «Mi lista» que se regresa sola si tocas justo después de abrir la ficha. |
| D1 filtros en modo claro | **cumple** | `Design/ListControls.swift:217-229` con `dsPrimaryButton(size: .small)`. |
| D2 «Hoy» | **cumple** | `Screens/HomeTimeline.swift:61` `DSBadge(.fresh)` → `DS.success/onSuccess` (`OrbitalCore/.../DesignTokens.swift:82-100`). Contraste ≥4.5 en claro y oscuro: `DesignTests.swift:84-88`. Aumentar contraste solo pide «más que normal» (`:101-104`), no ≥4.5 explícito. |

### Tanda 1 · Núcleo

| Hallazgo | Veredicto | Evidencia |
|---|---|---|
| B3 cachés fuera de UserDefaults | **a medias** | `CacheStore.swift:14` con `actor CacheWriter`; lo usan WatchingModel, ParaTiModel, HomeModel, CatalogModel, RepisaModel y Charts. Hay `CacheStoreTests` (6) y `CacheMigrationTests`. Pero la migración es perezosa: una clave vieja solo se borra cuando se lee (`CacheStore.swift:45-48`). `foryou-mosaic` sigue en UserDefaults (`ForYou.swift:523,532`) y Charts codifica en el hilo de quien llama (`:88`, `:304`). |
| B4 duplicados | **cumple** | `Interleave` en CatalogModel:98, ParaTiModel:334, :389 y ForYou:550; `ShelfFetcher` en ParaTiModel:393. Pruebas: `InterleaveTests` y `ShelfPlanTests`. |
| B5 código muerto | **a medias** | 15 de 16 borrados. **`DSChipText` sigue** (`Design/Badges.swift:33`, solo su declaración). estado.md dice «15 piezas» y la lista tenía 16. |
| B6 estado global | **cumple** | `Tmdb.detailsMemo`, `TmdbDetailsGate.shared` y `MosaicCover.remembered`: 0 resultados. Se inyectan por `Services(detailsMemo:)` y `ParaTiModel.coverWall`. |
| B9 cancelar la fila de TMDB | **cumple** | `Tmdb.swift:507-534`. Pruebas: `TmdbDetailsGateTests.testWhenEveryoneLeavesTheRequestIsCancelled` y `testIfSomeoneStillWaitsItIsNotCancelled`. |
| C1 archivos dañados | **cumple** | `StoredFile.swift` (`.corrupt` y registro) en `Watch.swift:182-185` y `LocalLibrary.swift:103`; `persist` escribe fuera del candado (`:133-141`). Pruebas: `StoredFileTests` (4). Nota: el comentario de `LocalLibrary.flush()` dice que se llama antes de suspender la app, pero nadie lo llama. |
| C2 bitácoras y Perf | **a medias** | `Log.storage/.cache/.network` existen, pero se usan en 5 lugares. Siguen mudos los `try?` de disco de Tmdb (:350), TallArt (:91) y OneDriveLibrary (:71, :117). `Perf` solo apaga `isOn` en Release; es aceptable. |
| C3 URLs sin «!» | **cumple** | `Tmdb.url`, `Trakt.url` y `StremioAPI.iso` sin forzar. `URLSafetyTests` (4). Quedan casos menores con datos: `OneDriveLibrary.swift:236` y `OneDrive.swift:153`. |
| C4 observadores | **cumple** (en modelos) | `NotificationTokens` en ParaTiModel:56 y HomeModel:109/:121, con `NotificationTokensTests`. `endObserver` de AVPlayerEngine sigue pendiente (`PlayerEngines.swift:169,201,210`), como dice estado.md (tanda 2). |
| C8 escribir en cada tecla | **cumple** | `DebouncedWrite` en `GameCompanionView.swift:43-52`; `DebouncedWriteTests`. |
| T pruebas faltantes | **cumple** | Pruebas para los siete modelos (40 en total). `YearRulerLogic` (7 pruebas) y `CoverWall` (5) en OrbitalModels. |

### Tanda 3 · Sistema de diseño

| Hallazgo | Veredicto | Evidencia |
|---|---|---|
| D3 esqueleto | **cumple** | `HeroSkeleton` (`Design/Shelf.swift:69`) con `DS.HomeHero.current`. Queda un comentario viejo en `Feedback.swift:113`. |
| D4 cajas → dsCard | **a medias** | 48 usos de `dsCard`. Quedan cajas a mano que la regla no ve: ternarios en `AdvancedFilterEditors.swift:181` y `Filtro.swift:505`, `.fill` en `ParaTiB.swift:236` y `VoiceRow.swift:276` (`fillStrong`). |
| D5 anillos | **a medias** | `dsSelectionRing` con 11 usos. Quedan dos a mano: `Screens/DecideView.swift:116` (`DS.accent`, 3 pt) y `Screens/YearView.swift:109` (1.5 pt). |
| D6 títulos de hoja | **cumple** | `DSSheetHeader` en Save, SourcesSheet, Downloads, Decide, MatchDeck, RemoteSheet y TitleActions. |
| D7 cerrar | **cumple** | No queda ninguna `xmark` de cerrar fuera de `DSIconButton`. `.glass` y `.circle` solo en el reproductor, Simpson y `Projection.swift:292` (con excepción). |
| D8 temporada | **cumple** | `DSSeasonPicker` en TitleView:373, MiMediaView:312, EpisodePickerSheet:50 y EpisodesPanel:33; las piezas viejas, borradas. |
| D9 botones nativos | **a medias** | Las cápsulas `.plain` listadas se fueron y hay `dsPrimaryButton(size:)` ×10. Siguen **dos secundarios** que se mezclan en la misma pantalla: `dsSecondaryButton` (13) y `dsGlassButton` (28), por ejemplo TitleView:170 y :394. Quedan cápsulas `.plain` a mano en `RemoteSheet.swift:279` y `RemoteStatusCard.swift:37`, que pasan porque la regla exenta todo archivo `Remote*` (`DesignRulesTests.swift:136`). |
| D10 «Nuevo» y «En Mi lista» | **cumple** | `DSCornerRibbon` en HomeTimeline:81 y MiMediaView:125; `DSIconBadge` en Posters:124 y Mosaic:325. |
| D11 rótulos y mayúsculas | **a medias** | `DSGroupLabel` existe y los textos se escriben normal. Pero `.textCase(.uppercase)` sigue regado fuera de la pieza: VoiceRow:116/145/227, MazoMatch:52, PlatformFan:35 y Collections:154. |
| D12 recetas torcidas | **cumple** (lo que pedía) | `.weight(`/`.fontWeight(` sobre receta: 2, con excepción. Pero 71 `Text`/`Label` siguen con `.font(DS.TextRecipe.X.font)` en vez de `.recipe()` (SettingsView 13, Guide 11, VoiceGuideView 10…). |
| D13 radios de logos | **cumple** | `DS.Radius.logo(lado)` y `DS.Radius.tag` (`Tokens.swift:176-179`) en todos los logos y placas. |
| D14 realce del puntero | **cumple** | `pointerHover(_:radius:)` (`Projection.swift:391-396`); PosterCard con `radius: DS.Radius.md` (`Posters.swift:117`). |
| D15 ritmo | **cumple** | `DS.Layout` pasó de 14 a 63 usos; la prueba prometida existe (`testScreensKeepTheLayoutRhythm`). Dos rejillas de BrowseView (:339, :372) usan `DS.Space.s3`. |
| D16 opacidades | **a medias** | `DS.Opacity` con 15 usos y ningún número suelto. Quedan 15 `DesignTokens.Opacity/Motion` directos (TitleActions:56-57, PlayerControls:127, Backdrop:152, más los `Task.sleep` que estado.md ya declara). |
| D17 movimiento | **a medias** | Ya no queda ningún `DS.Motion.*(false)`. Queda la curva a mano `.linear` de `TitleActions.swift:18` (la regla no la ve porque va sin paréntesis) y unas 14 transiciones armadas a mano. |
| D18 nombres que se pisan | **a medias** | Los préstamos se quitaron. Siguen todos los alias (`eyebrow`, `orbitalBlue`, `good`, `solidPrimary`, `switchOn`), `Collections.orbital` fijo y dos dorados. estado.md solo declara `statScale`. |
| D19 cargas y vacíos | **cumple** | `DSLoadingState`, `DSInlineProgress` ×10 y `DSEmptyState` en VoiceGuide y Calificar. |
| D20 placa sin vidrio | **cumple** | `Editorial.swift:59-64,124` con `DS.badgeBackground`. |
| D21 sombras | **cumple** | Solo quedan sombras a mano en el reproductor y en Simpson (excepciones). |
| D22 tokens sin uso | **a medias** | Siguen sin uso `PlayerPanel.portraitCenterRange` y `PlayerPanel.portraitTop` (`Tokens+Player.swift:121,124`), y uno nuevo: `DS.Motion.lockShrink(_:)` (`Tokens.swift:270`). La regla 13 no los ve (abajo). Además `DSChipText` (B5). |
| D23 docs | **a medias** | `docs/ios-proyeccion.md` y la tabla de Tokens.swift ya están bien. Siguen comentarios que dicen «ámbar» (Tokens.swift:64, Badges.swift:215-219, Editorial.swift:5, Labels.swift:13, Shelf.swift:18, Tokens+Screens.swift:241) y «SF Mono» (Art.swift:170, Projection.swift:253). |
| D24 escala y esquinas | **cumple** | Los casos listados ya usan `DS.Radius`/`DS.Space`. Solo 3 `RoundedRectangle` no son continuos, y son del reproductor. |

### Las 13 reglas (`ios/OrbitalCore/Tests/OrbitalCoreTests/DesignRulesTests.swift`)

Las 13 existen y recorren Design/ y Screens/ con sus subcarpetas, Onboarding incluida. Hay 78 `ds-exception:` en Design y
Screens (90 en todo App/Sources), y la mayoría tiene motivo legítimo: arte, reproductor, Simpson y demo. `hits()` se salta cualquier
renglón con `ds-exception:`, sea para la regla que sea.

| Regla | Veredicto | Huecos encontrados |
|---|---|---|
| 1 tokens en la escala | floja | Solo nombres que terminan en radius/gap/padding/inset/spacing; no ve `corner = 60`, `seekBubbleSideMargin = 64` ni `barTitleLeading = 72` (Tokens.swift). |
| 2 cuentas que inventan | cumple | Un `/ 2` en cualquier parte exime todo el renglón; sin casos reales. |
| 3 recetas sin torcer | floja | No ve `.monospaced()`/`.italic()` sobre receta ni un `.fontWeight` en el renglón siguiente (RepisaView:238, :275). |
| 4 sombras | cumple | — |
| 5 botones nativos | floja | Exime todo archivo `Remote*`, y por eso pasan RemoteSheet:279 y RemoteStatusCard:37 (D9). |
| 6 una caja, una pieza | muy floja | Solo la forma literal; se le escapan ternarios, `in: shape`, `fillStrong`, `UnevenRoundedRectangle` y `.fill(DS.fill)` (MatchDeckScreen:77, RemoteStatusCard:46). |
| 7 esquinas continuas | cumple | No revisa `UnevenRoundedRectangle` (hoy van bien). |
| 8 movimiento | floja | Exige paréntesis: no ve `.linear,` (TitleActions:18); no revisa transiciones. |
| 9 vacíos y cargas | floja | No ve vacíos escritos a mano (SaveView:89, AdvancedFilterEditors:206). |
| 10 papel solo sobre arte | floja | Solo `background(DS.paper`; no ve `.fill(DS.paper)` (Remote.swift:242). |
| 11 ritmo | floja | No ve `ScrollView` sin stack (BrowseView:339, :372) ni pantallas con desplazamiento en Design/. |
| 12 hojas, cerrar y mayúsculas | floja | No ve `Button(…, systemImage: "xmark")` (Filtro:476) ni `.uppercased()` (RichTitle:13); exime `Remote*`. |
| 13 tokens sin uso | **falla en lo que promete** | Compara por pedazo de nombre: `portraitTop` cuenta como usado por `portraitTopClearance`, y `lockShrink` por `lockShrinkDuration`. Además no lee declaraciones con tipo genérico (`portraitCenterRange: ClosedRange<CGFloat>`). Arreglo: `\bDueño\.token\b` y aceptar genéricos. |

Excepciones dudosas (salidas fáciles más que motivos): `Filtro.swift:371` («dsCard no tiene ese nivel»: falta el nivel),
`Projection.swift:292` (falta la variante de arte de DSIconButton), `Filters.swift:118` (receta torcida a propósito),
encabezados exentos en WrappedView:123/132/163 y TVCards:156, y la exención por archivo `Remote*` en las reglas 5 y 12.

### Lo que estado.md declara como no hecho o para después: confirmado

- Tanda 2 completa: pendiente (A2, A3, B1, B2, B7, B8, C5, C6, C7, R3 y `endObserver` de C4).
- D18 `statScale`, opacidad 0.10 de VoiceRow, `Task.sleep` con DesignTokens.Motion, curvas aproximadas, eyebrow en
  `DSSheetHeader` y `PlatformLogoTile(glow:)`: tal cual.
- «No me interesa» sigue en la vista (`Screens/HomeView.swift:243-251`).
- **«Cargando» → «Charging» es un error real que se ve**: `scripts/ios_strings.py:620` lo traduce así y llega a
  `Resources/Localizable.xcstrings` (en: «Charging»). Solo `Design/Companion.swift:82` habla de la batería; el resto son
  cargas: el botón principal de la ficha (`Screens/TitleView+Acciones.swift:120`), PlayerControls:337, Feedback:148,
  PlayerIndicators:66 y MatchDeckScreen:79. Arreglo: separar la clave de la batería.

## Lo que estado.md dice y no es del todo exacto

1. «B5 15 piezas sin uso borradas»: eran 16 y `DSChipText` sigue.
2. «D22 51 tokens sin uso borrados»: quedan 3 sin uso que la regla 13 no ve.
3. «CI de macOS verde» (en cb110385 y cb8a9421): era cierto en esa corrida, pero la CI no es estable (prueba de Mi lista).
4. «`ChaosRegressionUITests` con 10 escenarios confiables»: `testMosaicoEnRafaga` falla siempre en los dos simuladores (la prueba busca el mosaico con un tipo que ya no tiene).
5. «Migración desde UserDefaults» (B3): solo al leer cada clave; `foryou-mosaic` sigue ahí.

## Qué haría después (orden sugerido)

1. La carrera de `TitleModel.swift:179` (también pinta la CI de rojo) y «Charging».
2. `testMosaicoEnRafaga`: `descendants(matching: .any)["mosaic"]`.
3. Regla 13 con límite de palabra; borrar los 3 tokens y `DSChipText`.
4. Apretar las reglas 5, 6, 8 y 12 (quitar la exención `Remote*`) y limpiar lo que salga: D4, D5, D9 y D11.
5. Una prueba que revise los `.contextMenu` como `ToolbarEnvironmentTests` revisa la barra, o volver opcional el entorno de `SuggestionActions`.
6. Pasar R5 en SE y Pro Max.
