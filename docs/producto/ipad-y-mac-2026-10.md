# Orbital en iPad y Mac (plan del 28 oct 2026)

Objetivo: llevar la app del iPhone al iPad y a la Mac **con el menor mantenimiento posible**, conservando el sistema visual
Proyección. Plan hecho leyendo el código de `main` en `d190e4d1` (sin compilar) y atacado por un agente independiente; esta es
la versión corregida. Lo marcado «supuesto» no se verificó.

## Decisión de arquitectura

**Una sola app, un solo target. El iPad entra como aparato de primera; la Mac usa la misma app de iPad («Diseñada para iPad»).**

| Opción para la Mac | Qué ve quien la usa | MKV (AetherEngine) | Mantenimiento | Veredicto |
|---|---|---|---|---|
| **«Diseñada para iPad»** | La app de iPad en una ventana de Mac, con el mismo aspecto | Sí: corre la rebanada `ios-arm64` | Casi nada: ninguna plataforma nueva que compilar | **Elegida** |
| Mac Catalyst | App de Mac o iPad escalado | **No**: las 11 xcframeworks del motor (FFmpegBuild 3.7.1, `Dovi`, `TrueHD`) no traen `maccatalyst` | Medio: plataforma nueva, filtros de widgets y del motor | Descartada |
| App nativa de macOS (SwiftUI) | La más pulida | Sí: rebanada `macos-arm64_x86_64`, ejemplo `DemoPlayerMac` | Alto: lo táctil y lo de UIKit se rehace | Solo si un día hace falta una app de Mac de verdad |

Lo que se pierde con «Diseñada para iPad»: no parece app de Mac (sin menús de Mac propios más allá de los de iPadOS) y solo
corre en Macs con chip de Apple, no en Intel.

## Regla que sostiene el bajo mantenimiento

Lo exclusivo de un aparato vive **solo** en `App/Sources/Platform/` detrás de una interfaz común. Fuera de ahí quedan
prohibidos `UIScreen`, `UIDevice`, `userInterfaceIdiom` y `requestGeometryUpdate`. Las pantallas deciden por el **espacio
disponible** (tamaño de la ventana), nunca por «qué aparato es». Una prueba lo verifica.

## Etapas

### Etapa 0 · Ordenar sin cambiar nada para quien usa el iPhone

Criterio de éxito: **capturas antes y después idénticas** en SE, mini, Pro Max (Orbital QA, iOS 26.3) y el «iPhone 17 Pro»
de iOS 27, en vertical (el resto de la app es solo vertical; el reproductor no se toca). El mini es el caso límite: el
umbral de pantalla corta es 700 pt. Un commit por pantalla para revertir solo lo que falle.

| # | Cambio | Riesgo en el iPhone |
|---|---|---|
| 0.1 | Prueba de arquitectura con la lista **real** de pendientes: 37 archivos usan tipos `UI*`, 26 fuera de `Platform/` (incluye `Support/HardwareVolumeButtons`, `UIApplication.connectedScenes` en `SourcesSheet`, `beginBackgroundTask` en `RootView`, `AVAudioSession`/`isIdleTimerDisabled` en `PlayerScreen`, `UIPasteboard`). La lista solo puede encogerse | Ninguno |
| 0.2 | Interfaces en `Platform/` para lo que no existe en todos lados: Live Activities, volumen por botones, info del aparato. `AppEnvironment.swift:316` hoy manda `kind: "iphone"` a la Orbital para todo lo que no es iPad: preparar `ipad` y `mac` | Muy bajo |
| 0.3 | «Medir la ventana» en vez de la pantalla: 11 lecturas de `UIScreen.main.bounds` que alimentan ~23 llamadas en 9 archivos (`keyHeightFitted` ×6, `PlatformFan.width` ×7, `padHeightFitted` ×3, `maxShareFitted` ×3, `narrow` ×2, `airingWidth`, `isShortScreen`). Los tokens estáticos pasan a funciones que reciben el tamaño. Se mide **la ventana completa, con áreas seguras** (no un `GeometryReader` que las resta ~90 pt). `Tokens.swift` también compila en la extensión de widgets: el tamaño se define donde la vean las dos | Bajo a medio: en el iPhone mide lo mismo; cambia *cuándo* se recalcula |

