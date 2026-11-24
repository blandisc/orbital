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
- **Si el contenido puede tener un renglón más** (un nombre que parte en dos), el contenedor lo contempla: crece con su aire
  intacto (alto *mínimo*, no fijo).
- **Tarjeta de acción** (ícono + nombre, **en un solo renglón**): una sola pieza, `ActionTileLabel` (`Design/TitleActions.swift`),
  con sus medidas en `DS.ActionTile` (relleno vertical, alto mínimo y caja del ícono, que crece con la letra). La usan la
  ficha (Guardar, Descargar, Vista, Tráiler), «Mi media» y las teclas del control (`style: .key`). Las filas de teclas llevan
  `fixedSize(horizontal: false, vertical: true)` para que sus teclas midan lo mismo.
  El nombre **nunca toca la orilla** de su tarjeta: lleva aire a los lados (`DS.Space.s1`) en todos sus estilos; si con
  letra grande los cuatro ya no caben así, la fila de la ficha pasa a 2×2 (12 nov 2026, «Guardada» y «Descargar» tocaban
  la orilla en el SE con letra XXXL). El nombre no se encoge a medias: en una fila, todas las tarjetas miden lo mismo
  (`ActionTileRow`, el ancho del nombre más largo), nunca un `HStack` que reparte según cada nombre.
- **Sin renglón de estado** (F1, 12 nov 2026; antes «Guardar» llevaba «Viendo» abajo y la fila lo reservaba, y Descargar y
  Tráiler quedaban con un hueco: «descargar y tráiler tiene mucho espacio vacío abajo»): el estado lo dicen el nombre y el
  ícono («Guardada» con el marcador lleno, «Vista» en verde, el anillo de la descarga) y el detalle va al tocar.
- Lo cuidan `DesignRulesTests+Air.swift`: que la ficha, «Mi media» y el control usen la pieza; que sus medidas no se usen
  fuera de ella; que la pieza tenga un solo relleno vertical y un solo renglón; y que ningún contenedor con fondo de
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

### Lo que se desplaza a lo ancho (13 nov 2026)

Fernando, de «Día por día» en «Lo que ves»: «aparece como rota, o sea, no se ve completa, tienes que darle a la derecha cuando
la abres». El mapa abría en el extremo equivocado (`defaultScrollAnchor(.trailing)` con una lista perezosa y con el historial
que llega después de abrir) y cortaba una semana a la mitad en la orilla.

**El mapa de «Día por día» pinta por niveles y solo con fechas de verdad** (Fernando, 14 nov 2026: «se traba… no te está poniendo más fuerte los días que ves más»). Lo marcado «No sé cuándo» Trakt lo guarda en 1970: no entra al mapa, que llega a lo más tres años atrás. El tono va en tres niveles por tercios de tus días (`WatchingHeat.levels`), nunca contra el día más grande: un maratón no apaga el resto. Lo cuida `WatchingHeatTests`.

- **Regla: lo que se desplaza a lo ancho abre mostrando lo importante completo, y dice que hay más.** Lo importante es lo de
  hoy (o lo elegido); «completo» es sin una columna o tarjeta a medias en la orilla de la columna; «dice que hay más» es un
  desvanecido en la orilla de lo que queda atrás (o la tarjeta que se asoma en un carrusel de orilla a orilla).
- **Regla: ninguna tarjeta de Explorar va en gris** (23 nov 2026, «Esta semana»: «se ven todos grises en comparación a los demás»). Toda tarjeta de colección lleva el color y el ícono de su tema, como Temporadas y Géneros; una lista de «Esta semana» lo dice en la tabla («art») y, si falta, toma uno fijo según su id. Lo vigila `testCadaListaTieneSuIconoYExiste`; en la TV, `tests/web/curation.test.mjs` («ninguna lista de «Esta semana» va en gris»).
- **Regla: lo que va dentro de una tarjeta no se sale de ella** (22 nov 2026, en la Mac: «Lo nuevo de lo tuyo» se salía del
  panel por los dos lados y los pósters de «Por lo que viste» pasaban la orilla de su tarjeta). Cada fila dice hasta dónde
  llega: `.rowEdge(.bleeds)` la suelta, que en el iPhone llega a la orilla de la pantalla y en ventana ancha (iPad, Mac) termina en
  el mismo margen que todo lo demás, con un desvanecido ancho (`DS.Size.rowFade`) que dice que hay más; `.rowEdge(.inCard)` la
  que va en una tarjeta o un panel. El margen de cada fila va por dentro del desplazamiento (`contentMargins`), nunca como
  relleno de afuera (con los dos, Colecciones empezaba más adentro que todo lo demás). El corte solo esconde lo que ya pasó: al inicio de una fila no hay corte a la izquierda (se comía el «1» de «Lo que más
  viste»), y una fila que lleva su margen como relleno de adentro también termina en el margen de la ventana. Lo mismo en
  una cuadrícula: un puesto cabe con su número (`DS.Poster.rankedWideMin`; en el Top de un género el póster tapaba la cifra
  de al lado), lo vigila `testRankedGridsMakeRoomForTheirNumber`. Lo vigilan `testRowsSayWhereTheyEnd` y `testHorizontalRowsDoNotClipWhatGrows`.
- **Una acción, un botón:** una fila que termina con su tarjeta de añadir («Añadir canal») no repite el «+» en su
  encabezado (`testRowsDoNotRepeatTheirAddButton`).
- Los mapas de semanas son una pieza, `DSWeekStrip` (`Design/WeekStrip.swift`, medidas en `DS.WeekStrip`): las casillas salen
  del ancho que le queda (`WindowMetrics.column`), caben semanas enteras, abre en la de hoy por su id (también cuando llega
  más historial), se detiene por semanas, desvanece lo de atrás y, si todo cabe (iPad, Mac), no se desliza. Arriba, el mes
  abreviado («oct», el año en enero); a la izquierda, L, X, V y D (14 nov 2026); hoy con borde; debajo, «Hoy» y «Menos ▢▢▢▢ Más».
- **Gráficas: una gráfica, un color; el nombre y el valor en el mismo renglón.** Para comparar pocas categorías, barras de
  mayor a menor (no dona ni pastel); se ven cinco y el resto va en «Otros», en gris. El color es el azul del mapa
  (`DS.orbitalBlue`); el largo dice cuánto. VoiceOver lee «Comedia, 34 %».
- Lo cuida `DesignRulesTests+Strips.swift`. En la TV: el registro de paridad dice qué pasa allá.

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
- **No existe un renglón de versión aparte.** Lo que queda bajo el botón: la línea del avance (barra, «quedan 20 min» y ↺,
  R1) y un aviso que solo informa («Sin versiones por ahora», «Sin conexión», lo de un pedido a la nube).
- **El botón va entero** cuando no hay versión que elegir: sin versiones, sin red, Real-Debrid con su propio botón
  («Pedir a la nube», un pedido en camino) o la versión Orbital, que no trae «Versión» (`instantStreams`).
- **Mientras se busca**, la zona derecha va en gris con la forma y el ancho que tendrá: el botón no cambia de ancho cuando
  llega. Si el nombre del botón no cabe en un renglón (SE, letra grande), la derecha se queda con la bandera y la flechita;
  el nombre nunca se corta.
- VoiceOver: «Versión: Español, 1080p. Cambiar». La ficha ancha del iPad y la Mac usa el mismo botón.
- Lo cuidan `DesignRulesTests+Version.swift`: `title-sources` solo en la pieza, `ContinueAction` sin otro selector, la
  ficha abre «Versión» solo por puertas conocidas (cada una con su porqué), y la pieza con su token y aire parejo.

### La dirección de un complemento se arma con `addonURL` (13 nov 2026)

Fernando: «sigue sin aparecer» el latino de Los Simpson. La causa de fondo: desde iOS 17, `URL(string:)` vuelve a codificar
los «%» de una cadena que trae algún carácter inválido. La dirección de Torrentio lleva «|» entre sus opciones, así que el
episodio `tt0096697%3A11%3A2` salía `%253A` y Torrentio contestaba vacío para TODA serie (las películas no llevan «:» y la de
Comet no lleva «|»: por eso funcionaban). Regla: toda dirección que sale de la de un complemento (versiones, subtítulos,
catálogos, lo que existe sin Real-Debrid, la de reproducir) se arma con `addonURL` (`Net.swift`), nunca con `URL(string:)`
directo. `AddonURLTests` lo cuida. En la TV no aplica (Python no hace eso).

### El canal no desordena tu serie, pero lo que dejaste a medias siempre se puede retomar (13 nov 2026)

Fernando: «cuando veo un episodio de Simpson no aparece en seguir viendo»; eligió V2 («vamos con B2»). Un canal de Inicio y
la ruleta de Los Simpson (`PlayRequest.offTheRecord`) ya no se ven «sin dejar rastro»:

- Un episodio que cortas a la mitad sale en «Seguir viendo» («T15 E12 · quedan 12 min») y el «Continuar» de la ficha lo
  ofrece. Tu orden de la serie queda apartado (`LibraryEntry.detour`), no se pierde.
- Al terminarlo (en el canal o desde la ficha) queda visto, aquí y en Trakt, y la serie vuelve a donde ibas en tu orden: nunca
  deja un «siguiente: T15 E13». Quitarlo de «Seguir viendo» también regresa tu orden y saca la serie de la fila.
- Si el canal puso justo el episodio que te tocaba, cuenta como verlo en orden. Zapear (menos de 20 s) no cambia nada. Lo que
  Trakt devuelva de ese episodio (el eco) no mueve tu orden (`channelAt`).
- Lo que sigue al terminar en el canal hereda lo mismo; «¿Sigues viendo?», el widget y el Centro de control no cambian.
- Una serie escondida (SS1-A) no deja «siguiente episodio», pero lo que dejaste a medias (por un canal o desde la ficha) sí
  sale en «Seguir viendo» y en el widget hasta que lo termines o lo quites (`HomeItem.shownInContinue`,
  `FollowHideTests.testLoQueDejasteAMediasDeUnaEscondidaSiSale`).

`ChannelProgressTests` (OrbitalCoreTests) y `PlayerModelTests.testChannelPlaybackHalfway…` lo cuidan. En la TV: distinto,
pendiente (registro de paridad): sus canales de Orbital no guardan nada, ni a medias.

### El reproductor no ofrece ni promete lo que no hay (12 nov 2026)

Fernando: «que no salga saltar intro hasta que ya esté cargada la serie» y, del aviso al probar otra versión, «no es como que
falle y que luego busques otra para que continúe. Es que esa no estaba disponible».

- «Saltar intro» y «Saltar resumen» solo salen con el video corriendo: nunca mientras carga, se llena o espera a arrancar.
- Al probar otra versión, «Sigue en el mismo punto» solo se dice si la anterior ya había sonado; si nunca arrancó, «La
  anterior no estaba disponible».
- Lo que ya suena no se cambia solo por otra versión salvo que de verdad falle: una duración corta de un momento (el motor
  abriendo el archivo) no es el aviso de Real-Debrid, «otra versión» nunca vuelve a cargar el mismo archivo (aunque venga
  de otro torrent) y toda versión que se da por fallida queda en la bitácora con su motivo (`markFailed`).

`PlayerModelTests+Avisos.swift` y `RetryOnlyWhenItFailsTests.swift` lo cuidan. En la TV: pendiente de revisar si su aviso dice lo mismo (registro de paridad).
- **Si el video no arranca, nada del reproductor tapa el aviso**: ni los controles, ni ±10, ni el iPod, ni «Audio y
  subtítulos» fijo del iPad de pie. El aviso trae sus propios botones («Pedir a la nube», «Cerrar») y es la única salida.
  Nació en el recorrido de la Mac (16 nov 2026): en el iPad de pie, «Todavía no está en la nube» quedaba bajo el panel fijo,
  sin ✕ ni «Cerrar» a la vista. `DesignRulesTests+Quitar.swift` (`testNothingCoversThePlayerFailure`) lo cuida.
### Las acciones de un título (12 nov 2026)

Fernando, al ver la ficha del iPhone: «integrar los dos botones que están abajo, los de descargar y vista, a estos tres de ahí
arriba… porque no es muy consistente»; decidió «Me gusta la F1».

- **Las acciones de un título viven en una sola fila de mosaicos de un renglón; no hay botones de acción sueltos en otra parte
  de la ficha.** La fila es **Guardar · Descargar · Vista · Tráiler** (`TitleView.actionTiles`), cada uno con `ActionTileLabel`,
  mismo alto y estilo. «Vista» solo si hay qué marcar (una película siempre; una serie con episodios) y «Tráiler» solo si lo
  hay: la fila se reparte sin hueco (tres o cuatro). Si los nombres no caben enteros en un renglón (SE con letra grande, letra
  de accesibilidad), pasan a 2×2; la letra no se achica para que quepan.
- **Guardar** dice «Guardar» o, ya en alguna parte, «Guardada» (la palabra de la TV) con el marcador lleno y el color del arte.
  En qué lista está («Viendo», «En Mi lista»…) se ve al tocarlo. «Vista» ya no va en ese menú cuando está su mosaico.
- **Descargar** en una serie pregunta qué con el menú del sistema: este episodio, los siguientes, «Temporada N» con lo que
  pesa lo que falta (y si no cabe) y toda la serie; «Elegir versión…» aparte. Bajando o lista, el mismo menú suma la temporada y
  la serie. En una película, un toque baja la recomendada. Reemplaza la hoja «¿Qué descargo?» y el círculo de la temporada.
- **Vista** en una película abre «¿Cuándo la viste?»; en una serie pregunta: este episodio, «Temporada N» (con cuántos llevas)
  o toda la serie, y «Calificar la temporada» (con Trakt y algo visto). Toda vista: el ícono lleno y en verde.
- **Una sola fila de estrellas a la vista**: «Tu calificación» (la película o la serie). La de la temporada se pone desde
  «Vista» (hoja `SeasonRatingSheet`); cada capítulo conserva las suyas en su fila.
- La TV no cambia (registro de paridad, «Distinto a propósito»). Lo cuida `DesignRulesTests+Actions.swift`.

### Las preguntas son tarjetas de la app (13 nov 2026)

Fernando: «Cuando le picas un episodio ya visto, que créate una tarjeta, que no aparezca esta notificación como del sistema,
toda fea». Cambia EV1 (9 nov, «la del sistema»). La regla: **las preguntas y elecciones de la app son tarjetas de la app, no
diálogos del sistema.**

- Una elección («¿qué hago con esto?») es una `ChoiceSheet` (`Design/ChoiceSheet.swift`), presentada con `choiceSheet(item:)`:
  hoja a la medida de lo que trae (`fittedSheet`, con `dsSheetContent`), arriba qué es (la imagen, el nombre y una línea gris),
  la acción principal grande (`dsSolidPrimaryButton`, opcional) y las demás como renglones con ícono (`WatchedOption`, los de
  «¿Cuándo la viste?»). Sin «Cancelar»: se cierra deslizándola, tocando fuera o con Esc. Lo que toques corre cuando la hoja ya
  se cerró (el reproductor o «Versión» no chocan con ella).
- **«Ya lo viste»** (tocar un episodio visto): la miniatura, «T2 E5 · nombre» y «Ya lo viste» en gris; «Ver otra vez» con la
  versión que va a sonar («🇲🇽 Español»); «Otra versión o idioma» (`DS.Symbol.switchVersion`) y «Marcar como no visto»
  (`DS.Symbol.watched`; no va en rojo: se puede volver a marcar). En el iPad es la misma tarjeta, centrada y a la medida.
- **Confirmar un cambio que no borra ni desconecta también es tarjeta** (21 nov 2026, Fernando: «sale un anuncio de sistema
  muy feo. Mejor que salga una card de abajo»): «Pasar a la TV» y «Usar la de la TV» de Cuentas, y «Esta lista es «Solo tú»»
  al compartir una lista. Arriba qué queda y qué pasa si falla; la acción grande; dejarlo como está es cerrarla.
