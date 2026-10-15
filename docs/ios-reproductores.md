# Reproductor para la app de iPhone: investigación (2026-10-12)

Complementa `docs/ios-companera.md` (§4, §7 y §14). Cuatro investigaciones web independientes: VLC,
Infuse, AetherEngine y otros candidatos.

> **Cómo leer las cifras.** Las páginas se leyeron con una herramienta que resume con un modelo pequeño:
> las citas son resúmenes, no texto literal. Lo marcado **(sin confirmar)** no se pudo comprobar en una
> fuente primaria. Los precios no se verificaron en la tienda de EE. UU.

**Requisito del usuario:** en iOS solo se usan fuentes con enlace `url` http(s) (Real-Debrid). Las
fuentes `infoHash` se ocultan.

---

## 1. Resumen

| | Devuelve posición | Guardado mientras ves | Veredicto |
|---|---|---|---|
| **Infuse** (externo) | Sí, al cerrar (`position`) | No | **Versión 1**, con prueba previa |
| **SenPlayer** (externo) | Según su historial de versiones, sí (sin documentar) | Sin confirmar | Probar junto a Infuse |
| **VLC** (externo) | **No** (el callback no lleva datos) | No | Descartado para el avance |
| **AetherEngine** (embebido) | Sí, `clock` a ~10 Hz | Sí | Primer motor propio a probar |
| **SwiftVLC / VLCKit** (embebido) | Sí | Sí | Plan B |
| Outplayer, nPlayer | No encontrado | — | Descartados |
| MPVKit, FFmpegKit, KSPlayer | — | — | Descartados |

## 2. Infuse (externo)

