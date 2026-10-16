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

## Descargas: cómo se reanudan

- **Pausa o corte de red**: se conserva lo bajado con los datos de reanudación de `URLSession` y se continúa mientras el enlace valga.
- **Enlace de Real-Debrid caducado** (403/404/410): se pide un enlace nuevo al mismo complemento y la descarga empieza de nuevo desde cero
  (los datos de reanudación están atados al enlace viejo).
- **Relanzar la app**: una descarga que el sistema siguió en segundo plano se adopta, no se reinicia.
- iOS cancela las descargas si cierras la app deslizándola en el selector de apps.

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
- El mosaico de «Para ti» no tiene aún el «modo ambiente» ni el acercamiento lento de la TV.
- PiP y AirPlay dependen del motor; el reproductor propio todavía no los expone en la interfaz.
- Los mensajes de error que arman los modelos en español no se traducen todos al inglés.
- La API de Stremio no es oficial: si cambia, falla aquí y en Orbital a la vez.
