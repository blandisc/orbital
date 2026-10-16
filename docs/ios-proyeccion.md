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
| surface | `surface` | ink-850 | #ffffff | Renglones de listas y formularios |
| surfaceRaised | `surfaceRaised` | ink-800 | #ebe9e3 | Placeholders |
| label / secondaryLabel / tertiaryLabel | `text` / `textMuted` / `textFaint` | paper / ink-300 / ink-500 | #111113 / #5c5c64 / #9a9aa1 | Texto (el terciario solo adornos) |
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
- Cambia en `DS.Motion.tint` (0.6 s); con «Reducir movimiento», sin animación.

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
| `DataLine` | Datos en SF Mono; quita del final lo que no cabe | Destacados, ficha, descargas |
| `Eyebrow` | Rótulo pequeño (acento o sobre el arte) | Destacados |
| `ActionGrid` + `ProjectionAction` | Acciones secundarias iguales con ícono y nombre (se apilan con letra grande) | Ficha (Mi lista, Descargar, Fuentes) |
| `StillCard` | Pieza 16:9 con avance, nombre y datos | «También tenías» |
| `PageDots` | Puntos de un carrusel | Inicio |
| `RankedRow` + `MovementBadge` | Renglón con puesto, póster chico y ▲ ▼ / Nuevo | Buscar › Lo más popular (y la Cartelera) |
| `ArtTile` | Mosaico con arte y nombre | Buscar › Explora (géneros) |
| `DSOptionMenu` | Menú nativo para elegir entre muchas opciones | Temporadas (más de `DS.Size.seasonChipsMax`) |
| `TVAccessory` | Lo que suena en tu Orbital, en el accesorio de la barra | Toda la app (iOS 26.1+) |
| `Shelf`, `RankedPosterCard`, `PosterCard`, `TitleLink`, `Rail` | Estantes, Top 10, pósters | Para ti, Inicio, Buscar |
| `Mosaic` | El mosaico que sube despacio (como `foryou-mosaic.js` de la TV) | Para ti |
| `DSSegmented`, `DSChipRow`, `DSIconButton`, `DSNotice`, `DSProgress` | Controles nativos con los tokens de Orbital | Varias |

### Recetas de pantalla

- `.titleDestinations()`: la pantalla abre fichas con el **zoom nativo** desde el póster (`.titleZoomSource(route)` en el póster).
- `.onArt()`: lo que va sobre el arte, como en la sala oscura.
- `.bottomAccessory(isEnabled:)`: el accesorio de la barra solo cuando hay algo (iOS 26.1+; en 26.0, la tarjeta en Inicio).
- `.tint(DS.accent)` en listas y formularios: lo interactivo (interruptores, botones de la lista) en el acento.

## 5. Movimiento con causa

| Qué | Cómo |
|---|---|
| Mosaico | Sube solo tras 30 s quieto, cada columna a su ritmo (`DesignTokens.Mosaic.driftPattern`, el mismo de la TV); las columnas se igualan en ambiente; «cobra vida» acerca la pieza en 9 s |
| Póster → ficha | `navigationTransition(.zoom)` |
| Color del arte | Fundido de 0.6 s al cambiar lo que está al frente |
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
| Nombres | «Ver», «Continuar», «Ver T3 E6», «Ver la serie» (una serie sugerida abre su ficha), «Elegir fuente», «Mi lista» / «En mi lista», «Ver en la TV», «termina a las 23:21» |
| Motivos | Los de `foryou.py` (campo `why`) tal cual (`SuggestionReason.console`) |
| A propósito distinto | El mosaico del teléfono (3 carriles parejos e información abajo; la TV: 6 columnas y la enfocada crece). Los estantes con Top 10 de Listas |

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
- `scripts/ios_strings.py --check`: ningún texto sin traducir.
