# Orbital como app de Mac de verdad: traspaso (27 nov 2026)

## La decisión

Fernando eligió **TL1-B** (Canvas https://claude.ai/artifact/J4ASgkoWNVC9QwSsGxBwoz), el 27 nov 2026. En sus palabras: «Vamos
a volver la app de Mac de verdad».

- **El problema:** en la Mac la letra «se ve como cruda». La letra ya es la del iPhone (SF Pro, `DS.styled`). Lo que la
  ensucia es que Orbital entra a la Mac como app de iPad («Designed for iPad»), y macOS dibuja esas apps al 77 %. Cada letra
  cae entre los puntos de la pantalla y se ve un poco borrosa y delgada.
- **El arreglo:** solo una app de Mac de verdad, Mac Catalyst con «Optimize Interface for Mac» (idioma `.mac`), se dibuja al
  100 %.

El plan acordado tiene dos pasos:

1. **Prueba barata.** Una versión de Mac de verdad solo con las pantallas, sin el reproductor AetherEngine. Se pone su letra
   lado a lado con la de hoy, en el mismo tamaño en pantalla. Si Fernando no ve la diferencia, se para ahí.
2. **Si le convence:** compilar el motor de video para Mac Catalyst, revisar los tamaños de la Mac pantalla por pantalla y
   probar el reproductor.

## Lo que ya se averiguó

- **El motor de video:** solo `ios/App/Sources/Platform/AetherEnginePlayer.swift` importa AetherEngine, y todo va tras la
  bandera `AETHER_ENGINE` (`project.yml` → `SWIFT_ACTIVE_COMPILATION_CONDITIONS`). Sin el paquete ni la bandera, la app usa
  AVPlayer y compila (comentario en `project.yml`). Para el paso 1 basta con quitar el paquete y la bandera.
- **Las bibliotecas no traen Catalyst.** Las xcframeworks de AetherEngine (FFmpegBuild `AetherLib*`, `Dovi`, `TrueHD`) traen
  ios, simulador, macos, tvos y xros, pero no `ios-arm64_x86_64-maccatalyst`. El paso 2 necesita compilarlas para Catalyst
  (forks o pedirlo upstream, superuser404notfound).
- **Qué se cambia en `project.yml`:** `SUPPORTS_MACCATALYST: YES` y `TARGETED_DEVICE_FAMILY` con `6` (idioma Mac).
  - Para la prueba, un bundle id aparte, para no pisar la app instalada.
  - Firma: equipo B7KRCF776Z, con cuenta de paga.
  - El widget (`OrbitalWidgets`) y los entitlements pueden estorbar en la prueba: quitarlos ahí si hace falta.
- **Todo lo «de Mac» se decide hoy con `ProcessInfo.processInfo.isiOSAppOnMac`**, en 14 archivos de `ios/App/Sources`, y
  con `ThisDevice.isMac` (`Platform/DeviceInfo.swift:80`). En Catalyst `isiOSAppOnMac` es falso: hay que sumar
  `isMacCatalystApp` o `targetEnvironment(macCatalyst)`.
- **Los tamaños de la Mac están en puntos de iPad pensados para el 77 %.**
  - `DS.Mac.typeScale = 1.25` en `Design/Tokens+Mac.swift`; `DS.Mac.sized()`, `styleSizes`, pósters y márgenes.
  - Al 100 % todo saldría ~30 % más grande. Para que se vea del mismo tamaño, cada medida de la Mac va ×0.77 (por ejemplo
    `typeScale` ≈ 0.96).
  - En el paso 1 basta con la letra, para comparar. El ajuste completo es el paso 2.
- **Datos para la prueba:** con otro bundle id no hay sesión de Trakt ni biblioteca. Hay banderas de demostración
  (`-demo-…`, ver `rg '"-demo' ios/App/Sources`) y `DeviceInfo.macLookForDemo`. Hay que elegir una pantalla con datos que
  se pueda comparar.
- **Cómo comparar:** `screencapture -l <ventana>` no tiene permiso de grabar pantalla desde la terminal. Sirven las capturas
  de computer-use (`app_screenshot` / `app_zoom`) o `MacDrive.snap` (solo en compilaciones con `-DMAC_DRIVE`).

## Reglas que siguen valiendo

- Compilaciones: máximo 2 a la vez en la Mac (`pgrep -x xcodebuild`), cada copia con su `-derivedDataPath /tmp/dd-…`.
- `ios/App/Secrets.xcconfig` no va a git: se copia de `/Users/fer.iracheta/code/orbital/ios/App/Secrets.xcconfig` y se
  borra al terminar.
- `xcodegen generate` se corre desde `ios/App`. Si al traer `main` llega un archivo nuevo, hay que regenerar.
- Decisiones visibles: en Canvas con códigos (regla 12). El informe se da en tres estados (comprobado con clics / hecho sin
  comprobar / no hecho).
- No reproducir videos en la cuenta real de la Mac (marca vistos en Trakt).


## Paso 1 hecho (27 nov 2026, noche)

- **La prueba compila y abre** como app de Mac de verdad (Mac Catalyst, idioma Mac, al 100 %), sin AetherEngine, con bundle id
  `mx.iracheta.orbital.macprueba` y firma local (ad hoc). Quedó instalada como **«Orbital Mac (prueba)»** en `/Applications`:
  abre sola en modo demostración (no toca la cuenta). Si Fernando elige TL2-B, se borra.
- **Cómo se armó** (para rehacerla o para el paso 2):
  - `prueba-paso1-project.catalyst.yml`: copia de `project.yml` con `SUPPORTS_MACCATALYST`, familia `1,2,6`, sin AetherEngine,
    sin widgets, sin entitlements y sin `LSSupportsOpeningDocumentsInPlace` (en macOS no se permite en `NO`). Se copia a
    `ios/App/` y se corre `xcodegen generate --spec project.catalyst.yml` (crea `OrbitalCatalyst.xcodeproj`, esquema `Orbital`).
  - `prueba-paso1.patch` (`git apply`): lo que se cambió en el código, solo para la prueba:
    - `isiOSAppOnMac` → `isiOSAppOnMac || isMacCatalystApp` en los 14 archivos (en el paso 2 conviene un solo ayudante).
    - `DS.Mac.typeScale` = 1.25 × 0.77 solo en Catalyst. Pósters, márgenes y botones **no** se ajustaron (salen ~30 % grandes).
    - Lo que no existe en Mac Catalyst, tapado con `#if !targetEnvironment(macCatalyst)`: ActivityKit (actividades en vivo de
      descargas y de la TV), `BGContinuedProcessingTask` (DownloadContinuation) y `DataScannerViewController` (QRScanner).
    - `Demo.arguments`: con el bundle id de la prueba arranca con `-demo` (para abrirla con doble clic).
  - Compilar: `xcodebuild build -project OrbitalCatalyst.xcodeproj -scheme Orbital -configuration Debug -destination
    'platform=macOS,variant=Mac Catalyst' -derivedDataPath /tmp/dd-orbital-catalyst` (con `'OTHER_SWIFT_FLAGS=$(inherited)
    -DMAC_DRIVE'` si se quiere `-macDrive`).
- **Comparación:** Canvas https://claude.ai/artifact/TEZmW6ThthTXRSKtZVUr8o (códigos TL2-A seguir al paso 2, TL2-B parar,
  TL2-C verlas en persona primero; recomendada TL2-C). Es una **simulación** con la misma letra y los mismos números: la Mac estaba
  bloqueada (de madrugada), `screencapture` no tiene permiso y computer-use se negó solo. Con la pantalla bloqueada la app no
  dibuja, así que tampoco sirvió `MacDrive.snap`. El monitor de Fernando es el ultrawide MG801 de 3440 × 1440 **sin Retina**:
  ahí el 77 % se nota más que en una pantalla Retina.
