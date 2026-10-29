# Auditoría de arquitectura de la app de iPhone (29 oct 2026)

Revisión de `ios/` como la haría un desarrollador senior que recibe el proyecto para auditarlo y corregirlo: capas,
monolitos, modularidad, sistema de diseño y prácticas de Swift y SwiftUI. Tres rondas: encontrar, corregir y volver a correr.

## Qué estaba bien (y se conserva)

- **Tres capas limpias.** `OrbitalCore` (lógica portada de la consola, sin interfaz), `OrbitalModels` (modelos de vista
  con Observation, sin SwiftUI) y la app (SwiftUI). Ningún archivo del paquete importa SwiftUI ni UIKit: se prueba en Mac y Linux.
- **Sistema de diseño vigilado por pruebas.** `DesignTests` compara la paleta y los tokens con los de la TV
  (`design/tokens.json`, `palette.json`), prohíbe colores, tamaños y duraciones a mano en las pantallas y prohíbe estilos de
  control propios (HIG). `PlatformBoundaryTests` confina lo que depende del aparato a `Platform/`.
- **Prácticas modernas.** `@Observable` y Observation en vez de `ObservableObject`/Combine; concurrencia con `async/await`
  y `@MainActor` en todos los modelos; textos 100 % en el catálogo de traducción (`ios_strings.py --check`); casi sin
  `try!`/`as!` (solo expresiones regulares fijas); sin `print` en producción.

## Lo que se encontró y lo que se hizo

