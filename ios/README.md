# Orbital para iPhone

App compañera de Orbital para ver **películas y series** en el iPhone con tus complementos de Stremio y Real-Debrid.
Uso personal: no va a la App Store (la regla 5.2.3 lo impide); se instala con tu cuenta de desarrollador o TestFlight interno.

- **Stremio es la cuenta eje**: lo que ves aquí (avance, visto, Mi lista) se guarda en tu cuenta y aparece en Orbital, y al revés.
- **Trakt** cuelga de eso: tu watchlist, tus listas y recomendaciones en «Para ti», y el *scrobble* de lo que ves.
- **Reproductor propio** (AetherEngine, con AVPlayer de respaldo) y **«Abrir en Infuse»** para los archivos difíciles.
- **Descargas** con enlaces de Real-Debrid, para ver sin conexión.
- Español e inglés (interfaz y fichas).
- Solo fuentes con enlace http(s) (Real-Debrid): las de torrent sin Real-Debrid (`infoHash`) no se ofrecen.

## Componentes nativos y Human Interface Guidelines

La app usa los controles de Apple y no inventa los suyos (se compila con **Xcode 26 / iOS 26**, así que el aspecto *Liquid Glass* llega solo):

| Qué | Cómo |
|---|---|
| Barra de pestañas de abajo | `TabView` con `Tab` (vidrio nativo; se encoge al deslizar con `.tabBarMinimizeBehavior`) |
| Navegación, títulos grandes, buscar | `NavigationStack`, `.navigationTitle`, `.searchable` |
| Selectores (Mosaico · Listas, Ver · Descargar, Series · Películas) | `Picker` con `.segmented` |
| Botones | `.glassProminent`, `.glass`, `.bordered(Prominent)` con `.buttonBorderShape` y `.controlSize` |
| Hojas (fuentes, audio y subtítulos) | `.sheet` con `presentationDetents` y vidrio por omisión |
| Ajustes, descargas | `Form` y `List` con `swipeActions`, `Toggle`, `Picker` |
| Menús, avisos | `contextMenu`, `confirmationDialog`, `alert` |
| Texto | estilos de texto del sistema (Dynamic Type), SF Symbols, `accessibilityLabel` en cada botón de ícono |
| Respuesta táctil | `sensoryFeedback` al cambiar un selector o la watchlist |

Una prueba (`DesignTests`) impide definir estilos de botón o de selector propios y poner fondos de hoja propios.
**Excepción:** la app es siempre oscura (`.preferredColorScheme(.dark)`), como las apps de video (Infuse, Netflix): la paleta de Orbital es de grafito.
Pendiente de revisar en un iPhone con iOS 26: el reproductor (controles sobre el video) y el mosaico, que son diseño propio por necesidad.

### Para ti › Listas: un feed de estantes (CEN-50)

Listas se arma con las mismas listas que la consola (`/api/foryou`), sin calcular nada nuevo en el iPhone:
un destacado «Para ti hoy», el selector Series · Películas (pegado arriba al desplazar; solo cambia los estantes con `split`)
y un estante por lista. El orden y la fusión de «Lo tuyo» viven en `OrbitalModels/ShelfPlan.swift` (`ShelfPlanner`, con pruebas).

| Pieza del iPhone (`Design/`) | Equivalente en la consola | Qué es |
|---|---|---|
| `Shelf` (`Shelf.swift`) | `shelf` | Encabezado tocable (logo de plataforma con `DSPlatformLogo` o ícono de la fuente, título, dato secundario, chevron → `ListGridView`) y tira horizontal con `scrollTargetBehavior(.viewAligned)`; esqueletos (`ShelfSkeleton`) mientras carga |
| `RankedPosterCard` (`Shelf.swift`) | `card__rank` | Top 10 estilo Netflix (solo `chart:*`): cifra enorme en gris (`DS.ink500`, tamaño `DS.Size.rankNumber`) detrás del póster. En `jw:*` el puesto discreto es `DSRankBadge` |
| `FeatureTile` = `HeroCard` (`Components.swift`) | `tiles` / destacado | Arte a sangre, logo del título (con caída al nombre), etiqueta de razón, «Ver» y «Más». Es la misma pieza que el destacado de Inicio; `logo` y `detailText` son opcionales |