- Se quedan como pregunta del sistema, cada una con `ds-exception: <motivo>` en su renglón: las confirmaciones cortas de algo
  destructivo o de desconectar («¿Quitar…?», «¿Desconectar Trakt?»), las que piden un nombre (el campo de texto del sistema) y
  «¿Terminaste de verlo?» (llega al volver de Infuse sobre lo que esté abierto). Los `Menu` que se despliegan del propio botón
  («Descargar», «Vista») no son diálogos y se quedan.
- **«Versión»** (13 nov, Fernando: «Sí, también conviértelos en la tarjeta, los otros tres diálogos»): «¿Para el resto de la
  serie también?» con «Los siguientes episodios, en 🇲🇽 latino.» en gris, «Sí, desde aquí» grande (`DS.Symbol.fromHereOn`) y
  «Solo este episodio» (`DS.Symbol.onlyThisOne`); cerrarla no abre nada, como antes. El pedido que baja en la nube («Ver cómo
  va»): arriba cómo va y cuánto falta y, si hay, «Ver Inglés · 1080p, ya arranca» grande; ya no lleva «Esperar a que llegue»
  (era el «Cancelar»: esperar es cerrarla, el pedido sigue igual). «Ver Inglés…» puede traer luego la de la serie: corre cuando
  la tarjeta ya se cerró.
- **En el reproductor** es la misma tarjeta, pero flotando sobre el video (`ChoiceSheet(floating: true)`, de vidrio como sus
  paneles) y no una hoja: en horizontal la hoja de iOS sube a todo el alto y tapa el video. La pone `PlayerScreen+Preguntas.swift`
  encima de todo (también del candado), con el video oscurecido detrás: abajo en vertical (donde van los controles), al centro
  en horizontal, dentro del área segura y, si no cabe (SE acostado, letra grande), se desplaza por dentro. No pausa nada que
  antes no se pausara y no vibra.
  - «¿Sigues viendo?» («Llevas tres episodios seguidos.»): «Seguir viendo» grande y «Salir» (`DS.Symbol.leavePlayer`). Llega tras
    tres episodios seguidos sin tocar la pantalla, con el video en pausa; no tiene cuenta atrás y no se cierra sin contestar
    (tocar fuera no hace nada; Esc es «Salir», como en la del sistema).
  - «Real-Debrid aún no tiene esta versión» (al elegir en «Versión» una que hay que bajar): «Abrirla de todos modos» grande
    (`DS.Symbol.cloud`); tocar fuera, Esc o el escape de VoiceOver es «Mejor no» y sigue la que ves.
  - Mientras está «¿Sigues viendo?», la tarjeta de «Siguiente episodio» no se dibuja (se encimaba debajo).
  - Banderas de demostración: `-demo-player-state still-watching` y `-demo-player-state slow-pick`; en «Versión»,
    `-demo-open sources-series` (con `-demo-title series:…`).
- **Las pruebas del reproductor en el simulador van en silencio: `-demo-mute`** (Fernando, 13 nov 2026: el video de prueba
  sonaba por las bocinas de la Mac). Pone en 0 el volumen del motor (AetherEngine y AVPlayer), sin tocar el del sistema; todo
  lanzamiento de demostración de `ios/App/UITests` la lleva y `DesignRulesTests+DemoMute` lo revisa.
- Lo cuida `DesignRulesTests+Dialogs.swift`: un `confirmationDialog`, `alert` o `actionSheet` nuevo falla si no lleva su porqué;
  ya no quedan pendientes, y también revisa que las de «Versión» y el reproductor sigan siendo tarjetas.
  En la TV: igual (sus elecciones ya son hojas propias).

### Lo que acompaña a un control va en su misma línea (12 nov 2026)

Fernando: «donde dice la temporada de la serie y donde dice X de tantos X vistos, ayúdame a centrarlo más porque está como ahí
volando»; «tu nota… ocupa mucho espacio innecesario»; y de «Desde el principio», «una forma tal vez un poquito más estética»
(decidió R1).

- **Lo que acompaña a un control va en su misma línea, centrado con él**, no debajo ni flotando a un lado:
  - la temporada: la cápsula «Temporada N ⌄» a la izquierda y «3 de 22 vistos» a la derecha; abajo, la barra de la temporada;
  - «Tu calificación»: las estrellas y, al final, el botón redondo de «Tu nota» (con el más si no has escrito; resaltado si ya);
  - bajo «Continuar» (R1): la barra (ocupa lo que sobra), «quedan 20 min» y ↺ «Desde el principio», botón redondo
    (`DSIconButton`, 44 pt, con su nombre para VoiceOver), sin texto en color. Si no ibas a medias, la línea no existe.
- El aviso que solo informa («Sin versiones por ahora») va en su propio renglón debajo, en gris, y la otra salida de
  Real-Debrid («Verlo en inglés al instante», «Cancelar pedido») a su derecha, con su nombre (dice qué hace).
- Con letra de accesibilidad, lo que no quepa baja de renglón entero («quedan…» bajo la barra), nunca cortado.
- Lo cuida `DesignRulesTests+Actions.swift`.

### Tu idioma, aunque haya que pedirlo (12 nov 2026)

Fernando, con Los Simpson T11E2 y latino primero en «Tus idiomas»: «me salen puros episodios en inglés. Y me tengo que meter a
checar cada uno… Me salieron todas de Comet». Decidió: «Sí, vamos a hacer la 2 y la 3». La regla: **si tu idioma existe, la
app te lo dice aunque no arranque al instante; y si un complemento no contestó, también.**

- **Un complemento lento no se pierde.** «Versión» sale con lo que llegó a tiempo (el plazo de siempre) y lo del lento se
  suma en cuanto llega, sin volver a preguntar. Si de plano no contesta: «No contestó a tiempo: Torrentio · Reintentar»
  (`AddonQuietLine`); «Reintentar» le pregunta otra vez a todos, también al que se saltaba por fallar.
- **Tu idioma que hay que pedir se dice arriba**: si ninguna versión de tu idioma arranca al instante pero alguna existe (en
  la lista o en tu Torrentio sin Real-Debrid), «Hay latino, pero hay que pedirlo a la nube» con «Pedir a la nube»
  (`VersionYoursAside`, la misma acción de R4). No sale si ya la pediste: su renglón dice cómo va.
- **Tu idioma rechazado también se dice** (LN2, 18 nov 2026, Los Simpson T37E3): si la única de tu idioma la rechazó
  Real-Debrid, en su lugar «Hay latino, pero Real-Debrid no lo dejó bajar · Prueba otra versión», con el triángulo y sin
  «Pedir a la nube», porque pedirla otra vez falla igual (`VersionYoursRefused`, en «Versión» de la ficha y del reproductor).
  Nunca el inglés sin explicación. La TV lo dice en la nota de la ficha. Lo cuidan `LatinoRechazadoTests` y
  `testVersionSaysWhenRealDebridRefusedYourLanguage`.
- **Revisar por dentro**: de las que arrancan al instante con idioma dudoso (MKV que solo dice su idioma original o nada,
  o «Multi»/«Dual»), se leen las pistas de audio de su encabezado (un pedazo del principio, nunca el archivo), hasta 3, una
  a la vez, nunca con el reproductor abierto ni la que estás viendo, y cada una una sola vez. Lo leído queda «Comprobado» y
  se guarda; los demás episodios del mismo paquete salen «Lo trajo otro episodio». Solo las que arrancan al instante: pedir
  el enlace de una «por bajar» le pide a Real-Debrid que la baje.
- La bitácora dice por complemento cuántas trajo y en cuánto («complemento Torrentio: 50 versiones en 4,2 s (llegó tarde: se
  suman)»), sin direcciones; y qué mandó: entradas, con enlace, solo torrent, avisos por tipo, el «HTTP 4xx» si lo hubo, las
  opciones de Torrentio sin claves y si la dirección lleva tu clave (`AddonAnswerReport`). Al elegir versión, en qué idioma
  quedó y si había alguna en tu idioma al instante («sin es-419 al instante: 30 en, 5 fr»).
- **El reproductor directo también lo dice** (13 nov, Fernando: «Sobre todo pasa cuando le doy a la ruleta esta de los
  Simpsons, ya sea que entre por widget o por control panel»): la ruleta, el widget, el Centro de control y «Continuar»
  siguen abriendo la mejor que hay (la regla de elección no cambia), pero si ninguna de tu idioma arranca al instante
  (`YourLanguageNow`: solo evidencia sólida; un «español» sin variante, un «Multi» o un «tal vez» no cuentan) y existe para
  pedir, avisa una vez «No está en latino al instante · Versión», y «Versión» del reproductor la ofrece arriba con «Pedir a
  la nube», como la de la ficha.
- **Puros torrents no son «no hay»**: si un complemento con Real-Debrid (lo dice su dirección o su nombre, «Torrentio RD»)
  manda entradas y ninguna con enlace, la dirección va sin tu clave: se dice en la bitácora, se rearman tus complementos y se
  le pregunta otra vez; si sigue igual, sale como «No contestó a tiempo», nunca como lista vacía guardada.

Lo cuidan `LatinoNubeFinderTests`, `LatinoNubeModelTests`, `LatinoRuletaTests`, `TorrentioSinClaveTests`, `AudioProbeTests` y
`DesignRulesTests+YourLanguage`. En la TV: pendiente (registro de paridad, LN1).

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
- **Tu música manda** (20 nov 2026, Fernando: «cuando entras reproduciendo música… le sube el volumen y no te deja
  bajar»): si suena audio de otra app (`isOtherAudioPlaying`), los botones de volumen son del iPhone, no del control, y la
  app no acerca el volumen al centro. Al salir de la app, el volumen regresa al que tenías.

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

### Toda lista ofrece los mismos órdenes; uno que no aplica no aparece (13 nov 2026)

Fernando: «Que en mis listas también pueda ordenar por agregadas más recientemente o menos recientemente a la lista». Los
órdenes de «Ordenar y filtrar» salen de un solo lugar, `OrbitalModels.ListSort.offered`, con los datos de la lista: «Agregadas:
más recientes» y «Agregadas: más viejas» solo donde hay cuándo lo agregaste (`Suggestion.addedAt`: Mi lista y tus listas, no
Viendo, Vistas, Las dejé ni las listas de otros), IMDb si se puede pedir, Trakt si trae su calificación. Nunca una opción muerta.
Cada lista recuerda su orden con `ListSort.saved`/`remember`; ninguna pantalla arma su propia lista de órdenes ni guarda el orden
por su lado. Lo que no trae fecha va al final en el orden en que venía, y elegir un orden no toca tu orden a mano de Trakt.
`ListSortTests` y `DesignRulesTests+ListSort.swift` lo cuidan.
### Volver a la app nunca te hace esperar para seguir (12 nov 2026)

Fernando: «si dejo pausado un elemento y salgo de la aplicación y regreso y le doy play, que se reproduzca inmediatamente»;
y luego: «que no cargue de nuevo». La regla: **volver a la app nunca te hace esperar para seguir: play responde al instante
y un solo toque basta.**

- Salida corta (menos de ~30 s, lo que iOS presta antes de suspender la app): el motor no suelta el video ni su búfer; play
  va directo al motor, sin volver a pedirlo ni enseñar carga.
- Salida larga: AetherEngine suelta el video al vencer ese plazo (lo exige iOS al suspender la app; no hay forma de
  conservarlo en pausa). Se rearma en cuanto vuelves, en pausa (no arranca solo ni le quita el sonido a otra app), con el
  cuadro donde ibas y el play a la vista. Si tocas play a media carga, ese toque llega al motor en ese momento y suena en
  cuanto abre: nunca se pierde ni se toma como pausa; la carga solo se asoma si tarda (`PlayerPresentation`, `.soon`).
- Si el motor no puede rearmar (el enlace caducó), se pide otra vez donde ibas, se ve la carga y, si ya tocaste play, suena
  solo al abrir.
- `PlayerModelTests` («volver a la app nunca te hace esperar») lo cuida. En la TV no aplica (no hay segundo plano).

### Una sola escala de clasificación por idioma (12 nov 2026)

Fernando: «Si pides metadatos en español, que lo hagas siempre mexicana […]. Si lo pides en inglés o cualquier otra que no
sea en español latino, que te dé [la de EE. UU.]». La regla: **una sola escala de clasificación por idioma: en español, la
mexicana; en cualquier otro, la de EE. UU.; nunca se muestra el dato crudo de otro país.**

- Toda clasificación pasa por `Certification.resolve(mx:us:kind:language:)` con el idioma de las fichas (`uiLanguage`); sin
  la de su escala, se convierte la otra (R → B15, TV-MA → C; B15 → R o TV-14). Sin ninguna de las dos, no se enseña nada.
- La tabla y los casos son `design/clasificaciones.json` (los mismos de la TV); `CertificationTests` falla si el iPhone
  copia otra cosa o un caso sale distinto.

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
| Aprende | `graduationcap` (`DS.Symbol.learn`) | Ajustes › Aprende y la portada de Aprende; antes el destello, que es de Explorar (AJ-A, 20 nov 2026; `testSparklesOnlyMeansDiscover`) |
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
| Regresar el ajuste a cero | `0.circle` (`DS.Symbol.resetDelay`) | Sincronía, «Volver a cero» |
| Tamaño de los subtítulos | `textformat.size` (`DS.Symbol.subtitleSize`) | «Audio y subtítulos» › Tamaño |
| Pista de audio | `speaker.wave.2` (`DS.Symbol.audioTrack`) | «Audio y subtítulos» › Audio |
| Versión del video | `square.stack` (`DS.Symbol.videoVersion`) | «Audio y subtítulos» › Versión |
| Subtítulos para sordos | `ear` (`DS.Symbol.hearingImpaired`) | Versiones de subtítulos, con la palabra |
| Subtítulos forzados | `quote.bubble` (`DS.Symbol.forcedSubtitles`) | Versiones de subtítulos, con la palabra |
| Una versión de subtítulos | `captions.bubble` (`DS.Symbol.subtitleVersion`) | Versiones de subtítulos |
| Marcar como visto | `checkmark.circle` / `checkmark.circle.fill` (`DS.Symbol.watched`, `watchedFill`) | Mosaico «Vista» de la ficha (lleno y en verde: ya la viste) |
| Volver a empezar | `arrow.left.to.line` (`DS.Symbol.restart`) | «Desde el principio», junto al avance (R1) |
| Tu nota | `note.text.badge.plus` / `note.text` (`DS.Symbol.addNote`, `note`) | Al final de «Tu calificación» |
| Calificar | `star` (`DS.Symbol.rate`) | «Calificar la temporada», en el menú de «Vista» |
| De este episodio en adelante | `arrow.right.circle` (`DS.Symbol.fromHereOn`) | «¿Para el resto de la serie también?» › «Sí, desde aquí» |
| Solo este episodio | `1.circle` (`DS.Symbol.onlyThisOne`) | «¿Para el resto de la serie también?» |
| Salir del reproductor | `rectangle.portrait.and.arrow.right` (`DS.Symbol.leavePlayer`, igual a `leave`) | «¿Sigues viendo?» › «Salir» (la ✕ de la barra del reproductor) |
| Decide por mí (el sorteo), y nada más | `dice` (`DS.Symbol.decide`) | La entrada de «Decide por mí» y su vacío por filtros |
| Las temporadas de la dona (de cuáles sale el episodio) | `rectangle.stack.badge.play` (`DS.Symbol.channelSeasons`) | Inicio › Canales › la dona › Temporadas |
| Repartido por décadas (una de cada época) | `calendar.day.timeline.left` (`DS.Symbol.spreadDecades`) | Filtro avanzado › Época |
| Tres que caben (tres carteles lado a lado) | `rectangle.split.3x1` (`DS.Symbol.decideTrio`) | «Decide por mí», su primera pestaña |
| Una por una (el mazo) | `rectangle.portrait.on.rectangle.portrait.angled` (`DS.Symbol.decideDeck`) | «Decide por mí», su segunda pestaña |
| Filtros (abre la hoja de filtros) | `slider.horizontal.3` (`DS.Symbol.refine`) | «Decide por mí», el botón «Filtros» de las dos pestañas y lo de afinar en la línea de lo puesto |
| Duración | `clock` (`DS.Symbol.filterTime`) | «Decide por mí» › Filtros › Duración, y en la línea de lo puesto |
| Ánimo (sin elegir) | `face.smiling` (`DS.Symbol.filterMood`) | Lo mismo; elegido, el ícono de su ánimo |
| Calificación | la estrella de calificar (`DS.Symbol.filterRating`, igual a `rate`) | «Decide por mí» › Filtros › Calificación y Letterboxd |
| Barajar | `shuffle` (`DS.Symbol.shuffle`) | «Tres que caben» |
| Paso · Guardar · Para hoy | `hand.thumbsdown.fill`, `bookmark.fill` (= `saved`), `pin.fill` (`DS.Symbol.matchPass`, `matchKeep`, `matchTonight`) | «Una por una»: los botones y el sello de la carta |
| Botones de otras consolas | `xmark`, `circle`, `square`, `triangle`, `line.3.horizontal`, `rectangle.on.rectangle` (`DS.Symbol.padCross`, `padCircle`, `padSquare`, `padTriangle`, `padMenu`, `padView`) | El acompañante del juego (cómo quedan los botones) |
| El mosaico | `square.grid.3x3` (`DS.Symbol.mosaic`) | La chapa de la portada de Explorar, el mosaico vacío. Solo él usa la cuadrícula de 3×3 (MO1) |
| «Lo que ves» | `chart.bar.xaxis` (`DS.Symbol.whatYouWatch`) | El índice de Explorar (antes la cuadrícula rellena, que se confundía con el mosaico) |
| Toda la serie (descargar) | `square.stack.3d.up` (`DS.Symbol.wholeSeries`) | «Descargar» de una serie (antes la cuadrícula del mosaico) |
| Cerrar y regresar | `xmark` (`DS.Symbol.close`) | Salir del mosaico en el iPad y la Mac (F1); «Cerrar» del panel de una ficha |
| Quitar (de una lista, un filtro, la búsqueda, el recordatorio de calificar) | `minus` (`DS.Symbol.remove`) | «Quitar de Seguir viendo», «Quitar de vistas», «Quitar filtros», la ficha de un filtro, «No calificar esta» (OI-8, 20 nov 2026: la ✕ es solo cerrar) |
| Salir (del video en la TV, del reproductor) | `rectangle.portrait.and.arrow.right` (`DS.Symbol.leave`) | «Salir del video», la tecla «Salir» del control, «¿Sigues viendo?» › «Salir» (OI-8) |

