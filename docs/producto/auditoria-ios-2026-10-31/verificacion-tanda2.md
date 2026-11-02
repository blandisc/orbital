# Verificación de la tanda 2 · auditor autónomo (1 nov 2026)

Auditor sobre `43eef232` (main). No arregla nada: revisa en el código lo que `estado.md` da por hecho en la tanda 2
(rendimiento y arquitectura) y los cambios de otras sesiones en `ios/` desde `368bba5a` (sobre todo `a9fdc584`, el zoom al
abrir la ficha, y `43eef232`, filtros de Colecciones); corre las pruebas e intenta romper la app en el simulador. Las tandas
1 y 3 ya las revisó `verificacion.md` y no se repiten.

## Resumen para decidir (5 líneas)

1. **La app no se cayó ni una vez** en ~1 h 30 min de maltrato en tres simuladores (iPhone con iOS 26.3 y 27, iPad): fichas en ráfaga con el zoom nuevo, «atrás» a media animación, reproductor abrir y cerrar de golpe, fondo y regreso seguidos, cambiar el idioma, Colecciones con filtros. Ninguna bitácora de cierre nueva.
2. **La tanda 2 está hecha de verdad**: 11 de 12 temas cumplen y 1 queda a medias (A2). Lo que estado.md dice que no se hizo (B1, el resto de B2) sigue sin hacerse, tal cual.
3. **Inicio gasta menos de lo prometido**: 4.0–4.3 % de CPU quieto (el commit decía ~6 %; antes ~18 %).
4. **Dos fallos nuevos que se ven**: en el reproductor, «Siguiente» ya no aparece solo al llegar al 90 % con los controles a la vista (sale hasta que vuelves a tocar); y en el iPad de pie, tocar un póster del Top 10 de Buscar no abre la ficha (antes del zoom nuevo sí abría).
5. **Pruebas y CI en verde**: 917 pruebas del paquete, la app compila en Debug y Release, las últimas 13 corridas de GitHub en main pasaron. La decisión nueva de Fernando sobre las temporadas (desplegable en la ficha) entra al encargo de arreglos.

## Pruebas corridas

| Qué | Resultado |
|---|---|
| `swift test` completo (ios/OrbitalCore, copia en /tmp de `43eef232`) | **Verde**: 917 pruebas (452 OrbitalModels + 455 OrbitalCore + 10 Addons), 0 fallas. |
| App Debug (`build-for-testing`, Orbital QA) | **TEST BUILD SUCCEEDED**. |
| App Release (`generic/platform=iOS Simulator`) | **BUILD SUCCEEDED**. |
| CI de GitHub (`gh run list --branch main`) | **Verde** las 13 corridas de `368bba5a` a `43eef232` (la última, 41259842720). La inestable de Mi lista no salió en esta racha, pero la causa sigue en el código (`OrbitalModels/TitleModel.swift:179`). |
| `ChaosRegressionUITests`, Orbital QA (iOS 26.3) | **9/10**. Solo falla `testMosaicoEnRafaga` (la prueba busca `otherElements["mosaic"]`; ya documentado en verificacion.md). |
| `ChaosRegressionUITests`, iPhone 17 Pro (iOS 27) | **9/10**, la misma. |
| Escenarios del auditor (`AuditorT2UITests`, temporal, no se commitea; copia en `/tmp/orbital-evidencia/auditor-t2/`) | iOS 26.3 y 27: pasan zoom en ráfaga, «atrás» a media animación, Explorar entrando y saliendo, fondo y regreso ×9, idioma ida y vuelta ×4, Colecciones con filtros, reproductor (barra avanza, giro, fondo) y reproductor de golpe ×6. Falla «Siguiente al 90 %» (fallo real, abajo). «Mantener durante el zoom» se cortó por la prueba (no halló póster en la 2.ª vuelta) sin cierres. |
| `IPadLayoutUITests`, Orbital QA iPad (iOS 27) | **5/6** (más el recorrido en horizontal, que se salta sin `ORBITAL_HANDSHAKE`). Falla `testTitleOpensInTheSidePanel` en vertical, 3 de 3: fallo real (abajo). |
| Desplazar rápido en el iPad (A3) | **Pasa**: 36 deslizones rápidos en Inicio y el panel de la ficha sale del póster tocado después. |
| Bitácoras `~/Library/Logs/DiagnosticReports/Orbital-*.ips` | **Ninguna nueva** (la última sigue siendo la de R1, 31 oct). |

