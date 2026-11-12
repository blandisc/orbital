# Interfaz de la app compañera de iPhone (propuesta)

> **Hoy:** el sistema visual vigente es **Proyección** — ver [`ios-proyeccion.md`](ios-proyeccion.md) (papeles con modo claro
> y oscuro, recetas de texto, catálogo de piezas y lo que vigilan las pruebas). Lo de abajo es la propuesta original.

Maqueta: `docs/ios-interfaz/maqueta.html` (se abre en el navegador) y `maqueta.png`. Es una propuesta
visual con la paleta real de Orbital (`orbital/web/styles/palette.json`); los pósteres son marcadores.

## 1. Idea

La app es **Orbital en el bolsillo**: mismo grafito oscuro, el color lo pone el título enfocado, sin
mayúsculas espaciadas, español primero. **Primera versión: solo películas y series** (sin juegos), que funciona por
sí sola; lo que ves aparece en Orbital y al revés porque **la cuenta de Stremio es el eje**. Hace algo que la TV no
hace: **ver en el teléfono** (reproductor propio, descargas sin conexión).

## 2. Navegación

Cuatro pestañas abajo, las secciones multimedia de la TV:

| Pestaña | Contenido | De dónde sale |
|---|---|---|
| Inicio | Seguir viendo (destacado), Mi lista, pendientes de Trakt | Stremio y Trakt |
| Para ti | Mosaico (solo series y películas), listas de plataformas y Trakt | TMDB y Trakt |
| Ver | Buscar y lo más popular de Stremio, ficha | Stremio, Cinemeta, TMDB |
| Descargas | Cola, espacio, lo disponible sin conexión | Local |

Ajustes en el icono de la esquina de Inicio (cuenta de Stremio, complementos, Trakt, idiomas, calidad, descargas, reproductor).
Un estado discreto dice «Stremio al día» o «N cambios por subir» (si no hubo internet).

## 3. Pantallas (ver la maqueta)

1. **Inicio**: destacado «Continuar T2 E5» con barra de avance y botones Continuar · Descargar · Más.
2. **Para ti**, con selector Mosaico · Listas:
   - **Mosaico**: igual al de Orbital (columnas de imágenes, la enfocada crece y enseña etiqueta, título y dato; ícono de serie o película en la esquina). **Sin juegos.**
   - **Listas**: lo más popular en Netflix, Disney+ y HBO Max en tu país (TMDB), y la **zona de Trakt** (watchlist, tus listas, viendo, recomendadas, tendencia, popular), leída a través de tu Orbital.
3. **Ficha**: Continuar, Mi lista, Descargar (serie o episodio), temporadas, episodios con estado
   (visto ✓ del bitfield de Stremio, a medias, descargado).
4. **Fuentes**: hoja inferior con «Ver / Descargar». Solo fuentes `url` de Real-Debrid. La recomendada
   arranca sola al tocar Continuar; esta hoja es para elegir otra.
5. **Descargas**: espacio usado, cola, listas para ver sin conexión, «reponer el siguiente».
7. **Reproductor** (horizontal): toque muestra controles, doble toque ±10 s, arrastre busca, panel único de
   audio y subtítulos (se recuerda por serie), menú ⋯ con «Otra fuente» y **«Abrir en Infuse»**,
   «Siguiente episodio» con cuenta atrás en los créditos.

## 4. Sistema de diseño en Swift (la regla «nada se crea suelto», también aquí)

- Paquete `OrbitalDesign` con **tokens**: `Palette` (los mismos valores de `palette.json`), `Space`,
  `Radius`, `Font` (escala de Orbital sobre Dynamic Type, equivale a «Tamaño del texto»), `Motion`
  (duración y curva; respeta «Reducir movimiento»).