«Todo» del selector de tipo se queda con su 2×2 (`KindGlyph.all`): ninguna cuadrícula significa dos cosas.

### Lo que crece no choca (13 nov 2026)

Fernando, del selector de Inicio: «como que lo tocas y como que rebota de inmediato en los botones que están arriba a la
derecha». Era un resorte con rebote (`morph`, 0.22) y un renglón que, abierto, no cabía: el logo brincaba a la izquierda y la
cápsula se salía de su margen. La regla, para todo lo que se abre junto a otra cosa:

- **Lo de al lado cede primero.** Lo que crece usa `DS.Motion.grow` (resorte que se asienta casi sin pasarse) y lo que le
  deja el lugar `DS.Motion.fold` (sin rebote y más rápido). Nunca dos resortes con rebote que se acercan al mismo tiempo.
- **Abierto cabe.** El estado abierto se mide en el iPhone grande y en el SE: si no cabe, lo de al lado se va (en el SE la
  cápsula entera) o se quita aire, nunca se ensancha el renglón.
- **Abrir es más lento que cerrar.** Abrir con `grow`; cerrar con `fold`. Lo que sobra al cerrar se apaga rápido
  (`DS.Motion.fadeQuick`) antes de que lo demás se recoja: no se encima.
- **Nada nace de la nada.** Lo que llega entra desde un tamaño cercano al suyo (`DS.KindPill.enterScale`, 0.8) del lado de
  donde sale, uno tras otro (`DS.KindPill.stagger`); lo elegido viaja (un solo círculo, no dos que se cruzan).
- **Lo elegido se ve antes de recogerse, y cabe.** Tras elegir, la pastilla se queda abierta un momento
  (`DS.KindPill.settle`, 900 ms; nunca menos de medio segundo) y entonces se recoge. En ese momento las otras opciones se van
  y en su lugar se lee el nombre de lo elegido («Películas»): un ícono solo no dice qué escogiste. El círculo de lo elegido es más chico
  que su lugar (`DS.KindPill.markInset`) y la pastilla recorta: nunca se asoma por la orilla (Fernando, 13 nov 2026).
- **Todo se interrumpe.** Los resortes retoman desde donde van y un cierre que espera (`Task.sleep`) se cancela con el
  siguiente toque. Al apretar responde ya (`DS.Motion.press`). Con «Reducir movimiento», solo fundidos.

`DesignRulesTests+Motion.swift` lo cuida: `grow` con rebote ≤ 0.1 y más lento que `fold`, `enterScale` ≥ 0.75, y el selector
de tipo (`KindPill`, la misma pieza en Inicio, Explorar y las listas) y la cápsula de Inicio sin resortes con rebote.

### Un filtro que se ve puesto, filtra (13 nov 2026)

Fernando, al pedir el pulido de «Decide por mí» (DE1): «Construye DE1 y DE2 para ver cómo se ven. Antes de decidir». La
auditoría (F3) encontró que la cápsula del tiempo decía «⏱ 1 h» y el menú lo marcaba, pero salían películas de tres horas: el
tiempo de la hora solo ordenaba.

- **Lo que se ve puesto es lo que filtra.** Un filtro que la app propone sola (el tiempo según la hora) ordena, pero no se
  enseña puesto: el ícono del tiempo no se llena ni sale en la línea de lo puesto hasta que eliges uno, y el menú trae
  «Cualquier duración» para volver.
  «Nada con…» nombra solo lo que tú pusiste (antes culpaba al «1 h» que no elegiste).
- **Una opción que no deja nada no se toca** («Documental · 0», «Óscar · 0»): va gris y apagada; si ya estaba puesta, sí se
  puede quitar (`DecideModel.offered`).
- **Las opciones de un filtro llevan ícono o arte**, no cápsulas de solo texto: géneros y épocas son mosaicos con su imagen
  (las épocas en la misma cuadrícula de tres: «2020s» y «90s» miden lo mismo), «Fama» es el cuadro del filtro avanzado
  (`FameQuadrant`, con cuántas quedan en cada esquina) y «Premios» las estatuillas (`FilterLogoChoice`). De qué listas usa las
  pestañas de texto (`DSTextTabs`).
- **Sin huecos ni botones que no hacen nada**: con una o dos opciones los carteles miden lo mismo y van centrados
  (`DecideTrioLayout`); «Barajar» se apaga si no hay más (`canShuffle`).
- **Sin red no se culpa a los filtros**: «Sin conexión · Reintentar» (`DecideModel.empty`: sin conexión, sin sugerencias o por
  los filtros; solo el último ofrece qué quitar). El mazo y su tarjeta de Explorar dicen lo mismo, y la tarjeta no desaparece.
- «Mi lista», Favoritos, «Tus series» y tus listas van bajo «Tus listas» en «De qué listas», no bajo «Sugerencias».
- La hoja lleva ✕; con letra de accesibilidad la cuenta baja bajo el título y la hoja se abre completa si no cabe.

### Lo que quitas se puede deshacer (13 nov 2026)

Mismo pedido (F5): «No me interesa» era para siempre (quita la sugerencia de Para ti y de la TV) y no tenía vuelta; en el mazo
solo «Guardar» tenía «Deshacer».

- **Todo lo que aparta algo de lo que te proponen avisa con «Deshacer»**: «No me interesa» («Ya no te la sugiero · Deshacer») y
  «Hoy no» en Decide; «Paso» y «Para hoy» («Para hoy · Ver ya · ↩︎») en el mazo, como «Guardar». Deshacer lo regresa a su
  lugar y vuelve a sugerirse.
- **Lo que sale del aparato espera a que ya no se pueda deshacer**: a la TV se le avisa «No me interesa» al quitar otra o al
  cerrar la hoja (`DecideModel.commitDismissals`), nunca en el momento.
- Los avisos de una hoja o pantalla completa van dentro de ella (`BannerView` con `coverShowsNotices`), no detrás.
- El dado es solo «Decide por mí» (tabla de íconos).
- **Todo «Quitar de …» de un título avisa con «Deshacer»** (Mi lista, una lista, favoritos y Seguir viendo). Si quitarlo borra
  algo que no se recupera al volver a agregarlo (tu avance en Trakt), sale de la pantalla al instante y del aparato hasta que
  el aviso ya se fue (`HomeModel.dismiss(_:undoWindow:)`, `DS.Timing.undoCommit`). Nació en el recorrido de la Mac del 16 nov
  2026: «Quitar de Seguir viendo» no tenía vuelta. Lo cuidan `DesignRulesTests+Quitar.swift` y
  `ScreenModelsTests.testRemovingFromContinueWaitsForUndoBeforeLeavingThePhone`.
- **«Borrar» una descarga también avisa con «Deshacer»** (una descarga, un título o una temporada): sale de la lista al
  instante y el archivo se borra hasta que el aviso ya se fue (`DownloadsModel.deleteWithUndo`, D1-A, Fernando, 16 nov 2026:
  volver a bajarla tarda y gasta datos). Ningún «Borrar» de Descargas llama a `delete(` directo. Lo cuidan
  `DesignRulesTests+Quitar.swift` (`testDeletingADownloadOffersUndo`) y
  `ScreenModelsTests.testDeletingADownloadCanBeUndoneUntilTheNoticeIsGone`.

Lo cuidan `DecidePolishTests` (OrbitalModelsTests) y `DesignRulesTests+Decide.swift`. En la TV: «No me interesa» de su Decide
tampoco tiene «Deshacer» (pendiente en el registro de paridad); lo demás de la TV no cambia.

### Una pregunta, una puerta (13 nov 2026)

DE2 (Fernando: «Construye DE1 y DE2 para ver cómo se ven»): «¿Qué vemos?» tenía dos puertas en Explorar (el dado de la barra y
la tarjeta «¿Qué vemos hoy?») que llevaban a dos pantallas con filtros distintos.

- **Una pregunta tiene una sola puerta y un solo nombre**: «Decide por mí» (tarjeta `DecideDoor` en Explorar, la misma tarjeta
  con el mismo abanico de carteles en Inicio, `DecideHomeRow`; el abanico sale de lo mismo que alimenta la hoja,
  `ParaTiModel.decideFan`). **La puerta abre la hoja donde estás**: desde Inicio, sobre Inicio (`DecideSheet`, 13 nov 2026;
  antes te mandaba a Explorar), con lo mismo que en Explorar (`decidePool`: «Porque viste», el mosaico y cada estante que se
  ve); si aún no carga, la hoja dice que carga en vez de abrirse vacía. Adentro, las maneras de contestarla son pestañas (`DSTextTabs`): «Tres que caben» y «Una por
  una», con los nombres de la TV.
- **Las pestañas de una misma pregunta comparten sus filtros**: lo que pones en «Filtros» filtra las dos
  (`DecideModel.deckPool`); el tiempo y el ánimo son solo de «Tres que caben» (son de esta noche).
- No se agrega otra puerta (otro botón en la barra, otra tarjeta) a algo que ya tiene la suya.

Lo cuida `DesignRulesTests+Decide.swift` (`testOneQuestionOneDoor`) y `DecideDeckTests`.

### Una hoja, un renglón de controles; lo puesto se dice en una línea (13 nov 2026)

Fernando, al quedarse con DE2: «Solamente ayúdame a pulir dentro de las tres que caben y una por una. Porque las veo un poco
crudas». Arriba había cuatro renglones (la cuenta, las pestañas, el tipo y una rejilla de cápsulas «⏱ Cualquier duración ⌄»)
y las dos pestañas tenían filtros distintos y en otro lugar.

- **Un renglón de controles por hoja**, debajo de sus pestañas y **idéntico en todas ellas**: el tipo (`DSKindFilter`) a la
  izquierda y **un solo botón «Filtros»** a la derecha (`DSFiltersButton`, el mismo círculo de vidrio que la pastilla del
  tipo; Fernando, 13 nov 2026: en lugar de cuatro íconos), con el mismo ícono, lugar y numerito en las dos pestañas. Siempre
  en un renglón: los dos son de tamaño fijo (hasta xxxLarge) y caben juntos aun en un SE.
- **Una sola hoja de filtros** (`DecideFilters`), por secciones con los encabezados de dos niveles: «Esta noche» (duración y
  ánimo), «Qué tan buena» (calificación, según quién, Letterboxd, fama, premios), «Qué tipo» (géneros, época) y «De dónde»
  (listas, lo ya visto). En una pestaña donde una sección no aplica (el mazo: «Esta noche») se ve apagada y lo dice; nunca
  desaparece lo que cuenta en el numerito. Las opciones son baldosas con ícono **y nombre** (`DecideChoice`) o con su arte
  (`DecideTile`), con cuántas quedan; arriba, cuántas opciones quedan mientras eliges; abajo «Ver N»; arriba a la derecha
  «Quitar filtros» (todo menos el tipo). Se aplica al regresar, y solo si cambió algo.
  Las baldosas de una fila miden lo mismo y todas las filas cuelgan de las mismas orillas (ver «Un número dice lo de
  ahora»).
- **Puesto se ve**: el botón se llena de su tinte y lleva cuántos hay; cada sección tiene el suyo (`DS.DecideLive`). Sin
  cápsulas de texto.
- **Lo puesto se dice en una línea** debajo del renglón («1 h · Ligero · 7+ · Comedia», cada parte con el color de su
  sección), y tocarla ofrece «Cambiar filtros», quitar cada uno o todos. Sin nada puesto, la línea no existe (no queda «Sin
  filtros» ni un hueco).
- **La cuenta va junto al título** («128 opciones»), no en su propio renglón.

### Un número dice lo de ahora; las filas de opciones son parejas (13 nov 2026)

Fernando, la hoja de filtros: en «Calificación» las baldosas decían «0» mientras arriba decía «33 opciones». Causa: los
números se calculaban dentro de una rejilla perezosa (`LazyVGrid`), que guarda sus celdas de la primera vez; los datos de
Cinemeta llegaban después (y avisaban), la cuenta de arriba subía y las baldosas no. Además, lo que llegaba antes de
TMDB o Letterboxd creaba un detalle vacío y la calificación de IMDb ya no se pedía.

- **Qué dice cada número** (`DecideModel.tally`): arriba y «Ver N», cuántas quedan con lo puesto; cada baldosa, cuántas
  quedarían **si eliges esa**, con todo lo demás puesto (en los grupos de varias —géneros, épocas, premios— con esa sola en
  su grupo). La baldosa elegida dice lo mismo que arriba. En «Una por una» todo cuenta como el mazo (sin tiempo ni ánimo).
- **Un número que aún no se sabe no se enseña**: nunca un «0» que luego resulta 12 (`Tally.shown` es nil mientras falta
  saber) y la baldosa no se apaga. Arriba dice «Buscando opciones…».
- **Los números se calculan en el `body` de la hoja**, no dentro de una celda perezosa: una lista de opciones con números
  va en `DecideChoiceGrid` (un `Grid`). Lo que llega en segundo plano avisa **una vez por tanda** (`describe`, cada tanda de
  12), no una por título; elegir una propuesta junta sus tres campos en un aviso (`coalescing`).