| # | Hallazgo | Por qué importa | Qué se hizo |
|---|---|---|---|
| 1 | **`AppEnvironment` era un «objeto dios»** (902 líneas, ~10 responsabilidades: armar los servicios, la cola de avisos, Infuse, enlaces entrantes, importar videos, apariencia, pasar a la TV, la ruleta de Los Simpson, acciones sobre un título, el `AppDelegate` y `AppUI` en el mismo archivo) | Todo cambio pasa por el mismo archivo; nada de eso se podía probar sin levantar la app entera | Se partió por responsabilidad: `App/AppComposition.swift` (raíz de composición), `App/AppDelegate.swift`, `App/AppUI.swift`, `AppEnvironment+Infuse.swift`, `+Orbital.swift` (la TV), `+Titles.swift` (ver, guardar, quitar, marcar, descargar). `AppEnvironment.swift` queda en 393 líneas: estado, arranque y enlaces entrantes |
| 2 | **La cola de avisos («toasts») vivía dentro del objeto dios, sin pruebas** | Reglas finas (un «Deshacer» no se pisa, tope de cola, el siguiente sale al irse el actual) sin una sola prueba | `OrbitalModels/NoticeCenter.swift` (`Notice`, `NoticeTone`, `NoticeAction`) con `NoticeCenterTests` (6 pruebas). `AppEnvironment.notify` solo traduce y delega; la raíz pinta `env.notices.current` |
| 3 | **«Un Simpson al azar» era lógica de negocio dentro de `AppEnvironment`** (elegir episodio, tira de la ruleta, prefetch, temporadas) | Imposible de probar; acoplada a `ImagePipeline`, `Strings` y tokens | `OrbitalModels/SimpsonsModel.swift` con las piezas del iPhone enchufadas por cierres (`warmImages`, `onError`, `services.episodeLabel`) y `SimpsonsModelTests` (7 pruebas con un Cinemeta fingido) |
| 4 | **Piezas del catálogo (`Design/`) leían el estado global** (`AppEnvironment.shared` en `Companion`, `Collections`, `ListControls`, `SettingsParts`, `SimpsonsRoulette`) | Una pieza del sistema de diseño debe recibir datos y avisar eventos; si lee el estado de la app no se previsualiza ni se prueba sola, y el widget no la puede usar | El idioma llega por `@Environment(\.locale)`; `SortableGrid` recibe `CollectionsModel`; `genreName` recibe el idioma; `AppMark`, `SimpsonsSeasonsSection` y `SimpsonsRoulette` (que sí son pantallas) se movieron a `Screens/`. **Nueva prueba `DesignBoundaryTests`**: `Design/` no puede mencionar `AppEnvironment` ni `Services` (hoy: 0 usos) |
| 5 | **`Components.swift`: 52 tipos en un archivo de 1 300 líneas** | Un catálogo sí, pero un solo archivo no: imposible de navegar y de revisar en un diff | Se partió por tema, sin tocar código: `Badges`, `RemoteImage`, `Posters`, `Art`, `Buttons`, `Feedback`, `Filters`, `PlayerIndicators`, `Backdrop`, `Storage`, `Labels` (el más grande, 215 líneas) |
| 6 | **`PlayerScreen` tenía 91 `@State` en una sola vista** (repartida en 6 archivos con extensiones) | La vista era la máquina de estados del reproductor; cada `@State` es un motivo de redibujo y una variable global de facto | Primer paso: el estado del arrastre (eje, brillo, volumen, buscar, 2×: 18 variables) ahora vive en `Screens/PlayerDragState.swift` (`@Observable`), con `@State var drag` en la vista. Quedan 74; el patrón está marcado para los grupos que siguen (candado, panel de subtítulos, zoom, avisos) |
| 7 | **Un modelo compartido como `static` dentro de una vista** (`ListsView.sharedCollections`, construido con `AppEnvironment.shared`) | Un singleton escondido en una pantalla; `RootView` y `ListControls` lo buscaban ahí | Lo posee `AppEnvironment` (`env.collections`, perezoso), como los demás modelos de toda la app |
| 8 | **`try! AetherEngine()`** al abrir el reproductor | Si el motor no arranca (una versión nueva del paquete, memoria), la app truena al tocar «Ver» | `AetherEnginePlayer.init?()`; si falla, la fábrica cae a `AVPlayer` |
| 9 | **`DispatchQueue.main` en vistas** (`HomeView`, `Collections`) | Mezcla de GCD con el modelo de concurrencia de Swift en código `@MainActor` | `Task { @MainActor in … }` y `Task.sleep` con el token de duración |
| 10 | **La parte de disco de «abrir un video que te pasaron»** (copiar, mover desde `Inbox`, excluir del respaldo, borrar a los 3 días) estaba en `AppEnvironment` | Lógica de archivos fuera de `Platform/` | `Platform/ImportedVideos.swift` (`store`, `prune`); `AppEnvironment.openFile` solo reconoce y reproduce |
| 11 | **Nada impedía que volvieran los monolitos** | Las pruebas de arquitectura existentes vigilaban tokens y aparato, no el tamaño | **Nueva prueba `FileBudgetTests`**: ningún archivo de Swift pasa de 600 líneas; los que hoy lo pasan están en una lista con su tamaño y solo pueden encogerse (al bajar de 600 la prueba pide quitarlos de la lista) |

### Cifras

| | Antes | Después |
|---|---|---|
| `AppEnvironment.swift` | 902 líneas | 393 (+ 6 archivos por tema, el mayor de 188) |
| `Components.swift` | 1 311 líneas, 52 tipos | 11 archivos, el mayor de 215 líneas |
| `@State` en `PlayerScreen` | 91 | 74 (18 en `PlayerDragState`) |
| Piezas de `Design/` que leen `AppEnvironment` | 5 archivos, 12 usos | 0 (y una prueba lo impide) |
| `DispatchQueue.main` fuera de `Platform/` | 2 | 0 |
| `try!` en la app | 3 | 2 (expresiones regulares fijas) |
| Pruebas nuevas en el paquete | — | 15 (avisos 6, Simpson 7, dos guardias de arquitectura); 347 en total, todas en verde |

## Segunda pasada (misma fecha): las recomendaciones, hechas