Orden de estantes: Lo tuyo (watchlist + «Tus series» fusionados) → Recomendadas y listas propias de Trakt → Top 10 en Netflix →
plataformas `jw:*` (el respaldo de TMDB solo si no hay `jw:` ni Top 10 de esa marca) → En tendencia / Lo más popular → catálogos de
complementos. «Seguir viendo» y «Mi lista» de Stremio viven en Inicio. Un estante vacío o que falla no se pinta; sin ninguna fuente:
destacado + «Lo más popular en Stremio» + un botón «Conecta Trakt o tu Orbital».

Cada póster: tocar abre la ficha (háptica suave); mantener abre el menú (Ver, Mi lista, Descargar, En la TV, No me interesa).
En modo demostración, `-demo-console` simula un overview con varios estantes y `-demo-mode lists` abre en Listas.

### Gestos del reproductor (como Infuse)

Además de tocar (controles), doble tocar por mitades (±10 s) y pellizcar (llenar pantalla), `PlayerScreen` decide
el eje del arrastre en los primeros `DesignTokens.Gesture.axisThreshold` puntos (así no choca con el toque ni con
el doble toque):

| Gesto | Qué hace | Indicador |
|---|---|---|
| Arrastrar vertical, mitad izquierda | Brillo de la pantalla (`UIScreen.main.brightness`; se restaura al salir) | Ícono `sun.max` + barra, sobre vidrio |
| Arrastrar vertical, mitad derecha | Volumen del sistema (`MPVolumeView` oculto, sin el HUD nativo) | Ícono `speaker.wave.2` + barra, sobre vidrio |
| Arrastrar horizontal, cualquier zona | Buscar: salta al soltar (no en cada movimiento). Ancho completo = 10 % de la duración o 3 min, lo que sea menor | Burbuja con el tiempo destino y la diferencia («+1:20») |
| Mantener el dedo ≥ 0,4 s | 2× mientras se mantiene; vuelve a la velocidad previa al soltar; vibra al entrar | Píldora «2×» arriba al centro |

La aritmética (eje dominante, segundos por punto, brillo/volumen 0…1) vive en `PlayerGestures.swift`
(`OrbitalModels`, sin UIKit) y se prueba en `OrbitalModelsTests/PlayerGesturesTests.swift`. En modo demostración,
`-demo-gesture brightness|volume|seek|fastforward` simula el gesto a medio camino sin tocar la pantalla, para
capturarlo en el simulador.

## Widgets

Dos cosas viven en la extensión `OrbitalWidgets` (`ios/App/Widgets`):

- **Actividad en vivo de las descargas** (pantalla bloqueada y Dynamic Island).
- **«Lo siguiente para ti»** (`NextUpWidget`): pequeño, mediano y de bloqueo (rectangular). Enseña hasta 3 títulos de «Seguir viendo».
  Tocar uno abre `orbital-ios://play?kind=&id=&video=` (el reproductor, donde ibas) o, sin episodio conocido, `orbital-ios://title?kind=&id=` (la ficha).

**Datos.** El widget nunca llama a la red. La app escribe un `WidgetSnapshot` (`OrbitalCore`, `Codable`) en el App Group
`group.mx.iracheta.orbital` (carpeta `Widget/`: `snapshot.json` y un JPEG de máx. 300 px por título) cada vez que `HomeModel.refresh()` termina,
al quitar algo de «Seguir viendo» y al cargar «Para ti» (`Services.publishWidget`), y llama a `WidgetCenter.reloadTimelines`. `WidgetPublisher`
baja y reduce los pósters (no repite los que no cambiaron) y calcula el tono del arte (mismo recipe que el fondo de las pantallas).
La línea de tiempo es una sola entrada con `.after(6 h)` de respaldo. Los textos van ya en el idioma de la app dentro del snapshot.
Una compilación sin firmar no tiene App Group: el widget se ve vacío (en el simulador hay que compilar con firma ad hoc, no `CODE_SIGNING_ALLOWED=NO`).

