# Orbital para iPhone: plan de la app compañera

App de iOS para uso personal que reproduce películas y series con los mismos complementos de Stremio,
la misma cuenta y las mismas preferencias que Orbital. Este documento es solo investigación y plan;
todavía no hay código de la app.

> **Cómo leer las cifras.** La parte de Orbital sale de leer el código (rama `claude/addons-genericos`).
> Los datos externos (versiones, licencias, precios, reglas de Real-Debrid, Trakt, Apple) salen de lo
> que se conocía hasta mediados de 2026. **La búsqueda web de esta sesión no terminó a tiempo**: lo
> marcado con **(verificar)** hay que comprobarlo en la fuente antes de decidir con eso. Al final hay
> una lista de qué comprobar.

---

> **Actualización (2026-10-12, investigación web terminada):** dos conclusiones de este documento
> cambian; ver §14. (1) **Infuse sí devuelve la posición** (`x-success` con `position`), así que sirve
> como primera versión. (2) **MPVKit no es para producción** según su propio autor; **AetherEngine** es
> la opción a probar primero (PiP nativo, Dolby Vision 5/8, SwiftUI). El resto del texto se dejó como
> estaba para no perder el razonamiento.

## 1. Resumen y recomendación

- **App nativa en SwiftUI** (no React Native). Es una sola plataforma, tienes Mac y Xcode, y lo
  difícil (reproductor, PiP, AirPlay, descargas en segundo plano, Keychain) es todo API nativa.
- **Reproductor: libmpv vía MPVKit** como motor principal: es el mismo motor que Orbital (mpv), abre
  MKV con todas sus pistas y subtítulos ASS/PGS, y la lógica de idiomas de `playback.py` se porta casi
  tal cual (`alang`, `slang`, `subs-fallback-forced`…). **AVPlayer** queda como segunda vía para lo que
  libmpv hace peor (AirPlay de video, Dolby Vision real en archivos MP4/HLS). **Infuse** como plan B
  con un botón «Abrir en Infuse», no como primera versión (ver §7.3).
- **Sincronización: la cuenta de Stremio es la fuente de verdad**, igual que en Orbital: el
  `libraryItem` con su `state` (avance, `video_id`, bitfield `watched`). Se porta `stremio_api.py`
  completo. **Trakt: opcional y después** (scrobble para tener historial), no para el avance.
- **Descargas**: `URLSession` en segundo plano con el enlace directo de Real-Debrid, guardando la URL
  «resolver» del complemento para pedir un enlace nuevo si el viejo caduca; subtítulos y ficha junto
  al video; el avance offline se encola y se sube al volver la red.
- **Instalación**: con tu cuenta de desarrollador de pago (perfil de un año, o TestFlight interno).
  Con Apple ID gratuito la app caduca a los 7 días.
- **Primera versión mínima** (§12, etapa 1): entrar con Stremio, «Seguir viendo», buscar, ficha con
  episodios, lista de fuentes ordenada como en Orbital, reproducir con MPVKit con audio y subtítulos
  en tu idioma, y guardar el avance en Stremio. Sin descargas ni Trakt todavía.

---

## 2. Qué se puede portar de Orbital

Orbital ya resuelve casi toda la lógica que no es interfaz. Es Python puro y sin dependencias raras:
se traduce a Swift función por función. Propuesta: un paquete Swift `OrbitalCore` (sin UIKit) con
pruebas que usen **los mismos casos que las pruebas de Python** (fixtures JSON compartidos: el mismo
título de Torrentio debe dar la misma puntuación en los dos lados).

