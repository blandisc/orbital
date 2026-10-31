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

## 1. Tokens (`orbital/web/styles/`)

| Capa | Archivo | Qué hay |
|---|---|---|
| Paleta | `palette.json` + `tokens.css` (`--palette-*`) | Los colores crudos. **Una sola paleta** para la interfaz y el reproductor (`player_ui.py` la lee del JSON). Una prueba verifica que coinciden. |
| Primitivos | `tokens.css` | Espacio (`--space-*`), radios (`--radius-*`, desde `--radius-2xs` para lo diminuto: el cursor, la batería, las casillas de Tu año), letra (`--text-*`, `--weight-*`, `--tracking-*`, interlineado `--leading-*`), opacidad por lo que significa (`--opacity-*`: `off`, `away`, `near`, `faint`, `text`, y `solid` casi entero, `soft` lo que acompaña sin mandar, `dim` lo lejano, `grain` el grano del fondo), vidrio (`--blur-glass`), movimiento (`--duration-*`, `--ease-*`, `--delay-*`, `--stagger`), capas (`--z-*`), medidas de consola (`--card-*`, `--tile-*` —también `--tile-channel-width`, el canal de TV en vivo—, `--key-height`, `--sheet-width`, y las alturas de control `--pill-height`, `--control-height`, `--control-sm`, `--menu-row-height` y `--touch-target`; íconos `--icon-*` y trazo `--stroke-*`…). |
| Semánticos | `themes/orbital.css` | Lo que usan los componentes: `--color-*`, el borde fino por dentro (`--edge-hairline`, `--edge-strong`), `--shadow-*` (cajas) y `--shadow-drop*` (siluetas), `--ring-focus`, foco invertido (`--inverse-bg/fg/scale`), sobre el arte (`--color-badge-bg`, `--gradient-tile-shade`), dentro de algo claro (`--on-light-*`) o de color (`--on-color-fill`), máscaras (`--mask-solid`), fondo de ambiente (`--color-backdrop-deep`), sombra sobre el arte (`--color-art-shade`), relieves (`--gradient-sheet`, `--gradient-console-tile`, `--gradient-launch-planet`), `--color-star`, `--color-video-bg`, `--assistant-accent`, el grafito neutro del arte (`--art-*-neutral`) y el color de cada consola (`--system-*`). |

**Compartido con el iPhone: `design/tokens.json`** (paleta, papeles, espacios, radios, duraciones, opacidades, recetas de
texto) y **`design/vocabulario.json`** (lo que las dos apps dicen igual: «Mi lista», «Ver la serie», «Seguir viendo»…).
`tests/web/design-parity.test.mjs` compara `tokens.css`, `themes/orbital.css` y el código Swift del iPhone contra esos dos
archivos: cambiar un valor o un texto en un solo lado falla CI. Las diferencias a propósito (la superficie, ink-900 aquí
e ink-850 en el iPhone) van en el JSON con su `porque`.

**Recetas de texto** (`--type-*`, los nombres del iPhone): `display` (3xl, negrita), `title` (2xl, negrita), `section`
(lg, negrita), `card-title` (md, medium), `body` (md), `secondary` (sm), `footnote` (xs), `caption` (2xs), `eyebrow` (sm,
medium) y `data` (xs, números tabulares); solo en la TV, `heading` (xl: un encabezado de zona) y `hero` (el título del héroe). **Un componente usa la receta, nunca el tamaño de la escala** (`--text-*` es del CSS de tokens; la prueba lo vigila).

**Jerarquía de encabezados (iPhone, 30 oct 2026):** dos niveles y nada más, una sola pieza (`DSSectionHead`).