**Próximo estreno.** `WidgetSnapshot.upcoming` (opcional) lleva los 2 estrenos más cercanos de «Próximos estrenos» (Trakt, `ForYou.calendar()`);
se llena desde Inicio y desde Para ti (fuente iPhone; con la consola como fuente no hay estrenos en el teléfono). Cuando hay,
el widget mediano los enseña como «Próximo estreno» («T3 E4 · Mañana») en el segundo renglón.

**Verlo.** `-demo` escribe un snapshot de ejemplo con pósters reales (`-demo-widget empty` lo deja vacío, `-demo-widget live` usa el de Inicio).
Agrega el widget desde la pantalla de inicio del simulador; también hay `#Preview` (`NextUpPreviews.swift`).
Los tokens del widget salen de `DesignTokens` (`DesignTokens.Widget`) y `DesignTests` también revisa `ios/App/Widgets`.

## Estructura

```
ios/
  OrbitalCore/            paquete de Swift (sin interfaz). Se prueba con `swift test`, en Mac o Linux.
    Sources/OrbitalCore     la lógica portada de Orbital (Python): Stremio, complementos, fuentes, Cinemeta,
                            TMDB, Trakt, reproducción (avance, cola sin conexión), descargas, Infuse, ajustes
    Sources/OrbitalModels   modelos de vista (inicio, ficha, reproductor, Para ti…): sin SwiftUI, también se prueban
  App/                    la app (SwiftUI). Se genera con XcodeGen (project.yml)
    Sources/Design          sistema de diseño: tokens y piezas (los colores salen de palette.json de Orbital)
    Sources/Screens         pantallas
    Sources/Platform        descargas en segundo plano, motores de video, red, disco
    Resources               Localizable.xcstrings (es/en), iconos
scripts/ios_golden.py     valores de referencia que generan las funciones de Python de Orbital (tests/fixtures/ios)
scripts/ios_strings.py    genera y comprueba el catálogo de textos
```

## Probar

### Modo demostración (simulador, sin tu cuenta)

Solo en Debug. Arranca la app con `-demo`: una cuenta de Stremio falsa con biblioteca, un complemento con videos de prueba
públicos y Cinemeta de verdad. Nada toca tu Keychain ni tus ajustes. Para abrir una pantalla directo:

| Argumento | Qué abre |
|---|---|
| `-demo-tab 1` | la pestaña (0 Inicio, 1 Para ti, 2 Ver, 3 Descargas) |
| `-demo-title series:tt0386676` | una ficha |
| `-demo-open settings` · `sources` · `play` · `download` | Ajustes, la hoja de fuentes, el reproductor o una descarga (sobre la ficha) |
| `-demo-search dune` | una búsqueda en Ver |
| `-demo-mode lists` | en Para ti, abre en Listas (con `-demo-console`, el feed completo de estantes) |
| `-demo-lang en` | la app en inglés |
| `-demo-signed-out` | la pantalla de entrada |
| `-demo-gesture brightness` · `volume` · `seek` · `fastforward` | con el reproductor abierto, simula ese gesto a medio camino (ver «Gestos del reproductor») |

```bash
xcrun simctl launch booted mx.iracheta.orbital -demo -demo-title series:tt0386676 -demo-open play
```

### Pruebas

```bash
cd ios/OrbitalCore && swift test         # lógica y modelos (con los mismos casos que las pruebas de Python)
python scripts/ios_golden.py             # regenera los valores de referencia si cambia la lógica de Python
python scripts/ios_strings.py --check    # ningún texto sin traducir
```

Las pruebas de Swift leen `tests/fixtures/` (los mismos datos de ejemplo que usan las de Python) y los valores que genera
`scripts/ios_golden.py` a partir de las funciones de Python: si Swift y Python dan distinto, la prueba falla.

## Instalar en tu iPhone