- **Las baldosas de una fila miden lo mismo** (ancho y alto, aunque una parta su nombre en dos renglones o aún no tenga
  número: el renglón del número siempre se aparta) y **todas las filas usan las mismas columnas**: tres (el ánimo, dos por
  dos); con letra de accesibilidad, dos.
- «Quitar filtros» es texto discreto arriba a la derecha y solo aparece cuando hay algo que quitar.
- Los logos de «Según» caben en el mismo ancho (`DS.Filter.ratingLogo`): IMDb y TMDB ya no se ven más grandes que Trakt.

Lo cuidan `DecideCountsTests` (OrbitalModelsTests), `testFilterNumbersAreFreshAndRowsEven` y `DecidePolishUITests`
(mide filas, márgenes y que arriba = «Ver N» = la baldosa elegida).

### Un botón fijo abajo deja ver lo que pasa debajo (13 nov 2026)

«Ver 33» tapaba a medias los logos de «Según». **Un botón o barra fija al pie de algo que se desliza va en
`safeAreaBar(edge: .bottom)`**: lo que pasa por debajo se funde y el último renglón se puede subir por encima. Nunca
`safeAreaInset(edge: .bottom)`, salvo sobre algo que no se desliza (la cámara del lector QR, con `ds-exception`). Arreglados
también la guía, el filtro avanzado, «De qué listas», la barra de elegir varios de Mi lista y la de «Lo que sigue» de la
repisa. Lo cuida `testFixedBottomButtonLetsContentShowThrough`.

### Los datos son de la carta que se ve (13 nov 2026)

En «Una por una», al tocar «Paso» la carta salía volando pero debajo seguía escrito su nombre un segundo, ya con la siguiente
arriba. **Lo que describe una pieza que se va cambia en cuanto se va, no cuando el modelo la quita**: el mazo marca la que
va volando (`leaving`) y los datos son de la primera que no se está yendo. Lo cuida `testCardInfoFollowsTheVisibleCard`.

### VoiceOver dice el nombre que se lee (13 nov 2026)

El cartel elegido de «Tres que caben» se anunciaba «The Office» y debajo se leía «La Oficina». **La etiqueta de accesibilidad
de un título usa `titleName`, igual que el texto que se ve**, nunca `.title` crudo. Lo cuida `testSpokenTitleIsTheShownTitle`.

### Ninguna tarea sobrevive a su vista (13 nov 2026)

Tras el congelamiento de «Una por una» el registro traía un segundo cierre (`swift::AsyncTask::completeFuture` →
`__cxa_pure_virtual`): tareas que seguían vivas después de cerrar la hoja. **Una tarea que lanza una vista se guarda y se
cancela al desaparecer** (Barajar, la carta que sale volando) y revisa `Task.isCancelled` después de cada espera; **un
modelo cerrado no empieza nada nuevo** (`DecideModel.stopped`: la hoja de filtros aplicaba al desaparecer aunque la hoja ya
se hubiera cerrado). Lo cuida `testNoTaskOutlivesItsView`.

### Los datos no se enciman con el arte; lo elegido crece (13 nov 2026)

Mismo pulido. En «Una por una» el nombre, los datos y las cápsulas de géneros iban sobre el póster con un velo, el ▶ flotaba
encima y la carta dejaba franjas oscuras a los lados; en «Tres que caben» la elegida llevaba un marco blanco y las otras se
encogían y apagaban.

- **El arte llena su carta**: la carta mide lo que su póster (`DS.Poster.aspect`), con las esquinas y la sombra de la carta,
  y en el iPad no pasa de `DS.Match.cardMax`. Encima solo va lo que dice qué pasa al arrastrarla (el tinte y el sello).
- **Los datos van debajo, alineados a la orilla de la carta** (`MatchCardInfo`): el porqué en turquesa, el nombre y una sola
  línea «2026 · Película · Acción, Aventura, Comedia» (géneros en texto, no en cápsulas). Cada renglón aparta su lugar
  (`reservesSpace`): al pasar de carta el texto se funde y nada brinca.
- **Lo que sigue asoma**: las de atrás, un poco más chicas desde su orilla de abajo, se asoman `DS.Match.behindPeek` cada una.
  Soltada antes del umbral, la carta regresa sin rebote (`DS.Motion.snap`).
- **Las acciones son una sola familia**: Paso · Para hoy · Guardar · Ver, cuatro círculos iguales con su nombre debajo, de
  margen a margen; el color solo en las tres que mandan la carta a un lado (el de su sello). Nada flota sobre el arte.
- **Un juego de carteles**: los tres miden lo mismo y van sobre la misma base (`DecideTrioLayout`); la elegida crece un poco
  desde abajo con su sombra (`DS.Motion.grow`, la otra se recoge con `fold`). Sin marco ni las otras apagadas o más chicas.
  Sus datos van al margen con el alto apartado; Ver se estira y Barajar y «⋯» son círculos del mismo alto.

Lo cuida `DesignRulesTests+Decide.swift` (`testOneControlRowPerSheet`, `testDataDoesNotSitOnTheArt`). En la TV no cambia: su
carta ya lleva el nombre debajo del póster; revisar que sus filtros vayan en un solo renglón queda en el registro de paridad.

### Decide se siente vivo (13 nov 2026)

Fernando: «Pon un toque de color, hazlos más bonitos… poner una animación, una interacción». Lo que se toca en «Decide por
mí» responde, sin adornos que distraigan:

- **Cada filtro con su color** (`DS.DecideLive`: duración, ánimo, calificación y lo demás), sacado de los tintes de las listas;
  nunca el turquesa, que es de la voz y del porqué. Elegir llena la baldosa creciendo con un resorte corto
  (`DS.Motion.grow`), el ícono da un saltito (`symbolEffect(.bounce)`, una vez) y el teléfono marca la selección.
- **Barajar**: los tres salen encogiéndose uno tras otro y los nuevos entran subiendo en cascada; el ícono salta. Detrás de los
  tres, un resplandor suave del color del cartel elegido (`ArtTint`, el mismo de la ficha).
- **El mazo**: la carta se inclina al arrastrarla, su sello crece con el avance, las de atrás van subiendo, el teléfono da un
  toque al cruzar el umbral y la carta sale con la velocidad del dedo; los botones de abajo se encienden del color de su lado.
  Un botón manda la carta igual que el dedo.
- **Las pestañas**: la rayita viaja a la elegida y el contenido entra de su lado (`tabTransition`) con un fundido; el
  encabezado se queda quieto.
- Todo con `DS.Motion`, solo propiedades baratas (escala, opacidad, desplazamiento), interrumpible, sin animaciones sin fin;
  con «Reducir movimiento», fundidos.

### Cambiar de tipo no vuelve a barajar (13 nov 2026)

Fernando: al pasar de Todo a Películas y regresar salían otros tres. **Lo que ves con cada tipo se recuerda mientras la hoja
está abierta** (`DecideModel.switchKind`): volver a un tipo regresa los mismos tres y la misma elegida, también al ir y venir de
pestaña. Solo «Barajar» o cambiar otro filtro barajan. El mazo no necesita memoria: su orden es fijo por día y lo que pasaste
o guardaste no vuelve. Lo cuida `DecideKindMemoryTests`.

**Del cartel a la carta, de verdad** (13 nov 2026): al pasar a «Una por una» el mazo empieza por el cartel que estaba
elegido (si pasa los filtros del mazo; `MatchDeckModel.lead`, el resto conserva su orden del día) y ese cartel crece hasta
volverse la carta (`matchedGeometryEffect`, `DecideView.heroKey`); de regreso, la carta de arriba vuelve a ser la elegida si
está entre los tres. El mazo vive en la hoja (no en su pestaña): ir y volver no lo recarga. Con «Reducir movimiento», solo la
transición de lado. Lo cuidan `DecidePolishUITests` y `MatchDeckLeadTests`.

### ViewThatFits no se anida ni vive bajo alineación por línea base (13 nov 2026)

La 2291–2293 se colgaba al abrir «Una por una» (registro 0x8BADF00D: el hilo principal atorado en `explicitAlignment` de
`ViewThatFits` dentro de pilas por línea base, varios niveles). `ViewThatFits` mide cada rama; si adentro hay otro, una pila
por línea base o una guía de alineación, o si vive dentro de una pila alineada por línea base o por `.sectionTitle`, cada
pregunta de alineación vuelve a medirlo todo, y en una hoja que cambia de alto eso pasa en cada cuadro.

- **Un `ViewThatFits` por rama, nunca uno dentro de otro, sin pilas por línea base ni guías de alineación adentro y nunca
  dentro de una pila alineada por línea base.** Para elegir forma, decide por el tamaño de letra (`dynamicTypeSize`) o con una
  pieza de `Layout`.
- En un encabezado que se mide muy seguido (la hoja de Decide), ningún `ViewThatFits`: las pestañas usan `adapts: false`.
- **Si elige entre una lista (`ForEach`), se rearma cuando la lista cambia** (`.id(opciones)`). En la Mac la 2458 tronó cuatro
  veces seguidas en Explorar cuando la tira de pósters cambiaba cuántas opciones tenía mientras llegaban
  (`DesignRulesTests+Sheets`, `testListChoicesRebuildWhenTheyChange`).
- Arreglados también el encabezado de sección (`DSSectionHead` con sello), las fuentes («Recomendada») y los sustos del control.

Lo cuida `DesignRulesTests+Layout.swift` (`testViewThatFitsIsNotNestedNorUnderBaseline`) en todo `ios/App/Sources`.

### Un gesto de contenido nunca tapa los controles de la hoja (13 nov 2026)

Fernando, la 2291: «de "Una por una" ya no deja regresar a "Tres que caben"». **Los controles de una hoja (título, pestañas,
filtros) son uno solo, se quedan quietos y van encima del contenido**: lo que se arrastra o sale volando (la carta del mazo)
nunca les quita los toques. En Decide el encabezado es el mismo para las dos pestañas, con `zIndex` sobre el contenido, y
cambia solo lo de abajo. Lo cuidan `testContentGestureNeverCoversSheetControls` y `DecideTabsUITests` (ida y vuelta, después
de arrastrar una carta y abriendo «Filtros» en las dos pestañas, con tiempos límite).

### En una hoja, lo que crece cede ante los controles (13 nov 2026)

Fernando, en su 17 Pro: «hay que pulir el tamaño de los botones debajo porque se comen, se cortan con la tarjeta». **Los
controles y sus nombres apartan su alto primero; lo que crece (la carta, un cartel) toma lo que sobra** y se achica guardando
su forma. En el mazo los cuatro botones y los datos de la carta se acomodan antes y la carta toma el resto
(`MatchDeckLayout`, en una pasada, sin estados que se persigan), con cualquier letra (ya no se desliza a un alto fijo), y el
mazo se queda sobre el área segura. Nada se encima ni se recorta. Lo cuidan `testGrowingContentYieldsToControls` y
`DecideTabsUITests` (los datos terminan antes que los botones y los botones caben en la pantalla, también con letra grande).

### La puerta de algo grande es grande y tiene nombre (13 nov 2026)

Fernando, del mosaico: «lo saquemos de la barra de menú que está arriba y lo pongamos de manera creativa abajo… mejorar el
discoverability de que hay un mosaico». Decidió MO1 («Vamos con MO1»): **la portada es la puerta**.

- **Regla: nada importante vive solo como un ícono en una barra.** Una función grande (un modo, una pantalla entera) tiene una
  puerta grande en el contenido, con su ícono y su nombre, que se toca entera y se hunde al tocarla (`DS.Motion.press`). La
  barra de arriba es para herramientas de la pantalla (ir a una sección, el perfil), no para puertas.
- **El mosaico:** su puerta es la portada inclinada de Explorar (`MosaicCover`). Lleva su chapa de vidrio anclada abajo a la
  izquierda, dentro de la portada (`MosaicDoorBadge`: la cuadrícula del mosaico y «Pasea por tus 96», con el número real de
  piezas; con letra grande parte en dos renglones). Al tocarla el muro se endereza y crece (`DS.Motion.grow`) y el mosaico
  entra creciendo desde arriba (`MosaicCover.mosaicTransition`); al salir, el mosaico se encoge hacia arriba y la portada
  vuelve derecha y se inclina (`DS.Motion.fold`). Con «Reducir movimiento», solo fundidos.
- **La primera vez** (una sola, `mosaic-door-hint-seen` en los ajustes locales; nunca con «Reducir movimiento» ni fuera de
  pantalla) la portada se endereza sola un momento (`DS.ParaTiB.doorHintHold`) y regresa: enseña que se abre. No mueve el
  contenido: solo gira y crece el arte dentro de su marco.
- **Jalar:** «jalar para actualizar» se queda como está y la puerta va **más allá**: jalar poco (hasta `DS.Refresh.threshold`)
  actualiza con la luna; seguir jalando (hasta `DS.ParaTiB.doorPull`) apaga la luna y endereza la portada siguiendo al dedo;
  soltar ahí entra al mosaico y no actualiza; soltar antes regresa (o actualiza, si pasaste la luna). Solo cuenta con el dedo
  puesto (`RefreshPull.door`, `orbitalRefreshable(beyond:)`): la inercia no abre nada.
- **Sin piezas** (sin red, sin sugerencias): la portada no promete un muro vacío: sin chapa, no se toca y no hay puerta al
  jalar (F8).
- **Siempre una salida visible** del mosaico (F1), además de deslizar de lado: en el iPhone la flecha ‹ a la izquierda; en el
  iPad y la Mac la barra de pestañas va en ese renglón y manda lo de la izquierda a «⋯», así que ahí es ✕ «Regresar a
  Explorar» al final de la derecha, en el lugar del perfil (el perfil sigue en Explorar, Inicio y Buscar).
- Lo cuida `DesignRulesTests+Doors.swift`. En la TV: distinto a propósito (allá Explorar **es** el mosaico; registro de
  paridad).

### El control de una sección va en el renglón de su rótulo (13 nov 2026)

Fernando, del selector Todo · Películas · Series de Explorar: «está ahí como volando». Decidió X1.

- El control que filtra una sección (el selector de tipo de «Lo que se ve hoy») va **en el renglón de su rótulo, a la
  derecha**, alineado al margen y centrado con el rótulo, en lugar de la línea fina: `DSChapterHead(label:symbol:) { control }`.
  Es la regla «Lo que acompaña a un control va en su misma línea» aplicada a los encabezados.
- Si no cabe (SE, letra grande), baja **entero** a su renglón bajo el rótulo con su línea (`ViewThatFits`); nunca cortado ni
  achicado. Su comportamiento y su animación no cambian.
- Lo cuida `DesignRulesTests+Doors.swift`.

### Lo guardado se ve al entrar: pestañas, no un índice (13 nov 2026)

Fernando, GD2: «Pestañas, como la tele». El tablero de Guardado (G2-A, 9 nov) era un índice: cuatro tarjetas con cifras que
había que tocar para ver algo, y cada una abría una pantalla distinta. La regla:

- **Al entrar se ven los pósters.** Guardado abre en «Mi lista» con su cuadrícula. Arriba, sus cuatro partes con ícono, cifra
  y nombre (Mi lista · Viendo · Vistas · Listas) en el selector de Orbital completo (SG1, `DSSelector`), para que no se
  confunda con las pestañas subrayadas de la Biblioteca. Se recuerda la última.
- **Abajo del selector, un renglón (R1).** A la izquierda el orden elegido (una sola vez: no se repite dentro de ⊜); a la
  derecha Todo · Películas · Series, ⊜, ＋ y elegir varios, todos con ícono y siempre en ese orden. Lo que no aplica no
  aparece: ＋ solo donde agrega algo (Mi lista, Listas, Historial), y Listas no lleva tipo ni filtro.