| Nivel | Receta | Lleva | Ejemplos |
|---|---|---|---|
| Pantalla | barra nativa / `display` | — | «Para ti», «Buscar» |
| Sección (`level: .section`) | `title` | solo el título (y a la derecha un dato: cuántos, cuánto pesa) | Plataformas, Premios, Tuyo, Temporadas, Día por día, Descargando |
| Subsección (por omisión) | `section` | su porqué arriba en `eyebrow` turquesa (`--color-eyebrow`), siempre | En tendencia, Seguir viendo, Próximas temporadas, Reparto y equipo |
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
| Encabezado | `DSSectionHead(level:)` | Sección sola; subsección con su porqué (ver arriba). | sí |
| Arranque de una parte grande | `DSChapterHead(label:title:)` | Las partes de Para ti (HOY, PLATAFORMAS, ESTUDIOS, TEMPORADAS, GÉNEROS, PREMIOS, AÑOS): rótulo chico en mayúsculas gris con su línea fina hasta la orilla y un título blanco que dice algo («Del terror a la comedia»). Sin colores ni íconos de app: el aire y la línea separan. | — |
| Renglón de lista | `ListRow` | Pósters en pila, nombre y una línea gris, con flecha: las listas de «Tuyo» y la entrada de «Lo que ves». | — |
| Porqué | `Eyebrow(reason: true)` · `DS.eyebrow` | Siempre turquesa, arriba de su título; solo para porqués: un dato (el periodo «Este mes», lo elegido en un filtro) no va en turquesa. Las excepciones dicen por qué (`ds-exception:`): los rótulos de historia del Wrapped (ámbar), la ruleta de Los Simpson (su amarillo), «En la tele» sobre el arte. | sí |
| Botón principal | `dsPrimaryButton()` (vidrio) · `dsSolidPrimaryButton()` (sólido) | Sólido a todo lo ancho con esquinas de tarjeta (Ver, Continuar, Ver resultados, Ver tu Wrapped); en línea dentro de un renglón, `shape: .capsule`; en una fila de íconos, `shape: .circle`. El de vidrio, junto a otros botones de vidrio. | sí |
| Botón secundario | `dsSecondaryButton()` | Con borde, en cápsula y del color del texto; el tamaño, con `controlSize`. | sí |
| Botón de ícono | `.dsIconButtonLook()` · `DSIconButton` | Vidrio en círculo; sólido donde el vidrio no se lleva bien. | — |
| Selector | por categoría: `DSTextTabs` · `DSKindFilter` · `DSSegmented` · `PanelChip` · `FilterChoice` | Según lo que hace (Fernando, 31 oct 2026): **cambiar lo que ves** → pestañas de texto (`DSTextTabs`, con ícono si ayuda; Todo · Películas · Series es `DSKindFilter`): Para ti, Buscar, listas, Decide por mí, los periodos de «Lo que ves», Descargas, Mi media y el reproductor. Excepciones decididas: Inicio con la rayita turquesa (`mark: DS.eyebrow`) y el Top 10 con su pastilla junto al título (`DSKindFilter(compact:)`, con ícono). **Ajustar un valor** → el segmentado de iOS (`DSSegmented`): Modo, energía, Quiero · Quitar, Solo este episodio · Desde aquí. **Elegir varios** → cápsulas (`PanelChip`; elegida, en el color del texto). **Elegir uno grande** → mosaicos (`FilterChoice`). Lo elegido, en blanco; nunca turquesa. | sí |
| Búsqueda avanzada | `FilterDoor` · `ActiveFilterChip` | La puerta en Buscar: la tarjeta de siempre con su nombre y una fila de filtros con íconos de línea en blanco (tocar uno abre el cajón ahí). Lo elegido, en `brandMoon` (el color de la selección del filtro), nunca en turquesa. En los resultados, cada filtro puesto es un `ActiveFilterChip` con su ✕. | — |
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
| Lo que se mueve solo | `TimelineView(.animation(paused:))` | Toda animación continua (el cielo, la estática, el cargador) se detiene con «Reducir movimiento» y con la app en segundo plano, y usa los cuadros que necesita (el cielo, 12 por segundo). | sí |
| Accesibilidad | `.accessibilityElement(children: .contain)` | Un contenedor con identificador declara `.contain`: si no, le pone su id a todo lo de adentro y VoiceOver y las pruebas pierden sus botones. | sí |

**Glosario (un nombre por cosa).** Lo que se ve en pantalla se llama igual en todos lados; `DesignTests` no deja volver los
nombres viejos.