- **Catálogo de piezas** (equivalencia con Orbital): `Chip`, `Badge`, `ProgressBar`, `SectionHead`,
  `PosterCard` (`card`), `FeatureHero` (`tiles`), `EpisodeRow`, `SourceRow` (`sources`), `DownloadRow`,
  `Sheet` (`sheet`), `Toast`, `StatusPill`, `PlayerControls`, `TrackPanel`. Una pantalla solo se arma con
  estas piezas; si falta una, se añade al catálogo.
- **Prueba automática** (`swift test`): los valores de `Palette` coinciden con `palette.json` (misma idea
  que la prueba que ya existe entre `tokens.css` y `player_ui.py`), y ningún archivo de pantalla escribe un
  color, tamaño o duración a mano.
- El fondo toma el tono del título (como `--art-tint`), calculado del póster.
- **Bordes** (I12, revisión del 10 nov 2026): todo cambio de interfaz se mira en tres condiciones antes de darlo por
  hecho: el iPhone grande normal, el iPhone SE, y el SE con letra de accesibilidad grande en modo claro. Nada cortado
  ni encimado, nada pegado a la orilla (el margen es `DS.Space.gutter`), los íconos dentro de su círculo y el texto en
  AA (4.5:1) también en claro. `ios/scripts/bordes.sh <udid-grande> <udid-se>` toma las pantallas principales en
  las tres y deja las capturas en `/tmp/orbital-bordes`. Lo que no cabe se reacomoda con `ViewThatFits` (de títulos con
  íconos a solo títulos y, al final, solo íconos) o se topa con `dynamicTypeSize` y el visor de contenido grande; nunca
  con un tamaño fijo. Un estado vacío va arriba, donde empezaría la lista, no al centro.
- **Capturas con banderas o íconos** (revisión 2 del 11 nov 2026): se toman en un simulador **sin adelgazar** (sin simslim)
  con el sistema más nuevo, que se crea para eso y se borra al terminar. El simulador adelgazado no trae los emojis de color
  ni todas las fuentes de símbolos: las banderas salen como «?» en un cuadro y parecen un error de la app cuando no lo son.
  Los simuladores del proyecto (adelgazados) sirven para todo lo demás.
- **Después de tocar `TitleView*`** (la ficha): correr `ios/scripts/abrir-fichas.sh <Orbital.app> <udid>` en Debug y en
  Release: abre la ficha de una película y la de una serie y dice si la app se cerró (el cierre de `oneColumnLayout` del
  11 nov solo salía al abrir una ficha; las pruebas de lógica no lo ven).
- **Instalar en el iPhone** (revisión del 11 nov 2026): `ios/scripts/instalar-iphone.sh [udid] [ultra|plus|orbital]` compila
  Release para el iPhone conectado con el número `git rev-list --count HEAD`, firma con el equipo del proyecto, instala con
  `xcrun devicectl device install app`, guarda los dSYM con `guardar-dsym.sh` y dice el número de compilación. Sin udid usa
  el primer iPhone conectado. Respeta el tope de 2 compilaciones a la vez y usa `/tmp/dd-orbital-release`.
- **Repintado** (V9, revisión del 10 nov 2026): `ios/scripts/medir-repintado.sh <udid> [Orbital.app]` abre Inicio, una ficha
  de película, una de serie y el reproductor con la demostración y `-perf-bodies` (solo Debug), y dice cuántas veces se
  evaluó el `body` de cada pantalla. Se corre antes y después de tocar cómo avisan los modelos: menos es mejor, y nada
  debe dejar de actualizarse. Los modelos que avisan por propiedad usan `@Tracked` (`OrbitalModels/ObservableModel.swift`).

### Aire parejo (11 nov 2026)

Fernando: «"Guardar / Viendo" como que tiene muy poco espacio abajo… establecer una regla para que ya no vuelva a pasar».