**Confirmado** (<https://support.firecore.com/hc/en-us/articles/215090997-API-for-Third-Party-Apps>):
- `infuse://x-callback-url/play?url=…` con `position` (segundos enteros), `filename`, `sub` (un solo
  subtítulo), `x-success`, `x-error`. Varias `url` forman una lista temporal. Desde Infuse 8.4.7.
- `x-success` se llama **una vez**, al terminar la lista o cerrar el reproductor, con `lastPlayedUrl` y
  `position`. **No devuelve la duración.** `x-error` devuelve `errorCode`, `errorMessage`, `failedUrl`.
- `save` con `download=1` baja un enlace a Infuse para ver sin conexión; su `x-success` no devuelve
  parámetros, así que el avance de lo descargado no vuelve a nuestra app.
- La URL hay que codificarla **por completo**; una URL larga con `?` y `&` mal codificada falló
  (<https://community.firecore.com/t/x-callback-url-not-working/46195>). En Swift: un juego de caracteres
  permitidos casi vacío, no `.urlQueryAllowed`.
- Si el MKV trae subtítulos internos, Infuse ignora el `sub` externo
  (<https://community.firecore.com/t/subtitle-parameter-in-x-callback-url-does-not-work-when-the-video-have-internal-subtitle/50505>).
- Fallo reportado en mayo de 2026: en videos ya vistos al 100 %, el callback da progreso 1.0 aunque se
  pare a la mitad (<https://community.firecore.com/t/additions-for-x-callback-url-support/58103>). Ese
  hilo habla de `progress`, la documentación de `position`: **contradicción sin resolver**.
- Pro: 1,99 USD/mes, 16,99/año o 99,99 de por vida (<https://firecore.com/infuse>, **sin verificar en la
  tienda**). Dolby Vision y Atmos son de Pro; AirPlay también.

**Sin confirmar (hay que probarlo en el iPhone):** si reproducir una URL por la API exige Pro; si acepta
las redirecciones 302 de Real-Debrid; si `x-success` llega al matar la app, al pasar a segundo plano o al
terminar el video; qué `position` llega al terminar; límite de longitud de URL; si Infuse reanuda solo.

**Valoración:** viable pero frágil. El avance es de «mejor esfuerzo»: solo llega si Infuse llama al
callback, no hay guardados intermedios y falta la duración (se toma de Cinemeta/ficha).

## 3. VLC

**VLC para iOS como app externa: descartado para el avance.** Leído en el código
(`Sources/Helpers/Network/URLHandler.swift`, `VLCPlaybackService.m`, espejo de GitHub):
- Acciones `stream` y `download`; parámetros `url`, `sub`, `filename`, `x-success`, `x-error`, `loop`,
  `shuffle`. Sin posición inicial ni lista.
- `x-success` abre la URL **tal cual, sin parámetros**: no hay posición ni duración. Se llama al cerrar.
- Versión 3.7.3 en la App Store, gratis. La 4.0 (PiP, HDR) aún no está publicada.

**VLCKit embebido:** da `time`, `position` y `length`. Estable 3.7.4 (libvlc 3.0.x); VLCKit 4 sigue en
alfa (4.0.0a21; PiP y mejor gestión de pistas, API distinta). LGPL-2.1. **Sin confirmar:** Dolby Vision,
HDR, PGS en MKV, comportamiento con streams http largos (el tracker de VideoLAN bloquea el acceso
automático). **SwiftVLC** (<https://github.com/harflabs/SwiftVLC>, MIT, libVLC 4, 1.0 publicada, iOS 18+,
PiP en iOS) es una envoltura Swift más cómoda; Dolby Vision, PGS y AirPlay sin confirmar.

## 4. AetherEngine (embebido)

<https://github.com/superuser404notfound/AetherEngine>

**Confirmado:**
- LGPL-3.0 con excepción para tiendas y TestFlight (solo tengo un resumen: leer el `LICENSE` entero).
  Para uso personal sin redistribuir, la LGPL no obliga a más (inferencia, no asesoría legal).
- Creado el 2026-04-12. 7.35.1 (2026-10-12), 16 versiones entre el 7 y el 12 de octubre. 218 estrellas,
  314 incidencias cerradas y 65 abiertas. Un autor principal; el README lo describe como programado con
  Claude. CI compila en simuladores iOS pero **no ejecuta pruebas en iOS ni en dispositivo**.
- API: `engine.load(url:startPosition:options:)` con `httpHeaders`; `play/pause/seek`; estado y tiempo
  con Combine (`$state`, `clock.$currentTime` ~10 Hz, `$duration`); pistas de audio y subtítulos;
  subtítulos externos; capítulos; errores tipados (`PlaybackErrorKind`); vista `AetherPlayerSurface`.
- Formatos: MKV/MP4, H.264/HEVC/AV1, HDR10/HDR10+/HLG, Dolby Vision P5, P7 (convertido a 8.1), P8.1/8.4;
  PGS por OCR o como imagen; AC3/EAC3/Atmos EAC3 sin tocar. **TrueHD y DTS/DTS-HD se convierten con
  pérdida** (EAC3 5.1 por defecto, FLAC opcional).
- PiP en la ruta nativa y en la de software. 302 de CDN: manejadas (incidencias #307, #323, #584).
- Lo usan Moonfin (migró de mpv en 2.3.2; la 2.4.0 arregló problemas iniciales), Sodalite y otras. Ninguna
  es de Stremio/Real-Debrid.

**Riesgos:**
1. Proyecto joven, un autor, muchos parches seguidos. **Fijar el tag exacto**, nunca `from:`.
2. FFmpeg viene en binarios ya compilados dentro de `FFmpegBuild` (otro repo del mismo autor), sin
   checksum independiente. Verificable solo recompilando con su `build.sh`.
3. El motor abre un servidor HTTP local en todas las interfaces (puerto efímero, token de 128 bits) para
   AirPlay.
4. Incidencia #752 (abierta): fallo de enlace desde la 7.34.0. #255 y #400: cierres por force-unwrap.
5. Pide iOS 18+ y una toolchain muy nueva (CI con Xcode 27): comprobar con tu Xcode.
6. Sin retardo/tamaño de subtítulos (se construye encima), sin cifras de batería, temperatura ni
   memoria en iPhone, y ninguna prueba con enlaces de Real-Debrid de 4K.
7. P7 con capa FEL: se descarta la capa de mejora.

## 5. Otros candidatos

- **SenPlayer** (<https://apps.apple.com/us/app/senplayer-media-player/id6443975850>): gratis; Pro de pago
  único (~10 a 13 USD). Su historial de versiones dice (v6.1.2) que acepta la posición de inicio por URL
  scheme y «devuelve el tiempo actual al salir»; v6.2.0, Dolby Vision nativo. **Parámetros exactos sin
  documentar.** Candidato externo a probar junto a Infuse.
- **Outplayer, nPlayer:** esquema sin documentación oficial y sin retorno de posición encontrado.
- **KSPlayer:** GPL, o LGPL de pago (mínimo 15 USD/mes y adelanto). Descartado.
- **MPVKit:** el autor lo califica de «solo para aprender» y recomienda AetherEngine. Descartado.
- **FFmpegKit:** retirado. Descartado.
- **AVPlayer + remux propio** (ejemplo: GMPlayer, MIT, 5 commits): AetherEngine ya lo hace. No se
  construye desde cero.
- **Swiftfin** muestra que ningún motor cubre todo: el nativo (AVPlayer) da PiP, AirPlay y Dolby Vision
  completos pero no abre MKV ni PGS; el de VLC abre todo pero no da DV P5 ni PiP.
- **StremioX** (<https://github.com/OrigamiSpace/StremioX>, GPL-3.0) reproduce con libmpv y guarda el
  progreso en `api.strem.io` mientras ves: el modelo que queremos a largo plazo.

## 6. Recomendación

1. **Versión 1: Infuse**, tratando la posición como mejor esfuerzo y pasando siempre `position` al
   reanudar. Guardar localmente la posición enviada y la hora de inicio como respaldo.
2. **En la misma prueba, SenPlayer**: si devuelve la posición y el costo es aceptable, queda como segundo
   `ExternalPlayer`.
3. **Descargas en la versión 1**: `save` + `download=1` de Infuse da ver sin conexión, pero sin avance.
   Decisión pendiente (§8).
4. **Reproductor propio: probar AetherEngine** (tag fijo) con el guion de la §7. Si falla, **SwiftVLC**.
5. Un `PlayerEngine` común para que todo sea intercambiable.

## 7. Pruebas antes de decidir (en un iPhone real, build Release)

**A. Reproductores externos** (Infuse gratis y SenPlayer, con una URL de Real-Debrid con 302):
1. ¿Reproduce? ¿Pide Pro?
2. ¿`x-success` llega al terminar, al cerrar con la X, al pasar a segundo plano y al matar la app? ¿Con
   qué `position`? ¿Hay duración?
3. ¿Respeta `position` y `sub`? ¿Y con una URL de más de 2000 caracteres?

**B. AetherEngine** (tag 7.35.1):
1. Archivos: MP4 1080p; MKV 1080p HEVC con SRT/ASS/PGS y 3 audios; MKV 4K HDR10; 4K Dolby Vision P8.1 y
   P5; REMUX P7; MKV con TrueHD Atmos y DTS-HD MA; un enlace caducado.
2. Medir: primer fotograma, 20 seeks, cambio de pista, reanudar desde `startPosition`, PiP, bloqueo de
   pantalla 1 y 5 min, AirPlay con subtítulos.
3. Fiabilidad del avance: posición cada 60 s durante 2 h y un corte de red de 10 a 30 s (incidencia #115,
   salto atrás).
4. Sesión de 90 min en 4K HDR: temperatura, batería y memoria, frente a AVPlayer nativo.
5. **Descartar** si hay cierres, seeks de más de 3 s con frecuencia, pérdida de imagen o audio al volver
   del segundo plano, o estado térmico «serious» en menos de 30 min.

## 8. Decisiones pendientes

- ¿Descargas con Infuse en la versión 1 (sin avance) o esperar al reproductor propio?
- Pagar Infuse Pro (o SenPlayer Pro) si la prueba A muestra que hace falta.
- Compilar AetherEngine y FFmpegBuild desde fuente (más seguro) o aceptar los binarios del repo.

## 9. Contradicciones sin resolver

- Infuse: `progress` (hilo de mayo de 2026) frente a `position` (documentación).
- Swiftfin: unas fuentes dicen VLCKit, su documentación actual dice SwiftVLC (se tomó la documentación).
- AetherEngine: 3 585 commits (README) frente a 986 (Swift Package Index, fecha desconocida).