| Módulo de Orbital | Qué hace | En Swift |
|---|---|---|
| `library/addons.py` | Manifiesto, `resources` con reglas propias, `types`, `idPrefixes`; `Addon.handles(recurso, tipo, id)`; `manifest_url` acepta `stremio://` y sin `/manifest.json`; lista = cuenta (`addonCollectionGet`) + tuyos; caché de 10 min y solo 15 s si algo falló; `redact()` para los registros | **Se porta entero.** `AddonRegistry` como `actor`. Los complementos propios (su URL lleva la clave de Real-Debrid) van al **Keychain**, como en Orbital van cifrados con DPAPI |
| `library/streams.py` | Pide fuentes en paralelo, las analiza (banderas e indicios de idioma, resolución, HDR/DV, tamaño, seeders, `[RD+]`, REMUX/x265/Atmos, CAM/Tráiler), `score()` por idioma/calidad/caché y `bingeGroup`; índice estable por hash; subtítulos de los complementos por idioma ISO 639-2 | **Se porta entero**, con `TaskGroup` en lugar de `ThreadPoolExecutor`. `score()` necesita un ajuste para el teléfono: preferir 1080p y castigar antes lo enorme en datos móviles; y una variante «para descargar» (§5). `encode_stream`/`player_link` (enlace `stremio:///player/…`) no hacen falta |
| `library/stremio_api.py` | `login`, `datastoreGet`/`datastorePut` de `libraryItem`, `with_progress` (avance, `timeWatched`, umbral de visto 0,9, salto al siguiente episodio con `timeOffset: 1`), `parse_watched`/`encode_watched` (bitfield zlib+base64 de stremio-core), `library_toggled` (Mi lista), `dismissed` (Quitar de Seguir viendo), `parse_item` con la regla de `is_in_continue_watching` | **Se porta entero; es el corazón de la sincronización.** zlib: `Compression` de Apple trae `COMPRESSION_ZLIB`, que es *deflate crudo* sin la cabecera zlib de 2 bytes ni el Adler-32: hay que añadirlos/quitarlos a mano (o usar `libz` del sistema, que sí está en iOS). Probarlo contra bitfields reales de tu cuenta |
| `library/cinemeta.py` | Catálogo `top`, búsqueda tolerante, ficha con `videos`, `seasons()`, `next_episode()`, `search_results()` alternando series y películas, `credits()`; para ids no IMDb (kitsu) pide la ficha al primer complemento que la sabe | **Se porta entero** |
| `library/localize.py` + `library/tmdb.py` | Ficha en tu idioma vía TMDB (`es` → `es-MX`), título, sinopsis, géneros y episodios; ignora «Episodio 3» genérico; caché 24 h, reintento 10 min | **Se porta entero.** La clave de TMDB al Keychain |
| `watch.py` | Orquesta: preferencias por título (cada serie recuerda su audio/subtítulos), `best_source` con `bingeGroup`, «otra fuente si falla» (hasta 4, en el mismo punto), Up Next, episodio anterior/siguiente, guardado del avance cada minuto, al pausar y al terminar | **Se porta la lógica** (no el código: aquí hay sesiones, ventanas y mando de Windows). Es el `PlaybackCoordinator` de la app |
| `playback.py` | `stream_url()` (solo `http(s)`/`magnet`; los `infoHash` van al servidor local de Stremio), opciones de idioma de mpv (`alang`, `slang`, modo «forzados»), `track_properties` para el mpv ya abierto, `chapter_kind()` (intro/créditos por nombre de capítulo), `wrong_audio()`, constantes (`STARTUP_TIMEOUT` 45 s, `SAVE_EVERY` 60 s, Up Next a 30 s del final o al empezar los créditos, «¿Sigues viendo?» tras 3 episodios) | **Las opciones de mpv se reutilizan tal cual con MPVKit** (mismo motor). Los botones del mando no; en su lugar, gestos |
| `library/trakt.py` | Trakt por *device code*, refresco del token, listas, watchlist, recomendaciones; **solo lectura, sin scrobble** | Se porta si llega la etapa de Trakt; en el teléfono se usa OAuth normal (`ASWebAuthenticationSession`) en vez del código |

**Lo que no se porta:** fuentes `infoHash` sin Real-Debrid. Orbital las manda al servidor de Stremio
(`127.0.0.1:11470`) que hace de cliente BitTorrent; en el iPhone no hay tal servidor. La app solo
acepta fuentes con `url` http(s) (en la práctica, las de Real-Debrid) y oculta el resto.

**Una observación del código** (para no copiarla): en `watch._save_progress`, si el título aún no
existía en tu biblioteca, el `libraryItem` nuevo se crea con `info.get("name")`, y esa ficha ya viene
traducida por `localize`. Stremio guardaría el nombre en español. En la app, el `name` del
`libraryItem` debe ser el original de Cinemeta, no el traducido.

---

## 3. Arquitectura

### 3.1 SwiftUI frente a React Native

| | SwiftUI nativo | React Native (como Nuvio) |
|---|---|---|
| Reproductor con libmpv/AVPlayer, PiP, AirPlay | Directo | Módulo nativo de todas formas (en Swift/ObjC) |
| Descargas en segundo plano | `URLSession` background, directo | Módulo nativo o librería de terceros |
| Android algún día | No | Sí (la razón de ser de Nuvio) |
| Tu equipo | Mac + Xcode, una persona | Añade Node, Metro, Expo, puentes |
| Reutilizar Orbital | Se traduce Python → Swift | Se traduce Python → TypeScript (la interfaz web de Orbital es JS, pero no comparte nada de esto) |

**Recomendación: SwiftUI.** React Native solo compensa si quieres Android; para una app personal de
iPhone el puente nativo es justo la parte difícil, y la tendrías que escribir igual.

### 3.2 Módulos

