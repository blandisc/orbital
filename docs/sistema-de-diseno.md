# Sistema de diseño de Orbital

**Regla de oro: nada se crea suelto.** Una pantalla nueva se arma con las piezas de este documento. Si
falta una pieza, se agrega al sistema (aquí y en `js/components/` + `styles/components/`), no dentro de
la pantalla. Así un chip, una tecla o un foco se ven igual en todas partes.

Esto no depende de la buena memoria: **`tests/web/design-system.test.mjs` lo verifica** en cada corrida
de pruebas (`node --test tests/web/*.test.mjs`) y falla si:

1. el CSS de un componente escribe a mano un **color**, una **duración**, una **capa** (`z-index`), un
   **tamaño de letra** o **mayúsculas espaciadas** (todo eso son tokens);
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
| Primitivos | `tokens.css` | Espacio (`--space-*`), radios (`--radius-*`), letra (`--text-*`, `--weight-*`, `--tracking-*`, interlineado `--leading-*`), opacidad por lo que significa (`--opacity-*`), vidrio (`--blur-glass`), movimiento (`--duration-*`, `--ease-*`, `--delay-*`, `--stagger`), capas (`--z-*`), medidas de consola (`--card-*`, `--tile-*` —también `--tile-channel-width`, el canal de TV en vivo—, `--key-height`, `--sheet-width`, y las alturas de control `--pill-height`, `--control-height`, `--control-sm`, `--menu-row-height` y `--touch-target`; íconos `--icon-*` y trazo `--stroke-*`…). |
| Semánticos | `themes/orbital.css` | Lo que usan los componentes: `--color-*`, `--shadow-*` (cajas) y `--shadow-drop*` (siluetas), `--ring-focus`, foco invertido (`--inverse-bg/fg/scale`), sobre el arte (`--color-badge-bg`, `--gradient-tile-shade`), dentro de algo claro (`--on-light-*`) o de color (`--on-color-fill`), máscaras (`--mask-solid`), fondo de ambiente (`--color-backdrop-deep`), sombra sobre el arte (`--color-art-shade`), relieves (`--gradient-sheet`, `--gradient-console-tile`, `--gradient-launch-planet`), `--color-star`, `--color-video-bg`, `--assistant-accent`, el grafito neutro del arte (`--art-*-neutral`) y el color de cada consola (`--system-*`). |

**Compartido con el iPhone: `design/tokens.json`** (paleta, papeles, espacios, radios, duraciones, opacidades, recetas de
texto) y **`design/vocabulario.json`** (lo que las dos apps dicen igual: «Mi lista», «Ver la serie», «Seguir viendo»…).
`tests/web/design-parity.test.mjs` compara `tokens.css`, `themes/orbital.css` y el código Swift del iPhone contra esos dos
archivos: cambiar un valor o un texto en un solo lado falla CI. Las diferencias a propósito (la superficie, ink-900 aquí
e ink-850 en el iPhone) van en el JSON con su `porque`.

