# Proyección: el sistema visual de Orbital para iPhone

> **Nativo en todo. Propio en una sola cosa: el arte es la luz.** Y es la misma luz que la TV: el iPhone usa la cuenta de
> `orbital/web/js/core/color.js` (`ArtPalette`, con sus mismas pruebas), los mismos nombres y la TV es la fuente de verdad.
> La interfaz es iOS 26 tal cual (Liquid Glass, barra de pestañas con búsqueda, hojas, menús, SF Pro). Lo único propio es
> cómo se enciende la pantalla: con el color de lo que estás viendo, como una sala a oscuras cuando empieza la película.

Las maquetas viven en el canvas de diseño (página «Proyección»). Este documento es la referencia de código: qué existe,
cuándo usar cada pieza y qué vigilan las pruebas. **Nada se crea suelto**: las pantallas solo componen piezas de
`ios/App/Sources/Design/` con tokens de `DS` (que salen de `OrbitalCore.DesignTokens`).

## 1. Capas

| Capa | Qué va | Cómo |
|---|---|---|
| **Navegación** (vidrio) | Barra de pestañas, pestaña de búsqueda, botones de la barra superior, accesorio «En la TV», hojas | Solo controles nativos (`TabView`, `Tab(role: .search)`, `.toolbar`, `.sheet`, `tabViewBottomAccessory`). Nunca vidrio en tarjetas ni chips (HIG › Materials). |
| **Contenido** | Arte, estantes, listas, botones de acción | Rellenos del sistema (`.bordered`, `List`/`Form`), tokens de papel. El efecto de borde de desplazamiento del sistema separa una capa de la otra. |
| **Sala oscura** (sobre el arte) | Lo que va encima de un póster o un fondo: logo, rótulo, datos, botones | `.onArt()`: siempre como en modo oscuro, en los dos modos. El velo (`DS.scrim…`) es negro siempre. |

## 2. Color: papeles, no paleta

Las pantallas usan **papeles** (`DS.bg`, `DS.text`…), que cambian solos con el modo. La paleta de la consola
(`palette.json`) es el modo oscuro; el claro es «papel». `DesignTests.testBothAppearancesHaveReadableContrast` exige
WCAG AA en los dos.

| Papel | `DS.` | Oscuro | Claro | Para |
|---|---|---|---|---|
| background | `bg` | ink-950 | #f6f5f1 | Fondo de pantalla |
| surface | `surface` | ink-850 | #ffffff | Renglones de listas y formularios (la TV usa ink-900: distinto a propósito, ver `design/tokens.json`) |
| surfaceRaised | `surfaceRaised` | ink-800 | #ebe9e3 | Placeholders |
| label / secondaryLabel / tertiaryLabel | `text` / `textMuted` / `textFaint` | paper / ink-300 / #868687 | #111113 / #5c5c64 / #6b6b72 | Texto; el terciario también se lee (≥ 4.5:1, el blanco al 50 % de la TV) |
| decorative | `ink500` | ink-500 | #9a9aa1 | Solo adornos que no se leen: la cifra del Top 10 (`--color-decorative` en la TV) |
| primary / onPrimary | `primary` / `onPrimary` | paper / ink-1000 | #111113 / paper | **La** acción principal (una por pantalla) |
| accent | `accent` | paper | #111113 | Avance, selección y foco (como `--color-focus` y las barras de la TV) |
| live | `live` | teal-300 | #0b7a6e | **Solo «En vivo»** (como `--color-live` en la TV) |
| warning / danger | `warning` / `danger` | amber-300 / red-400 | #9a6200 / #c4362c | Avisos |

Capas translúcidas (`hairline`, `fill`, `fillStrong`, `track`): blanco en oscuro, negro en claro, con `DesignTokens.Opacity`.

### El color del arte (la firma)

`Backdrop(tint:)` + `ArtTint` → `ArtColors`: el **tono dominante** del arte (no el promedio, que se vuelve café) sale de una
miniatura de 48 px con `ArtPalette` — la misma cuenta que la TV — en dos colores:

- `tint` (L 0.20): tiñe el fondo en modo oscuro (`--art-tint`), fundido al fondo a `DesignTokens.Projection.fadeTo` (62 %).
- `accent` (L 0.76): **el botón principal** (`.dsArtButton(colors)`, texto oscuro encima, como `--color-primary-art`) y, en modo
  claro, un velo suave sobre el papel (`lightMix` 0.84). Sin tono (arte gris): los neutros de la TV (rgb 205 205 211).
- Cambia en `DS.Motion.tint` (0.7 s, como la TV); con «Reducir movimiento», sin animación.

Dónde: Inicio (el destacado del carrusel), Para ti › Mosaico (la pieza enfocada), la ficha (su fondo), Descargas (lo que
se baja). Un solo color por pantalla.

### Arte a sangre

`BleedArt` (y `HeroCard` encima de él): en oscuro el arte se funde con el fondo de borde a borde; en claro es una tarjeta con
esquinas continuas (la sala oscura no se funde con el papel). El texto encima, con `.onArt()`. Los logos oscuros y sin color
(medidos con `LogoTone`) se pintan claros; los de color se respetan.

## 3. Texto: recetas

`DS.TextRecipe` + `Text.recipe(_:)`. SF Pro con Dynamic Type; los datos (tiempos, temporadas, tamaños) con **números
tabulares**, como `tabular-nums` en la TV. `DesignTests` prohíbe `DS.font(…)` en la app: todo pasa por una receta.