- **Lo de una parte vive dentro de ella, sin otro renglón de pestañas (VS2).** En «Vistas», ⊜ elige Terminadas o Las dejé y el
  reloj abre el Historial (cada vez que viste algo, con su día y su hora) en su propia pantalla.
- **Una lista abierta es la misma pantalla de lista** y lleva el mismo cielo que el resto de Guardado.

### Sin conexión nunca se ve como vacío (13 nov 2026)

Sin internet (o con Trakt sin contestar) una pantalla no dice «no tienes nada»: dice «Sin conexión» con «Reintentar»
(`DSErrorState`). Se revisa **antes** de decidir que algo está vacío: en el modelo, «no llegó» (`failed`, `unreachable`) es
distinto de «llegó vacío». Lo que ya se tenía se sigue viendo; el aviso sale solo cuando no hay nada que enseñar.

### Un vacío enseña qué hacer (13 nov 2026)

Un vacío trae su ícono, qué pasa y **un botón a dónde ir** («Explorar», «Agregar», «Buscar qué ver», «Conectar Trakt»), no solo
un letrero. Una cuenta nueva ve una sola guía para todo Guardado, no cuatro pestañas vacías; una pestaña en cero que no aplica
(«Las dejé») no aparece. El aviso flotante «¿Qué tal…?» deja su alto libre abajo (`ratingReminderHeight`) para no tapar lo
último de la pantalla.

`DesignRulesTests+Saved.swift` lo cuida: Guardado usa `DSSelector` completo con sus cuatro partes en orden y sin el tablero ni sus
pantallas por estado, revisa «sin conexión» antes que «vacío» (también en una lista abierta), cada `DSEmptyState` de Guardado
lleva símbolo y botón, deja lugar a «¿Qué tal…?» y las listas abiertas llevan el cielo (`Backdrop`).

### El arte nunca enseña su orilla (13 nov 2026)

Fernando, de la ficha: «cuando le das para abajo… sale como un color sólido que corta el póster». Decidió AR1 · «Se funde».
El arte nunca enseña su orilla: se funde con el fondo que de verdad tiene detrás; nada de un color pintado encima.

- **Sin velo de color encima.** Al bajar, el arte de la ficha (`BleedArt(collapses:)`) se desenfoca y se desvanece y deja
  ver el `Backdrop` que ya estaba detrás: el mismo color a los dos lados de la frontera. No hay velo ni degradado del tono
  del arte que lo cubra (eso era el «bloque» café, rojo vino u ocre con el borde recto).
- **Nada lo recorta mientras se mueve.** El arte se va con el contenido (sin parallax ni encogido, que lo sacaban de su
  marco o dejaban costuras a los lados). El origen del zoom hacia el reproductor (`playerZoomSource`) es un marco quieto
  detrás del arte, no el arte: su esquina recortaba lo que se movía.
- **Arriba, una transición larga.** Lo que sube bajo la barra se desvanece en `DS.TitleAction.topFade` (~96 pt, antes 36):
  no queda una franja de color con orilla ni texto cortado a la mitad (el SE). En el iPad, detrás de la ficha va el mismo
  fondo de la sala (`DS.backdropDeep`) que hay debajo del arte, sin la franja del tono.
- **En claro** el arte es una tarjeta: sube nítida con el contenido, sin velo ni desenfoque (desenfocada se lavaba a un
  rectángulo gris). El logo chico de la barra va en el color del texto sobre el papel (uno blanco no se leía).
- Con «Reducir movimiento» o «Reducir transparencia», solo el desvanecido, sin desenfoque.

`DesignRulesTests+ArtEdge.swift` lo cuida (sin velo ni `Backdrop.tone` sobre el arte, sin parallax ni encogido en
`HeroCollapse`, el zoom desde un marco quieto, `topFade` ≥ 90 y el iPad sin el fondo teñido). Los otros artes grandes (el
destacado de Inicio, la portada de una colección, «Lo que ves», una persona) no se recogen: se van con el contenido y se
funden con máscara o velo hacia el fondo, sin recorte que se mueva. En la TV el arte ya nunca enseña su orilla.

### «Mejor resultado» es la más conocida de las exactas (16 nov 2026)

Al buscar «matrix», lo grande arriba era la serie Matrix de 1993 y The Matrix quedaba abajo: con una película y una serie
que se llaman igual a lo que escribes, la serie ganaba solo por ir primero (S1-A, Fernando, 16 nov 2026: «también aplica
para el iPhone»). Cuando hay coincidencias exactas de los dos tipos, la búsqueda pide su ficha a Cinemeta (`popularity`) y
la más vista va primero; si tarda más de `SearchModel.tieLimit`, se queda el orden de antes. Con una sola exacta («office»)
no se pregunta nada. Pruebas: `CinemetaTests.testTheBestKnownExactMatchWinsTheTopSpot` y
`ScreenModelsTests.testSearchPutsTheBestKnownOfTwoExactMatchesFirst`.

### Un buscador que flota tapa lo que pasa por debajo (13 nov 2026)

En Buscar, al subir a media página, el campo regresaba con la barra y los filtros y mosaicos se veían a través de él, como
si estuviera encima de ellos (Fernando, 13 nov 2026). Toda pantalla con `.searchable` lleva
`.scrollEdgeEffectStyle(.hard, for: .top)`: lo que pasa bajo la barra y el campo se tapa, como en Inicio. Prueba:
`DesignRulesTests+SystemCallbacks` (`testSearchFieldsHideWhatPassesUnder`) y `SearchBarOverlapUITests`.

### Un listón no recorta lo que crece (13 nov 2026)

Un póster de un listón que crece al picarlo, al dejarlo apretado o con el puntero se cortaba en la orilla de la fila: la caja
se quedaba fija y el póster crecía adentro (Fernando, 13 nov 2026). Todo `ScrollView(.horizontal …)` lleva
`.scrollClipDisabled()`. La única excepción es un carrusel de página completa, donde la página de al lado no debe asomar,
y lleva `// recorta: <motivo>` en la línea del `ScrollView`. Prueba: `DesignRulesTests+SystemCallbacks`
(`testHorizontalRowsDoNotClipWhatGrows`).

### Las respuestas del sistema se arman fuera de la pantalla (13 nov 2026)

Un permiso (dictado, micrófono, notificaciones), el audio que entrega el micrófono o el resultado del reconocimiento de voz
llegan por un hilo que no es el de la pantalla. Escritos como cierre dentro de una clase `@MainActor`, Swift 6 los declara
de la pantalla y la app truena en cuanto llegan por otro hilo (la 2296: «truena al dar un comando de voz»). Se piden
desde una función `nonisolated` (o con la versión `async` del sistema) y solo vuelven a la pantalla con
`Task { @MainActor … }`. Prueba: `DesignRulesTests+SystemCallbacks`.

**Un solo selector (SL1, 13 nov 2026).** Para elegir qué ves aquí, `DSSelector` (completo en Guardado, normal en lo demás) y,
para el tipo, su tamaño compacto `DSKindFilter`, que dice el nombre de lo elegido («Todo», «Películas», «Series») adentro de la pastilla, a la izquierda de los íconos, y la pastilla mide justo lo que necesita: sin hueco apartado para el nombre más largo (KT2, 14 nov; antes KT1 lo ponía afuera). Donde va a la derecha (Guardado) los íconos no se mueven al elegir. Con un tipo elegido en Inicio, «Por lo que viste» arma su mazo solo con títulos de ese tipo (Trakt relaciona película con película y serie con serie; si no, salía «Trakt aún no relaciona nada»): `testBecauseDeckFollowsTheKind`. En Inicio, recién elegido, el nombre ocupa el lugar de lo que había a la izquierda: el círculo se queda donde lo tocaste y luego la pastilla se recoge, todo un poco más pausado (`DS.KindPill.pace`). Las pestañas subrayadas
(`DSTextTabs`) son solo para moverte entre partes: Biblioteca, la ficha y el reproductor. Sin `Picker` segmentado ni pestañas
armadas a mano. `testOneSelectorEverywhere` lo cuida.

**Un renglón de controles nunca empuja la página.** El renglón de una lista (orden, pastilla de tipo, ⊜, ＋, elegir varios)
va en `ListControlsRow`: decide con el ancho que le dan y, si no cabe (un SE, letra grande, el nombre «Series» en la
pastilla), la pastilla baja a su renglón. Nada de `HStack` a mano con piezas de ancho fijo: crecían más que la pantalla y los
pósters se salían por los lados. `testListControlsUseTheMeasuredRow` lo cuida; `OneSelectorUITests` mide que nada salga.

**Lo que eliges arriba se queda al cambiar de pestaña, y no se mueve.** En una pantalla con pestañas (Guardado), Todo · Películas
· Series es uno para todas: vive en la pantalla, no en cada pestaña, y cambiar de pestaña no lo regresa a «Todo». El renglón
aparta el lugar de sus íconos más anchos (`ListControlsRow(reservedIcons:)`), así la pastilla queda en el mismo sitio en cada
pestaña aunque una traiga más íconos que otra (Fernando, 13 nov 2026). `testSavedTabsShareTheKindFilter` y
`testListControlsUseTheMeasuredRow` lo cuidan.

**Las estrellas que se tocan se atinan.** `RatingStars` aparta un lugar táctil de 44 pt de alto (y un poco a cada lado) aunque
la estrella sea chica, y al arrastrar una burbuja arriba del dedo dice cuánto llevas («3½»). Donde calificas sin abrir nada
(la pastilla «¿Qué tal…?» y «Por calificar»), las estrellas van en `DS.Rating.starTouch` con más aire; `starInline` es solo
para las que se leen. La pastilla no se va sola mientras tienes el dedo encima (Fernando, 13 nov 2026: «es bien difícil
atinarle»). `testRatingStarsAreEasyToHit` lo cuida.

**La pastilla «¿Qué tal…?» es un solo renglón.** Sus letreros («Guardada», «y 2 más») llevan `.lineLimit(1)` y nunca se parten letra por letra; ya calificada, «y 2 más» se quita para dejarle su lugar a «Guardada» (14 nov 2026). Lo cuida `testRatingReminderLabelsStayOnOneLine`.

**Lo que suena en la tele siempre trae su póster.** El accesorio de la barra, la tarjeta del control y la Live Activity
pintan el arte de la TV y, si no llega o no carga, el póster de metahub del título (`NowPlaying.artFallback`); la Live
Activity vuelve a intentarlo en el siguiente sondeo y, mientras, enseña el ícono de la tele (nunca la flecha de descarga).
`testNowPlayingArtFallsBackToThePoster` y `testNowPlayingAlwaysHasAPoster` lo cuidan.

**Una imagen que falta busca otra antes de enseñar el nombre.** Ningún póster se queda en el nombre sobre color si el título
tiene imagen en algún lado: se prueba TMDB, luego metahub y al final IMDb (`ImdbPoster`); una portada hecha del fondo que no
carga pasa al póster. Mientras se decide qué imagen va, el marco espera quieto: nunca el nombre que luego brinca a la imagen
(23 nov 2026: 13 % de los resultados de Buscar no tenían nada en metahub ni en TMDB, e IMDb tenía 8 de cada 10; el destacado
de Inicio enseñaba el nombre hasta 1.5 s). `testPosterTriesEverySourceBeforeTheName`, `testWideArtFallsBackToThePoster` y
`testArtWaitsQuietlyWhileDeciding` lo cuidan. En una caja ancha (un episodio, «Seguir viendo», un tráiler) el nombre sobre color es solo la película, centrada: su nombre ya va al lado o abajo (`testAWideStandInIsCentered`).

**La marca es una sola en toda la app.** El Centro de control y la Live Activity usan el símbolo `orbital.mark`, que sale
del mismo dibujo que `OrbitalMark` y el ícono (`scripts/orbital_symbol.py`, que llama a `scripts/orbital_mark_path.swift`). Si
cambia la marca (`DS.Brand`), se corre el script. `testBrandSymbolMatchesTheMark` compara su firma con `Tokens.swift`.

### iPad y Mac: su propio tamaño (MAC-A, 16 nov 2026)

La Mac corre la app del iPad («Diseñada para iPad») y macOS la dibuja al 77 % en ventana. Por eso la Mac tiene un mini
sistema propio, en `DS.Mac` y `DS.HomeHero` (Fernando, 16 nov 2026: «crea otro mini sistema de diseño para iPad y Mac con
nuevos tamaños»):

- **Letra:** la Mac ignora Dynamic Type. Toda receta pasa por `DS.styled(_:)`, que en la Mac da el tamaño de iOS por
  `DS.Mac.typeScale` (1.25). Nada de `.system(.estilo)` suelto en los tokens.
- **La escala de la Mac: una vez y para todo** (Fernando, 16 nov 2026: «haz esa misma revisión en cuanto a tamaños de fuente
  y todos los botones… que queden registradas una vez y se apliquen siempre»). El tamaño de la Mac se decide en un solo
  lugar, `DS.Mac`, y se pone una sola vez, con `macDefaults()` en `RootView`:
  - **La letra chica se aprieta, no baja:** en `DS.Mac.styleSizes` lo más chico es 13 pt (×1.25): en el iPhone una nota de
    11 pt se lee a palmo; en la Mac, al 77 % y a medio metro, salía de 10 px.
  - **La letra del sistema crece igual** (formularios, menús, botones nativos, lo que no pasa por `DS.styled`):
    `DS.Mac.systemType` (`.xxLarge`). Ninguna pantalla le pone un tope menor.
  - **Los controles suben un tamaño:** toda la app pide su tamaño con `.dsControlSize(…)`, nunca `.controlSize(…)` directo;
    en la Mac pasa por `DS.Mac.control` (chico → normal → grande → extragrande). Los que no piden ninguno toman
    `DS.Mac.controlDefault`.
  - Lo vigila `DesignRulesTests+MacScale`. Un tamaño nuevo de la Mac se agrega en `DS.Mac`, no en la pantalla.
- **Una sola barra:** en la Mac no hay barra de pestañas del sistema ni barra lateral (la lateral salía vacía, tapaba el
  contenido y ahí tronaba). Inicio · Explorar · Biblioteca · Buscar van en el renglón del logo (`MacTabStrip`). En Inicio
  van en su encabezado; en las otras, por `.macTopBar()`, sin título del sistema (con título, las pestañas se iban a «More»).
  En la Mac las pestañas siempre llevan nombre: la barra le ofrece poco ancho a lo de la izquierda y los nombres se recortaban hasta desaparecer, así que la tira lleva `.fixedSize()`.
- **Un solo logo reporta su lugar:** el de la barra de la Mac va con `AppMark(reportsFrame: false)`. Dos logos escribiendo
  el mismo dato se peleaban y la app se trababa redibujando.
- **Imágenes al ancho de la ventana (solo Mac):** `DS.Image.bleed` y `DS.Image.wide` se piden al ancho de la columna, y
  `ImagePipeline` pide al menos 2× en la Mac. Si no, la portada se ve pixeleada.
- **Inicio como el escritorio de la tele** (RI2, 16 nov): en la Mac la portada va a todo lo ancho, como el Inicio de la tele, y «Seguir viendo» se monta sobre su borde. Si no hay nada a medias, en su lugar va «Lo que sigue» (`upNextRail`, tarjetas anchas; tocar una la pasa al frente). Ya no hay portada partida ni renglones a la derecha.
- **Pósters:** en la Mac, las filas usan `DS.Mac.railWidth` (188 pt).
- **Controles de tamaño fijo con ícono** (el selector Todo · Películas · Series, `DS.KindPill`): en la Mac crecen como la
  letra (`DS.Mac.sized`); si no, el ícono, que sí crece, llenaba su círculo.