**Recetas de texto** (`--type-*`, los nombres del iPhone): `display` (3xl, negrita), `title` (2xl, negrita), `section`
(lg, negrita), `card-title` (md, medium), `body` (md), `secondary` (sm), `footnote` (xs), `caption` (2xs), `eyebrow` (sm,
medium) y `data` (xs, números tabulares); solo en la TV, `heading` (xl: un encabezado de zona) y `hero` (el título del héroe). **Un componente usa la receta, nunca el tamaño de la escala** (`--text-*` es del CSS de tokens; la prueba lo vigila).

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
| `Pill(label, { on, tone, icon })` | `ui` | Píldora que se elige: los filtros de Juegos y de ¿Qué vemos? (`tone: "outline"`), las pestañas de una lista y de las temporadas, y las búsquedas recientes (`tone: "fill"`). **Una sola pieza**: misma altura (`--pill-height`), mismo peso, lo elegido con relleno tenue (`pill--on`) y el foco invertido (`pill--focused` o `.is-focused`). |
| `.side-panel` + `.side-panel__panel` | `ui.css` | Un panel a la derecha sobre un velo: los menús (`sheet`) y las fuentes (`sources`). Comparten el velo que se funde, el marco (relieve `--gradient-sheet`, borde, sombra) y cómo entra y sale; cada uno pone su ancho, su relleno y su contenido. |
| `Progress(fraction)` | `ui` | Cuánto llevas de un video. |
| `SectionHead(title, { meta, end })` | `ui` | Título de una zona con su dato y algo a la derecha. |
| `ScreenHead({ eyebrow, title, lead })` + `.screen` | `ui` | Pantalla completa encima de todo (Conectar Stremio, Conectar Trakt): `.screen` es el marco (fondo, margen, entrada y salida con `screen--leaving`) y `ScreenHead` su encabezado («Cuentas» · título · una línea). **Dos composiciones**: *página* (el encabezado arriba, centrado, y el contenido debajo: Conectar Stremio, ¿Qué vemos?, Tu año; el calendario lo alinea a la izquierda porque su mes ocupa todo el ancho) y *diálogo* (una tarjeta al centro que lleva su propio encabezado: Conectar Trakt, OneDrive y iPhone, Cambiar el arte). Una pantalla nueva elige una de las dos. |
| `KeyHint(glyph, label, { small })` | `ui` | Botón del mando + qué hace («A Continuar»). **El pie de controles se arma con esta pieza.** |
| `.tile` | `ui` | Superficie enfocable de las pantallas nuevas: mismo radio, anillo de foco y atenuado. |
| `Button({ label, glyph, variant, yields, art })` | `button` | Acción con su glifo. Con `art`, el principal toma el color del arte de lo enfocado (`--color-primary-art`, como el «Jugar» de Game Glance): destacado del Inicio, ficha lateral, héroe y «Ver» en la ficha. En una fila van dentro de `.button-row`: **nunca se parte ni se corta**; si no cabe, solo el botón `yields` (la alternativa, «Con Ryujinx») se encoge con «…». Casi siempre es leyenda (no se enfoca); cuando es lo único que hay que hacer (Conectar Trakt), lleva `data-focus-id` y el anillo de foco. |
| `Glyph(text, { small })` | `glyph` | El botón del mando en su color (A verde, B rojo, X azul, Y amarillo); cambia con el modo de entrada (`data-input`: mando o teclado). |
| `createKeyboard()` | `keyboard` | Teclado en pantalla (Buscar, Conectar Stremio). |

## 3. Tarjetas y tiles (`card`, `tiles`)