- **Todo contenedor con fondo** (tarjeta, botón, cápsula, hoja) tiene **el mismo aire arriba y abajo** de su contenido, y
  ese aire sale de un token (`DS.Space.*` o el de su pieza), nunca de un número suelto. Se escribe con un solo
  `padding(.vertical, …)` (o `padding(…)`), no con un `.top` y un `.bottom` distintos.
- **Si el contenido puede tener un renglón más** (un estado, un nombre que parte en dos), el contenedor lo contempla: crece
  con su aire intacto (alto *mínimo*, no fijo) y, en una fila de tarjetas iguales, todas reservan ese renglón para medir lo
  mismo y tener el ícono y el nombre a la misma altura.
- **Tarjeta de acción** (ícono + nombre + estado opcional): una sola pieza, `ActionTileLabel` (`Design/TitleActions.swift`),
  con sus medidas en `DS.ActionTile` (relleno vertical, alto mínimo y caja del ícono, que crece con la letra). La usan la
  ficha (Guardar, Descargar, Tráiler), «Mi media» y las teclas del control (`style: .key`). La fila de la ficha avisa con
  `actionTileRow(reservesDetail:)` cuando «Guardar» lleva su estado; las filas de teclas llevan
  `fixedSize(horizontal: false, vertical: true)` para que sus teclas midan lo mismo.
- **Lo que no se puede todo a la vez**: con el renglón de estado reservado, Descargar y Tráiler quedan con su lugar vacío
  abajo (el ícono y el nombre alineados con los de «Guardar» mandan sobre su centrado propio).
- Lo cuidan `DesignRulesTests+Air.swift`: que la ficha, «Mi media» y el control usen la pieza; que sus medidas no se usen
  fuera de ella; que la pieza tenga un solo relleno vertical y reserve el estado; y que ningún contenedor con fondo de
  `ios/App/Sources/Design` tenga distinto relleno arriba que abajo sin `ds-exception: <motivo>`.
- Se comprueba en las capturas, midiendo: del borde de la tarjeta a lo primero que se ve, arriba y abajo (±1 pt), en el
  iPhone grande, el SE y el SE con accessibility-large en claro (`ios/scripts/bordes.sh`, pantalla `ficha-viendo`).

### Lo que le queda a la pantalla (11 nov 2026)