| Receta | Estilo | Uso |
|---|---|---|
| `display` | largeTitle bold | Títulos grandes fuera de la barra |
| `title` | title bold | El título de una hoja (`DSSheetHeader`) |
| `section` | title2 bold | **Subsección**: el título de una fila o estante (`DSSectionHead`, `Shelf`, `Rail`), con su porqué turquesa arriba si ayuda |
| `groupLabel` | footnote negrita, en letra normal (2 nov 2026) | **Sección**: `DSSectionHead(level: .section)` pinta `DSChapterLabel` (el rótulo con su línea), sola, sin porqué; dentro de una hoja o panel, `DSGroupLabel` |
| `eyebrow` | footnote semibold, turquesa | El porqué arriba de una subsección o de una portada (≤ 38 letras, sin cifras) |
| `cardTitle` | headline | Nombre en una pieza o renglón |
| `body` | body | Texto de lectura |
| `secondary` | subheadline | Datos de una ficha |
| `footnote` / `caption` | footnote / caption | Pies, nombres bajo un póster |
| `label` / `labelLarge` | footnote / subheadline semibold | Botones chicos, el valor de un control, datos que resaltan |
| `badge` | caption bold | Placas («4K», «Nuevo») |
| `stat` | largeTitle heavy, tabular | Las cifras grandes (Lo que ves, el porcentaje, las horas) |
| `data` | footnote, números tabulares | `DataLine`: «T2 E5 · quedan 20 min · termina a las 23:21» |

Encabezados en **dos niveles** (Fernando, 30 oct 2026): una sección agrupa varias cosas y va sola; una subsección es una
fila o estante y lleva su porqué en turquesa solo si ayuda. Nada de torcer una receta con `.weight`/`.fontWeight`:
`DesignRulesTests` lo prohíbe (fuera del reproductor, el iPod, la marca y la tele de Los Simpson).

### Piezas y tokens de la auditoría del 31 oct 2026 (`Design/Surfaces.swift`, `Tokens.swift`)

- Cajas: `.dsCard(.row)` (renglón o caja, esquina `lg`) y `.dsCard(.card)` (tarjeta grande, `xl`), siempre continuas; en la
  superficie (blanca en claro) o translúcidas (`translucent: true`) sobre arte o dentro de otra caja. `DSCard` les pone su aire.
- Hojas sin barra: `DSSheetHeader(title:subtitle:close:)` dentro de `dsSheetContent()`; el ✕ es siempre `DSIconButton`.
- `DSIconButton(size: .small/.regular/.large)`: el único círculo de vidrio. `dsPrimaryButton(size:)`, `dsSecondaryButton()`,
  `dsGlassButton()`: los demás botones.
- Esperas: `DSInlineProgress(text:)` junto a lo que lo pidió; `DSLoadingState` para un área; `DSEmptyState` vacío.
- Lo elegido: `.dsSelectionRing(_:)` en el color del texto, del grueso `DS.Stroke.selected` (líneas: `DS.Stroke.hairline,
  regular, selected, focus`).
- `DSSeasonMenu`: las temporadas en una lista desplegable nativa («Temporada 3 ⌃⌄») en la ficha, Mi media y la hoja de
  episodios. `DSSeasonPicker`: las cápsulas «T1, T2…», solo en el panel de episodios del reproductor (Fernando, 1 nov 2026).
- `DSGroupLabel`: el rótulo de un grupo. `HeroSkeleton`: la portada mientras llega.
- Opacidad: `DS.Opacity.disabled, dimmed, faint, pressed, selectedFill`. Movimiento: `DS.Motion.fade` (solo opacidad, también
  con «Reducir movimiento»), `snap`, `reveal`, `appear(_:)` para tarjetas que entran. Sombras: `DS.Elevation.low/medium/high/
  floating`; brillos de color: `.glow(color, .soft/.strong)`. Radios: `DS.Radius.tag` (placas) y `DS.Radius.logo(lado)`.
- Ritmo: el primer contenedor de cada pantalla separa con `DS.Layout` (`titleToContent`, `betweenSubsections`,
  `betweenSections`, `screenBottom`).
- Los tokens de pieza (`Tokens+*.swift`) salen de la escala (`DS.Space`, `DS.Radius`); lo que no, con `ds-exception: motivo`.
  `DesignRulesTests` vigila las 13 reglas y que no quede ningún token sin uso.

## 4. Piezas (catálogo)

`Design/Projection.swift` (Proyección) y las piezas por tema (`Design/Badges.swift`, `Posters.swift`, `Art.swift`, `Buttons.swift`, `Feedback.swift`, `Filters.swift`, `PlayerIndicators.swift`, `Backdrop.swift`, `Storage.swift`, `Labels.swift`, `RemoteImage.swift`), `Design/Shelf.swift`, `Design/Mosaic.swift` (base).