- **Las filas llenan la ventana** (segunda pasada, 16 nov: «en plataformas no se extiende completamente a la derecha»):
  - Plataformas, Premios y Estudios crecen con `DS.PlatformFan.scale` hasta que seis llenan el renglón (tope 2×); en ventana más ancha caben más. Si la tele no trae un ranking (Prime Video llegaba vacío), la app lo pide ella misma a JustWatch.
  - Canales reparte el renglón (`DS.HomeChannels.width(count:)`).
  - La puerta de «Decide por mí» asoma una tira de pósters (`DecideStrip`; `DS.ParaTiB.doorFan`, la misma en Inicio y Explorar).
  - Buscar vacío muestra un muro de «Lo más popular hoy» que llena lo ancho y lo alto (los renglones que caben bajo la búsqueda avanzada, al menos `DS.Mac.searchRowsMin`).
  - Inicio también lleva la sombra bajo la barra (`macTopShade`): al bajar, las pestañas se perdían sobre la portada.
- **La Mac con su propio acomodo** (Fernando, 16 nov 2026: «vamos con tus recomendaciones», MB1 · MA1 · MS1 · MT1 · MC1):
  - Biblioteca (BI-A, 22 nov 2026; reemplaza la columna de la izquierda de MB1, que se comía un cuarto de la ventana): filas como Inicio (`LibraryHome`): arriba Descargas y Mi media en dos tarjetas (Fernando, 22 nov 2026: «subo lo de descargas y mi media hasta arriba»); luego Viendo, Mi lista, Vistas y Tus listas, cada una con cuántos hay y su pantalla completa en el encabezado. También en el iPad ancho (`DownloadsView.rows`); en el iPhone y el iPad angosto siguen sus pestañas arriba.
  - Inicio en ventana ancha (22 nov 2026): el panel del tablero: «Seguir viendo» en renglones de 176 (los que quepan), debajo «Lo nuevo de lo tuyo» y «Decide por mí» al pie, sin hueco muerto.
  - En la Mac nada se mueve solo (22 nov 2026, «está inusable»): el cielo, el muro de Explorar y los canales quedan quietos (`ThisDevice.ambientMotion`); con ellos el compositor de la Mac se iba a 60–95 % en reposo. Se mueve lo que tocas. `DesignRulesTests+Ambient` lo cuida. Y nada que espere sin soltar el hilo (Vision) corre en los hilos de Swift: los ocupaba todos y la ficha y las imágenes se quedaban esperando (`DesignRulesTests+Threads`). La portada se vuelve a acomodar al cambiar el tamaño de la ventana.
  - La ficha en la Mac (FI-B, Fernando, 22 nov 2026): al tocar un póster entra por la derecha, cerca de 40 % de la ventana (`DS.TitleAction.sidePanelWidth`), sobre la pantalla oscurecida, que no se reacomoda. Clic afuera, ✕ o Esc la cierran; otro póster la cambia. Adentro, la ficha de una columna. Con ventana angosta y en el iPad, la ficha completa (FE1).
  - Revisión pantalla por pantalla en la Mac (22 nov 2026). Cinco reglas, cada una con su prueba:
    - El título de cada pantalla crece con la Mac, como el resto de la letra: lo dibuja la barra del sistema y salía del tamaño del iPhone («en Mi media el título se me hace muy pequeño»). `testMacScreenTitlesUseTheMacScale`.
    - Con un título arriba, lo que pasa por debajo se tapa: en una pantalla de pósters (una lista, una colección), el título y «Editar» no quedan encima de los pósters. `testPosterScreensWithATitleCoverWhatScrollsUnder`.
    - Los botones de vidrio se leen: su letra va del color del texto (en la Mac salía oscura sobre fondo oscuro), y un aviso de «vacío» dentro de una lista no se estira a toda la pantalla (se cortaba y escondía su botón). `testGlassButtonsGoThroughTheCatalog`, `testEmptyStatesInAListDoNotFillTheScreen`.
    - Una fila de tarjetas no repite los pósters de la de al lado (Acción, Aventura y Animación enseñaban los mismos). `CoverSpreadTests`.
    - Cambiar de pestaña no traba: lo que tiene imágenes o renglones cuenta cuántos caben con el espacio medido, no arma varias versiones para ver cuál cabe (el panel de Inicio armaba doce y la Mac se trababa al ir de Inicio a Explorar). `testOnlyTextTriesManyVersionsToFit`.
    - Cambiar de pantalla no relee nada ni repinta lo que no cambió: el idioma de Orbital es el preferido de la app (con otro `Locale`, cada texto releía `Localizable.strings` del disco: 16 % del cambio de pestaña) y lo que va por el entorno para toda la app lleva solo datos, no acciones (`PosterQuick`, `TallArtLookup`). Desplazarse tampoco: lo que se anota al pasar (qué sección ves) va a una caja que lee solo quien lo enseña (`SectionTracker`), nunca al estado de la pantalla. Y nada que se pinta le pregunta al disco (el espacio libre lo sabe `DiskSpace`, medido por detrás: abrir una serie tardaba 125 ms por esa pregunta). Lo que llega de a poco (estantes, estudios, temporadas) no compara todo lo que ya llegó: cada llave se guarda con `put`, y lo que señala un aviso de la guía viaja solo, no en un diccionario de toda la pantalla (las dos cosas costaban 0.5 s de la primera visita a Explorar). Cambiar de pestaña tampoco cambia el entorno de toda la app: la pestaña en que estás va en una caja (`MacTabs`) que leen solo la tira y «Buscar» (como valor, cada clic revisaba las cuatro pestañas: Explorar pasó de 1.2 s a menos de 0.1 s). Y volver a una pestaña no relee lo que leyó hace menos de un minuto (`loadIfStale`, `seriesStale`). En Ajustes, un ajuste de pocas opciones va en un renglón con su nombre a la izquierda y el selector a la derecha (`SettingsChoiceRow`), nunca solo en su tarjeta; `testSettingsChoicesSitInARowWithTheirName`. Un título sin póster lleva su nombre sobre un resplandor de color (`PosterStandIn`), no un cuadro gris. `testSwitchingScreensRereadsNothingAndRepaintsOnlyWhatChanged`.
    - Una fila que muestra «Ver todas» cuenta antes cuántas caben: si caben todas, no sale; si no, el último lugar es «Ver todas» y las demás se esconden al achicar la ventana, sin deslizarse ni cortar una a la mitad (la repisa de Colecciones). Y el «+» de crear algo es uno solo en toda la app (`DSAddTile`: círculo con el + turquesa y su nombre debajo, sin caja). `testMacRowsFillTheWindow`.
    - Una imagen que falla se vuelve a pedir sola mientras siga en pantalla (antes se quedaba vacía hasta salir y volver a entrar). `testRemoteImageLoadsEvenWhenItsContentIsEmpty`.
  - Explorar en ventana ancha (22 nov 2026): «Tus listas» en mosaicos que se deslizan con «Nueva lista» como el primero; «Lo que ves» como puerta grande (`ListRow(large:)`); el mosaico con columnas de 210 y su entrada animada; el muro de la portada cubre también la cuña de la izquierda (`coverTiltSlack`).
  - Ajustes: lista y detalle, como Ajustes del Sistema. Cada renglón es un `SettingsLink`: en la Mac abre su página a la derecha (`SettingsView.destination`); en iPhone y iPad la empuja.
  - Buscar: el campo grande al centro (`MacSearchField`, 88 pt de alto y letra de título) en vez del de la barra, y los seis mosaicos de la búsqueda avanzada en una fila, de 150 pt de alto con su dibujo grande (`DS.Mac.doorTileHeight`): con el tamaño del iPhone eran franjas que se leían como botones de formulario.
  - Al cambiar de pestaña, el cambio es al momento (sin el fundido del sistema, `DS.Mac.tabSwitchQuiet`).
- **El replanteamiento de la Mac** (Fernando, 16 nov 2026: «hazlo de acuerdo a tus sugerencias», RF2 · RI2 · RN2 · RP2 · RB2):
  - Ficha (RF2): en la Mac no lleva pestañas; todo en una sola página que se baja: episodios, tráiler y reparto, tus créditos, tu calificación y tus vistas, reseñas en tres columnas de igual alto (`DS.Mac.reviewColumns`, con `Grid`), saga y parecidas, y detalles. En iPad siguen las pestañas.
  - Inicio (RI2): la portada a lo ancho con «Seguir viendo» (o «Lo que sigue») montado en su borde.
  - Pestañas (RN2): una cápsula al centro de la barra (`MacTabStrip`), en el orden del menú «Ir» (⌘1 Inicio, ⌘2 Explorar, ⌘3 Biblioteca), con la elegida llena del color del texto (crema en oscuro, oscura en claro). «Buscar» es una cápsula junto al logo (`MacSearchChip`) que abre Buscar con el cursor listo. En una ventana de menos de `DS.Mac.centeredTabsFrom` las dos van junto al logo, solo con íconos: al centro se encimaban.
  - Pósters (RP2): al pasar el puntero, la tarjeta crece y su póster lleva el marco crema del foco de la tele; si el póster mide al menos `DS.Mac.quickMinWidth`, en su esquina salen ▶ y ＋. El marco y los botones se ponen sobre el póster (`macPosterBounds`), no sobre toda la tarjeta. ▶ y ＋ también son acciones de VoiceOver. La acción la pone la raíz (`posterQuick`, comparable: no repinta los pósters); ＋ sobre algo que ya está en Mi lista solo lo avisa, sin «Deshacer».
  - Pantallas vacías (RB2): `DSEmptyState` ocupa casi todo el alto de lo que lo contiene (`DS.Mac.emptyShare`, con `containerRelativeFrame`), no de la ventana: en una hoja chica no se sale.
- **La variante de iPad dice «dispositivo»:** la Mac toma la variante de iPad del catálogo de textos, así que ahí nunca se escribe «iPad» sino «dispositivo» («device»); «Como el iPad» es «Como el sistema». Al compilar, Xcode reescribe `Localizable.xcstrings`: se restaura y solo se cambia el texto a propósito.
- **Una sola pestaña no se dibuja** (`DSTextTabs` con menos de dos opciones): en la ficha de una película sin reparto ni parecidas, «Detalles» sola parecía rota. Vale en iPhone, iPad y Mac.
- **Lo que se lee va a ancho de lectura** (`DS.TitleAction.wideReading`): en la ficha ancha, créditos, tu calificación y las reseñas ya no van de orilla a orilla.
- **Una plataforma nunca queda vacía:** si su tarjeta llega sin pósters, pide su ranking (Prime Video salía en blanco).
- **Un ranking filtrado se numera dentro de lo que ves:** el Top 10 de Inicio dice 1, 2, 3… en Series o Películas. Con el
  puesto del ranking mezclado brincaba del 4 al 6. Los rankings de una sola lista sí llevan su puesto.
- **La barra de la Mac lleva sombra** (`DS.Mac.topScrim`, con `ArtVeil`): sobre el mosaico de Explorar las pestañas se perdían.
- **La ficha y los tutoriales crecen con la letra:** la columna y el logo de la ficha ancha, el ancho de lectura de la guía, la
  burbuja de los avisos y la escena de las historias van por `DS.Mac.sized`.
- **El vidrio lleva base en la Mac:** el selector Todo · Películas · Series, «Filtros» y la cápsula de arriba de Inicio van
  sobre `macPillBase` (el color de las tarjetas y su filo). Sobre el fondo oscuro de la Mac el vidrio solo no se veía y el
  selector parecía íconos sueltos. En la Mac los íconos del tipo van de línea (`KindGlyph.variant`): el rollo de película
  relleno se veía como un bloque. El vidrio del reproductor no lleva base: va sobre el video. El renglón de arriba (las
  pestañas, «Buscar», tu foto y el campo de Buscar) va de vidrio con un tinte leve en vez de base (`macTopGlass`, 24 nov
  2026: «un look más liquid glass a los 3 elementos de arriba y a buscar»): ahí el tinte basta para que se lea.
- **El reproductor en la Mac** (revisión del 16 nov 2026, «revisa muy bien el reproductor»):
  - **Toda pantalla completa y toda hoja recibe la app a mano:** cada `fullScreenCover` lleva `.environment(env)` en lo que
    muestra y toda hoja se abre con `.appSheet(` (nunca `.sheet(` suelto), que se la pone. En la Mac la cubierta o la hoja lee
    sus preferencias (el zoom de entrada, `interactiveDismissDisabled`) antes de heredar `AppEnvironment` y la app tronaba al
    abrir el reproductor desde cualquier lado y, en la 2491 (23 nov), al abrir una hoja con una película puesta.
    `DesignRulesTests+Covers` y `DesignRulesTests+Sheets` lo vigilan.
  - **Sus controles crecen en la Mac y en el iPad** (Fernando: «más grandes los iconos para tanto pantalla de Mac como
    para pantalla de iPad»): play, ±10, los círculos de arriba (`DS.PlayerPanel.circle`), la barra de avance y el ancho del
    panel van por `DS.PlayerPanel.big`: en la Mac como su letra (×1.25), en el iPad ×1.2 (`padScale`), en el iPhone igual.
    Con el tamaño del iPhone se veían chicos en pantallas grandes.
  - **El puntero muestra los controles:** moverlo sobre el video los saca (antes había que hacer clic). El puntero no se
    esconde: `pointerVisibility` no existe en una app de iPad.

### Pasada de la Mac del 17 nov 2026

Fernando: «Está lentísimo… cuando intento cambiar de Inicio a Explorar», «Decide por mí, hazlo más vistoso», «quítale la
cajita gris» a «Añadir canal», «el top 10 de Netflix sigue sin seguir el top 10», «pulir el elemento Navidad» y «da una muy
buena pulida a los landing pages». Las reglas que quedan:

- **El muro de Explorar tiene tope de columnas** (`DS.ParaTiB.coverMaxColumns`, 9): en ventana ancha las columnas se
  ensanchan y llevan menos renglones en vez de sumar columnas. En la Mac eran 13 columnas de 26 pósters (~340 a la vez,
  cada uno con sus tareas) y el cambio de pestaña se trababa.
- **Lo mismo no vuelve a pintar la página:** toda propiedad de un modelo que avisa (`changed()`) compara con `oldValue`.
  En `CollectionsModel` cada estudio, temporada o género que llegaba igual redibujaba Explorar entero.
- **Un ranking que ves no hace fila:** buscar el IMDb de un título del Top 10 pide sus detalles con `urgent: true`; detrás
  de los ~260 detalles de fondo de Explorar, las series de Netflix tardaban más de un minuto en salir.
- **Tu país sale de donde estás:** sin elegirlo en Ajustes, el país (Top 10 de Netflix, JustWatch, «dónde verla») sale de
  la zona horaria y luego del idioma y región del aparato (`AppSettings.phoneRegion`, `zoneRegion`). Una Mac en inglés de
  EE. UU. en Monterrey pedía el Top 10 de Estados Unidos. Sin elegir, el guardado sigue al aparato en cada arranque.
- **Una página que terminó sin nada lo dice:** el ranking de una plataforma sin resultados enseña «Hoy no hay ranking de
  este servicio.» en vez de quedarse en blanco.
- **«Decide por mí»** (Inicio y Explorar, la misma puerta): nombre en tamaño de título con el dado en turquesa, abanico más
  grande (`deckPoster` 104) y un brillo del color de acento desde el abanico (`doorGlow`; el turquesa es voz: solo el dado).
- **«Añadir canal» sin caja:** un círculo neutro con el + en turquesa y su nombre debajo (`DS.HomeChannels.addCircle`); el turquesa no pinta el fondo ni la orilla.
- **«La temporada»** (la de ahora en Explorar): su ícono, el nombre en tamaño `display`, más color y un anillo de su color,
  más alta y, en la Mac, una tira de sus títulos que se desvanece hacia el texto.
- **La bienvenida y la guía:** en ventana ancha la marca crece hasta ×1.5 (`DS.Welcome.wideScale`, con la clase de tamaño ancha), la frase va un escalón
  arriba del cuerpo (`DS.Welcome.lead`), el texto de la bienvenida va al centro y los botones van al centro de la ventana
  con ancho tope (`DS.Welcome.buttonWidth`); antes quedaban pegados a la izquierda en la Mac.