```
OrbitalCore (paquete Swift, sin UI, con pruebas)
  Addons        manifiestos, reglas, registro (cuenta + tuyos)
  Streams       análisis, puntuación, idiomas, subtítulos de complementos
  StremioAPI    login, datastore, with_progress, bitfield watched
  Catalog       Cinemeta, búsqueda, temporadas, siguiente episodio
  Localize      TMDB, fichas en tu idioma
  Secrets       Keychain (authKey, URLs de complementos, TMDB, Trakt)
App (SwiftUI)
  Inicio        Seguir viendo, Mi lista, populares
  Buscar        Cinemeta + catálogos de complementos
  Ficha         datos, temporadas, «Continuar T3 E5», fuentes
  Player        PlayerEngine (protocolo) → MPVEngine | AVPlayerEngine
                PlaybackCoordinator: fuente, reanudar, otra fuente si falla, Up Next, guardado
  Downloads     DownloadManager (URLSession background), almacén, cola de avance offline
  Sync          ProgressSync (Stremio; Trakt opcional), cola persistente
  Ajustes       idioma de la app, audio, subtítulos, calidad, datos móviles, cuenta
```

- `PlayerEngine` es un protocolo (`load`, `play/pause`, `seek`, `tracks`, `select(track)`,
  `addSubtitle(url)`, publicación de `position/duration/chapters/buffering`). Así se puede cambiar
  de motor sin tocar la interfaz, y el plan B de Infuse es otro «motor» que solo abre y no informa.
- Estado: `@Observable` + `actor`s para lo de red; persistencia local con SwiftData o SQLite
  (GRDB) para caché de fichas, descargas y la cola de sincronización.
- Las URLs de las fuentes nunca se registran (como `redact()` en Orbital): llevan tu clave.

---

## 4. Reproductor

### 4.1 Comparativa

| | **MPVKit (libmpv)** | **VLCKit** | **KSPlayer** | **AVPlayer** |
|---|---|---|---|---|
| Qué es | libmpv + FFmpeg empaquetados como Swift Package (`mpvkit/MPVKit`) | Motor de VLC para Apple (VLCKit 3 estable; VLCKit 4 en desarrollo largo) | Reproductor Swift: AVPlayer para lo nativo + motor propio FFmpeg (`KSMEPlayer`) | El de Apple |
| Licencia | LGPL (libmpv/FFmpeg en configuración LGPL; hay variante GPL) **(verificar la del paquete)** | LGPL-2.1 | GPL-3.0 en GitHub; licencia LGPL/comercial de pago para la versión completa **(verificar)** | Propietaria del sistema |
| MKV, varias pistas, ASS/PGS | Sí, todo (es mpv) | Sí | Sí (motor FFmpeg) | **No MKV**; MP4/MOV/HLS; subtítulos WebVTT/CEA |
| HDR10 | Sí, con renderizado propio; calidad depende de la salida (Metal/vo) **(verificar estado en iOS)** | Sí con tone mapping; mejor en VLCKit 4 | Sí, vía `AVSampleBufferDisplayLayer` | Sí, nativo |
| Dolby Vision | Perfil 8 se ve como HDR10 (capa base); **perfil 5 sale con colores verdes/morados** salvo que el renderizado lo convierta | Similar a mpv | Promete DV pasando por la capa de Apple **(verificar perfiles)** | Nativo, en MP4/HLS, no MKV |
| PiP | Difícil: PiP de iOS exige `AVPlayerLayer` o `AVSampleBufferDisplayLayer`; hay ramas/experimentos en MPVKit **(verificar madurez)** | VLCKit 4 lo trae; VLCKit 3 no | Sí | Sí |
| AirPlay de video | Solo duplicar pantalla o audio | Igual | Sí si usa la ruta AVPlayer; con el motor FFmpeg, no | Sí, real |
| Decodificación por hardware | VideoToolbox (`hwdec=videotoolbox`) | Sí | Sí | Sí |
| Madurez y mantenimiento | Activo; lo usan varias apps de iOS de terceros | Muy maduro (VLC); VLCKit 4 lleva años en beta | Activo, un mantenedor principal | Máxima |
| Encaje con Orbital | **Igual que Orbital**: mismas opciones de idioma y subtítulos | Otra API | Otra API | Otra API |

### 4.2 Elección: MPVKit como motor principal, AVPlayer como segunda vía

**Pros de MPVKit**
- Es mpv: lo que `playback.py` ya resolvió (alang/slang con códigos `es`, `spa`, `es-419`; modo
  «solo forzados»; volver `aid/sid` a `auto` entre episodios; capítulos para saltar intro y créditos)
  se reutiliza literal.
- MKV, pistas múltiples, ASS con estilos, PGS, cambio de pista sin recargar, caché de red configurable
  (`demuxer-max-bytes`, útil con datos móviles).
- LGPL: para uso personal no hay problema; ni siquiera la variante GPL te obliga a nada si no
  distribuyes la app.