En el iPad (acostado, o el de 13" de pie) y en la Mac el control de la TV se abre como panel a la derecha y las pestañas se
angostan. Inicio medía su página con `containerRelativeFrame` y su portada con la ventana: con el panel abierto la página
salía ~20 pt más ancha, recorrida a la izquierda y cortada de los dos lados.

- **Regla:** todo lo que va dentro de las pestañas toma su ancho de la columna (`WindowMetrics.column`, sin el panel), nunca de
  la ventana (`WindowMetrics.size`) ni de `containerRelativeFrame` (al ScrollView de una pestaña el panel le llega como margen
  seguro y lo cuenta). Medir el ScrollView tampoco sirve: con el panel crece con lo que tiene adentro.
- La columna la miden las pestañas (`.tracksColumnSize()` en `RootView`, antes del `.inspector`): su ancho sin los márgenes de
  los lados (el panel), su alto con los de arriba y abajo.
- Lo que de verdad depende de la ventana (decidir si hay panel, una hoja que flota encima, el reproductor a pantalla completa)
  o un `containerRelativeFrame` que mide su propia fila (un carrusel, la barra de arriba) lleva `ds-exception: <motivo>`.
- Lo cuida `DesignRulesTests+Column.swift`. Se comprueba con capturas con el control abierto y cerrado: `-demo-open
  remote-idle` en «Orbital QA iPad 13» de pie (ventana de 1032: ya sale el panel) y en «Orbital QA iPad» acostado;
  `-demo-sidebar` (solo Debug) abre la barra lateral.

### Un panel alto no deja el fondo vacío (11 nov 2026)

Fernando, sobre el control de la TV abierto como columna a la derecha del iPad: «no tiene caso tener todo ese espacio vacío
abajo». Decidió «Vamos con CT2»: **arriba lo que suena, abajo el control**. Solo el iPad: la Mac no tiene control de la TV, el
iPhone conserva su hoja de dos alturas y en la TV no aplica.

- **Lo fijo se ancla abajo y lo de arriba informa.** En el panel (`RemoteSheet+Panel.swift`), el control va junto al borde de
  abajo en el orden de siempre: voz, volumen, secciones, el pad, Atrás · Atajo · Opciones, −5 · Inicio · Menú · Buscar · +5 y
  «Escribir en la TV». Arriba, lo que hay en la tele: lo que suena (`RemoteNowHeader`: póster, nombre, «T1 E3 · quedan 27 min»
  y «Seguir aquí»; debajo la barra, ±10, pausa, subtítulos y audio de `playerDeck`) o, en reposo, tus «Seguir viendo» (los de
  Inicio, `RemoteSendRow`) para mandarlos a la tele con un toque («Ver en la TV»). Sin nada a medias, las frases de la voz del
  momento (`RemoteHintRow`).
- **Lo que sobra lo absorbe una pieza que sirve** (el pad, `navigation(growing: true)`), nunca un `Spacer` ni un hueco: el
  contenido mide al menos el alto del panel. Si no cabe (iPad chico acostado, letra grande), el panel se desliza.
- De reposo a sonando solo cambia lo de arriba con un fundido (`DS.Motion.smooth`); el control de abajo no se mueve.
- No es desprendible ni flotante (Fernando lo descartó).
- Lo cuida `DesignRulesTests+Panel.swift`.

### La versión vive en el botón (11 nov 2026)

Fernando, al ver tres opciones construidas en real: «Vamos L3». Antes el renglón «🇲🇽 Español · 1080p ›» iba suelto a la
izquierda, entre el avance y las tarjetas, y «rompe simetría».

- **En la ficha, el idioma y la calidad se eligen desde la zona derecha del botón principal** («Ver», «Continuar T2 E5»):
  el botón va partido (`SplitPlayButton`, `Design/SplitPlayButton.swift`, medidas en `DS.SplitPlay`). La izquierda, la
  mayor, reproduce; la derecha, más angosta, dice «🇲🇽 1080p ⌄» y abre «Versión». Cada lado se hunde por su cuenta.
- **No existe un renglón de versión aparte.** Lo que queda bajo el botón solo informa: «quedan 20 min», «Desde el
  principio» o un aviso («Sin versiones por ahora», «Sin conexión», lo de un pedido a la nube).
- **El botón va entero** cuando no hay versión que elegir: sin versiones, sin red, Real-Debrid con su propio botón
  («Pedir a la nube», un pedido en camino) o la versión Orbital, que no trae «Versión» (`instantStreams`).
- **Mientras se busca**, la zona derecha va en gris con la forma y el ancho que tendrá: el botón no cambia de ancho cuando
  llega. Si el nombre del botón no cabe en un renglón (SE, letra grande), la derecha se queda con la bandera y la flechita;
  el nombre nunca se corta.
- VoiceOver: «Versión: Español, 1080p. Cambiar». La ficha ancha del iPad y la Mac usa el mismo botón.
- Lo cuidan `DesignRulesTests+Version.swift`: `title-sources` solo en la pieza, `ContinueAction` sin otro selector, la
  ficha abre «Versión» solo por puertas conocidas (cada una con su porqué), y la pieza con su token y aire parejo.

### El reproductor no ofrece ni promete lo que no hay (12 nov 2026)

Fernando: «que no salga saltar intro hasta que ya esté cargada la serie» y, del aviso al probar otra versión, «no es como que
falle y que luego busques otra para que continúe. Es que esa no estaba disponible».

- «Saltar intro» y «Saltar resumen» solo salen con el video corriendo: nunca mientras carga, se llena o espera a arrancar.
- Al probar otra versión, «Sigue en el mismo punto» solo se dice si la anterior ya había sonado; si nunca arrancó, «La
  anterior no estaba disponible».

`PlayerModelTests+Avisos.swift` lo cuida. En la TV: pendiente de revisar si su aviso dice lo mismo (registro de paridad).

### Un botón, un estado (11 nov 2026)

Fernando: «cuando abres una ficha aparece la parte blanca y la otra aparece la parte gris, en lo que se carga el botón de
reproducir». El botón partido de la ficha (`SplitPlayButton`) se ve y se comporta como un solo botón: sus dos lados se apagan
juntos, y cuando el botón está apagado («Cargando», «Aún sin episodios», «Sale el…») va entero, sin zona de versión. La zona
derecha en gris solo aparece mientras de verdad se busca la versión de un episodio que ya se puede ver.
`DesignRulesTests.testSplitPlayButtonHasOneState` lo cuida. En la TV no aplica (no tiene botón partido).

### El volumen no se mueve solo (11 nov 2026)

Fernando: «cuando abro Orbital como que aparece la barra de volumen, como si hubiera cambiado el volumen». Con el control de
la TV abierto, los botones de volumen del iPhone son del control (`Platform/HardwareVolumeButtons.swift`) y la app regresa el
volumen del iPhone a donde estaba. La regla:

- La app solo mueve el volumen del iPhone con su tapa del aviso (`MPVolumeView`) ya puesta **en la ventana**, nunca al montar
  ni al desmontar una vista: movido antes o después, sale la barra del sistema.
- Al volver a la app, el volumen que se encuentre es el nuevo punto de partida: no cuenta como botón (no mueve la TV) ni se
  regresa.
- `MPVolumeView` y `outputVolume` solo se usan en `Platform/` (los botones del control y el volumen del reproductor) y en el
  gesto del reproductor. `DesignRulesTests+Volume.swift` lo cuida. En la TV no aplica.

### Opciones que se eligen: renglones con palomita (S1, 11 nov 2026)

Fernando: «Me gusta tu propuesta S1». En «Audio y subtítulos» del reproductor antes había cápsulas y acordeones que se partían
en dos filas desalineadas, medían distinto y los «−» «+» no eran del mismo tamaño. La regla:

- Lo que se elige de una lista (un idioma, una pista, una versión) es un **renglón con palomita** (`SubtitleRow`,
  `SubtitleVersionRow`): ícono o bandera en una columna fija (`DS.PlayerPanel.rowLead`), el nombre y su segunda línea gris, y la
  palomita en otra columna fija (`DS.PlayerPanel.rowMark`). Con o sin bandera, elegido o no, todos miden y se alinean igual, y
  nunca menos de `DS.Size.touchTarget`. Nada de cápsulas (`PanelChip`, `FlowChips`), acordeones (`DisclosureGroup`) ni
  `Capsule()` para elegir en el panel.
- La bandera de un renglón se pinta de una sola forma: `Text.flagMark(código)` en la columna del ícono (o `Text.flag`, que es lo
  mismo dentro de un texto). Nunca la bandera pegada al nombre en un renglón y suelta en otro.
- Todo está a la vista: tocar un idioma lo pone; tocar el puesto abre sus versiones (no recarga); solo ‹ › cambian de versión.
  En horizontal, en el SE o con letra grande, la lista se desplaza por dentro y «Listo» se queda fijo arriba a la derecha.
- Los botones que van en pareja («−» «+», ‹ ›) usan `DSIconButton(…, steady: true)`: el símbolo va en un marco fijo
  (`DS.IconButton.steadyGlyph`) y los dos miden lo mismo aunque «−» sea más angosto que «+». Mantener presionado repite
  (`repeats: true`) y sin vibrar: el reproductor no vibra mientras ves. Vale para toda la app: las flechas de «Colecciones» y de «Tu año» también van con marco fijo.
- Donde sí quedan cápsulas (filtros, temporadas «T1, T2…»), las de una misma fila miden lo mismo: `FlowChips` da a cada una el
  alto de su línea y `PanelChip` lo llena; el selector de temporada usa el mismo tamaño y forma para la elegida y las demás.
- Abierto el panel, el video no se tapa: en vertical se acomoda justo arriba del panel (`PlayerLayout.portraitRect(abovePanel:)`,
  sin franja negra) y en horizontal el panel y el video se reparten la pantalla (`PlayerLayout.sideDock`), dentro del área segura.

`DesignRulesTests+Subtitles.swift` y `PlayerLayoutTests` lo cuidan. La TV ya usa renglones con ✓: sin cambio. En el iPad el panel
es el mismo (al lado del video).

### Íconos: uno por idea (revisión 2 del 11 nov 2026)

Cada idea tiene un solo símbolo del sistema y vive en `DS.Symbol` (`ios/App/Sources/Design/Icons.swift`). Nunca un carácter
de texto como ícono («✓», «↻», «☰», «✕», «△», «▲»), en ningún archivo de la app: se usa el símbolo. Las estrellas «★» y «½» de Letterboxd no son íconos: son su forma de
escribir la calificación. `DesignTests.testOneIconPerIdea` revisa que cada símbolo de `DS.Symbol` esté en esta tabla y que no
haya caracteres de texto usados como ícono.

| Idea | Símbolo | Dónde |
|---|---|---|
| Guardar en una lista | `bookmark` (`DS.Symbol.save`) | Botón «Guardar» de la ficha, Mi lista |
| Ya está guardado | `bookmark.fill` (`DS.Symbol.saved`) | El mismo botón, relleno |
| Favoritos | `heart` / `heart.fill` (`DS.Favorites`) | «Guardar en…» |
| Descargar a este aparato | `arrow.down.circle` (`DS.Symbol.download`) | Ficha, episodios |
| Seguir una descarga en pausa | `arrow.down` (`DS.Symbol.resumeDownload`) | Anillo de descarga |
| La nube (Real-Debrid) | `icloud.and.arrow.down` (`DS.Symbol.cloud`, `cloudFill`) | Versiones, pedidos |
| Cancelar o quitar un pedido | `DS.Symbol.cancelRequest`, `removeRequest` | Pedidos a la nube |
| Lo que la app hace sola | `arrow.triangle.2.circlepath` (`DS.Symbol.automatic`) | Descarga inteligente |
| Más detalle (ⓘ) | `info.circle` (`DS.Symbol.info`) | Versiones, complementos, reproductor |
| Saltar segundos | `gobackward.10` / `goforward.10` (`DS.Symbol.skipBack`, `skipForward`) | Reproductor, control |
| Saltar 5 en la fila de la TV | `arrow.left.square` / `arrow.right.square` (`DS.Symbol.rowBack`, `rowForward`) | Control |
| Hecho | `checkmark` (`DS.Symbol.done`) | «En la TV» de la voz |
| La versión recomendada | `sparkles` (`DS.Symbol.recommended`) | «Versión»; la leyenda de la primera vez lo explica |
| Lista al instante (ya en la nube) | `bolt.fill` (`DS.Symbol.instant`) | «Versión», reproductor; la leyenda lo explica |
| ¿Otro título? (el nombre dice otro año) | `questionmark.circle` (`DS.Symbol.otherTitle`) | «Ver todas las versiones»: explicado una vez arriba |
| Cambiar de versión para oír ese idioma | `arrow.triangle.swap` (`DS.Symbol.switchVersion`) | Reproductor › Audio, los idiomas de otra versión |
| La que estás viendo | `checkmark` (`DS.Symbol.current`) | «Ir a una sección» de las listas |
| Subtítulos apagados | `character.bubble` (`DS.Symbol.subtitlesOff`) | «Audio y subtítulos» › Apagados |
| Buscar otro idioma | `magnifyingglass` (`DS.Symbol.otherLanguage`) | «Audio y subtítulos» › Otro idioma |
| Sin conexión | `wifi.slash` (`DS.Symbol.offline`) | «Audio y subtítulos», sin red |
| Sincronía de los subtítulos | `timer` (`DS.Symbol.subtitleSync`) | «Audio y subtítulos» › Sincronía |
| Sincronizar con una línea | `text.line.first.and.arrowtriangle.forward` (`DS.Symbol.syncWithLine`) | «Audio y subtítulos» |
| Regresar el ajuste a cero | `arrow.counterclockwise` (`DS.Symbol.resetDelay`) | Sincronía, «Volver a cero» |
| Tamaño de los subtítulos | `textformat.size` (`DS.Symbol.subtitleSize`) | «Audio y subtítulos» › Tamaño |
| Pista de audio | `speaker.wave.2` (`DS.Symbol.audioTrack`) | «Audio y subtítulos» › Audio |
| Versión del video | `square.stack` (`DS.Symbol.videoVersion`) | «Audio y subtítulos» › Versión |
| Subtítulos para sordos | `ear` (`DS.Symbol.hearingImpaired`) | Versiones de subtítulos, con la palabra |
| Subtítulos forzados | `quote.bubble` (`DS.Symbol.forcedSubtitles`) | Versiones de subtítulos, con la palabra |
| Una versión de subtítulos | `captions.bubble` (`DS.Symbol.subtitleVersion`) | Versiones de subtítulos |
| Botones de otras consolas | `xmark`, `circle`, `square`, `triangle`, `line.3.horizontal`, `rectangle.on.rectangle` (`DS.Symbol.padCross`, `padCircle`, `padSquare`, `padTriangle`, `padMenu`, `padView`) | El acompañante del juego (cómo quedan los botones) |

## 4b. Bilingüe

Textos en `Localizable.xcstrings` (es base, en); fichas según el idioma de la app; lo guardado en Stremio
lleva el título original. Audio y subtítulos tienen su propio idioma, separado.

## 5. Decisiones que quedan abiertas

- Si «Ver» y «Para ti» deben fundirse en una sola pestaña (hoy son dos para igualar la TV).
- Estilo del destacado: póster fijo (maqueta) o carrusel.

## 6. Trakt

**Propuesta de ubicación:** Trakt es una fuente más de Para ti → Listas (selector Todo · Trakt · Netflix · Disney+ · HBO Max;
dentro de Trakt: Watchlist · Tus listas · Viendo · …, con «Tuyo» antes que «Descubrir»), y la watchlist se asoma en Inicio.

**Scrobble: obligatorio.** La app lo hace por sí sola; Orbital también (hoy `trakt.py` solo lee). Stremio sigue siendo la fuente
de verdad de qué viste y cuánto. Cada reproductor avisa de lo que reproduce él mismo (en línea: `/scrobble/stop`, que responde
409 si ya está registrado; sin conexión: `/sync/history` con la fecha real, comprobando antes que no exista).

**Obstáculo a resolver antes de escribir código** (investigación del 2026-10-12, ver el artefacto de la propuesta):
- Cuentas gratuitas: una sola «app comunitaria» conectada (anuncio del 22-jul-2026); Stremio casi seguro ya la ocupa.
- Crear una app de API exige VIP desde agosto de 2026; la aplicación de Trakt de Orbital puede haber desaparecido.
- Sin confirmar: si una app propia cuenta como conectada y si un mismo `client_id` en dos dispositivos cuenta como una sola.
- Sin confirmar: si lo que se escribe en Stremio llega a Trakt (no hay evidencia): la app no depende de eso.
- Los términos de Trakt no se pudieron leer.

**Lo que debe comprobar el usuario:** en trakt.tv → Ajustes → Apps, cuántas apps hay conectadas y si la de Orbital sigue existiendo.