1. `brew install xcodegen`, luego `cd ios/App && xcodegen` y abre `Orbital.xcodeproj`.
2. En `project.yml` pon tu **equipo** (`DEVELOPMENT_TEAM`) y tu **identificador** (`PRODUCT_BUNDLE_IDENTIFIER`).
3. Ejecuta en tu iPhone (iOS 26+, Xcode 26). Con cuenta de desarrollador de pago el perfil dura un año.
4. Al abrir: entra con tu cuenta de **Stremio**. En Ajustes agrega (opcional) la clave de **TMDB** (fichas en español y
   plataformas) y el *client id* de tu aplicación de **Trakt**.

## Lo que está verificado y lo que no

| | Estado |
|---|---|
| `OrbitalCore` y `OrbitalModels` | Compilados y probados (Swift 6.2, Linux): `swift test` (193 pruebas). Pasaron además dos revisiones independientes (compilación y lógica/seguridad); sus hallazgos están corregidos y con prueba. |
| Los modelos de vista y su lógica de reproducción | Probados con un motor y una red falsos. |
| Sistema de diseño (colores = `palette.json`, sin valores sueltos en pantallas) | Verificado con pruebas. |
| **SwiftUI, descargas en segundo plano, AVPlayer, Keychain** | Compilado con Xcode 27 (SDK iOS 26) e instalado en un iPhone. Recorrido en el simulador con el modo demostración: Inicio, Para ti, Ver, Buscar, ficha, fuentes, Descargas (una descarga real de punta a punta), Ajustes, entrada, en español e inglés y con letra de accesibilidad. |
| **AetherEngine** (`Platform/AetherEnginePlayer.swift`) | Compila con la 7.35.1 y reproduce en el simulador (HLS por su vía nativa). PiP no se puede probar en el simulador: falta verlo en el iPhone. |
| Infuse, Real-Debrid, Trakt reales | Sin probar contra los servicios reales. Ver «Pruebas pendientes en el iPhone». |

## Pruebas pendientes en el iPhone

1. ¿Infuse reproduce la URL (¿pide Pro?), y llega `x-success` con `position` al cerrar, al terminar y al matar la app?
2. AetherEngine con tus archivos de Real-Debrid (4K HDR/Dolby Vision, PGS, varios audios): arranque, seek, PiP, batería, temperatura.
3. Descargas: que el enlace caducado se renueve y se reanude, y que el archivo descargado se reproduzca.
4. Trakt: que la app pueda conectarse a tu cuenta (las cuentas gratuitas permiten una sola «app comunitaria»; Stremio ya la ocupa).
5. Que lo guardado en Stremio aparezca en Orbital (con el título original, no el traducido) y al revés.
6. Gestos del reproductor (CEN-16): que el `MPVolumeView` oculto mueva el volumen de verdad sin que aparezca el
   HUD del sistema, que el brillo real responda igual de fino que en el simulador, y la sensación de los tres
   gestos (brillo, volumen, buscar) a la vez que el doble toque y el pellizcar, con el dedo de verdad (el
   simulador no tiene multitáctil con el mismo tacto).

## Mosaico fluido (CEN-49)

El mosaico de «Para ti» se trababa (en el iPhone, con congelamientos de hasta ~3 s). Qué se cambió, sin tocar el aspecto:

- **Imágenes** (`Platform/ImagePipeline.swift`, `RemoteImage` en el catálogo): reemplaza a `AsyncImage` en todo el app. `URLSession` +
  ImageIO (`kCGImageSourceThumbnailMaxPixelSize`) reducen cada imagen al tamaño en que se ve (`DS.Image`), fuera del hilo principal,
  máx. 4 a la vez, con caché en memoria (`NSCache`, tope 96 MB, se vacía con avisos de memoria) y en disco (`URLCache` de 256 MB, compartido).
  Una imagen ya cargada aparece en el primer fotograma. `ArtTint` ya no decodifica el fondo completo (usa una miniatura de 48 px).
- **Layout**: las columnas ya no son `@Published`: el arrastre y el ambiente mueven solo un `offset` (`MosaicColumnScroll`, uno por columna);
  las piezas viven en `MosaicColumnLayer` (`Equatable`), que no se reevalúa si no cambió su contenido. Solo se pintan las piezas a la vista más
  medio alto de colchón (`DesignTokens.Mosaic.cullMargin`). El temporizador del ambiente solo corre en ambiente. `fill` no arma conjuntos si no hace falta.