**Contras de MPVKit (y cómo cubrirlos)**
- **PiP**: es la mayor debilidad. Plan: (1) en la etapa 0 probar si la versión actual de MPVKit
  ofrece una salida compatible con PiP; (2) si no, usar AVPlayer cuando la fuente sea MP4/HLS
  compatible, y para MKV ofrecer «Abrir en Infuse» cuando quieras PiP.
- **AirPlay a la Apple TV**: mpv no envía video por AirPlay (solo duplicando pantalla). Misma
  salida: AVPlayer para fuentes compatibles; para MKV, Infuse en la Apple TV es mejor opción que
  mandar desde el teléfono.
- **Dolby Vision perfil 5**: `score()` de Orbital ya castiga «DV sin HDR de respaldo» (−200). En el
  teléfono hay que castigarlo más fuerte (o esconderlo) mientras el motor no lo convierta bien.
- Tamaño del binario (FFmpeg + libmpv: decenas de MB): irrelevante para uso personal.

**Por qué no VLCKit**: estable pero la versión con PiP y mejor HDR (4.x) lleva mucho tiempo sin
versión final **(verificar)**, y no reutiliza nada de Orbital.
**Por qué no KSPlayer como primera opción**: es el candidato más completo «todo en uno» (PiP, AirPlay
por la ruta AVPlayer, DV), y es la alternativa seria si la etapa 0 muestra que MPVKit no da PiP. Pega:
la versión libre es GPL y la completa es de pago **(verificar condiciones actuales)**; para uso
personal la GPL no estorba.

**Decisión condicionada a la etapa 0** (un día de prueba): reproducir en un iPhone real el mismo MKV
4K HDR con 3 audios y subtítulos PGS/ASS desde un enlace de Real-Debrid con MPVKit y con KSPlayer;
medir arranque, cambio de pista, batería/temperatura, PiP y AirPlay. Si MPVKit no da PiP y KSPlayer sí,
gana KSPlayer.

---

## 5. Descargas para ver sin conexión

### 5.1 El enlace
Una fuente de Real-Debrid en Torrentio y similares trae una `url` del propio complemento
(`…/resolve/realdebrid/<clave>/…`) que **redirige** al enlace directo `*.download.real-debrid.com`.
El enlace final caduca **(verificar el plazo actual; hay que tratarlo como horas, no días)**. Por eso:

- Guardar en la descarga **la URL del complemento** (resolver), no solo la final; si una reanudación
  falla con 403/404/410, pedir de nuevo el resolver → enlace nuevo → continuar con `Range` desde los
  bytes que ya hay.
- La `resumeData` de `URLSession` está atada a la URL: si cambia, se reanuda a mano con una
  petición `Range: bytes=N-` y se agrega al archivo parcial. Comprobar `Content-Length`/`ETag` para
  no pegar trozos de otro archivo.
- Solo fuentes `[RD+]` (ya en la caché de Real-Debrid). Lo que no está en caché no se ofrece para
  descargar.

### 5.2 Descarga en segundo plano
- `URLSessionConfiguration.background(withIdentifier:)`: el sistema sigue descargando con la app
  suspendida y relanza la app al terminar (`handleEventsForBackgroundURLSession`). Usar
  `isDiscretionary = false` para las que pides tú, y `allowsCellularAccess` según Ajustes
  («Descargar solo con Wi-Fi», activado por defecto).
- `AVAssetDownloadURLSession` **no sirve**: es solo para HLS; aquí son archivos MKV/MP4 sueltos.
- Si el usuario cierra la app a la fuerza (deslizar en el selector), iOS cancela las descargas en
  segundo plano: avisarlo en la interfaz.
- Una descarga a la vez (o dos), en cola, con reintento exponencial.

### 5.3 Qué se guarda y dónde
```
Application Support/Downloads/<meta_id>/<video_id>/
  video.mkv            (excluido de la copia de iCloud: isExcludedFromBackup)
  subs/es.srt, en.srt  (de los complementos de subtítulos, como streams.subtitles())
  meta.json            ficha ya traducida, temporada/episodio, fuente elegida, resolver, tamaño
  poster.jpg, still.jpg
```
- Subtítulos: además de las pistas que trae el MKV, bajar los del idioma de audio/subtítulos de esa
  serie (la preferencia por título de `watch.language_for`). Con mpv se cargan con `sub-add`.
- **Elegir fuente para descargar** es distinto de para transmitir: una variante de `score()` con
  1080p, x265/HEVC y tamaño moderado (p. ej. 1,5–4 GB película, 0,3–1,5 GB episodio) por encima de
  REMUX o 4K.
- Espacio: antes de empezar, `volumeAvailableCapacityForImportantUsage` contra el tamaño de la
  fuente (Orbital ya lo saca del título, `💾 2.1 GB`), dejando un margen; pantalla de descargas con el
  total usado y «borrar al terminar de verlo» (opcional, como Netflix).
- Series: «Descargar los siguientes N episodios» y reponer el siguiente al terminar uno (imitar las
  descargas inteligentes de Netflix/Infuse).