| Pieza | Para qué |
|---|---|
| `Card(item, { caption, showAgo, pop })` (`card`) | Portada de un juego o video en filas y cuadrículas. Sin arte: el respaldo con su nombre; apps: su ícono (`appIcon`). Esquina: estrella si es favorito (`item.favorite`), palomita si ya lo tienes en una lista de afuera (`item.owned`); la otra esquina, el puesto del Top 10 (`item.rank`, Netflix o lo más visto de una plataforma) con la misma placa oscura. |
| `RankedCard(item, options)` (`card`) | Un puesto en una lista Top 10 (todas sus portadas traen `rank`), como `RankedPosterCard` del iPhone: la cifra enorme en `--color-decorative` detrás del póster, que va encima a la derecha; el ▲ ▼ / «Nuevo» sube a la esquina. Devuelve `{ card, el }`: `card` es el botón enfocable y `el` lo que se monta. |
| `CollectionCard(item)` · `SourceBadge(source)` · `AwardWordmark(name, tint)` (`collection-card`) | Una lista como tarjeta, las mismas del iPhone (FanCard, AwardCard, YearCard, ListCard, BecauseCard): plataforma (su top 3 en abanico y su logo con el halo de su color), estudio (nombre en cápsula), premio (la estatuilla real al frente y su halo oro, plata o bronce), año (cuatro pósters y el número grande), lista tuya (dos pósters en pila, nombre, sello y cuántos) y «Porque viste X». Mide como una portada (alto `--card-height`, ancho por su proporción) y A abre su lista (`list-screen`). `SourceBadge`: el sello de origen junto a un título (TRAKT, STREMIO, ORBITAL) en `--color-source-*`. `AwardWordmark`: el nombre de un premio como logotipo (`--font-award`, mayúsculas espaciadas puestas por el JS, degradado de su metal `--color-award-*`); también en el héroe y en la lista abierta. En una fila `centered` (`.shelf__row--centered`) la enfocada va al centro y las de los lados más chicas y apagadas, con reflejo. |
| `FeatureTile` (`tiles`) | El destacado del Inicio: arte a sangre, logo o título, dato y botones (`.button-row`). Si solo hay caja (GBA cuadrada, Switch alta), **estuche**: la portada desenfocada de fondo y la caja encima, a la derecha. De dónde es va en una píldora de vidrio sobre el arte (`.tile__platform--pill`), igual que en la ficha lateral. Sobre el título, el rótulo (`eyebrowOf`, el `Eyebrow` del iPhone): «Seguir viendo», «Sigue» o «Seguir jugando». |
| `RowTile` (`tiles`) | Renglón: miniatura ancha (cápsula de Steam, fondo, o la caja recortada) y al lado el nombre grande y su dato siempre a la vista, con avance si es video. El texto nunca va encima del arte. |
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
| `foryou-mosaic` | Mosaico de Para ti: columnas de imágenes; la enfocada crece y enseña etiqueta, logo y un dato; bajar sube todo (cascada) y quieto ~30 s entra en ambiente. Ícono de esquina: la consola del juego, o serie / película. |
| `trakt-link` | Conectar Trakt: un código grande para escribir en trakt.tv/activate desde el celular. |
| `tv` | TV en vivo (entre Películas y series y Apps): los canales de México. A la izquierda, las categorías en una lista vertical siempre a la vista (`.tv__cat`: ícono, nombre y cuántos canales; la elegida con relleno tenue aunque el foco esté en los canales); a la derecha, arriba, el canal enfocado en vivo (miniatura sin sonido, o su logo mientras conecta) con su nombre grande, y abajo una cuadrícula de `.tile` con el logo del canal (o las letras de su nombre), su número (`Chip`) y su nombre. **↑↓ en la lista cambian de categoría al instante, → pasa a los canales, ← regresa; LT/RT también cambian de categoría** (LB/RB siguen cambiando de sección). El logo siempre va **dentro de su caja** y ya viene parejo de Orbital (recortado, y sobre placa clara si es oscuro). Arriba a la derecha de cada canal: `Badge` «Al aire» (el que ves en el reproductor) o `Chip` «Sin señal reciente» (el que ya falló una vez, que además va al final de su lista y atenuado); el número y el aviso llevan placa oscura para leerse sobre cualquier logo. A sintoniza (o vuelve al que ya está al aire), teclear un número sintoniza ese canal, X vuelve a buscar y revisar los canales, B vuelve (primero al primer canal, luego a Inicio). Sin canales dice qué pasa (buscando, sin Internet). |
| `phone-link` | Conectar iPhone: un QR para la cámara del iPhone (la dirección del túnel y el token van dentro de la imagen, nunca en texto). |
| `list-screen` | Una lista abierta de Películas y series (como SortableGrid del iPhone): arriba la lista en grande (estatuilla, logo o año, nombre, sello y dato), pestañas en píldora (Series · Películas, o los rankings de una plataforma: LB/RB o ↑ hasta ellas), los filtros activos en cápsula y la cuadrícula de pósters con su nombre (y el año del premio o el día del estreno en placa). ☰ abre «Ordenar y filtrar» (como viene, IMDb, Trakt, año, A–Z; tipo, género, ocultar lo que ya viste); cada lista recuerda su orden; un ranking no se reordena. A abre la ficha (encima; B regresa a la lista), Y sus opciones, B cierra. |
| `decide` | «¿Qué vemos?» (X en Para ti, o ☰), como DecideView del iPhone: tres de tus sugerencias lado a lado que caben en tu tiempo (la hora lo propone) y tu ánimo; la enfocada dice por qué (duración, IMDb, géneros). Abajo, las preguntas en píldora (`browse__filter`): Tiempo, Ánimo y Qué. A abre su ficha, X baraja, Y «Hoy no» (24 horas), B cierra. Marco `.screen`. |
| `calendar` | Próximos estrenos en vista calendario (la tarjeta «Próximos estrenos»), como «Sale hoy › el mes» del iPhone: el mes en una cuadrícula de lunes a domingo; cada día con el arte de lo que sale (dos el mismo día: la casilla partida; más: «+N»), hoy con el número en blanco y lo ya pasado atenuado. A la derecha, lo que sale el día enfocado (póster, episodio, hora y dónde). Cruceta día, LB/RB mes, A abre la serie (con varias, baja a la lista), B vuelve. Marco `.screen`. |
| `year` | «Tu año» (☰), como YearView del iPhone: horas, racha más larga y tu género en `.tile`; el mapa día por día (semanas en columnas, colores `--color-year-*` del iPhone) con lo que viste el día enfocado (←→ semana, ↑↓ día, LT/RT un mes); y «Lo que más viste» en portadas. Marco `.screen`. |
| `art-picker` | Cambiar el arte de una película o serie (Opciones › «Cambiar el arte»): dos filas, Póster y Fondo, con lo que tiene TMDB (primero en español); la primera casilla es «El de siempre» y la elegida lleva el borde del acento. La cruceta recorre, A elige (se ve ya en la biblioteca, Para ti y la ficha) y B cierra. |
| `home` | Inicio: saludo, el destacado (enseña lo enfocado) y «También tenías» en renglones a la derecha; Tus consolas asoman abajo y al bajar a ellas el Inicio se desliza. |
| `games` | Juegos: tus consolas en el riel (cruceta o LT/RT), encabezado de consola, filtros y cuadrícula; la ficha del juego enfocado. Armado con `rail`, `browse` y `detail-panel`. |
| `rail` | Riel lateral de una vista con secciones (consolas, listas): casillas con foto, logo de marca o ícono; RePág/AvPág arriba y abajo; grupos con su nombre. **Al enfocarlo se abre como pestaña** y enseña el nombre y un dato de cada sección; lo de atrás se aparta. |
| `browse` | El centro de una vista con secciones: encabezado (`BrowseHead`: la sección en su casilla, nombre grande y lo esencial), filtros en píldora (`fillFilters`, se compactan si no caben en una fila) y la cuadrícula de portadas (`keepInView`). La usa Juegos. |
| `detail-panel` | Ficha lateral de lo enfocado (un juego, una película, una serie): arte que se funde con la ficha (máscara, sin bordes), logo o nombre, de dónde es, hasta cuatro datos, la descripción y sus acciones (o una nota: «No lo tienes»). |
| `hero` + `shelf` | Películas y series / Apps: el destacado arriba y las filas de portadas. El destacado cede la descripción antes que cortar los botones. Películas y series lleva el orden y los nombres de Para ti › Listas del iPhone (`core/media-plan.js`): Destacados, Porque viste, lo general con su sello, Nuevo en tus plataformas, Tus plataformas, Premios, Estudios, Por año, Próximos estrenos, Listas de Trakt y Listas de Stremio (y Por género al final). LT/RT pasan de grupo en grupo; ☰ suma «Ir a…» y «Mostrar» (Todo · Series · Películas). «Porque viste» va en escenario (`row.stage`, `.shelf__stage-row`): a la izquierda un panel fijo (`--because-stage-width`) que es un carrusel contenido de tus últimos títulos: uno a la vez, con su arte y su logo (sin él, su nombre en negrita), un punto por título y «Sugeridas ›». ◀ ▶ pasa de uno a otro (el panel lleva el anillo de foco y sus tarjetas quedan ocultas en la fila) y cambia lo relacionado, que se recorre a la derecha sin tapar el panel; **RT salta de tus títulos a lo sugerido y LT regresa al título elegido** (el pie lo dice: «Ver sugeridas» / «Tus títulos»; del otro lado, LT/RT pasan de grupo como siempre). Moverte entre tus títulos solo rehace esa fila (`updateRow`), no toda la biblioteca. |
| `title` | Ficha de una película o serie: datos, botones, temporadas (LB/RB) y episodios. |
| `sources` | Elegir fuente de un video. |
| `search` | Buscar con el teclado en pantalla y resultados vivos. |
| `login` | Conectar Stremio con el teclado en pantalla. |
| `sheet` | Hojas laterales (menús, ajustes, atajos). Encabezados de sección (`heading: true`) que no se enfocan; se desplaza con el foco. Una cuenta o servicio lleva su logotipo real (`mark`: Stremio, Trakt, TMDB) en lugar del ícono, y un estado que ya está bien (`ok`: «✓ Conectada», «✓ Guardada») va en `--color-ok`. |
| `toast` | Aviso: el mismo del iPhone (`Toast` / `BannerView`). Píldora arriba a la derecha, pegada a la barra de estado (nunca encima de una hoja ni de las pestañas). **Tono** (`tone`): `info` (gris), `success` (papel), `warn` (ámbar), `error` (rojo; dura `--duration-notice-long` y se anuncia como alerta), más `progress` (un texto que acaba en «…»: su ícono gira) y `voice` (Alexa). Título en un renglón y `detail` en el segundo (un « · » los parte solo); sin «Listo:» al principio: lo dice el ícono. Acción como el «Ver ›» del iPhone: `action: { label, glyph, onPress }` («Y Deshacer ›»). Con `image` (al volver de un juego), su portada ya decodificada. Dura `--duration-notice` (= `Timing.banner` del iPhone). |
| `boot` | Pantalla de arranque (`#boot` en `index.html`, `js/app/boot.js`): el planeta y su órbita sobre las estrellas; al estar lista la biblioteca, la cámara se zambulle en el planeta. Es un componente como los demás (su CSS está en `main.css`, no en línea) y también respeta movimiento reducido. |
| `launch-overlay` | Pantalla de carga al abrir algo. |
| `viewer` | Visor de capturas. |
| `touch-back` | «Atrás» y «Menú» con el dedo (sin botón B ni ☰): «Atrás» arriba a la derecha sobre cualquier vista encima, «Menú» abajo a la derecha en las pantallas de siempre. Solo se ven con `data-input="touch"`. |
| `backdrop` | Fondo: arte del foco, o el espacio vivo (estrellas y luz) del Inicio, Juegos y Para ti. |