- **Falta:** la elección de Fernando (TL2). Si es TL2-A: compilar las xcframeworks de AetherEngine para Catalyst, un ayudante
  único para «es la Mac», `DS.Mac` ×0.77 completo y revisar pantalla por pantalla.
- **La Orbital normal ya está reinstalada** en la Mac: 2638, sin `-DMAC_DRIVE` (Release de aparato, `instalar-en-mac.sh`).

## Lo que quedó pendiente de la sesión anterior

- ~~La app instalada en la Mac es la 2615 de medición~~: hecho, la normal 2638 quedó instalada (27 nov).
- **Deslizar en la Mac por debajo de 5** («tirones» = ms atrasados por segundo, a 120 Hz). Fernando lo pidió el 27 nov: «todas
  te tienen que dar debajo de 5». Quedó interrumpido por TL1-B. Al volverse app de Mac al 100 % puede cambiar todo, así que
  conviene medirlo de nuevo ahí. **Sigue pendiente** (27 nov): medirlo en la app de Mac de verdad (la prueba compilada con
  `-DMAC_DRIVE`, ver «Paso 1 hecho») si Fernando elige TL2-A, o en la de iPad si elige TL2-B. Lo último medido (con Instruments grabando, que también atrasa):

  | Pantalla | Bajando | Subiendo |
  |---|---|---|
  | Inicio | 21–41 | 8–12 |
  | Explorar | ~169 | sin dato confiable |

  - Herramientas: `ios/scripts/medir-mac-sin-manos.sh` y `ios/scripts/mac-deslizar.txt`. La orden `scroll` de `MacDrive`
    deja «frames … tirones …».
  - Para medir sin Instruments: abrir la app con `--args -macDrive "<órdenes separadas por |>"`, mandar
    `notifyutil -p mx.iracheta.orbital.go` y leer
    `log show --predicate 'subsystem == "mx.iracheta.orbital" AND category == "drive"'`.
  - Sospecha siguiente en Explorar: `ListsView` con `.scrollPosition($position)` y `.scrollTargetLayout()` reevalúa todo el
    cuerpo al cambiar la fila de arriba. La idea es pasar ese estado a una vista envoltorio chica.
  - Detalle en `docs/ios-interfaz.md` § «Deslizar sin tirones en la Mac».