### 5.4 Avance sin conexión
Lo que ves sin red va a una cola persistente (`meta_id`, `video_id`, posición, duración, segundos
vistos, hora). Al volver la red se sube con la misma lógica de `with_progress`, comparando con el
`_mtime`/`lastWatched` del elemento remoto: si el remoto es más nuevo (lo viste en Orbital
mientras tanto), no se pisa.

---

## 6. Sincronización

### 6.1 Stremio (obligatorio)
Es exactamente lo que hace Orbital, así que **lo que veas en el iPhone aparece en «Seguir viendo»
de Orbital y de Stremio, y al revés**:

- Leer: `datastoreGet` (`collection: libraryItem`, `all: true`) al abrir la app y al volver a primer
  plano; `parse_library` + regla de «Seguir viendo» (`type != other` y `timeOffset > 0`).
- Reanudar: `resume_seconds()` (solo si el `video_id` coincide y no pasó del 90 %).
- Escribir: `datastorePut` con `with_progress()` **cada 60 s, al pausar, al pasar a segundo plano
  (`scenePhase`), al cerrar el reproductor y al terminar**; al terminar un episodio, `watched`
  marcado en el bitfield y `state.video_id` pasa al siguiente con `timeOffset: 1`.
- Antes de escribir, releer el elemento (`library_item`) para no pisar cambios de otro dispositivo
  (Orbital ya lo hace así).
- Mi lista (`library_toggled`) y «Quitar de Seguir viendo» (`dismissed`) igual que en Orbital.
- Inicio de sesión: email y contraseña de Stremio una vez → `authKey` al Keychain.

La API de Stremio **no es oficial ni está documentada** (Orbital lo dice en `stremio_api.py`); si
cambia, falla en los dos lados a la vez y se arregla en los dos.

### 6.2 ¿Trakt además?
- **A favor**: historial completo y estadísticas, calendario de estrenos, recomendaciones (Orbital ya
  las lee en «Para ti»), y si algún día usas Infuse, Infuse sincroniza con Trakt.
- **En contra**: el avance «a medias» de Trakt (`/sync/playback`, scrobble `start/pause/stop`) es otra
  fuente de verdad; mezclarlo con Stremio crea conflictos. Además Trakt endureció en 2025 los límites
  de la cuenta gratuita (listas/colección/watchlist con tope de elementos) y la API pide registrar la
  app **(verificar límites actuales)**.
- **Recomendación**: Stremio para avance y «Seguir viendo»; Trakt solo como **destino de scrobble**
  (marca vistos e historial), en una etapa posterior y desactivable. Si se hace, conviene que Orbital
  también haga scrobble con su `trakt.py` (hoy solo lee) para que el historial no tenga huecos.

---

## 7. Infuse como inspiración (y como plan B)

### 7.1 Lo que hace bien
- **Pantalla de inicio limpia**: «Seguir viendo»/«En curso» arriba, fondos grandes, logos del título
  en vez de texto.
- **Fichas ricas**: fondo, logo, reparto con fotos, calificaciones, temporadas en carrusel con
  miniaturas y sinopsis de cada episodio; indicadores de visto/a medias en cada episodio.
- **Reproductor**: barra mínima; gestos (tocar = mostrar controles, doble toque a los lados = ±10 s,
  deslizar horizontal = buscar con miniaturas, vertical = brillo/volumen, pellizcar = ajustar/llenar);
  bloqueo de pantalla.
- **Audio y subtítulos**: un solo panel con pistas nombradas por idioma y formato («Español · AC3 5.1»),
  búsqueda de subtítulos en línea (OpenSubtitles), ajuste de retraso, tamaño y estilo, «forzados»
  automáticos, recuerda la elección.
- **Up Next** con cuenta atrás al llegar a los créditos; **Skip intro** cuando hay capítulos.
- **Descargas** («sincronizar para ver sin conexión») con el avance que vuelve a subir.
- **Trakt**, **PiP**, **AirPlay**, y en Apple TV **ajustar frecuencia de cuadro y rango dinámico**
  (Match Frame Rate / Dynamic Range).
- Versión Pro de pago (suscripción o de por vida) para formatos como Dolby Vision/Atmos y servicios
  en la nube **(verificar precios y qué incluye hoy)**.

### 7.2 Qué imitar, por prioridad
1. **Panel único de audio y subtítulos** con nombres legibles; recordar por serie (Orbital ya lo
   hace). Ajuste de retraso de subtítulos (mpv: `sub-delay`) y tamaño (`sub-scale`; Orbital ya lo usa).
2. **Gestos del reproductor**: tocar, doble toque ±10 s, arrastre para buscar, bloqueo.
3. **Up Next + Skip intro** con capítulos (`chapter_kind()` ya existe) y, sin capítulos, la tarjeta a
   30 s del final (`UPNEXT_AT`). «¿Sigues viendo?» tras 3 episodios.