| Se llama | No | Qué es |
|---|---|---|
| Mi lista | tu watchlist, Tu watchlist | lo que dejaste pendiente (tu watchlist de Trakt) |
| Favoritos | — | lo que marcaste con el corazón |
| Tus series | lo que sigues (como título) | las series que estás viendo |
| Lo que ves | Tu año (como entrada) | tus números; «Tu año, día por día» es una vista adentro |
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
| `.side-panel` + `.side-panel__panel` | `ui.css` | Un panel a la derecha sobre un velo: los menús (`sheet`). Con `side-panel--bottom`, sube desde abajo, a todo lo ancho y **del alto de lo que trae** (como el panel del reproductor): «Elegir versión» (`sources`). Comparten el velo que se funde, el marco (relieve `--gradient-sheet`, borde, sombra) y cómo entra y sale; cada uno pone su relleno y su contenido. |
| `Segmented(choices, { onPick })` | `ui` | Valores segmentados: todas las opciones de un ajuste a la vista, cada una una `Pill`; la elegida en papel (`--color-primary`) y, dentro de una fila enfocada (foco invertido), se invierte con ella. Tocar o hacer clic en una la elige; con mando o teclado, ◀/▶ desde su fila. Solo cuando caben (`segmentable`: hasta cuatro valores y cortos); si no, el valor de siempre con ‹ ›. Con el dedo, del alto de `--touch-target`. En Ajustes (`settings`). |
| `Progress(fraction)` | `ui` | Cuánto llevas de un video. |
| `SectionHead(title, { meta, end })` | `ui` | Título de una zona con su dato y algo a la derecha. |
| `ScreenHead({ eyebrow, title, lead })` + `.screen` | `ui` | Pantalla completa encima de todo (Conectar Stremio, Conectar Trakt): `.screen` es el marco (fondo, margen, entrada y salida con `screen--leaving`) y `ScreenHead` su encabezado («Cuentas» · título · una línea). **Dos composiciones**: *página* (el encabezado arriba, centrado, y el contenido debajo: Conectar Stremio, ¿Qué vemos?, Tu año; el calendario lo alinea a la izquierda porque su mes ocupa todo el ancho) y *diálogo* (una tarjeta al centro que lleva su propio encabezado: Conectar Trakt, OneDrive y iPhone, Cambiar el arte). Una pantalla nueva elige una de las dos. |
| `KeyHint(glyph, label, { small })` | `ui` | Botón del mando + qué hace («A Continuar»). **El pie de controles se arma con esta pieza.** |
| `.tile` | `ui` | Superficie enfocable de las pantallas nuevas: mismo radio, anillo de foco y atenuado. |
| `Button({ label, glyph, variant, yields, art })` | `button` | Acción con su glifo. Con `art`, el principal toma el color del arte de lo enfocado (`--color-primary-art`, como el «Jugar» de Game Glance): destacado del Inicio, ficha lateral, héroe y «Ver» en la ficha. En una fila van dentro de `.button-row`: **nunca se parte ni se corta**; si no cabe, solo el botón `yields` (la alternativa, «Con Ryujinx») se encoge con «…». Casi siempre es leyenda (no se enfoca); cuando es lo único que hay que hacer (Conectar Trakt), lleva `data-focus-id` y el anillo de foco. |
| `Flag(code, hint)` | `flag` | La banderita de un idioma donde lo eliges: filas de Elegir versión y Ajustes › Idioma y Subtítulos. Del alto de la letra, en 3:2. Sale de `orbital/flags.py` (los SVG de `img/flags/` y `core/flags.js` los escribe `scripts/flags.py`), que también la dibuja en el reproductor (Audio, Subtítulos, Versión): la misma en los dos. Latino y el español que no dice cuál: 🇲🇽; castellano: 🇪🇸; portugués: 🇧🇷 (igual que el iPhone). Una versión con dos audios lleva las dos. El lector de pantalla lee solo el nombre. |
| `Glyph(text, { small })` | `glyph` | El botón del mando en su color (A verde, B rojo, X azul, Y amarillo); cambia con el modo de entrada (`data-input`: mando o teclado). |
| `createKeyboard()` | `keyboard` | Teclado en pantalla (Buscar, Conectar Stremio). |