- **Reducir movimiento** ya apagaba el ambiente y el acercamiento (se verificó: ni el temporizador ni `alive` corren).

### Cómo se midió

`-demo -demo-tab 1 -demo-mosaic-bench` (solo Debug, `MosaicBench`): el mosaico se desplaza solo 8 s (700 pt/s) y luego cambia de foco 6 s, y
la consola imprime fotogramas por segundo, percentiles, saltos (> 1,5 fotogramas), memoria (`phys_footprint`), el peor bloqueo del hilo
principal (vigilante) y cuántas veces se evaluó cada `body`. Imágenes reales de metahub, ~94 piezas vivas.

| Simulador (iPhone 17 Pro), 3 corridas | Antes | Después |
|---|---|---|
| Desplazar: fps | 46–54 | 53–59 |
| Desplazar: p95 del fotograma | 33–40 ms | 16,7 ms |
| Saltos al desplazar (de ~430 fotogramas) | 31–67 | 5–16 |
| Cambiar foco: p95 | 45–55 ms | 16,7–28 ms |
| Memoria | 365–383 MB | 48–66 MB |
| `body` de piezas al desplazar | 31 700–37 700 | 3 800–4 700 |

iPhone real («iPhone de Fer», antes, Debug): al desplazar 14–55 fps (varía entre corridas), p95 38–108 ms y **un bloqueo del hilo
principal de 2,95 s** en una corrida. Los números «después» en el iPhone **no se midieron** (sin instalar la versión nueva a petición del usuario).

## Viendo en la TV

En Inicio, arriba del destacado: una tarjeta con lo que se ve ahora en tu Orbital (con la dirección y el token de
«Tu Orbital» en Ajustes). Mientras la app está activa, `TVNowModel` consulta `GET /api/companion/now` cada 5 s; si
tu Orbital no contesta (apagada, sin túnel, una versión vieja) la tarjeta se oculta sin avisar, y si el token ya
no sirve se oculta y queda un aviso para revisarlo en Ajustes.

- **Película o episodio**: póster, título, episodio y «quedan N min», con una barra de avance que se interpola
  entre sondeos (no salta de 5 en 5 s). Botones −10 s · Pausa/Reanudar (un poco más grande) · +10 s · Siguiente
  episodio, y un menú ⋯ con «Salir del video» (para la consola) y «Seguir aquí» (abre la ficha en el iPhone; el
  avance ya vive en Stremio).
- **TV en vivo**: el nombre del canal, «● En vivo» (con el tono de aviso del sistema de diseño), ▲▼ para cambiar
  de canal y «Sin sonido».
- Cada botón manda `POST /api/companion/player` con `{action, delta?}` y pinta la respuesta al instante (sin
  esperar al siguiente sondeo); mientras una acción está en vuelo los botones se atenúan y un segundo toque no
  duplica la petición. Con «Reducir movimiento» la tarjeta no anima; con letra de accesibilidad grande los botones
  se apilan con su nombre.
- Modo demo: `-demo-tv-now` enseña la tarjeta con una serie de mentira que avanza sola (y obedece los botones),
  para verla en el simulador sin tu Orbital.

## Desde la TV

Desde la TV (el panel Y «Más» del reproductor, la ficha y el menú Y de un video en «Seguir viendo») puedes mandarle algo
al iPhone: **Enviar al iPhone** o **Descargar en el iPhone**. Solo aparece con un iPhone conectado (token y Tailscale).
La consola lo deja en una bandeja (`state.json`, máximo 20, sin repetir el mismo título con la misma acción) y la manda
dentro de la respuesta de `GET /api/companion/now` (`inbox: [...]`): el iPhone no hace una petición extra.

- `InboxModel` (en `OrbitalModels`, con pruebas) atiende lo pendiente que trae `TVNowModel`:
  - `download`: busca la fuente recomendada y la encola en `DownloadsModel`/`Downloads` por el mismo camino que el botón
    Descargar de la ficha (`Services.queueDownload`). «Solo con Wi‑Fi» lo respeta la cola: si no hay Wi‑Fi espera. Aviso:
    «Descargando The Office T2 · E5 (desde la TV)», con háptica.
  - `open`: guarda un «Desde la TV» (sobrevive a cerrar la app) que Inicio enseña como tarjeta pequeña bajo «Viendo en
    la TV», con Ver · Descargar · Descartar.