## 5. Comportamiento con el mando

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
| Al tocar un botón | Título, barra partida por capítulos con su punto, tiempo y «termina a las…», idioma y fuente | A Pausa · X Audio y subtítulos · Y Fuentes · B (mantener) Salir; en pausa también ◀▶ Adelantar · ↑↓ Volumen · LT RT Episodio |
| En pausa | Video oscurecido; título grande, datos, sinopsis y botones | Los mismos |
| Adelantando (◀ ▶, LB/RB) | Solo la barra y, sobre el punto, la hora, cuánto salta y el capítulo | Mantén: más rápido |
| X | Panel abajo: Audio · Subtítulos · Tamaño (el video sigue) | ◀ ▶ columna · A elegir · B cerrar |
| Y | Panel «Más»: Episodios (series) · Fuente · Desde el principio | Igual |
| Tarjetas | «Saltar intro» (botón claro), «Siguiente episodio» (anillo de cuenta atrás), «¿Sigues viendo?» | A / B |

El reproductor no usa ☰ (Start es de Orbital: con Home, salir del juego).

Ajustes → Tamaño del texto también llega al reproductor, **un poco menos que a la interfaz** a propósito (×1,08 y ×1,16 contra ×1,12 y ×1,25: sus tableros son más apretados y lo que se mide, como `fit` y `wrap`, crece igual para recortar bien). Su fuente es `Segoe UI` (la de libass) en vez de `--font-sans`.

**Con el dedo (o el ratón)** no hay glifos del mando: `TOUCH` cambia `hints` por `pills` (botones que se
tocan) y cada pieza tocable anota su lugar en `targets` (`hit()` dice qué tocaste). Reproduciendo: «−10 s ·
Pausa · +10 s · Audio y subtítulos · Episodios · Salir» abajo, al centro; tocar la barra salta ahí; tocar el
video enseña o esconde los botones. En los paneles se toca la opción (o la columna) y «Cerrar»; en las
tarjetas, sus botones («Seguir viendo», «Salir»). mpv avisa dónde tocaste (`script-message orbital-tap`) y
cualquier botón del mando vuelve a los glifos. Si el video se abrió con el dedo, empieza ya así.

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
