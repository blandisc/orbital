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
| `display` / `title` | largeTitle / title, bold | Títulos grandes fuera de la barra |
| `section` | title2 bold | Encabezado de sección o estante |
| `cardTitle` | headline | Nombre en una pieza o renglón |
| `body` | body | Texto de lectura |
| `secondary` | subheadline | Datos de una ficha |
| `footnote` / `caption` | footnote / caption | Pies, nombres bajo un póster |
| `eyebrow` | footnote semibold | Rótulo sobre un título («Seguir viendo») |
| `data` | footnote, números tabulares | `DataLine`: «T2 E5 · quedan 20 min · termina a las 23:21» |

## 4. Piezas (catálogo)

`Design/Projection.swift` (Proyección) y `Design/Components.swift`, `Design/Shelf.swift`, `Design/Mosaic.swift` (base).

| Pieza | Qué es | Dónde |
|---|---|---|
| `Backdrop(tint:)` | Fondo con el color del arte | Todas las pantallas |
| `BleedArt` / `HeroCard` | Arte a sangre con rótulo, logo, `DataLine`, acciones y avance | Inicio (carrusel), Para ti › Listas, ficha |
| `DataLine` | Datos con números tabulares (no una monoespaciada); quita del final lo que no cabe | Destacados, ficha, descargas |
| `Eyebrow` | Rótulo pequeño (acento o sobre el arte) | Destacados |
| `HeroActions` | Las acciones de un destacado en un renglón; si no caben (letra grande, iPhone SE), apiladas | Inicio (carrusel), Para ti › Listas |
| `ActionTileLabel` | Acción de la ficha: rectángulo que llena su parte del renglón, ícono arriba y nombre abajo; activa con el color del arte; con anillo de avance alrededor del ícono (Descargar). Tocar hace lo principal, mantener presionado el resto (`Menu` con `primaryAction`) | Ficha (Guardar, Descargar, Tráiler, Fuente) |
| `Glyphs/donut` (catálogo de imágenes) | La dona de Los Simpson, con el trazo de los íconos propios (solo iPhone; los de `Icons/` vienen de la TV) | Inicio › un Simpson al azar (el dado es «¿Qué vemos?») |
| `DSKindFilter` | El filtro de tipo de toda la app: Todo · Películas · Series (o Películas · Series). Segmentado a lo ancho; `compact`, el switch chico junto al título (dos opciones, Top 10); `menu`, la lista que se despliega en cápsula (tres opciones junto al título: En tendencia, Destacado) | Inicio (destacado y Top 10), Para ti › Listas, plataforma, colección por año, Buscar (con cuántas), «¿Qué vemos?» |
| `DSCapsuleLabel` / `SeeAllLabel` | La cápsula tenue a la derecha del título de una sección, a la altura del título: «Ver todo ›», «📅 Octubre», «Todo ⌄» | Todo encabezado con «Ver todo», Sale hoy (calendario), los filtros desplegables |
| `CalendarDayCell` | Un día del calendario de estrenos, pintado con el color del arte de lo que sale; dos el mismo día, la casilla partida; más, «+N» | Sale hoy › el mes |
| `DSEmptyState` | Un área entera vacía: el vacío nativo con ícono, qué pasa y qué hacer. Regla: área vacía → esto; renglón vacío → texto chico; error → `DSNotice` | Descargas, Buscar, listas con filtros, Próximos estrenos, Inicio, «¿Qué vemos?», Tu año, Para ti |
| `DSMoreMenu` | «Más»: el mismo menú en toda la app, círculo con «…» (vidrio, sólido donde no se lleva) | Destacado de Para ti, «¿Qué vemos?», pie del mosaico, «Viendo en la TV» |
| `DownloadRing` | El anillo de avance de una descarga | Ficha (Descargar) y la fila de cada episodio |
| `StillCard` | Pieza 16:9 con avance, nombre y datos | Inicio › Todo lo que sigues |
| `PageDots` | Puntos de un carrusel | Inicio |
| `MovementBadge` | ▲ ▼ / Nuevo bajo un puesto | Rankings de plataformas (Buscar › Lo más popular usa `RankedPosterCard`) |
| `ArtTile` | Mosaico con arte y nombre | Buscar › Explora (géneros) |
| `DSOptionMenu` | Menú nativo para elegir entre muchas opciones | Temporadas (más de `DS.Size.seasonChipsMax`) |
| `TouchPad`, `RemoteKey`, `RemoteTextField` | El control completo de tu Orbital: pad (deslizar = flechas, tocar = A), teclas de la consola y escribir en la TV | `RemoteSheet` (la hoja del accesorio, estirada) |
| `VoiceCommandBar`, `VoiceChoices` | La voz del control: el micrófono con lo que oyó, la respuesta y lo que entendió; y, si tu Orbital no supo cuál, las opciones para tocar (`VoiceAssistant.choose`) | `RemoteSheet` |
| `VoiceGuideView` | «Lo que puedes decir»: dónde hablarle (control, Siri, Alexa), lo que solo hace el iPhone, las frases de la consola (alexa/commands.json) y qué hacer si no funciona | Ajustes › Voz y el «?» junto al micrófono del control |
| `OrbitalIcon` | Los íconos propios de Orbital, los mismos de la TV (icons.js → `node scripts/list_icons.mjs` → Assets.xcassets/Icons; tests/web/list-icons.test.mjs los mantiene iguales). En el iPhone solo como marca | La pestaña Para ti |
| `DeckCard`, `deckTransition`, `TimeStyle`, `ProgressFillLabel` | El carrusel de «Seguir viendo»: tarjetas con lo que sigue a los lados (coverflow o abanico, más chicas y desenfocadas) y cuánto falta (píldora de vidrio, borde, botón que se llena u órbita); lo elige el usuario en Ajustes › Inicio | `HomeView` |
| `AvatarImage`, `AvatarPicker` | Tu avatar (Assets › Avatars, 12 espaciales) y su selector | `HomeView` (junto al saludo), Ajustes › Inicio |
| Botón «Control de tu Orbital» (`av.remote`) | Sin nada en la TV, abre el control completo desde la barra de Inicio (el accesorio solo aparece mientras la TV reproduce, y no dentro de fichas ni Ajustes) | Inicio, con tu Orbital conectada |
| `fittedSheet()` / `subtitle(_:)` | Hoja a la medida de su contenido; subtítulo de la barra solo cuando dice algo | Hojas cortas; Inicio, Para ti, Descargas |
| `TVAccessory` | Lo que suena en tu Orbital, en el accesorio de la barra | Toda la app (iOS 26.1+) |
| `Shelf`, `RankedPosterCard`, `PosterCard`, `TitleLink`, `Rail` | Estantes, Top 10, pósters | Para ti, Inicio, Buscar |
| `Mosaic` | El mosaico que sube despacio (como `foryou-mosaic.js` de la TV) | Para ti |
| `DSSegmented`, `DSChipRow`, `DSIconButton`, `DSNotice`, `DSProgress` | Controles nativos con los tokens de Orbital | Varias |
| `DSSectionHead` | El encabezado de toda sección («Editorial»): título grande, «Ver todo» si abre la lista completa (o un dato corto) y una línea gris solo si ayuda; sin íconos | Todas las pantallas (también `Shelf` y las listas de Descargas) |
| `CoverCard`, `WideCard` | La portada de una sección (lo más importante en grande, con su porqué en ámbar) y la pieza panorámica con su dato en la esquina | Inicio › Sale hoy / Sale pronto |
| `posterCaptions` (entorno) | El nombre bajo el póster: sí en cuadrículas, no en las tiras de una sección | Tiras y cuadrículas |
| `ProfileButton` | Tu avatar arriba a la derecha de cada pestaña: abre Ajustes | Inicio, Para ti, Buscar, Descargas |
| `StorageBar` | El espacio del iPhone: series, películas, otras apps y libre (ámbar con poco espacio) | Descargas |
| `SettingsRow`, `ProfileCard` | Renglón de Ajustes con su ícono de color y su valor actual; tu perfil arriba (el avatar con lápiz) | Ajustes |
| `StyleOption`, `DeckStylePreview`, `TimeStylePreview` | Elegir un estilo viéndolo: el carrusel que se mueve solo y cuánto falta sobre una tarjeta | Ajustes › Inicio |
| `PlayerLabelButton` | Botón del reproductor con su nombre («En la TV», «Ventana», «Audio y subtítulos»); si no cabe, solo el ícono | Reproductor |
| `PlatformPill` | Una plataforma en cápsula (logo chico y nombre); la elegida con su color tenue y su borde | Inicio › Top 10 (elegir de qué servicio) |
| `PanelRow`, `PanelIcon`, `PanelChip`, `PanelGroupTitle`, `FlowChips`, `SpeedStepper` | El panel «Ajustes del video»: renglones con su valor (ícono del sistema solo en su color, como Ajustes), opciones en cápsula (con glifo opcional) y la velocidad − 1× + | Reproductor, «Decide por mí» (a la derecha en horizontal, hoja ajustada en vertical) |
| `Toast` | El único aviso pasajero: arriba, en vidrio, glifo de color, texto y su acción («Pasó a tu Orbital · Deshacer», «Descargando… · Ver»); las notas fijas de una pantalla siguen siendo `DSNotice` | Toda la app |
| `FanCard`, `CollectionCard`, `AwardCard`, `AwardEmblem` | La tarjeta en abanico (plataformas y colecciones) con su emblema al frente; un premio con su estatuilla real | Para ti › Listas |
| `ListCard`, `SourceBadge` | Una lista tuya (pila de pósters, nombre, sello y cuántos) y el sello de origen (Trakt, Stremio, Orbital) junto a un título | Para ti › Listas |
| `BecauseCard` | «Porque viste X»: el póster de lo que viste y lo relacionado al lado | Para ti › Listas |
| `YearCard` | Un año con cuatro de sus películas y el número grande | Para ti › Por año |
| `SortableGrid` | Una lista abierta con ordenar y filtrar (series o películas, género, calificación, década, ocultar lo visto) arriba a la derecha; con su vacío, su carga al centro y, si la pantalla ya trae `DSKindFilter`, sin repetirlo (`showsKindFilter`) | Listas, premios, años, géneros, «Ver todo» |
| `DSPosterGrid` | La cuadrícula de pósters de toda la app: columnas fijas que llenan el ancho (`DS.Poster.gridColumns` 3; 4 en pantallas anchas; 2 con letra de accesibilidad), separación `DS.Space.s3`, bordes en el margen; cada celda recibe el ancho de su columna | `SortableGrid`, Buscar (resultados), Persona (filmografía), Top 10 abierto |
| `StudioEmblem` | El logo del estudio en blanco (como la TV); sin logo, su nombre en cápsula | Para ti › Estudios |
| `GameNowCard`, `CompanionPanel`, `ConsoleStatePanel`, `GuidePanel`, `NotesPanel`, `TimerPanel`, `ControlsPanel` | Modo acompañante: el juego en la consola (volver, inicio, cerrar) y su carrusel (la consola, guía, notas, temporizador, controles de emulador) | Inicio, mientras juegas |
| `AppMark` | El logotipo como en la TV y la computadora (`OrbitalWordmark`: planeta, «orbital» y su luna) en lugar del saludo | Inicio |
| `CenteredCarousel`, `reflected()` | Tira centrada (la del medio al frente, las de los lados más chicas) y el reflejo que da peso | Para ti › Plataformas, Premios, Estudios, Por año |
| `ConfirmIconButton` | Botón de ícono que se abre para confirmar («¿Ver en la TV?») | Inicio › carrusel |
| `CheckRow` | Renglón con ✓ para elegir varias (en qué listas va un título) | Ficha › Guardar en… |
| `QualityBadges` | Insignias con contorno: 4K · DV · HDR10+ · ATMOS · TRUEHD | Fuentes (ficha y reproductor) |
| `RatingsRow`, `RatingMark` | IMDb · TMDB · Trakt con el logotipo de cada servicio en sus colores (guarda su alto: no brinca) | Ficha |
| `PersonPhoto`, `PersonFace` | La cara de alguien (o sus iniciales), con nombre y personaje | Ficha › Reparto y equipo, Persona |
| `VideoClipCard` | Tráiler o extra de YouTube con ▶ | Ficha |
| `BrandLogos`, `TmdbPoster` | Dónde verlo; un título de TMDB (saga, «Más como esto», filmografía) que abre su ficha | Ficha, Persona |
| `SourcesGlossary`, `SourceRowView` | Qué significa cada etiqueta de las fuentes (Al instante, DV, REMUX…); un renglón de fuente que se toca y cuyas etiquetas se deslizan | Fuentes |
| `WatchlistCard` | Un pendiente de tu watchlist: póster chico, año y género, nombre y sinopsis (dos renglones que se deslizan juntos) | Inicio › Tu watchlist |
| `posterReflection(_:title:width:)` | El reflejo de solo el póster (no de la tarjeta con su texto ni su zoom) | Inicio y Para ti › renglones |
| `ScareTimeline`, `ScareMarks`, `ScarePanel`, `ScareWatcher`, `scareWarning(…)` | El mapa de sustos (Where's The Jump): la línea con cada susto (rojo los fuertes), el siguiente con su cuenta, «Avisarme» y la vibración unos segundos antes | Control (corto y estirado), reproductor |
| `VolumeControl`, `RemoteKey`, `TouchPad`, `VoiceCommandBar` | El control de la TV: todas sus piezas con el mismo relleno, esquinas y alto | Control |
| `GameSessionSummary` | Al cerrar un juego: cuánto jugaste esta vez y en total, capturas y si se cerró solo | Hoja al terminar |
| `ActivityPoster` | El póster en la actividad en vivo de las descargas (del App Group) | Pantalla bloqueada, Dynamic Island |
| `DownloadedFile` | Un archivo descargado para compartir (AirDrop, Archivos) con su nombre legible | Descargas › mantener |

### Recetas de pantalla

- `.titleDestinations()`: la pantalla abre fichas con el **zoom nativo** desde el póster (`.titleZoomSource(route)` en el póster).
- `.onArt()`: lo que va sobre el arte, como en la sala oscura.
- `.bottomAccessory(isEnabled:)`: el accesorio de la barra solo cuando hay algo (iOS 26.1+; en 26.0, la tarjeta en Inicio).
- `.tint(DS.accent)` en listas y formularios: lo interactivo (interruptores, botones de la lista) en el acento.

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
| Color del arte | Fundido de 0.7 s al cambiar lo que está al frente (las duraciones son las de la TV: 140 · 220 · 320 · 520 · 700 ms) |
| Empezar a ver | Toque háptico suave |
| Selección (carrusel, temporadas, Mi lista) | `sensoryFeedback(.selection)` |

Con «Reducir movimiento»: sin ambiente, sin acercamiento, sin fundidos.

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