- A la consola se le avisa (`POST /api/companion/inbox/ack {ids}`) **solo de lo que ya se atendió**. Si no se pudo (sin
  red, los complementos no contestan) se queda en su bandeja y se reintenta en el siguiente sondeo; tras 3 intentos
  se avisa en palabras. Si el aviso se pierde y la consola repite algo, no se descarga dos veces.
- El sondeo es de toda la app (arranca en `RootView`), no de Inicio: una descarga mandada desde la TV arranca aunque
  estés en otra pestaña.
- **Segundo plano, mejor esfuerzo**: `InboxBackgroundTask` registra un `BGAppRefreshTask`
  (`mx.iracheta.orbital.inbox`; `UIBackgroundModes` fetch y processing) que consulta la bandeja y encola descargas en la
  sesión de fondo. **iOS decide si y cuándo corre** (puede tardar horas o no correr nunca, sobre todo con poca batería o si
  casi no abres la app): lo seguro es abrir Orbital en el iPhone, donde se atiende al momento.
- Modo demo: `-demo -demo-inbox download` (la descarga de prueba y el aviso) y `-demo -demo-inbox open` (la tarjeta
  «Desde la TV» en Inicio).
- Lo que solo se prueba con la consola y el iPhone reales: el botón en el panel del reproductor (mpv), que el iPhone esté
  «conectado» de verdad (Tailscale) y que iOS despierte la tarea en segundo plano.

## Scrobble a Trakt

Qué le manda cada reproductor a Trakt (solo con Trakt conectado; en el iPhone, con la sesión que presta tu Orbital):

| Momento | Aviso | Porcentaje |
|---|---|---|
| El motor suena de verdad y ya se sabe la duración | `start` | el avance real |
| Pausar | `pause` | el avance real |
| Reanudar (aunque pase por «cargando») o un salto de 30 s o más (iPhone) / 60 s o más (consola) | `start` | el avance nuevo |
| Cerrar, terminar o pasar al siguiente episodio | `stop` | el avance real (Trakt lo marca visto desde 80 %) |

- Un 409 (ya registrado) no es un error; un 401 pide una sesión nueva (la consola renueva; el iPhone se la pide a la consola) UNA vez y reintenta.
- Sin conexión, lo visto (≥ 80 %) espera en la cola y se sube con su fecha real, sin duplicar (se revisa el historial antes).
- Ir a segundo plano solo guarda el avance en Stremio: el audio sigue sonando, así que no es un `stop`.
- Infuse avisa a Trakt con su propia conexión (aquí no se duplica). La TV en vivo nunca se manda.
- Ajustes › Trakt › «Último scrobble» (iPhone) y Ajustes › Cuentas › Trakt (TV) dicen qué se mandó y hace cuánto, o el error en palabras. Con `-demo -demo-scrobble` la fila sale llena.

**Verificarlo con tu cuenta:** ve algo unos minutos y, sin cerrarlo, abre trakt.tv › tu perfil › «Viendo ahora»; al cerrarlo (pasando del 80 %) aparece en trakt.tv › Historial.

## Descargas: cómo se reanudan

- **Pausa o corte de red**: se conserva lo bajado con los datos de reanudación de `URLSession` y se continúa mientras el enlace valga.
- **Enlace de Real-Debrid caducado** (403/404/410): se pide un enlace nuevo al mismo complemento y la descarga empieza de nuevo desde cero
  (los datos de reanudación están atados al enlace viejo).
- **Relanzar la app**: una descarga que el sistema siguió en segundo plano se adopta, no se reinicia.
- iOS cancela las descargas si cierras la app deslizándola en el selector de apps.

## Mosaico de «Para ti» (pieza `Mosaic`, espejo de `foryou-mosaic` en la TV)