| Pieza | Qué es | Dónde |
|---|---|---|
| `Backdrop(tint:)` | Fondo con el color del arte | Todas las pantallas |
| `BleedArt` / `HeroCard` | Arte a sangre con rótulo, logo, `DataLine`, acciones y avance; con `collapse:` (dentro de un `ScrollView`) se recoge al desplazar hacia ese color (ver «Movimiento») | Inicio (carrusel), Para ti › Listas, ficha (`collapse`) |
| `DataLine` | Datos con números tabulares (no una monoespaciada); quita del final lo que no cabe | Destacados, ficha, descargas |
| `Eyebrow` | Rótulo pequeño (acento o sobre el arte) | Destacados |
| `HeroActions` | Las acciones de un destacado en un renglón; si no caben (letra grande, iPhone SE), apiladas | Inicio (carrusel), Para ti › Listas |
| `ActionTileLabel` | Acción de la ficha: rectángulo que llena su parte del renglón, ícono arriba y nombre abajo; activa con el color del arte; con anillo de avance alrededor del ícono (Descargar). Tocar hace lo principal, mantener presionado el resto (`Menu` con `primaryAction`) | Ficha (Guardar, Descargar, Tráiler, Fuente) |
| `Glyphs/donut` (catálogo de imágenes) | La dona de Los Simpson, con el trazo de los íconos propios (solo iPhone; los de `Icons/` vienen de la TV) | Inicio › un Simpson al azar (el dado es «¿Qué vemos?») |
| `DSKindFilter` | El filtro de tipo de toda la app: Todo · Películas · Series (o Películas · Series). Segmentado a lo ancho; `compact`, el switch chico junto al título (dos opciones, Top 10); `menu`, la lista que se despliega en cápsula (tres opciones junto al título: En tendencia, Destacado) | Inicio (destacado y Top 10), Para ti › Listas, plataforma, colección por año, Buscar (con cuántas), «¿Qué vemos?» |
| `Text.withTitleChevron()` / `DSTitleChevron` | «Ver todo»: la flecha gris al final del título, dentro del mismo texto (centrada con su renglón y al final del último si se parte); junto a un rótulo de sección, `DSTitleChevron` a la derecha de su línea; todo el encabezado abre la lista (2 nov 2026: sin cápsula de texto, como Música y la App Store) | Todo encabezado que abre su lista completa, la tarjeta de «La temporada» |
| `DSCapsuleLabel` | La cápsula tenue de un filtro desplegable a la derecha de un título: «Todo ⌄», «Filtrar · 2» | Los filtros desplegables (un calendario o una acción de un solo ícono van en `DSIconButton`) |
| `DownloadVersionSheet` | «Ya la tienes»: la versión que tienes y la que elegiste lado a lado (mismo alto) y tres salidas del mismo tamaño: bajar también esta, cambiarla o dejarla | Descargar una fuente de algo que ya tienes (ficha) |
| `PlayerFailureView` | Cuando el reproductor no puede: ícono, qué pasó desde tu lado y solo las salidas que sirven (sin fuentes: Cerrar; ninguna sirvió o se cortó: Intentar de nuevo, Infuse, Cerrar; sin red: Intentar de nuevo). Reemplaza los controles | Reproductor |
| `SubtitleButton` | El botón de subtítulos del reproductor: con subtítulos, el idioma en corto («ES») en una placa sólida dentro del círculo (como el «CC»); apagados, la burbuja vacía; un toque abre los subtítulos rápidos (`SubtitleDock`), mantener presionado los apaga o prende | Barra del reproductor |
| `SubtitleDock` | Subtítulos rápidos: un panel chico sobre el video (abajo en vertical, arriba en horizontal para que se vean los subtítulos) con idioma (Apagados · Español · Inglés · Otro…), versión con ‹ ›, su etiqueta honesta («Hecho para tu copia» por el nombre de la copia, «Misma fuente», «Del video», descargas) y «N de M»; al cambiar de versión, «¿Va a tiempo? Sí, va bien / Probar otra» con las probadas tachadas; Tiempo «− Antes · A tiempo · Después +», «Sincronizar con una línea», Tamaño y Listo. Tocar la versión abre la media hoja con todas | Reproductor |
| `SubtitleSyncView` | «Sincronizar con una línea»: tres frases que vienen; tocas la que oyes y el tiempo se ajusta solo (se recuerda por versión); «¿Ya van bien? Sí / Otra vez» | Reproductor (dentro del panel de subtítulos) |
| `DSCornerRibbon` (`Design/CornerRibbon.swift`) | «Nuevo»: el listón verde en diagonal en la esquina del póster (nunca un punto ni una cápsula). `compact`, el de los pósters chicos del widget. Vive aparte para que la extensión de widgets lo compile | Inicio › Lo nuevo de lo tuyo, Descargas, widget «Lo nuevo de lo tuyo» (mediano: en el póster; chico: en la esquina del widget) |
| `DownloadSpeedTestView` | «Probar la velocidad»: tu internet, Real-Debrid con 1 y con 8 conexiones, y como baja la app en segundo plano; qué quiere decir y «Copiar resultados» | Ajustes › Descargas |
| `SubtitlePreview` | Una escena de muestra con «— Así se van a ver.» dibujada con tu estilo (fondo, tamaño, posición, estilo del iPhone) | Ajustes › Idioma y subtítulos |
| `subtitleLook(_:size:)` | El estilo de una línea de subtítulo: contorno oscuro o caja (oscura, translúcida o la del iPhone); lo comparten el reproductor y la muestra de Ajustes | `AetherSubtitleOverlay`, `SubtitlePreview` |
| `CalendarDayCell` | Un día del calendario de estrenos, pintado con el color del arte de lo que sale; dos el mismo día, la casilla partida; más, «+N» | Sale hoy › el mes |
| `DSEmptyState` | Un área entera vacía: el vacío nativo con ícono, qué pasa y qué hacer. Regla: área vacía → esto; renglón vacío → texto chico; error → `DSNotice` | Descargas, Buscar, listas con filtros, Próximos estrenos, Inicio, «¿Qué vemos?», Tu año, Para ti |
| `DSDegradedNotice` (envoltorio `DegradedNotice` en `Screens/Shared.swift`) | Modo degradado: cuando algo no llegó, la causa de verdad (`Degraded`: sin internet, un servicio que no contesta, algo sin conectar), qué sigue funcionando y la salida (Tus descargas, Intentar de nuevo, Abrir Ajustes). Tabla de escenarios en `docs/producto/modo-degradado.md` | Inicio sin internet, Buscar sin Trakt |
| `DSMoreMenu` | «Más»: el mismo menú en toda la app, círculo con «…» (vidrio, sólido donde no se lleva) | Destacado de Para ti, «¿Qué vemos?», pie del mosaico, «Viendo en la TV» |
| `DownloadRing` | El anillo de avance de una descarga | Ficha (Descargar) y la fila de cada episodio |
| `StillCard` | Pieza 16:9 con avance, nombre y datos | Inicio › Todo lo que sigues |
| `PageDots` | Puntos de un carrusel | Inicio |
| `MovementBadge` | ▲ ▼ / Nuevo bajo un puesto (sin cambio, nada: un «=» suelto parecía un error) | Rankings de plataformas (Buscar › Lo más popular usa `RankedPosterCard`) |
| `ArtTile` | Mosaico con arte y nombre | Buscar › Explora (géneros) |
| `DSSeasonMenu` | Menú nativo con las temporadas, en la cápsula de los secundarios | Ficha › temporada (a la izquierda; la versión de la serie, la cápsula gemela a la derecha), Mi media, hoja de episodios |
| `DSChoiceMenu` | La misma lista desplegable (`Menu` con `Picker`, cápsula de los secundarios, «⌃⌄») para elegir uno entre opciones que cambian y no caben como pestañas, con ícono si ayuda | Biblioteca › Guardado («Mi lista ⌃⌄»: Mi lista o una tuya de Trakt) |
| `TouchPad`, `RemoteKey`, `RemoteTextField` | El control completo de tu Orbital: pad (deslizar = flechas, tocar = A), teclas de la consola y escribir en la TV | `RemoteSheet` (la hoja del accesorio, estirada) |
| `VoiceCommandBar`, `VoiceChoices` | La voz del control: el micrófono con lo que oyó, la respuesta y lo que entendió; y, si tu Orbital no supo cuál, las opciones para tocar (`VoiceAssistant.choose`) | `RemoteSheet` |
| `GuideSteps`, `GuidePage`, `GuidePiece`, `GuideNumberedStep`, `GuideCode`, `AddonLabel`, `GuideArt` (`Design/Guide.swift`, tokens `DS.Guide`) | La guía de la primera vez y la hoja de «Usar con tu Orbital»: el arco de avance con la luna (`OrbitArcShape`), «Saltar» (`GuideSkip`), página con su botón abajo, pieza con ícono y etiqueta, paso numerado, el código de Trakt, un complemento y la ilustración de una página del tutorial (ícono grande en su recuadro) | Guía, Ajustes › Orbital en la TV |
| `OrbitCatch` (`Design/BrandWelcome.swift`, tokens `DS.Welcome`) | La bienvenida (A1): siete pósters que el planeta de la marca atrapa en su órbita, el anillo que se dibuja y la luna; un solo reloj, pausa en segundo plano y quieta con «Reducir movimiento» | Guía |
| `StoryPlayer`, `StoryCardView`, `StoryGesture`, `StoryBeforeAfter`, `LearnRings`, `LearnRing` (`Design/Stories.swift`, tokens `DS.Story`) | «Aprende Orbital» (G3): una historia a pantalla completa con sus cinco plantillas de tarjeta (portada, tres pasos, gesto, antes y ahora, símbolo) los círculos con su anillo de «nuevo» (`LearnRings`, `LearnRing` con `compact`, `LearnRingMark`) y lo que se asoma en la orilla de Inicio (`LearnPeek`, tokens `DS.HomeStories`) | Inicio, Ajustes › Aprende Orbital |
| `CoachContent`, `.coachAnchor(_:)`, `.coachHost(…)` (`Design/CoachMark.swift`, tokens `DS.Coach`) | Los avisos sobre la pantalla (F3): con foco (velo con hueco, anillo que se dibuja una vez) o aviso chico; en las pantallas se usan con `.learnCoach(…)` (`Screens/LearnCoach.swift`) | Ficha, Buscar, Explorar, Descargas |
| `QRScanner` (`Design/QRScanner.swift`) | Lee el código QR de la TV dentro de la app (VisionKit) con su recuadro; si el aparato no puede (simulador, sin cámara), lo dice y ofrece «Conectar a mano» | Ajustes › Orbital en la TV |
| `VoiceGuideView` | «Lo que puedes decir»: dónde hablarle (control, Siri, Alexa), lo que solo hace el iPhone, las frases de la consola (alexa/commands.json) y qué hacer si no funciona | Ajustes › Voz y el «?» junto al micrófono del control |
| `OrbitalIcon` | Los íconos propios de Orbital, los mismos de la TV (icons.js → `node scripts/list_icons.mjs` → Assets.xcassets/Icons; tests/web/list-icons.test.mjs los mantiene iguales). En el iPhone solo como marca | La pestaña Para ti |
| `DeckCard`, `deckTransition` | El carrusel de «En tendencia»: tarjetas con lo que sigue a los lados (más chicas, desenfocadas y giradas en 3D) | `HomeView` |
| `AvatarImage`, `AvatarPicker` | Tu avatar (Assets › Avatars, 12 espaciales) y su selector | `HomeView` (junto al saludo), Ajustes |
| Botón «Control de tu Orbital» (`av.remote`) | Sin nada en la TV, abre el control completo desde la barra de Inicio (el accesorio solo aparece mientras la TV reproduce, y no dentro de fichas ni Ajustes) | Inicio, con tu Orbital conectada |
| `fittedSheet()` / `subtitle(_:)` | Hoja a la medida de su contenido; subtítulo de la barra solo cuando dice algo | Hojas cortas; Inicio, Para ti, Descargas |
| `TVAccessory` | Lo que suena en tu Orbital, en el accesorio de la barra | Toda la app (iOS 26.1+) |
| `Shelf`, `RankedPosterCard`, `PosterCard`, `TitleLink`, `Rail` | Estantes, Top 10, pósters | Para ti, Inicio, Buscar |
| `Mosaic` | El mosaico que sube despacio (como `foryou-mosaic.js` de la TV) | Para ti |
| `DSSegmented`, `DSChipRow`, `DSIconButton`, `DSNotice`, `DSProgress` | Controles nativos con los tokens de Orbital | Varias |
| `DSSectionHead` | El encabezado de toda sección («Editorial»): título grande, la flecha de «Ver todo» pegada al título si abre la lista completa (o un dato corto a la derecha); de dónde viene una lista (Trakt) lo dice el porqué, no un sello y una línea gris solo si ayuda; sin íconos | Todas las pantallas (también `Shelf` y las listas de Descargas) |
| `CoverCard`, `WideCard` | La portada de una sección (lo más importante en grande, con su porqué en turquesa) y la pieza panorámica con su dato en la esquina | Inicio › Sale hoy / Sale pronto |
| `posterCaptions` (entorno) | El nombre bajo el póster: sí en cuadrículas, no en las tiras de una sección | Tiras y cuadrículas |
| `ProfileButton` | Tu avatar arriba a la derecha de cada pestaña: abre Ajustes | Inicio, Explorar, Buscar, Biblioteca |
| `StorageBar` | El espacio del iPhone: arriba «Orbital usa 7,2 GB» y «75,0 GB libres» (ámbar con poco espacio); la barra con series, películas, otras apps y libre, y la leyenda con la cifra de cada una, «Otras apps» incluida (2 nov 2026, I1) | Biblioteca › Descargas |
| `DownloadRingButton` | El anillo de una descarga con lo que hace: ‖ pausa; en pausa, la flecha y «Seguir» debajo; si falló, ↻ y «Reintentar» (2 nov 2026, I3) | Descargas, ficha › fila de un episodio |
| `DSToggleRow` · `DSSwitchStyle` | Un interruptor con nombre corto y su explicación en gris abajo (ícono opcional); todo interruptor prendido en el turquesa de la marca (`DS.switchOn`), puesto una vez en `OrbitalApp` | Descargas › Descarga inteligente, Ajustes |
| `listHeadRow()` · `listHeadRows()` | El rótulo de una sección como renglón de una lista agrupada: a ~20 pt de su tarjeta y ~40 entre secciones | Descargas |
| `SettingsRow`, `ProfileCard` | Renglón de Ajustes con su ícono de color y su valor actual; tu perfil arriba (el avatar con lápiz) | Ajustes |
| `SimpsonsSeasonsSection` | De qué temporadas sale «Un Simpson al azar» (`SimpsonsSeasonsPicker` con lo guardado) | Ajustes › Un Simpson al azar |
| `PlayerCircleButton`, `PlayerMenuRow` | «Barra limpia», la misma en vertical y en horizontal: arriba ✕, el nombre, subtítulos, AirPlay y «⋯»; el «⋯» abre un globo con un renglón por acción (Audio y subtítulos, Zoom con el puesto a la derecha, Ventana, Ver en la TV, Descargar y, aparte, Bloquear pantalla) | Reproductor |
| `SourceOrbit` | «Buscando la mejor versión»: el planeta al centro y una órbita que se llena con un punto por cada versión que de verdad trae cada complemento (`StreamFinder.events`); un barrido gira mientras se pregunta, la elegida se pinta del turquesa de la luna y viaja al planeta. Siempre al centro de la pantalla: en vertical la órbita sobre los textos, en horizontal a su lado. Con «Reducir movimiento», solo textos | Reproductor |
| `PlayerScrubBar`, `PlayPauseButton`, `SkipButton` | La barra de avance fina con las horas a los lados (lo visto en el color de Orbital, intro/resumen/créditos marcados, perilla que crece al arrastrar); el botón grande de vidrio (el único con círculo) y ±10 como flecha en círculo sin fondo; «Saltar intro», cápsula sólida | Reproductor |
| `PlatformBadge` | La píldora de una plataforma en su color con su logo chico: «En Netflix» o, con `rank`, solo «N.º 1» (el logo dice dónde; VoiceOver dice «Número 1 en Netflix»). Una plataforma sin logo, cápsula de vidrio con el texto completo | Mosaico y destacados de Para ti; pósters de Para ti › Listas (Recomendadas, «Porque viste») |
| `PlatformPill` | Una plataforma en cápsula (logo chico y nombre); la elegida con su color tenue y su borde | Inicio › Top 10 (elegir de qué servicio) |
| `DecideTile`, `DecideListRow` | «¿Qué vemos?» › «Más filtros»: el mosaico de un género o una época con su imagen (generada con Grok Imagine, en `Assets.xcassets/Decide`, viene con la app), velo abajo con el nombre y cuántas opciones tiene; al elegir crece con rebote (`DS.Motion.pop`), anillo con brillo en el color de Orbital y ✓, y los demás pierden color; las épocas con el número en grande; «De qué listas»: un renglón (carteles apilados, origen, cuántos títulos, marca); los filtros de la hoja son `DSCapsuleLabel` en rejilla 2×2 (`stretch`, `selected`, ⌄ al final) y «Todo ⌄» (`DSKindFilter` menú) junto al título | «¿Qué vemos?» |
| `PanelIcon`, `PanelChip`, `PanelGroupTitle`, `FlowChips` | Ícono del sistema solo en su color (como Ajustes), opciones en cápsula (con glifo opcional), rótulos de grupo y chips que se acomodan en renglones | «Audio y subtítulos» del reproductor, «Decide por mí», Ajustes, Descargas, Buscar |
| `Toast` | El único aviso pasajero: abajo, sobre la barra de pestañas (en el reproductor, arriba), en vidrio; ícono en su tono (neutral gris, hecho turquesa, te necesita ámbar, se perdió rojo), lo que pasó, su dato (hasta dos renglones) y la salida en su cápsula, gris si es opcional y clara si es lo que hay que hacer, sin «›». Dura 4 s, 8 s con salida o hasta que lo toques si te necesita; se quita deslizando hacia abajo. Uno con salida no se pisa: el siguiente espera (`NoticeCenter`, en OrbitalModels, con pruebas). Los resultados de descargar se dicen en un solo lugar (`AppEnvironment.report`). Las notas fijas de una pantalla siguen siendo `DSNotice` | Toda la app |
| `VersionLanguageRow` · `VersionChip` · `VersionEvidence` · `VersionCard` | «Elegir versión» (como la TV): una fila por idioma de audio (el tuyo, el original, latino/castellano/español; los demás plegados) con una cápsula por calidad que existe (dos por renglón), la recomendada con borde turquesa; la tarjeta dice el idioma y la calidad, cómo sabemos el idioma (Comprobado · Lo dice el nombre · Lo dice el sitio · Es el original · No dice idioma · Tal vez), Ver/Descargar y las demás de esa fila y calidad con su nombre técnico | `SourcesSheet` (ficha, Mi media) |
| `AllSourcesList` | «Todas las fuentes»: la lista completa y plana para quien quiere ver todo (`AllSources` en OrbitalModels). «Filtrar · N» (orden: recomendadas, más chicas o más semillas primero; solo las que ya están en Real-Debrid, idioma, grabaciones de cine y tráileres) y la leyenda de los puntos; una sección por calidad («4K · 6») con tres y «+N más en 1080p ›». Cada renglón en dos líneas: punto (turquesa: ya está en Real-Debrid; ámbar: Real-Debrid aún no la tiene; sin punto: no se sabe), «1080p · DV · 12.3 GB», «La que ves» o «Recomendada», y sus idiomas («· se supone» si nada lo dice). Tocarlo lo abre ahí mismo (uno a la vez): nombre técnico (seleccionable), semillas, complemento y sitio, cómo sabemos cada idioma, qué tan rápido arranca y los botones (Ver, Descargar, Copiar nombre). Las ocultas, atenuadas al final de su calidad | `SourcesSheet` › «Todas (N)» (ficha y episodios) |
| `IPodScreen` · `IPodWheel` · `IPodProgress` · `IPodLayout` · `IPodFace` | «Modo iPod» del reproductor vertical (un iPod Classic, blanco o negro; el negro, pantalla incluida, todo oscuro): la pantalla con el marco, «Reproduciendo», el video, el nombre, la versión o el episodio y el avance azul; la rueda (girar busca 10 s por muesca con un clic que se siente, rápido de a minuto; MENU cierra y mantenerlo bloquea; ⏮ ⏭ ±10; ▶❚❚; el centro, «Audio y subtítulos»). Se prende y se apaga en «⋯ › Modo iPod» (no → blanco → negro) | Reproductor (vertical) |
| `FanCard`, `CollectionCard`, `AwardCard`, `AwardEmblem` | La tarjeta en abanico (plataformas y colecciones) con su emblema al frente; un premio con su estatuilla real | Para ti › Listas |
| `ListCard`, `SourceBadge` | Una lista tuya (pila de pósters, nombre, sello y cuántos) y el sello de origen (Trakt, Complemento, Orbital; token `DS.Collections.addon`; Rotten Tomatoes es su jitomate, `Ratings/rating-rotten-tomatoes`, a la altura del título) junto a un título. Si el título y el sello no caben en un renglón, el sello baja: el título nunca se parte a media palabra | Para ti › Listas, «Aprobadas por la crítica» |
| `BecauseCard` | «Porque viste X»: el póster de lo que viste y lo relacionado al lado | Para ti › Listas |
| `YearCard` | Un año con cuatro de sus películas y el número grande | Para ti › Por año |
| `SortableGrid` | Una lista abierta con ordenar y filtrar (series o películas, género, calificación, década, ocultar lo visto) arriba a la derecha; con su vacío, su carga al centro y, si la pantalla ya trae `DSKindFilter`, sin repetirlo (`showsKindFilter`). Donde se sabe cuánto llevas de cada título (`states`), «Estado: Por ver · A medias · Vistas» en lugar de «Ocultar lo que ya vi» (BI3-A, 3 nov 2026) | Listas, premios, años, géneros, temporadas, «Ver todo», Biblioteca › Guardado (el Top de un género abierto va en su cuadrícula con puesto, `RankedPosterCard`, sin ordenar) |
| `DSPosterGrid` | La cuadrícula de pósters de toda la app: columnas fijas que llenan el ancho (`DS.Poster.gridColumns` 3; 4 en pantallas anchas; 2 con letra de accesibilidad), separación `DS.Space.s3`, bordes en el margen; cada celda recibe el ancho de su columna | `SortableGrid`, Buscar (resultados), Persona (filmografía), Top 10 abierto |
| `StudioEmblem` | El logo del estudio en blanco (como la TV); sin logo, su nombre en cápsula | Para ti › Estudios |
| `CollectionIconEmblem` | El ícono blanco de una temporada o un género (Grok Imagine, `Assets.xcassets/Collections/<slug>`) con su nombre debajo, al pie de su `CollectionCard`; al abrir la lista, solo el ícono en grande sobre su color. Halo: `DS.Collections.season(slug)` (Halloween naranja, Día de Muertos rosa mexicano, Navidad verde, San Valentín guinda, Verano ámbar); los géneros, el neutro `DS.Collections.studio`. Datos: `Tmdb.seasons`/`Tmdb.genres` (los de la TV), `ForYou.seasonItems` y `ForYou.genreChart`. Demo: `-demo -demo-tmdb -demo-section seasons\|genres`, `-demo-collection genre:terror` | Para ti › Temporadas, Lo mejor del género |
| `GameNowCard`, `CompanionPanel`, `ConsoleStatePanel`, `GuidePanel`, `NotesPanel`, `TimerPanel`, `ControlsPanel` | Modo acompañante: el juego en la consola (volver, inicio, cerrar) y su carrusel (la consola, guía, notas, temporizador, controles de emulador) | Inicio, mientras juegas |
| `LaunchSplash` | La entrada de la app (arranque en frío): el anillo se dibuja sobre el planeta, las letras de «orbital» suben una tras otra y la luna cae; luego el logotipo vuela hasta el de Inicio (`AppMark` reporta dónde está) mientras Inicio aparece debajo. ~1.4 s, los mismos tiempos que la TV y la computadora (`DS.Splash`). Con «Reducir movimiento», un fundido; en modo demo, solo con `-demo-splash` | Arranque |
| `AppMark` | El logotipo como en la TV y la computadora (`OrbitalWordmark`: planeta, «orbital» y su luna) en lugar del saludo | Inicio |
| `CenteredCarousel`, `reflected()` | Tira centrada (la del medio al frente, las de los lados más chicas) y el reflejo que da peso | Para ti › Plataformas, Premios, Estudios, Temporadas, Lo mejor del género, Por año |
| `ConfirmIconButton` | Botón de ícono que se abre para confirmar («¿Ver en la TV?») | Inicio › carrusel |
| `CheckRow` | Renglón con ✓ para elegir varias (en qué listas va un título); todo el renglón se toca y mide al menos `DS.Size.touchTarget` | Ficha › Guardar en… |
| `CheckRowSkeleton` | El lugar de un `CheckRow` que todavía no llega: el mismo renglón en modo marcador (`redacted`), sin interacción y oculto a VoiceOver (la zona dice «Cargando tus listas de Trakt») | Ficha › Guardar en… |
| `SaveDestinationName` | El nombre de una lista fija con su servicio en gris («Tu watchlist (Trakt)», «Mi lista (Stremio)»), su símbolo y su tono | Menú de «Guardar» de la ficha, Guardar en… |
| `QualityBadges` | Insignias con contorno: 4K · DV · HDR10+ · ATMOS · TRUEHD | Fuentes (ficha y reproductor) |
| `RatingsRow`, `RatingMark` | IMDb · TMDB · Trakt con el logotipo de cada servicio en sus colores (guarda su alto: no brinca) | Ficha |
| `PersonPhoto`, `PersonFace` | La cara de alguien (o sus iniciales), con nombre y personaje | Ficha › Reparto y equipo, Persona |
| `VideoClipCard` | Tráiler o extra de YouTube con ▶ | Ficha |
| `BrandLogos`, `TmdbPoster` | Dónde verlo; un título de TMDB (saga, «Más como esto», filmografía) que abre su ficha | Ficha, Persona |
| `SourcesGlossary`, `SourceRowView` | Qué significa cada etiqueta de las fuentes (Al instante, DV, REMUX…); un renglón de fuente: tocarlo la pone, ▶ y ↓ a la derecha (la recomendada: «Ver» y «Descargar» del mismo tamaño abajo), «Ligera para guardar» en la que más conviene bajar, etiquetas que se deslizan | Fuentes (una sola lista, sin pestañas) |
| `WatchlistCard` | Un pendiente de tu watchlist: póster chico, año y género, nombre y sinopsis (dos renglones que se deslizan juntos) | Inicio › Tu watchlist |
| `posterReflection(_:title:width:)` | El reflejo de solo el póster (no de la tarjeta con su texto ni su zoom) | Inicio y Para ti › renglones |
| `ScareTimeline`, `ScarePanel`, `ScareWatcher`, `scareWarning(…)` | El mapa de sustos (Where's The Jump): la línea con cada susto (rojo los fuertes), el siguiente con su cuenta, «Avisarme» y la vibración unos segundos antes. En el reproductor los sustos son puntos sobre la misma `PlayerScrubBar` (como capítulos: rojo fuerte, ámbar leve, gris ya pasó); al arrastrar encima, `DSSeekBubble` lleva una nota con el susto; en el reproductor nada vibra (la vibración de «Avisarme» es solo del control de la TV); las dos primeras películas, un `Toast` dice qué son; Ajustes › Reproductor › «Marcar los sustos en la barra» los quita | Control (corto y estirado), reproductor |
| `VolumeControl`, `RemoteKey`, `TouchPad`, `VoiceCommandBar` | El control de la TV: todas sus piezas con el mismo relleno, esquinas y alto | Control |
| `ActivityPoster` | El póster en la actividad en vivo de las descargas (del App Group) | Pantalla bloqueada, Dynamic Island |
| `DownloadedFile` | Un archivo descargado para compartir (AirDrop, Archivos) con su nombre legible | Descargas › mantener |

### Recetas de pantalla

- `.titleDestinations()`: la pantalla abre fichas con el **zoom nativo** desde el póster (`.titleZoomSource(route)` en el póster).
- `.onArt()`: lo que va sobre el arte, como en la sala oscura.
- `.bottomAccessory(isEnabled:)`: el accesorio de la barra solo cuando hay algo (iOS 26.1+; en 26.0, la tarjeta en Inicio).
- `.tint(DS.accent)` en listas y formularios: lo interactivo (interruptores, botones de la lista) en el acento.

- Saltar a un grupo dentro de una lista perezosa (`LazyVStack`): cada grupo es **hijo directo** de la lista (sin caja que los junte) y su `.id` va **por fuera** de los demás modificadores; con `.scrollTargetLayout()` y `ScrollPosition.scrollTo(id:)`. Si no, el salto no encuentra un grupo que aún no se arma (Explorar › índice › «Temporadas» no bajaba, 2 nov 2026).

### Regla de íconos

- **Secciones**: sin ícono. El color lo pone el arte.
- **Renglones de ajustes** (Ajustes, «Ajustes del video»): símbolo del sistema (SF Symbols) solo en su color de `DS.ListTint`, sin fondo.
- **Botones y controles**: símbolo del sistema en blanco (o el color del texto), con su nombre cuando no es obvio.
- **Íconos propios de Orbital** (`OrbitalIcon`): solo como marca (la pestaña «Para ti»).

## 5. Movimiento con causa

| Qué | Cómo |
|---|---|
| Mosaico | Sube solo tras 3 s quieto (arranca suave, como la TV), cada columna a su ritmo (`DesignTokens.Mosaic.driftPattern`, el mismo de la TV); las columnas se igualan en ambiente; «cobra vida» acerca la pieza en 9 s |
| Póster → ficha | `navigationTransition(.zoom)` |
| Deslizar la ficha | El arte se recoge como en Apple TV (`BleedArt(collapse:)`, tokens `DS.TitleHero`, curvas en `OrbitalModels/HeroCollapse.swift` con pruebas): todo sale del progreso (cuánto subió el arte / su alto) con curvas suaves (smoothstep). El arte se queda un poco atrás (parallax 0.4), se encoge apenas (5 %), se oscurece hacia el color del fondo (`Backdrop.tone`: un velo parejo y un degradado que sube desde abajo), se difumina solo al final y se desvanece; el logo y la frase se van con el contenido y antes que el arte (ya no quedan detrás de los datos). Todo en `visualEffect`, sin volver a dibujar la imagen. Lo que sube se desvanece bajo la barra de arriba y el nombre aparece entre ‹ y los botones. Jalar hacia abajo estira el arte desde abajo. Siempre se puede recoger (el contenido mide al menos la pantalla). `-demo-scroll N` abre la ficha desplazada para capturarlo |
| Color del arte | Fundido de 0.7 s al cambiar lo que está al frente (las duraciones son las de la TV: 140 · 220 · 320 · 520 · 700 ms) |
| Empezar a ver | Toque háptico suave |
| Selección (carrusel, temporadas, Mi lista) | `sensoryFeedback(.selection)` |
| Tarjeta → reproductor | Zoom nativo desde la tarjeta de «Seguir viendo» o el arte de la ficha; al cerrar regresa a ella (`PlayerZoom.swift`) |
| El arte respira | La ficha y la portada se acercan 3 % en 16 s, un solo tramo (`BleedArt.breathes`, `DS.TitleHero.breathe*`); quieto con «Reducir movimiento», bajo consumo y `-demo-no-idle` |
| Póster con cuerpo | En la ficha, mantener y mover inclina el arte con un brillo (`tiltable()`). Sin hundido al tocar ni inclinación en la portada: en iOS 27 un estilo de botón propio, y en iOS 26 el gesto de la portada, le ganaban al deslizar las filas (HomePicksUITests) |
| Entradas | Las filas de Inicio y los estantes de Explorar entran escalonados la primera vez de la sesión (`entrance(_:order:)`) |
| Palomita de «Visto» | Se dibuja al marcar, con toque de «listo» (`WatchedMark`) |
| Calificar | Las estrellas se llenan en onda con un toque por estrella (`RatingStars`) |
| Tirar para actualizar | La luna de Orbital (`orbitalRefreshable` en la lista y `refreshOrbitHost()` en su contenido; nunca una capa alrededor de la lista: le quita a iOS esconder la barra de búsqueda) |
| Orilla de una fila | Golpe suave al empujar más allá del final (`edgeBump()`) |

Con «Reducir movimiento»: sin ambiente, sin acercamiento, sin fundidos; la ficha solo se oscurece y se desvanece (sin parallax, encogerse, difuminado, degradado que sube ni estirarse).

## 5b. Una sola experiencia con la TV

| Qué | Regla (la TV manda) |
|---|---|
| Color del arte | `ArtPalette` = `core/color.js` (tono dominante; tint L .20, accent L .76) |
| Botón principal | Con arte: el color claro del arte con texto oscuro. Sin arte: papel |
| Avance y foco | Papel (tinta en modo claro); teal solo «En vivo» |
| Episodio | «T2 E5» (el « · » separa datos) |
| Valores | `design/tokens.json`: paleta, papeles, espacios, radios, duraciones, opacidades y recetas. `tests/web/design-parity.test.mjs` (CI) lee `DesignTokens.swift` y falla si algo se separa; `DesignTests.testTokensMatchSharedJSON` hace lo mismo aquí |
| Nombres | `design/vocabulario.json`: «Ver», «Continuar», «Ver T3 E6», «Ver la serie», «Elegir fuente», «Mi lista» / «En Mi lista» (siempre con M), «Seguir viendo», «Ver en la TV», «termina a las 23:21». La misma prueba falla si una app dice otra cosa |
| Top 10 | La cifra grande detrás del póster en las dos (`RankedPosterCard` aquí, `RankedCard` en la TV) |
| Rótulo | `Eyebrow` sobre el título del destacado de Inicio en las dos («Seguir viendo», «Sigue») |
| Motivos | Los de `foryou.py` (campo `why`) tal cual (`SuggestionReason.console`) |
| A propósito distinto | El mosaico del teléfono (3 carriles parejos e información abajo; la TV: 6 columnas y la enfocada crece). Los estantes de Listas. La superficie (ink-850 aquí, ink-900 en la sala oscura). El vidrio: aquí solo en navegación (HIG); en la TV, píldoras sobre el arte. El modo claro (solo aquí) |

## 6. Textos en español e inglés

Todo texto de pantalla es su clave en español (`LocalizedStringKey`) y su traducción vive en `scripts/ios_strings.py`
(`python scripts/ios_strings.py --check` falla si falta una). Los textos armados (`Strings.endsAt`, `Strings.timeLeft`,
`Strings.episode`) usan el idioma de Ajustes, no el del sistema. Los errores y avisos que arma un modelo en español («No pude marcarlo: …»,
«La descarga falló (código 418).») se muestran con `env.message(…)` / `Strings.message`: reconoce la forma de su clave en el
catálogo y la vuelve a armar traducida, nunca `LocalizedStringKey(texto)` (un texto ya armado no encuentra su clave). Los géneros de Cinemeta se traducen con
`Vocabulary.genres` (la misma tabla que `format.js` de la TV).

## 7. Modo claro y oscuro

Ajustes › Apariencia: Como el iPhone · Claro · Oscuro (`AppSettings.appearance`). El reproductor y todo lo que va sobre el
arte siguen siendo sala oscura. Para capturas: `-demo-appearance light|dark`.

## 8. Qué vigilan las pruebas

- `DesignTests.testBothAppearancesHaveReadableContrast`: texto ≥ 7:1, secundario, acento y error ≥ 4.5:1, en los dos modos.
- `DesignTests.testScreensUseOnlyDesignSystemTokens`: sin colores, tamaños, duraciones, radios, espacios ni opacidades a
  mano; sin estilos de control propios; **sin `DS.font(…)`** (solo recetas) y **sin `Color.white/black`** en pantallas.
- `DesignTests.testPaletteMatchesOrbitalsPaletteJSON`: la paleta es la de la consola.
- `DesignTests.testTokensMatchSharedJSON` y, en CI, `tests/web/design-parity.test.mjs`: espacios, radios, duraciones,
  opacidades, papeles y recetas iguales a `design/tokens.json`; los textos de `design/vocabulario.json`.
- `scripts/ios_strings.py --check`: ningún texto sin traducir.