## CPU de Inicio en reposo

«Orbital QA» (iOS 26.3), app Debug, Inicio quieto 20 s sin `-demo-no-idle`, `-demo -demo-trakt -demo-tmdb -demo-console
-demo-airings -demo-because -demo-mode lists -demo-tab 0 -demo-appearance dark`, medido con `top` cada segundo.

| | CPU |
|---|---|
| Antes de la tanda 2 (estado.md / commit 0ec0af48) | 17.8 % y 18.1 % |
| Después según el commit | 6.5 % y 6.1 % |
| **Medido ahora** | **4.3 % y 4.0 %** |

La memoria de `top` (~155 MB) no se compara con los ~430 MB del commit: midieron cosas distintas (`top` da la memoria
propia; el commit, `ps`). Captura: `/tmp/orbital-evidencia/auditor-t2/01-inicio-cpu.png`.

## Lo que rompí

### 1. «Siguiente» no aparece solo al cruzar el 90 % (regresión de A2)

- **Pasos**: abrir un episodio (`-demo -demo-title series:tt0386676 -demo-open play -demo-player-portrait`), tocar para ver los
  controles y arrastrar la barra a ~8:59 de 10:00. Con los controles a la vista, el video pasa 9:00 y 9:01 y **no sale
  «Siguiente · T1 E2»**; al tocar la pantalla otra vez, sale. iOS 26.3 y 27 (`siguiente-bitacora.log`: `8:59 next=false |
  9:00 next=false | 9:01 next=false … tras tocar=true`).
- **Causa**: `offersSkipOrNext` y `nextEpisode` (`Screens/PlayerScreen+Panel.swift:402-409`) leen `model.snapshot.position`
  en el cuerpo de la pantalla entera; desde A2 el modelo ya no avisa cuando solo cambia la posición
  (`OrbitalModels/PlayerModel.swift:52-56`), así que la pantalla no se vuelve a pintar al cruzar el 90 %. Lo mismo pasa con
  quien lea `snapshot.position` fuera de `PlayerTimeReader`. Arreglo sugerido: que el modelo calcule «ya pasó el 90 %» como
  propiedad que sí avisa (cambia una vez), o leerlo dentro de `PlayerTimeReader`.

### 2. iPad de pie: el Top 10 de Buscar no abre la ficha (regresión de `a9fdc584`)

- **Pasos**: Orbital QA iPad en vertical, `-demo -demo-no-idle -demo-tab 2`. Tocar cualquiera de los pósters de «Lo más popular
  hoy» (Puesto 1, 2 o 3): no pasa nada. Un póster dentro de un género sí abre el panel, y en horizontal también abre.
- **Acotado**: misma prueba temporal en tres versiones: `368bba5a` abre 3/3, `bdab51b0` (justo antes del zoom) abre 3/3,
  `a9fdc584` abre 0/3 (bitácoras `ui-ipad-old.log`, `ui-ipad-mid.log`, `ui-ipad-zoom.log`). No es A3 (`a408ccd1`).
  Sospecha: el `simultaneousGesture(TapGesture())` o el `matchedTransitionSource` con recorte y sombra que el zoom pone en
  cada póster (`Design/Projection.swift:255-266`) le gana el toque al botón del panel (`Design/TitlePanel.swift:31`) en esa fila;
  el reflejo no recibe toques (`allowsHitTesting(false)`, `Screens/HomeMark.swift:180`). Captura: `ipad/Orbital_QA_iPad-ipad-v-1.png`.
  `IPadLayoutUITests.testTitleOpensInTheSidePanel` ya lo detecta (rojo en vertical).

### Lo demás (sin fallos de la app)