## 3. Tarjetas y tiles (`card`, `tiles`)

| Pieza | Para qué |
|---|---|
| `Card(item, { caption, showAgo, pop })` (`card`) | Portada de un juego o video en filas y cuadrículas. Sin arte: el respaldo con su nombre; apps: su ícono (`appIcon`). Esquina: estrella si es favorito (`item.favorite`), palomita si ya lo tienes en una lista de afuera (`item.owned`); la otra esquina, el puesto del Top 10 (`item.rank`, Netflix o lo más visto de una plataforma) con la misma placa oscura. |
| `RankedCard(item, options)` (`card`) | Un puesto en una lista Top 10 (todas sus portadas traen `rank`), como `RankedPosterCard` del iPhone: la cifra enorme en `--color-decorative` detrás del póster, que va encima a la derecha; el ▲ ▼ / «Nuevo» sube a la esquina. Devuelve `{ card, el }`: `card` es el botón enfocable y `el` lo que se monta. |
| `CollectionCard(item)` · `SourceBadge(source)` · `AwardWordmark(name, tint)` (`collection-card`) | Una lista como tarjeta, las mismas del iPhone (FanCard, AwardCard, YearCard, ListCard, BecauseCard): plataforma (su top 3 en abanico y su logo con el halo de su color), estudio (nombre en cápsula), género y temporada (el mismo abanico y, al frente, su ícono a color `.collection__emblem` —`img/collections/<slug>.png`, los 19 de Grok Imagine del iPhone, tal cual, sin filtro ni placa— y su nombre debajo; las temporadas con su color `--color-season-*`, los géneros neutros; el héroe dice «Género» o «Temporada»), premio (la estatuilla real al frente y su halo oro, plata o bronce), año (cuatro pósters y el número grande), lista tuya (dos pósters en pila, nombre, sello y cuántos) y «Porque viste X». Mide como una portada (alto `--card-height`, ancho por su proporción) y A abre su lista (`list-screen`). `SourceBadge`: el sello de origen junto a un título (TRAKT, STREMIO, ORBITAL) en `--color-source-*`. `AwardWordmark`: el nombre de un premio como logotipo (`--font-award`, mayúsculas espaciadas puestas por el JS, degradado de su metal `--color-award-*`); también en el héroe y en la lista abierta. En una fila `centered` (`.shelf__row--centered`) la enfocada va al centro y las de los lados más chicas y apagadas, con reflejo. |
| `FeatureTile` (`tiles`) | El destacado del Inicio: arte a sangre, logo o título, dato y botones (`.button-row`). Si solo hay caja (GBA cuadrada, Switch alta), **estuche**: la portada desenfocada de fondo y la caja encima, a la derecha. De dónde es va en una píldora de vidrio sobre el arte (`.tile__platform--pill`), igual que en la ficha lateral. Sobre el título, el rótulo (`eyebrowOf`, el `Eyebrow` del iPhone): «Seguir viendo», «Sigue» o «Seguir jugando». |
| `RowTile` (`tiles`) | Renglón: miniatura ancha (cápsula de Steam, fondo, o la caja recortada) y al lado el nombre grande y su dato siempre a la vista, con avance si es video. El texto nunca va encima del arte. |
| `ArtFit(src, { poster, ratio, fallback, onReady })` (`art-fit`) | El arte de una caja ancha: la ficha (`title`), el destacado (`FeatureTile`), el escenario de «Porque viste» (`shelf`), la tarjeta ancha de Destacados (`Card` con `wide`) y lo ancho del mosaico de Para ti. Llena la caja; si la imagen es un **póster vertical** —se sabe (`poster`: no hay fondo ancho) o lo dice su medida al cargar (`tooNarrow` en `core/images.js`: la caja es más de 1,25 veces más ancha, en proporción, que la imagen)—, el **tratamiento de póster**: nítido y entero (`contain`) sobre una copia de sí mismo muy desenfocada (`.art-fit__blur`, la misma del estuche del destacado), como el fondo de ambiente con solo portada (`backdrop`). Nunca un póster recortado a una franja. No se ve hasta saber cómo va (sin recorte primero y póster después); en caché, al instante. Quien lo usa dice dónde cae el póster (`--art-fit-x`, a la derecha por omisión: el texto va a la izquierda), su aire (`--art-fit-pad`) y de qué altura se recorta (`--art-fit-y`). En la ficha cada fondo nuevo se carga primero y entra fundido (`--duration-base`) sobre el anterior. |
| `PersonChip(person, { onPress })` · `PersonHead(person)` (`people`) | Una cara del reparto o de quien la hizo, como CastMember del iPhone: foto redonda (o sus iniciales), nombre y papel («Dirección», o el personaje), en la fila «Reparto» de la ficha (bajo «Más como esto»). Foco: anillo en la foto. `PersonHead`: la persona arriba de su filmografía (`list-screen` con `person`): foto grande, de dónde es y su biografía en tres líneas (X la despliega). |
| `ConsoleTile` (`tiles`) | Foto real de la consola (o logo) con brillo de su color, juegos, nuevos y lo último. |