`DesignRulesTests+Wide.testWidePassOfNov17` lo vigila; `SettingsTests.testRegionFollowsTimeZone` el país.

### Las pestañas de la Mac no dependen de la barra del sistema (17 nov 2026)

En la Mac, Explorar, Biblioteca y Buscar dibujan su propio renglón de arriba (`.macOwnTopRow { … }`, `MacTabStrip.swift`), con
las mismas medidas que el de Inicio (`HomeHeader`): logo y «Buscar» a la izquierda, la cápsula de pestañas al centro y los
botones de la pantalla con tu perfil a la derecha. Antes iban en la barra del sistema (`.toolbar`, `.principal`) y UIKit los
soltaba: al entrar a Buscar, al regresar de una ficha o al volver a Explorar la pantalla se quedaba sin pestañas o sin logo.
Dos caminos probados que no sirven: la cápsula encima del contenido (la barra del sistema se queda con los clics) y corrida
dentro de la pieza del logo midiéndose (la app se traba redibujando). `DesignRulesTests.testMacTabsLiveInTheLogoRow` revisa que
ni la cápsula ni «Buscar» vuelvan a un `.toolbar { … }`.

### Ajustes y conectar cuentas en la Mac (MA2, 17 nov 2026)

- **Lo que se abre desde Ajustes se queda a la derecha.** En la Mac, un enlace dentro de una página de Ajustes es `PaneLink`
  (`SettingsParts.swift`): abre la página junto a la lista, con su nombre arriba y «‹» para volver (`SettingsPaneHeader`). Con
  `NavigationLink` se empujaba a toda la ventana y quedaba una columna angosta sola. En iPhone y iPad, `PaneLink` es un
  `NavigationLink` de siempre. No va dentro de una hoja (la hoja hereda el entorno y abriría la página detrás).
- **Una sola pantalla de código.** Trakt, Real-Debrid y OneDrive se conectan con `DeviceCodeCard` (`Guide.swift`): dónde
  escribirlo, el código grande, «Copiar y abrir …» y «Esperando a que lo apruebes…», en Ajustes y en la guía.
- **Nada de sensores de movimiento en la Mac.** Soltar un `CMMotionManager` en la Mac (el cielo de Ajustes al salir) trababa la
  app para siempre; `SkyTilt` ni lo crea ahí.
- **Inicio de escritorio.** En la Mac el margen de las pantallas es de 40 pt (`DS.Space.gutter`), la portada toma a lo más
  ~la mitad de la ventana (`DS.Mac.heroHeightShare`) y su logo y «Ver» crecen (`DS.Mac.heroScale`, `macHeroButtons`); el logo
  de Orbital, las pestañas, «Buscar» y tu foto crecen con la letra.

`DesignRulesTests.testSettingsPagesOpenBesideTheList` y `testNoMotionSensorOnTheMac` lo cuidan.

### Del Mac al iPad ancho (17 nov 2026)

Fernando: «tráete de Mac a iPad lo que haga sentido y dale una muy buena pulida». La regla: **lo que crece con la ventana
sigue a la ventana, no a la Mac.** `WindowMetrics.roomy` es la Mac o una columna desde 900 pt (iPad de 13" de pie, cualquier
iPad acostado). Con espacio, en el iPad también: los canales llenan el renglón, la tira de «Decide por mí» y la de «La
temporada», los logos de plataforma más grandes, el muro de lo popular en Buscar vacío y «A continuación» en Inicio cuando no
hay «Seguir viendo». Se quedan solo en la Mac: el arte a sangre pedido al ancho de la ventana (en el iPad, 800 por memoria),
las pestañas en el renglón del logo, el campo de búsqueda propio, el puntero y los íconos de línea. La ficha del iPad sigue
con pestañas (FE2-B).

**Una tira de carteles junto a un texto nunca le quita el ancho al texto:** el texto lleva `layoutPriority(1)` y la tira
(`DecideStrip`) enseña solo los carteles que caben (`ViewThatFits`). En el iPad la tira de ocho dejaba «Decide por mí» a
una letra por renglón. `DesignRulesTests+Wide.testWideRoomFollowsTheWindowNotTheMac` lo vigila.

`DesignRulesTests+Wide` lo cuida (`testMacHasItsOwnSizes`, `testMacTabsLiveInTheLogoRow`, `testMacRowsFillTheWindow`, `testMacGlassControlsHaveABase`) y `DesignRulesTests+MacLayout` el replanteamiento (`testMacLooksLikeTheDesktop`).

### Rendimiento de la Mac y el ultrawide (17 nov 2026)

Fernando: «muchos problemas de performance en la Mac… un monitor ultrawide y no funciona». Reglas:

- **Nada de fondo deja corriendo el reloj de pantalla.** Una animación larga (`withAnimation` de 16 s, `repeatForever`) o un
  `TimelineView` con calendario propio mantienen el reloj de SwiftUI a 165 Hz aunque ya terminaron: Inicio quieto gastaba
  ~48 % de CPU. Lo largo va a pasos con una tarea que se detiene sola (`Breathing`: 20 por segundo, 16 s y fin). El cielo de
  la Mac va a 2 cuadros por segundo (`DS.Sky.calmFrame`).
- **Ultrawide:** la portada de Inicio no se topa a lo ancho en la Mac (56 % del alto); cuando la caja es mucho más ancha que
  la imagen, el arte va a la derecha y se funde a la izquierda sobre su copia desenfocada (`PosterView`, `.whole`). Las
  tarjetas a lo ancho («Decide por mí», «Porque viste…») llenan la fila como las demás (con tope, unas seguían y otras
  no); «Porque viste…» pone su encabezado al lado desde 1300 pt.
- **Abrir pantallas rápido:** los estantes de Explorar son perezosos (`ShelfStack`), el muro y la tira de Explorar usan
  pósters de adorno (`PosterView(decorative:)`) y se arman columna por columna, y el destino de Ajustes va borrado de tipo
  (`AnyView`): en el iPad Explorar abría en ~0.8 s en vez de ~1.1 s y Ajustes en ~1.1 s en vez de ~1.4 s.
- **La ventana más chica de la Mac es 560 pt**; abajo de 760 la barra lleva solo el planeta, sin «orbital».

**Cómo medir (solo Debug, sin manos):** escribe en
`~/Library/Containers/<contenedor>/Data/tmp/mac-check-request` una orden por renglón (`wait 10`, `perf <nombre>`, `tour`,
`size full|W H`, `cpu <nombre>`, `off sky|breath|drift`) y corre la app desde Xcode. A los 10 s `MacSelfCheck` (en
`Perf.swift`) la lee y deja `mac-perf-<nombre>.txt` con las cinco medidas en grande (1440×900) y ultrawide (la pantalla
entera): CPU en reposo (10 s), cuadros perdidos y peor cuadro al desplazar Inicio, peor cuadro al abrir una ficha, peor
cuadro al cambiar el tamaño y memoria. `tour` deja capturas de cada pantalla en cinco tamaños en `mac-tour/`. No midas
mientras corre `sample`: detiene la app y ensucia el desplazamiento.

`load <nombre>` mide cuánto se traba la pantalla al abrir cada una (Explorar, Buscar, Biblioteca, fichas, Ajustes) con
`MainPing` (sirve aunque la ventana esté tapada) y `fichas` deja la ficha en seis tamaños, de alta a ultrawide, en
`mac-fichas/`; en el simulador del iPad se piden igual (el contenedor de la app en el simulador).

`DesignRulesTests+MacLayout.testMacPerformanceAndWideWindows` lo vigila.

### Cambiar de pestaña en la Mac (23 nov 2026)

Fernando: «le pico explorar y se tarda como 2 segundos en cambiar. Debería ser instantáneo… primero quiero evidencia».

- **Regla: cambiar de pestaña muestra lo que ya estaba armado.** En la Mac las pestañas son una baraja (`MacTabDeck`): cada
  pantalla se arma la primera vez y después solo se esconde. Lo escondido no cambia ningún valor del entorno (SwiftUI volvería
  a resolver cada texto y color: la primera versión lo hacía y seguía costando ~0.4 s); se pregunta con `@TabHidden` o
  `.onTabHidden`, y sus atajos de teclado van con `shownKeyboardShortcut`. Lo que antes se apagaba en `onDisappear` (cielo,
  vaivén, «a la vista» de Descargas, cursor de Buscar) se apaga también al esconderse. «Esta semana» no se relee si se armó
  hace menos de diez minutos (`RepisaModel.weeklyMaxAge`). `DesignRulesTests.testMacTabsStayBuilt` y
  `RepisaWeeklyTests.testVolverAExplorarAlRatoNoVuelveACargar` lo vigilan. Con una ficha abierta, el renglón de las
  pestañas sigue tomando clics y cambiar de pestaña la cierra (antes el velo de la ficha se comía el primer clic: «le pico
  a Inicio y no cambia»).
- **Cambiar de pestaña no toca la raíz (24 nov 2026).** En la Mac la pestaña vive en `macTabs` y solo la baraja la lee
  (`RootView.setTab`); antes cada clic pasaba por el estado de la raíz, que se recalculaba y con ella las letras y colores
  de las cuatro pantallas: ~0.5 s congelada en cada cambio, aunque la pestaña ya estuviera armada. Además Biblioteca y
  Explorar se arman solas, escondidas y una a la vez, unos segundos después de abrir la app (`DS.Mac.tabPrepareDelay`): el
  primer clic ya no paga armarlas (también Buscar, sin quitarle el cursor a nadie). Lo que se arma escondido no actúa sobre
  otra pestaña ni le habla a quien la usa: lee `@TabHidden` en sus acciones, y los consejos de Aprende esperan a que su
  pestaña esté a la vista (antes uno podía salir en Biblioteca mientras se veía Inicio). Lo que vuela hacia una pestaña (el
  póster de una descarga) llega a donde está el botón de verdad (`AppUI.libraryTabCenter`, arriba en la Mac), no a un lugar
  calculado.
  Medido (2516 → 2518): cambiar entre pestañas ya vistas, 450–550 ms congelada → nada (150–350 ms de trabajo); primera vez
  a Explorar, 2.4 s con 0.8 s congelada → 1.2 s sin congelarse; Biblioteca, 1 s → 0.6 s.
- **Cómo se mide (y cómo no).** La velocidad se mide en la app instalada (Release, la cuenta de Fernando, su ventana) con
  `ios/scripts/medir-clics-mac.sh`, antes y después, la misma secuencia con la app recién abierta. No vale medir solo en Debug ni
  con la demostración (allí se «mejoraba» y en la Mac de Fernando se sentía igual). Tres números por clic: trabajo del hilo
  de la pantalla, cuándo quedó quieta y el congelamiento más largo (Apple: >250 ms se siente, >500 ms es «Hang»).
- **Resultado (2495 → 2497, dos rondas cada una):** primera vez a Explorar, congelada 1.1–1.6 s → 0.6 s; cada cambio
  después, congelada 0.5–0.8 s → nada (10 de 10 sin congelarse) y quieta en 0.65–1.8 s → 0.35–0.7 s. Abrir una ficha no
  cambió (1.2–1.7 s de trabajo): sigue pendiente (el acomodo de los botones de la ficha, `SpreadRow`, y dibujarla entera).
- **Lo que no sirvió (segunda vuelta, 23 nov 2026, medido igual, 2498 → 2500).** Sacar la pestaña, las pilas y la ficha
  del estado de la raíz a cajas, medir la ficha redondeado y sin animación, acotar la animación del panel y no dejar armadas
  las pestañas escondidas: ninguna bajó el trabajo por clic (abrir la ficha siguió en 0.9–1.1 s y ~45 acomodos de la raíz).
  No se quedaron. Sí sirvió: el arte que respira a 4 pasos por segundo en vez de 20 (Inicio quieto: 15 % → 9 % del hilo
  principal). Ojo al medir: los clics por accesibilidad (computer use) suman 10–20 % de trabajo que el mouse no.

### La ficha de la Mac va en su propia capa (24 nov 2026)

Fernando: «picarle a una película es lento… tuve que hacer un force quit». Medido con Instruments en la app instalada: con
la ficha vacía (solo el título) abrirla o cerrarla congelaba la pantalla igual (~200 ms; 1 s la primera vez). El costo no
era la ficha: ponerla como `overlay` de la raíz hacía que SwiftUI volviera a acomodar y pintar todo lo de atrás (las
cuatro pestañas armadas). La versión del 21 nov (antes de la ficha a la derecha y de la baraja) era más lenta en todo:
abrir 3.4 s de trabajo con 1 s congelada, Explorar 2 s con 1 s congelada.

- **Regla: lo que flota encima de toda la pantalla de la Mac no se mete en la pantalla de SwiftUI.** La ficha vive en su
  propia capa de UIKit (`MacTitleHost`), una por ventana: la pantalla de atrás no se entera de que se abrió. Hereda lo que
  la raíz le pone a todo uno por uno (`SideTitle`); el entorno entero (`\.self`) no, porque escondía la ficha a VoiceOver.
  Lo de atrás se esconde a VoiceOver solo si VoiceOver está prendido (esconderlo rearma la accesibilidad de todas las
  pestañas: ~250 ms con un cliente de accesibilidad). `DesignRulesTests.testMacTabsStayBuilt` lo vigila.
- **Resultado (2504 → 2514, la misma secuencia, Mac con poca carga):** cerrar, 200 ms congelada → nada; abrir otra
  película, 450–550 ms congelada → 250–400 ms. Lo que queda es armar la ficha nueva (textos, dibujarla): siguiente paso.
- **Ojo al medir:** otras sesiones compilando suben la carga de la Mac a 20–80 y los números se inflan al doble; medir
  con carga < 6. Los clics de computer use pasan por accesibilidad y suman su propio trabajo.
- **Primero lo que se ve (24 nov 2026).** Los episodios, el reparto y los detalles de la ficha se arman un instante
  después de que llegó (`TitleView.belowFold`), no en el mismo cuadro del clic: abrir otra película, 808 → 760 ms de
  trabajo y el congelamiento más largo de ~400 a ~300 ms.
- **El arte del panel no se recorta hacia una orilla (24 nov 2026).** Fernando: «se ve como descentrado el póster de
  fondo». El marco del panel es casi cuadrado: un fondo 16:9 se recortaba a menos de la mitad y se corría hacia el sujeto
  (si estaba en la orilla, quedaba pegado al borde y cortado), y un póster alto se corría hacia un cuchillo y cortaba la
  cabeza. En el panel (`keepsWide`), el fondo ancho va completo arriba y se funde en su copia difuminada
  (`ArtFit.wholeTop`) y el póster alto se ancla arriba y al centro (`ArtFit.fillTop`). En el panel esto se decide antes
  que nada: con el marco casi cuadrado un póster 2:3 pasaba el límite de «completo» y se iba pegado a la derecha, como el
  destacado de Inicio (Fernando, otra vez el mismo día: «no está bien centrado»). `ArtFitTests.testWideArtStaysWholeInTallPanel`.

### Lo que no se ve no se arma (24 nov 2026)

Pedido: bajar al menos 30 % abrir la app, cambiar de pestaña y abrir una ficha en la Mac. Medido con Instruments en la app
instalada, sin clics (`ios/scripts/medir-mac-sin-manos.sh`: la app sigue unas órdenes en una compilación de medición y
marca cada una), tres rondas antes (2531) y cuatro después (2533).

