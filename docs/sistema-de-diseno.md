# Sistema de diseño de Orbital

**Regla de oro: nada se crea suelto.** Una pantalla nueva se arma con las piezas de este documento. Si
falta una pieza, se agrega al sistema (aquí y en `js/components/` + `styles/components/`), no dentro de
la pantalla. Así un chip, una tecla o un foco se ven igual en todas partes.

Esto no depende de la buena memoria: **`tests/web/design-system.test.mjs` lo verifica** en cada corrida
de pruebas (`node --test tests/web/*.test.mjs`) y falla si:

1. el CSS de un componente escribe a mano un **color**, una **duración**, una **capa** (`z-index`), un
   **tamaño de letra**, **mayúsculas espaciadas**, una **opacidad** de estado (fuera de `@keyframes`), un **radio** o el
   **borde fino** (`inset 0 0 0 1px` del hairline) (todo eso son tokens);
2. se usa un **token que no existe**;
3. hay un **componente** (`js/components/*.js` o `styles/components/*.css`) que **no está en el catálogo**
   de abajo;
4. queda **CSS muerto** (una clase que ningún JavaScript usa);
5. un JavaScript **pinta un color fijo**.

La única salida es una **excepción documentada**: la línea lleva `/* ds-exception: <motivo> */` (o
`// ds-exception: <motivo>` en JS) y ese mismo motivo aparece en la sección [Excepciones](#7-excepciones).

---

## 0. Lenguaje de la TV (Apple TV, 31 oct 2026)

Fernando eligió (página «Inicio y Juegos al estilo Apple TV», tres vueltas): **Inicio B «A continuación»**, **Juegos «pulido»
en dos pisos**, el foco que se levanta, la barra y los botones de vidrio con íconos, «Jugar» en blanco, el nombre solo bajo lo
enfocado y **la luz de atrás que cambia con lo que enfocas**. Este lenguaje vale para **todas** las pantallas de la TV y para el
reproductor: una pantalla nueva o tocada se arma con estas recetas, y `tests/web/design-system.test.mjs` revisa las que se
pueden medir (marcadas «prueba»).

### Recetas

| Receta | Cómo se escribe | Dónde | Prueba |
|---|---|---|---|
| **Vidrio** (riguroso, 1 nov 2026) | Tres papeles. **Control** (lo que se toca o se enfoca: botones secundarios y redondos, teclas, campos, versiones, cápsulas, chips, íconos en su casilla): `background: var(--color-glass)` y su filo, `--edge-glass` si flota sobre el arte o `--edge-glass-hairline` dentro de una fila o un panel; al señalar, `--color-glass-hover`; lo elegido dentro de un grupo, `--color-glass-selected` con `--edge-glass-selected`. **Lo que flota encima de todo** (menús, hojas, paneles, avisos): `--color-glass-strong`, `--edge-glass`, `--shadow-overlay` y `backdrop-filter: var(--filter-glass)`. **Contenido** (portadas, fotos, tarjetas) y esqueletos de carga: no son vidrio. Los glifos del mando y las teclas, de cristal (`--glyph-bg`, `--edge-glyph`); sobre lo blanco, sólidos (`--glyph-bg-solid`). El principal, siempre en blanco. El desenfoque solo en lo que flota directo sobre el arte (Orbital ligera: las teclas no desenfocan cada una) | Barra y Buscar, selector de consolas, botones, teclas, Ajustes, menús, avisos, la batería | sí: `--color-fill` solo en esqueletos; todo `--shadow-overlay` con `--color-glass-strong`; todo control de vidrio con su filo; ningún `backdrop-filter` fuera de `--filter-glass` |
| **Principal en blanco** | `Button({ variant: "primary" })` → `--color-primary` con `--color-on-primary`; nunca el color del arte | «Jugar», «Continuar», «Ver», «Ver la serie», «Reintentar»; en el reproductor, el primer botón de `buttons()` | sí |
| **Cápsula** | `border-radius: var(--radius-pill)` en todo botón, píldora y selector | Botones, pestañas, filtros, `GlassSwitch`, `Segmented` | — |
| **El foco se levanta** | Crece (`--card-focus-scale`, `--tile-focus-scale`, `--inverse-scale`) y flota con `--focus-lift`; a una portada le cruza `--focus-shine` (en su `::after`). Sin anillo | Portadas, tarjetas, tiles, consolas, caras del reparto, casillas del calendario y de Tu año | sí: nadie usa `--color-focus` fuera de `:focus-visible` |
| **Foco invertido** (lo que no es arte) | `--inverse-bg` / `--inverse-fg` y crece `--inverse-scale` | Opciones de un menú, filas de Ajustes, teclas, filtros, la consola enfocada del selector, Buscar y Alexa | — |
| **Nombre solo bajo lo enfocado** | `Card(item, { caption: "focus" })` | Los juegos de Juegos, «A continuación» | — |
| **Porqué en turquesa** | `--color-reason` con la receta `eyebrow`, arriba del logo o título; solo porqués | El juego de Juegos («Lo jugaste hace 3 h · 48 h»), el destacado del Inicio, el héroe de Películas y series, las filas | — |
| **Destacado sobre el arte** | El arte a pantalla lo pone el fondo (`backdrop`); encima, abajo a la izquierda: porqué, logo (o título `display`), una línea de datos, avance y botones (`FeatureHero`) | Inicio, Juegos, Películas y series, la ficha | — |
| **Dos pisos** | Arriba la barra de secciones; debajo, el selector de la sección (`GlassSwitch`). Al bajar de la primera fila, las dos barras y el destacado se van (`body[data-chrome="away"]`) | Juegos (consolas) | — |
| **La luz de atrás** | `backdrop.show(arte)` toma el tono (`--art-tint`, `--art-accent`) y `backdrop.light(x, y)` acerca la luz a lo enfocado; cambia en `--duration-tint` y se queda quieta (Orbital no gasta) | Inicio, Juegos, Explorar, TV en vivo; con arte a pantalla en Inicio, Juegos y Películas y series | — |
| **Menú flotante** | `side-panel`: vidrio fuerte, separado de las orillas y con esquinas `--radius-2xl`; del alto de lo que trae | Opciones, ☰, panel rápido, confirmaciones; abajo, «Elegir versión» | — |

### Escala de texto (recetas `--type-*`)

A 1080p, 1 rem ≈ 21,6 px (`--root-size`); «Tamaño del texto» multiplica todo por `--text-scale`.

| Receta | Tamaño | ≈ px a 1080p | Peso | Para |
|---|---|---|---|---|
| `hero` | `--text-display` 3,7 rem | 80 | negrita | El título del héroe de Películas y series sin logo |
| `display` | `--text-3xl` 2,9 rem | 63 | negrita | El título de un destacado sin logo (Inicio, Juegos), el de una pantalla (Ajustes) |
| `title` | `--text-2xl` 2,4 rem | 52 | negrita | Un título largo que baja un paso, una pregunta grande |
| `heading` | `--text-xl` 1,55 rem | 33 | negrita | El encabezado de una zona o de una hoja |
| `section` | `--text-lg` 1,2 rem | 26 | negrita | El título de una fila («A continuación», «Tus 13 juegos») |
| `card-title` · `body` | `--text-md` 1,07 rem | 23 | medium · regular | El nombre en una opción o renglón · el cuerpo |
| `secondary` · `eyebrow` | `--text-sm` 0,98 rem | 21 | regular · medium | Datos bajo un título · el porqué |
| `footnote` · `data` | `--text-xs` 0,9 rem | 19 | regular | Notas · números (tabulares) |
| `caption` | `--text-2xs` 0,86 rem | 18,6 | medium | El nombre bajo lo enfocado, rótulos chicos, glifos |

Nada baja de `caption` (se lee a 3 m). Un componente usa la receta, nunca `--text-*` (prueba).

### Colores por papel (`themes/orbital.css`)

| Papel | Token | Regla |
|---|---|---|
| Fondo | `--color-bg`, `--color-tinted-bg` (el tono del arte) | Grafito; el color lo pone lo enfocado |
| Superficie | `--color-surface`, `--color-surface-raised` | Paneles de una pantalla completa (Ajustes, el calendario); sobre el arte, vidrio |
| Vidrio | `--color-glass`, `--color-glass-hover`, `--color-glass-selected`, `--color-glass-strong`, `--edge-glass`, `--edge-glass-hairline`, `--edge-glass-selected` | Ver la receta |
| Texto | `--color-text`, `--color-text-muted`, `--color-text-faint`, `--color-on-art-secondary` | El tenue (50 %) se lee (≥ 4,5:1); sobre el arte, `on-art-secondary` con su sombra |
| Principal | `--color-primary` / `--color-on-primary` | Blanco con letra negra; también el foco invertido |
| Porqué | `--color-reason` | Turquesa; solo porqués |
| Lo de Orbital | `--color-orbital` (la luna) | El ícono de un rótulo de sección |
| En vivo · bien | `--color-live`, `--color-ok` | Turquesa |
| Aviso · peligro | `--color-warning`, `--color-danger` | Ámbar · rojo |
| Nuevo | `--color-new` | El listón «Nuevo», «Hoy» |
| Acento por categoría | `--rainbow-*` | El arcoíris del azul de Orbital: categorías de TV en vivo (filtros, después) |
| Marcas | `--platform-*`, `--brand-*`, `--system-*`, `--color-source-*` | El color de cada plataforma, consola o fuente; nunca para la interfaz |

### Espacios

| Qué | Token | Valor |
|---|---|---|
| La escala | `--space-1` … `--space-14` | 4 px a 16 px/rem: .25, .5, .75, 1, 1,25, 1,5, 2, 2,5, 3,5 rem |
| A los lados de la pantalla | `--page-gutter` | El margen de la TV (`--safe-x`, Ajustes › Márgenes de la TV), nunca menos de `--space-4` |
| Lo que ocupa la barra de arriba | `--status-room` | `--space-5` + `--safe-y` + `--control-height` |
| Del título a lo suyo | `--layout-title-to-content` | `--space-3` (el mismo 12 del iPhone) |
| Entre filas del Inicio y de Juegos | `--space-5` (`.home__scroll`) | Cada fila mide un alto fijo y la siguiente asoma |
| Entre tarjetas de una fila | `--card-gap`, `--tile-gap`, `--space-6` (tarjetas anchas) | — |
| Dentro de una tarjeta | `--inset-poster` · `--inset-row` · `--inset-card` · `--inset-feature` | Un margen por tarjeta, igual en los cuatro lados (§ 3) |
| Entre botones de una fila | `--space-3` (`.button-row`) | Nunca se parte ni se corta |
| Alturas | `--control-height` (botón), `--pill-height` (píldora), `--menu-row-height` (opción), `--touch-target` (el dedo) | — |

### Piezas del lenguaje

| Pieza | Archivo | Para qué |
|---|---|---|
| `GlassSwitch(items, { label, onPick })` | `ui` | El selector de vidrio del segundo piso (las consolas de Juegos): cada opción con su foto y su nombre; la elegida en blanco tenue, la enfocada invertida; si no caben, las demás quedan en su foto (`glass-switch--compact`). |
| `FeatureHero(item, { runningId, glyphs, onAction, reason })` | `tiles` | El destacado sobre el arte del Inicio: porqué, logo o título, de dónde es y su dato, avance y botones. |
| `Card(item, { caption: "focus" })` | `card` | La portada que solo dice su nombre cuando está enfocada. |
| `Button({ variant: "primary" })` · `Button({ icon })` | `button` | El principal en blanco · el secundario redondo de vidrio con su nombre debajo. |

### Revisión por pantalla

Cada pantalla de la TV, con su estado en el lenguaje. «Por las piezas» quiere decir que el cambio le llegó por lo compartido
(botones, foco, menús, vidrio) sin tocar su acomodo.

| Pantalla | Estado |
|---|---|
| Barra de arriba | Vidrio con íconos; la sección elegida, en blanco con su nombre; se va al bajar en Juegos |
| Inicio | Rediseñado: «A continuación» (B) |
| Juegos | Rediseñado: dos pisos y el juego a pantalla (A); la página de cada juego (C) en Opciones › «Ver ficha» (A sigue jugando directo) |
| Películas y series | Por las piezas: héroe con «Ver» en blanco y secundarios de vidrio, portadas que se levantan |
| La ficha | Por las piezas: «Ver» en blanco, acciones de vidrio, episodios que se levantan |
| Explorar | Por las piezas: el mosaico se levanta sin anillo; sus marcas, de vidrio |
| TV en vivo | Por las piezas: canales que se levantan |
| Buscar · Conectar Stremio | Por las piezas: teclas con foco invertido, resultados que se levantan |
| Menús, panel rápido, Opciones, confirmaciones | Menú flotante de vidrio |
| Elegir versión | Menú flotante de vidrio, abajo |
| Ajustes | Por las piezas: filas con foco invertido, `Segmented` en cápsula |
| Calendario · ¿Qué vemos? · listas | Por las piezas: casillas y pósters que se levantan |
| Cambiar el arte | Por las piezas: casillas que se levantan |
| Pantalla de carga · arranque · avisos | Sin cambio (ya eran del lenguaje) |
| Reproductor (`player_ui.py`) | Botones en cápsula: el primero en blanco, los demás de vidrio (`GLASS_ALPHA`, `GLASS_EDGE_ALPHA`); píldoras táctiles de vidrio |

## 1. Tokens (`orbital/web/styles/`)

| Capa | Archivo | Qué hay |
|---|---|---|
| Paleta | `palette.json` + `tokens.css` (`--palette-*`) | Los colores crudos. **Una sola paleta** para la interfaz y el reproductor (`player_ui.py` la lee del JSON). Una prueba verifica que coinciden. |
| Primitivos | `tokens.css` | Espacio (`--space-*`), radios (`--radius-*`, desde `--radius-2xs` para lo diminuto: el cursor, la batería, las casillas del calendario), letra (`--text-*`, `--weight-*`, `--tracking-*`, interlineado `--leading-*`), opacidad por lo que significa (`--opacity-*`: `off`, `away`, `near`, `faint`, `text`, y `solid` casi entero, `soft` lo que acompaña sin mandar, `dim` lo lejano, `grain` el grano del fondo), vidrio (`--blur-glass`), movimiento (`--duration-*`, `--ease-*`, `--delay-*`, `--stagger`), capas (`--z-*`), medidas de consola (`--card-*`, `--tile-*` —también `--tile-channel-width`, el canal de TV en vivo—, `--key-height`, `--sheet-width`, y las alturas de control `--pill-height`, `--control-height`, `--control-sm`, `--menu-row-height` y `--touch-target`; íconos `--icon-*` y trazo `--stroke-*`…). |
| Semánticos | `themes/orbital.css` | Lo que usan los componentes: `--color-*`, el borde fino por dentro (`--edge-hairline`, `--edge-strong`), `--shadow-*` (cajas) y `--shadow-drop*` (siluetas), el foco (`--focus-lift`, `--focus-shine`), el vidrio (`--color-glass*`, `--edge-glass`, `--filter-glass`), foco invertido (`--inverse-bg/fg/scale`), sobre el arte (`--color-badge-bg`, `--gradient-tile-shade`), dentro de algo claro (`--on-light-*`) o de color (`--on-color-fill`), máscaras (`--mask-solid`), fondo de ambiente (`--color-backdrop-deep`), sombra sobre el arte (`--color-art-shade`), relieves (`--gradient-console-tile`, `--gradient-launch-planet`), `--color-star`, `--color-video-bg`, `--assistant-accent`, el grafito neutro del arte (`--art-*-neutral`) y el color de cada consola (`--system-*`). |

**Compartido con el iPhone: `design/tokens.json`** (paleta, papeles, espacios, radios, duraciones, opacidades, recetas de
texto) y **`design/vocabulario.json`** (lo que las dos apps dicen igual: «Mi lista», «Ver la serie», «Seguir viendo»…).
`tests/web/design-parity.test.mjs` compara `tokens.css`, `themes/orbital.css` y el código Swift del iPhone contra esos dos
archivos: cambiar un valor o un texto en un solo lado falla CI. Las diferencias a propósito (la superficie, ink-900 aquí
e ink-850 en el iPhone) van en el JSON con su `porque`.

**Recetas de texto** (`--type-*`, los nombres del iPhone): `display` (3xl, negrita), `title` (2xl, negrita), `section`
(lg, negrita), `card-title` (md, medium), `body` (md), `secondary` (sm), `footnote` (xs), `caption` (2xs), `eyebrow` (sm,
medium) y `data` (xs, números tabulares); solo en la TV, `heading` (xl: un encabezado de zona) y `hero` (el título del héroe). **Un componente usa la receta, nunca el tamaño de la escala** (`--text-*` es del CSS de tokens; la prueba lo vigila).

**Jerarquía de encabezados (iPhone, 30 oct 2026; regla A del 31 oct):** dos niveles y nada más, una sola pieza (`DSSectionHead`).
Una sección es el **rótulo**: ícono en el azul de Orbital, el nombre en mayúsculas chicas y una línea fina hasta la orilla
(`DSChapterLabel`, el mismo de `DSChapterHead`). Lo de adentro son subsecciones con título blanco.

| Nivel | Receta | Lleva | Ejemplos |
|---|---|---|---|
| Pantalla | barra nativa / `display` | — | «Para ti», «Buscar» |
| Sección (`level: .section`) | rótulo (`caption` en mayúsculas) + ícono (`symbol:`) + línea | solo el rótulo (y a la derecha un dato o «Ver todo») | Plataformas, Premios, Temporadas, Día por día, Descargando |
| Subsección (por omisión) | `section` | título blanco; su porqué arriba en `eyebrow` turquesa solo si ayuda | En tendencia, Seguir viendo, Próximas temporadas, Tus 5 estrellas |

**Espacios (iPhone, decisión 2 del 31 oct 2026):** cuatro medidas, en `DS.Layout`, medidas desde donde termina lo que se ve
(el pie de un póster y lo visible de su reflejo cuentan): del título a lo suyo **12** (`titleToContent`), entre
subsecciones **24** (`betweenSubsections`), entre secciones **40** (`betweenSections`, también `DS.Editorial.sectionGap`) y
al pie de la pantalla **56** (`screenBottom`). Arriba de cada pantalla, 12 (`screenTop`).
| Pieza | `card-title` | — | el nombre en una tarjeta o renglón |
| Cuerpo · secundario · pie · etiqueta · dato | `body` · `secondary` · `footnote` · `caption` · `data` | — | lo que explica, datos, notas, placas, números |

Una sección agrupa varias cosas; una subsección es una fila o un estante (las filas del Inicio, los estantes de «Ahora», las
filas de la ficha). Lo que explica una sección va en el cuerpo, debajo, nunca como subtítulo. `DesignTests`
(`testSectionsHaveNoReasonAndSubsectionsAlwaysDo`) revisa las dos reglas.

### Lenguaje de diseño del iPhone (una pieza por papel)

Si hay dos maneras de hacer lo mismo, una sobra. Antes de armar algo en una pantalla se busca su pieza aquí; si no existe, se
agrega al catálogo (`ios/App/Sources/Design/`) y a esta tabla. `DesignTests` revisa las que dicen «prueba».

| Papel | La pieza | Regla | Prueba |
|---|---|---|---|
| Encabezado | `DSSectionHead(level:)` | Sección = rótulo con ícono y línea; subsección = título blanco (ver arriba). | sí |
| Arranque de una parte grande | `DSChapterHead(label:title:)` | Las partes de Para ti (HOY, PLATAFORMAS, ESTUDIOS, TEMPORADAS, GÉNEROS, PREMIOS, AÑOS): rótulo chico en mayúsculas gris con su línea fina hasta la orilla y un título blanco que dice algo («Del terror a la comedia»). Sin colores ni íconos de app: el aire y la línea separan. | — |
| Renglón de lista | `sheet__item`, `showcase__item`, `filter__row` | Igual | Las opciones de un menú, una colección con cuánto llevas, una fila del filtro: ícono, nombre y su dato, con el foco invertido. |
| Porqué | `Eyebrow(reason: true)` · `DS.eyebrow` | Siempre turquesa, arriba de su título; solo para porqués: un dato (el periodo «Este mes», lo elegido en un filtro) no va en turquesa. Las excepciones dicen por qué (`ds-exception:`): los rótulos de historia del Wrapped (ámbar), la ruleta de Los Simpson (su amarillo), «En la tele» sobre el arte. | sí |
| Botón principal | `Button({ variant: "primary" })` | Igual | Siempre blanco con letra negra (rediseño estilo Apple TV, § 0): el color lo pone la luz de atrás. |
| Botón secundario | `Button` (vidrio) | Distinto a propósito: de vidrio y en cápsula, sin borde; con el mando el foco lo invierte y un borde fino no se ve a tres metros | — |
| Botón de ícono | `.dsIconButtonLook()` · `DSIconButton` | Vidrio en círculo; sólido donde el vidrio no se lleva bien. | — |
| Selector | por categoría: `DSTextTabs` · `DSKindFilter` · `DSSegmented` · `PanelChip` · `FilterChoice` | Según lo que hace (Fernando, 31 oct 2026): **cambiar lo que ves** → pestañas de texto (`DSTextTabs`, con ícono si ayuda; Todo · Películas · Series es `DSKindFilter`): Para ti, Buscar, listas, Decide por mí, los periodos de «Lo que ves», Descargas, Mi media y el reproductor. Excepciones decididas: Inicio con la rayita turquesa (`mark: DS.eyebrow`) y el Top 10 con su pastilla junto al título (`DSKindFilter(compact:)`, con ícono). **Ajustar un valor** → el segmentado de iOS (`DSSegmented`): Modo, energía, Quiero · Quitar, Solo este episodio · Desde aquí. **Elegir varios** → cápsulas (`PanelChip`; elegida, en el color del texto). **Elegir uno grande** → mosaicos (`FilterChoice`). Lo elegido, en blanco; nunca turquesa. | sí |
| Búsqueda avanzada | `filter-panel` | Distinto a propósito: en filas con ‹ › (se maneja con el mando), sin premios ni estudios (viven en Películas y series y en Colecciones) | ☰ › Filtro avanzado; cada filtro con su color del arcoíris solo en su ícono; los resultados en `list-screen`. |
| Marcar como vista | «¿Cuándo la viste?» (`yours-commands.js` · `watchedMenu`) | Distinto a propósito: «Otro día…» ofrece días comunes (ayer, hace una semana…) en lugar del calendario | En la ficha y en Opciones, con Trakt; la serie entera dice «Cuando salió cada episodio». |
| Vacío | `DSEmptyState` | Ícono, título y una línea; sus botones, de vidrio. | sí |
| Tarjeta | `DS.surface` · `DS.Radius.lg` | Las tarjetas y renglones van en `surface` con `Radius.lg`; las destacadas (una por pantalla: «¿Qué vemos hoy?», «La temporada», «Por lo que viste») en `Radius.xl`. Los rellenos dentro de una tarjeta, `DS.fill`. | — |
| Hoja con encabezado propio | `dsSheetContent()` · `DS.Space.sheetTop` | Toda hoja sin barra de navegación (calendario, «Tu Orbital», Decide por mí, Guardar en…, Versión, Stremio) deja 24 pt del asa a su primer título y el margen de siempre a los lados; `sides: false` si un carrusel llega a las orillas. | sí |
| Aviso | `Toast` · `dsNoticePlacement(lift:)` · `DS.Toast.gap` | Abajo, al alcance del pulgar, y siempre a 8 pt (`DS.Toast.gap`) de lo que tenga debajo: la barra de pestañas, «Viendo en la TV» o lo que la pantalla deje flotando (el pie del mosaico lo declara en `AppUI.noticeLift`). Nunca un margen a ojo. La pastilla de calificar va en el mismo lugar. Uno a la vez: el nuevo reemplaza al que solo informa y espera detrás del que trae salida («Deshacer»). Una acción que tarda avisa al tocar («Mandando a tu Orbital…») y confirma al terminar («Ya está en tu Orbital»). (30 oct 2026) | sí |
| Etiqueta | íconos antes que texto | Nada de cápsulas de texto para estados; un ícono o el dato tal cual (`DSBadge` solo sobre el arte o «HOY»; «Nuevo» sobre un póster, el listón de la esquina `DSCornerRibbon`). | — |
| Texto sobre arte | `ArtVeil` | Todo texto encima de un póster, fotograma o fondo desenfocado va sobre su velo (`bottom`, `top`, `both`, `full`, `leading`; `soft`, `strong`, `deep`). Nunca un degradado a mano. | sí |
| Cargando | el esqueleto de su forma · `DSLoadingState` | Una lista o fila carga con su esqueleto (`FeedSkeleton`, `ShelfSkeleton`, `CheckRowSkeleton`); un área que no es lista, con `DSLoadingState`. Junto a un botón, el indicador chico con su texto («Conectando…»). | sí |
| Sin conexión o error | `DSErrorState(offline:retry:)` · `DSNotice` | Un área que no llegó dice «Sin conexión» o «No se pudo cargar» con «Reintentar»; nunca un vacío que diga «nada» cuando lo que pasó es que no llegó. Dentro de una sección, `DSNotice`. | — |
| Números y fechas | `Strings.count` · `Strings.date` | En el idioma de la app, no en el del teléfono: «1000» sin separador hasta 9999 y con espacio fino después; «jueves 12 de agosto». Nada de `.formatted()` ni `DateFormatter` en las pantallas. | sí |
| Logos de marca | a la misma altura *visual* | Los logos que van juntos (IMDb, TMDB, Rotten Tomatoes; las plataformas) se ven del mismo tamaño, no miden lo mismo: una palabra larga (TMDB) va más baja (`DS.RatingBrand.wordmarkScale`). | — |
| Lo que se mueve solo | El mosaico se detiene a los 90 s (con el protector, avanza a pasos); todo respeta movimiento reducido | Igual | La TV no tiene cielo que se mueva: Orbital no gasta detrás de un juego. |
| Accesibilidad | `.accessibilityElement(children: .contain)` | Un contenedor con identificador declara `.contain`: si no, le pone su id a todo lo de adentro y VoiceOver y las pruebas pierden sus botones. | sí |

**Glosario (un nombre por cosa).** Lo que se ve en pantalla se llama igual en todos lados; `DesignTests` no deja volver los
nombres viejos.

| Se llama | No | Qué es |
|---|---|---|
| Mi lista | tu watchlist, Tu watchlist | lo que dejaste pendiente (tu watchlist de Trakt) |
| Favoritos | — | lo que marcaste con el corazón |
| Tus series | lo que sigues (como título) | las series que estás viendo |
| Lo que ves | Tu año (como entrada) | tus números (solo en el iPhone) |
| Colecciones | tu repisa | los premios y listas del canon |
| Decide por mí | ¿Qué vemos? | el sorteo de una propuesta |
| ¿Qué vemos hoy? | Tinder | el mazo «Encuentra tu match perfecto» |
| Reintentar | Intentar de nuevo | el botón tras un error |

**Textos cortos y que no mienten.** Un porqué cabe en un renglón en un iPhone SE (38 letras como máximo) y no lleva cifras
fijas («Más de 50 formas» mentía si había menos). Sin jerga («Al instante»). La prueba los mide.

**Antes de cerrar una pantalla.** Se revisa en cuatro combinaciones: claro y oscuro, en un iPhone SE y en uno grande
(`scripts/ios_capture_matrix.sh`). Varios errores de esta revisión solo se veían en una de las cuatro.

**Espacios.** Entre secciones de una pantalla, `DS.Editorial.sectionGap` (36) en todas: Inicio, Para ti, Buscar, Lo que ves,
Colecciones, Mi media, una persona, la hoja de Canales. Del encabezado a su contenido, `DS.Space.s3`. Entre renglones o
tarjetas de una lista, `DS.Space.s2`. A los lados, `DS.Space.gutter`. Los grupos dentro de una misma lista (las décadas de una
colección) van más juntos (`s5`): no son secciones. En Para ti, las colecciones en carrusel se separan con `groupGap` porque su
reflejo ya pone el resto del aire.

**Títulos de navegación.** Las pestañas (Para ti, Descargas, Buscar) llevan el título grande en el renglón de los botones
(`.inlineLarge`); Inicio, el logotipo. Lo que se abre encima va en `.inline`, salvo las pantallas con su propio encabezado en
grande (Lo que ves, Colecciones).

**Acentos.** Turquesa: el porqué y lo que está en vivo. Ámbar: las estrellas de calificar y los avisos. El verde de `success`:
lo que ya se puede ver («HOY», «Nuevo»). El color del arte: el botón principal de un título y su fondo.

**Texto tenue vs. adorno:** `--color-text-faint` (blanco al 50 %, ≥ 4,5:1) es texto que se lee; `--color-decorative`
(ink-500) solo adornos que no se leen, como la cifra grande del Top 10.

**Los componentes solo usan tokens semánticos** (o primitivos de medida y movimiento): nunca `--palette-*` directo. Un valor nuevo
primero se nombra aquí: qué *es* (`--duration-enter`, «algo que aparece»), no cuánto vale.

### Tabla espejo (iPhone ↔ TV)

Una sola Orbital (Fernando, 31 oct 2026): cada papel del lenguaje del iPhone tiene aquí su pieza de la TV y su estado. Estado:
`Igual`, `Pendiente · ola N` (con su renglón en `docs/producto/paridad-registro.md`), `Distinto a propósito: motivo` o
`Solo iPhone: motivo`. `tests/web/design-parity.test.mjs` falla si un papel nuevo del iPhone no tiene renglón aquí. Cuando se
decide algo del iPhone, su commit dice qué pasa en la TV («En la TV: igual · distinto a propósito · pendiente»).

| Papel | Pieza de la TV | Estado | Nota |
|---|---|---|---|
| Encabezado | `SectionHead(title, { level })` (`ui.js`) y el rótulo de las filas de tarjetas (`shelf__heading--section`) | Igual | Sección = rótulo con ícono en `--color-orbital`, mayúsculas chicas y línea, el dato a la derecha (Tus consolas, Día por día, Premios, Estudios…); subsección = título blanco. |
| Arranque de una parte grande | El rótulo de sección de cada grupo (`shelf__heading--section`) | Distinto a propósito: con el mando, un renglón menos (el título grande lo pone el destacado de arriba, que cambia con el foco) | Los grupos de Películas y series (Plataformas, Estudios, Premios, Temporadas, Años…). |
| Renglón de lista | Tarjetas de lista en fila (`collection-card`) y `sheet__item` en las hojas | Distinto a propósito: con el mando, tus listas son tarjetas en una fila (Listas de Trakt, de Stremio) | En las hojas (☰, Opciones, Guardar en…), el renglón es `sheet__item`. |
| Porqué | `SectionHead(title, { reason })` y `--color-reason` | Igual | Solo cuando el porqué dice algo que el título no; un dato nunca va en turquesa. |
| Botón principal | `Button({ variant: "primary" })` y `title__action--primary` | Igual | En blanco, como el iPhone (dsSolidPrimaryButton): «Jugar», «Ver», «Continuar»; nunca del color del arte. |
| Botón secundario | `Button` y los redondos, de vidrio (`--color-glass` con su filo) | Igual | El vidrio del iPhone (`.glassEffect(.regular)`), en su versión sutil; enfocado, se invierte (con el mando, el foco se ve a tres metros). |
| Botón de ícono | `Button({ icon })` (`button--round`) y los redondos de la ficha (`title__action--icon`) | Igual | Uno sólido y los demás redondos: Opciones, Ficha y Episodios en el destacado de Inicio, el de Películas y series y la ficha de Juegos, con el glifo en su orilla y su nombre debajo. |
| Selector | `Pill({ tone: "tab" })` (pestañas de texto), `Segmented`, `Pill` (cápsulas) | Igual | Cambiar lo que ves: pestañas de texto (los filtros de una consola, Series · Películas de una lista, las temporadas de la ficha); ajustar un valor: `Segmented` (Ajustes); elegir: cápsulas (¿Qué vemos?, búsquedas recientes). Lo elegido en blanco; el foco, invertido. Los mosaicos llegan con el mazo (ola 2). |
| Búsqueda avanzada | `filter-panel` (☰ › Filtro avanzado) y «Ordenar y filtrar» de `list-screen` | Igual | En la TV vive en ☰ (Fernando, 31 oct 2026); filas con ‹ › en lugar de mosaicos (distinto a propósito: el mando). Las listas y colecciones: tipo, género, calificación, década y lo visto. |
| Marcar como vista | La hoja «¿Cuándo la viste?» (Opciones › Marcar como vista) | Igual | «Otro día…» ofrece días comunes en lugar del calendario (distinto a propósito: el mando). |
| Vacío | `EmptyState({ icon, title, text })` (`ui.js`) | Igual | Juegos sin favoritos o sin juegos, un día sin estrenos, TV en vivo sin canales, Explorar sin sugerencias o sin conexión, una lista vacía o sin nada con sus filtros. |
| Tarjeta | `--color-surface` (ink-900) y `--radius-*` | Distinto a propósito: la superficie es ink-900 en la TV (lo explica `design/tokens.json`) | — |
| Hoja con encabezado propio | `sheet`, `side-panel` | Igual | — |
| Aviso | `toast` | Distinto a propósito: arriba a la derecha, porque abajo va el pie de pistas y se lee desde el sillón | Mismos tonos, textos y duración (`--duration-notice`). |
| Etiqueta | `Badge`, `Chip` y `CornerRibbon` | Igual | «Nuevo» es el listón de la esquina del póster (Mi media, sus listas); «HOY» y el ▲▼ del Top 10 se quedan en placa. |
| Texto sobre arte | `Veil(...lados)` y `--veil-bottom`, `--veil-leading`, `--veil-top`, `--veil-bottom-soft`, `--veil-corner` | Igual | Una receta por lado; los velos de pseudo-elemento (tarjeta de premio, escenario de «Porque viste», mosaico) usan los mismos tokens. |
| Cargando | `PosterSkeletons(n)` (`skeleton--poster`, `skeleton--heading`) | Igual | Películas y series (dos filas) y una lista abierta, quietos: nada se anima mientras se espera. |
| Sin conexión o error | Mensajes en palabras con «Reintentar» | Igual | — |
| Números y fechas | `core/format.js` | Igual | — |
| Logos de marca | `--platform-*` y los logos de `ui.js` | Igual | — |
| Lo que se mueve solo | El mosaico se detiene a los 90 s; todo respeta movimiento reducido | Igual | La TV no tiene cielo que se mueva: Orbital no gasta detrás de un juego. |
| Accesibilidad | Foco visible y pistas de cada superficie | Solo iPhone: es cómo SwiftUI agrupa los identificadores | — |

### Movimiento

| Token | Para qué |
|---|---|
| `--duration-none` | Movimiento reducido: sin transición. |
| `--duration-instant` · `--duration-fast` · `--duration-base` | Salidas cortas, foco, cambios de estado. |
| `--duration-slow` · `--duration-snap` | Paneles, secciones que entran de lado, el «salto» de una portada. |
| `--duration-enter` · `--duration-enter-long` · `--duration-land` | Algo que aparece · la primera entrada de una pantalla · el arranque. |
| `--duration-exit` | Salidas (más cortas que las entradas y acelerando: `--ease-in`). |
| `--duration-tint` · `--duration-drift` | El color del fondo cambia · el fondo sigue al foco. |
| `--duration-alive` | «Cobra vida»: quieto en una pieza de Para ti, su arte se acerca despacio. |
| `--duration-glide` · `--ease-glide-in/out` | Un tramo de la deriva de Para ti (la anima el compositor) y cómo arranca y se frena sin costura. |
| `--duration-pulse` · `--duration-breathe` | Cursor de escribir, «te escuché» · algo que espera (dictando). |
| `--duration-launch-*` | Pantalla de carga (cinemática, más lenta a propósito). |
| `--delay-1/2/3` · `--stagger` | Escalonado: cada pieza entra un poco después. |
| `--ease-out` · `--ease-in` · `--ease-spring` · `--ease-pop` · `--ease-launch` · `--ease-sweep` | Entradas · salidas · resorte corto · foco que salta · disparo · barrido. |

**Capas**: toda capa nueva se funde en `--duration-base`, un panel lateral se desliza en `--duration-slow` y todo sale en `--duration-exit` (la ficha entra en `--duration-fast` a propósito: su arte aparece casi de inmediato).

Todo respeta **movimiento reducido** (`prefers-reduced-motion` o Ajustes → Pantalla): `base.css` lleva
todas las duraciones a `--duration-none` y detiene los bucles.

### Capas

Globales: `--z-overlay`, `--z-hints`, `--z-launch`, `--z-toast`. Dentro de un componente:
`--z-behind`, `--z-raised`, `--z-above`, `--z-panel`.

---

## 2. Piezas base (`ui`, `button`, `glyph`, `keyboard`)

| Pieza | Archivo | Para qué |
|---|---|---|
| `Chip(text, { tone })` | `ui` | Un dato corto: «4K», «Inglés», «Al instante» (`good`/`warn`). Una línea, nunca se parte. |
| `PlatformMark(src, fallback)` | `ui` | La marca **real** de una plataforma, a color y del alto de la letra (`platformMark(item)` en `core/icons.js`): el logo de Stremio para películas y series, los de Steam y GeForce NOW, y la foto de la consola para un juego retro. La misma en el Inicio, Películas y series, el héroe y Juegos; sin marca (una app), el ícono de líneas. |
| `Badge(text, { large })` | `ui` | Etiqueta que llama la atención: «3 nuevos», «Recomendada» (sin mayúsculas). `large` sobre arte a sangre (el mosaico de Para ti). |
| `PlatformBadge(text, brand, { large })` | `ui` | «En Netflix», «N.º 1 en Disney+» como el iPhone: cápsula del color de la plataforma (`--platform-*`, vía `--platform-color`), su logo de JustWatch chico a la izquierda (`.badge__logo`) y el texto en blanco. Solo Netflix, Disney+, HBO Max, Prime Video y Paramount+ (`PLATFORM_PILLS`); las demás, `Badge` con el nombre en su estilo. En el mosaico de Para ti. |
| `Pill(label, { on, tone, icon })` | `ui` | Píldora que se elige: los filtros de Juegos y de ¿Qué vemos? (`tone: "outline"`), las pestañas de una lista y de las temporadas, y las búsquedas recientes (`tone: "fill"`). **Una sola pieza**: misma altura (`--pill-height`), mismo peso, lo elegido con relleno tenue (`pill--on`) y el foco invertido (`pill--focused` o `.is-focused`). |
| `.side-panel` + `.side-panel__panel` | `ui.css` | El menú flotante: vidrio fuerte separado de las orillas, del alto de lo que trae, sobre un velo: los menús (`sheet`). Con `side-panel--bottom`, sube desde abajo, a lo ancho: «Elegir versión» (`sources`). Comparten el velo, el marco y cómo entra y sale; cada uno pone su ancho, su relleno y su contenido. |
| `Segmented(choices, { onPick })` | `ui` | Valores segmentados: todas las opciones de un ajuste a la vista, cada una una `Pill`; la elegida en papel (`--color-primary`) y, dentro de una fila enfocada (foco invertido), se invierte con ella. Tocar o hacer clic en una la elige; con mando o teclado, ◀/▶ desde su fila. Solo cuando caben (`segmentable`: hasta cuatro valores y cortos); si no, el valor de siempre con ‹ ›. Con el dedo, del alto de `--touch-target`. En Ajustes (`settings`). |
| `Progress(fraction)` | `ui` | Cuánto llevas de un video. |
| `SectionHead(title, { meta, end })` | `ui` | Título de una zona con su dato y algo a la derecha. |
| `ScreenHead({ eyebrow, title, lead })` + `.screen` | `ui` | Pantalla completa encima de todo (Conectar Stremio, Conectar Trakt): `.screen` es el marco (fondo, margen, entrada y salida con `screen--leaving`) y `ScreenHead` su encabezado («Cuentas» · título · una línea). **Dos composiciones**: *página* (el encabezado arriba, centrado, y el contenido debajo: Conectar Stremio, ¿Qué vemos?, Tu año; el calendario lo alinea a la izquierda porque su mes ocupa todo el ancho) y *diálogo* (una tarjeta al centro que lleva su propio encabezado: Conectar Trakt, OneDrive y iPhone, Cambiar el arte). Una pantalla nueva elige una de las dos. |
| `KeyHint(glyph, label, { small })` | `ui` | Botón del mando + qué hace («A Continuar»). **El pie de controles se arma con esta pieza.** |
| `.tile` | `ui` | Superficie enfocable de las pantallas nuevas: mismo radio, anillo de foco y atenuado. |
| `Button({ label, glyph, variant, yields, icon })` | `button` | Acción con su glifo, en cápsula. El principal (`variant: "primary"`), siempre blanco; los demás, de vidrio; con `icon`, redondo con su nombre debajo. `yields`: el que se encoge si la fila no cabe. Con mando no reciben foco (son la leyenda); con ratón o dedo se pulsan. |
| `Flag(code, hint)` | `flag` | La banderita de un idioma donde lo eliges: filas de Elegir versión y Ajustes › Idioma y Subtítulos. Del alto de la letra, en 3:2. Sale de `orbital/flags.py` (los SVG de `img/flags/` y `core/flags.js` los escribe `scripts/flags.py`), que también la dibuja en el reproductor (Audio, Subtítulos, Versión): la misma en los dos. Latino y el español que no dice cuál: 🇲🇽; castellano: 🇪🇸; portugués: 🇧🇷 (igual que el iPhone). Una versión con dos audios lleva las dos. El lector de pantalla lee solo el nombre. |
| `Glyph(text, { small })` | `glyph` | El botón del mando en su color (A verde, B rojo, X azul, Y amarillo); cambia con el modo de entrada (`data-input`: mando o teclado). |
| `createKeyboard()` | `keyboard` | Teclado en pantalla (Buscar, Conectar Stremio). |

## 3. Tarjetas y tiles (`card`, `tiles`)

| Pieza | Para qué |
|---|---|
| `Card(item, { caption, showAgo, pop })` (`card`) | Portada de un juego o video en filas y cuadrículas (`caption: "focus"`: el nombre solo bajo la enfocada). Sin arte: el respaldo con su nombre; apps: su ícono (`appIcon`). Esquina: estrella si es favorito (`item.favorite`), palomita si ya lo tienes en una lista de afuera (`item.owned`); la otra esquina, el puesto del Top 10 (`item.rank`, Netflix o lo más visto de una plataforma) con la misma placa oscura. |
| `RankedCard(item, options)` (`card`) | Un puesto en una lista Top 10 (todas sus portadas traen `rank`), como `RankedPosterCard` del iPhone: la cifra enorme en `--color-decorative` detrás del póster, que va encima a la derecha; el ▲ ▼ / «Nuevo» sube a la esquina. Devuelve `{ card, el }`: `card` es el botón enfocable y `el` lo que se monta. |
| `CollectionCard(item)` · `SourceBadge(source)` · `AwardWordmark(name, tint)` (`collection-card`) | Una lista como tarjeta, las mismas del iPhone (FanCard, AwardCard, YearCard, ListCard, BecauseCard): plataforma (su top 3 en abanico y su logo con el halo de su color), estudio (nombre en cápsula), género y temporada (el mismo abanico y, al frente, su ícono a color `.collection__emblem` —`img/collections/<slug>.png`, los 19 de Grok Imagine del iPhone, tal cual, sin filtro ni placa— y su nombre debajo; las temporadas con su color `--color-season-*`, los géneros neutros; el héroe dice «Género» o «Temporada»), premio (la estatuilla real al frente y su halo oro, plata o bronce), año (cuatro pósters y el número grande), lista tuya (dos pósters en pila, nombre, sello y cuántos) y «Porque viste X». Mide como una portada (alto `--card-height`, ancho por su proporción) y A abre su lista (`list-screen`). `SourceBadge`: el sello de origen junto a un título (TRAKT, STREMIO, ORBITAL) en `--color-source-*`. `AwardWordmark`: el nombre de un premio como logotipo (`--font-award`, mayúsculas espaciadas puestas por el JS, degradado de su metal `--color-award-*`); también en el héroe y en la lista abierta. En una fila `centered` (`.shelf__row--centered`) la enfocada va al centro y las de los lados más chicas y apagadas, con reflejo. |
| `FeatureHero` (`tiles`) | El destacado del Inicio sobre el arte a pantalla (§ 0). |
| `ArtFit(src, { poster, ratio, fallback, onReady })` (`art-fit`) | El arte de una caja ancha: la ficha (`title`), el escenario de «Porque viste» (`shelf`), la tarjeta ancha de Destacados (`Card` con `wide`) y lo ancho del mosaico de Para ti. Llena la caja; si la imagen es un **póster vertical** —se sabe (`poster`: no hay fondo ancho) o lo dice su medida al cargar (`tooNarrow` en `core/images.js`: la caja es más de 1,25 veces más ancha, en proporción, que la imagen)—, el **tratamiento de póster**: nítido y entero (`contain`) sobre una copia de sí mismo muy desenfocada (`.art-fit__blur`, la misma del estuche del destacado), como el fondo de ambiente con solo portada (`backdrop`). Nunca un póster recortado a una franja. No se ve hasta saber cómo va (sin recorte primero y póster después); en caché, al instante. Quien lo usa dice dónde cae el póster (`--art-fit-x`, a la derecha por omisión: el texto va a la izquierda), su aire (`--art-fit-pad`) y de qué altura se recorta (`--art-fit-y`). En la ficha cada fondo nuevo se carga primero y entra fundido (`--duration-base`) sobre el anterior. |
| `PersonChip(person, { onPress })` · `PersonHead(person)` (`people`) | Una cara del reparto o de quien la hizo, como CastMember del iPhone: foto redonda (o sus iniciales), nombre y papel («Dirección», o el personaje), en la fila «Reparto» de la ficha (bajo «Más como esto»). Foco: anillo en la foto. `PersonHead`: la persona arriba de su filmografía (`list-screen` con `person`): foto grande, de dónde es y su biografía en tres líneas (X la despliega). |
| `ConsoleTile` (`tiles`) | Foto real de la consola (o logo) con brillo de su color, juegos, nuevos y lo último. |

`.card-grid` (`card.css`): la cuadrícula de portadas de Juegos y de una lista abierta; todas con la misma forma (`--grid-ratio`) y la enfocada de la primera o la última columna crece hacia adentro (`markGridEdge`).

### Márgenes de las tarjetas

| Tamaño | Token | Valor | Dónde |
|---|---|---|---|
| Póster o miniatura | `--inset-poster` | `--space-2` | Insignias, puesto, avance sobre una portada o una miniatura (`Card`, número del canal, calendario compacto) |
| Renglón | `--inset-row` | `--space-2` | Un renglón con miniatura y texto |
| Tarjeta mediana | `--inset-card` | `--space-4` | `ConsoleTile`, canal de TV en vivo y tarjeta del calendario |
| Destacado | `--inset-feature` | `--space-6` | La invitación del Inicio vacío y las fichas grandes |

Reglas:
1. **Un margen por tarjeta, igual en los cuatro lados.**
2. **Lo que va en una esquina usa el mismo margen que el texto** (píldora de plataforma, insignia, número): su borde
   izquierdo queda en la misma línea que el título.
3. **Esquinas concéntricas:** lo que va dentro curva como la tarjeta menos el margen (`--radius-inner-row`); así no
   asoman esquinas claras entre la miniatura y el borde.
4. **El avance de un video va sobre la imagen**, abajo, con `--inset-poster` (póster, miniatura de renglón), nunca como
   renglón extra de texto.
5. **Nada más grande que su tarjeta:** una imagen dentro de un renglón se mide contra el alto del renglón
   (`grid-template-rows: minmax(0, 1fr)` + `height: 100%`), no contra un tope fijo.

**Ningún texto de tarjeta o botón se sale**: una línea con «…» (o `line-clamp` con espacio para las
letras que bajan: g, p, j, y).

## 4. Pantallas y vistas (cada una con su JS y su CSS del mismo nombre)

| Componente | Qué es |
|---|---|
| `status-bar` | Barra de arriba: marca, Buscar, pestañas (LB/RB), Alexa (navegable: muestra ejemplos de órdenes), lo que está abierto (un ícono quieto en `--color-live` —▶ si es un video, el control si es un juego; en pausa, ▶ en ámbar— y su nombre, centrado con la altura de las mayúsculas), batería y hora. |
| `hints` | Pie de controles del momento (piezas `KeyHint`). |
| `foryou` | Para ti (a la izquierda del Inicio): el mosaico de lo tuyo mezclado (`foryou-mosaic`). A ve o juega, Y abre Opciones (ficha, «No me interesa»). Las listas viven en Películas y series (`core/media-plan.js`), con el orden del iPhone. |
| `foryou-mosaic` | Mosaico de Para ti: columnas de imágenes; la enfocada crece y enseña etiqueta, logo y un dato; bajar sube todo (cascada) y quieto 2 s entra en ambiente (como el iPhone): todo sube despacio durante 90 s, se frena y se queda quieto hasta el siguiente botón (Orbital no gasta mientras nadie la usa). La deriva son tramos de `--duration-glide` que anima el compositor; JavaScript solo trae piezas al empezar cada tramo. Ícono de esquina: la consola del juego, o serie / película. |
| `trakt-link` | Conectar Trakt: un código grande para escribir en trakt.tv/activate desde el celular. |
| `tv` | TV en vivo (la última de la barra, después de Películas y series): los canales de México. A la izquierda, las categorías en una lista vertical siempre a la vista (`.tv__cat`: ícono, nombre y cuántos canales; la elegida con relleno tenue aunque el foco esté en los canales); a la derecha, arriba, el canal enfocado en vivo (miniatura sin sonido, o su logo mientras conecta) con su nombre grande, y abajo una cuadrícula de `.tile` con el logo del canal (o las letras de su nombre), su número (`Chip`) y su nombre. **↑↓ en la lista cambian de categoría al instante, → pasa a los canales, ← regresa; LT/RT también cambian de categoría** (LB/RB siguen cambiando de sección). El logo siempre va **dentro de su caja** y ya viene parejo de Orbital (recortado, y sobre placa clara si es oscuro). Arriba a la derecha de cada canal: `Badge` «Al aire» (el que ves en el reproductor) o `Chip` «Sin señal reciente» (el que ya falló una vez, que además va al final de su lista y atenuado); el número y el aviso llevan placa oscura para leerse sobre cualquier logo. A sintoniza (o vuelve al que ya está al aire), teclear un número sintoniza ese canal, X vuelve a buscar y revisar los canales, B vuelve (primero al primer canal, luego a Inicio). Sin canales dice qué pasa (buscando, sin Internet). |
| `phone-link` | Conectar iPhone: un QR para la cámara del iPhone (la dirección del túnel y el token van dentro de la imagen, nunca en texto). |
| `list-screen` | Una lista abierta de Películas y series (como SortableGrid del iPhone): arriba la lista en grande (estatuilla, logo o año, nombre, sello y dato), pestañas en píldora (Series · Películas, o los rankings de una plataforma: LB/RB o ↑ hasta ellas), los filtros activos en cápsula y la cuadrícula de pósters con su nombre (y el año del premio o el día del estreno en placa). ☰ abre «Ordenar y filtrar» (como viene, IMDb, Trakt, año, A–Z; tipo, género, ocultar lo que ya viste); cada lista recuerda su orden; un ranking no se reordena. A abre la ficha (encima; B regresa a la lista), Y sus opciones, B cierra. |
| `decide` | «¿Qué vemos?» (X en Para ti, o ☰), como DecideView del iPhone: tres de tus sugerencias lado a lado que caben en tu tiempo (la hora lo propone) y tu ánimo; la enfocada dice por qué (duración, IMDb, géneros). Abajo, las preguntas en píldora (`browse__filter`): Tiempo, Ánimo y Qué. A abre su ficha, X baraja, Y «Hoy no» (24 horas), B cierra. Marco `.screen`. |
| `match-deck` | «¿Qué vemos hoy?» (☰), como MatchDeckScreen del iPhone: el mazo de tus propuestas de hoy (sin lo visto ni lo descartado en un mes, en el mismo orden diario que el iPhone), con los ánimos arriba (↑). ← Paso · → Guardar (en «Tu match perfecto» de Trakt; sin Trakt, en Mi lista) · A Ver ya · Y la ficha · X deshace lo último; con el dedo, sus tres botones. |
| `showcase` | Colecciones (☰), como la vitrina y la repisa del iPhone: los premios y las listas famosas (Criterion, Top 250 de IMDb, NYT) en tarjetas, cada una con «12 de 96» y su barra (lo visto, de Trakt). A abre su lista (`list-screen`). |
| `filter-panel` | El filtro avanzado (☰), como el del iPhone: una fila por filtro (formato, género, época, calificación, fama, dónde verla, país), cada uno con su color del arcoíris del azul de Orbital solo en su ícono (formato y «Dónde verla», en el azul de Orbital); ←→ o A cambian el valor, abajo «Ver N títulos» (cuenta TMDB al dejar de moverte) abre los resultados en `list-screen`; X borra. Con el dedo, tocar la fila o ‹ ›. |
| `calendar` | Próximos estrenos en vista calendario (la tarjeta «Próximos estrenos»), como «Sale hoy › el mes» del iPhone: el mes en una cuadrícula de lunes a domingo; cada día con el arte de lo que sale (dos el mismo día: la casilla partida; más: «+N»), hoy con el número en blanco y lo ya pasado atenuado. A la derecha, lo que sale el día enfocado (póster, episodio, hora y dónde). Cruceta día, LB/RB mes, A abre la serie (con varias, baja a la lista), B vuelve. Marco `.screen`. |
| `art-picker` | Cambiar el arte de una película o serie (Opciones › «Cambiar el arte»): dos filas, Póster y Fondo, con lo que tiene TMDB (primero en español); la primera casilla es «El de siempre» y la elegida lleva el borde del acento. La cruceta recorre, A elige (se ve ya en la biblioteca, Para ti y la ficha) y B cierra. |
| `home` | Inicio, como el Apple TV (§ 0): arriba lo que te toca sobre su arte (`FeatureHero`), abajo «A continuación» (tarjetas anchas; enfocar una la pone arriba) y Tus consolas; al bajar a ellas el Inicio se desliza. |
| `games` | Juegos en dos pisos (§ 0): debajo de la barra, tus consolas en un `GlassSwitch` (LT/RT, o ↑ y A); el juego enfocado a pantalla con su porqué, logo, datos y botones; abajo sus juegos con filtros (`browse`). Al bajar de la primera fila, las barras y el juego se van. |
| `game-page` | La página de un juego (Opciones › «Ver ficha»; Juegos «C», como la página de producto del Apple TV): su arte a pantalla con su porqué, logo, datos, sinopsis y botones; a la derecha, en vidrio, lo tuyo con él; abajo, los demás de su consola (←/→ cambian de juego y el fondo con él; A juega). |
| `rail` | Riel lateral de las categorías de Ajustes: casillas con ícono; al enfocarlo se abre como pestaña y enseña el nombre y un dato de cada una. |
| `browse` | Las piezas de una vista con portadas y filtros (Juegos, TV en vivo, ¿Qué vemos?): filtros como pestañas de texto que siempre caben en un renglón (`fillFilters`, `fitBar`, `showFilter`), la cuadrícula que se recorre lo justo (`keepInView`) y el fundido al cambiar (`replay`). |
| `hero` + `shelf` | Películas y series: el destacado arriba y las filas de portadas. El destacado cede la descripción antes que cortar los botones. Películas y series lleva, bajo Destacados, **Seguir viendo** (lo que dejaste a medias en Stremio, lo más reciente primero; Y › «Quitar de Seguir viendo») y luego el orden y los nombres de Para ti › Listas del iPhone (`core/media-plan.js`): Destacados, Porque viste, lo general con su sello, Nuevo en tus plataformas, Tus plataformas, Premios, Estudios, Por año, Próximos estrenos, Listas de Trakt y Listas de Stremio (y Por género al final). LT/RT pasan de grupo en grupo; ☰ suma «Ir a…» y «Mostrar» (Todo · Series · Películas). «Porque viste» va en escenario (`row.stage`, `.shelf__stage-row`): a la izquierda un panel fijo (`--because-stage-width`) que es un carrusel contenido de tus últimos títulos: uno a la vez, con su arte y su logo (sin él, su nombre en negrita), un punto por título y «Sugeridas ›». ◀ ▶ pasa de uno a otro (el panel lleva el anillo de foco y sus tarjetas quedan ocultas en la fila) y cambia lo relacionado, que se recorre a la derecha sin tapar el panel; **RT salta de tus títulos a lo sugerido y LT regresa al título elegido** (el pie lo dice: «Ver sugeridas» / «Tus títulos»; del otro lado, LT/RT pasan de grupo como siempre). Moverte entre tus títulos solo rehace esa fila (`updateRow`), no toda la biblioteca. |
| `title` | Ficha de una película o serie, **el arte primero** (como Apple TV): a sangre y casi entero; abajo a la izquierda solo el logo, un renglón de datos con las calificaciones (`.title__meta`), la sinopsis en tres renglones, lo disponible en texto tenue (`.title__avail`: «4K · HDR · Al instante»; si lo que va a sonar se sale de lo pedido, primero el aviso en `--color-warning`: «Solo en castellano: no hay latino») y los botones **en un renglón**: «Ver» / «Continuar» (con cómo va a sonar debajo: «Latino · 1080p · Sin subtítulos») y, a su lado, redondos solo con su ícono, cuyo nombre sale debajo del enfocado (sin mover nada). «Guardar» abre **«Guardar en…»** (como el iPhone): una hoja con casillas —Mi lista (Stremio), tu watchlist y cada una de tus listas de Trakt— que cambian al instante (`save-toggle`, en su lugar) y regresan si el servicio falla; el botón dice «Guardada» si está en cualquiera. Con más de cuatro redondos, los de menos uso (descargar, el iPhone, tu carpeta) esperan en «Más» (`ICONS.more`). Quién la hizo vive en «Reparto», al bajar. **Serie**: abajo, las temporadas en `Pill` (LB/RB, LT/RT de 5 en 5) y los episodios en una **fila de imágenes** (`.episode`: miniatura 16:9 con número, ✓, avance y «Continuar» / «Sigue»; su nombre debajo); ◀ ▶ episodio y arriba se lee el enfocado (`.title__episode` «T2 · E3 · Nombre» y su sinopsis, que guardan su lugar: nada brinca); ↑ a los botones, ↓ a «Más como esto». |
| `sources` | «Versión» de un video (Y en la ficha), en un `side-panel--bottom`: una fila por **idioma de audio** (`.versions__row`: tu idioma, luego el original y los demás; «Tu idioma», «Original» o «Tal vez» bajo el nombre) y, a la derecha, **solo las calidades que hay** (`.version`: la resolución, «Al instante» / «Tarda en empezar» y lo esencial; la recomendada con `Badge` arriba a la derecha de su casilla —fuera del flujo: nunca se corta—, una que no menciona el título con `Chip` «¿Otro título?»). La recomendada es la que pone «Ver» (con «Continuar», la de antes). En un episodio, arriba «Solo este episodio | Desde aquí» (LB/RB; `.sources__scope`): «Desde aquí» hace que la serie siga con el idioma y el doblaje de la que elijas. Sin casillas vacías ni contadores. Abajo, en una línea (`.sources__why`), los idiomas de la enfocada y cómo lo sabemos: Comprobado, Lo dice el nombre, Lo dice el sitio, Es el original, No dice idioma, Tal vez (`core/watch.js` · `PROOF_LABELS`). ↑↓ idioma (se queda en la misma calidad), ◀ ▶ calidad, A ve, X abre todas las de esa fila y calidad (`.source`, con su nombre técnico), B regresa. |
| `search` | Buscar con el teclado en pantalla y resultados vivos. |
| `login` | Conectar Stremio con el teclado en pantalla. |
| `settings` | Ajustes a pantalla completa (☰ › Ajustes, marco `.screen`): a la izquierda el `rail` con siete categorías (Resumen, Ver, Jugar, Tele y voz, Pantalla y sonido, Cuentas, Sistema; `SETTINGS_CATEGORIES` en `core/menus.js`), en su columna (no flota) y abierto mientras está enfocado, con el dato de cada una (`settingsMeta`); a la derecha la lámina de la elegida (`settingsCategory`): título, una línea, y **las filas de una hoja** (`sheet__item`, `sheet__icon`, `sheet__value`…: mismo foco invertido) con los valores en `Segmented` o con ‹ ›; lo que falta con el ícono en ámbar (`settings__row--warn`). Al pie, la ayuda de la fila enfocada en una línea (`settings__help`). Resumen enseña primero lo que falta (`settingsMissing`: la voz que no llega en dos días, Stremio, Trakt, el iPhone). Riel: ↑↓ categoría (se ve al instante, la lámina atenuada), ▶ o A entra, B cierra. Lámina: ↑↓ fila, ◀▶ cambia el valor (en una fila sin valor, ◀ vuelve al riel), A el siguiente valor o abre, LB/RB categoría, B al riel. Mouse y dedo: tocar una categoría la abre, un segmento lo elige, una fila la abre, ‹ › se tocan; la lista se desplaza con la rueda o el dedo. Lo que abre una fila (Cuentas, Emuladores, Qué ha oído…) sale encima, en una hoja o su pantalla, y B regresa a Ajustes. |
| `sheet` | Hojas laterales (menús cortos, el panel rápido, atajos). Encabezados de sección (`heading: true`) que no se enfocan; se desplaza con el foco. Una cuenta o servicio lleva su logotipo real (`mark`: Stremio, Trakt, TMDB) en lugar del ícono, y un estado que ya está bien (`ok`: «✓ Conectada», «✓ Guardada») va en `--color-ok`. |
| `toast` | Aviso: el mismo del iPhone (`Toast` / `BannerView`). Píldora arriba a la derecha, pegada a la barra de estado (nunca encima de una hoja ni de las pestañas). **Tono** (`tone`): `info` (gris), `success` (papel), `warn` (ámbar), `error` (rojo; dura `--duration-notice-long` y se anuncia como alerta), más `progress` (un texto que acaba en «…»: su ícono gira) y `voice` (Alexa). Título en un renglón y `detail` en el segundo (un « · » los parte solo); sin «Listo:» al principio: lo dice el ícono. Acción como el «Ver ›» del iPhone: `action: { label, glyph, onPress }` («Y Deshacer ›»). Con `image` (al volver de un juego), su portada ya decodificada. Dura `--duration-notice` (= `Timing.banner` del iPhone). |
| `boot` | Pantalla de arranque (`#boot` en `index.html`, `js/app/boot.js`): la entrada del iPhone (`OrbitalWordmark`, con sus mismos tiempos: `--duration-brand-*`): sobre negro, el anillo se dibuja, las letras de «orbital» suben una tras otra y la luna cae con un rebote; al estar lista la biblioteca, la marca viaja y se encoge hasta su lugar exacto en la barra mientras Inicio aparece (la de la barra no hace su propia entrada). Con movimiento reducido, un fundido. Es un componente como los demás (su CSS está en `main.css`, no en línea) y también respeta movimiento reducido. |
| `launch-overlay` | Pantalla de carga al abrir algo: la portada y, alrededor, un satélite que **va pintando su órbita** (no hay anillo dibujado: `launch__tail`, una estela que se apaga detrás de él y gira con el mismo reloj). |
| `viewer` | Visor de capturas. |
| `touch-back` | «Atrás» y «Menú» con el dedo (sin botón B ni ☰): «Atrás» arriba a la derecha sobre cualquier vista encima, «Menú» abajo a la derecha en las pantallas de siempre. Solo se ven con `data-input="touch"`. |
| `backdrop` | Fondo: arte del foco, o el espacio vivo (estrellas y luz) del Inicio, Juegos y Para ti. |

## 5. Comportamiento con el mando

> **Regla de las cuatro superficies (Fernando, oct 2026).** Todo cambio en la app de escritorio (interfaz y reproductor)
> se diseña y se prueba para las cuatro formas de usarla: **control** (mando), **teclado**, **mouse** y **touch** (la
> pantalla de la Legion Go). Cada acción nueva dice cómo se hace en las cuatro: su botón del mando y su tecla en las
> pistas del pie (`KeyHint`/`Glyph`, que cambian con `data-input`), algo que se pueda **señalar y hacer clic** con el mouse,
> y un botón tocable del tamaño del dedo con touch (en el reproductor, `player_ui.pills` y `targets`). Un atajo «oculto»
> (mantener un botón) siempre tiene también un camino visible en el menú, y el menú dice el atajo. Nada se da por listo
> sin evidencia en las cuatro.

- **Navegación espacial** (`core/spatial.js`): las piezas llevan `data-focus-id`; `nextFocus()` decide a
  cuál vas con ↑↓←→. Sirve para cualquier acomodo, no solo filas.
- **Vistas encima** (`OVERLAYS` en `main.js`): una vista nueva solo declara `{ handle, hints, isOpen }`.
- **Mismo idioma de botones en todas partes**: A abre · X la acción secundaria · Y Opciones · B atrás ·
  LB/RB sección · LT/RT saltan (o cambian de consola) · ☰ menú · ⧉ buscar.
- **Foco**:
  - Portadas y tiles: **se levantan** (crecen y flotan con `--focus-lift`; a la portada le cruza `--focus-shine`), sin anillo.
  - Teclas, opciones, filtros, Buscar y Alexa: **foco invertido** (`--inverse-bg/fg`, crece `--inverse-scale`).
  - Clase: los componentes con foco propio usan su modificador BEM (`card--focused`, `sheet__item--focused`);
    la navegación espacial marca lo demás con `.is-focused`. Lo enfocado lleva `aria-current`.
- **«Atrás» con el dedo** (sin botón B): en todo lo que va encima (Buscar, ficha, fuentes, listas, persona, menús, ¿Qué vemos?,
  Tu año, conectar cuentas) va **siempre arriba a la derecha**, el mismo lugar en cada pantalla; lo que use esa esquina (el
  encabezado de Buscar, de una lista, de una hoja o de Fuentes, las temporadas de la ficha) le deja `--touch-back-room`.
  «Menú» (sin nada encima) va abajo a la derecha: arriba está la barra con la hora. Excepción: el reproductor, cuyos botones
  van en la barra de abajo («Salir» al final) para no tapar el video.
- **Una sección que no se ve se estaciona, no se esconde** (`.is-parked` en `base.css`: `visibility: hidden` y sin toques):
  Para ti y las filas de Películas y series conservan su layout y entrar a ellas no lo arma dentro del botón. Por eso cada
  sección de la retícula tiene su celda fija (`grid-row` y `grid-column: 1`): estacionada se encima, no empuja. Las filas
  se arman de antemano en tiempo libre (`shelf.prepare`).
- **El mando, solo por `core/pads.js`.** Nadie llama `navigator.getGamepads()` ni escucha `gamepadconnected` en la ventana:
  con solo pedirlos una vez, Edge deja un hilo leyendo el hardware para siempre (~14 % de un núcleo). Se piden desde un
  iframe que, con Orbital quieta, se suelta; el primer botón llega entonces del servidor (`shell.forward_to_ui`, que ya lee
  XInput) y la interfaz vuelve a tomar el mando. Solo si el servidor ve un mando XInput y todos los que ve Edge lo son. Un
  mando que XInput no ve (PlayStation, Switch Pro) no podía despertarla: el servidor lo busca con winmm cada 3 s
  (`GamepadWatcher.others`), manda `pad-wake` y la interfaz deja de soltar el suyo mientras siga conectado.
- **Con el dedo, primero se enfoca y luego se abre.** El toque que cambia del mando (o el teclado) al dedo solo enfoca, aunque
  caiga en lo que ya estaba enfocado: eso lo eligió el mando, no tú (`justTouched` en `main.js`).
- **Pistas del pie**: dicen lo que hace cada botón *aquí*; nada de pistas que no apliquen (p. ej. «Cambiar
  de fila» con una sola fila).

## 6. Texto

- **Fuentes**: todo el texto es Segoe UI Variable, la del sistema (`--font-sans` para títulos, `--font-text` para cuerpo); no se carga ninguna con `@font-face` porque Orbital corre en Windows. Solo el nombre de un premio (`--font-award`) pide una con remate: Didot (que Windows no trae), luego Bodoni MT y Palatino Linotype; en esta máquina sale Bodoni MT.
- Español, frases normales. **Sin mayúsculas espaciadas** (se ven «de IA»; la única es el rótulo de sección, ver Excepciones): ni en etiquetas, ni pestañas,
  ni insignias.
- Tamaños solo con `--text-*` o, mejor, una receta `--type-*` (escalan con Ajustes → Tamaño del texto).
- Títulos con `line-clamp` o «…»: `-webkit-line-clamp` corta en el borde del último renglón, así que un `padding-bottom` no salva la cola de g, p, j, y. **Chicos** (tarjetas, riel, hojas): interlineado `--leading-title` (1,3). **Grandes** (héroe, ficha, destacado, mosaico): su interlineado de siempre y `overflow: clip; overflow-clip-margin: var(--clip-tail)`, que deja asomar la cola sin inflar el interlineado ni mover el diseño (con `clip` el elemento flex pide `min-width: 0` y `min-height: 0`).

## 7. Excepciones

Cada una se marca en el código con `ds-exception: <motivo>` usando exactamente el motivo de aquí.

| Motivo | Dónde | Por qué |
|---|---|---|
| logotipo en mayúsculas | `collection-card.js` (`AwardWordmark`, `SourceBadge`), `hero.js` y `list-screen.js` (el nombre de un premio) | Un premio (ÓSCAR, EMMY) y el sello de origen (TRAKT, STREMIO, ORBITAL) son **logotipos**, como en el iPhone: el JS los pone en mayúsculas (con `--tracking-award` / `--tracking-label`). No es una etiqueta de la interfaz. |
| iniciales de un canal sin logo | `core/tv.js` | Las iniciales dentro del círculo de un canal sin logo (como el avatar de una persona) van en mayúsculas. |
| rótulo de sección | `ui.css` (`.section-head__label`) | El rótulo de una sección (ícono, nombre y línea) va en mayúsculas chicas, igual que `DSChapterLabel` del iPhone (Fernando, 31 oct 2026): es lo que separa una sección de sus filas. Solo el rótulo; nada más lleva mayúsculas espaciadas. |
| listón «Nuevo» | `ui.css` (`.corner-ribbon__band`) | El listón en diagonal de la esquina de un póster dice NUEVO en mayúsculas, como `DSCornerRibbon` del iPhone. |

(Antes de agregar una, intenta un token o una pieza nueva.)

## 8. El reproductor (`orbital/player_ui.py`)

Lo dibuja mpv encima del video (texto y figuras ASS), así que no usa este CSS, pero sí **la misma
paleta** (`palette.json`) y el mismo idioma de botones. Sigue los tableros «Reproductor» del lienzo de
diseño y tiene sus propias piezas reutilizables en `player_ui.py`: `rrect`, `circle`, `ring` (cuenta
atrás), `gradient` (velo sin franjas), `glyph`/`hints` (botones del mando), `buttons`, `text`/`fit`/`wrap`
y el panel de columnas (`Panel`/`Column`). Los tamaños se escriben «como en CSS» (`FS` los convierte).

| Estado | Qué se ve | Botones |
|---|---|---|
| Al tocar un botón | Solo la barra partida por capítulos con su punto, tiempo y «termina a las…»; abajo a la izquierda el idioma, los subtítulos y la versión (el mismo renglón que en pausa). Sin título ni «Película»: eso es de la pausa | A Pausa · X Audio y subtítulos · Y Versión (en una serie, «Episodios y versión») · B (mantener) Salir; en pausa también ◀▶ Adelantar · ↑↓ Volumen · **RT Siguiente episodio** (solo si hay siguiente; con teclado, `]`). RT con un toque pasa al siguiente y LT al anterior: sale la tarjeta «Cambio de episodio · Siguiente · E3» con la cuenta atrás de 3 s en su anillo y «B Cancelar» (con el dedo, «Cancelar»; con teclado, Esc); mantenerlo cuenta una vez |
| En pausa | Video oscurecido; el **logo del título** (el mismo recortado de la ficha, en blanco si es oscuro; mpv lo pone encima con `overlay-add` en el lugar que deja `paused_ass`, `placed["logo"]`, y se prepara por detrás al pausar) o, sin logo, su nombre grande; datos, sinopsis y botones | Los mismos |
| Adelantando (◀ ▶, LB/RB) | Solo la barra y, sobre el punto, la hora, cuánto salta y el capítulo | Mantén: más rápido |
| X | Panel abajo: Audio · Subtítulos · Tamaño · Sincronía (el video sigue). Elegir audio o subtítulos **no lo cierra**; mientras está abierto, los subtítulos suben (`sub-pos`) para verse encima. En Audio, tras las pistas de esta versión, tu idioma (y los que no trae) en otra: «Latino» con «En otra · 4K» a la derecha (corto: la columna es angosta); elegirla cambia de fuente y sigue donde ibas | ◀ ▶ columna · A elegir · B cerrar |
| Probar otros (X › Subtítulos) | Franja arriba (`sub_trial_ass`, 96 px): «Español · Subtítulo 2 de 5», del video o de tu complemento, la sincronía y, a la derecha, qué pasa (bajando, sin internet, no hay más) | ◀▶ Otro subtítulo · ↑↓ Adelantar o atrasar · A Este va bien · B Listo (se queda el último que probaste, como el iPhone) |
| Y | Panel «Más»: **Episodios** (series; el encabezado dice la temporada, «Episodios · T5», y abre en la que ves; el que ves dice «Viendo» y el que sigue «Siguiente» en ámbar, `--color-warning`; LB/RB cambian de temporada, con el dedo «‹ Temporada» y «Temporada ›») · **Versión** · Reproducción. Versión es la cuadrícula de «Versión» de la ficha (`watch.version_grid`, `_grid_rows`): un renglón por idioma y sus calidades en casillas («1080p» y debajo «Al instante» en `--color-live`); abre en la que ves (con contorno) y abajo dice la enfocada en palabras | ↑↓ idioma · ◀ ▶ calidad (del borde, a la columna de al lado) · A cambiar (sigue donde ibas) · B cerrar |
| Tarjetas | «Saltar intro» (botón claro), «Siguiente episodio» (anillo de cuenta atrás), «¿Sigues viendo?» | A / B |

El reproductor no usa ☰ (Start es de Orbital: con Home, salir del juego).

Ajustes → Tamaño del texto también llega al reproductor, **un poco menos que a la interfaz** a propósito (×1,08 y ×1,16 contra ×1,12 y ×1,25: sus tableros son más apretados y lo que se mide, como `fit` y `wrap`, crece igual para recortar bien). Su fuente es `Segoe UI` (la de libass) en vez de `--font-sans`.

**Con el dedo (o el ratón)** no hay glifos del mando: `TOUCH` cambia `hints` por `pills` (botones que se
tocan) y cada pieza tocable anota su lugar en `targets` (`hit()` dice qué tocaste). Reproduciendo: «−10 s ·
Pausa · +10 s · Audio y subtítulos · Episodios · Salir» abajo, a la derecha; en pausa, «−10 s · +10 s · ⏭ Siguiente · E3 ·
Probar subtítulos · Salir» a la derecha («⏭ Siguiente» solo si hay siguiente; «T6 E1» si cruza de temporada; hace lo mismo que RT); tocar la barra salta ahí; tocar el
video enseña o esconde los botones. En los paneles se toca la opción (o la columna) y «Cerrar»; en las
tarjetas, sus botones («Seguir viendo», «Salir»). mpv avisa dónde tocaste (`script-message orbital-tap`) y
cualquier botón del mando vuelve a los glifos. Si el video se abrió con el dedo, empieza ya así.

### Tráiler

«Tráiler» en la ficha se ve **dentro de Orbital**, con el mismo mpv: `yt-dlp` le enseña a abrir el video de YouTube
(`orbital/ytdlp.py`; Orbital lo baja solo a `%LOCALAPPDATA%\orbital\tools`, comprueba su huella SHA-256 y lo actualiza
al rato de arrancar y cada 12 h). Es un *clip* (`meta["clip"]`): hasta 1080p y, si el video trae doblajes, el audio en tu
idioma; no guarda avance, no avisa a Trakt, no entra en «Seguir viendo» y no tiene versiones ni episodios (la barra, la
pausa y los botones táctiles no ofrecen «Versión», y Y no abre nada). Lo demás es igual: A pausa, ◀ ▶ adelanta, X audio,
B mantenido (o «Salir» con el dedo) regresa a la ficha, y al terminar se cierra solo. Si hay un juego abierto, antes
pregunta, como cualquier video. Si falla: «No pude reproducir el tráiler».

### TV en vivo

Los canales usan el mismo mpv y la misma pantalla, pero no hay película que pausar ni a dónde adelantar:
no se guarda avance, no hay «Seguir viendo» ni episodios, y los botones cambian de sentido.

| Estado | Qué se ve | Botones |
|---|---|---|
| Al sintonizar o tocar un botón | La barra del canal: su número en un bloque claro, el nombre, el estado (● En vivo · Sintonizando… · Sin señal), la categoría, la calidad, la hora y las pistas | ↑ ↓ o LT/RT cambian de canal (la barra enseña a dónde vas al instante y se sintoniza al parar) · ◀ ▶ volumen · A sin sonido · X audio · Y guía de canales · B (mantener) Salir |
| Y | Panel «Categoría \| Canales» (el video sigue); el canal que ves, marcado; los que fallaron, «Sin señal reciente» | ◀ ▶ columna · LT/RT página · A elegir · B cerrar |
| Un canal que no abre | «Sin señal en este canal · ↑ ↓ para cambiar»; se marca y se pasa al siguiente (máximo 3 seguidos) | ↑ ↓ |
| Sin sonido (A) | Una píldora fija «Sin sonido» arriba a la izquierda mientras dure (la barra del canal se va sola) | A otra vez |
| Home (volver a Orbital) | El canal sigue al aire **sin sonido** (no se pausa: al volver estaría atrasado); al volver suena, salvo que ya lo hubieras silenciado | — |

## 9. Arte

Todo tiene imagen. Orden: arte propio de Orbital (scraper) → el de ES-DE si sirve → respaldo de
`img/placeholders/` (varias opciones por consola, generadas con Grok Imagine; a cada juego le toca
siempre la misma). Fotos de consolas en `img/consoles/` (Evan-Amos, dominio público).

## 10. Deuda conocida

Cosas que una auditoría (octubre de 2026) encontró y que se dejaron a propósito. Ninguna rompe una pantalla; cuando se toque la
pieza, se paga de paso.

| Qué | Por qué se deja |
|---|---|
| El brillo con el color de la consola se escribe en seis lugares con geometrías distintas (`card`, `tiles`, `rail`) | Una propiedad personalizada no se resuelve por pieza dentro de un token del tema; haría falta una clase compartida (`.console-glow`) y tocar el JS de cinco piezas. |
| Hover y `disabled`: solo existen donde el ratón importa (botones, teclas, pistas); no hay controles deshabilitados | La interfaz es de mando y el ratón enfoca al pasar; si aparece un control deshabilitado, se define su estado en `ui.css` antes de usarlo. |
| El foco usa dos clases: `--focused` (BEM, la de cada pieza) y `.is-focused` (la que pone la navegación espacial) | Unificarlas pide tocar `core/spatial.js` y los componentes que la usan; `core/focus-mark.js` ya pone `aria-current` en las dos. |
| `✓`, `★`, `⚠`, `◀ ▶` salen como texto (fuente Segoe UI Symbol) | Hay ícono dibujado (`ICONS.check`, `ICONS.star`) pero esos textos también viajan al iPhone. |
| Medidas sueltas en rem (.55, .6, .15…) que no coinciden con un `--space-*` | Son ajustes ópticos de cada pieza (un relleno de píldora, un hueco entre líneas); un token por cada una no aclararía nada. |
| El mosaico de Para ti llega a 9 px del borde de la pantalla | Es a propósito (los pósters pasan por los lados); con sobrebarrido de la TV, ajustar «Márgenes de la TV» no lo mueve. |