**No se toca el reproductor**: brillo (`PlayerScreen+Gestos.swift` 271/288, `PlayerScreen.swift` 378/542) y orientación
(`PlayerScreen+CicloDeVida.swift` 197–222, `PlayerScreen.swift` 371/540) quedan en la lista de pendientes hasta la Etapa 1.

### Etapa 1 · iPad (y con eso, la Mac)

| # | Cambio |
|---|---|
| 1.1 | `TARGETED_DEVICE_FAMILY: "1,2"` en `Orbital`, `OrbitalWidgets` y `OrbitalUITests`; cuatro orientaciones en iPad |
| 1.2 | **Toda la app en cualquier tamaño y orientación.** iPadOS 26 ignora la máscara de orientación con multitarea y deja en desuso `UIRequiresFullScreen`. El candado `AppDelegate.orientations = .portrait` (`AppEnvironment.swift:51`, `:842`, `:877`) queda solo para el iPhone, en `Platform/` |
| 1.3 | Reproductor: en iPad y Mac se **apaga** el forzado de giro (`requestGeometryUpdate`, `UIDevice.orientation`) y el gesto de brillo; el sistema decide el giro y el panel lateral cabe siempre |
| 1.4 | Pestañas con `.tabViewStyle(.sidebarAdaptable)`: barra abajo en iPhone, lateral en iPad |
| 1.5 | Hojas: en ancho regular iPadOS ignora `.presentationDetents([.height(…)])` (`RemoteSheet.swift:61` y su medición en 45/55/57, `DecideView.swift:46/72`, `SourcesSheet.swift:228`, `Projection.swift:342/356`). Usar `presentationSizing` (`.form`/`.fitted`) y decidir cómo se ve el control remoto en iPad (decisión de producto, con maquetas) |
| 1.6 | Layouts puros extendidos, no duplicados: casos de iPad en `MosaicLayout` (ya prevé 6 columnas), `PlayerLayout`, `ShelfPlan`; ancho máximo legible en fichas |
| 1.7 | Puntero, teclado y **barra de menús de iPadOS 26** (`.commands`): espacio, ←/→ ±10, ⌘F buscar, ⌘, Ajustes. Sirve igual en iPad con teclado y en la Mac. Cada atajo con su lugar en el menú (regla de las cuatro superficies) |
| 1.8 | Pruebas: un simulador de iPad (adelgazado con `simslim`) en cada pasada: vertical, horizontal y media pantalla |

### Etapa 2 · Mac («Diseñada para iPad»)

| # | Cambio |
|---|---|
| 2.1 | Marcar la app como disponible en Macs con chip de Apple; instalar con firma de desarrollo |
| 2.2 | Lo que no existe en la Mac se apaga en `Platform/`: brillo, botones de volumen, Live Activities (supuesto) |
| 2.3 | Verificar en la Mac real: descargas en segundo plano, `BGTaskScheduler`, PiP, micrófono y control por voz |
| 2.4 | Pruebas: una pasada manual en la Mac por cada versión (las UITests usan gestos táctiles y `XCUIScreen.main`; no se portan) |

## Avance