`.card-grid` (`card.css`): la cuadrícula de portadas de Juegos y de una lista abierta; todas con la misma forma (`--grid-ratio`) y la enfocada de la primera o la última columna crece hacia adentro (`markGridEdge`).

### Márgenes de las tarjetas

| Tamaño | Token | Valor | Dónde |
|---|---|---|---|
| Póster o miniatura | `--inset-poster` | `--space-2` | Insignias, puesto, avance sobre una portada o una miniatura (`Card`, número del canal, calendario compacto) |
| Renglón | `--inset-row` | `--space-2` | `RowTile` (También tenías): del borde a la miniatura y al texto |
| Tarjeta mediana | `--inset-card` | `--space-4` | `ConsoleTile`, canal de TV en vivo y tarjeta del calendario |
| Destacado | `--inset-feature` | `--space-6` | `FeatureTile` (y fichas grandes) |

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
| `calendar` | Próximos estrenos en vista calendario (la tarjeta «Próximos estrenos»), como «Sale hoy › el mes» del iPhone: el mes en una cuadrícula de lunes a domingo; cada día con el arte de lo que sale (dos el mismo día: la casilla partida; más: «+N»), hoy con el número en blanco y lo ya pasado atenuado. A la derecha, lo que sale el día enfocado (póster, episodio, hora y dónde). Cruceta día, LB/RB mes, A abre la serie (con varias, baja a la lista), B vuelve. Marco `.screen`. |
| `year` | «Tu año» (☰), como YearView del iPhone: horas, racha más larga y tu género en `.tile`; el mapa día por día (semanas en columnas, colores `--color-year-*` del iPhone) con lo que viste el día enfocado (←→ semana, ↑↓ día, LT/RT un mes); y «Lo que más viste» en portadas. Marco `.screen`. |
| `art-picker` | Cambiar el arte de una película o serie (Opciones › «Cambiar el arte»): dos filas, Póster y Fondo, con lo que tiene TMDB (primero en español); la primera casilla es «El de siempre» y la elegida lleva el borde del acento. La cruceta recorre, A elige (se ve ya en la biblioteca, Para ti y la ficha) y B cierra. |
| `home` | Inicio: saludo, el destacado (enseña lo enfocado) y a la derecha, en renglones, «Continuar» (si hay un juego) o «Seguir viendo» (solo videos) (`core/home.js`); Tus consolas asoman abajo y al bajar a ellas el Inicio se desliza. |
| `games` | Juegos: tus consolas en el riel (cruceta o LT/RT), encabezado de consola, filtros y cuadrícula; la ficha del juego enfocado. Armado con `rail`, `browse` y `detail-panel`. |
| `rail` | Riel lateral de una vista con secciones (consolas, listas, las categorías de Ajustes): casillas con foto, logo de marca o ícono; RePág/AvPág arriba y abajo; grupos con su nombre. **Al enfocarlo se abre como pestaña** y enseña el nombre y un dato de cada sección; lo de atrás se aparta. |
| `browse` | El centro de una vista con secciones: encabezado (`BrowseHead`: la sección en su casilla, nombre grande y lo esencial), filtros en píldora (`fillFilters`, se compactan si no caben en una fila) y la cuadrícula de portadas (`keepInView`). La usa Juegos. |
| `detail-panel` | Ficha lateral de lo enfocado (un juego, una película, una serie): arte que se funde con la ficha (máscara, sin bordes), logo o nombre, de dónde es, hasta cuatro datos, la descripción y sus acciones (o una nota: «No lo tienes»). |
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
  - Portadas y tiles: anillo blanco (`--ring-focus`) y crecen un poco.
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
- Español, frases normales. **Sin mayúsculas espaciadas** (se ven «de IA»): ni en etiquetas, ni pestañas,
  ni insignias.