`Design/Mosaic.swift` (vista y motor) sobre `OrbitalModels/MosaicLayout.swift` (geometría pura, probada en `MosaicLayoutTests`): 4 columnas en vertical (6 en horizontal/iPad),
la columna enfocada ×1,8, ninguna pieza partida, cascada con relleno/poda, ambiente a los 30 s, «cobra vida» a los 2,2 s; con Reducir movimiento no hay ambiente ni acercamiento ni resorte.
Tocar enfoca (resorte + háptica), volver a tocar abre la ficha, mantener pulsado «No me interesa». La enfocada enseña etiqueta + logo (metahub, cae al nombre) + dato.
Tokens: `DesignTokens.Mosaic`. Modo demostración: `-demo-mosaic-focus N` enfoca la sugerencia N al abrir.
Ojo al probar en el simulador: instala siempre un build propio (`-derivedDataPath`); otro worktree puede dejar su `.app` con el mismo identificador.

## La firma de la consola en Inicio y en la ficha (CEN-37)

Un solo sistema de diseño con dos implementaciones espejo: cada pieza lleva el mismo nombre que en la TV y usa los mismos tokens (`DesignTokens.Backdrop`, `Size.logoHero`).

| Pieza (iPhone) | Equivale en la TV | Qué hace |
|---|---|---|
| `Backdrop` (`Components.swift`) | `backdrop.js` / `--art-tint` / `.backdrop__space` | El tono del arte enfocado o abierto tiñe toda la pantalla (fundido `DS.Motion.tint`, sin movimiento con Reducir movimiento). Sin arte y con `space`: estrellas muy tenues (Inicio, Para ti). Inicio: el destacado; ficha: el póster; Para ti: la pieza enfocada (`Mosaic.onFocusChange`) |
| `BleedArt` | arte de `FeatureTile` y `.title__backdrop` | Arte a sangre que se funde con el fondo (máscara de gradiente, sin esquinas) |
| `TitleLogo` | `.title__logo` / `--logo` | Logo de metahub; si no carga, el nombre en texto. `.tile` (mosaico) y `.hero` (destacado y ficha) |
| `HeroCard` | `FeatureTile` | Destacado de Inicio: arte a sangre, logo, «T2 · E5 · quedan 20 min», Continuar |
| `RowTile` | `RowTile` (`tiles.js`) | Renglón con miniatura ancha, nombre y dato: «También tenías» |

Vocabulario único en `OrbitalCore/Vocabulary.swift` (`runtimeText`, `timeLeft`, `factLine`, `factVariants`, `titleFacts`, `greeting`): `runtimeText` y `timeLeft` se comparan con `orbital/foryou.py` y `orbital/watch.py` (`scripts/ios_golden.py` → `tests/fixtures/ios/vocabulary.json`). Inicio saluda como `core/home.js`; la ficha pone Mi lista y En la TV como íconos en la barra, Descargar y Fuentes bajo el botón principal, y pide la sinopsis en español a `/api/foryou/details` si la consola está conectada.

## Excepciones al sistema de diseño

`DesignTests` revisa que las pantallas no escriban colores, medidas, opacidades ni esperas a mano. Una línea se exime con `ds-exception: motivo`:

| Dónde | Motivo |
|---|---|
| `Design/Components.swift` (`averageColor`) | el color sale de los píxeles del póster, no es un valor de diseño |
| `Support/Demo.swift` | demora de red simulada del modo demostración (solo Debug), no es una espera de la interfaz |

## Límites conocidos

- Los enlaces de Real-Debrid pueden quedar en la memoria de la app mientras corre; no se guardan en disco (sesión efímera, Keychain para lo guardado).
- Infuse recibe la URL del video y devuelve `orbital-ios://…` a quien la abra: es inherente a la API de Infuse.

- Infuse solo avisa **al cerrar** y no da la duración: el avance de lo visto en Infuse es de «mejor esfuerzo».
- PiP y AirPlay dependen del motor; el reproductor propio todavía no los expone en la interfaz.
- Los mensajes de error que arman los modelos en español no se traducen todos al inglés.
- La API de Stremio no es oficial: si cambia, falla aquí y en Orbital a la vez.