| Paso | Estado |
|---|---|
| 0.1 Prueba de frontera (`PlatformBoundaryTests`) | Hecho (`e517f97d`) |
| 0.2 Tipo de aparato y botones de volumen en `Platform/` | Hecho (`929dafaf`) |
| 0.3 Medir la ventana (`Platform/WindowMetrics.swift`, `.tracksWindowSize()` en la raíz) | Hecho. La medida suma los márgenes seguros: con `ignoresSafeArea` faltaba la barra de estado y el control completo quedaba ~50 pt más bajo (lo cacharon las capturas) |
| 1.1 iPad en el proyecto (`TARGETED_DEVICE_FAMILY "1,2"`, cuatro orientaciones) | Hecho |
| 1.2 / 1.3 Giro: `Platform/Orientation.swift`; en iPad y Mac no se fuerza; brillo en `ScreenBrightness` | Hecho |
| 1.4 Pestañas `.sidebarAdaptable` | Hecho |
| 1.5 Hojas: `.fittedFormSizing()`; el control abre completo en ventana ancha | Hecho |
| 1.7 Barra de menús (`AppCommands`): Ir (⌘1–3, ⌘F, ⌘R) y Reproducción (espacio, ←/→, ⌘L, Esc) | Hecho |
| 1.6 Layouts del iPad | Hecho: cuadrícula de pósters con columnas adaptables (`DS.Poster.gridColumns(for:)`); hojas que se desplazan con su alto ideal (`fittedFormSizing(idealHeight:)`); el reproductor es horizontal en ventana ancha si es más ancha que alta |
| 1.8 Pruebas de iPad | Hecho: `IPadLayoutUITests` (4/4 en «Orbital QA iPad», iPad Pro 11" iOS 27) |
| Textos por aparato | Hecho: variaciones de dispositivo del catálogo («iPad», «la Mac»), generadas por `scripts/ios_strings.py` |
| 2.1 Mac «Diseñada para iPad» | Compila y firma (el perfil de desarrollo incluye la Mac). Las pruebas de interfaz no corren ahí (Xcode no lo permite) y abrirla a mano desde una terminal la deja suspendida: se lanza la primera vez desde Xcode (abajo) |
| 2.2 Lo que no existe en la Mac | Brillo apagado (`ScreenBrightness`); giro no forzado; Live Activities y botones de volumen no hacen nada ahí (supuesto, sin verificar en la Mac) |
| 2.3 Descargas de fondo, PiP y voz en la Mac | Pendiente de probar en la Mac real |
| Control de la TV en el iPad | Opción B (29 oct): panel fijo a la derecha en ventana ancha (≥ 1000 pt, ancho regular) con el inspector de SwiftUI; tarjeta en ventana angosta. Página de la decisión: claude.ai/artifact/386cRFMTfgRCvJvEU4tnFw |
| La Mac sin la consola | `Services(allowsOrbital: false)` en la Mac (`ThisDevice.talksToOrbital`): sin control, «En la TV» ni emparejar; Ajustes sin «Tu Orbital» ni «Voz y Siri» (`OrbitalOffTests`) |
| Pulido en horizontal | Ficha a 720 pt (`DS.TitleAction.readableWidth`); géneros adaptables (`DS.Poster.genreTileMin`); tamaño mínimo de ventana = iPhone SE (`WindowMetrics.minimum`) |
| Revisión general (29 oct, tarde) | Selectores segmentados a lo más `DS.Size.segmentedMax` (480 pt; antes de orilla a orilla en Buscar y Descargas); las cuadrículas «de dos en dos» (Top 10 completo, tus listas, Seguir viendo › Ver todo) pasan a columnas adaptables en ventana ancha (`DS.Poster.pairColumns`); «Próximos estrenos» con tope (`DS.Poster.airingMax`); ancho de lectura en las listas que faltaban (Descargas › temporadas, Ajustes › Cuentas, OneDrive, Mi media, Probar la velocidad); el video del iPad de pie abre a media pantalla (`DS.PlayerPanel.regularCenter`) y no pegado arriba con ~600 pt de negro; en la Mac los textos dicen «Haz clic» y «Mantén el clic» en vez de «Toca» y «Mantén presionado» (variación `mac` del catálogo, `scripts/ios_strings.py` › `MAC_TOUCH_ES`/`MAC_TOUCH_EN`) |
| Pasada pantalla por pantalla (4 nov) | iPad mini (A17 Pro) y iPad Pro 13" (simuladores «Orbital QA iPad mini» y «Orbital QA iPad 13», iOS 27), de pie y acostado, 27 pantallas cada uno (incluye las que llegaron después del 29 oct: Inicio nuevo, el mazo, Lo que ves, Colecciones, Tu año, Filtros, calificar, la consola). Arreglos: la portada de Inicio en el iPad mini de pie usaba la del iPhone (744 pt < el umbral de 800) y ocupaba casi toda la pantalla → «ancha» desde 700 pt y, de pie, menos apaisada (`DS.HomeHero.wideFrom`, `aspectWidePortrait`); la carta del mazo «¿Qué vemos hoy?» se estiraba a lo ancho y recortaba el póster → en mazo ancho no pasa de un póster y se centra (`DS.Match.cardAspectMin`, `wideDeck`); la pastilla de calificar cruzaba la pantalla → mismo tope que los avisos (`DS.Toast.maxWidth`). En el iPhone nada cambia. `IPadLayoutUITests/testLandscapeTour` cubre ahora las 27 pantallas |
| Pasada de pulido (10 nov) | Simulador «Orbital QA iPad» (iPadOS 27), 27 pantallas acostado más letra grande y modo oscuro; la Mac compila Debug y Release («Diseñada para iPad»). Arreglos: **la app se cerraba en el iPad al abrir el reproductor y tocar** (`sensoryFeedback` va por la vibración «con lugar» del iPad y truena en `LocationBasedFeedbackAdaptor`) → toda vibración pasa por `dsFeedback`, solo en el iPhone (`Platform/Haptics.swift`; `PlatformBoundaryTests.testHapticsGoThroughDSFeedback`); portada de Inicio a lo más 60 % del alto (`DS.HomeHero.maxHeightShare`, `aspectWideMax`); muro de Explorar sin cuña vacía (`DS.ParaTiB.coverColumns(forWidth:)`); mosaico con columnas de ~170 pt (`DS.Mosaic.wideColumn`); Guardado con los cuatro montones en fila y al ancho de lectura (`DS.SavedBoard.columns(forWidth:tiles:)`); «Día por día» y «Lo que ves» abren en hoy (`defaultScrollAnchor`); menú «Título» con ⌘↩, ⌘D y ⌥⌘V, y Esc / ⌘. cierra las hojas (`escapeCloses()` en `dsSheetContent` y las hojas a la medida; `IPadKeyboardUITests`); la ficha ancha con letra de accesibilidad usa 720 pt. **Límites que quedan:** Tab no mueve un foco visible entre botones (SwiftUI en iPadOS; `.focusable` tronaba en iOS 26.3), por eso todo va por la barra de menús; la tecla Esc que inyecta XCUITest no llega en el simulador de iPadOS 27 (la prueba usa ⌘., la misma acción); «Versión» deja espacio vacío abajo cuando tiene pocas filas; la Mac no se abrió a mano (la primera vez se abre desde Xcode) |
| Segunda pasada (10 nov, noche) | **iPad:** «Orbital QA iPad» 11" acostado en oscuro (27 pantallas) y de pie en claro con letra grande, «Orbital QA iPad mini» de pie en oscuro y «Orbital QA iPad 13» acostado en claro (15 pantallas cada uno), sin cierres. Arreglos: Guardado con las cinco pilas iguales (Historial con número, mismo ancho: `SavedStateTile` con `minWidth: 0`); «Versión» a la medida de su lista con tope en ventana ancha (`VersionSheetSizing`: el alto medido va en `presentationDetents` y `fittedFormSizing`, así iPadOS vuelve a medir cuando llega la lista; con `idealHeight` solo la tarjeta se quedaba en ~280 pt y cortaba la lista). La tarjeta de calificar (D2-A) se ve bien en el iPad, bajo «Seguir viendo»: no sale en la primera pantalla porque la portada ocupa hasta el 60 % del alto (así se decidió). **Tab:** iOS solo mueve el foco por botones con «Acceso total con teclado» prendido (documentación de `focusable(_:interactions:)`: los botones aceptan foco solo con la navegación con teclado del sistema); sin él, Tab no hace nada en iPadOS 27 y no truena (`IPadKeyboardUITests.testTabMovesVisibleFocus`). Hacer enfocables los pósters con `.focusable()` les quita la acción del botón y es lo que tronaba en 26.3: queda como decisión de diseño (la órbita en el foco, fila del registro de paridad). **Mac:** compila Debug y Release; Xcode no corre XCUITest ahí, así que el recorrido vive dentro de la app (`MacTests/MacTourTests.swift`, esquema `OrbitalMac`). No se pudo abrir: la sesión de la Mac estaba bloqueada y macOS deja la app de iPad suspendida antes de arrancar (RunningBoard «running-suspended-NotVisible»); abrirla con `open` sobre una envoltura (`Orbital.app/Wrapper/Orbital.app` + `WrappedBundle`) llega al mismo punto. Pantalla dividida del iPad: el simulador no deja cambiar el tamaño de la ventana desde una prueba; queda para la Mac (`MacTourTests` con ventana de 420 pt) o a mano |

### Instalar en el iPad y en la Mac

- **iPad:** en Xcode, `Orbital` → tu iPad → Run (como en el iPhone). Con `CURRENT_PROJECT_VERSION=$(git rev-list --count HEAD)` para que cada instalación tenga su número.
- **Los símbolos de cada instalación** (iPhone, iPad; desde el 11 nov 2026): al terminar de instalar, `ios/scripts/guardar-dsym.sh <…/Build/Products/Release-iphoneos>` copia los dSYM a `~/Library/Developer/Orbital-dSYMs/<número de compilación>/`. Sin ellos, un cierre que llega del aparato (.ips) solo trae direcciones; con ellos, `xcrun atos` dice en qué función pasó.
- **Recorrido de la Mac sin manos** (con la sesión desbloqueada): `cd ios/App && xcodegen && xcodebuild test -scheme OrbitalMac -destination 'platform=macOS,arch=arm64,variant=Designed for iPad' -derivedDataPath /tmp/dd-orbital-ipad -allowProvisioningUpdates`. Las capturas quedan en la carpeta temporal de la app (`MAC-TOUR folder` en la bitácora).
- **Mac (chip de Apple):** `cd ios/App && xcodegen && open Orbital.xcodeproj`, destino **My Mac (Designed for iPad)** → Run. La primera vez Xcode la instala y la abre; después queda en el Launchpad. Por terminal compila con
  `xcodebuild build -scheme Orbital -destination 'platform=macOS,arch=arm64,variant=Designed for iPad' -allowProvisioningUpdates`.

### Lo que encontró la revisión con capturas

- La medida de la ventana con `ignoresSafeArea` no traía la barra de estado: el control completo quedaba ~50 pt más bajo en iPhone con notch (corregido antes de subir).
- «¿Qué vemos?» salía cortada a ~70 pt en el iPad (su raíz se desplaza y se medía en «casi nada»).
- El reproductor del iPad siempre se creía en vertical (la clase vertical del iPad nunca es compacta) y enseñaba el modo iPod en horizontal.
- Descargas y Ajustes decían «iPhone» en el iPad.

## Riesgos abiertos

1. Decidir cómo se ve el control remoto en iPad (1.5): hoy está hecho alrededor de la altura del iPhone.
2. La matriz de pruebas crece: iPhone ×3 tamaños + iOS 27 + iPad + una pasada en Mac.
3. Si un día se quiere app de Mac de verdad, el camino es SwiftUI nativo de macOS (el motor ya lo soporta), no Catalyst.

## No verificado

ActivityKit y Live Activities en iPad y en la Mac con «Diseñada para iPad»; descargas de fondo y `BGContinuedProcessingTask`
en la Mac; ControlWidget en iPad.
