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

## Lo que quedó pendiente de la sesión anterior

- **La app instalada en la Mac es la 2615 de medición** (`-DMAC_DRIVE`; sus órdenes solo se activan con `-macDrive`). Hay que
  reinstalar una normal: la misma línea de `xcodebuild` sin `-DMAC_DRIVE`, un número mayor e
  `ios/scripts/instalar-en-mac.sh`.
- **Deslizar en la Mac por debajo de 5** («tirones» = ms atrasados por segundo, a 120 Hz). Fernando lo pidió el 27 nov: «todas
  te tienen que dar debajo de 5». Quedó interrumpido por TL1-B. Al volverse app de Mac al 100 % puede cambiar todo, así que
  conviene medirlo de nuevo ahí. Lo último medido (con Instruments grabando, que también atrasa):

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