| # | Recomendación | Qué se hizo |
|---|---|---|
| 1 | `PlayerModel.swift` (1 634 líneas) | «Pistas» y «versiones de subtítulos» salen a `PlayerModel+Tracks.swift` (205) y `PlayerModel+Subtitles.swift` (212): el estado guardado sigue en la clase (una extensión no puede tener propiedades), lo que se hace con él vive aparte. Lo que esas extensiones tocan pasó de `private` a interno del módulo (no público). `PlayerModel.swift` queda en 1 267. El paso siguiente, cuando haga falta, es un colaborador con su propia prueba |
| 2 | Agrupar el estado de `PlayerScreen` | Cuatro grupos más con el patrón de `PlayerDragState`: `PlayerLockState` (candado, 7), `PlayerZoomState` (encuadre, 8), `PlayerDockState` (panel de abajo, 13) y `PlayerNoticeState` (avisos, 7). `PlayerScreen` pasa de 74 a 43 `@State`; los que quedan son de la vista misma (controles visibles, tareas, tamaños) |
| 3 | `Screens/Shared.swift` | Partido: `Design/Rail.swift` (`Rail`, `TitleLink`, el reflejo: piezas puras), `Screens/TitleFacts.swift` (los datos en palabras, con el idioma explícito: ya no leen `AppEnvironment.shared`) y `Screens/TVCards.swift` (las dos tarjetas de la TV). `Shared.swift` queda con 20 líneas |
| 4 | `AppEnvironment+Titles` como caso de uso | `OrbitalModels/TitleActions.swift`: por dónde empieza una serie, lista por omisión, guardar y quitar, favoritos, marcar como vista y el detalle de una descarga, con `TitleActionsTests` (6). `AppEnvironment+Titles.swift` (132 líneas) solo pone avisos, «Deshacer» y abre el reproductor |
| 5 | Modo Swift 6 en la app | `SWIFT_STRICT_CONCURRENCY: complete` en `project.yml` (modo 5 todavía): una compilación completa enseña 127 avisos distintos, de ellos 33 serían errores en Swift 6 (conformancias `Equatable`/`VideoPlayerEngine` que cruzan al hilo principal, `NSCache` globales, cierres `sending`, capturas no `Sendable`) y el resto son APIs que iOS 26 dejó en desuso (`UIScreen.main`, `Text +`). Esa es la lista para subir a Swift 6 |
| 6 | `project.yml` | `bundleIdPrefix` ya no es la plantilla `com.example` (cada target fija su identificador). `NSAllowsArbitraryLoads` se queda: no se conocen de antemano los dominios de los complementos |
| 7 | Pruebas sin SwiftUI | Lo que bajó al paquete en estas dos pasadas trae 21 pruebas nuevas (avisos, Simpson, acciones sobre un título, dos guardias) |

### Lo que sigue (si se quiere seguir)

1. Convertir las extensiones de `PlayerModel` en colaboradores (`SubtitleVersions`, `TrackSelection`) con su estado y su prueba.
2. Atender los 33 avisos de aislamiento y luego poner `SWIFT_VERSION: "6.0"` en la app.
3. Los archivos que siguen en la lista de `FileBudgetTests` (13): `PlayerPanel.swift` (1 223), `Tokens.swift` (1 014), `ParaTiView.swift` (936), `Demo.swift` (854), `TitleView.swift` (813)…

## Cómo se verificó

- `xcodebuild build` (simulador, Xcode 26) en verde tras cada ronda.
- `swift test` del paquete: 351 pruebas tras la segunda pasada, 0 fallas (incluye `DesignTests`, `PlatformBoundaryTests` y las dos guardias nuevas).
- Ojo: mientras corría esta auditoría otra sesión editaba el mismo checkout (`PlayerModel.swift`, `Tokens.swift`, `TitleView.swift`, `ArtFit`, la web de la TV). Esos cambios no son de esta auditoría y no van en su commit.
- No se instaló en un simulador ni en el iPhone: los dos simuladores encendidos los estaban usando otras sesiones y los
  cambios son de estructura (mismo código, otro lugar), no de comportamiento. Para verlo: `-demo -demo-title series:tt0386676
  -demo-open play -demo-gesture brightness` (el estado de gestos extraído) y `-demo -demo-open simpsons` (la ruleta con `SimpsonsModel`).