- **Regla: lo que no está a la vista no se arma ni avisa.** Un panel cerrado no arma lo de adentro (el `.inspector` de la
  raíz armaba el panel lateral al abrir la app y lo repintaba con cada sondeo de la TV); lo de abajo de la ficha va
  perezoso (`LazyVStack`); un valor que se calcula de un modelo en cada pasada se guarda hasta que el modelo cambie
  (`ObservableModel.revision`, el abanico de «Decide por mí»), y una propiedad publicada que se compara no avisa con el
  mismo valor (`@Tracked` sin `always`). `DesignRulesTests.testWhatIsNotSeenIsNotBuilt` y
  `testTrackedValuesCompareBeforeNotifying` lo vigilan.
- **Resultado (2531 → 2533):** abrir la app, congelada 720–800 ms → 380–640 ms (mediana 750 → 470, −37 %), trabajo de la
  pantalla en los primeros 5 s 1.8–2.1 s → 1.51–1.70 s (−18 %), lista en 3.45–3.6 s → 3.05–3.45 s (−10 %). Cambiar de pestaña: 50–190 ms
  de trabajo, igual que antes, pero quieta en 100 ms en vez de 150 ms y sin congelarse nunca. Abrir una ficha: 475–690 ms
  → 430–650 ms (la serie bajó en dos de tres rondas; las películas, igual).
- **Por qué la ficha no bajó 30 %.** Lo que cuesta ya no es código de la app (~10 % de las muestras) sino que SwiftUI acomode
  y dibuje una ficha nueva: ~250 ms el primer acomodo (textos, la barra con sus botones, los íconos, el renglón de acciones)
  y otros ~250 ms repartidos en cuatro o cinco reacomodos conforme llega cada dato (Cinemeta, lo de abajo, TMDB, Letterboxd,
  las fuentes). Cambiar de pestaña ya no se congela: lo que queda es dibujar la pantalla que aparece. Para bajar más hay
  que juntar esas llegadas en un solo acomodo o armar menos ficha de entrada: es un cambio de cómo carga la ficha, no un
  ajuste.

### La receta de la ficha ancha (17 nov 2026)

Fernando: «replantea con una receta el cómo se debe de armar… que la imagen que está atrás de manera inteligente se
centre». La ficha del iPad y la Mac se arma así (`WideStage`, en OrbitalModels, con sus pruebas):

1. **Escenario.** Arte y columna viven en un escenario centrado de 2.4:1 como mucho (`DS.TitleAction.stageAspect`). En una
   ventana más ancha (el ultrawide) queda al centro y a los lados sigue el mismo arte, difuminado y oscuro
   (`StageSides`); las orillas del escenario se funden en él (`StageEdges`). Nada se clava a la izquierda ni flota en un
   hueco negro.
2. **Margen.** La columna («Ver», acciones, sinopsis) y las filas de abajo empiezan en la orilla del escenario más el 5 %
   de su ancho (mínimo 40 pt, el de la TV). Las filas salen por la orilla de la ventana.
3. **Vertical.** Si la ventana es más alta que ancha (iPad parado), la columna va al centro con el texto centrado, sin el
   velo de la izquierda, y el arte se centra en el sujeto (`FocalPoint`).

4. **Banda a dos columnas (M2, 18 nov 2026).** En una ventana acostada de 1100 pt o más (la Mac, el iPad acostado sin la
   barra lateral), bajo el arte va una banda: a la izquierda lo que se hace (logo, datos, «Ver» o «Continuar», acciones), a
   la derecha la sinopsis a un ancho de lectura (hasta cuatro renglones). El arte baja al 72 % para que la primera fila
   (tráilers o episodios) se asome sin desplazar. Con letra de accesibilidad o una ventana más angosta, la columna de
   siempre. «Dirección · Con» se queda abajo (no se repite).
5. **Acciones de la Mac (A1).** Guardar · Descargar · Vista · Tráiler son círculos con su nombre chico debajo, siempre
   visible (el nombre dice el estado: «Guardada», «45 %»); en iPhone e iPad, mosaicos para el dedo
   (`\.roundActionTiles`, `ActionTileLabel.roundBody`).
6. **Vertical (I1).** Con el iPad parado, la columna (logo, «Ver», acciones, sinopsis) va al centro. Reabre los botones al
   centro (FE2-A, descartado el 4 nov) solo para esa posición; acostado sigue a la izquierda.
7. **Lo de abajo usa todo el ancho (23 nov 2026).** Con el iPad parado, las pestañas, los episodios, el reparto y las
   filas arrancan en el margen de la pantalla, no en la orilla de la columna centrada: así dejaban un hueco a la
   izquierda (Fernando: «estás desperdiciando ahí espacio»). `WideStageTests.testPortraitRowsUseTheWholeWidth`.

No se arregla la ficha moviendo márgenes sueltos: se cambia la receta y sus números. Canvas de la decisión:
`docs/producto/ficha-ancha-2026-11-18/propuesta.html`.

### «más» solo si el texto se corta (17 nov 2026)

Fernando: «un texto corto… que si le picas más, no sale más, que no aparezca… que sea inteligente». Ningún «más» se decide
por número de letras: todo texto plegable usa `FoldingText`, que mide el texto completo contra el que se ve y solo pone
«más» si de verdad se corta (la sinopsis en iPhone, iPad y Mac; la biografía de una persona ya medía así). La TV corta la
sinopsis a tres renglones sin «más».

### Pantalla ancha: la orilla crece y las filas tienen flechas (18 nov 2026)

Inicio replanteado para Mac e iPad (MI2 · II1 · C1–C6, `docs/producto/inicio-ancho-2026-11-18/`). Reglas para toda la app:

- **La orilla crece con la ventana (C2).** Con espacio (`WindowMetrics.roomy`) `DS.Space.gutter` es el 5 % de la columna, de 40 a
  160 pt (`DS.Space.wideGutter`), como la orilla de la ficha ancha; en el iPhone y el iPad angosto, 16. Nunca un margen fijo nuevo.
- **Las tiras cuentan columnas (C5).** Con espacio, pósters y tarjetas anchas llenan el renglón (`DS.Poster.filling`: de 5 a 10
  pósters, de 3 a 6 tarjetas anchas) con un pedazo de la siguiente asomando. «Lo nuevo de lo tuyo» toma el ancho de un póster.
- **Toda fila horizontal lleva ‹ › con el puntero (C4).** `.pagingArrows()` en su `ScrollView`: salen al pasar el mouse o el
  trackpad y avanzan casi una pantalla; con el dedo no salen. `DesignRulesTests+WideHome` lo cuida.
- **Una sola barra arriba en el iPad con espacio (C1).** Como la Mac: el logo, «Buscar», las pestañas y tu foto en el renglón de
  la pantalla (`TopRow.tabsInLogoRow`, `macOwnTopRow`); la barra de pestañas del sistema se esconde. Angosto, la de siempre.
- **Inicio: tablero o cine (MI2 · II1).** Ventana acostada y ancha (1100 pt en el iPad, 1200 en la Mac; `HomeBoard.isOn`):
  la portada como tarjeta en dos tercios y a la derecha lo tuyo («Seguir viendo» en renglones, «Lo nuevo de lo tuyo» y «Decide
  por mí», `HomeBoardPanel`). De pie, angosta o con letra de accesibilidad: la portada de orilla a orilla de siempre. El control
  abierto a la derecha angosta la columna y puede volver el cine.
- **«Decide por mí» es tarjeta con espacio (C6).** Al final de «Seguir viendo» (cine) o en el panel (tablero), sin la tira.

### Tu nube: nunca Real-Debrid a secas (18 nov 2026)

DN1: Orbital funciona con Real-Debrid, TorBox o AllDebrid, una a la vez (Ajustes › Cuentas › Tu nube; la guía abre la misma
página en su hoja, `DebridCloudSheet`).

- **Los textos dicen tu nube.** Usa `service.name`, `service.site` y `service.keyPlace`, o `Text(_:cloud:locale:)` para un texto
  del catálogo. «Real-Debrid» a secas solo vale si el texto nombra las tres, o si es algo que solo tiene Real-Debrid (el código de
  real-debrid.com/device, canjear puntos) y se marca `// solo Real-Debrid`.
- **Antes de elegir no se nombra ninguna sola.** Primero «Ya tengo cuenta» y «Todavía no tengo», y no se recomienda ninguna.
- `DesignRulesTests+Cloud.swift` lo vigila.

### Mantener no es tocar (18 nov 2026)

Un botón que además se mantiene presionado (para explicar, para la segunda acción del control) no hace también lo del toque
al soltar. Cada `LongPressGesture` simultáneo lleva en su renglón `// soltar-no-toca: <cómo>` (una marca `held` que el
botón revisa). Se vio en «¿Qué ya tienes?»: mantener para leer qué es marcaba la tarjeta como «la tengo».
`DesignRulesTests.testHoldingIsNotAlsoTapping` lo vigila.

### La guía no se reacomoda (18 nov 2026)

El paso donde estás sigue en el plan de la guía aunque ahí mismo conectes la pieza (tu nube, Trakt, la TV): la luna del arco
no regresa al principio. `OnboardingModel.plan` incluye los pasos visitados (`reached`).
`OnboardingModelTests.testConnectingOnItsStepKeepsThePlace` lo vigila.

### En las escenas de la guía nada se corta (18 nov 2026)

Las miniaturas de la guía son angostas: un nombre junto a un ícono no cabe y salía «i…», «iP» en el dibujo de Trakt. Si un
texto puede no caber, va dentro de `ViewThatFits` con una versión sin texto (solo el ícono, y el nombre para VoiceOver); nunca
se trunca. `DesignRulesTests.testSceneDeviceNeverCutsItsName` vigila `SceneDevice`.

### Esperas que se cancelan (19 nov 2026)

En un `.task(id:)`, cuando cambia el `id` SwiftUI cancela la tarea vieja, pero `try? await Task.sleep` se traga la
cancelación y lo de abajo corre igual, tarde, sobre lo nuevo. Pasó en la primera pantalla de una lección (la escena se
congelaba antes de aparecer) y estaba igual en «¿Seguro?», el póster que se rinde, el salto pendiente del reproductor y el
mosaico. Se escribe `guard (try? await Task.sleep(…)) != nil else { return }` (o `break` en un ciclo).
`DesignRulesTests.testTaskIDWaitsStopWhenCancelled` lo vigila.

### Escenas de lección: escala y giro antes del lugar (19 nov 2026)

En una escena de Aprende, una pieza puesta con `sceneAt` crece o gira con `.scaleEffect`/`.rotationEffect` **antes** de
`sceneAt`; después, crece alrededor de la esquina del lienzo y se sale de su lugar (los tres pósters de «Junta filtros» se
salían de la cuadrícula). `scenePut` con escala o giro, solo en piezas que vuelan con `dx`/`dy`.
`DesignRulesTests.testScaledScenePiecesScaleBeforeTheirPlace` lo vigila.

### Idiomas en un solo lugar (22 nov 2026, ID-A)

Todo lo de idioma vive en un renglón de Ajustes, «Idiomas», igual en iPhone, iPad y Mac: la app (menús), los títulos y
sinopsis (aparte; si nunca lo elegiste, el mismo de la app), lo que ves (el audio, en orden), los subtítulos y el país. Dos o
tres opciones cortas se eligen a la vista con `DSSelector`, nunca con una lista que abre otra pantalla.
`testLanguagesLiveInOnePlace` y `testOneSelectorEverywhere`.

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

### Las fechas ISO se leen con `ISODates` (21 nov 2026)

Nunca un `ISO8601DateFormatter()` nuevo por llamada: se usa `ISODates.parse`, `ISODates.string` o `ISODates.day`
(`OrbitalAddons/ISODates.swift`), creados una sola vez. *Por qué:* crear uno arranca ICU y gasta mucha pila; la ficha de una
serie armaba dos en cada dibujo y, al girar el iPhone (también con el reproductor encima), la 2436 se cerró por pila agotada.
`ISODatesRuleTests` falla si vuelve a aparecer fuera de `ISODates.swift` y de la demostración.

**Cada renglón de Ajustes lleva su ícono (23 nov 2026).** También los interruptores y selectores de las subpáginas
(Subtítulos, Letra, Reproducción, Descargas, Avisos, País): `DSToggleRow`, `SettingsMenuRow` (menú), `SettingsChoiceRow` (dos o
tres opciones a la vista) y `SettingsRow`, cada uno con `symbol:` y `tint:`. Un `Toggle`/`Picker` suelto se veía crudo y su
texto empezaba más a la izquierda. `testEverySettingsRowHasItsIcon` lo cuida.

**Lo que llega de iCloud se lee también al arrancar (23 nov 2026).** En la Mac la app nace activa y `onChange(of: scenePhase)`
no corre al abrir: lo que depende de «al volver a la app» se pide además en un `.task` del arranque (tu nube compartida:
el TorBox del iPhone no llegaba a la Mac hasta abrir su página). `testSharedCloudIsReadAtLaunch` lo cuida.

**Girar el iPhone no cierra la ficha (23 nov 2026).** La 2480 se volvió a cerrar al girar con el reproductor encima: la ficha de
abajo se rearmaba dentro de la pila del giro y SwiftUI se acababa la pila resolviendo el tipo enorme de su cuerpo. Cada forma de
la ficha (ancha y de una columna) va en su propia vista con el tipo borrado (`TitleLayoutHost { AnyView(...) }`), así se arma en
su turno y no dentro del cuerpo de `TitleView`. `testTitleLayoutsBuildInTheirOwnView` falla si se vuelve a llamar directo.

### El video, del tamaño de su imagen (21 nov 2026)

Parado, el recuadro del video toma la forma de la imagen de verdad: si el archivo trae rayas negras pintadas a los lados (un 4:3
rellenado a 16:9), `PictureBars` las encuentra en tres cuadros y el motor llena ese recuadro, así que las rayas quedan fuera.
Parado no hay zoom: ni «Imagen» en el «⋯» ni pellizco. Acostado sí, y el video sigue a los dedos mientras pellizcas. *Por qué:*
*It's Always Sunny* T4 salía parado con dos rayas a los lados, y llenar parado recortaba tres cuartas partes de la imagen.
`DesignRulesTests+VideoFrame` falla si el motor recibe otro zoom que `engineZoom` o si vuelve un zoom en vertical.

### Un aviso arriba a la vez (23 nov 2026)

En el reproductor nunca se ven dos avisos de texto arriba al mismo tiempo. Comparten un solo lugar y `topNotice` elige cuál:
primero la guía del pellizco mientras tienes los dedos puestos, luego el aviso con botones, luego el resultado de lo que
acabas de hacer (el zoom) y al final lo que solo informa (subtítulos, «Orbital ajustó la imagen»). Cada uno conserva su
forma. *Por qué:* al pellizcar, «Suelta para llenar la pantalla» salía encima de otro aviso y chocaban.
`DesignRulesTests+TopNotice` falla si un aviso de arriba vuelve a pintarse por su cuenta o con otra píldora.

### Lo que eliges en el reproductor se ve al tocar (23 nov 2026)

Cambiar de versión, de audio, de subtítulo o de episodio se ve elegido al momento (la palomita, la carga) aunque el motor o la
red tarden, y el último toque gana: lo que llega tarde de un toque anterior no se pone encima ni te regresa al principio. Lo que
no se ve (guardar en Stremio y Trakt, la bitácora) corre aparte y nunca hace esperar al cambio. *Por qué:* tocar dos versiones
seguidas empezaba la película desde el principio, el audio nuevo no se marcaba hasta 2 s después, un subtítulo de internet que
llegaba tarde tapaba el que elegiste y otro episodio esperaba a que se guardara el anterior. `InstantSwitchingTests` lo vigila.

### Pegar es el botón del sistema (22 nov 2026)

Para pegar se usa `PasteButton`, nunca `UIPasteboard.general.string` leído por código; al pegar se quitan los espacios y los
saltos de las orillas. *Por qué:* leerlo por código hace que iOS pregunte «Permitir pegar» cada vez, y así pasaba al pegar la
clave de una nube. Copiar (escribir en el portapapeles) sí se vale. `DesignRulesTests+Paste` falla si vuelve una lectura.