- Tamaños solo con `--text-*` o, mejor, una receta `--type-*` (escalan con Ajustes → Tamaño del texto).
- Títulos con `line-clamp` o «…»: `-webkit-line-clamp` corta en el borde del último renglón, así que un `padding-bottom` no salva la cola de g, p, j, y. **Chicos** (tarjetas, riel, hojas): interlineado `--leading-title` (1,3). **Grandes** (héroe, ficha, destacado, mosaico): su interlineado de siempre y `overflow: clip; overflow-clip-margin: var(--clip-tail)`, que deja asomar la cola sin inflar el interlineado ni mover el diseño (con `clip` el elemento flex pide `min-width: 0` y `min-height: 0`).

## 7. Excepciones

Cada una se marca en el código con `ds-exception: <motivo>` usando exactamente el motivo de aquí.

| Motivo | Dónde | Por qué |
|---|---|---|
| logotipo en mayúsculas | `collection-card.js` (`AwardWordmark`, `SourceBadge`), `hero.js` y `list-screen.js` (el nombre de un premio) | Un premio (ÓSCAR, EMMY) y el sello de origen (TRAKT, STREMIO, ORBITAL) son **logotipos**, como en el iPhone: el JS los pone en mayúsculas (con `--tracking-award` / `--tracking-label`). No es una etiqueta de la interfaz. |
| iniciales de un canal sin logo | `core/tv.js` | Las iniciales dentro del círculo de un canal sin logo (como el avatar de una persona) van en mayúsculas. |

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
| El brillo con el color de la consola se escribe en seis lugares con geometrías distintas (`card`, `detail-panel`, `tiles`, `browse`, `rail`) | Una propiedad personalizada no se resuelve por pieza dentro de un token del tema; haría falta una clase compartida (`.console-glow`) y tocar el JS de cinco piezas. |
| Hover y `disabled`: solo existen donde el ratón importa (botones, teclas, pistas); no hay controles deshabilitados | La interfaz es de mando y el ratón enfoca al pasar; si aparece un control deshabilitado, se define su estado en `ui.css` antes de usarlo. |
| El foco usa dos clases: `--focused` (BEM, la de cada pieza) y `.is-focused` (la que pone la navegación espacial) | Unificarlas pide tocar `core/spatial.js` y los componentes que la usan; `core/focus-mark.js` ya pone `aria-current` en las dos. |
| `✓`, `★`, `⚠`, `◀ ▶` salen como texto (fuente Segoe UI Symbol) | Hay ícono dibujado (`ICONS.check`, `ICONS.star`) pero esos textos también viajan al iPhone. |
| Medidas sueltas en rem (.55, .6, .15…) que no coinciden con un `--space-*` | Son ajustes ópticos de cada pieza (un relleno de píldora, un hueco entre líneas); un token por cada una no aclararía nada. |
| El mosaico de Para ti llega a 9 px del borde de la pantalla | Es a propósito (los pósters pasan por los lados); con sobrebarrido de la TV, ajustar «Márgenes de la TV» no lo mueve. |