| Escenario | Resultado |
|---|---|
| Fichas en ráfaga con el zoom | 8 veces tocar y «atrás» a los 0.1–0.3 s; tres pósters seguidos; el mismo póster 6 veces. Sin cierres ni pantallas vacías. |
| Mantener presionado durante el zoom | Sin cierres; el menú o la ficha salen bien. Corte de la prueba en la 2.ª vuelta (no halló póster). |
| Explorar entrando y saliendo | 12 cambios de pestaña en ráfaga, entrar al muro y salir 5 veces cambiando de pestaña a medias, desplazar rápido. Sin cierres. |
| Fondo y regreso | 6 seguidos en Inicio (0.3–1.5 s afuera) y 3 en Explorar: siempre vuelve al frente con contenido. |
| Reproductor | La barra avanza (0:05 → 0:08), sigue tras girar y tras ir al fondo (0:20 → 0:25). Abrir y cerrar de golpe 6 veces, una girando: sin cierres. |
| Idioma | Español ↔ English 4 veces seguidas: la app sigue y regresa en español. Región no se probó por la interfaz (el selector está en otra página); B7 tiene prueba unitaria. |
| Colecciones con filtros (iOS 27) | Género, década y calificación con sus cápsulas: «Drama + 2010s» deja 10, «Comedia + 2010s» deja 3, el contador del grupo se ajusta. Detalle: la barra de abajo «La más reciente que te falta: Anora» ignora el filtro (Anora es de 2024). |

Notas sin fallo: la demo responde con el reparto de *The Office* a cualquier ficha de TMDB (por eso «Corpus Christi» sale con
Steve Carell); en iOS 27 un toque al centro cayó en la barra y adelantó el video: fue la prueba.

## Veredicto por hallazgo

Rutas relativas a `ios/App/Sources` salvo que digan `OrbitalCore`/`OrbitalModels`.

### Tanda 2

| Hallazgo | Veredicto | Evidencia |
|---|---|---|
| R3 + C7 consumo de Inicio | **cumple** | `Screens/HomeChannels.swift:83` (`ChannelDrift` solo si se ve y la app está al frente, 30 cuadros); `Design/Sky.swift:55-70` y `SkyPace` (6 cuadros quieto, 12 al inclinar). Medido: 4.0–4.3 %. Sin prueba unitaria (es dibujo), como declara. |
| A2 reloj del reproductor | **a medias** | `OrbitalModels/PlayerEngine.swift:27-48` (`PlayerTime`), `PlayerModel.swift:52-56`; ~30 `didSet` comparan. `PlayerTimeTests` (2). Barra, iPod y «ya llegó» usan `PlayerTimeReader` (`Screens/PlayerScreen+Panel.swift:450`, `PlayerScreen.swift:435`, `PlayerScreen+IPod.swift:29`). **Pero** «Siguiente» quedó leyendo la posición fuera del reloj (fallo 1). |
| A3 marco del póster (iPad/Mac) | **cumple** | `Design/TitlePanel.swift:28-44` (`FrameBox`). `TitlePanelOpener`, `RemoteOpener` y `TallArtLookup` Equatable (`TitlePanel.swift:10`, `RootView.swift:182`, `TallArtPicker.swift:14`). Desplazar rápido en el iPad pasa. El fallo 2 no viene de aquí. |
| C5 volver a la app | **cumple** | `OrbitalModels/ForegroundRefresh.swift`; `Screens/RootView.swift:147-155`; la biblioteca al abrir solo en `.task` (`:119`). `ForegroundRefreshTests` (5). |
| C6 estantes guardados | **cumple** | `OrbitalModels/ParaTiModel.swift:113-126, :431-436`; se borran al cambiar estantes, listas, tipo, carga o lo cargado. `ShelfPlanTests.testLosEstantesVisiblesGuardadosSeRenuevanAlCargar`. |
| B7 un solo aviso | **cumple** | `OrbitalModels/Services.swift:111-121` (`batched`), `SettingsModel.swift:66-80`. `ScreenModelsTests.testCambiarElIdiomaAvisaUnaSolaVez` (`:489`). La otra mitad (`services` registra lectura) sigue, como dice estado.md. |
| B8 muro de Explorar | **cumple** | `Design/ParaTiB.swift:346-366` (`addChild` al entrar a la ventana, se suelta al salir); `rootView` solo si cambia la clave (`:310`). |
| C4 `endObserver` | **cumple** | `Platform/PlayerEngines.swift:169, 201-204` (deinit) y `:212` (se quita antes de registrar otro). |
| B2 primera parte | **cumple** | `PersonModel` y `YearReviewModel` con pruebas (`PersonModelTests` 2, `YearReviewModelTests` 2); `PersonView`/`YearView` ya no llaman a TMDB ni a Para ti. Resto chico: `Screens/PersonView.swift:20` (la vista que abre una película de la persona) sigue llamando `TitleModel.imdbID(…, services: env.services)`. |
| Calendario degradado | **cumple** | `OrbitalModels/ReleaseCalendarModel.swift` (`problem: Degraded?`), `Screens/ReleaseCalendarView.swift` (`DegradedNotice` con «Reintentar» solo si el día está vacío). `ReleaseCalendarModelTests.testTraktCaidoSeDiceYAlVolverSeQuita`. |
| Estudios sin logo | **cumple** | `OrbitalModels/CollectionsModel.swift:95-108`; `testUnEstudioSinLogoNoSeVuelveAPreguntar`. Nota: «sin logo» se guarda para siempre en disco; si TMDB lo agrega después, no se vuelve a pedir. |
| DebouncedWriteTests estable | **cumple** | Espera hasta 2 s; verde en esta corrida y en la CI. |