4. **Fichas con logo, fondo y episodios con miniatura y estado**; el bitfield `watched` de Stremio da
   el ✓ de cada episodio.
5. **Descargas inteligentes de series**.
6. **Elegir fuente sin pensarlo** (la recomendada arranca sola, la lista detrás): esto ya es mejor en
   Orbital que en Infuse, que no tiene concepto de fuentes.
7. **PiP y AirPlay** donde el motor lo permita.
8. Frecuencia de cuadro y rango dinámico: solo tiene sentido en Apple TV (ver §12, etapa 5).

### 7.3 Infuse como reproductor externo
Infuse acepta un esquema x-callback-url del tipo
`infuse://x-callback-url/play?url=<URL codificada>` (con `x-success`/`x-error` para volver a la app)
**(verificar parámetros exactos en la documentación de Firecore, incluido si acepta un subtítulo
externo)**. Con enlaces http directos de Real-Debrid funciona como «abrir URL».

- **Como primera versión: no.** Infuse **no devuelve la posición** a la app que lo abrió (el
  callback solo dice que terminó o falló **(verificar)**), así que el avance no llegaría a Stremio y se
  pierde el requisito principal. Sí se sincronizaría vía Trakt si Infuse está conectado a Trakt, pero
  eso es el avance de Trakt, no el de Stremio.
- **Como plan B: sí.** Botón «Abrir en Infuse» en la ficha/fuentes, útil para PiP de MKV, AirPlay a
  Apple TV o un DV problemático. Al volver (`x-success`), la app puede preguntar «¿Hasta dónde
  llegaste?» o marcar como visto con un toque.
- Ojo: el enlace lleva tu sesión de Real-Debrid; queda en el historial de Infuse.

---

## 8. Bilingüe (español / inglés)

- Interfaz con **String Catalogs** (`Localizable.xcstrings`) en `es` (base, como Orbital) y `en`;
  idioma por sistema y selector propio en Ajustes (iOS permite idioma por app en Ajustes del sistema).
- Fichas con `Localize` (TMDB, `es-MX` como en Orbital) según el idioma de la app; en inglés no se
  traduce nada.
- Nombres de idiomas de las fuentes: en lugar de `LANG_NAMES` fijo en español, usar
  `Locale.current.localizedString(forLanguageCode:)`.
- Preferencias por separado: idioma de la app ≠ idioma de audio ≠ idioma de subtítulos (en Orbital
  también son tres ajustes distintos).
- Fechas, tamaños y duraciones con `FormatStyle` (no a mano).

---

## 9. Instalación y sus límites

| Vía | Duración | Límites |
|---|---|---|
| Apple ID gratuito + Xcode | 7 días, luego reinstalar | Pocas apps instaladas a la vez con ese perfil, sin algunas capacidades **(verificar si afecta a descargas en segundo plano y PiP)** |
| **Programa de desarrolladores de pago** (99 USD/año) + Xcode | El perfil de desarrollo dura **un año** | Se reinstala al renovar. La opción recomendada |
| TestFlight (pruebas internas) con la misma cuenta | Cada build caduca a los 90 días | Las pruebas internas no pasan por revisión de Apple **(verificar)**; cómodo para instalar sin cable |
| AltStore / SideStore | Refresco cada 7 días con Apple ID gratuito | Útil sin cuenta de pago; más mantenimiento |
| Tiendas alternativas (UE) | — | Solo en la UE y con notarización; no aplica |

La App Store queda fuera: la regla 5.2.3 impide apps que faciliten descargar o reproducir contenido
de terceros sin autorización. Tampoco tiene sentido para algo personal.

---

## 10. Riesgos

- **Legales (neutral)**: los complementos dan acceso a contenido cuya licencia no se verifica; la
  responsabilidad de qué se reproduce es de quien lo usa y depende de la legislación de cada país. La
  app no aloja ni comparte nada y no funciona como servicio para otros.
- **Real-Debrid, uso simultáneo**: sus condiciones prohíben compartir la cuenta y vigilan el uso desde
  varias IP a la vez; ver en el iPhone con datos móviles mientras Orbital transmite en casa puede
  parecer una cuenta compartida **(verificar la regla exacta y si hay tolerancia para un mismo usuario)**.
  Mitigación: Ajuste «No transmitir si Orbital está reproduciendo» (difícil de saber) o al menos un
  aviso; las descargas hacerlas en el Wi-Fi de casa (misma IP que Orbital).
- **Real-Debrid, caducidad y límites**: enlaces que caducan (§5.1), límite de peticiones a su API
  **(verificar, del orden de cientos por minuto)**; la app no llama a la API de Real-Debrid
  directamente: habla con el complemento, que ya tiene tu clave. Desde finales de 2024 Real-Debrid
  quitó el endpoint de disponibilidad instantánea; la marca `[RD+]` de los complementos puede ser
  menos fiable **(verificar)** — por eso existe «otra fuente si falla».
