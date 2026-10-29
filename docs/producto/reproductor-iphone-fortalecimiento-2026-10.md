# Fortalecer el reproductor del iPhone (revisión del 28 oct 2026)

Revisión de UX, UI y técnica hecha con un agente fresco (modelo Fable) sobre `main` en `d497aa71`, solo leyendo el código
(sin compilar ni simulador). Lo marcado «supuesto» no se verificó. Rutas: `PlayerScreen.swift` = PS, `PlayerModel.swift` = PM,
`PlayerPanel.swift` = PP, `AetherEnginePlayer.swift` = AEP, `Tokens.swift` = TK.

## Diagnóstico en una frase

El modelo (`PlayerModel`, ~1 500 líneas, ~70 pruebas) es sano. La fragilidad vive en la pantalla (`PlayerScreen`, ~2 400 líneas,
~110 `@State`, 12 temporizadores): ahí se reinterpreta el estado del motor con retardos sueltos (`loadingShown`, `glyphPlaying`,
`frozenFrame`, `knownAspect`, zoom por sentido) sin pruebas, y cada síntoma se arregló con otro temporizador. Se sana moviendo esa
«verdad derivada» a un objeto con reloj inyectado y pruebas, y partiendo la pantalla por responsabilidades.

## Lista priorizada

| # | P | Problema | Qué siente el usuario | Arreglo | Esfuerzo | Riesgo |
|---|---|---|---|---|---|---|
| 1 | P0 | ±10/play y controles en dos bloques con transiciones distintas (PS 287–296) | ±10/play flotando sin barras | Un solo bloque de controles con el transport dentro | S | Bajo · rápido |
| 2 | P0 | Pausa no funciona mientras carga (PM `togglePlay`) | «Le doy pausa y sigue cargando» | Pausar también en búfer o con petición de play viva | S | Bajo · rápido |
| 3 | P0 | Volver de segundo plano durante un cambio de versión no rearma (PM `appDidBecomeActive`) | Pantalla negra, play no responde | No consumir `backgrounded` si `!acceptingSnapshots`; reintentar | S | Medio |
| 4 | P0 | Carga, glifo, controles y posición calculados en la vista sin pruebas | Cada arreglo rompe otro | `PlayerPresentation` (`@Observable`, reloj inyectado) + pruebas | M | Medio |
| 5 | P1 | «Probamos otra versión» no se avisa en la vista | Cambia de versión a escondidas | Aviso «Probando otra versión (2/4)» | S | Bajo · rápido |
| 6 | P1 | Un toque mientras los controles se desvanecen los apaga | «Toqué y no salió nada» | Si se estaban escondiendo, mostrar en vez de alternar | S | Bajo · rápido |
| 7 | P1 | En horizontal la barra cambia de ancho con «Saltar intro»/«Siguiente» | El punto brinca bajo el dedo | Ancho reservado o botones encima de la barra | S | Bajo · rápido |
| 8 | P1 | Panel de 420 pt fijo en horizontal | iPhone SE/mini: video de ~180 pt (calculado) | `min(420, ancho × 0.55)` u hoja en pantallas chicas | S | Bajo |
| 9 | P1 | Zoom en cuatro copias (vista, Ajustes, motor, cuadro congelado) | Bugs de zoom a la próxima | Una sola fuente por orientación y una sola llamada al motor | M | Medio |
| 10 | P1 | `knownAspect` se borra al pasar de episodio | Un 4:3 brinca de alto al cambiar de episodio | Guardarla por video en el modelo | S | Bajo · rápido |
| 11 | P1 | 12 temporizadores sin cancelar al cerrar | Motor retenido, avisos tardíos | Cancelarlos todos al salir; `stop()` del motor al soltarlo | S | Bajo · rápido |
| 12 | P1 | Sin pruebas de segundo plano ni de giro con pellizco | Regresiones silenciosas | 5 pruebas del modelo + UITests de fondo y pellizco | M | Bajo |
| 13 | P2 | Dos burbujas de búsqueda a distinta altura | Posición distinta según cómo buscas | Una sola posición | S | Bajo · rápido |
| 14 | P2 | La tarjeta «Siguiente» empuja la barra en vertical | La barra se mueve al final | Reservar alto o ponerla sobre el video | S | Bajo |
| 15 | P2 | ×2 fijo sigue en el siguiente episodio | El siguiente arranca a 2× | Decisión de producto | S | Bajo |
| 16 | P2 | Avisos en 6 lugares distintos | Ruido visual | Un centro de avisos con dos lugares fijos | M | Medio |
| 17 | P2 | ±10 sin fondo sobre imagen clara | Se pierden en cielo blanco | Contorno o disco de vidrio tenue | S | Bajo |
| 18 | P2 | La ruta de software del motor (MKV raros) no se puede probar | Bugs que solo salen en el iPhone | Bandera demo + MKV de prueba | S | Bajo · rápido |
| 19 | P2 | `PlayerScreen` de 2 400 líneas | Cambios lentos y arriesgados | Partirla por piezas (abajo) | L | Medio |
| 20 | P2 | El error no ofrece «Elegir otra versión» | Hay que cerrar y reabrir | Botón directo si hay otras versiones | S | Bajo |