### Lo que estado.md declara como no hecho: confirmado

- **B1**: `PlayerScreen` sigue en 7 archivos (2,426 líneas) con 43 `@State` en `Screens/PlayerScreen.swift`.
- **B2, el resto**: `Screens/PlayerScreen+Controles.swift:169, :317, :323` llaman servicios; `DownloadsModel(…)` se arma en
  `AppEnvironment.swift:154`, `Screens/DownloadsView.swift:20`, `PlayerScreen.swift:45` y `PlayerScreen+CicloDeVida.swift:51`;
  51 `AppEnvironment.shared` en Screens/ y Design/. `DecideView` ya no llama servicios en la línea 272 (solo lee `configured`).

### Cambios de otras sesiones en ios/

| Commit | Veredicto | Evidencia |
|---|---|---|
| `a9fdc584` zoom desde el póster | **no cumple** (por el iPad) | En iPhone funciona y aguanta la ráfaga. Rompe el Top 10 de Buscar en el iPad de pie (fallo 2). Además, el zoom solo sabe de qué póster salir si lo tocaste con el dedo (`Design/Projection.swift:266`); con el menú largo, VoiceOver o teclado sale desde abajo (así lo dice su comentario). |
| `43eef232` filtros de Colecciones | **cumple** | `Screens/RepisaView.swift:125-202`, `CollectionsModel.imdbFacts` con `testLosGenerosLleganConLaCalificacion`. Probado en iOS 27. Detalle: la barra «La más reciente que te falta» no respeta el filtro. TV pendiente, anotada en el registro de paridad. |
| `bdab51b0` búsqueda avanzada | sin revisar a fondo | Solo por sus pruebas (verdes). |

### Decisión nueva de Fernando (1 nov 2026): temporadas

Las cápsulas «T1, T2…» van **solo en el reproductor** (panel de próximos capítulos). En la ficha de la serie va la **lista
desplegable**. Hoy `DSSeasonPicker` (cápsulas) está en la ficha (`Screens/TitleView.swift:343`), Mi media
(`Screens/MiMediaView.swift:312`) y la hoja de episodios (`Screens/EpisodePickerSheet.swift:50`), además del reproductor
(`Design/EpisodesPanel.swift:33`): **no cumple**. Esto corrige la nota del 31 oct en `README.md` y D8 de `hallazgos.md`.

## Qué haría después (para la tanda 6)

1. Fallo 2 (iPad, Top 10 de Buscar) y fallo 1 («Siguiente»), con prueba que falle antes.
2. Temporadas: desplegable en la ficha (y en Mi media y la hoja de episodios), cápsulas solo en el reproductor.
3. Lo pendiente de `verificacion.md`: carrera de `TitleModel.swift:179`, «Charging», `testMosaicoEnRafaga`, regla 13 y tokens sin
   uso, reglas 5/6/8/12 sin exención `Remote*` (D4, D5, D9, D11) y una prueba de los `.contextMenu`.
4. La barra «La más reciente que te falta» con el filtro de Colecciones.