- **API de Stremio no oficial**: puede cambiar (afecta también a Orbital).
- **Datos móviles y batería**: un REMUX 4K por datos móviles se come el plan; `score()` del teléfono
  debe preferir tamaños moderados y avisar en móvil.
- **Secretos**: `authKey`, URLs de complementos con la clave de Real-Debrid, TMDB y Trakt en el
  Keychain; registros con `redact()`.
- **Motor y PiP/AirPlay**: si MPVKit no da PiP, cambio a KSPlayer (§4.2); por eso el `PlayerEngine`
  es un protocolo.
- **Mantenimiento**: dos clientes con la misma lógica (Python y Swift). Mitigación: fixtures JSON
  compartidos en las pruebas de los dos lados.

---

## 11. Apps de código abierto parecidas

- **Nuvio (`tapframe/NuvioStreaming`)**: React Native/Expo para iOS y Android con complementos de
  Stremio, Trakt y descargas; en iOS usa un reproductor nativo basado en KSPlayer y/o mpv
  **(verificar cuál en la versión actual y su licencia)**. Útil para leer cómo integra el reproductor
  y la cola de descargas, aunque la recomendación aquí sea SwiftUI.
- **Stremio oficial en iOS**: existe una versión limitada en la App Store (sin reproducir la mayoría
  de complementos por las reglas de Apple) **(verificar estado actual)**; `stremio-core` (Rust, MIT) es
  la referencia del formato de `libraryItem` y del bitfield, que Orbital ya siguió.
- Otras con complementos de Stremio en iOS que conviene revisar **(verificar si son abiertas)**:
  Fusion, Chillio, VidHub, SenPlayer. Varias de ellas son cerradas; sirven como referencia de
  experiencia, no de código.

---

## 12. Plan por etapas

**Etapa 0 — Prueba del motor (1–2 días)**
- Proyecto SwiftUI vacío con MPVKit y KSPlayer; reproducir un enlace de Real-Debrid (pegado a mano)
  de un MKV con varios audios, ASS y PGS, y un 4K HDR/DV.
- Medir: arranque, cambio de pista, PiP, AirPlay, temperatura. Decidir motor (§4.2).

**Etapa 1 — Primera versión mínima**
- `OrbitalCore`: Addons, Streams, StremioAPI, Catalog, Localize, Secrets, con las pruebas portadas.
- Entrar con Stremio; complementos de la cuenta (+ añadir uno propio pegando la URL).
- Inicio: «Seguir viendo» y Mi lista. Buscar (Cinemeta). Ficha con temporadas y «Continuar T3 E5».
- Fuentes ordenadas como Orbital, la recomendada arranca sola, la lista detrás.
- Reproductor: reanudar, audio y subtítulos en tu idioma (y los recuerda por serie), subtítulos de
  complementos si el video no trae, ±10 s, otra fuente si falla.
- Avance a Stremio (60 s, pausa, segundo plano, fin) y episodio visto en el bitfield.
- Interfaz en español e inglés. Instalación con tu cuenta de desarrollador.

**Etapa 2 — Experiencia de reproductor (lo de Infuse)**
- Up Next con cuenta atrás, Skip intro por capítulos, «¿Sigues viendo?».
- Gestos completos, bloqueo, panel único de audio/subtítulos con retraso y tamaño.
- PiP y AirPlay según el motor; segunda vía AVPlayer para fuentes compatibles.
- Botón «Abrir en Infuse» (plan B).

**Etapa 3 — Descargas**
- `DownloadManager` en segundo plano, cola, reanudación con resolver, Wi-Fi/móvil, espacio.
- Subtítulos y ficha junto al video; series «siguientes N episodios».
- Cola de avance sin conexión.

**Etapa 4 — Trakt (opcional)**
- OAuth, scrobble de vistos; el mismo scrobble en Orbital (`trakt.py`).

**Etapa 5 — Extras**
- Catálogos de los complementos en Inicio, widgets de «Seguir viendo», Handoff con Orbital
  («sigue en la TV»: Orbital ya tiene servidor local), app de tvOS con ajuste de frecuencia y rango.

---

## 13. Pendiente de verificar en la fuente

1. MPVKit: versión actual, licencia exacta del paquete, estado de PiP y de la salida HDR en iOS.
2. KSPlayer: licencia de la versión libre y condiciones/precio de la de pago; perfiles de DV.
3. VLCKit 4: si ya hay versión final.
4. Infuse: parámetros del esquema `x-callback-url` (subtítulos, posición inicial) y si devuelve algo
   en `x-success`; precio de Pro.