## Plan por etapas

1. **Arreglos rápidos sin tocar diseño:** 1, 2, 5, 6, 7, 10, 11, 18.
2. **La base:** `PlayerPresentation` con pruebas (4), segundo plano (3, 12), zoom único (9).
3. **Layout único** (`PlayerLayout` puro con pruebas en SE/mini/Pro Max) y centro de avisos: 8, 13, 14, 16.
4. **Partir la pantalla** (una pieza por cambio: iPod → panel → controles → gestos → ciclo de vida) y pulido: 15, 17, 19, 20.

No se reescriben gestos, modelo ni motor, ni se tocan decisiones de diseño ya tomadas.

## Cómo partir `PlayerScreen`

| Pieza | Qué se lleva | Con pruebas sin UI |
|---|---|---|
| `PlayerPresentation` | carga, glifo, controles visibles, posición mostrada, proporción por video | Sí |
| `PlayerLayout` | rect del video, límites en vertical, posiciones de indicador, burbuja y píldora ×2 | Sí |
| `PlayerGestureController` | ejes, brillo/volumen, ×2, doble toque, pellizco, mover el video | Parcial |
| `NoticeCenter` | avisos, toasts, candado, destellos | Sí |
| `PlayerChrome` | barra de arriba, «⋯», transport, barra de avance, siguiente, saltar intro | UITests |
| `PlayerDock` | audio y subtítulos, versión, episodios, sincronía | UITests |
| `IPodMode` | modo iPod | — |
| `PlayerLifecycle` | primer plano, cuadro congelado, PiP, Now Playing, giro | Parcial |

## Estado al 29 oct 2026 (versión 1126 en el iPhone)

Después de aplicar el reporte aparecieron fallas en el iPhone; se reprodujeron en el simulador y quedaron cerradas con su prueba:

| Falla | Causa | Arreglo |
|---|---|---|
| Cargando para siempre (3 min o más) | `tick()` esperaba la carga; si el motor se colgaba, nadie revisaba el plazo | El reloj nunca espera: lo largo corre en `transition`; toda carga tiene plazo de 45 s |
| Cambiar de versión solo enseñaba la carga | La nueva quedaba detrás de la trabada | `engine.stop()` antes de cargar (también al volver a pedirla) |
| Siguiente episodio automático trabado | `tick` esperaba `advance` | Ya no lo espera |
| Un «suena» viejo contaba para la versión nueva | `acceptingSnapshots` no distinguía cargas | Se ignora el motor hasta que abre el archivo (`engineOpened`) |
| Al volver, el motor se colgaba rearmando | El plazo empezaba después de rearmar | Empieza antes; búfer de más de 20 s se pide otra vez |
| Pantalla negra con franja de color arriba | El fondo ambiente medía 1383 puntos y estiraba la pantalla | Se quitó el fondo ambiente (fondo negro, pedido de Fernando) |
| «Audio y subtítulos» arriba con espacio muerto | Tres copias del panel con su propio renglón abierto | El renglón abierto vive en la pantalla (`dockOpens`) |
| Controles de abajo fuera de la pantalla | Lugar fijo de 260 puntos | Se miden y suben lo justo |

Pruebas: `PlayerModelTests` (motor que se cuelga en carga y al rearmar) y `PlayerStuckUITests` con
`scripts/ios_video_server.py … v=1` (una versión que nunca contesta); todo junto en `scripts/ios_software_path.sh`.

Tiempo de carga medido en el iPhone: 3 a 4 s. Los 28 s de una noche fueron de Real-Debrid preparando el archivo. No sirve medir
el servidor con una segunda conexión al mismo archivo: Real-Debrid la hace esperar y compite con el video.

## 29 oct, segunda pasada: carga → pausa → carga, y la ruleta que giraba sola

| Falla | Causa | Arreglo |
|---|---|---|
| El botón grande hacía carga → pausa → carga → pausa en cada video | El motor dice «suena» a los 3 s con casi nada en el búfer y enseguida se detiene a llenarlo (el video avanzaba 3 s en 9 s de reloj); además, cambiar la pista de audio al arrancar recarga todo el video en AetherEngine (`selectAudioTrack` → `reloadWithAudioOverride`) | La carga no se quita con el primer «suena» sino cuando el video de verdad corre: 2 s avanzados (`PlayerModel.playbackSettled`), o en cuanto lo pausas. Lo que pase en medio (búfer, recarga, salto) sigue siendo la misma carga |
| Con el video en la ventana de PiP (o al salir de la app) empezaban episodios de Los Simpson al azar debajo | La ruleta vuelve a «aparecer» con el reproductor encima (el sistema la vuelve a presentar) y su `.task` giraba otra vez: a los ~5 s (la animación completa) abría otro episodio al azar en lugar del que sonaba. En la bitácora: «a segundo plano» y 5 s después «abrir series tt0096697:10:20» | La ruleta gira una sola vez: no gira si ya hay un episodio encima ni cuando se está cerrando |

Pruebas: `PlayerPresentationTests` (`testTheLoadStaysUntilTheVideoReallyRuns`, pausar al arrancar, saltar al arrancar, video nuevo).
