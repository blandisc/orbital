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

## Paso 2 (TL2-A, Fernando, 27 nov 2026: «Vamos en TL2A»)

### Cómo se arma la app de Mac de verdad (ya no es un parche aparte)

1. **Las bibliotecas del motor de video:** `python3 ios/scripts/catalyst_bibliotecas.py`. Copia FFmpegBuild, LibDovi y LibTrueHD
   (de los checkouts de SwiftPM de una compilación normal) a `ios/Vendor/catalyst/` (no va a git) y le agrega a cada
   xcframework la rebanada `ios-arm64-maccatalyst`: la de macOS arm64, marcada como Mac Catalyst. El código de máquina es el
   mismo; solo cambia la etiqueta de plataforma. A los frameworks (FFmpeg) se les cambia con `vtool` y se firman de nuevo; a los
   objetos de las bibliotecas estáticas (Dovi y TrueHD, de Rust) se les cambia el campo de plataforma en su lugar, porque
   `vtool` no cabe en sus comandos de carga. Se corre otra vez cada que suba AetherEngine.
2. **El proyecto:** `python3 ios/scripts/catalyst_proyecto.py` escribe `ios/App/project.catalyst.yml` desde `project.yml` (no va
   a git; se regenera) y `xcodegen generate --spec project.catalyst.yml` crea `OrbitalCatalyst.xcodeproj`. Si alguien cambia
   una de las líneas que toca, el script se detiene y dice cuál.
3. **El código ya compila igual para las dos:**
   - «¿Es la Mac?» se pregunta en un solo lugar: `ProcessInfo.onMac` (las dos formas) y `ProcessInfo.macNative` (solo la de
     verdad), en `Design/Tokens+Mac.swift`. Lo cuida `DesignRulesTests.testTheMacIsAskedInOnePlace`.
   - Lo que no existe en Mac Catalyst va tras `#if !targetEnvironment(macCatalyst)`: las actividades en vivo (descargas y
     «Viendo en la TV»), la descarga continua con la app cerrada y el lector de QR (en la Mac dice que no puede, como sin cámara).
   - **El App Group solo por `WidgetStore`** (`directory` y `defaults`), que en Mac Catalyst devuelven nada. En macOS el
     contenedor `group.mx.iracheta.orbital` existe igual (es el de la Orbital de iPad instalada) y abrirlo dispara el aviso
     «quiere acceder a datos de otras apps»: la app se quedaba congelada al abrir, con su ventana vacía y sin que se viera el
     aviso (27 nov 2026). Lo cuida la misma prueba.
4. **Tamaños:** `DS.Mac.native` (0.77 en la de verdad, 1 en la otra) multiplica lo que en `DS.Mac` creció para compensar el
   77 %: `typeScale`, `railWidth`, la búsqueda, Ajustes, los anchos de ventana donde cambia la barra, etc. Lo genérico (los
   espacios `DS.Space`, los radios, los íconos) todavía no: sale ~30 % más grande que hoy. Se decide al revisar pantalla por pantalla.
5. **Compilar:** `xcodebuild build -project OrbitalCatalyst.xcodeproj -scheme Orbital -configuration Debug -destination
   'platform=macOS,variant=Mac Catalyst' -derivedDataPath /tmp/dd-orbital-catalyst 'OTHER_SWIFT_FLAGS=$(inherited) -DMAC_DRIVE'`.
   Abrir: `open -n …/Debug-maccatalyst/Orbital.app --args -demo -demo-no-idle -demo-mute -macDrive "wait 8|snap inicio"`. Las
   capturas quedan en `$TMPDIR/macsnap-*.png`. Para el reproductor: `-demo-open play` y `-macDrive "wait 6|title movie tt1160419|…"`
   (en la Mac la ficha se abre por `title`, no por `-demo-title`). Con la pantalla bloqueada la app no dibuja.

### Estado (27 nov 2026, mañana)

- **Comprobado** (registro y capturas de la propia app): compila para Mac Catalyst con AetherEngine; carga las 9 bibliotecas de
  FFmpeg; dibuja Inicio, Explorar y Biblioteca al 100 %; **el reproductor reproduce** los videos de demostración (`motor: playing`,
  cambia de versión cuando una falla). La compilación de iPhone sigue en verde.
- **Arreglado al revisar** (capturas de la propia app y el recorrido `tour` en cinco tamaños, `$TMPDIR/mac-tour/`):
  - Los espacios y las esquinas (`DS.Space`, `DS.Radius`) y el logo de la barra (`markScale`, `heroScale`) también van
    ×`native`: con ellos a 100 % la cápsula de pestañas se montaba sobre el logo.
  - Los puntitos de la portada (con puntero van en su renglón, bajo la portada) quedaban tapados por «Lo que tienes a
    medias», que sube sobre la portada. Ahora sube solo hasta quedar bajo ellos (`heroLift`). Pasaba también en el iPad ancho y
    en la Mac de hoy.
- **Visto, sin arreglar todavía:**
  - En 1024 de ancho, la cápsula de pestañas al centro tapa «Buscar» (junto al logo): falta subir `centeredTabsFrom` en la de verdad.
  - Biblioteca sale solo con sus dos puertas en la demostración (hay que ver si es la demostración o la Mac).
  - La ventana arranca de 1024 × 768.
- **Instalada para que Fernando la vea:** `/Applications/Orbital Mac (prueba).app` (Debug, ad hoc), abre sola en modo
  demostración por su identificador (`Demo.macTrial`). La de siempre sigue siendo la 2638 («Diseñada para iPad»).
- **Falta:**
  - Revisar pantalla por pantalla (Inicio, Explorar, Biblioteca, Buscar, ficha, reproductor, Ajustes) y decidir lo genérico ×0.77.
  - Firmar con el equipo (hoy es ad hoc): sin `application-identifier` no hay descargas en segundo plano
    (`Background URLSession adopters are required to have com.apple.application-identifier`) ni Llavero compartido. Crear el App
    ID de Mac Catalyst en la cuenta de Apple necesita el OK de Fernando.
  - Que Fernando la vea en persona (la de verdad junto a la instalada) antes de cambiar la que se instala.
  - Medir el deslizar (abajo de 5) en esta app.