5. Real-Debrid: regla de IP/dispositivos simultáneos, duración de los enlaces, límite de la API.
6. Trakt: límites de la cuenta gratuita y requisitos de la API en 2026.
7. Apple: límites del Apple ID gratuito y de TestFlight interno en 2026.
8. Nuvio: motor de reproducción en iOS y licencia; si Stremio oficial ya sincroniza con Trakt.


## 14. Datos verificados en la web (2026-10-12) y lo que cambia

Fuentes al lado de cada punto. Lo marcado «sin confirmar» no se pudo comprobar.

### Lo que cambia del plan

1. **Infuse como primera versión: sí.** Su API (`infuse://x-callback-url/play?url=…&position=…&sub=…
   &x-success=…&x-error=…`, Infuse 8.4.7+) llama a `x-success` al cerrar el reproductor con
   `lastPlayedUrl` y `position` en segundos (una vez, no por episodio). Con eso la app compañera puede
   guardar el avance en Stremio. Se puede pasar la posición inicial y un subtítulo, y una lista
   (repitiendo `url`). Sin confirmar: si exige Infuse Pro.
   <https://support.firecore.com/hc/en-us/articles/215090997-API-for-Third-Party-Apps>
   → **Nueva etapa 1 posible:** la app hace todo (cuenta, fichas, fuentes, descargas) y reproduce en
   Infuse; el reproductor propio llega después. Ahorra la parte más difícil.
2. **Motor propio: probar primero AetherEngine, no MPVKit.**
   - *MPVKit* 1.0.0 (jul 2026, mpv 0.41, LGPL-3.0): su README dice que es «solo para aprender libmpv» y
     recomienda AetherEngine para producción; no documenta PiP, HDR ni AirPlay.
     <https://github.com/mpvkit/MPVKit>
   - *AetherEngine* 7.35 (oct 2026, LGPL-3.0 con excepción para App Store): FFmpeg + VideoToolbox, MKV,
     HDR10/HDR10+/HLG, Dolby Vision 5/7/8, Atmos, PGS/ASS, **PiP nativo**, vista SwiftUI. iOS 18+. Lo
     usan NuvioTVOS (con MPVKit de respaldo) y Moonfin. Ojo: proyecto de un autor, escrito con IA según
     su README, pruebas de rendimiento propias. <https://github.com/superuser404notfound/AetherEngine>
   - *KSPlayer*: GPL-3.0 gratis; Dolby Vision y Atmos solo en la versión de pago (mínimo 15 USD/mes).
     <https://github.com/kingslay/KSPlayer/issues/731>
   - *VLCKit 4* sigue en alfa (4.0.0a25); 3.7.x estable. HDR/DV sin confirmar.
   - *AirPlay de video* de verdad solo con AVPlayer; con motores FFmpeg/mpv es audio o duplicar pantalla
     (deducción, sin confirmar).
3. **Real-Debrid ya no dice qué está «en caché».** Quitó `instantAvailability` en nov 2024; los
   complementos lo deducen (Torrentio sigue marcando `[RD+]`). El plan de descargas sigue igual pero no
   debe depender de una API de caché. API: 250 peticiones/min. Sus términos registran las conexiones
   para detectar cuentas compartidas, sin un límite numérico; «una IP a la vez» es conocimiento de la
   comunidad, no regla oficial. El riesgo de §10 se mantiene. <https://real-debrid.com/terms>
4. **Trakt, menos atractivo:** cuentas gratis con 1 app conectada (desde jul 2026), listas de 100;
   tokens de 7 días; sus términos prohíben apps que «promuevan la piratería»; hay reportes (sin
   confirmar) de que crear apps de API pasó a ser solo VIP. Refuerza «Stremio manda, Trakt después».

### Confirmado sin cambios

- API de Stremio (código de stremio-core actual): `addonCollectionGet`, `datastoreGet/Put` con la
  colección `libraryItem`, como usa Orbital. Stremio sacó un IPA oficial para instalar por fuera
  (feb 2026) tras retirar Stremio Lite de la App Store.
- Nuvio se reescribió en Kotlin Multiplatform (GPL-3.0) con MPVKit; se instala por AltStore/SideStore
  y TestFlight. <https://github.com/NuvioMedia/NuvioMobile>
- Instalación: Apple ID gratis = 7 días y 3 apps; cuenta de pago = 1 año; TestFlight interno hasta 100
  personas, 90 días por versión. La regla 5.2.3 de la App Store se confirma.
- Descargas: `URLSession` en segundo plano sobrevive a la suspensión (no a cerrar la app a la fuerza);
  iOS 26 añade `BGContinuedProcessingTask` con Live Activity para descargas iniciadas por ti.
- Infuse 8.5.6: descargas nativas en segundo plano (8.5.1), Live Activity de descargas, saltar intro y
  créditos por separado, Trakt gratis, sincronía por iCloud en Pro. Buenas ideas para §7.
