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

- **Regla: lo que se desplaza a lo ancho abre mostrando lo importante completo, y dice que hay más.** Lo importante es lo de
  hoy (o lo elegido); «completo» es sin una columna o tarjeta a medias en la orilla de la columna; «dice que hay más» es un
  desvanecido en la orilla de lo que queda atrás (o la tarjeta que se asoma en un carrusel de orilla a orilla).
- Los mapas de semanas son una pieza, `DSWeekStrip` (`Design/WeekStrip.swift`, medidas en `DS.WeekStrip`): las casillas salen
  del ancho que le queda (`WindowMetrics.column`), caben semanas enteras, abre en la de hoy por su id (también cuando llega
  más historial), se detiene por semanas, desvanece lo de atrás y, si todo cabe (iPad, Mac), no se desliza. Arriba, el mes
  abreviado («oct», el año en enero); a la izquierda, L, X y V; hoy con borde; debajo, «Hoy» y «Menos ▢▢▢▢ Más».
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
| Marcar como visto | `checkmark.circle` / `checkmark.circle.fill` (`DS.Symbol.watched`, `watchedFill`) | Mosaico «Vista» de la ficha (lleno y en verde: ya la viste) |
| Volver a empezar | `arrow.counterclockwise` (`DS.Symbol.restart`) | ↺ «Desde el principio», junto al avance (R1) |
| Tu nota | `note.text.badge.plus` / `note.text` (`DS.Symbol.addNote`, `note`) | Al final de «Tu calificación» |
| Calificar | `star` (`DS.Symbol.rate`) | «Calificar la temporada», en el menú de «Vista» |
| De este episodio en adelante | `arrow.right.circle` (`DS.Symbol.fromHereOn`) | «¿Para el resto de la serie también?» › «Sí, desde aquí» |
| Solo este episodio | `1.circle` (`DS.Symbol.onlyThisOne`) | «¿Para el resto de la serie también?» |
| Salir del reproductor | `xmark` (`DS.Symbol.leavePlayer`) | «¿Sigues viendo?» › «Salir» (la ✕ de la barra del reproductor) |
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
| Paso · Guardar · Para hoy | `xmark`, `heart.fill`, `star.fill` (`DS.Symbol.matchPass`, `matchKeep`, `matchTonight`) | «Una por una»: los botones y el sello de la carta |
| Botones de otras consolas | `xmark`, `circle`, `square`, `triangle`, `line.3.horizontal`, `rectangle.on.rectangle` (`DS.Symbol.padCross`, `padCircle`, `padSquare`, `padTriangle`, `padMenu`, `padView`) | El acompañante del juego (cómo quedan los botones) |
| El mosaico | `square.grid.3x3` (`DS.Symbol.mosaic`) | La chapa de la portada de Explorar, el mosaico vacío. Solo él usa la cuadrícula de 3×3 (MO1) |
| «Lo que ves» | `chart.bar.xaxis` (`DS.Symbol.whatYouWatch`) | El índice de Explorar (antes la cuadrícula rellena, que se confundía con el mosaico) |
| Toda la serie (descargar) | `square.stack.3d.up` (`DS.Symbol.wholeSeries`) | «Descargar» de una serie (antes la cuadrícula del mosaico) |
| Cerrar y regresar | `xmark` (`DS.Symbol.close`) | Salir del mosaico en el iPad y la Mac (F1); «Cerrar» del panel de una ficha |

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
para el tipo, su tamaño compacto `DSKindFilter`, que dice el nombre de lo elegido («Todo», «Películas», «Series») adentro de la pastilla, a la izquierda de los íconos, y la pastilla mide justo lo que necesita: sin hueco apartado para el nombre más largo (KT2, 14 nov; antes KT1 lo ponía afuera). Donde va a la derecha (Guardado) los íconos no se mueven al elegir. En Inicio, recién elegido, el nombre ocupa el lugar de lo que había a la izquierda: el círculo se queda donde lo tocaste y luego la pastilla se recoge, todo un poco más pausado (`DS.KindPill.pace`). Las pestañas subrayadas
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

**La marca es una sola en toda la app.** El Centro de control y la Live Activity usan el símbolo `orbital.mark`, que sale
del mismo dibujo que `OrbitalMark` y el ícono (`scripts/orbital_symbol.py`, que llama a `scripts/orbital_mark_path.swift`). Si
cambia la marca (`DS.Brand`), se corre el script. `testBrandSymbolMatchesTheMark` compara su firma con `Tokens.swift`.

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
