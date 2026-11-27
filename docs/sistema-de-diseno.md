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
| **El foco se levanta: la órbita** (D3-A, 10 nov 2026) | Crece (`--card-focus-scale`, `--tile-focus-scale` 1,08, nunca menos) y flota con `--focus-lift`; lleva un filo de luz **quieto** del color de su arte (`--orbit-color`: `--art-accent` con un piso claro; desde el 15 nov ya no lo recorre una luz al llegar: Fernando, «quita el resalte con movimiento»), con una línea oscura por dentro (`--orbit-shade`) que lo separa del arte claro. Una sola pieza: `orbit` (`orbit.js` + `orbit.css`); un solo anillo que pasa de la pieza que deja el foco a la nueva (no se crea uno por tecla) y que `focus-mark.js` no vuelve a revisar. Fuera de la pieza si no recorta; por dentro si recorta (tiles, colecciones, episodios). Sin brillo encima ni anillo grueso fijo; lo único que se mueve al enfocar es que la pieza crece | Portadas, tarjetas, tiles (consolas, canales de TV en vivo, Cambiar el arte), caras del reparto, episodios, casillas del calendario | sí: nadie usa `--color-focus` fuera de `:focus-visible`; `test_behavior.py · test_art_tint_only_reaches_the_pieces_that_use_it` mueve el foco en un navegador y mide que el color del arte cambie solo en las piezas teñidas (nunca en `<html>`) y que la órbita de lo enfocado salga de él (R3: antes `tint.test.mjs` comparaba dos listas en el código) |
| **Foco invertido** (lo que no es arte) | `--inverse-bg` / `--inverse-fg` y crece `--inverse-scale` | Opciones de un menú, filas de Ajustes, teclas, filtros, la consola enfocada del selector, Buscar y Alexa | — |
| **Nombre solo bajo lo enfocado** | `Card(item, { caption: "focus" })` | Los juegos de Juegos, «A continuación» | — |
| **La etiqueta de arriba: el porqué en turquesa** (R2, 11 nov 2026: una sola receta) | `Eyebrow(texto)` (`ui.js`) → `.eyebrow`: `--color-reason` con la receta `eyebrow` y `--shadow-text-strong`, arriba del logo o título. Dice el **porqué** («Seguir viendo», «En Mi lista», «En tendencia», «Lo que pediste», «Seguir jugando», «Sale hoy · 19:00»); los datos (tipo, año, «T1 E3», lo que queda, duración, de dónde es) van **solo** en la línea de datos y una vez. Un texto que parece dato no se pinta (`format.js · reasonOnly`). Las clases de cada pantalla (`feature-hero__eyebrow`, `hero__eyebrow`, `screen-head__eyebrow`, `games__reason`, `shelf__reason`…) solo la colocan. Antes había cuatro: turquesa con datos, gris, gris con el año y el salmón del arte (Versión, Colecciones, Decide) | El juego de Juegos («Lo jugaste hace 3 h · 48 h»), el destacado del Inicio, el héroe de Películas y series, las filas, Decide, Colecciones, Versión, TV en vivo | sí: ninguna otra regla con «eyebrow» o «reason» cambia color o letra, nadie más pinta con `--color-reason` y nadie arma la etiqueta sin `Eyebrow` (`design-system.test.mjs`); `reasonOnly` en `home.test.mjs` |
| **Destacado sobre el arte** | El arte a pantalla lo pone el fondo (`backdrop`); encima, abajo a la izquierda: porqué, logo (o título `display`), una línea de datos, avance y botones (`FeatureHero`) | Inicio, Juegos, Películas y series, la ficha | — |
| **Dos pisos** | Arriba la barra de secciones; debajo, el selector de la sección (`GlassSwitch`). Al bajar de la primera fila, las dos barras y el destacado se van (`body[data-chrome="away"]`) | Juegos (consolas) | — |
| **La luz de atrás** | `backdrop.show(arte, { tone })` toma el tono (`--art-tint`, `--art-accent`): el que ya midió el servidor (`art_tone` del ítem, V3, solo para el arte que sirve Orbital) o, si no vino, el que calcula leyendo la copia de 160 px y `backdrop.light(x, y)` acerca la luz a lo enfocado; cambia en `--duration-tint` y se queda quieta (Orbital no gasta) | Inicio, Juegos, Explorar, TV en vivo; con arte a pantalla en Inicio, Juegos y Películas y series | — |
| **Menú flotante** | `side-panel`: vidrio fuerte, separado de las orillas y con esquinas `--radius-lg`; del alto de lo que trae | Opciones, ☰, panel rápido, confirmaciones; abajo, «Elegir versión» | — |

### Escala de texto (recetas `--type-*`)

A 1080p, 1 rem ≈ 21,6 px (`--root-size`); «Tamaño del texto» multiplica todo por `--text-scale`. En pantalla chica (la Legion Go
en la mano, 1280×800: alto ≤ 900 px) el texto sube un paso más con `--text-room` (×1,1, `base.css`) sin mover el lienzo de
80 × 50 rem: así lo más chico no baja de ~17 px; en una ventana de 700 px o menos (la raíz baja a 12 px), `--text-room` es 1,04
para que `caption` no baje de 12 px (TB-05, 24 nov 2026; antes 11,6). Escala subida el 10 nov 2026 (T2) y **reducida a seis
tamaños el 24 nov 2026 (TB-03, sistema base B4)**: cuatro de interfaz y dos grandes, cada uno al menos 1,2× el de abajo (antes
nueve, con saltos de 1,04×: 21, 24, 26, 27, 30, 35, 52, 63 y 80). `--text-xs`, `--text-md` y `--text-display` ya no existen:
`footnote`, `data` y `label` subieron de 24 a 26; `card-title` y `body` bajaron de 27 a 26; `section` subió de 30 a 32;
`heading` de 35 a 40, y `hero` bajó de 80 a 63 (el tamaño de `display`: los dos son el título más grande de su pantalla).

| Receta | Tamaño | ≈ px a 1080p | Peso | Para |
|---|---|---|---|---|
| `hero` · `display` | `--text-3xl` 2,9 rem | 63 | negrita | El título del héroe de Películas y series sin logo · el de un destacado sin logo (Inicio, Juegos), el de una pantalla (la categoría de Ajustes) |
| `title` · `stat` | `--text-2xl` 2,4 rem | 52 | seminegrita | Un título largo que baja un paso, una pregunta grande · una cifra grande (tabular) |
| `heading` | `--text-xl` 1,85 rem | 40 | seminegrita | El encabezado de una zona o de una hoja |
| `section` | `--text-lg` 1,48 rem | 32 | seminegrita | El título de una fila («A continuación», «Tus 13 juegos») |
| `card-title` · `body` · `secondary` · `eyebrow` · `footnote` · `data` · `label` · `label-large` · `group-label` | `--text-sm` 1,2 rem | 26 | seminegrita o regular, según la receta | El nombre en una opción o renglón · el cuerpo · datos bajo un título · el porqué · notas · números (tabulares) · un rótulo |
| `caption` · `badge` | `--text-2xs` 0,97 rem | 21 | regular · seminegrita | El nombre bajo lo enfocado, rótulos chicos · una placa, los glifos |

Dentro del mismo tamaño, la jerarquía la ponen el grosor y la tinta (`--color-text`, `--color-text-muted`, `--color-text-faint`).
La cifra del Top 10 (`card-ranked__number`) no es texto que se lee sino un adorno (`--color-decorative`): mide con la portada
(`--card-height` × `--rank-figure`) y queda fuera de la escala. El nombre en una portada de respaldo (`.card--stand-in`) es
`card-title`, o `caption` si la portada mide menos de 7 rem de ancho (antes un tamaño que seguía al alto del póster).

**Jerarquía de grosor (D2-B, 20 nov 2026; TB-06, 24 nov 2026).** La negrita es solo para el título más grande de la pantalla
(`hero`, `display`) y para la cifra del Top 10; `title`, `heading`, `section` y `group-label` van en seminegrita, en la TV y en
el iPhone. **En la TV, desde TB-06 (sistema base B5), también las placas (`badge`) y la cifra que tecleas en TV en vivo (`stat`,
antes 800: no es lo más grande de su pantalla, el programa va en `display`) van en seminegrita**, igual que el nombre de una
plataforma (`.brand-name`) y la nota de la ficha (`.title__rating`); el 800 (`--weight-heavy`) ya no existe en la TV. El iPhone
sigue con `badge` en bold y `stat` en heavy hasta que Fernando lo vea allá (`design/tokens.json › type › pesoTv` con su porqué;
registro de paridad, «TB»). La lista vive en `design/tokens.json › boldOnly` y `tests/web/design-parity.test.mjs` falla si otra
receta lleva negrita en cualquiera de los dos lados. En los componentes tampoco hay negrita a mano: `strong`, `b` y los `h*` son
seminegrita (`base.css`), y `design-system.test.mjs` falla si un componente pone 700 fuera de `hero`, `display` o la cifra del
Top 10 (OT-2, 20 nov 2026).

Nada baja de `caption` (se lee a 3 m). Un componente usa la receta, nunca `--text-*` (prueba).

**Aire entre letras (2 nov 2026, «tipografía de cerca»).** Cada receta que lo necesita trae el suyo, `--type-<receta>-tracking`:
lo grande se aprieta (`hero` y `display` −0,03 em, `title` −0,022, `heading` −0,018, `section` −0,012, `card-title` −0,006) y lo
chico se abre (`eyebrow` 0,01, `label` y `caption` 0,012, `badge` 0,02; `group-label`, `--tracking-caps`). `body`, `secondary`,
`footnote`, `label-large` y `data` van sin ajuste. Una regla con una de esas recetas siempre lleva `letter-spacing` (prueba); puede
pedir otro a propósito (la cifra del Top 10, `--tracking-rank`; un título largo, `--tracking-display`). En el iPhone lo hace SF Pro
solo, por tamaño (su tracking óptico): por eso no hay token allá.

### Colores por papel (`themes/orbital.css`)

| Papel | Token | Regla |
|---|---|---|
| Fondo | `--color-bg`, `--color-tinted-bg` (el tono del arte) | Grafito; el color lo pone lo enfocado |
| Superficie | `--color-surface`, `--color-surface-raised` | Paneles de una pantalla completa (Ajustes, el calendario); sobre el arte, vidrio |
| Vidrio | `--color-glass`, `--color-glass-legible`, `--color-glass-hover`, `--color-glass-selected`, `--color-glass-strong`, `--edge-glass`, `--edge-glass-hairline`, `--edge-glass-selected` | Ver la receta. `--color-glass-legible` (P4): el vidrio que lleva nombres encima del arte (la barra de secciones y el selector de consolas), más oscuro debajo para que se lean (AA) sobre un arte claro |
| Texto | `--color-text`, `--color-text-muted`, `--color-text-faint`, `--color-on-art-secondary` | Tres tintas (TB-13, sistema base B9): el papel, el gris de los datos (ink-250) y el tenue, un gris opaco (#868687, el blanco al 50 % ya mezclado sobre el fondo: el `tertiaryLabel` del iPhone), que se lee (≥ 4,5:1 sobre el fondo, la superficie y la superficie alta; 4,7 la más clara). El blanco al 62 % (`--color-text-faint-strong`) se fue a `--color-text-muted`. Sobre el arte, `on-art-secondary` con su sombra |
| Principal | `--color-primary` / `--color-on-primary` | Blanco con letra negra; también el foco invertido |
| Porqué | `--color-reason` | Turquesa; solo porqués |
| Lo de Orbital | `--color-orbital` (la luna) | El ícono de un rótulo de sección |
| En vivo · bien | `--color-live`, `--color-ok` | Turquesa |
| Aviso · peligro | `--color-warning`, `--color-danger` | Ámbar · rojo. El ámbar es solo para avisos: la calificación (★) lleva su token, `--color-rating` (el mismo ámbar que el iPhone), y lo que está bien («Listo», `chip--good`) va en verde, `--color-success` / `--on-light-success` (OT-6, 20 nov 2026) |
| Nuevo | `--color-new` | El listón «Nuevo», «Hoy»: el turquesa del puntito del logo (`DS.fresh`), no el verde (11 nov 2026: Fernando deshizo el puntito, «no quiero que quites la cinta de nuevo») |
| Acento por categoría | `--rainbow-*` | El arcoíris del azul de Orbital: categorías de TV en vivo (filtros, después) |
| Marcas | `--platform-*`, `--brand-*`, `--system-*`, `--color-source-*` | El color de cada plataforma, consola o fuente; nunca para la interfaz |

**Sombras: solo lo que flota (TB-14, 24 nov 2026; sistema base B10).** Para separar se usa lo más ligero: espacio, línea, tinte,
borde y, al final, tarjeta. La sombra de caja queda para lo que de verdad flota encima de todo (menús, hojas, avisos:
`--shadow-overlay`) y para lo enfocado que se levanta (`--focus-lift`). `--edge-glass` es solo el filo (antes llevaba una sombra que
despegaba cada control del arte); el botón principal resalta por su blanco, sin sombra; las portadas (`.card`), las tarjetas de
colección y el escenario de «Porque viste» (`.shelf__stage`) quietos van sin sombra. Los halos de color se quedan (B11 no se
aplica: Fernando, 24 nov).

### Ritmo (5 nov 2026)

Una medida para cada cosa, repetida en toda la app, en la TV y en el iPhone:

| Qué | TV | iPhone | Valor |
|---|---|---|---|
| Esquina chica: botones cuadrados, teclas, insignias, lo diminuto | `--radius-sm` (T11, 10 nov: antes `--radius-2xs` … `--radius-md`, cuatro nombres para un valor) | `DS.Radius.xs` … `.md` | .5rem · 8 pt |
| Esquina de tarjeta: pósters, tarjetas, hojas, menús | `--radius-lg` (antes también `--radius-xl` y `--radius-2xl`) | `DS.Radius.lg` … `.xxl` | 1rem · 16 pt |
| Lo redondo | `--radius-pill` | `DS.Radius.pill` | cápsula |
| Entre secciones | `--layout-between-sections` | `DS.Layout.betweenSections` | 2rem · 32 pt |
| Alto de fila | `--row-height` | — | uno para todas las filas |

Los nombres viejos se quedan como alias para no tocar cada componente, pero solo valen esas dos medidas. Las esquinas
de adentro (`--radius-inner-*`, abajo) y los dibujos de aparatos (`ds-exception`) siguen aparte.

**Esquinas anidadas (C2, 24 nov 2026):** lo que va dentro de algo redondeado curva como lo de afuera menos el margen entre
ambos, nunca menos de 0; un token por par, y `tests/web/radius-nesting.test.mjs` comprueba la cuenta, que lo de afuera y su
margen sigan siendo esos y que lo de adentro use su token:

| Par | Token | Cuenta | Da |
|---|---|---|---|
| Renglón de una hoja (`.sheet__item`) dentro del panel (`.side-panel__panel`) | `--radius-inner-sheet` | `--radius-lg` − `--space-6` | 0: el margen (1,5rem) es más que la esquina (1rem), así que el renglón enfocado va en rectángulo (antes `--radius-lg`, chueco contra el panel) |
| Miniatura del calendario (`.calendar__thumb`) dentro de su programa (`.calendar__show`) | `--radius-inner-card` | `--radius-lg` − `--inset-row` | .5rem (antes `--radius-inner-row`, que medía contra `--tile-radius` y no contra su tarjeta; se quitó) |
| Ícono de una pregunta del filtro (`.filter__icon`) dentro de su renglón (`.filter__row`) | `--radius-inner-filter` | `--radius-lg` − `--space-2` | .5rem (el mismo valor que tenía, ahora por cuenta) | Lo vigilan
`tests/web/design-system.test.mjs` («ritmo») y `DesignTests.testRadiiFollowTheRhythm`; los valores viven en `design/tokens.json`.

### Espacios

| Qué | Token | Valor |
|---|---|---|
| La escala | `--space-1`, `-2`, `-4`, `-6`, `-8`, `-12`, `-16` | **Siete pasos y nada más (D3-B, Fernando, 20 nov 2026): 4 · 8 · 16 · 24 · 32 · 48 · 64** (.25, .5, 1, 1,5, 2, 3, 4 rem; en el iPhone `DS.Space.s1` … `s16`, los mismos puntos). 4 y 8 dentro de un grupo, 16 y 24 entre piezas, 32, 48 y 64 entre grupos. Si un aire no cae en la escala, se usa el paso más cercano, no un número nuevo; 12, 20, 40 y 56 ya no existen (pasaron a 8, 24, 48 y 64). `tests/web/design-parity.test.mjs` («siete pasos») falla si aparece otro en la TV o en el iPhone. **B1 (24 nov 2026):** los rellenos, márgenes y huecos sueltos de `orbital/web/styles` (.1, .15, .4, .6, .78rem, 2px…: los 46 que anotaba el revisor y 12 que no veía por ir en la misma línea que otro) pasaron al paso más cercano (los de .1rem, a 0); el revisor común (`tools/sistema-base/revisar.py`, SB-2) ya no anota ninguno en la TV. Lo que no es un aire sino una cuenta va en `calc()`: el lado de la lupa de Buscar (el aire más media diferencia entre la lupa y la tecla, para que sigan concéntricas) y el centrado de la órbita y el satélite de la pantalla de carga (la mitad de su medida) |
| A los lados de la pantalla | `--page-gutter` | El margen de la TV (`--safe-x`, Ajustes › Márgenes de la TV), nunca menos de `--space-4` |
| Lo que ocupa la barra de arriba | `--status-room` | `--space-6` + `--safe-y` + `--control-height` |
| Del título a lo suyo | `--layout-title-to-content` | `--space-2` (el mismo 8 del iPhone) |
| Entre filas del Inicio y de Juegos | `--layout-between-sections` (`.home__scroll`) | Cada fila mide un alto fijo y la siguiente asoma; entre ellas, el mismo espacio de sección que en el resto de la app. En el Inicio, lo de arriba (`.home__hero`) ocupa lo que queda sobre la fila enfocada y nunca menos que lo suyo: no se mete bajo la barra |
| Entre tarjetas de una fila | `--card-gap` (`--space-8`), `--tile-gap` (`--space-4`), `--space-6` (tarjetas anchas) | Antes 1,85rem y 1,1rem, fuera de la escala (B1, 24 nov 2026) |
| Lo más ancho de un párrafo | `--measure-text` (36rem) | 45–75 letras por renglón (B6, 24 nov 2026): el texto de una hoja (`.sheet__subtitle`), el de un encabezado (`.screen-head__lead`), el de un vacío (`.empty-state__text`) y el del héroe |
| Dentro de una tarjeta | `--inset-poster` · `--inset-row` · `--inset-card` · `--inset-feature` | Un margen por tarjeta, igual en los cuatro lados (§ 3) |
| Entre botones de una fila | `--space-2` (`.button-row`) | Nunca se parte ni se corta |
| Alturas | `--control-height` (botón), `--pill-height` (píldora), `--menu-row-height` (opción), `--touch-target` (el dedo) | — |

### Reglas que salieron de recorrer todas las pantallas (2 nov 2026)

Cada una corrigió algo que se veía distinto en una pantalla poco común; las que se pueden revisar solas tienen su prueba.

| Regla | Dónde vive | Prueba |
|---|---|---|
| Una hoja del lado dice su título con un solo tamaño (`--type-heading`); el grande (`sheet__title--question`) es solo para una pregunta, un título que empieza con «¿». Un texto abajo no lo vuelve pregunta | `sheet.js` | smoke · `test_every_side_sheet_speaks_with_one_title_size` |
| **Texto y logos sobre el arte se leen (AA, P4, medido)**: el vidrio que lleva nombres es `--color-glass-legible`; el texto sin cápsula (pestañas `pill--tab`, contadores `row-count`, la cuenta de una categoría de TV) lleva `--shadow-text-strong`; todo logo sobre el arte lleva su sombra (`--shadow-logo`, o `--shadow-drop-sm` en la tarjeta). Medido con el texto invisible y el fondo real debajo (1920×1080 y 1280×800): todo pasa contra la mediana del fondo; lo que se desvanece a propósito (la tarjeta que asoma en la orilla, una fila sin foco) no cuenta. **R3-6 (11 nov): la medida estricta**, contra el 5 % más claro del fondo y sin contar la sombra: las pestañas de texto (`pill--tab`) y las consolas (`glass-switch__item`) van en blanco aunque no estén elegidas (la elegida la marcan su seminegrita y su raya, o la cápsula que viaja); la cápsula de lo elegido que viaja sobre el arte (la sección de arriba, la consola) es `--color-glass-selected-legible`, menos clara que `--color-glass-selected` (ese no cambia: el reproductor lo copia, `player_ui.GLASS_TOKENS`); LB/RB de la barra llevan de base el vidrio legible; la cuenta de la categoría elegida de TV en vivo, en blanco. Antes → ahora (1280 × 800, arte de Hades): «Con control» 2,8 → 4,9 · «PSP» 3,1 → 5,4 · «Steam» 3,8 → AA · «Juegos» 4,1 → 5,1 · LB/RB 4,7 → 5,5 · «47» 3,9 → 6,5 | `ui.css`, `status-bar.css`, `tv.css`, `title.css`, `card.css`, `themes/orbital.css` | humo · `test_contrast.py · test_text_on_art_passes_strict_contrast` (1920 × 1080 y 1280 × 800) |
| El origen de algo (Trakt, Letterboxd, Stremio, Orbital) es su logo en sus colores, a la altura de la letra, centrado con ella; nunca una placa de color con su nombre | `collection-card.js · SourceBadge`, `.source-logo` | — |
| Lo que crece al enfocarse tiene su aire arriba y a los lados dentro de su caja: nunca se monta en el título de su fila ni se le corta la sombra. Ninguna pieza enfocada se recorta, ya crecida y con su órbita, en ninguna fila ni rejilla (P4, 10 nov 2026: la de «A continuación» salía cortada 9 px por arriba; el aire es de la fila, `--row-grow` en `.home__viewport--*`) | `home.css`, `title.css`, `game-page.css` | smoke · `test_no_text_is_cut_in_half`, `test_focused_piece_is_never_cut` (Inicio, Juegos, Películas y series, TV en vivo, Buscar y la ficha, a 1920 × 1080 y 1280 × 800) |
| **Una cuadrícula larga arma solo lo cercano** (V4, P4): desde `LAZY_FROM` (60) portadas, cada casilla existe con su lugar, su tamaño y su `data-focus-id`, pero lejos de la vista es un hueco (`.card--slot`, sin imagen ni pie ni sombra); se arma lo que está a una pantalla de la vista y se vacía lo que quedó a más de dos. La enfocada siempre está armada. El foco, `keepInView`, la memoria de posición, la rueda y el dedo no cambian. Juegos, las listas y TV en vivo lo usan (R3, 11 nov: el hueco de un canal es `.tv__tile--slot`, del alto de una casilla; la vista previa sigue al enfocado y el salto de categoría rearma la ventana); el Top 10 no (diez, cada uno con su cifra) | `browse.js` (`windowCells`, `fillWindow`), `games.js`, `list-screen.js`, `tv.js`, `card.css`, `tv.css` | sí (humo, en un navegador: `test_long_grid_arms_only_what_is_near` con 300 juegos, `test_long_list_and_editing_your_list` con Mi lista de 300 y `test_live_tv_with_hundreds_of_channels_arms_only_what_is_near` con 400 canales: 400 armados antes, menos de 50 ahora) |
| Una cuadrícula que se desliza desvanece lo que quedó arriba (`is-above`, `browse.js · keepInView`) y lo que sigue abajo se funde; nada se corta en seco a media fila | `browse.css`, `list-screen.css`, `sources.css` | — |
| Un botón del mando en la esquina de una pieza solo si es corto (A, X, Y); el de teclado («Enter») lo dice el pie | `match-deck.js`, `button.css` | — |
| Un aviso no se encima con una hoja abierta: se corre a su izquierda, con su margen. En Juegos baja un piso, bajo el selector de consolas, sobre el arte (T12, 10 nov) | `toast.css` | — |
| Un texto recortado termina en palabra entera y «…», sin coma colgando (la sinopsis de la ficha, T10) | `dom.js · clampWords` | `text-trim.test.mjs` |
| Una cápsula de versión nunca empieza con « · »: el punto entre la bandera y el texto lo pone el CSS y se va con la bandera | `title.js · versionCapsule` | — |
| Un texto que viene de afuera se dice en español y sin ruido: los cargos de TMDB («Producer» → «Producción», «Self» → «Como sí mismo»), el nombre de una captura sin lo que pone Windows | `tmdb.py · role_es`, `menus.js · captureName` | `test_tmdb.py`, `menus.test.mjs` |
| Un pie no repite lo que ya dice su grupo (en «Películas», el año; no «Película · 2021») | `search.js` | — |
| En Ajustes, al bajar, la fila enfocada queda arriba del desvanecido de abajo (`scroll-padding-bottom` del mismo alto, `--space-12`; AJ-1, 25 nov 2026) | `settings.css` | — |
| Un botón de cuenta dice qué conecta, agrega o desconecta («Conectar Trakt», «Agregar clave», «Guardar clave», «Desconectar OneDrive»); lo seguro de una confirmación dice lo que protege («Dejarlo conectado», «No reiniciar») y el otro, su objeto («Reiniciar la consola», «Reiniciar Hades») (AJ-8, AJ-9, AJ-17, AJ-18) | `menus-settings.js`, `menus-cloud.js`, `menus.js`, `login.js` | `menus.test.mjs` |

| Un aviso largo con «Algo: lo demás» se parte en título y detalle; nunca termina en «…» | `toast.js · linesOf` | smoke · `test_special_situations_look_like_the_rest` |
| Un vacío (no hay resultados, no hay nada todavía) es el `EmptyState` del sistema donde iría el contenido, no una frase chica a un lado | `search.js` (y las demás pantallas) | smoke · `test_special_situations_look_like_the_rest` |
| Un error es vidrio fuerte con un filo rojo y su ícono en rojo (`toast--error`, `title__status--error`); ninguna tarjeta lleva franja de color a un lado | `toast.css`, `title.css` | — |
| Con el dedo, «Atrás» entra en la esquina de la hoja abierta, no montado en su borde | `touch-back.css` | — |
| El reproductor (mpv): una tarjeta sin renglón de arriba se acorta; sus capas se revisan pintándolas con el mpv de Orbital sobre un cuadro de prueba | `player_ui.upnext_ass` | — |

Las situaciones especiales que se revisaron a mano el 2 nov: el arranque y «Tu consola» de la primera vez, sin internet (Inicio,
Películas y series, TV en vivo), sin Stremio, la pantalla de carga con y sin arte, un juego abierto (el Inicio, el menú, sus opciones
y el aviso al volver), el protector, Buscar sin resultados, Explorar y Películas y series sin poder cargar, con el dedo, conectar
Trakt y Stremio, Actualizar Orbital, y el reproductor (reproduciendo, en pausa, adelantando, audio y subtítulos, volumen, avisos,
«Saltar intro», «¿Sigues viendo?», «¿Salir?» y con el dedo).

Las pantallas que recorre la prueba de texto partido: las cinco secciones, la ficha de un juego, el mazo, Decide por mí, el Filtro
avanzado, Colecciones, Panel rápido, Jugadores, Buscar con resultados y las siete categorías de Ajustes, en la tele y en la Legion Go
con la letra más grande.

### Juegos, TV en vivo y conectar (JT, 25 nov 2026)

La pasada del sistema base por Juegos, TV en vivo, Cambiar el arte, el visor de capturas, abrir un juego, los avisos y
conectar un aparato o Trakt (Fernando aprobó los 14 arreglos).

| Regla | Dónde vive | Prueba |
|---|---|---|
| **TV en vivo sin canales usa las piezas del catálogo** (C5 · C4, JT-1): si no llegó la lista, `ErrorState` («No pude traer los canales», qué no se perdió y «Reintentar», que la vuelve a pedir); si llegó vacía, `EmptyState` en positivo («Aquí salen tus canales en vivo») con «Buscar canales». X hace el botón con el mando o el teclado; con el dedo o el mouse se toca (`.tv__notice` deja pasar el toque al botón). Nunca el texto crudo del servidor («Connection reset by peer…») ni «Pulsa X» | `core/tv.js · emptyState`, `components/tv.js`, `app/tv-screen.js`, `core/hints.js · tvHints` | `tv.test.mjs` |
| **Un mosaico quieto no lleva sombra** (B10, JT-2): `.tile` (canales, Cambiar el arte, consolas) va con su filo (`--edge-hairline`) y la sombra llega con el foco (`--focus-lift`); la miniatura de TV en vivo, solo `--edge-strong` | `ui.css`, `tv.css` | — |
| De «Jugar» a las pestañas de filtro, 24 (B2, JT-3; antes 8): los filtros son de sus juegos, no del héroe | `games.css · .games__hero` | — |
| **Un filtro vacío dice en positivo qué saldrá y trae «Ver todos»** (C4 · C7, JT-4): «Tus favoritos de Switch salen aquí» y «Ningún juego de Steam en «Instalados»», con «Ver todos» (X, o el botón), que regresa a Recientes con el foco en su pestaña | `games.js · emptyFilter`, `core/hints.js · gamesHints` | `icon-meaning.test.mjs` |
| El nombre en una portada de respaldo usa el alto antes de cortar (C10, JT-5): la foto de la consola sube y se achica y el nombre llega a cinco renglones («Zelda Tears of the Kingdom» entero a 1280) | `card.css · .card--stand-in` | — |
| «Más de Steam» en la página de un juego: 48 de aire arriba (B3, JT-6; antes 24, quedaba más cerca de los botones que de su fila). Con letra «Muy grande» en una pantalla de 900 o menos de alto (la Legion Go), 24: con 48 el panel de lo tuyo se cortaba | `game-page.css · .game-page` | humo · `test_no_text_is_cut_in_half` |
| Si no se pudo guardar el arte elegido, se dice (C5, JT-7): aviso «No pude cambiar el arte de X» · «Se queda la de ahora» con «Reintentar»; antes no se decía nada y quedaba un error suelto | `art-picker.js · choose` (`onPickFailed`), `main.js` | — |
| El pie del visor de capturas (C10 · B9 · B7, JT-8): el nombre limpio (`captureName`), en placa de vidrio legible (`--color-glass-legible`) y «1 de 2» con cifras del mismo ancho | `viewer.js`, `viewer.css` | — |
| **Abrir un juego que falla no repite el título** (C5, JT-9): el detalle es la causa útil («Revisa que Steam esté abierto y con tu sesión iniciada», «Ryujinx no arrancó. Revisa que siga instalado»); lo que dijo el servidor solo si dice algo más que «No pude abrir X» | `app/launching.js · launchCause`, `api/play.py · humane_error` | `test_player_flow.py · test_errors_in_plain_words` |
| **La pantalla de carga dice qué abre** (C9, JT-10): «Esperando a Steam…», «Abriendo Ryujinx…» (o «Abriendo el emulador…»), luego «Preparando el juego…»; «Está tardando más de lo normal» a los 8 s (antes 15) | `launch-overlay.js · openingPhase`, `SLOW_MS` | — |
| **Un error de JavaScript nunca se enseña** (C5, JT-11): `serverDetail` calla los errores del código (`TypeError`…) y el texto técnico del sistema (en inglés, `[WinError …]`); el aviso genérico de un menú dice qué se intentaba con el nombre de la opción («No pude añadir a favoritos», `triedTitle`), no «No pude hacerlo» | `core/notices.js`, `main.js · runCommand` | `notices.test.mjs` |
| **Conectar un aparato sin túnel** (V5 · C5 · P2, JT-12): sin código no hay hueco del QR ni pasos que apuntan a él; la causa en palabras (sin `config.yaml` ni nombres de ajustes) y el botón dice «Reintentar» | `phone-link.js · blocked`, `phone-link.css`, `companion.py · tunnel_info` | `test_companion.py` |
| Conectar Trakt (u OneDrive) con error esconde la fila del código (C10 · C5, JT-13): ni la píldora negra vacía ni el QR | `trakt-link.js` | — |
| El reproductor no dice «Cargando…» a secas ni «Listo» solo (C9 · P2, JT-14): la tarjeta del siguiente sin nombre dice «Preparando el siguiente episodio…»; mandar al iPhone dice lo que pasó («Sigue en tu iPhone», «Enviado al iPhone») | `player_screen/cards.py`, `player_screen/menus.py` | — |

### Avisos (la regla, 2 nov 2026)

Un aviso dice una cosa, se lee de un vistazo y no se pierde. Valen para los de la interfaz (`toast.js`), los que manda el servidor
(`{"type": "toast"}`) y los del reproductor (`player_ui.toast_ass`). Prueba: `tests/web/notifications.test.mjs` (y
`test_player.py · test_player_notices_follow_the_same_rule_as_the_interface`).

| Regla | Cómo |
|---|---|
| Título y detalle | El título dice qué pasó; el detalle, qué sigue o por qué. Se escribe con `detail` (o « · »). Si llega una frase entera («No pude reproducir X. Prueba otra versión»), se parte sola por la primera frase o por «Algo: lo demás» (`linesOf`, `lines_of`): ningún título termina en «…» recortado; si es largo, cabe en dos renglones |
| Sin punto final, sin «!» | Un aviso no es un párrafo. «…» solo al final del título de lo que está en curso («Actualizando Orbital…»), que gira (`progress`) |
| Un tono por papel | `info` (pasó), `success` (quedó hecho), `warn` (funciona con un pero), `error` (no se pudo: dura más, se adelanta y suena), `progress` (en curso), `voice` (Alexa). Nada de otros tonos |
| Sonido | Un error siempre suena, venga de donde venga (`createToast({ onTone })`); el mismo sonido dos veces seguidas es uno (`sound.js`). Lo logrado suena a `success` desde quien lo hace |
| La cola | Uno a la vez, en orden; el mismo dos veces seguidas, una; un error, una cuenta atrás o una acción («Deshacer») se adelantan, y lo que estaba a la vista vuelve después, no se pierde; caben 4 esperando |
| Duración | La del iPhone (`--duration-notice`), más larga para un error; en el reproductor, nunca menos de lo que tarda en leerse (`toast_seconds`) |
| Dónde | Arriba a la derecha, bajo la hora; con una hoja abierta, a su izquierda; con el dedo y algo encima, debajo de «Atrás» |
| A dónde manda | Si dice «Ajustes › …», nombra una categoría que existe (Resumen, Ver, Complementos, Jugar, Tele y voz, Pantalla y sonido, Cuentas, Sistema) |
| Un error trae su arreglo (OT-3, C5, 20 nov 2026) | Todo aviso de error lleva `fix`: «Reintentar» (siempre esa palabra), «Abrir Ajustes», «Usar la recomendada»… Se toca con el dedo o el mouse, y con el mando o el teclado lo hace Y mientras se ve. El título dice qué pasó con palabras de Orbital («No pude abrir X», «Sin internet»); el texto del servidor va solo en el detalle, limpio (`core/notices.js · failure`, `serverDetail`). Los del servidor que no traen arreglo ofrecen «Abrir Diagnóstico». Prueba: `tests/web/notices.test.mjs` |
| Al volver del reproductor (FI-16/17, 24 nov 2026) | Un episodio dice cuál terminaste y cuál sigue («Severance» · «Terminaste T2 E7 · Sigue el E8», el título sin el episodio) y «Calificar la serie» dice qué se califica; sin terminar, en qué minuto quedaste («Guardé dónde ibas: 40 min de 2 h 46»). El reproductor lo anota en `last_end` (`episode`, `next`, `position`, `duration`) y `core/format.js · closedSummary` lo dice |
| Lo que dice una nota (FI-18, 24 nov 2026, B13) | Las estrellas que diste van con sus palabras («Me gustó · 4 de 5», las de `STARS`): nunca solo el color dice la nota |
| Lo que se borra se deshace (FI-19, 24 nov 2026) | «Borré esa vista» trae «Deshacer» (Y), como «Quitada de Mi lista»: `undoable` |
| Confirmaciones (C3, 20 nov 2026) | El botón seguro dice lo que protege («Conservar la lista», «Dejarla conectada», «Seguir jugando»), nunca «Cancelar». Los botones dicen verbo y objeto: «Continuar» a secas solo en el video a medias, y «Siguiente», «Aceptar», «OK», «Aplicar», «Enviar», «Omitir» o «Cargando…» nunca solos (X1-B). Prueba: `tests/web/button-words.test.mjs` y el revisor común (`tests/web/sistema-base.test.mjs`) |

### Piezas del lenguaje

| Pieza | Archivo | Para qué |
|---|---|---|
| `GlassSwitch(items, { label, onPick })` | `ui` | El selector de vidrio del segundo piso (las consolas de Juegos): cada opción con su foto y su nombre; la elegida en blanco tenue, la enfocada invertida; si no caben, las demás quedan en su foto (`glass-switch--compact`). |
| `FeatureHero(item, { runningId, glyphs, onAction, reason })` | `tiles` | El destacado sobre el arte del Inicio: porqué, logo o título, de dónde es y su dato, avance y botones. |
| `ConsoleHero(system, { glyphs, onAction })` | `tiles` | Lo de arriba del Inicio cuando enfocas una consola: «N juegos nuevos» como porqué, su nombre, «9 juegos · Jugaste Hades hace 36 min» y «Entrar» · «Seguir Hades». |
| `Card(item, { caption: "focus" })` | `card` | La portada que solo dice su nombre cuando está enfocada. Clic y clic secundario llegan por un solo oyente en el documento (V10, P4), no dos por tarjeta. |
| `Button({ variant: "primary" })` · `Button({ icon })` | `button` | El principal en blanco · el secundario redondo de vidrio con su nombre debajo. Margen a cada lado: la mitad de su alto (`calc(var(--control-height) / 2)`, C1, 24 nov 2026), con glifo o sin él y con mando o con el dedo; antes .7rem junto al glifo y 1,5 o 1,6rem del otro lado. |

### Revisión por pantalla

Cada pantalla de la TV, con su estado en el lenguaje. «Por las piezas» quiere decir que el cambio le llegó por lo compartido
(botones, foco, menús, vidrio) sin tocar su acomodo.

| Pantalla | Estado |
|---|---|
| Barra de arriba | Vidrio con íconos; la sección elegida, en blanco con su nombre; se va al bajar en Juegos. La pastilla «Buscar», centrada (14 nov): la lupa y el círculo de la tecla, concéntricos con sus puntas redondas (`.4rem` a la derecha, como arriba y abajo; `.625rem` a la izquierda, lo que la lupa es más chica); con el dedo, sin tecla, el mismo aire a los dos lados (`test_search_pill_is_centered`). En el iPhone, igual: una cápsula que se queda con una sola pieza (la de Inicio con solo tu foto mientras la TV reproduce) lleva el mismo aire a los dos lados (`DesignTests · testCapsuleWithOnePieceHasEvenAir`, 25 nov 2026). **IN3-A (Fernando, 26 nov 2026):** «Buscar» en reposo es su lupa (`--icon-md`, en blanco: chica y gris no se veía que ahí se busca) y su tecla; la palabra se abre de lado al enfocarlo o señalarlo, en `--duration-base` y sin rebote, encima del aire de su derecha (`.status-bar__search-slot` mide lo plegado: las secciones no se recorren). Con el dedo, un toque busca directo. En el pie del Inicio, «Menú» queda en su tecla y su nombre sale al señalarlo (`hints__item--collapsible`). **IN2-A (26 nov 2026):** a la izquierda de la hora, los controles (`.pad-lights`): la silueta de un control con cuatro focos encima, prendidos en `--color-orbital` tantos como jugadores (el 1 a la izquierda), en `--color-warning` el de batería baja y en `--color-danger` el casi vacío. Cuenta también los que XInput no ve (PlayStation, Switch Pro: winmm, sin batería, su foco prendido sin color de pila; «Jugadores» los nombra). La central USB de la Legion Go (17EF:61ED) no cuenta: Windows la ve siempre, con o sin controles (`gamepad.GHOST_HUBS`); los de la Legion cuentan en XInput (Legion L + RB), con su batería. Sin controles no se ve (MN-A), pero su hueco se queda: las secciones no se recorren al llegar el primero o irse el último. Su nombre («2 controles · Jugador 2 con batería baja», `format.js · padsLabel`) sale en una etiqueta de vidrio debajo al enfocarlo o señalarlo; A, un clic o un toque abren Jugadores. Llega con `/api/system` (`players`) y se pone al día cuando un control llega o se va (aviso `pads`) |
| Inicio | Rediseñado: «A continuación» (B), una sola fila con juegos, películas y series por lo último que usaste, una vez cada cosa (R2, 11 nov: lo que estás viendo ya no se corta tras los cuatro primeros: la serie que sigues en Trakt sale aunque haya más juegos recientes) (P4, 10 nov: «Seguir viendo» aparte repetía lo mismo y se quitó del Inicio); debajo, «Mi lista» y «Tus consolas» (D4-B, 10 nov). Lo de arriba sigue al foco: el episodio, la película de Mi lista o la consola con sus juegos y lo último que jugaste; ↑↓ (o LT/RT) pasan de fila y cada fila recuerda dónde ibas. **IN1-A (Fernando, 26 nov 2026):** las tarjetas de «A continuación» miden 440×248 en 1920 (antes 320×180) y caben 3½; ahí lo de abajo ya no asoma: abajo al centro, la señal (`ScrollCue`, colocada con `.home__cue`) dice qué sigue con el ícono de cada fila en el azul de Orbital («Mi lista», «Tus consolas») y la flecha; desde MN-A (27 nov) sin tecla. Al entrar al Inicio los íconos brincan tres veces, uno tras otro (`--duration-hop`), y se quedan quietos; un clic o un toque bajan. Mientras se ve, el pie no repite «LT RT»; lo dice «Cómo se usa» |
| **Menos ruido (MN-A, Fernando, 27 nov 2026; en todas las pantallas)** | Lo que no dice nada no se pinta: (1) sin controles, el indicador de junto a la hora no se ve (aparece al llegar uno); (2) la señal de abajo va sin tecla y la fila siguiente no asoma (Inicio y Películas y series, `ScrollCue`); (3) el redondo de «Ficha» o «Episodios» sale de los destacados (Inicio y Películas y series): X sigue abriéndola, el pie la dice chica («X Episodios», como pide § 5) y en ··· es lo primero, con «También con X» (con el dedo, sin esa pista: `sheet__hint--key`); un juego conserva «Con Ryujinx» (otra acción, no está en ···); (4) «Menú» del pie queda en su tecla en todas las pantallas (`hints__item--collapsible`). Lo que sale de la pantalla se dice en «Cómo se usa» (ahora con «Saltar (fila, grupo, consola o categoría) · LT / RT» y «RePág · AvPág»). Variantes vistas y no elegidas: MN-B (sin LB/RB, título gris, sin ☰) y MN-C (barra que aparece con ↑): https://claude.ai/artifact/JAiRVnsqCf9gfJuJDVxmkU |
| Juegos | Rediseñado: dos pisos y el juego a pantalla (A); la página de cada juego (C) en Opciones › «Ver ficha» (A sigue jugando directo). Al pasar de un juego a otro nada parpadea ni brinca (14 nov): el fundido corto de un juego nuevo no vuelve a empezar si aún va entrando; el logo entra cuando ya llegó (mientras, el nombre) y el porqué con el logo o el nombre van abajo de una caja del alto del logo más alto (`.games__head`), así los datos, los botones y la cuadrícula se quedan quietos (`test_switching_games_fast_does_not_blink`) |
| Películas y series | Por las piezas: héroe con «Ver» en blanco y secundarios de vidrio, portadas que se levantan. De fondo, el arte horizontal del título; de datos, solo el año (en «Lo nuevo de lo tuyo», antes el episodio «T2 E7»). El 11 nov 2026 Fernando deshizo T10 (el renglón con Trakt, géneros y duración, la oración de la sinopsis y el póster desenfocado de fondo): «dejemos solamente el año como estaba antes». La sinopsis vive en la ficha |
| La ficha | Por las piezas: «Ver» en blanco, acciones de vidrio, episodios que se levantan |
| Explorar | Por las piezas: el mosaico se levanta sin anillo; sus marcas, de vidrio |
| TV en vivo | Por las piezas: canales que se levantan |
| Buscar · Conectar Stremio | Buscar rediseñado (T7, 10 nov; P4 el mismo día): sobre el cielo del sistema (la luz de `--art-tint` arriba a la derecha sobre `--color-backdrop-deep`, no negro plano); a la izquierda el campo y un teclado compacto **alfabético de 7 columnas** (A–G, H–N, Ñ–T, U–Z, números debajo; sin tecla Atrás desde el 11 nov, B/Esc del pie la hace; `--keyboard-width` 24 rem, con el dedo 30 rem y teclas más altas; `createKeyboard` cuenta las columnas de la distribución, Conectar Stremio sigue en QWERTY de 10); a la derecha los resultados en vivo en la **cuadrícula de una lista** (`.card-grid`: la misma forma 2:3, el tamaño `--card-height` del sistema y el foco que crece 1.1 hacia adentro en la orilla), por grupo; sin portada, el nombre entero encima (hasta cuatro renglones); → desde la orilla del teclado entra y ← regresa; con la caja vacía, Recientes, Seguir viendo, Tus juegos y Por género, cada grupo con el encabezado de subsección (`SectionHead`, blanco, como una fila; antes gris y más chico) (lo popular vive en Películas y series, como el iPhone). Conectar Stremio, por las piezas |
| Menús, panel rápido, Opciones, confirmaciones | Menú flotante de vidrio |
| Elegir versión | Menú flotante de vidrio, abajo. La recomendada lleva un destello (`spark`, turquesa) antes de la calidad, como el iPhone; ya no la cápsula «Recomendada» en la esquina, que tapaba la marca del complemento (T12, 10 nov). La cuadrícula se funde solo del lado donde hay más (`sources__list--up` / `--down`): al llegar abajo, «Ver los demás» se ve entera. Lo enfocado nunca queda bajo el fundido: al moverse, la lista lo deja a 3 rem de la orilla y, cerca de la primera o la última fila, hasta la orilla, donde el velo se apaga (`sources.js · reveal`, R3, 11 nov; antes `scrollIntoView` lo dejaba a medias); si a la lista le sobra menos que el fundido, manda hacia dónde vas (14 nov: bajando, la última fila se quedaba cortada; `test_choose_version_last_row_is_whole_when_it_barely_overflows`); entre la lista y el renglón de lo que trae queda el hueco del panel. La demo sirve la ficha y las versiones de toda película o serie de sus filas sin internet (`demo_server.py · demo_row_title`) y `test_choose_version_is_whole_and_the_notice_does_not_cover` lo mide a 1920 × 1080 y 1280 × 800. Con la hoja abierta, el aviso sale abajo, sobre el pie, y en dos frases cortas («Esa versión ya no está.» · «Elige otra de la lista.», `playProblem`) (revisión 2, 11 nov) |
| Ajustes | Por las piezas: filas con foco invertido, `Segmented` en cápsula. Un solo título grande, el de la categoría (`display`), con «Ajustes» como etiqueta chica encima; la lámina mide lo mismo en todas las categorías y con el riel abierto (el riel la recorre, no la angosta; lo que sale se desvanece) (T10, 10 nov) |
| Calendario · ¿Qué vemos? · listas | Por las piezas: casillas y pósters que se levantan |
| Cambiar el arte | Por las piezas: casillas que se levantan |
| Pantalla de carga · arranque · avisos | Sin cambio (ya eran del lenguaje) |
| Reproductor (`player_ui.py`) | Botones en cápsula: el primero en blanco, los demás de vidrio (`player_ui.glass`, los números de los tokens); píldoras táctiles, panel de columnas (flotante), tarjetas y avisos de vidrio (8 nov 2026) |

## 1. Tokens (`orbital/web/styles/`)

| Capa | Archivo | Qué hay |
|---|---|---|
| Paleta | `palette.json` + `tokens.css` (`--palette-*`) | Los colores crudos. **Una sola paleta** para la interfaz y el reproductor (`player_ui.py` la lee del JSON). Una prueba verifica que coinciden. |
| Primitivos | `tokens.css` | Espacio (`--space-*`), radios (`--radius-sm` y `--radius-lg`, más la cápsula `--radius-pill`), letra (`--text-*`, `--weight-*`, `--tracking-*`, interlineado `--leading-*`), opacidad por lo que significa (`--opacity-*`: `off`, `away`, `near`, `faint`, `text`, y `solid` casi entero, `soft` lo que acompaña sin mandar, `dim` lo lejano, `grain` el grano del fondo), vidrio (`--blur-glass`), movimiento (`--duration-*`, `--ease-*`, `--delay-*`, `--stagger`), capas (`--z-*`), medidas de consola (`--card-*`, `--tile-*` —también `--tile-channel-width`, el canal de TV en vivo—, `--key-height`, `--sheet-width`, y las alturas de control `--pill-height`, `--control-height`, `--control-sm`, `--menu-row-height` y `--touch-target`; íconos `--icon-*` y trazo `--stroke-*`…). |
| Semánticos | `themes/orbital.css` | Lo que usan los componentes: `--color-*`, el borde fino por dentro (`--edge-hairline`, `--edge-strong`), `--shadow-*` (cajas) y `--shadow-drop*` (siluetas), el foco (`--focus-lift`), el vidrio (`--color-glass*`, `--edge-glass`, `--filter-glass`), foco invertido (`--inverse-bg/fg/scale`), sobre el arte (`--color-badge-bg`, `--gradient-tile-shade`), dentro de algo claro (`--on-light-*`) o de color (`--on-color-fill`), máscaras (`--mask-solid`), fondo de ambiente (`--color-backdrop-deep`), sombra sobre el arte (`--color-art-shade`), relieves (`--gradient-console-tile`, `--gradient-launch-planet`), `--color-star`, `--color-video-bg`, `--assistant-accent`, el grafito neutro del arte (`--art-*-neutral`) y el color de cada consola (`--system-*`). |

**Compartido con el iPhone: `design/tokens.json`** (paleta, papeles, espacios, radios, duraciones, opacidades, recetas de
texto) y **`design/vocabulario.json`** (lo que las dos apps dicen igual: «Mi lista», «Ver la serie», «Seguir viendo»…).
`tests/web/design-parity.test.mjs` compara `tokens.css`, `themes/orbital.css` y el código Swift del iPhone contra esos dos
archivos: cambiar un valor o un texto en un solo lado falla CI. Las diferencias a propósito (la superficie, ink-900 aquí
e ink-850 en el iPhone) van en el JSON con su `porque`.

**Recetas de texto: las mismas del iPhone** (`DS.TextRecipe` ↔ `--type-<receta>` + `--type-<receta>-weight`; la fuente de
verdad es `design/tokens.json` › `type`). Cada receta es un tamaño y un grosor que van siempre juntos: un componente pone
`font-size: var(--type-X); font-weight: var(--type-X-weight)` y nada más. **Torcer una receta con otro grosor no se vale: si
hace falta otro, es otra receta** (como hizo el iPhone con `label`, `labelLarge`, `badge`…). Los grosores se llaman como en el
iPhone: `--weight-regular` 400, `--weight-semibold` 600, `--weight-bold` 700 (el iPhone tiene además `.heavy`, 800, solo para `stat`;
la TV no lo define desde TB-06).

| Receta | iPhone | TV | Grosor | Para qué |
|---|---|---|---|---|
| `display` | largeTitle | 3xl | bold | El título de una pantalla grande |
| `title` | title | 2xl | bold | El título de una pantalla o de un destacado |
| `section` | title2 | lg | bold | El título de una fila o subsección |
| `card-title` | headline | sm | semibold | El nombre en una tarjeta, una opción de menú |
| `body` | body | sm | regular | El texto de lectura |
| `secondary` | subheadline | sm | regular | Lo que acompaña: datos, sinopsis corta |
| `footnote` | footnote | sm | regular | Notas, créditos, la leyenda |
| `caption` | caption | 2xs | regular | Lo más chico: pie de tarjeta |
| `eyebrow` | footnote | sm | semibold | El porqué en turquesa, sobre un título |
| `data` | footnote | sm | regular | Números (siempre `tabular-nums`). B7 (24 nov 2026): también todo contador que cambia aunque use otra receta: `.list-screen__count`, `.decide__filters-count`, `.tile--console__count` (y los de siempre: la hora, la pila, `RowCount`, los chips) |
| `label` | footnote | sm | semibold | Un rótulo o botón chico |
| `label-large` | subheadline | sm | semibold | El valor de un control, un nombre en un renglón |
| `badge` | caption | 2xs | bold (TV: semibold, TB-06) | Una placa («4K», «Nuevo») y los glifos del mando |
| `group-label` | caption | sm | bold | El rótulo de una sección, en mayúsculas (un paso más grande en la TV: se lee de lejos) |
| `stat` | largeTitle | 2xl | heavy (TV: semibold, TB-06) | Una cifra grande (siempre `tabular-nums`) |
| `heading` | — | xl | bold | Solo la TV: un encabezado de zona entre `section` y `title` |
| `hero` | — | 3xl | bold | Solo la TV: el título del destacado a pantalla completa |

**Un componente usa la receta, nunca el tamaño de la escala** (`--text-*` es de los tokens). Las pruebas lo vigilan:
`design-system.test.mjs` (cada tamaño con el grosor de su receta; `data` y `stat`, tabulares) y `design-parity.test.mjs`
(misma receta, mismo estilo de Dynamic Type y mismo grosor en los dos lados; una receta solo de la TV dice por qué).

**Espacios de una pantalla, los del iPhone (`DS.Layout`):** del título a lo suyo `--layout-title-to-content` (8), entre
subsecciones `--layout-between-subsections` (24), entre secciones `--layout-between-sections` (32). En la TV se usan donde se
apilan partes (lo de abajo de la ficha, Cambiar el arte, TV en vivo); entre las filas de alto fijo de Inicio, Juegos y
Películas y series manda el alto de cada fila, y al pie va el pie de pistas (`--hints-room`) en lugar del 64 del iPhone.

**Jerarquía de encabezados (iPhone, 30 oct 2026; regla A del 31 oct):** dos niveles y nada más, una sola pieza (`DSSectionHead`).
Una sección es el **rótulo**: ícono gris, el nombre en letra normal (`groupLabel`, sin mayúsculas espaciadas desde el 2 nov 2026) y una línea fina hasta la orilla
(`DSChapterLabel`, el mismo de `DSChapterHead`). Lo de adentro son subsecciones con título blanco.

| Nivel | Receta | Lleva | Ejemplos |
|---|---|---|---|
| Pantalla | barra nativa / `display` | — | «Para ti», «Buscar» |
| Sección (`level: .section`) | rótulo (`groupLabel`, letra normal) + ícono gris (`symbol:`) + línea | solo el rótulo (y a la derecha un dato o «Ver todo») | Plataformas, Premios, Temporadas, Día por día, Descargando |
| Subsección (por omisión) | `section` | título blanco; su porqué arriba en `eyebrow` turquesa solo si ayuda | En tendencia, Seguir viendo, Próximas temporadas, Tus 5 estrellas |

**Espacios (iPhone, decisión 2 del 31 oct 2026):** cuatro medidas, en `DS.Layout`, medidas desde donde termina lo que se ve
(el pie de un póster cuenta; los reflejos se quitaron de toda la app el 2 nov 2026): del título a lo suyo **8** (`titleToContent`), entre
subsecciones **24** (`betweenSubsections`), entre secciones **32** (`betweenSections`) y
al pie de la pantalla **64** (`screenBottom`). Arriba de cada pantalla, 8 (`screenTop`). (12 y 56 hasta el 20 nov 2026: D3-B.)
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
| Selector | `DSSelector` · `DSKindFilter` · `DSTextTabs` · `PanelChip` · `FilterChoice` | Una sola pieza para elegir (SL1, Fernando, 13 nov 2026: «el selector unificado»). **Elegir qué ves aquí** → `DSSelector`: un riel de vidrio con la elegida rellena en blanco; completo (ícono, cifra y nombre: Guardado) o normal (nombre, con ícono si ayuda: Decide por mí, Lo que ves, Mi media, Versión, De dónde, Modo, energía, Quiero · No quiero, el estado de una serie). Todo · Películas · Series es su tamaño compacto, `DSKindFilter`, y dice el nombre de lo elegido (KT1). **Moverte entre partes** → pestañas subrayadas (`DSTextTabs`): Biblioteca, la ficha y el reproductor; subrayado es «dónde estás», relleno es «qué ves aquí». **Elegir varios** → cápsulas (`PanelChip`). **Elegir uno grande** → mosaicos (`FilterChoice`). Antes eran cinco caras (pestañas con cifra, el segmentado de iOS, pestañas para elegir). `testOneSelectorEverywhere` lo cuida. **Un solo tamaño (SZ1, 23 nov 2026):** junto a un título o arriba de una pantalla, todo lo que se elige o se toca de vidrio mide 44 de alto: la pastilla de tipo (`DS.KindPill.cell` + su orilla) en Inicio, Explorar, el Top 10 y las listas; el botón redondo junto a un título (`DSIconButton(size: .selector)`: calendario, Canales); «Ver en la TV» (`ConfirmIconButton`) y la cápsula del control y tu foto. Antes había 32, 34, 38, 42 y 57. `testSelectorsShareOneSize`. | Distinto a propósito en la TV: pestañas con ‹ › para el mando |
| Muestra de idioma | `LanguagePreview` | En Ajustes › Idiomas, debajo de los dos mosaicos (IP-C, 24 nov 2026): al tocar Español o English, la barra de pestañas de juguete cambia sus palabras una tras otra y el póster de mentira da una vuelta con su nombre y sinopsis en el idioma nuevo. Con «Reducir movimiento», solo cambia el texto. | Solo del iPhone: la TV no tiene esta página |
| Marca de idioma | `LanguageMark` | En Ajustes › Idiomas (IM-A, 24 nov 2026: las banderas se veían genéricas): las letras del idioma («ES», «EN», «LAT», «CAS») en un círculo de su color; el idioma original, un globo. El mismo idioma siempre del mismo color. | Solo del iPhone |
| Búsqueda avanzada | `filter-panel` | Distinto a propósito: en filas con ‹ › (se maneja con el mando), sin premios ni estudios (viven en Películas y series y en Colecciones) | ☰ › Filtro avanzado; cada filtro con su color del arcoíris solo en su ícono; los resultados en `list-screen`. |
| Marcar como vista | «¿Cuándo la viste?» (`yours-commands.js` · `watchedMenu`) | Distinto a propósito: «Otro día…» ofrece días comunes (ayer, hace una semana…) en lugar del calendario | En la ficha y en Opciones, con Trakt; la serie entera dice «Cuando salió cada episodio». |
| Vacío | `DSEmptyState` · `VersionsEmptyCause` | Ícono, título y una línea; sus botones, de vidrio. «Versión» sin versiones (V4, `Design/Versions.swift`): la causa de la tabla de «Ver» (`UnavailableCause`, `SourcesModel.emptyCause`) en un `DSEmptyState`: su ícono (`UnavailableCause.symbol`, el mismo del reproductor), la frase y su única salida con ícono (Renovar, Ajustes, Reintentar). Un complemento que no contestó dice «no sé si hay versiones» con Reintentar, nunca «no hay». Nunca una hoja en blanco (9 nov 2026). | sí |
| Lista de versiones | `VersionLanguageList` · `VersionListRow` · `VersionGroup` · `VersionGroupHeader` · `VersionPreview` · `VersionMark` (`Design/VersionList.swift`) | «Versión» (V1 + V3, Fernando, 9 nov 2026): renglones, no cápsulas. Tu idioma primero con su bandera de encabezado; los demás bajo «Otros idiomas», con la bandera y el nombre en cada renglón. Cada renglón: ✦ si es la recomendada (su lugar se aparta aunque no la lleve), la calidad, los íconos de estado (⚡ al instante, la nube `DS.Symbol.cloud` hay que pedirla o cómo va, el triángulo solo si Real-Debrid no la dejó bajar, `questionmark.circle` «tal vez») y el tamaño a la derecha. Tocar reproduce (o la pide); mantener presionado da `VersionPreview` (cómo sabemos el idioma, qué más trae, de qué complemento) y Descargar, Infuse y las otras de ese idioma y calidad. Sin pestañas arriba: «Ver todas las versiones · N» al pie; en un episodio, «¿Para el resto de la serie también?» solo después de elegir otro idioma. Cada renglón con su etiqueta hablada. El reproductor usa la misma lista. | — |
| Tarjeta | `DS.surface` · `DS.Radius.lg` | Las tarjetas y renglones van en `surface` con `Radius.lg`; las destacadas (una por pantalla: «¿Qué vemos hoy?», «La temporada», «Por lo que viste») en `Radius.xl`. Los rellenos dentro de una tarjeta, `DS.fill`. | — |
| Hoja con encabezado propio | `dsSheetContent()` · `DS.Space.sheetTop` | Toda hoja sin barra de navegación (calendario, «Tu Orbital», Decide por mí, Guardar en…, Versión, Stremio) deja 24 pt del asa a su primer título y el margen de siempre a los lados; `sides: false` si un carrusel llega a las orillas. | sí |
| Aviso | `Toast` · `dsNoticePlacement(lift:)` · `DS.Toast.gap` | Abajo, al alcance del pulgar, y siempre a 8 pt (`DS.Toast.gap`) de lo que tenga debajo: la barra de pestañas, «Viendo en la TV» o lo que la pantalla deje flotando (el pie del mosaico lo declara en `AppUI.noticeLift`). Nunca un margen a ojo. La pastilla de calificar va en el mismo lugar. Uno a la vez: el nuevo reemplaza al que solo informa y espera detrás del que trae salida («Deshacer»). Una acción que tarda avisa al tocar («Mandando a tu Orbital…») y confirma al terminar («Ya está en tu Orbital»). (30 oct 2026) | sí |
| Etiqueta | íconos antes que texto | Nada de cápsulas de texto para estados; un ícono o el dato tal cual (`DSBadge` solo sobre el arte o «HOY»; «Nuevo» sobre un póster: el listón turquesa en diagonal de la esquina, en la TV (`CornerRibbon`) y en el iPhone (`DSCornerRibbon`); el 11 nov 2026 Fernando deshizo el puntito y pidió volver a la cinta). | — |
| Editar una lista tuya | `DSBookmarkToggle` · `DSRemoveMark` · `ListEditToolbar` · `AddToListSheet` · `.listEditable` (`Design/ListEditing.swift`) | Solo en Mi lista y tus listas de Trakt (`TitleActions.isEditable`); un ranking, un catálogo o Para ti no parecen editables. El marcador de Mi lista en un póster es un botón (44 pt) que quita sin preguntar, con «Deshacer» en el aviso; «Editar» · «Listo» y «+» en la barra (⌘E, ⌘N): en edición cada póster lleva el «−» rojo en la esquina y deja de abrir la ficha; mantener el dedo o clic secundario: «Quitar de esta lista». Cambia al instante y, si Trakt no acepta, regresa y lo dice (Fernando, 6 nov 2026). | — |
| Elegir varios (Guardado) | `ListSelection` · `DSSelectMark` · `.selectable` · `.selectionDrag` · `ListSelectToolbar` · `SelectionHeader` · `DSSelectionBar` · `DSSelectionBarLabel` (`Design/ListSelection.swift`) | G3-A (Fernando, 10 nov 2026): en Guardado (Mi lista, tus listas y los montones del tablero) «Editar» elige en lugar del «−»: cada toque elige (círculo arriba a la derecha; los no elegidos se apagan), deslizar de lado elige de corrido, «Todas» junto a la cifra, y abajo, encima de las pestañas (nunca se esconden), la barra de ícono con nombre con solo lo que aplica ahí (`SavedModel.batchActions`). Un solo aviso con «Deshacer» para el grupo. ⌘E, ⌘A, Esc y ⌫. Las demás listas (Ver todo) siguen con el «−» por ahora. | — |
| Manejar tus listas (Guardado) | `SavedListManagement` · `ReorderListSheet` (`Screens/SavedListMenu.swift`) · `ListFilterMenu.manualOrder` | G4-A (Fernando, 10 nov 2026): cada lista tuya lleva «···» arriba a la derecha con Cambiar nombre, Quién la ve (candado, enlace, globo), Ordenar a mano (hoja con agarraderas), Duplicar, Compartir enlace (si es «Solo tú», pregunta antes de abrirla con el enlace y lo copia) y Borrar lista (confirma; no se deshace; vuelve al tablero). Mi lista no lo lleva: «Ordenar › A mano…». El tablero suma «Nueva lista» al final de «Tus listas». Sin internet, todo apagado y el menú dice por qué. | — |
| Tus vistas, tu nota e Historial | `ViewingsLine` · `ViewingsSheet` · `ViewingDatePicker` · `NoteSheet` (`Screens/TitleView+TusVistas.swift`) · `HistoryScreen` | O3-B (Fernando, 10 nov 2026): en la ficha de una película vista, bajo tu calificación, «La viste N veces · la última, el…» abre cada vista con fecha y hora (tocar cambia la fecha; el bote borra solo esa, con «Deshacer»; «La vi otra vez…»); en un capítulo visto, mantener el dedo › «Tus vistas…». «Tu nota» (ícono de nota, «+» o «›»): privada; con Trakt VIP vive en Trakt (hasta 500 letras, con contador) y, sin VIP, solo en el iPhone, y la hoja lo dice. Guardado › Vistas lleva el reloj de «Historial»: por mes, las repetidas en ámbar con «Repetida» y «Borrar N vistas repetidas» arriba (confirma). Estrellas de la temporada bajo «N de M vistos» («La temporada»). Sin internet, lo que cambias espera en la cola y la fila lo dice. | — |
| Texto sobre arte | `ArtVeil` | Todo texto encima de un póster, fotograma o fondo desenfocado va sobre su velo (`bottom`, `top`, `both`, `full`, `leading`; `soft`, `strong`, `deep`). Nunca un degradado a mano. | sí |
| Cargando | el esqueleto de su forma · `DSLoadingState` | Una lista o fila carga con su esqueleto (`FeedSkeleton`, `ShelfSkeleton`, `CheckRowSkeleton`); un área que no es lista, con `DSLoadingState`. Junto a un botón, el indicador chico con su texto («Conectando…»). **Tirar para actualizar**, siempre la luna de Orbital (`orbitalRefreshable`; en una `List`, `orbitalRefreshableList`), nunca la ruedita del sistema (23 nov 2026: en Descargas salía la otra; `testPullToRefreshIsAlwaysTheOrbit`). | sí |
| Sin conexión o error | `DSErrorState(offline:retry:)` · `DSNotice` | Un área que no llegó dice «Sin conexión» o «No se pudo cargar» con «Reintentar»; nunca un vacío que diga «nada» cuando lo que pasó es que no llegó. Dentro de una sección, `DSNotice`. | — |
| Problema con su arreglo | `DSProblem` · `dsProblemFix(primary:)` | Qué pasa en ámbar con su ícono, por qué en gris y el arreglo de un toque debajo; arriba de la página y solo cuando pasa (3 nov 2026, P3-B y P6-A). Un aviso sin salida es `DSNotice`. | sí |
| Números y fechas | `Strings.count` · `Strings.date` | En el idioma de la app, no en el del teléfono: «1000» sin separador hasta 9999 y con espacio fino después; «jueves 12 de agosto». Nada de `.formatted()` ni `DateFormatter` en las pantallas. | sí |
| Logos de marca | a la misma altura *visual* | Los logos que van juntos (IMDb, TMDB, Rotten Tomatoes; las plataformas) se ven del mismo tamaño, no miden lo mismo: una palabra larga (TMDB) va más baja (`DS.RatingBrand.wordmarkScale`). | — |
| Lo que se mueve solo | El mosaico se detiene a los 90 s (con el protector, avanza a pasos); todo respeta movimiento reducido | Igual | La TV no tiene cielo que se mueva: Orbital no gasta detrás de un juego. |
| Pedido a Real-Debrid | `DebridRequestStatus` · `DebridRequestSheet` · `DebridWhereLine` · `DebridNotifyPrompt` (`Design/DebridRequests.swift`) | Un estado de pedido (R13) lleva su ícono propio y su palabra (`DebridRequestWords`), nunca solo color; el problema (rechazado, sin gente, atorado) en ámbar. «¿Qué es esto?» (O2) abre `DebridExplainer` donde surge la duda. En la ficha, «Pedirlo y avisarme» es el botón principal (`ContinueAction` con `aside`: «Verlo en inglés al instante» o «Cancelar pedido»). (Fase 2, 3 nov 2026) | — |
| Explicación «¿Qué es esto?» | `DebridExplainer` · `DSExplainerCard` · `DSIconTile` · `DebridFlowStrip` (`Design/Explainer.swift`) | Una idea por tarjeta (`.dsCard(.card)`): su cuadro de color de 44 pt (crece con la letra hasta ×1,4) con el símbolo centrado en su color de `DS.ListTint` sobre ese color al 18 %, centrado con el título y la explicación. En Real-Debrid y los pedidos, arriba, los tres pasos animados «Tú lo pides → Real-Debrid lo baja → Arranca al instante» (cuadros de 56 pt; uno se enciende cada 1,6 s con `DS.Motion.spring` y el símbolo brinca; con «Reducir movimiento», los tres quietos y encendidos). La hoja se mide sola (`fittedScrollSheet`) y se desplaza si no cabe. Nunca turquesa: no es la voz. (Fernando, 3 nov, probando la 1729.) | sí |
| Botón principal de la ficha | `ContinueAction` · `SplitPlayButton` (`Design/SplitPlayButton.swift`, medidas en `DS.SplitPlay`) | L3 (Fernando, 11 nov 2026): «Ver» partido; la izquierda reproduce y la derecha («🇲🇽 1080p ⌄») abre «Versión». Es el único selector de versión de la ficha: no hay renglón aparte (docs/ios-interfaz.md § «La versión vive en el botón», `DesignRulesTests+Version`). Sin versión que elegir, el botón va entero; mientras se busca, la derecha en gris con su ancho. |
| Versiones por pedir | `VersionRequestGroup` · `VersionRequestRow` (`Design/VersionRequests.swift`) · `SourcesModel.toRequest` | En «Versión», después de las de al instante, «Hay que pedirlas · tardan»: una por idioma y calidad que no salga ya como cápsula, con idioma, calidad, tamaño y «Pedirlo y avisarme». Nunca «Ver» (abrirla saca el video de aviso de Real-Debrid); ya pedida, su estado (`DebridRequestStatus`). La cápsula de una así dice «Por pedir» con ↓; su tarjeta y «Todas las fuentes» también piden en lugar de ver (T8-A). | sí |
| Confirmación importante | una hoja propia (`DebridRedeemSheet`) | Lo que hay que explicar antes de hacerlo (qué pasa, que no se deshace) va en su hoja con su botón principal y «Ahora no», a la medida (`fittedSheet`); un sí/no corto y destructivo («¿Quitar?») sigue siendo la pregunta de iOS. Un botón de acción dentro de una lista es del sistema de diseño (`dsSecondaryButton`), no el renglón azul de iOS. | sí |
| Complementos y Torrentio | `AddonRowLabel` · `AddonHealthLine` · `AddonWhat` · `TorrentioWords` · `TorrentioProbeRow` (`Design/AddonPieces.swift`) | Cómo le va a un complemento con ícono de forma distinta y palabra (nunca solo color): contesta (✓ verde), lento (tortuga) y no contesta (ámbar). Cada opción de Torrentio dice qué es en una línea gris (`TorrentioWords`); lo raro va en «Más opciones». La prueba con un título va en la misma página y trae su arreglo de un toque. «¿Qué es esto?» es `DebridExplainer(topic:)` (Torrentio, Complementos, Real-Debrid). (Fase 3, 3 nov 2026) | — |
| Tu lista y la de tu TV | `AddonTVStatus` · `AddonTVOnlyRow` (`Design/AddonTVPieces.swift`) | Dónde está la lista con la de tu TV en un renglón con ícono y palabra (igual ✓ verde, no contestó en ámbar, lo que espera las llaves con una llave gris: es calma, no error); lo que es solo de la TV, «Archivos de la TV · Solo en la TV». Solo en Ultra con TV emparejada (S4). (Fase 4, 3 nov 2026) | — |
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
| Familia | Familiar | el género (Por género y el filtro avanzado; 2 nov 2026) |
| Fama | Qué tan conocida | el filtro de qué tan vista es (fama × calificación; 2 nov 2026) |

**Textos cortos y que no mienten.** Un porqué cabe en un renglón en un iPhone SE (38 letras como máximo) y no lleva cifras
fijas («Más de 50 formas» mentía si había menos). Sin jerga («Al instante»). La prueba los mide.

**Antes de cerrar una pantalla.** Se revisa en cuatro combinaciones: claro y oscuro, en un iPhone SE y en uno grande
(`scripts/ios_capture_matrix.sh`). Varios errores de esta revisión solo se veían en una de las cuatro.

**Espacios.** Entre secciones de una pantalla, `DS.Layout.betweenSections` (32) en todas: Inicio, Para ti, Buscar, Lo que ves,
Colecciones, Mi media, una persona, la hoja de Canales. Del encabezado a su contenido, `DS.Space.s2`. Entre renglones o
tarjetas de una lista, `DS.Space.s2`. A los lados, `DS.Space.gutter`. Los grupos dentro de una misma lista (las décadas de una
colección) van más juntos (`s6`): no son secciones. En Para ti, las colecciones en carrusel se separan con `groupGap` porque su
reflejo ya pone el resto del aire.

**Listas con rótulo por sección (Descargas, 2 nov 2026, I2).** Cuando el rótulo de una sección es el primer renglón de una
lista agrupada, va con `listHeadRow()` y la lista con `listHeadRows()`: el rótulo a unos 20 pt de su tarjeta y unos 40 entre
secciones (antes 34 y 67, por el alto mínimo de renglón del sistema).

**Interruptores (2 nov 2026, J2–J4).** Todos con el estilo nativo y prendidos en el turquesa de la marca (`DS.switchOn`, puesto
una vez en `OrbitalApp` con `DSSwitchStyle`); apagados, el gris del sistema. Dentro de un menú siguen siendo palomita
(`.toggleStyle(.automatic)`). Nombre corto en un renglón y, si hace falta, la explicación abajo en gris (`DSToggleRow`); un ajuste
que vive en Ajustes y se usa en otra pantalla va ahí también como interruptor (el mismo ajuste), no como una nota.

**Íconos que dicen una idea.** «Automático» son dos flechas en círculo (`DS.Symbol.automatic`), nunca la chispa de la IA. Un
ícono que no dice solo lo que hace lleva su nombre debajo: el anillo de una descarga en pausa dice «Seguir»
(`DownloadRingButton`, el mismo en Descargas y en la fila de un episodio).

**Un ícono por idea (TV, R2, 11 nov 2026).** `list` es «Episodios» y las listas; «Versión» es `hd` (la calidad); «Filtro
avanzado» es `sliders`, nunca la lupa (la lupa es Buscar); el iPhone es un solo botón `phone` («Al iPhone», que abre
«Enviar al iPhone» y «Descargar en el iPhone»). «Versión» va en un solo lugar: la cápsula junto a «Ver» (con su Y adentro)
o, si no hay cápsula, su botón; el pie no la repite. El pie dice lo mismo que el botón enfocado; **FI-2 (24 nov 2026, V1; Fernando, 25 nov: «haz una sugerencia y ejecútala», se queda así):** si
el redondo ya está prendido, el pie dice su verbo y no su estado (`verb` en `core/watch.js`): «Quitar de Mi lista» (A la quita,
con «Deshacer»), «Ver tu pedido», «Borrar la descarga» (A abre la hoja que lo confirma); con «Viendo», «Vista» o «La dejé», A
abre «¿Cómo vas?» y el pie no lo repite en X. El nombre bajo el botón sigue diciendo el estado.
En la lista de episodios, el que sigue lleva ▶ sobre su imagen (sin cápsula «Sigue»). La clasificación se lee
«Clasificación B», nunca una letra suelta que parece el botón B.

**Lo que se corrigió en Ajustes › Resumen (TV, 20 nov 2026; regla dura 16):**
- Un ícono, un significado: el destello (`spark`) es solo Explorar (su pestaña, su pantalla y sus listas) y la versión
  recomendada (VR-A, Fernando, 20 nov 2026: se queda, igual en el iPhone; si un día se cambia, en los dos). Trakt es la cadena `link`, «Decide por mí»
  el dado `dice` (como el iPhone), un género la etiqueta `tag`, el canal «Orbital 24/7» el reloj y la clave de MDBList el
  trofeo. En el iPhone, «Aprende» es el birrete (`DS.Symbol.learn`, `testSparklesOnlyMeansDiscover`). Mapa de ícono a idea (OT-5, 20 nov 2026): ↻ es hacerlo otra vez; deshacer es `undo`; «Desde el principio» es `fromStart`;
  reiniciar es `restart`; ★ es calificar; ♥ es favoritos (`heart`, `heartFill`, `heartOff`); el marcador es guardar; Premium es
  `premium`; «Para hoy» es la tachuela (`pin`). Prueba: `tests/web/icon-meaning.test.mjs`.
- La ayuda al pie nunca repite el renglón: dice qué abre o para qué sirve («Abre lo último que llegó por voz y de dónde
  vino»); si no tiene nada nuevo que decir, se calla (`menus-settings.js · footerHelp`). Prueba: `tests/web/settings-summary.test.mjs`.
- Un botón dice verbo y cosa («Conectar Trakt», «Conectar tu nube», «Ver complementos»), nunca «Conectar» o «Ver» solos, y
  el pie dice lo mismo que el botón (`action` del renglón). Prueba: `tests/web/settings-summary.test.mjs`.

**Una sola escala de clasificación por idioma (12 nov 2026, Fernando).** En español, la mexicana; en cualquier otro idioma,
la de EE. UU.; nunca se muestra el dato crudo de otro país. Sin la de su escala se convierte la otra (R → B15, TV-MA → C).
La tabla es `design/clasificaciones.json` (la misma del iPhone); la TV la aplica en `orbital/library/certification.py` con
el idioma de las fichas y sirve `certification` ya elegida: la web nunca elige ni convierte. `tests/test_certification.py`
corre los casos del archivo.

**La versión en un renglón.** «🇲🇽 · 1080p»: la bandera sola, sin el nombre del idioma (la bandera ya distingue latino de
castellano; sin bandera conocida, el nombre). VoiceOver lee el nombre. Bajo «Continuar», en la cápsula de la versión de la
serie (sin ícono de lista) y en el reproductor (2 nov 2026, M2 y N2).

**Títulos de navegación.** Las pestañas (Explorar, Biblioteca, Buscar) llevan el título grande en el renglón de los botones
(`.inlineLarge`): grande arriba y chico al centro al deslizar, siempre el del sistema, nunca uno hecho a mano (HB1, 23 nov
2026: Explorar llevaba el suyo y no se encogía). Inicio, el logotipo. Lo que se abre encima va en `.inline`, salvo las
pantallas con su propio encabezado en grande (Lo que ves, Colecciones). Prueba: `testTabsShareTheSystemHeader`. El título
siempre en el idioma de la app, también si cambia con la pantalla abierta: un título fijo va por `.dsNavigationTitle("…")`
(TN1, 25 nov 2026: «Idiomas» seguía en español con la app en inglés). Prueba: `testNavigationTitlesFollowTheLanguage`.
Toda frase que se ve en pantalla tiene su inglés, también las que empiezan con un dato o un número («en 3 meses», «de 10»,
«\(n) por ver») (T2, 25 nov 2026). Prueba: `python3 scripts/ios_strings.py --check` (en la CI, `tests/test_ios_strings.py`).
Lo que llega de la TV en español (las teclas del control, la sección) también se traduce: pasa por el catálogo con `Text(tv:)`, nunca tal cual (CT1, 25 nov 2026; `DesignRulesTests.testRemoteTranslatesWhatTheTVSends`).

**Acentos.** Turquesa: el porqué, lo nuevo y lo de hoy («Nuevo», «Hoy») y lo que está en vivo. Ámbar: las estrellas de calificar y los avisos. El verde de `success`: solo «listo, conectado». El color del arte: el botón principal de un título y su fondo.

**Texto tenue vs. adorno:** `--color-text-faint` (gris opaco #868687, ≥ 4,5:1) es texto que se lee; `--color-decorative`
(ink-500) solo adornos que no se leen, como la cifra grande del Top 10.

**Los componentes solo usan tokens semánticos** (o primitivos de medida y movimiento): nunca `--palette-*` directo. Un valor nuevo
primero se nombra aquí: qué *es* (`--duration-enter`, «algo que aparece»), no cuánto vale.

### Decisiones del 2 nov 2026 (iPhone, canvas «unslop vs Impeccable»)

Fernando dictó qué aplicar del canvas (códigos A1…O2) y pidió que cada cambio sea regla de todo el sistema: «cuando te pido
un cambio, impacta el sistema de diseño y modifica todo lo demás que esté igual». `DesignDecisionsTests` (OrbitalCore) las
vigila.

| Regla | Cómo | Prueba |
|---|---|---|
| «Ver todo» es la flecha pegada al título; todo el encabezado abre la lista | `Text.withTitleChevron()` (dentro del texto del título, centrada con su renglón); nunca una cápsula de texto | `testSeeAllIsTheTitleChevron` |
| **Cada estreno dice cuándo sale** (Fernando, 25 nov 2026): en la línea de Inicio cada tarjeta lleva su día («Mañana», «Domingo») o, si es hoy, su hora o «Hoy»; nunca un rótulo en blanco | `HomeTimeline` | `testEveryUpcomingCardSaysWhen` |
| **Toda lista de títulos se puede filtrar** (Fernando, 25 nov 2026): «Ver todo», colecciones, Descubre, Top 10, rankings de plataformas y filmografías traen el mismo botón de filtro arriba a la derecha y lo filtrado en cápsulas; un ranking no se reordena y cada título guarda su puesto | `SortableGrid`, `FilteredRanking`, `ListFilterMenu` | `testEveryTitleListHasTheFilter` |
| Lo que es una acción de un solo ícono va en un botón redondo | `DSIconButton` (el calendario de Lo nuevo, el «+» de Canales) | — |
| Sin reflejos bajo pósters ni tarjetas | se quitaron de `Rail`, `Shelf` y los carruseles; el color de una tarjeta de colección es `cardWeight` | `testNoReflections` |
| La barra de pestañas siempre completa | `.tabBarMinimizeBehavior(.never)`; ninguna pantalla la esconde | `testTabBarAlwaysFull` |
| Los rótulos en letra normal, con su ícono gris | `DSGroupLabel` / `DSChapterLabel` sin mayúsculas espaciadas | `testNoNewSpacedCaps` |
| De dónde viene una lista lo dice su porqué («Recomendadas por Trakt»); un sello solo si califica la lista (el jitomate) | `DSSectionHead` ignora `.trakt` | `testTraktIsNotATitleStamp` |
| Lo nuevo y lo de hoy en el turquesa del puntito del logo | `DS.fresh` / `DSFreshMark` / `DSCornerRibbon`; el verde (`DS.success`) es solo «listo, conectado» | `testNewAndTodayAreFresh` |
| Un solo interruptor: prendido en turquesa, apagado gris; si necesita explicarse, nombre corto y la explicación en gris abajo | `DSSwitchStyle` en toda la app y `DSToggleRow` | `testTogglesAreNotTintedPerScreen` |
| Los datos en gris, un paso más legibles | `secondaryLabel` = ink-250 (también la TV, `--color-text-muted`) | DesignTests (contraste) |
| En una pantalla que mezcla lo tuyo con lo que descubres (Inicio), lo de descubrir lleva título un paso más chico | `DSSectionHead(quiet:)`, receta `sectionQuiet` | — |
| Elegir de una lista corta (plataformas, Películas · Series) es con íconos o logos, no cápsulas de texto | `PlatformPill` (logo redondo con anillo), `DSKindFilter(compact:)` solo íconos | — |
| Cuándo sale, en un póster: el calendario y el día completo («Domingo») | `DSBadge(symbol:)` | — |
| Una placa sobre el arte es oscura; el color lo pone el logo | `PlatformBadge` en `DS.badgeBackground` | — |
| Una sola palabra por cosa en toda la app | «Familia», «Fama», la versión como «🇲🇽 · 1080p» | design/vocabulario.json |
| El turquesa es la voz de Orbital: el porqué, lo nuevo y lo encendido o lo que pasa ahora («En vivo», «Viendo», la voz que escucha). Nunca decoración: ni fondos, ni orillas, ni íconos sueltos, ni cifras. Dos excepciones decididas: la línea de tiempo de Próximas temporadas y la tarjeta de Búsqueda avanzada (su tinte, su orilla y su círculo) | `DS.eyebrow`, `DS.fresh`, `DS.switchOn`, `DS.live`; lo «listo» (en Real-Debrid, verificado) es verde (`DS.success`); el avance es el papel (`DS.accent`) | `testTurquoiseIsNotDecoration` |
| Nada en mayúsculas: todo en letra normal (también el listón «Nuevo», «Top», «✓ En la TV»). Única excepción: el sello del mazo de Match, que imita un sello físico | sin `dsCaps()` fuera de `MazoMatch` | `testNoSpacedCaps` |
| Títulos: dos niveles (sección y subsección). La subsección tiene dos pesos solo en una pantalla que mezcla lo tuyo con lo que descubres (Inicio): lo de descubrir un paso más chico. Explorar, que es todo descubrir, lleva el tamaño normal | `DSSectionHead(quiet:)` | — |

**En la TV (Fernando, 2 nov 2026: «aplica las reglas»):** igual. Rótulos y listón «Nuevo» en letra normal; lo nuevo y «Hoy» en
turquesa (`--color-new` = la luna); sin reflejo bajo la fila centrada; Trakt ya no es sello junto al título de una fila
(`shelf.js`). **«El turquesa no es decoración» no se aplica en la TV por ahora** (Fernando, 2 nov: «ahorita la turquesa no hagas
caso»): el turquesa se queda donde estaba (ícono del rótulo, Colecciones, «✓ Conectada», «Al instante»); solo lo nuevo y «Hoy» pasan a él.

### Reglas de la pasada de Real-Debrid y Complementos (3 nov 2026, iPhone)

Fernando: «dale una pasada a todas las pantallas que hiciste intentando romperlas». Lo que se rompía y es patrón:

| Regla | Cómo | Prueba |
|---|---|---|
| Una pregunta que confirma «Cancelar …» nombra su salida: iOS pone su propio «Cancelar» y quedan dos que hacen lo contrario | `Button("Seguir esperando", role: .cancel)` | `testCancellingSomethingNamesItsCancel` (DesignRulesTests) |
| Ícono a la izquierda de un texto de varias líneas: con letra de accesibilidad el ícono va arriba del texto (antes se encimaba con el título) | `IconBeside` (`DebridRequests.swift`), como `ParaTiB` | — |
| Lo que no se puede hacer no se ofrece: «Agregar idioma» con los 41 ya elegidos, «Ordenar» con uno solo, el último sitio de Torrentio apagado | se esconde o se deshabilita, y el pie dice por qué | — |
| Donde marcar es esconder, la marca es el ojo tachado, no la palomita (y VoiceOver dice «Escondida», no «seleccionado») | `CheckLine(mark: "eye.slash")` | — |
| Con clave guardada pero sin respuesta de Real-Debrid, la página dice «No pude ver tu cuenta» con «Reintentar»; nunca el campo vacío para pegarla | `DebridAccountView.unknown` | `-demo-rd unreachable` |

**Decisiones del 3 nov 2026 (P1-A…P6-A, canvas «Seis decisiones de Real-Debrid»).** Fernando: «Vamos con P1A. Vamos con P2B.
Vamos con P3B. Vamos con P4A. Vamos P5A. P6A.» Cada una es regla de todo el sistema:

| Regla | Cómo | Prueba |
|---|---|---|
| **Un problema siempre trae su arreglo.** Qué pasa (ámbar con su ícono), por qué (gris) y el arreglo de un toque debajo (el primero blanco, los demás de vidrio); arriba de la página, donde se ve al abrirla, y solo cuando pasa: si todo va bien, la página no cambia. Entra y sale con `DS.Motion.base` | `DSProblem` (`Feedback.swift`, sus arreglos son obligatorios) · `dsProblemFix(primary:)`. «Con esto no verías nada» (P3-B, `TorrentioNothingProblem`), «Vuelve a conectar Real-Debrid» (P6-A). «Avisos apagados» siempre con «Ajustes», también en el reproductor (P5-A, `PlayerNotice.opensNotificationSettings`) | `testAProblemAlwaysBringsItsFix` |
| **Lo que dice la pantalla es verdad al abrirla.** Tu cuenta de Real-Debrid le pregunta a Real-Debrid al abrirse; mientras, lo último que se supo sin la palomita («Guardada · Revisando…»); «Conectada ✓» solo con lo confirmado en esta visita; rechazada, «No sirve» | `DebridModel.recheck()` / `keyCheck` | `testWhatTheScreenSaysIsTrueWhenItOpens`, `testAbrirTuCuentaRevisaLaClaveYNuncaConfirmaLoDeAyer` · `-demo-rd revoked`, `-demo-rd-slow` |
| Una lista de cosas que pasan solas se parte en lo que falta y lo que ya terminó, como las descargas de iOS; un grupo vacío no sale | «Tus pedidos»: «Bajando» y «Ya terminaron» (`DebridRequestWords.grouped`) | `testRequestsSplitIntoPendingAndFinished` |
| Tocar un renglón hace lo que promete: abre su hoja con lo que se puede hacer (no solo dejando el dedo). La hoja es la misma donde salga | `DebridRequestSheet` (en la ficha y en «Tus pedidos»): «Probar otra versión» solo si ayuda (`suggestsOtherVersion`), «Abrir la ficha», «Cancelar pedido» con «Seguir esperando»; de otra cuenta, solo «Abrir la ficha» | `-demo-rd-sheet mine\|other` |
| Antes de una pregunta de iOS que se hace una sola vez, la misma explicación en todos lados | `DebridNotifyAsk` (ficha y reproductor) | `-demo-player rd-notify` |
| Un renglón de datos lleva su forma corta si la larga no cabe: `DataLine` suelta lo que no cabe, y lo que importa no puede ser lo que se suelta | «Seguir viendo» dice «T2 E5 · Bajando · 42 %» | — |

### Reglas de la auditoría del iPhone (IOS-1…IOS-19, 3 nov 2026)

Fernando: «audita a fondo…» y después «RE1-A». Lo que se rompía en el iPhone y en la TV ya estaba resuelto; es regla de las dos:

| Regla | Cómo | Prueba |
|---|---|---|
| **Conectado solo si contestó.** «Conectada ✓» de tu TV solo si contestó hace menos de 2 min (como la TV con tus aparatos, `PHONE_LIVE`); mientras, «Revisando…»; si no, «Tu TV no contesta» con «Reintentar». De tu Real-Debrid, solo si sirve para ver: vencida o gratuita, la clave dice «Guardada · sin Premium». Debajo de un problema de «Escanear», nunca «Conectada» | `Services.checkTV()` / `tvLinkNow` (`Services+TVLink.swift`), `SettingsView+Orbital`; `DebridAccountView.canPlay` | `testConnectedOnlyIfItAnswered` |
| **Lo terminado no se cancela, se quita.** Listo: «Ver ahora», «Abrir la ficha» y «Quitar de tu Real-Debrid» («¿Quitarlo de tu Real-Debrid?»); cancelar algo en camino pregunta siempre con «Seguir esperando», también desde el botón de la ficha | `debridCancelConfirmation` (`DebridRequests.swift`), `DebridRequestSheet.finished` | `testFinishedIsRemovedNotCancelled` |
| **Sin permiso no se promete avisar.** «Te aviso cuando esté listo» solo si este aparato tiene permiso y lo pidió; si no, «Ábrelo aquí para ver cuánto lleva». «Avisarme cuando aparezca» pasa por la misma explicación (P4-A) y, ya activado, abre su hoja con «Ya no avisarme» | `DebridRequestWords.detail(notifies:)`, `DebridRequestNotifier.canNotify`, `TitleDebridSheet.notifyAppear` / `.appear` | `testNoPromiseToNotifyWithoutPermission` |
| **Se compara la cuenta, no la clave.** «Tu TV usa la cuenta X · La misma que este iPhone ✓» sin botones; la pregunta («Pasar la de este iPhone · Usar la de la TV · Dejar cada una») solo si son distintas, también al conectar | `DebridModel.compareWithTV()` / `TVAccount`, `DebridTVCompare` | `DeviceKeysTests` |
| Un problema va arriba, en ámbar y con su arreglo; nunca un texto rojo sin botón. Con letra de accesibilidad, la explicación larga se queda en su hoja («¿Qué es esto?») y no tapa la página | `DSProblem`, `DSNotice(tone: .warn)`; `dynamicTypeSize.isAccessibilitySize` | `testAProblemAlwaysBringsItsFix` |
| Quitar un aparato: tocar su renglón abre su hoja con «Quitar» (como `deviceMenu` de la TV); el propio va aparte, «Desconectar este iPhone» | `OrbitalDevicesSection`, `OrbitalDeviceSheet` | — |
| Un renglón que se toca y hace algo (no lleva a otra página) lleva el color de lo interactivo; uno que lleva a otra, su chevron | `TorrentioRowLabel(action: true)` | — |
| La Mac dice «Mac»: una app de iPad en la Mac se presenta como iPad, así que las frases de «este iPhone» que también ve la Mac eligen la palabra en el código | `DeviceWords.text(_:mac:)` (`DeviceInfo.swift`) | `DeviceWordsOnMacTests` |

### Reglas del pulido de la 1729 (3 nov 2026, iPhone)

Fernando probó la compilación 1729 en su iPhone. Lo que se rompía y es patrón:

| Regla | Cómo | Prueba |
|---|---|---|
| **Una hoja mide lo que trae.** Nunca media pantalla con un hueco abajo ni texto cortado: a la medida de su contenido y, si no cabe (letra de accesibilidad, iPhone SE), llega al tope y se desplaza. El margen de la barra de inicio no se cuenta dos veces | `fittedSheet()` (contenido fijo) · `fittedScrollSheet()` (raíz que se desplaza, también un `Form` en `NavigationStack`); las tres de antes con `.medium` quedan anotadas | `testSheetsFitTheirContent` |
| **Una pantalla no se suelta al final.** Al llegar abajo, la pantalla se detiene en lo último: no sigue a un hueco vacío ni brinca para arriba (la ficha de Endgame, 26 nov 2026). Lo perezoso (que adivina el alto de lo que no ha armado) solo para listas largas | `VStack` para unos cuantos bloques; `LazyVStack` con `ForEach` o en los feeds largos (Inicio, Listas, Biblioteca) | `testLazyStacksAreOnlyForLongLists` |
| **Una hoja con asa no lleva ✕.** Se cierra jalándola hacia abajo; la ✕ «Cerrar» solo va donde no se puede deslizar: pantalla completa (el mazo, tu año), los paneles fijos (el control, la ficha) y las tarjetas de la voz dentro del control. (Fernando, 4 nov, la 1774.) | `DSSheetHeader` ya no tiene `close:` | `testSheetsWithAGrabberHaveNoCloseButton` |
| **El ícono junto a su texto va centrado.** En su columna fija, con el símbolo centrado y a la altura del primer renglón (línea base del título, como `Label`); en «¿Qué es esto?», un cuadro de color centrado con el texto | `IconBeside` (`.firstTextBaseline`) · `DSExplainerCard` | `testIconsBesideTextAreCentered` |
| **Una confirmación que hay que explicar va en su hoja.** Qué pasa, si se deshace y el botón; nunca una pregunta del sistema que diga «No se puede deshacer» | `DebridRedeemSheet` | `testImportantConfirmationsGoInTheirOwnSheet` |
| **Lo que hay que pedir no se esconde detrás de lo que arranca al instante.** Su propio grupo, con su acción («Pedir a la nube»; antes «Pedirlo y avisarme»), nunca «Ver» | `VersionRequestGroup` | `testWhatMustBeRequestedIsNotBuriedUnderTheInstantOnes` |
| **Un pedido dice dónde y cómo.** «La nube es tu Real-Debrid: lo baja por ti, no en este iPhone. Cuando termine, arranca al instante aquí (y en tu TV). Suele tardar de minutos a horas (; te aviso).» con «¿Qué es esto?» | `DebridWhereLine` | — |
| Lo que es de la TV no se queda en el iPhone: Local Files de Stremio (`127.0.0.1`) nunca se trae ni «se queda en este iPhone»; se ve como «Archivos de la TV · Solo en la TV». Nunca la descripción en inglés de un complemento: `AddonWhat` o nada | `AddonShare.livesOnTV` · `AddonList.dropTVOnly` | `testLocalFilesNeverLivesOnThisIPhone` |
| Lo que ya no lleva a nada no se ofrece: sin «Avanzado › Conectar a mano» ni su botón en el lector de códigos (TEC-35: con la llave por aparato, el token solo abre Alexa) | `QRScanner` manda a la cámara del iPhone | — |

### Una puerta dice su nombre entero (DM-A, 18 nov 2026, iPhone)

Fernando: «ajuste fino, pero ponle más grande el icono del dado». Una puerta (tarjeta con abanico de pósters y texto:
«Decide por mí», «La temporada») dice su nombre y su línea **en un renglón**: el abanico va junto (`DS.ParaTiB.doorPoster`
88, `doorShift` 8) y el aire es de 16 (`DS.Space.s4`), para dejarle al texto lo que necesita. Si aun así no cabe (el SE, letra
grande), se achica (`doorTitleScale`, `titleShrink`) antes de partirse o cortarse; nunca «Decide / por mí», «Navi-dad» ni
«La tempo…». Con letra de accesibilidad el texto baja bajo el abanico y puede partirse. Antes, el texto partido hacía crecer la
tarjeta por encima de su lugar y le comía 10 pt de aire a la fila de arriba. Prueba: `testDoorsSayTheirNameWhole`.

### El control de un capítulo no le gana a su rótulo (EX-A, 19 nov 2026, iPhone; tamaño cambiado por SZ1 el 23 nov)

Un capítulo con control (`DSChapterHead` con `accessory`, «Lo que se ve hoy» de Explorar) se ve como sus hermanas: ícono,
rótulo y **la línea fina hasta el control**. El control va al final de la línea y se asoma `chapterBleed` sobre el aire sin
empujarlo: los 32 entre secciones se miden al rótulo, no al control. Desde SZ1 mide 44, como todos los selectores (antes 36).

### Nube = Real-Debrid; descargar = a este aparato (RX, 3 nov 2026, iPhone; la TV lo iguala)

Fernando, 3 nov («RX1A… RX2A… RX4A», y RX3-A alineado con la guía de bienvenida; canvas
https://claude.ai/artifact/BJGeSBJKrCsvRqbScXZdVh): «Pedir», «bajando» y «descargar» se confundían, y «Real-Debrid» no le dice
nada a quien no lo conoce. Cada palabra dice dónde pasa:

| Regla | Cómo | Prueba |
|---|---|---|
| **Lo que pasa en Real-Debrid se dice «la nube».** «Pedir a la nube», «Bajando en la nube · 42 %», «La nube lo recibió y espera turno», «Todavía no está en la nube». Nunca «Real-Debrid lo está buscando»: lo está bajando. Se explica una vez dónde se ve («Lo que pediste», con el sello de Real-Debrid, «La nube es tu Real-Debrid: …», «Real-Debrid es la nube» en «¿Qué es esto?») | `UnavailableCause`, `DebridRequestWords`, `DebridWhereLine` | `nube = Real-Debrid; descargar = a este aparato` (tests/web/design-parity.test.mjs) y el vocabulario |
| **«Descargar» es solo guardar en este aparato** para verlo sin internet. A la nube se pide, nunca se «descarga» | `DownloadsView` (sus dos partes) | la misma |
| **«Real-Debrid» queda donde se habla de la cuenta o la marca:** Ajustes › Cuentas › Real-Debrid, «Tu Real-Debrid venció», «Quitar de tu Real-Debrid», «Real-Debrid no lo dejó bajar» | — | — |
| **Lo que pides vive en Descargas**, en dos partes: «Lo que pediste» (T9, 10 nov; antes «Real-Debrid · bajando para ti», que el iPhone todavía dice: pendiente; los grupos «Bajando» y «Ya terminaron», la misma fila y la misma hoja de siempre) y «En este iPhone · sin internet», bajo la pestaña de texto «Descargas»; la otra, «Mi media» (OneDrive, luego Plex y Jellyfin), lleva carpeta, nunca nube: la nube es solo Real-Debrid. El grupo no se llama «En la nube» para no confundirlo con Mi media (Fernando, 3 nov). Cada parte con su vacío y su única salida. Ajustes › Cuentas › Real-Debrid › «Tus pedidos» es un atajo que lleva ahí. La pestaña cuenta también lo que baja en la nube. Sin Real-Debrid no hay nube (Plus, App Store) | `DownloadsCloudPart` · `CloudSheetsHost` | — |
| **Tocar lo que baja en la nube dice cuánto falta, honesto,** y deja elegir: «A este paso, falta menos de una hora. Te aviso.» (del avance desde que se pidió; sin qué medir, «Suele tardar de minutos a horas.»; «Te aviso» solo con permiso), «Ver Inglés · 1080p, ya arranca» (la mejor que ya arranca en tus idiomas, la regla de «Ver») y «Esperar a que llegue». Sin otra al instante, solo cuánto lleva | `DebridRequestWords.paceLine` · `SourcesSheet` (al tocar la ya pedida) · `DebridRequestSheet` | `testThePaceComesFromTheProgressRateOrSaysMinutesToHours` |
| **«Así funciona», una sola vez:** la primera vez que ves «↓ Por pedir» (en «Versión» o en la ficha), los tres pasos animados, «No ocupa espacio en este iPhone» y «Entendido». Se recuerda en `learn.seen.debrid-flow`, la llave que también escribe la guía de bienvenida | `DebridFlowIntro` · `DebridFlowIntroHost` | — |

### Paridad TV ↔ iPhone (PT, 4 nov 2026; las dos)

Fernando, 4 nov, sobre las capturas lado a lado (https://claude.ai/artifact/1hb5WZZxkB8bgVZhnhczje): «de acuerdo a tu
recomendación» en todos, salvo PT6 («déjala como está»). Lo pendiente de la TV, en el registro de paridad.

| Regla | Cómo | Prueba |
|---|---|---|
| **La nube con flecha es Real-Debrid; la flecha sola es «Descargar» (PT5).** Todo lo de la nube (Pedir a la nube, Bajando en la nube, Tus pedidos, el grupo «Lo que pediste», el paso «La nube lo baja») lleva `icloud.and.arrow.down`; la flecha hacia abajo (`arrow.down.circle`) es solo guardar en este aparato | `DS.Symbol.cloud` / `cloudFill` (sale de `DebridRequestWords.Icon.cloud`), `DS.Symbol.download` | `testRealDebridIsTheCloudArrow` |
| **Un ícono por estado y por acción de un pedido (PT10),** igual en la TV: ⊗ `xmark.circle` cancelar · `trash` quitar · `clock` en cola · nube con flecha bajando · `person.2.slash` sin gente · `exclamationmark.triangle` **solo** «Real-Debrid no lo dejó bajar» · `square.stack.3d.up` «Muchas descargas activas» · `checkmark.circle` listo. Nadie escribe estos nombres a mano | `DebridRequestWords.Icon` y `.symbol(_:)`, `DS.Symbol.cancelRequest` / `removeRequest` | `testRequestIconsComeFromTheCatalog`, `ParityPTTests.testEachRequestStateHasItsOwnIcon` |
| **«Bajando en la nube · 42 %» en todos lados (PT11):** la ficha, «Versión», Tus pedidos, «Seguir viendo» (ahí el estado va primero para que, si no cabe, se suelte el episodio y no el avance) y el reproductor. Nunca «Bajando · 42 %» suelto | `DebridRequestWords.title` (ya no hay `short`) | `testDownloadingInTheCloudIsNeverBare` y el vocabulario |
| **Cuánto tarda un pedido, una frase (PT7):** «La nube las baja por ti: suele tardar de minutos a horas.»; los días solo en «¿Qué es esto?», como peor caso («…; si poca gente lo comparte, hasta días.») | `VersionRequestGroup`, `DebridExplainer` | el vocabulario |
| **Un tamaño, un formato (PT8):** «1,2 GB» con la coma del español y «1.2 GB» en inglés; GB y TB con un decimal, MB y KB sin decimales | `ByteSize.text` (OrbitalCore), con el idioma de la app | `testSizesAreWrittenWithByteSize`, `ParityPTTests.testSizesUseTheAppLanguageSeparator` |
| **Letra de los subtítulos: Pequeño · Normal · Grande · Muy grande (PT19)**, las cuatro de la TV | `AppSettings.subtitleSizes` | `ParityPTTests.testFourSubtitleSizesLikeTheTV` |
| **Complementos (PT16):** el grupo «Se preguntan en este orden»; cada renglón dice lo que aporta y cómo contesta («Contesta en 0,3 s»); solo se marca «Apagado» | `AddonRowLabel`, `AddonHealthLine` | `testAddonsOnlySayOff` |
| **Preguntar antes de prometer (PT24):** con el episodio bajando en la nube, «¿Te aviso cuando esté listo?» y «Sí, avísame»; después de tocar, «Te aviso cuando esté listo» (o «Avisos apagados · actívalos» con «Ajustes») | `PlayerFailureView.notifyAnswer` | `testAProblemAlwaysBringsItsFix` |

### Biblioteca: Descargas · Mi media · Guardado (BI, 3 nov 2026, iPhone; la TV decide aparte)

Fernando, 3 nov («Vamos con tu recomendación de BI1A y BI2A. Y pon el mismo filtro que ponemos en otras listas…»; canvas
https://claude.ai/artifact/Ko68NmPSKW11puvFaU6Pct): la pestaña Descargas pasa a llamarse **Biblioteca** y junta lo tuyo en
tres partes. Solo el iPhone, el iPad y la Mac; la TV lo decide en su sesión (registro de paridad).

| Regla | Cómo | Prueba |
|---|---|---|
| **Biblioteca, con tres pestañas de texto** en este orden: «Descargas» (lo de este aparato arriba y «Lo que pediste» abajo) · «Mi media» (OneDrive; luego Plex y Jellyfin) · «Guardado». Abre donde la dejaste, en ese aparato; la primera vez, en Guardado. Un aviso de descargas, «Ver en Descargas» o «Tus pedidos» abren «Descargas». Si algo baja (en la nube o aquí), la pestaña lo dice: «Descargas · 2» | `DownloadsView` (`Part`, `library.part`), `AppUI.showDownloads`; el ícono de la pestaña, `rectangle.stack` (4 nov); las tres partes con el mismo fondo (`Backdrop`) y los íconos de las pestañas de texto sin rellenarse al elegirlas; en Guardado (FG1-A, 4 nov) un solo renglón: «Mi lista ⌃⌄» a la izquierda (`DSChoiceMenu` estilo `.title`) y, a la derecha, Todo · Películas · Series (`DSKindFilter` compacto) y el botón de ordenar y filtrar (`SortableGrid(bar:)`); debajo, solo lo filtrado en cápsulas; tocar el aviso «Ya está…» abre Descargas con la hoja de ese pedido y, viendo Descargas, ni aviso ni marca en la pestaña; ⌘3 «Biblioteca» en el menú | `SavedModelTests` |
| **Guardado es tu referencia rápida (BI1-A):** Mi lista de Trakt por omisión y, con un toque en «Mi lista ⌃⌄», cualquiera de tus listas de Trakt (las mismas de Para ti; la elegida se recuerda). Cuadrícula de pósters con su barra de avance (vista: completa; una serie: sus capítulos vistos; una película: dónde te quedaste); tocar abre la ficha | `LibrarySavedView`, `SavedModel`, `DSChoiceMenu`, `TitleLink(progress:)` | `SavedModelTests` |
| **El mismo filtro que las otras listas (BI3-A):** Todo · Películas · Series (`DSKindFilter`) y «Ordenar y filtrar» de toda lista abierta (`SortableGrid` › `ListFilterMenu`, `ListFilterChips`) con **«Estado»: Por ver · A medias · Vistas** (en lugar de «Ocultar lo que ya vi» donde se sabe cuánto llevas), género, calificación, década y orden. No hay filtro propio de Guardado: lo que faltaba («Estado») entró a la pieza compartida | `ListFilter.state`, `WatchStateName` | — |
| **Cada parte con su vacío y su única salida:** sin Trakt, «Conectar Trakt»; lista vacía, «Explorar»; Trakt no contestó, «Reintentar» | `LibrarySavedView` | — |

### Tabla espejo (iPhone ↔ TV)

Una sola Orbital (Fernando, 31 oct 2026): cada papel del lenguaje del iPhone tiene aquí su pieza de la TV y su estado. Estado:
`Igual`, `Pendiente · ola N` (con su renglón en `docs/producto/paridad-registro.md`), `Distinto a propósito: motivo` o
`Solo iPhone: motivo`. `tests/web/design-parity.test.mjs` falla si un papel nuevo del iPhone no tiene renglón aquí. Cuando se
decide algo del iPhone, su commit dice qué pasa en la TV («En la TV: igual · distinto a propósito · pendiente»).

| Papel | Pieza de la TV | Estado | Nota |
|---|---|---|---|
| Encabezado | `SectionHead(title, { level })` (`ui.js`) y el rótulo de las filas de tarjetas (`shelf__heading--section`) | Igual | Sección = rótulo con ícono en `--color-orbital`, letra normal en negrita y línea, el dato a la derecha (Tus consolas, Día por día, Premios, Estudios…); subsección = título blanco. |
| Arranque de una parte grande | El rótulo de sección de cada grupo (`shelf__heading--section`) | Distinto a propósito: con el mando, un renglón menos (el título grande lo pone el destacado de arriba, que cambia con el foco) | Los grupos de Películas y series (Plataformas, Estudios, Premios, Temporadas, Años…). |
| Renglón de lista | Tarjetas de lista en fila (`collection-card`) y `sheet__item` en las hojas | Distinto a propósito: con el mando, tus listas son tarjetas en una fila (Listas de Trakt, de Stremio) | En las hojas (☰, Opciones, Guardar en…), el renglón es `sheet__item`. |
| Porqué | `SectionHead(title, { reason })` y `--color-reason` | Igual | Solo cuando el porqué dice algo que el título no; un dato nunca va en turquesa. |
| Botón principal | `Button({ variant: "primary" })` y `title__action--primary` | Igual | En blanco, como el iPhone (dsSolidPrimaryButton): «Jugar», «Ver», «Continuar»; nunca del color del arte. |
| Botón secundario | `Button` y los redondos, de vidrio (`--color-glass` con su filo) | Igual | El vidrio del iPhone (`.glassEffect(.regular)`), en su versión sutil; enfocado, se invierte (con el mando, el foco se ve a tres metros). |
| Botón de ícono | `Button({ icon })` (`button--round`) y los redondos de la ficha (`title__action--icon`) | Igual | Uno sólido y los demás redondos: Opciones, Ficha y Episodios en el destacado de Inicio, el de Películas y series y la ficha de Juegos, con el glifo en su orilla y su nombre debajo. |
| Selector | `Pill({ tone: "tab" })` (pestañas de texto), `Segmented`, `Pill` (cápsulas) | Igual | Cambiar lo que ves: pestañas de texto (los filtros de una consola, Series · Películas de una lista, las temporadas de la ficha); ajustar un valor: `Segmented` (Ajustes); elegir: cápsulas (¿Qué vemos?, búsquedas recientes). Lo elegido en blanco; el foco, invertido. Los mosaicos llegan con el mazo (ola 2). |
| Muestra de idioma | — | Solo iPhone: la TV no tiene la página de Idiomas; su idioma se elige con `Segmented` | |
| Marca de idioma | — | Solo iPhone: la TV no tiene la página de Idiomas | |
| Búsqueda avanzada | `filter-panel` (☰ › Filtro avanzado) y «Ordenar y filtrar» de `list-screen` | Igual | En la TV vive en ☰ (Fernando, 31 oct 2026); filas con ‹ › en lugar de mosaicos (distinto a propósito: el mando). Las listas y colecciones: tipo, género, calificación, década y lo visto. |
| Marcar como vista | La hoja «¿Cuándo la viste?» (Opciones › Marcar como vista) | Igual | «Otro día…» ofrece días comunes en lugar del calendario (distinto a propósito: el mando). |
| Vacío | `EmptyState({ icon, title, text, action })` (`ui.js`) | Igual | Juegos sin favoritos o sin juegos, un día sin estrenos, TV en vivo sin canales, Explorar sin sugerencias o sin conexión, una lista vacía o sin nada con sus filtros, y el Inicio vacío. Con su primer paso (`action`, C4, 24 nov 2026), como los botones de `DSEmptyState`. |
| Lista de versiones | `sources` (filas por idioma con una casilla por calidad) | Pendiente · ola 6 | V1 en la TV: renglones con íconos y un toque (`docs/producto/paridad-registro.md`). V3 ya es así en la TV: no tiene pestañas ni el segmento del episodio. |
| Tarjeta | `--color-surface` (ink-900) y `--radius-*` | Distinto a propósito: la superficie es ink-900 en la TV (lo explica `design/tokens.json`) | — |
| Hoja con encabezado propio | `sheet`, `side-panel` | Igual | — |
| Aviso | `toast` | Distinto a propósito: arriba a la derecha, porque abajo va el pie de pistas y se lee desde el sillón | Mismos tonos, textos y duración (`--duration-notice`). La entrada por partes (ícono, la cajita que crece y rebota, el texto) es por ahora solo de la TV (registro de paridad). |
| Etiqueta | `Badge`, `Chip` y `CornerRibbon` | Igual | «Nuevo» es el listón turquesa en diagonal de la esquina del póster (Mi media, sus listas y Lo nuevo de lo tuyo); el 11 nov 2026 fue un rato un puntito y Fernando lo deshizo («no quiero que quites la cinta de nuevo»): la TV y el iPhone (`DSCornerRibbon`) vuelven al listón. «HOY» y el ▲▼ del Top 10 se quedan en placa. |
| Editar una lista tuya | «Editar» · «Agregar» · «Listo» de `list-screen`, Opciones › «Quitar de esta lista» (`gameMenu({ list })`) y `isEditableList` (`core/menus.js`) | Igual | Solo Mi lista y tus listas de Trakt, como el iPhone. Con el mando, X o ☰ › «Elegir varios» (el menú dice su atajo) en lugar de la barra; el marcador del póster no es botón en la TV: en la fila «Mi lista», Opciones › «Quitar de Mi lista». Agregar: ☰ › «Agregar a esta lista…» o, desde la ficha, «Agregar a una lista…». Mismos textos: «Quitada de «…»», «Agregada a «…»», «No pude cambiar «…»» (8 nov 2026). |
| Elegir varios (Guardado) | `SelectMark` (`ui.js`) y el modo de elegir de `list-screen` (`onBatch`, `sorter.chosen`), «Con las elegidas…» (`app/saved-commands.js` · `batchMenu`) | Igual | G3-A (10 nov 2026). Con el mando: X o ☰ › «Elegir varios», A elige, Y «Con las elegidas…», ☰ › «Elegir todas», B o X «Listo». Con mouse o dedo: «Editar», la casilla del póster, «Todas», «Con las elegidas…» y «Listo» junto al nombre. Lo que ofrece cada lugar, la tabla de la propuesta (`batchActions`); un solo aviso con «Deshacer» (Y); Trakt recibe un envío por lista (`Gestor.set_many`). Sin internet, Mi lista y lo dejado esperan en la cola de Trakt (`trakt_outbox.py`). |
| Manejar tus listas (Guardado) | ☰ de una lista tuya › «Esta lista» (`listManageOptions`): Cambiar nombre, Quién la ve, Ordenar a mano (`list-screen` · `setReordering`), Duplicar, Compartir enlace y Borrar lista; ☰ de Guardado › «Tus listas» y «Nueva lista» (`savedMenuOptions`) | Distinto a propósito: el «···» del iPhone es ☰ en la TV (el botón de menú del mando); ordenar a mano es A para tomar, flechas para mover y A para soltar; «Compartir enlace» enseña el enlace de trakt.tv (la tele no comparte) | G4-A (10 nov 2026). Todo necesita internet: sin él, apagado y dice «Necesita internet». Mi lista aún no se ordena a mano en la TV (su fila va por fecha en que la guardaste): en el registro de paridad. |
| Estado de un título (G1-A) | El botón de estado de la ficha (`titleActions` · `STATUS_WORDS`, `titleStatus` en `core/watch.js`) y «¿Cómo vas con…?» (`app/yours-commands.js` · `statusMenu`) | Igual | 10 nov 2026. «Mi lista» · «En Mi lista» · «Viendo» · «Vista» · «La dejé» en lugar de «Guardar», «Marcar como vista» y la campana; sin estado, A la guarda en Mi lista (con «Deshacer»); con estado, A abre «¿Cómo vas con…?»; X siempre lo abre (el pie lo dice). «La dejé» va también a las dejadas de trakt.tv (`Gestor.set_dropped`). |
| Guardado por estado (G2-A) | ☰ › «Guardado»: `list-screen` con una pestaña por montón y su cifra (En Mi lista · Viendo · Vistas · Las dejé · ¿Las dejaste?), Y › «Mover a…» (`moveMenu`), ☰ › «Sí, las dejé» (`app/saved-commands.js`; `Gestor.board` en `orbital/gestor.py`) | Distinto a propósito: en la TV no hay pestaña Biblioteca (BI-TV-A): Guardado vive en ☰ y sus montones son pestañas (LB/RB o Q/E), no tarjetas | 10 nov 2026. Las mismas reglas de `SavedBoard` (Trakt ya no manda las temporadas en `/sync/watched/shows`: el avance sale de `/shows/{id}/progress/watched` para tus 40 series más recientes). Lo que cambió solo («Dune pasó a Vistas») se avisa al abrirlo. |
| Tus vistas, tu nota e Historial | «¿Cómo vas con…?» › «Tus vistas», «Calificar la temporada N» y «Tu nota»; Y › «Cambiar» en el aviso de «Vista»; ☰ de Guardado › Vistas › «Historial» (`app/viewings-commands.js`: `viewingsMenu`, `viewingMenu`, `historyMenu`, `seasonStarsMenu`, `watchedFixMenu`; la nota con el teclado de `login`) | Distinto a propósito: hojas en lugar de pantallas; fechas de siempre (ayer, hace una semana…) en lugar del calendario; «Deshacer» y «Otra fecha» tras Y › «Cambiar» (un aviso de la TV lleva una sola acción); la nota sin VIP vive en la tele | O3-B (10 nov 2026). Las repetidas (menos de una hora de otra) dicen «Repetida»; se borran todas de una vez («Borrar N vistas repetidas»). La pregunta al terminar una temporada sale en el aviso al volver a la ficha (`finishedSeason`). Sin internet, todo espera en la cola de Trakt. |
| Texto sobre arte | `Veil(...lados)` y `--veil-bottom`, `--veil-leading`, `--veil-top`, `--veil-bottom-soft`, `--veil-corner` | Igual | Una receta por lado; los velos de pseudo-elemento (tarjeta de premio, escenario de «Porque viste», mosaico) usan los mismos tokens. |
| Cargando | `PosterSkeletons(n)` (`skeleton--poster`, `skeleton--heading`) y `LineSkeleton` (`skeleton--line`) | Igual | Películas y series (dos filas) y una lista abierta, quietos: nada se anima mientras se espera. Mientras se busca versión (8 nov 2026): la cápsula de al lado de «Ver» y las filas de «Versión» en gris con su forma (`VersionsSkeleton` y la zona derecha de `SplitPlayButton` del iPhone). |
| Sin conexión o error | `ErrorState` (`ui.js`) en una pantalla y `failure()` en un aviso, con «Reintentar» | Igual | C5 (24 nov 2026): qué pasó, qué no se perdió y «Reintentar» que reintenta; nunca el `err.message` crudo. En el iPhone todo error pasa por `UserMessages.humanize` (red, servidor y, desde el 25 nov, los errores del código o del sistema en inglés): queda lo que se intentaba y la salida (`UserMessagesTests`). |
| Problema con su arreglo | Mensajes en palabras con su botón | Pendiente · ola 6 | La TV aún no tiene la prueba con un título ni revisa tu clave al abrir tu cuenta (registro de paridad, «Decisiones de Real-Debrid»). |
| Números y fechas | `core/format.js` | Igual | — |
| Logos de marca | `--platform-*` y los logos de `ui.js` | Igual | — |
| Lo que se mueve solo | El mosaico se detiene a los 90 s; todo respeta movimiento reducido | Igual | La TV no tiene cielo que se mueva: Orbital no gasta detrás de un juego. |
| Pedido a Real-Debrid | `title.js` (RD-1, RD-3) y el aviso «Ya está…» de `rd_requests.py` | Distinto a propósito: la TV dice tres estados y el porcentaje; los seis de R13, la hoja del pedido y «Tus pedidos» llegan con S2/S4 (registro de paridad) | «Pedirlo y avisarme» y «Bajando en Real-Debrid · 42 %» ya son iguales. |
| Explicación «¿Qué es esto?» | La hoja «¿Qué es esto?» de `menus.js` (`explainerMenu`, las mismas ideas) · `.sheet__icon--tint` · `.sheet__steps` (`sheet.css`) | Igual | Los mismos colores de las listas (`--tint-*` = `DS.ListTint` en oscuro) a 18 %, el cuadro más grande que el ícono de siempre (`--explain-tile`) y centrado con el texto, y en los pedidos los tres pasos que se encienden cada 1,6 s (`--duration-loop`; con «Reducir movimiento», quietos y encendidos). El aviso de «Ya está» dice que en la TV llega aquí mismo. |
| Complemento de cada versión | `AddonMark(kind)` (`addon-mark`) en «Versión» y «Todas las de aquí» | Igual | Ⓣ Torrentio, Ⓒ Comet y la pieza para los demás, chico y tenue junto a la calidad (8 nov 2026). Comet va de respaldo igual que en el iPhone: su «al instante» pierde 300 (`streams.COMET_DOUBT` = `Streams.cometDoubt`). |
| Botón principal de la ficha | `title.js` (el botón principal y, a su lado, la cápsula de la versión `title__version`) | Igual | La versión pegada a «Ver» en los dos: en el iPhone dentro del botón partido (L3, 11 nov 2026), en la TV como cápsula enfocable a su lado; mientras se busca, gris con su forma. |
| Versiones por pedir | `sources.js` (grupo «Hay que pedirlas · tardan», 22b7a092) | Pendiente · ola 6 | El grupo y «Pedirlo y avisarme» ya están en los dos; falta en la TV la cápsula «Por pedir» y el renglón «dónde y cómo» del pedido. |
| Confirmación importante | — | Solo iPhone: canjear puntos (D4) solo vive en el iPhone | — |
| Complementos y Torrentio | Ajustes › Complementos (`menus.js`, `addonHealth`) | Distinto a propósito: la TV tiene sus propias pantallas con las mismas palabras; las opciones de Torrentio viajan con S6 (pendiente en el registro de paridad) | Las mismas palabras de cómo le va a cada uno («Contesta en 0,6 s»…) ya están en los dos. La página de Torrentio y la prueba con un título son del iPhone por ahora; las opciones viajan con S6 (renglón «Configurar Torrentio y Complementos» del registro de paridad). |
| Tu lista y la de tu TV | «Vienen de tu iPhone · cambiado hace 2 min» arriba de Ajustes › Complementos (`menus.js`) y «Archivos de la TV · Solo en la TV» | Distinto a propósito: la TV dice de dónde vino el último cambio; el iPhone dice si es la misma lista que la TV o si la TV no contestó | Las mismas palabras para lo que es solo de la TV. |
| Accesibilidad | Foco visible y pistas de cada superficie | Solo iPhone: es cómo SwiftUI agrupa los identificadores | — |

### Movimiento

| Token | Para qué |
|---|---|
| `--duration-none` | Movimiento reducido: sin transición. |
| **La regla (TB-19, 24 nov 2026; sistema base B12)** | Un movimiento de la interfaz dura **de 180 a 300 ms** y, si va en cadena, unos **100 ms** entre pieza y pieza (`--stagger`, antes 45). Se ajustaron `--duration-instant` 90 → 180, `--duration-fast` 140 → 180, `--duration-exit` 160 → 180, `--duration-slow` 320 → 240, `--duration-enter` 520 → 300, `--duration-snap` 360 → 300, `--duration-smooth` 440 → 300 (la misma curva) y `--duration-notice-grow` 420 → 300 (con `--delay-notice-text` 480 → 400). Fuera de la regla, a propósito: el arranque y la carga (`--duration-land`, `--duration-brand-*`, `--duration-launch-*`, `--duration-enter-long`, que también usan la pantalla de carga y la primera entrada de Inicio), lo ambiental que se ve lento (`--duration-tint`, `--duration-drift`, `--duration-alive`, `--duration-ken-burns`, `--duration-glide`), los ciclos (`--duration-loop`, `-pulse`, `-breathe`) y lo que dura un aviso a la vista (`--duration-notice*`). `fast`, `slow` y `enter` valen distinto en el iPhone hasta que Fernando lo vea allá (`design/tokens.json › durationTv`). |
| `--duration-instant` · `--duration-fast` · `--duration-base` | Salidas cortas, foco, cambios de estado. |
| `--duration-slow` · `--duration-snap` | Paneles, secciones que entran de lado, el «salto» de una portada. |
| `--duration-enter` · `--duration-enter-long` · `--duration-land` | Algo que aparece (también la primera entrada de Inicio y del mosaico, 25 nov 2026) · abrir un juego, lento a propósito · el arranque. |
| `--duration-exit` | Salidas (más cortas que las entradas y acelerando: `--ease-in`). |
| `--duration-tint` · `--duration-drift` | Lo lento que se ve (el color del fondo, la revelación al abrir un juego) · el fondo sigue al foco. |
| `--duration-alive` | «Cobra vida»: quieto en una pieza de Para ti, su arte se acerca despacio; lo que flota al abrir un juego. |
| `--duration-loop` | Un ciclo que se repite: barrido de carga, giro del aviso, cada paso de «¿Qué es esto?». |
| `--duration-glide` · `--ease-glide-in/out` | Un tramo de la deriva de Para ti (la anima el compositor) y cómo arranca y se frena sin costura. |
| `--duration-pulse` · `--duration-breathe` | Cursor de escribir, «te escuché» · algo que espera (dictando). |
| `--duration-hop` | Un brinco de la señal de «hay más abajo» del Inicio (IN1-A): da tres al entrar y se queda quieta. No es un ciclo: nada se mueve en bucle. |
| `--duration-launch-*` | Pantalla de carga (cinemática, más lenta a propósito). T11 (10 nov): la revelación, el vaivén y el barrido ya usan `--duration-tint`, `--duration-alive` y `--duration-loop` (mismos valores). |
| `--delay-1/2/3` · `--stagger` | Escalonado: cada pieza entra un poco después. |
| `--ease-out` · `--ease-in` · `--ease-spring` · `--ease-pop` · `--ease-launch` · `--ease-sweep` | Entradas · salidas · resorte corto · foco que salta · disparo · barrido. |
| `--duration-smooth` · `--ease-smooth` | **Los resortes con nombre del iPhone** (2 nov 2026): `DS.Motion.smooth` (sin rebote) como curva `linear()`. Lo que viaja y cambia de forma: la ficha que se abre desde su tarjeta y vuelve a ella. |
| `--duration-snappy` · `--ease-snappy` | `DS.Motion.snap` (firme, un rebote que casi no se ve): lo que se acomoda o se aprieta (el empujón del foco, el hundido de A). |
| `--duration-ken-burns` | El fondo, quieto en un título 2,5 s, se acerca un 3 % en 16 s y ahí se queda (un tramo, no un ciclo). |
| `--duration-notice-icon` · `--delay-notice-grow` · `--duration-notice-grow` · `--ease-notice-grow` · `--delay-notice-text` | **Cómo entra un aviso** (Fernando, 6 nov 2026): el ícono sale solo con un «pop» (`--ease-pop`); a los 160 ms la cajita crece desde él en 300 ms y se asienta sin pasarse (`--ease-notice-grow`; 24 nov 2026: el rebote la hacía resbalar bajo el texto); a los 400 ms llegan el texto y la sombra (`--duration-base`). Solo transform y opacity, y al terminar (~0,6 s) queda quieto. Con movimiento reducido aparece entero de una vez. Lo mismo encima del juego (`overlay.py`, que usa estos valores: `tests/test_overlay.py`). |

**Lo que hace que se sienta premium** (propuesta del 2 nov 2026, https://claude.ai/artifact/DhegvqEaNMkrsCDWHU9gfS):

- **Continuidad.** La ficha se abre desde la tarjeta (`title.js · flyIn`) y, al cerrar, su arte se encoge de vuelta a esa tarjeta
  y el foco sigue ahí (`flyOut`, `title--returning`); desde una persona o Buscar se funde como siempre.
- **Foco con cuerpo** (`core/feel.js`). Cada flecha deja `data-heading` en la raíz: la tarjeta que recibe el foco entra con un
  empujón de ese lado que se asienta (`focus-lean`). A hunde lo
  enfocado al 97 % y lo regresa (`.is-pressed`); con el dedo y el mouse, `:active`. En el borde, el rebote de siempre con su sonido.
- **Nada salta.** Una portada llega desenfocada y se enfoca mientras aparece; las calificaciones de la ficha ruedan hasta su número
  (`motion.js · rollNumber`) y su renglón se aparta desde que se abre (`title__ratings--waiting`); se precarga también el fondo de la
  tarjeta de atrás.
- **Pasada de unslop por Explorar** (Fernando, 2 nov 2026; vale para toda la app): la cápsula de una plataforma
  («N.º 1 en Netflix», `PlatformBadge`) es de vidrio y su color va solo en su logo; lo que no tiene arte se llena del color
  de su consola o plataforma (`.card--no-art` con `--fill`, la pieza `--bare` de Explorar con `--tile-fill`), nunca un cuadro
  gris; en una pieza angosta nada se corta: la versión corta del porqué («N.º 1»), el dato sin el tipo («2015») y el nombre
  en la receta `eyebrow`, hasta cuatro renglones, con guiones suaves por sílaba (`format.js · softHyphens`); la sombra de lo
  enfocado es `--focus-lift` (corta y con su filo); el pie dice qué hace el botón («Enter Explorar», no «Elegir»). Un juego
  de consola en Explorar va con su caja, como todo lo demás; su fondo con el logo sale al enfocarlo (Fernando, 18 nov 2026:
  el fondo recortado a lo alto no se reconocía; antes, del 2 nov, iba el fondo con su logo).
- **Una cuadrícula que se recorre** (`browse.js · keepInView`: Juegos, listas, TV en vivo) sube la fila enfocada hasta arriba; nunca
  deja la de antes a medias y desvanecida, que se veía como un hueco (TV-4, 2 nov 2026).
- **El porqué va arriba del título en todas las pantallas** (Fernando, 2 nov 2026, opción B): se consideró bajarlo a la línea de
  datos (impeccable) y se descartó para que la regla sea una sola.
- **El arte del fondo** (`backdrop.css`, Fernando, 2 nov 2026): arriba a la derecha, más chico que la pantalla (empieza a un
  tercio del ancho y termina a tres cuartos del alto), para que lo tapen menos la barra y el destacado; lo que deja libre se llena
  con su color (`backdrop__layer--art`). Una consola enfocada en Inicio no lleva arte: solo su color (`--system-*`).
- **Fondo vivo pero quieto** (`backdrop.js · ALIVE_MS`, `backdrop__layer--alive`): ver la tabla de arriba. Sin ciclos: al terminar no
  se mueve nada.
- **Velocidad.** `tests/smoke/test_ui_smoke.py · test_moving_feels_instant` mide, recorriendo una fila de Juegos, cuánto pasa de
  apretar a ver el foco (mediana menor a 100 ms) y cuántos cuadros tardan más de dos (menos del 10 %). Lo nuevo de movimiento pasa por
  ahí: si cuesta cuadros, no entra.

**Sonido: un idioma** (`core/sound.js`). Una sola familia de «clic de cristal», ordenada por tono:
`move` (el más corto), `select`, `back`, `open`, `menu`, `edge` (el borde: un golpe sordo; antes sonaba el de error), `success`
(lo logrado: guardar en Mi lista, calificar, marcar vista, un canal nuevo: dos notas que suben) y `error`. **El mando no vibra** al navegar ni al abrir algo (Fernando, 2 nov 2026: cansaba); solo cuando lo pides para saber qué jugador es (Jugadores, y al conectar un control). El sonido se apaga en Ajustes.

**Capas**: toda capa nueva se funde en `--duration-base`, un panel lateral se desliza en `--duration-slow` y todo sale en `--duration-exit` (la ficha entra en `--duration-fast` a propósito: su arte aparece casi de inmediato).

Todo respeta **movimiento reducido** (`prefers-reduced-motion` o Ajustes → Pantalla): `base.css` lleva
todas las duraciones a `--duration-none` y detiene los bucles. **Lo que solo se funde sigue fundiéndose, corto**
(`--duration-fast`): las pantallas que entran y salen y el fondo que cambia; sin eso todo aparecía de golpe. El viaje de la
ficha, el empujón, el destello, el hundido, los números que ruedan y el fondo vivo no se encienden.

### Capas

Globales: `--z-overlay`, `--z-hints`, `--z-launch`, `--z-toast`. Dentro de un componente:
`--z-behind`, `--z-raised`, `--z-above`, `--z-panel`.

---

## 2. Piezas base (`ui`, `button`, `glyph`, `keyboard`)

| Pieza | Archivo | Para qué |
|---|---|---|
| `Chip(text, { tone })` | `ui` | Un dato corto: «4K», «Inglés», «Al instante» (`good`/`warn`). Una línea, nunca se parte. |
| `ScrollCue({ onPress, className })` | `scroll-cue` | La señal de «hay más abajo» (IN1-A, 26 nov 2026; MN-A, 27 nov): abajo al centro, el nombre de lo que sigue con su ícono en el azul de Orbital y la flecha, sin tecla. `set(items)` dice qué sigue; `hop()`, tres brincos al entrar y quieta (`--duration-hop`). Un clic o un toque bajan. En el Inicio (`home__cue`: «Mi lista», «Tus consolas») y en Películas y series (`shelf__cue`: la fila siguiente, que ya no asoma). |
| `PlatformMark(src, fallback)` | `ui` | La marca **real** de una plataforma, a color y del alto de la letra (`platformMark(item)` en `core/icons.js`): los de Steam y GeForce NOW, y la foto de la consola para un juego retro. La misma en el Inicio, Películas y series, el héroe y Juegos; sin marca (una app), el ícono de líneas. **Una película o una serie no lleva sello de origen** (P4, 10 nov 2026, `isTitleItem`): el rombo de Stremio ya no decía nada (Trakt sincroniza; Stremio es solo respaldo); la línea queda solo con su texto («Serie · T2 E3 · quedan 12 min»). Stremio se nombra solo como servicio: Ajustes › Cuentas, la app Stremio y las listas de Stremio (`tests/web/origin-mark.test.mjs`). |
| `Badge(text, { large })` | `ui` | Etiqueta que llama la atención: «3 nuevos», «Recomendada» (sin mayúsculas). `large` sobre arte a sangre (el mosaico de Para ti). |
| `PlatformBadge(text, brand, { large })` | `ui` | «En Netflix», «N.º 1 en Disney+» como el iPhone: cápsula del color de la plataforma (`--platform-*`, vía `--platform-color`), su logo de JustWatch chico a la izquierda (`.badge__logo`) y el texto en blanco. Solo Netflix, Disney+, HBO Max, Prime Video y Paramount+ (`PLATFORM_PILLS`); las demás, `Badge` con el nombre en su estilo. En el mosaico de Para ti. |
| `Pill(label, { on, tone, icon })` | `ui` | Píldora que se elige: los filtros de Juegos y de ¿Qué vemos? (`tone: "outline"`), las pestañas de una lista y de las temporadas, y las búsquedas recientes (`tone: "fill"`). **Una sola pieza**: misma altura (`--pill-height`), mismo peso, lo elegido con relleno tenue (`pill--on`) y el foco invertido (`pill--focused` o `.is-focused`). **Píldora de ícono** (`className: "pill--icon"`, D5-A): solo el ícono y su nombre al enfocarla o al pasar el mouse; la llevan Guardado, Colecciones y Filtro avanzado junto a «Todo · Películas · Series» de Películas y series, separados de las pestañas por una rayita (`hero__kinds-gap`): las pestañas cambian lo que ves, los íconos abren otra pantalla. «Decide por mí» lleva arriba las pestañas «Tres que caben · Una por una» (el mazo). **Si no caben a lo ancho** (letra grande en 1280, 27 nov 2026), las herramientas de Películas y series (Decide por mí, Guardado, Colecciones, Búsqueda avanzada) quedan en su ícono y su nombre sale al enfocarlas o señalarlas, como Buscar (IN3-A); las pestañas no ceden (`hero.js · fitKinds`, `hero__kinds--tight`). |
| `.side-panel` + `.side-panel__panel` | `ui.css` | El menú flotante: vidrio fuerte separado de las orillas, del alto de lo que trae, sobre un velo: los menús (`sheet`). Con `side-panel--bottom`, sube desde abajo, a lo ancho: «Elegir versión» (`sources`); se apoya sobre el pie (`--hints-room` de margen abajo) y su alto descuenta ese margen y el de arriba (FI-7, 24 nov 2026: antes tocaba el borde de arriba). Comparten el velo, el marco y cómo entra y sale; cada uno pone su ancho, su relleno y su contenido. |
| `Segmented(choices, { onPick })` | `ui` | Valores segmentados: todas las opciones de un ajuste a la vista, cada una una `Pill`; la elegida en papel (`--color-primary`) y, dentro de una fila enfocada (foco invertido), se invierte con ella. Tocar o hacer clic en una la elige; con mando o teclado, ◀/▶ desde su fila. Solo cuando caben (`segmentable`: hasta cuatro valores y cortos); si no, el valor de siempre con ‹ ›. Con el dedo, del alto de `--touch-target`. En Ajustes (`settings`). |
| `Progress(fraction, { zero })` | `ui` | Cuánto llevas de un video. Sin avance no se dibuja; con `zero`, 0 dibuja la pista vacía (Colecciones, BL-14). |
| `LineSkeleton({ className, label })` · `PosterSkeletons(n)` | `ui` | Lo que todavía carga, con la forma de lo que llega y quieto (`skeleton`): un renglón gris del alto de su letra (`skeleton--line`) o un póster (`skeleton--poster`). Con `label`, el lector de pantalla dice qué se espera. La versión junto a «Ver» mientras se busca (`title__version--pending`) y las filas de «Versión» (`versions__skeleton`), como `VersionsSkeleton` y la zona derecha de `SplitPlayButton` del iPhone; nunca «Buscando…» ni una ruedita sola. |
| `SelectMark(on, { label, onPress })` | `ui` | La casilla de un póster mientras eliges varios (G3-A, `DSSelectMark` del iPhone): vacía, de vidrio fuerte con su filo; elegida, blanca (`--color-primary`) con la palomita en `--color-on-primary`; en la esquina de arriba a la izquierda, con el área del dedo (`--touch-target`). Clic o toque la elige o la suelta; con el mando, A sobre el póster. Reemplaza al «−» (`RemoveMark`) del 8 nov. |
| `RowCount({ className, veil })` · `rowCountText(at, total, { unit })` | `ui` | El único contador de fila (T12, 10 nov): «2 / 9» donde estás de cuántas (cifras tabulares, gris), o el total solo (o «9 juegos» con `unit`) cuando no hay uno enfocado; vacío no se ve. Lo usan las filas (`shelf__count`), Destacados (sin puntitos) y Juegos (`veil`: sobre el arte va en su cápsula con velo). Nada de «1 de 9» suelto. |
| `SectionHead(title, { meta, end })` | `ui` | Título de una zona con su dato y algo a la derecha. |
| `EmptyState({ icon, title, text, action, tone })` | `ui` | **El vacío, uno solo (C4)**: su ícono, un título que dice qué vas a tener ahí (nunca «No has…» ni «Aún no tienes…») y una línea; con `action` (`{ label, glyph, onPress }`), su **primer paso**, un `Button` principal con el glifo que lo hace (la pantalla atiende esa tecla; con el dedo o el mouse se toca). Lo usan el vacío del Inicio (antes una pieza aparte, «Ir a Juegos», «Mostrarlos», «Qué revisar»), una lista vacía («Agregar» en una lista tuya; «Volver a cargar» en las demás), Películas y series vacía («Buscar») y «Nada con esos filtros» («Quitar “Terror”»). |
| `ErrorState({ title, text, onRetry, glyph })` | `ui` | **El error, uno solo (C5)**, el gemelo de `failure()` de los avisos: `EmptyState` con `tone: "error"` (el ícono en `--color-danger`), qué pasó en palabras de Orbital, qué no se perdió («Lo que guardaste sigue guardado») y «Reintentar», que hace lo mismo otra vez (A o la tecla que diga su glifo; con el dedo, el botón). El texto del servidor nunca es el aviso: si sirve, va como detalle con `serverDetail(err)`. Lo usan el mazo, Colecciones, Explorar, Cambiar el arte, el calendario y una lista que no llegó; Conectar un aparato y Conectar Trakt cambian su «Otro código» por «Reintentar». `tests/web/notices.test.mjs` falla si un componente pinta `err.message`. |
| `FilterChip(label, { onRemove })` | `ui` | **Un filtro puesto, con su × (C7)**: tocarlo o hacerle clic lo quita (y solo ese). Vidrio con su filo, del alto de una píldora; con el dedo, de `--touch-target`. Con el mando, el mismo camino está en ☰ «Ordenar y filtrar». Arriba de una lista abierta (`list-screen`). |
| `ScreenHead({ eyebrow, title, lead })` + `.screen` | `ui` | Pantalla completa encima de todo (Conectar Stremio, Conectar Trakt): `.screen` es el marco (fondo, margen, entrada y salida con `screen--leaving`) y `ScreenHead` su encabezado («Cuentas» · título · una línea). **Dos composiciones**: *página* (el encabezado arriba, centrado, y el contenido debajo: Conectar Stremio, ¿Qué vemos?, Tu año; el calendario lo alinea a la izquierda porque su mes ocupa todo el ancho) y *diálogo* (una tarjeta al centro que lleva su propio encabezado: Conectar Trakt, OneDrive y iPhone, Cambiar el arte). Una pantalla nueva elige una de las dos. |
| `KeyHint(glyph, label, { small })` | `ui` | Botón del mando + qué hace («A Continuar»). **El pie de controles se arma con esta pieza.** |
| `.tile` | `ui` | Superficie enfocable de las pantallas nuevas: mismo radio, anillo de foco y atenuado. |
| `Button({ label, glyph, variant, yields, icon, busy, disabled })` · `setButtonBusy(button, on, label)` · `setButtonDisabled(button, on)` | `button` | Acción con su glifo, en cápsula. El principal (`variant: "primary"`), siempre blanco; los demás, de vidrio; con `icon`, redondo con su nombre debajo. `yields`: el que se encoge si la fila no cabe. Con mando no reciben foco (son la leyenda); con ratón o dedo se pulsan. | **Sus seis estados (C1, 24 nov 2026)**: reposo, hover, presionado, foco (`is-focused`), **esperando** (`busy`: true o el texto de lo que hace, «Contando títulos…», «Pidiendo…»; se queda del ancho que tenía —`--button-hold`—, su ícono ↻ gira donde iba el glifo y no responde a otro toque) y **apagado** (`disabled`: tenue, `--opacity-off`, sin responder). Los usan «Ver N títulos» de la Búsqueda avanzada mientras cuenta y «Otro código» de Conectar un aparato y Conectar Trakt mientras pide.
| `Flag(code, hint)` | `flag` | La banderita de un idioma donde lo eliges: filas de Elegir versión y Ajustes › Idioma y Subtítulos. Del alto de la letra, en 3:2. Sale de `orbital/flags.py` (los SVG de `img/flags/` y `core/flags.js` los escribe `scripts/flags.py`), que también la dibuja en el reproductor (Audio, Subtítulos, Versión): la misma en los dos. Latino y el español que no dice cuál: 🇲🇽; castellano: 🇪🇸; portugués: 🇧🇷 (igual que el iPhone). Una versión con dos audios lleva las dos. El lector de pantalla lee solo el nombre. |
| `AddonMark(kind)` | `addon-mark` | De qué complemento viene una versión (Fernando, 6 nov 2026: «un mini ícono»): Ⓣ Torrentio, Ⓒ Comet y la pieza (`addon`) para los demás, chico (`--icon-sm`) y tenue (`--color-text-muted`), junto a la calidad en «Versión» y en «Todas las de aquí» (X); en una enfocada toma el color del foco. `kind` es el `addon_kind` del servidor (`streams.addon_kind`, igual que `Streams.addonKind`). Lo de tu carpeta no lleva. El lector de pantalla dice el nombre. Es `AddonMark` del iPhone. |
| `Glyph(text, { small })` | `glyph` | El botón del mando en su color (A verde, B rojo, X azul, Y amarillo); cambia con el modo de entrada (`data-input`: mando o teclado). |
| `createKeyboard()` | `keyboard` | Teclado en pantalla (Buscar, alfabético de 7 columnas; Conectar Stremio, QWERTY de 10). Las columnas salen de la fila más ancha (`--keyboard-columns`); `iconOnly` deja solo el ícono (Atrás). |

**Lo elegido sobrevive (P6, 24 nov 2026)**: los filtros de una lista abierta (tipo, género, calificación, década y «ocultar vistas») se recuerdan por lista como ya se recordaba su orden (`list-screen` · `keptFilters`); el juego enfocado y el filtro de cada consola (`games`) y el canal de cada categoría de TV en vivo (`tv`) sobreviven al reiniciar con `rememberedMap(key)` (`core/storage.js`), un mapa que se escribe solo en el almacenamiento local.

**Espera que dice qué prepara (C9)**: «Buscando tres para ti…» (Decide por mí), «Buscando “<texto>”…» (Buscar), «Contando títulos…» (Búsqueda avanzada), «Trayendo los títulos de <lista>…» sobre el esqueleto de una lista y «Buscando lo que sale en <mes>…» (calendario). **Cifra con veredicto (C8)**: las horas de un juego en su página («Tu más jugado · 12 h más que el segundo», contra los de su consola: `playtimeVerdict`) y cuánto llevas de una colección («3 de 12 · te faltan 9», `collectionVerdict`); solo con datos reales.

## 3. Tarjetas y tiles (`card`, `tiles`)

| Pieza | Para qué |
|---|---|
| `Card(item, { caption, showAgo, pop })` (`card`) | Portada de un juego o video en filas y cuadrículas (`caption: "focus"`: el nombre solo bajo la enfocada). Sin arte: el respaldo con su nombre; apps: su ícono (`appIcon`). **Ninguna tarjeta muda** (P4, 10 nov 2026): una ancha lleva su nombre y su dato sobre el arte hasta que su logo ya se ve (`card--logo-ready`; si tarda o no llega, se queda el nombre) y un póster que es el arte de respaldo (`img/placeholders/`, `isStandInArt`) lleva su nombre encima (`card--named`), como «Mario Party Superstars». Prueba: `tests/smoke/test_ui_flows.py · test_every_card_says_what_it_is`. Esquina: estrella si es favorito (`item.favorite`), palomita si ya lo tienes en una lista de afuera (`item.owned`); la otra esquina, el puesto del Top 10 (`item.rank`, Netflix o lo más visto de una plataforma) con la misma placa oscura. Lo que te falta de algo a medias («T2 E3 · quedan 12 min») se lee entero sobre el póster con nombre (hasta tres renglones), no «queda…». **C10 (24 nov 2026)**: ningún texto va sobre un arte que no controlas sin su pieza: el nombre de una ancha y el de una con nombre encima («Terror») van sobre `Veil("bottom")` (`card__veil`, antes solo sombra o un degradado a mano), y el «hace 2 días» de abajo va en su placa (`Chip(…, { plate: true })`). |
| `RankedCard(item, options)` (`card`) | Un puesto en una lista Top 10 (todas sus portadas traen `rank`), como `RankedPosterCard` del iPhone: la cifra enorme en `--color-decorative` detrás del póster, que va encima a la derecha; el ▲ ▼ / «Nuevo» sube a la esquina. Devuelve `{ card, el }`: `card` es el botón enfocable y `el` lo que se monta. |
| `CollectionCard(item)` · `SourceBadge(source)` · `AwardWordmark(name, tint)` (`collection-card`) | Una lista como tarjeta, las mismas del iPhone (FanCard, AwardCard, YearCard, ListCard, BecauseCard): plataforma (su top 3 en abanico y su logo con el halo de su color), estudio (nombre en cápsula), género y temporada (el mismo abanico y, al frente, su ícono a color `.collection__emblem` —`img/collections/<slug>.png`, los 19 de Grok Imagine del iPhone, tal cual, sin filtro ni placa— y su nombre debajo; las temporadas con su color `--color-season-*`, los géneros neutros; el héroe dice «Género» o «Temporada»), premio (la estatuilla real al frente y su halo oro, plata o bronce), año (cuatro pósters y el número grande), lista tuya (dos pósters en pila, nombre, sello y cuántos) y «Porque viste X». Mide como una portada (alto `--card-height`, ancho por su proporción) y A abre su lista (`list-screen`). `SourceBadge`: el sello de origen junto a un título (TRAKT, STREMIO, ORBITAL) en `--color-source-*`. `AwardWordmark`: el nombre de un premio como logotipo (`--font-award`, mayúsculas espaciadas puestas por el JS, degradado de su metal `--color-award-*`); también en el héroe y en la lista abierta. En una fila `centered` (`.shelf__row--centered`) la enfocada va al centro y las de los lados más chicas y apagadas, con reflejo. |
| `FeatureHero` (`tiles`) | El destacado del Inicio sobre el arte a pantalla (§ 0). |
| `ArtFit(src, { poster, ratio, fallback, onReady })` (`art-fit`) | El arte de una caja ancha: la ficha (`title`), el escenario de «Porque viste» (`shelf`), la tarjeta ancha de Destacados (`Card` con `wide`) y lo ancho del mosaico de Para ti. Llena la caja; si la imagen es un **póster vertical** —se sabe (`poster`: no hay fondo ancho) o lo dice su medida al cargar (`tooNarrow` en `core/images.js`: la caja es más de 1,25 veces más ancha, en proporción, que la imagen)—, el **tratamiento de póster**: nítido y entero (`contain`) sobre una copia de sí mismo muy desenfocada (`.art-fit__blur`, la misma del estuche del destacado), como el fondo de ambiente con solo portada (`backdrop`). Nunca un póster recortado a una franja. No se ve hasta saber cómo va (sin recorte primero y póster después); en caché, al instante. Quien lo usa dice dónde cae el póster (`--art-fit-x`, a la derecha por omisión: el texto va a la izquierda), su aire (`--art-fit-pad`) y de qué altura se recorta (`--art-fit-y`). En la ficha cada fondo nuevo se carga primero y entra fundido (`--duration-base`) sobre el anterior. |
| `PersonChip(person, { onPress })` · `PersonHead(person)` (`people`) | Una cara del reparto o de quien la hizo, como CastMember del iPhone: foto redonda (o sus iniciales), nombre y papel («Dirección», o el personaje), en la fila «Reparto» de la ficha (bajo «Más como esto»). Foco: anillo en la foto. `PersonHead`: la persona arriba de su filmografía (`list-screen` con `person`): foto grande, de dónde es y su biografía en tres líneas (X la despliega). |
| `orbit` (`orbit.js` + `orbit.css`) | El foco de todo lo que es contenido (D3-A): un anillo (`<span class="orbit">`) que `core/focus-mark.js` le pone a la pieza al enfocarse y le quita al perder el foco (`wearOrbit`, `shedOrbit`, `ORBIT_HOSTS`): el filo quieto del color del arte con su línea oscura por dentro (la luz que daba una vuelta al llegar se quitó el 15 nov). Lo llevan `.card`, `.tile` (menos `showcase__item`, renglón invertido), `.person-chip` (alrededor de su foto), `.episode` (en su miniatura) y `.calendar__cell`; cada una dice dónde va con `--orbit-out` (0 = por dentro, si la pieza recorta) y su curva con `--orbit-radius`. Nada se anima. |
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
3. **Esquinas concéntricas:** lo que va dentro curva como la tarjeta menos el margen (un `--radius-inner-*` por par, § Ritmo); así no
   asoman esquinas claras entre la miniatura y el borde.
4. **El avance de un video va sobre la imagen**, abajo, con `--inset-poster` (póster, miniatura de renglón), nunca como
   renglón extra de texto.
5. **Nada más grande que su tarjeta:** una imagen dentro de un renglón se mide contra el alto del renglón
   (`grid-template-rows: minmax(0, 1fr)` + `height: 100%`), no contra un tope fijo.

**Ningún texto de tarjeta o botón se sale**: una línea con «…» (o `line-clamp` con espacio para las
letras que bajan: g, p, j, y).

## 4. Pantallas y vistas (cada una con su JS y su CSS del mismo nombre)

**Nada queda bajo el pie** (16 nov 2026, Decide por mí): una pantalla que no se desliza reparte su altura; lo que puede achicarse
(los carteles de `decide__stage`, con `container-type: size` y `100cqh`) toma lo que sobra, con su tamaño de siempre como tope, y
las preguntas y botones siempre caben sobre `hints`. En la tele de 1080 «Ánimo» quedaba tapado. Prueba:
`tests/smoke/test_ui_smoke.py · test_no_text_is_cut_in_half` (1920×1080 y la Legion Go con letra grande).

**Su trabajo · su protagonista** (P1, revisión del sistema base, 24 nov 2026): cada pantalla tiene un solo trabajo y una sola
pieza que lo cumple; lo demás baja de volumen. Si una pantalla nueva no cabe en esa línea, tiene dos trabajos.

| Componente | Qué es | Su trabajo · su protagonista |
|---|---|---|
| `status-bar` | Barra de arriba: marca, Buscar, pestañas (LB/RB), Alexa (navegable: muestra ejemplos de órdenes), lo que está abierto (un ícono quieto en `--color-live` —▶ si es un video, el control si es un juego; en pausa, ▶ en ámbar— y su nombre, centrado con la altura de las mayúsculas), batería y hora. | Decir dónde estás y llevarte a otra sección · las pestañas (la de ahora, encendida) |
| `hints` | Pie de controles del momento (piezas `KeyHint`). | Decir qué hace cada botón aquí y ahora · la primera pieza (lo principal, A) |
| `foryou` | Para ti (a la izquierda del Inicio): el mosaico de lo tuyo mezclado (`foryou-mosaic`). A ve o juega, Y abre Opciones (ficha, «No me interesa»). Las listas viven en Películas y series (`core/media-plan.js`), con el orden del iPhone. | Darte algo tuyo para ver o jugar sin buscarlo · la imagen enfocada del mosaico |
| `foryou-mosaic` | Mosaico de Para ti: columnas de imágenes; la enfocada crece y enseña etiqueta, logo y un dato; bajar sube todo (cascada) y quieto 2 s entra en ambiente (como el iPhone): todo sube despacio durante 90 s, se frena y se queda quieto hasta el siguiente botón (Orbital no gasta mientras nadie la usa). La deriva son tramos de `--duration-glide` que anima el compositor; JavaScript solo trae piezas al empezar cada tramo. Ícono de esquina: la consola del juego, o serie / película. | Pasear por lo tuyo · la pieza enfocada (crece y dice qué es) |
| `trakt-link` | Conectar Trakt: un código grande para escribir en trakt.tv/activate desde el celular. | Conectar Trakt sin teclear · el código grande |
| `tv` | TV en vivo (la última de la barra, después de Películas y series): los canales de México. A la izquierda, las categorías en una lista vertical siempre a la vista (`.tv__cat`: ícono, nombre y cuántos canales; la elegida con relleno tenue aunque el foco esté en los canales); a la derecha, arriba, el canal enfocado en vivo (miniatura sin sonido, o su logo mientras conecta) con su nombre grande, y abajo una cuadrícula de `.tile` con el logo del canal (o las letras de su nombre), su número (`Chip`) y su nombre. **↑↓ en la lista cambian de categoría al instante, → pasa a los canales, ← regresa; LT/RT también cambian de categoría** (LB/RB siguen cambiando de sección). El logo siempre va **dentro de su caja** y ya viene parejo de Orbital (recortado, y sobre placa clara si es oscuro). Arriba a la derecha de cada canal: `Badge` «Al aire» (el que ves en el reproductor) o `Chip` «Sin señal reciente» (el que ya falló una vez, que además va al final de su lista y atenuado); el número y el aviso llevan placa oscura para leerse sobre cualquier logo. A sintoniza (o vuelve al que ya está al aire), teclear un número sintoniza ese canal, X vuelve a buscar y revisar los canales, B vuelve (primero al primer canal, luego a Inicio). Sin canales dice qué pasa (buscando, sin Internet). | Poner un canal en vivo · el canal enfocado, en vivo arriba a la derecha |
| `phone-link` | Conectar iPhone: un QR para la cámara del iPhone (la dirección del túnel y el token van dentro de la imagen, nunca en texto). | Conectar el iPhone · el QR |
| `list-screen` | Una lista abierta de Películas y series (como SortableGrid del iPhone): arriba la lista en grande (estatuilla, logo o año, nombre, sello y dato), pestañas en píldora (Series · Películas, o los rankings de una plataforma: LB/RB o ↑ hasta ellas), los filtros activos en cápsula y la cuadrícula de pósters con su nombre en dos renglones y su dato en el tercero (BL-5: `.card__caption strong` en toda cuadrícula; entre renglones, `--caption-room-titled`) (y el año del premio o el día del estreno en placa). ☰ abre «Ordenar y filtrar» (como viene, IMDb, Trakt, «Año: más nuevas / más viejas», A–Z; cada orden y filtro avisa al cambiar, `onChange`, y el pie dice cuántos van; tipo, género, ocultar lo que ya viste); cada lista recuerda su orden; un ranking no se reordena. A abre la ficha (encima; B regresa a la lista), Y sus opciones (también clic secundario o mantener el dedo), B cierra. Una lista tuya (Mi lista, tus listas de Trakt y los montones de Guardado) se edita como el iPhone (G3-A, 10 nov 2026): X, ☰ › «Elegir varios» o el botón «Editar» junto a su nombre ponen la `SelectMark` en cada póster; A o la casilla eligen, Y o «Con las elegidas…» abren lo que se puede hacer (`onBatch`), «Todas» las elige, «Agregar» (☰ › «Agregar a esta lista…») abre Buscar para elegir y B o «Listo» terminan. «Ordenar a mano» (☰ de una lista tuya, G4-A): A toma el póster, las flechas lo mueven (`list-screen__grabbed`: sube más que el enfocado y lleva la placa de mover, `list-screen__grab`, BL-6), A lo suelta y B o «Listo» guardan el orden (`onReorder`). `open({ tab })` abre en esa pestaña (Guardado al ponerse al día). Una persona: X «Leer la biografía» / «Ver menos» solo si su biografía se corta (FI-14, 24 nov 2026; antes «X Biografía» aunque cupiera entera). Cambia al instante con «Deshacer» (Y) en el aviso y, si Trakt no acepta, regresa y lo dice. | Elegir algo de una lista · el póster enfocado de la cuadrícula |
| `decide` | «Decide por mí», pestaña «Tres que caben» (X en Explorar, R3 o D desde cualquier sección, el botón de Películas y series, su fila «¿No sabes qué ver?» y su puerta en el Inicio: `DecideDoor` + `DecideDoorHero`, NQ-1/2/5). AD-1…AD-12 (16 nov 2026): se ve y se maneja como el Inicio. `DecideBackdrop` (el arte de lo enfocado con el velo de Orbital; en el mazo, difuminado), `DecideHead` (encabezado compacto: «✦ Decide por mí», `DecideModes` con lo que hace cada pestaña y el reloj), `DecideInfo` (a la izquierda, igual en las dos: «Cabe en tu noche · termina a las …», el logo o el nombre, los datos y dos renglones), los botones del destacado («Ver ya» A, «Ficha» Y; el porqué una sola vez, en la etiqueta o al frente de los datos, BL-15), abajo las tres como tarjetas anchas, «Otras tres» (tarjeta, también X y el pie lo dice; BL-16: ya no también botón) y «Filtros» (tarjeta con su numerito) que abre su panel de vidrio (Qué tipo, Duración, Ánimo; A elige con ✓, B lo cierra y vuelve a elegir). «Hoy no» y «No me interesa» en ☰. LB/RB cambian de pestaña. Marco `.screen`. | Decidir qué ver esta noche · el destacado con «Ver ya» |
| `match-deck` | «Una por una», la segunda pestaña de «Decide por mí» (AD-10, 16 nov 2026): el mismo encabezado y bloque de la izquierda que «Tres que caben» («4 de 20 · termina a las …») y a la derecha el mazo (el póster con dos asomando detrás); una fila de botones: «Ver ya» (A) y ✕ Paso (◀) · ★ Para hoy (▲) · ♥ Guardar (▶) con su nombre. Al decidir, la carta se tiñe, asoma su sello y sale volando. Y la ficha · X deshace lo último · LB/RB «Tres que caben» · B regresa. | Decidir una por una · la carta de arriba del mazo (al acabarse, el vacío al centro con su botón: «Ver las que guardaste» o «Tres que caben», BL-17) |
| `showcase` | Colecciones (☰), como la vitrina y la repisa del iPhone: los premios y las listas famosas (Criterion, Top 250 de IMDb, NYT) en tarjetas, cada una con el nombre y su línea en hasta dos renglones y, abajo, su barra con «12 de 96» al lado (BL-13; sin nada visto, la barra vacía: `Progress({ zero: true })`, BL-14). A abre su lista (`list-screen`). | Escoger una colección · la tarjeta enfocada con su avance |
| `filter-panel` | El filtro avanzado (FA-1, 16 nov 2026), en la línea de «Decide por mí»: su encabezado (`DecideHead` con su nombre, lo elegido y el reloj) y de fondo el arte del primer resultado (`DecideBackdrop`). A la izquierda las siete preguntas en acordeón: solo la enfocada se abre con sus píldoras (✓ en la elegida, que lleva el foco; ◀▶ eligen al instante); las demás dicen su valor, en su color si cambió. A la derecha, en vivo, cuántos hay y los primeros diez pósters. Y «Ver N títulos» desde cualquier pregunta, X borra, A pasa a la siguiente, B cierra. Con cero: sin muro y «Borrar filtros» como botón principal. | Acotar hasta encontrar qué ver · «Ver N títulos», con el número en vivo |
| `calendar` | Próximos estrenos en vista calendario (la tarjeta «Próximos estrenos»), como «Sale hoy › el mes» del iPhone: el mes en una cuadrícula de lunes a domingo; cada día con el arte de lo que sale (dos el mismo día: la casilla partida; más: «+N»), hoy con el número en blanco y lo ya pasado atenuado. A la derecha, lo que sale el día enfocado (póster, episodio, hora y dónde). Un mes sin nada (FI-15, 24 nov 2026, C4): a la derecha `EmptyState` «Nada en enero», cuándo sale lo próximo (lo busca mes por mes, hasta el tope del servidor) y «Ir al próximo estreno (14 feb)» (Y o el botón; abre ese mes en ese día). Cruceta día, LB/RB mes, A abre la serie (con varias, baja a la lista), B vuelve. Marco `.screen`. | Saber qué sale y cuándo · el día enfocado y lo que sale ese día |
| `art-picker` | Cambiar el arte de una película o serie (Opciones › «Cambiar el arte»): dos filas, Póster y Fondo, con lo que tiene TMDB (primero en español); la primera casilla es «El de siempre» y la elegida lleva el borde del acento. La cruceta recorre, A elige (se ve ya en la biblioteca, Para ti y la ficha) y B cierra. | Cambiar el arte de un título · la casilla enfocada |
| `home` | Inicio, como el Apple TV (§ 0): arriba lo que te toca sobre su arte (`FeatureHero`, con su porqué turquesa: «Seguir viendo» para un episodio, «Seguir jugando» para un juego), abajo «A continuación» (tarjetas anchas de juegos, películas y series juntos; enfocar una la pone arriba), Mi lista y Tus consolas; al bajar a ellas el Inicio se desliza. | Retomar lo tuyo · lo de arriba (`FeatureHero`) con su botón |
| `games` | Juegos en dos pisos (§ 0): debajo de la barra, tus consolas en un `GlassSwitch` (LT/RT, o ↑ y A); el juego enfocado a pantalla con su porqué, logo, datos y botones; abajo sus juegos con filtros (`browse`). Al bajar de la primera fila, las barras y el juego se van. | Jugar · el juego enfocado, a pantalla, con «Jugar» |
| `game-page` | La página de un juego (Opciones › «Ver ficha»; Juegos «C», como la página de producto del Apple TV): su arte a pantalla con su porqué, logo, datos, sinopsis y botones; a la derecha, en vidrio, lo tuyo con él; abajo, los demás de su consola (←/→ cambian de juego y el fondo con él; A juega). | Decidir si juegas este juego · su arte con «Jugar» |
| `rail` | Riel lateral de las categorías de Ajustes: casillas con ícono; al enfocarlo se abre como pestaña y enseña el nombre y un dato de cada una. | Ir a una categoría de Ajustes · la casilla enfocada |
| `browse` | Las piezas de una vista con portadas y filtros (Juegos, TV en vivo, ¿Qué vemos?): filtros como pestañas de texto que siempre caben en un renglón (`fillFilters`, `fitBar`, `showFilter`), la cuadrícula que se recorre lo justo (`keepInView`), la ventana de las cuadrículas largas (`windowCells`, `fillWindow`: V4) y el fundido al cambiar (`replay`). | (Piezas, no pantalla) Recorrer portadas filtradas · la portada enfocada |
| `hero` + `shelf` | Películas y series: el destacado arriba y las filas de portadas. El destacado cede la descripción antes que cortar los botones. Películas y series lleva, bajo Destacados, **Seguir viendo** (lo que dejaste a medias en Stremio, lo más reciente primero; Y › «Quitar de Seguir viendo») y luego el orden y los nombres de Para ti › Listas del iPhone (`core/media-plan.js`): Destacados, Porque viste, lo general con su sello, Nuevo en tus plataformas, Tus plataformas, Premios, Estudios, Por año, Próximos estrenos, Listas de Trakt y Listas de Stremio (y Por género al final). LT/RT pasan de grupo en grupo; ☰ suma «Ir a…» y «Mostrar» (Todo · Series · Películas). Las pestañas Todo · Películas · Series del héroe se enfocan con ↑ desde la primera fila (T5, como los filtros de Juegos; el pie lo dice: «↑ Mostrar»): ◀ ▶ las recorren, A elige, ↓ o B regresan a la misma tarjeta, que mientras tanto no se ve enfocada (`shelf.rest`). «Porque viste» va en escenario (`row.stage`, `.shelf__stage-row`): a la izquierda un panel fijo (`--because-stage-width`) que es un carrusel contenido de tus últimos títulos: uno a la vez, con su arte y su logo (sin él, su nombre en negrita), un punto por título y «Sugeridas ›». ◀ ▶ pasa de uno a otro (el panel lleva el anillo de foco y sus tarjetas quedan ocultas en la fila) y cambia lo relacionado, que se recorre a la derecha sin tapar el panel; **RT salta de tus títulos a lo sugerido y LT regresa al título elegido** (el pie lo dice: «Ver sugeridas» / «Tus títulos»; del otro lado, LT/RT pasan de grupo como siempre). Moverte entre tus títulos solo rehace esa fila (`updateRow`), no toda la biblioteca. | Encontrar qué ver · el destacado de arriba, que sigue a la tarjeta enfocada |
| `title` | Ficha de una película o serie, **el arte primero** (como Apple TV): a sangre y casi entero; abajo a la izquierda solo el logo, un renglón de datos con las calificaciones (`.title__meta`), la sinopsis en tres renglones, lo disponible en texto tenue (`.title__avail`: «4K · HDR · Al instante»; si lo que va a sonar se sale de lo pedido, primero el aviso en `--color-warning`: «Solo en castellano: no hay latino») y los botones **en un renglón**: «Ver» / «Continuar la película» (con cómo va a sonar debajo: «Latino · 1080p · Sin subtítulos») y, a su lado, redondos solo con su ícono, cuyo nombre sale debajo del enfocado (sin mover nada). «Guardar» abre **«Guardar en…»** (como el iPhone): una hoja con casillas —Mi lista (Stremio), tu watchlist y cada una de tus listas de Trakt— que cambian al instante (`save-toggle`, en su lugar) y regresan si el servicio falla; el botón dice «Guardada» si está en cualquiera. Con más de cuatro redondos, los de menos uso (descargar, el iPhone, tu carpeta) esperan en «Más» (`ICONS.more`). Quién la hizo vive en «Reparto», al bajar. **Serie**: abajo, las temporadas en `Pill` (LB/RB, LT/RT de 5 en 5) y los episodios en una **fila de imágenes** (`.episode`: miniatura 16:9 con número, ✓, avance y «Continuar» / «Sigue»; su nombre debajo); ◀ ▶ episodio y arriba se lee el enfocado (`.title__episode` «T2 · E3 · Nombre» y su sinopsis, que guardan su lugar: nada brinca); ↑ a los botones, ↓ a «Más como esto». Abajo (`title__more`: «Más como esto», reparto y datos) sigue el arte desenfocado con el tono encima (T8, 10 nov; antes un tono liso), y entre el título de cada fila y sus portadas solo `--layout-title-to-content` y el filo de la órbita: en «La saga» y «Más como esto» la enfocada crece hacia abajo, desde su esquina de arriba (FI-3, 24 nov 2026, B3: arriba del título ~4 veces el aire de abajo; antes 65 contra 62 px). FI-4: en una serie, el renglón del nombre del redondo enfocado se guarda bajo los botones y el del primero no se centra (se salía del margen). FI-5: `.title__episode` en dos renglones si el nombre del episodio es largo. FI-6: entre el arte y el texto va `Veil("leading")` (`title__veil`) y la clasificación usa `--color-on-art-secondary`: sobre un arte claro (Severance) se leían a 1,1:1. FI-1: bajo los botones, un pedido en cola dice «Tu pedido está en cola en la nube». | Ver este título (o decidir si verlo) · el arte y el botón principal («Ver», «Continuar la película», «Continuar T2 E3») |
| `sources` | «Versión» de un video (Y en la ficha), en un `side-panel--bottom`: una fila por **idioma de audio** (`.versions__row`: tu idioma, luego el original y los demás; «Tu idioma», «Original» o «Tal vez» bajo el nombre) y, a la derecha, **solo las calidades que hay** (`.version`: la resolución, «Al instante» / «Tarda en empezar» y lo esencial; la recomendada con `Badge` arriba a la derecha de su casilla —fuera del flujo: nunca se corta—, una que no menciona el título con `Chip` «Puede ser otra película» (o «otra serie»), una de otra temporada con «Parece de otra temporada»; con letra grande pasa a dos renglones). La recomendada es la que pone «Ver» (con «Continuar», la de antes). En un episodio, arriba «Solo este episodio | Desde aquí» (LB/RB; `.sources__scope`): «Desde aquí» hace que la serie siga con el idioma y el doblaje de la que elijas. Sin casillas vacías ni contadores. Abajo, en una línea (`.sources__why`), los idiomas de la enfocada y cómo lo sabemos: Comprobado, Lo dice el nombre, Lo dice el sitio, Es el original, No dice idioma, Tal vez (`core/watch.js` · `PROOF_LABELS`). ↑↓ idioma (se queda en la misma calidad), ◀ ▶ calidad, A ve, X abre todas las de esa fila y calidad (`.source`, con su nombre técnico; FI-9: el pie y la línea de abajo dicen «Ver las 23 en 1080p», no «Todas las de aquí»), B regresa. Los datos de una calidad (`.version__fact`) van enteros: el que no cabe se suelta completo (FI-8). Sin versiones, `EmptyState` «No encontré dónde ver esto» con «Buscar otra vez»; con error, `ErrorState` con «Reintentar»; en los dos, sin la explicación de «Al instante» (FI-10). El panel va pegado abajo, sobre el pie, con el mismo margen arriba (FI-7). | Elegir con qué idioma y calidad ver · la versión recomendada (`Badge`) |
| `search` | Buscar juegos, películas y series (⧉, S o la lupa de la barra): a la izquierda el campo y un teclado alfabético de 7 columnas (A escribe, X borra, Y espacio; con un teclado físico o el del iPhone se escribe directo, y se puede dictar); a la derecha, desde la 2.ª letra (con una, lo de la caja vacía), los resultados en vivo en la cuadrícula de una lista, agrupados (Tus juegos, Películas, Series) y con el mejor resultado primero. → (desde la orilla del teclado) o RT pasan a los resultados, ← regresa, B cierra; en los resultados Y abre las Opciones de la portada (`onMore`, también clic secundario o el dedo sostenido) y X no hace nada (BL-4). Sin nada, el vacío con «Borrar todo»; sin conexión, `ErrorState` con «Reintentar» debajo de tus juegos (BL-1, BL-2): su botón se enfoca como un resultado más. Con la caja vacía: tus búsquedas recientes, lo que estás viendo, tus juegos y los géneros. También elige qué agregar a una lista tuya («Agregar»). | Llegar a un título por su nombre · el mejor resultado |
| `login` | Escribir con el mando lo que no se puede evitar: Conectar Stremio, una clave (TMDB, RAWG, Trakt, tu nube), el nombre de una lista nueva o tu nota. Los campos, un teclado QWERTY con mayúsculas y símbolos (A escribe, X borra, Y muestra u oculta lo secreto, LT/RT cambian de campo, B vuelve) y, a un lado, un QR para escribirlo desde el celular (llena el formulario y lo envía solo; en los formularios que lo tienen). Con un teclado físico se escribe directo y una clave se pega con Ctrl+V. La ayuda (`lead`) dice dónde se saca la clave; la etiqueta del campo solo dice qué es («Tu clave de Real-Debrid»). | Escribir lo que no se puede evitar sin sufrir con el mando · el QR del celular cuando lo hay (el teclado es el último recurso, P5) |
| `settings` | Ajustes a pantalla completa (☰ › Ajustes, marco `.screen`): a la izquierda el `rail` con ocho categorías (Resumen, Ver, Complementos, Jugar, Tele y voz, Pantalla y sonido, Cuentas, Sistema; `SETTINGS_CATEGORIES` en `core/menus.js`; Complementos, «La TV sin Stremio» S1: «Vienen con Orbital», «Traídos de tu Stremio» con «Volver a traer», y «De dónde salen» con «Volver a los de Stremio»; cada uno dice si contesta, `addonHealth`, y A abre `addonMenu`: Prender o Apagar, Subir, Bajar, Quitar con «Deshacer»; en Torrentio, primero «Configurar» —corte S3, `torrentioMenu` y sus hojas: idiomas, calidades, sitios—, donde A cambia al siguiente valor y cada cambio se guarda con «Deshacer»), en su columna (no flota) y abierto mientras está enfocado, con el dato de cada una (`settingsMeta`); a la derecha la lámina de la elegida (`settingsCategory`): título, una línea, y **las filas de una hoja** (`sheet__item`, `sheet__icon`, `sheet__value`…: mismo foco invertido) con los valores en `Segmented` o con ‹ ›; lo que falta con el ícono en ámbar (`settings__row--warn`). Al pie, la ayuda de la fila enfocada en una línea (`settings__help`). Cuentas empieza por Real-Debrid (corte S2: los días de Premium o la causa en palabras; A abre `debridAccountMenu` con de dónde salió la clave, «Tus pedidos» —`debridRequestsMenu`, cada pedido con su estado en palabras e ícono y quién lo pidió— y en cada pedido `debridRequestMenu` con «Cancelar» primero y «Cancelar pedido»). Resumen enseña primero lo que falta (`settingsMissing`: la voz que no llega en dos días, Real-Debrid sin conectar, vencido o por vencer en una semana, sin complementos prendidos o Torrentio que no contesta, Trakt, el iPhone; Stremio ya no, corte S4: en Cuentas va al final como «Stremio · respaldo», opcional). Riel: ↑↓ categoría (se ve al instante, la lámina atenuada), ▶ o A entra, B cierra. Lámina: ↑↓ fila, ◀▶ cambia el valor (en una fila sin valor, ◀ vuelve al riel), A el siguiente valor o abre, LB/RB categoría, B al riel. Mouse y dedo: tocar una categoría la abre, un segmento lo elige, una fila la abre, ‹ › se tocan; la lista se desplaza con la rueda o el dedo. Lo que abre una fila (Cuentas, Emuladores, Qué ha oído…) sale encima, en una hoja o su pantalla, y B regresa a Ajustes. | Cambiar cómo funciona Orbital · las filas de la categoría elegida |
| `sheet` | Hojas laterales (menús cortos, el panel rápido, atajos). Encabezados de sección (`heading: true`) que no se enfocan; se desplaza con el foco. Una cuenta o servicio lleva su logotipo real (`mark`: Stremio, Trakt, TMDB) en lugar del ícono, y un estado que ya está bien (`ok`: «✓ Conectada», «✓ Guardada») va en `--color-ok`. El valor de la derecha (`value`) ocupa a lo más el 40 % del renglón, con cifras del mismo ancho (AJ-12, AJ-16); una fila de puro texto no lleva valor (AJ-5). Una fila puede llevar su barra de avance bajo la línea (`progress`: 0–1, `Progress` con `.sheet__progress`; los pedidos que bajan en «Tus pedidos», FI-13). | Elegir una acción o un valor sin salir de donde estás · la opción enfocada (la primera, la segura) |
| `toast` | Aviso: el mismo del iPhone (`Toast` / `BannerView`). Píldora arriba a la derecha, pegada a la barra de estado (nunca encima de una hoja ni de las pestañas). **Tono** (`tone`): `info` (gris), `success` (papel), `warn` (ámbar), `error` (rojo; dura `--duration-notice-long` y se anuncia como alerta), más `progress` (un texto que acaba en «…»: su ícono gira) y `voice` (Alexa). Título en un renglón y `detail` en el segundo (un « · » los parte solo); sin «Listo:» al principio: lo dice el ícono. Acción como el «Ver ›» del iPhone: `action: { label, glyph, onPress }` («Y Deshacer ›»). Con `image` (al volver de un juego), su portada ya decodificada. Dura `--duration-notice` (= `Timing.banner` del iPhone). **Entra por partes** (`--*-notice-*`, ver Movimiento): el ícono (o la portada), luego el vidrio (`toast__glass`) que se desliza desde el ícono dentro de su recorte (`toast__surface`, con aire a la derecha para el rebote: nace como un círculo y se estira sin deformar sus esquinas) y al final el texto, la acción y la sombra (`toast__shade`); la cuenta regresiva va dentro del vidrio. | Decir qué pasó sin interrumpir · el título del aviso (y su acción, si la trae) |
| `boot` | Pantalla de arranque (`#boot` en `index.html`, `js/app/boot.js`): la entrada del iPhone (`OrbitalWordmark`, con sus mismos tiempos: `--duration-brand-*`): sobre negro, el anillo se dibuja, las letras de «orbital» suben una tras otra y la luna cae con un rebote; al estar lista la biblioteca, la marca viaja y se encoge hasta su lugar exacto en la barra mientras Inicio aparece (la de la barra no hace su propia entrada). Con movimiento reducido, un fundido. Es un componente como los demás (su CSS está en `main.css`, no en línea) y también respeta movimiento reducido. | Arrancar sin pantalla en blanco · la marca de Orbital |
| `launch-overlay` | Pantalla de carga al abrir algo: la portada y, alrededor, un satélite que **va pintando su órbita** (no hay anillo dibujado: `launch__tail`, una estela que se apaga detrás de él y gira con el mismo reloj). | Decir que algo se está abriendo · la portada con su satélite (B «No abrir») |
| `viewer` | Visor de capturas a pantalla completa (Panel rápido › Capturas): la captura y, abajo, su nombre, cuándo se tomó y «3 de 12». ◀ ▶ o deslizar pasan de una a otra; un clip no se ve aquí: A (o tocarlo) lo abre con su reproductor; B cierra. | Ver tus capturas · la captura |
| `touch-back` | «Atrás» y «Menú» con el dedo (sin botón B ni ☰): «Atrás» arriba a la derecha sobre cualquier vista encima, «Menú» abajo a la derecha en las pantallas de siempre. Solo se ven con `data-input="touch"`. | Volver o abrir el menú sin botones · «Atrás» |
| `backdrop` | Fondo: arte del foco, o el espacio vivo (estrellas y luz) del Inicio, Juegos y Para ti. | Ambientar sin competir · ninguno: el arte de lo enfocado es de la pantalla de encima |
| `setupMenu` («Tu consola») | La hoja de la primera vez (la abre el aviso «Tu consola» al arrancar; después, Ajustes › Sistema › Tu consola): qué encontró Orbital («Encontré 21 juegos» o «Dónde poner los juegos»), «Películas y series» (✓ Listas o Configurar), Para ti (Trakt) y al final «Ir a Inicio» (la primera vez) o «Volver». | Decirte qué ya funciona y qué falta · el primer renglón («Ver mis juegos» o lo que falta) |
| `moviesSetupMenu` (el primer «Películas y series») | Tres pasos, una sola vez, y cada uno se deja para después: 1 · Tu nube (Real-Debrid, TorBox o AllDebrid), 2 · Complementos (los recomendados ya vienen armados), 3 · Trakt; y Tu iPhone, opcional. Cada renglón dice si ya está (✓) y abre lo suyo; se reabre desde «Tu consola» o Ajustes › Resumen. | Dejar listas las películas y series · el primer paso que falta |
| `tourMenu` (la guía) | Cinco hojas («Guía 2 de 5») con los atajos del mando que tienes (Legion Go o GameSir): jugar y volver, cerrar un juego, Panel rápido, buscar y la voz. Cada botón dice a dónde lleva («Aprender a cerrar un juego») y al lado va «Saltar la guía». La última dice qué ya sabes y dónde vuelve a estar (☰ › Cómo se usa), con «Ir a Inicio». Sale la primera vez y desde «Cómo se usa». | Aprender lo esencial del mando · el atajo de este paso (su texto) |
| «Guardar en…» (`app/list-editing.js` · `saveMenu`) | La hoja de «Guardar» de una ficha o de las Opciones de una tarjeta, como el iPhone: casillas que cambian al instante —Mi lista y Favoritos (Trakt), tus listas de Trakt y, de respaldo, la biblioteca de Stremio— y regresan si el servicio falla. Sin listas: «Tus listas de Trakt salen aquí» y «Nueva lista» (se crea privada en Trakt y el título entra en ella). | Poner este título donde lo quieres · la casilla de Mi lista |

## 5. Comportamiento con el mando

> **Regla de las cuatro superficies (Fernando, oct 2026).** Todo cambio en la app de escritorio (interfaz y reproductor)
> se diseña y se prueba para las cuatro formas de usarla: **control** (mando), **teclado**, **mouse** y **touch** (la
> pantalla de la Legion Go). Cada acción nueva dice cómo se hace en las cuatro: su botón del mando y su tecla en las
> pistas del pie (`KeyHint`/`Glyph`, que cambian con `data-input`), algo que se pueda **señalar y hacer clic** con el mouse,
> y un botón tocable del tamaño del dedo con touch (en el reproductor, `player_ui.pills` y `targets`). Un atajo «oculto»
> (mantener un botón) siempre tiene también un camino visible en el menú, y el menú dice el atajo. Nada se da por listo
> sin evidencia en las cuatro.

- **Los modelos de foco (R3-5, 11 nov 2026).** Hay tres maneras de decidir adónde va el foco con ↑↓←→, y cada pantalla
  usa la que le queda a su acomodo. Las tres terminan igual: **una sola pieza con `.is-focused`, a la vista y sin nada
  encima** (`tests/smoke/test_focus.py · test_focus_is_never_lost`: 300 teclas al azar con semilla fija desde cada pantalla,
  con A, X, Y, B, LB/RB, LT/RT, ☰ y buscar; todo POST contesta 409, así que nada se abre de verdad).

  | Modelo | Cómo decide | Dónde | Por qué ahí |
  |---|---|---|---|
  | **Fila y columna** | Un índice: ←→ ±1, ↑↓ ± las columnas (o fila `r`, tarjeta `c`, y cada fila recuerda su `c`) | Las filas de Películas y series (`shelf`), una lista o colección en cuadrícula (`list-screen`, `.card-grid`), el mosaico de Explorar (`foryou-mosaic`, por columnas), el calendario (7 por renglón), las hojas y los menús (una columna), la lámina de Ajustes | Piezas del mismo tamaño en renglones parejos: el destino se sabe sin medir nada (barato aun con cientos, junto con `.card--slot`), y volver a una fila te deja donde ibas |
  | **Espacial** (`core/spatial.js`) | Mide las piezas (`data-focus-id`, `measureFocusables`) y `nextFocus()` elige la más cercana hacia ese lado, primero dentro de un cono de 45° | Inicio (destacado, «A continuación», Mi lista, Tus consolas), Juegos (filtros y cuadrícula), TV en vivo (categorías y canales), Buscar (teclado ↔ resultados), Colecciones | Piezas de tamaños distintos o dos bloques lado a lado: lo que está «abajo» depende de dónde cae, no de un índice; si el acomodo cambia (otro tamaño de pantalla, el dedo), sigue acertando |
  | **`handle` propio** | La pantalla tiene zonas con nombre y cada flecha significa algo en cada zona | La ficha (botones → episodios → Reparto, Más como esto, Reseñas, Detalles; LB/RB temporadas), Elegir versión, Decide (pestañas y tres tarjetas), el mazo «Una por una» (las flechas deciden, no mueven: la carta de arriba es lo enfocado), Ajustes (riel ↔ lámina), Filtro avanzado, conectar cuentas | Las flechas no solo mueven: pasan de zona, cambian de temporada o deciden; un índice o una medida no saben eso |

  Lo que encontró la prueba y se corrigió: en «Una por una» no había nada enfocado (ahora la carta de arriba lleva
  `.is-focused`, sin órbita: es lo único al frente) y en la ficha, al bajar a «Detalles», el foco desaparecía (ahora la parte
  entera es lo enfocado, con la placa de vidrio `--color-glass-legible`, sin que el texto se mueva).
- **Navegación espacial** (`core/spatial.js`): las piezas llevan `data-focus-id`; `nextFocus()` decide a
  cuál vas con ↑↓←→. Sirve para cualquier acomodo, no solo filas.
- **Vistas encima** (`OVERLAYS` en `main.js`): una vista nueva solo declara `{ handle, hints, isOpen }`.
- **Mismo idioma de botones en todas partes**: A abre · X la acción secundaria · Y Opciones · B atrás ·
  LB/RB sección · LT/RT saltan (o cambian de consola) · ☰ menú · ⧉ buscar.
- **Foco**:
  - Portadas, tiles, caras y episodios: **la órbita** (`orbit`): se levantan y un filo de luz del color de su arte los recorre una vez y se queda.
  - Teclas, opciones, filtros, Buscar y Alexa: **foco invertido** (`--inverse-bg/fg`, crece `--inverse-scale`).
  - Clase: **una sola, `.is-focused`**, en todas las piezas (T1, 10 nov 2026: antes cada una tenía su `--focused` BEM y la
    navegación espacial ponía `.is-focused`). El CSS la escribe **primero** y luego la clase de la pieza (`.is-focused.card`,
    `.is-focused.sheet__item`): el navegador indexa la regla por su primera clase, y con `.card.is-focused` un cambio arriba
    (`[data-heading]`, en cada tecla) revisaba todas las tarjetas (+55 elementos por tecla), no solo la enfocada. Lo enfocado lleva `aria-current` (`core/focus-mark.js`).
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
- **Lo que el dedo desplaza se ve entero (13 nov 2026).** Con el dedo, las filas y las cuadrículas suben sin mover el foco.
  Todo lo que se esconde, se desvanece o asoma (el asomo de Tus consolas, `.is-above` de una cuadrícula, el fundido de abajo
  del Inicio) se calcula con **el desplazamiento de ahora**, no con lo enfocado: si no, lo que el dedo trae a la vista llega
  invisible o cortado y solo queda el fondo (Fernando, 13 nov 2026: «al deslizar hacia abajo en las consolas se cortan los
  íconos»; en Juegos las portadas que el mando dejó arriba regresaban con `opacity: 0`, y en el Inicio las consolas se
  quedaban en su asomo desvanecido ya enteras a la vista). Así: (1) un `mask-image` u ocultar nunca cuelga de `[data-zone]`
  (el foco) en una zona que se arrastra; lo pone el JS con lo que de verdad queda cortado (`home--peek`,
  `home__rows--more` en `setShift`); (2) quien desplaza con `dragScroll` vuelve a marcar `.is-above` en su `onScroll`
  (`markAbove(grid, s, { whole: true })`: con el dedo solo se va lo que salió entero); (3) lo que cabe no se desplaza
  (`dragScroll` no da `extra` si nada queda fuera); (4) en Juegos, subir con el dedo hace lo de bajar con el mando: las
  barras y el juego se van, y jalar hacia abajo arriba del todo los regresa. Prueba: `tests/web/swipe.test.mjs`
  («lo que el dedo desplaza se ve entero»).
- **Con el dedo, primero se enfoca y luego se abre.** El toque que cambia del mando (o el teclado) al dedo solo enfoca, aunque
  caiga en lo que ya estaba enfocado: eso lo eligió el mando, no tú (`justTouched` en `main.js`).
- **Pistas del pie**: dicen lo que hace cada botón *aquí*; nada de pistas que no apliquen (p. ej. «Cambiar
  de fila» con una sola fila).

## 6. Texto

- **Fuentes** (TF-B, Fernando, 27 nov 2026: Segoe «se veía cruda»): todo el texto es **Inter 4.1** variable (`fonts/inter-variable.woff2`, licencia OFL en `Inter-OFL.txt`), la más cercana a San Francisco, la del iPhone. `--font-sans` y `--font-text` son la misma; el tamaño óptico lo pone el navegador (`font-optical-sizing: auto`: más cerrada en los títulos, más abierta en lo chico) y sus rasgos son `--font-features`: «l» con colita (cv05), «a» de un piso (cv11) y comillas redondas (ss03). Va dentro de Orbital: no pide internet. Los avisos encima del juego (`overlay.py`) usan la misma en `.ttf` con su peso y su tamaño óptico. **Siguen en Segoe a propósito** el reproductor (`player_ui`, lo dibuja libass: no sabe pedir los pesos de una letra variable ni sus cifras tabulares, y B7 depende de las de Segoe) y los subtítulos. Si Inter no carga, cae a Segoe UI Variable. Solo el nombre de un premio (`--font-award`) pide una con remate: Didot (que Windows no trae), luego Bodoni MT y Palatino Linotype; en esta máquina sale Bodoni MT.
- Español, frases normales. **Sin mayúsculas espaciadas** (se ven «de IA»): ni en etiquetas, ni pestañas, ni insignias, ni en el rótulo de
  sección, que desde el 2 nov 2026 va en minúsculas y negrita («Tus consolas», IN-1), ni en el listón «Nuevo»; solo el sello del mazo (ver Excepciones).
- **Nada se corta en su lugar**: un nombre que no cabe en su tarjeta se achica antes de cortarse («GeForce NOW», IN-3); una hora con
  «a. m.» o «p. m.» va con espacios que no se parten (`format.js · clock`, TV-3). En el reproductor, una línea de datos con « · » que no cabe
  suelta primero los datos del final, enteros (`player_ui.fit`), y la variante de un idioma va pegada a él («Español latino · Estéreo», RE-1). Una sinopsis que no cabe termina en la última frase
  completa (`player_ui.wrap_sentences`, PA-1), no a media frase con «…». En la pausa de una serie, el episodio va en su propio renglón,
  en blanco, bajo el logo (PA-2). Pasado el 100 de Windows, el reproductor amplifica hasta 150 (`playback.VOLUME_BOOST_MAX`).
- **Un dato dice qué es**: el tiempo jugado lleva «en total» («1 h 18 min en total», JU-2); una fecha dice qué pasa ese día
  («Episodio nuevo el miércoles 4», PS-2).
- **Un aviso de idioma no afirma lo que la pista no dice** (LA1, 16 nov 2026): «español» a secas es duda, no «no». Si quieres
  latino y la pista solo dice «español», el reproductor dice «No dice si es latino · La pista solo dice «español»», en `info` y
  sin botón; «No trae latino · Cambiar» queda para cuando la pista dice castellano u otro idioma. Prueba:
  `VersionQAModelFindingsTests.testLA1_UnspecifiedSpanishSaysTheDoubtWithoutSwitch`. La TV ya lo dice así en su lista
  («No dice si latino o castellano»); su reproductor no tiene este aviso.
- **Una etiqueta que llevan casi todos no se pone**: no distingue nada (el «24/7» de los canales de Orbital, TV-2).
- Tamaños solo con `--text-*` o, mejor, una receta `--type-*` (escalan con Ajustes → Tamaño del texto).
- Títulos con `line-clamp` o «…»: `-webkit-line-clamp` corta en el borde del último renglón, así que un `padding-bottom` no salva la cola de g, p, j, y. **Chicos** (tarjetas, riel, hojas): interlineado `--leading-title` (1,3). **Grandes** (héroe, ficha, destacado, mosaico): su interlineado de siempre y `overflow: clip; overflow-clip-margin: var(--clip-tail)`, que deja asomar la cola sin inflar el interlineado ni mover el diseño (con `clip` el elemento flex pide `min-width: 0` y `min-height: 0`).

## 7. Excepciones

Cada una se marca en el código con `ds-exception: <motivo>` usando exactamente el motivo de aquí.

| Motivo | Dónde | Por qué |
|---|---|---|
| logotipo en mayúsculas | `collection-card.js` (`AwardWordmark`, `SourceBadge`), `hero.js` y `list-screen.js` (el nombre de un premio) | Un premio (ÓSCAR, EMMY) y el sello de origen (TRAKT, STREMIO, ORBITAL) son **logotipos**, como en el iPhone: el JS los pone en mayúsculas (con `--tracking-award` / `--tracking-label`). No es una etiqueta de la interfaz. |
| iniciales de un canal sin logo | `core/tv.js` | Las iniciales dentro del círculo de un canal sin logo (como el avatar de una persona) van en mayúsculas. |
| siglas de calidad de video | TV: `core/menus.js` (las calidades de Torrentio); iPhone: `Design/AddonPieces.swift` (`TorrentioWords.quality`) y la lista de siglas de `DesignRulesTests` | «CAM» y «DVD» son como la gente reconoce esas copias en las listas de versiones, así que van tal cual junto a su nombre en palabras: «Grabada en el cine (CAM)», «Otras copias (DVD)» (Fernando, 3 nov 2026). |
| sello del mazo | `match-deck.css` (`.match__stamp`) | El sello que asoma al decidir en «Una por una» (el mazo de Decide por mí) (PASO, GUARDAR, ★ PARA HOY) va en mayúsculas, como el de `MatchCard` del iPhone y el de Tinder. |
| margen que deja lugar al foco | `card.css` (`.is-focused.card`, en las filas; las cuadrículas no lo usan) | V2 (P4, 10 nov): la enfocada crece y empuja a sus vecinas con un margen animado, que se recalcula en cada cuadro. Hacerlo con `transform` pediría mover cada tarjeta de la derecha (un selector `~` que recalcula toda la fila en cada tecla) y que `keepInView` dejara de medir con `offsetLeft`: más trabajo, no menos, y riesgo de que la fila se desacomode al volver. Medido: quitar esa transición no baja los elementos recalculados por tecla de forma clara (dentro del ruido, CPU 4x). Se queda el margen. |

| dibujo de la escena de la guía | iPhone: `Design/BrandWelcome.swift`, `BrandGuideTrakt.swift`, `BrandGuideCloud.swift`, `BrandGuideTV.swift` | Las escenas de la guía (el planeta, tu serie que viaja, la nube de tres pasos, el iPhone y la TV) son ilustraciones animadas hechas a la medida del prototipo aprobado (`docs/producto/guia-trabajos-2026-11-18/onboarding/`): un teléfono de 84 × 124, una isla de 26 × 7, el brillo de un 22 %. No son piezas de la interfaz y no se repiten fuera de su escena, así que no se vuelven tokens; los colores sí son tokens (Fernando, 18 nov 2026). |
| geometría de una pieza dibujada | TV: `backdrop.css`, `boot.css`, `launch-overlay.css` (la órbita), `rail.css` (la rayita), `status-bar.css` (la batería), `tv.css` (el logo del canal), `sources.css` (la columna del póster) | Medidas de un dibujo o de una pieza única (la órbita que gira, la pila de la batería, el hueco del póster en «Versiones»): no se repiten fuera de su pieza, así que no son espacios del sistema. Los espacios entre piezas sí son tokens (`--space-*`); desde SD1-A el guardián revisa `padding`, `margin`, `gap`, `inset` y `top/left/right/bottom` (26 nov 2026). Los ajustes ópticos en `em` (medio renglón para centrar un texto) quedan libres: son de la letra, no del espacio. |
(Antes de agregar una, intenta un token o una pieza nueva.)

## 8. El reproductor (`orbital/player_ui.py`)

Lo dibuja mpv encima del video (texto y figuras ASS), así que no usa este CSS, pero sí **la misma
paleta** (`palette.json`) y el mismo idioma de botones. Sigue los tableros «Reproductor» del lienzo de
diseño y tiene sus propias piezas reutilizables en `player_ui.py`: `rrect`, `circle`, `ring` (cuenta
atrás), `gradient` (velo sin franjas), `glyph`/`hints` (botones del mando), `buttons`, `text`/`fit`/`wrap`
y el panel de columnas (`Panel`/`Column`). Los tamaños se escriben «como en CSS» (`FS` los convierte).

**Letra, cifras, movimiento y palabras (24 nov 2026, revisión contra el sistema base: B4, B5, B7, B12, V1, V5).**

| Regla | En el reproductor | Prueba |
|---|---|---|
| B4 · pocos tamaños | Una sola escala, en `player_ui.canvas`: cuatro de interfaz, `TYPE_SM` 21 · `TYPE_MD` 26 · `TYPE_LG` 32 · `TYPE_XL` 40 (saltos de 1,2× o más), y dos grandes, `TYPE_DISPLAY` 52 · `TYPE_HERO` 64; los mismos números que la interfaz a 1080p. Antes eran catorce (19 a 64). Lo chico (pistas, datos, notas, encabezados de columna) es 21; botones, opciones, avisos, el tiempo y la sinopsis, 26; títulos de tarjeta, la hora y la cuenta atrás, 32; el episodio en pausa y el tiempo al adelantar, 40; el canal en vivo, 52; el título en pausa, 64. La cuadrícula de Versión ya no achica de uno en uno: el idioma baja un paso (26 → 21) y la calidad, si no cabe en seminegrita, va en normal. Fuera de la escala solo queda la letra dentro de un glifo del mando (es parte del ícono, se mide con su disco) | `test_player_type.py · test_the_player_uses_only_the_type_scale` (todas las capas, mando, teclado y dedo, tres pantallas, letra normal y grande) |
| B5 · dos grosores | Normal y seminegrita (`Segoe UI Semibold`); la negrita, solo en `TYPE_BOLD` (52 y 64). «Saltar intro», los títulos de las tarjetas y de «Probar otros», la cuenta atrás y la ✓ de la opción puesta pasaron de negrita a seminegrita | la misma |
| B7 · cifras del mismo ancho | libass no tiene `font-variant-numeric` y Segoe UI Semibold trae cifras proporcionales (su «1» mide 0,40 em y el «4» 0,58; Segoe UI normal y su negrita, todas iguales). Lo que cambia —el tiempo de la barra, el de adelantar, la hora, la cuenta atrás, el volumen y la sincronía de «Probar otros»— va con `figures(...)`: en normal (o negrita, si es de los grandes) | `test_numbers_that_change_use_tabular_figures` |
| B12 · reducir movimiento | `canvas.REDUCE_MOTION` (`set_reduce_motion`, desde `watch/playback.py`): Ajustes › Pantalla › «Reducir movimiento» o el de Windows (Efectos de animación, `SPI_GETCLIENTAREAANIMATION`: el mismo que la interfaz lee con `prefers-reduced-motion`). Con él, las tarjetas («Siguiente episodio», «¿Sigues viendo?», «Saltar intro», «Cambio de episodio», «¿Salir de…?») entran solo con el fundido, sin subir `CARD_RISE` | `test_cards_only_fade_in_with_reduce_motion` |
| V1 · el botón dice qué obtienes | En pausa, «A Seguir viendo» (antes «Continuar»; también en el control del iPhone, la leyenda de A en pausa); «Cambio de episodio», «B Quedarme en este» (antes «Cancelar»); «Probar otros» con el dedo, «Siguiente subtítulo ›» (antes «Siguiente ›») | `test_button_words_say_what_you_get` |
| V5 · palabras de quien ve | Un idioma fuera de la tabla ya no sale en código («HEB», «ENG»): su nombre (la tabla creció: hebreo, tailandés, griego…), el del idioma sin su región («en-US» → Inglés) o «Otro idioma»; sin idioma («und»), nada. El audio, con su nombre: «Dolby Digital Plus», «Dolby TrueHD», «Dolby Digital», «DTS», «AAC»; lo que no aporta (opus, mp3, flac, pcm) no se dice (`labels.CODECS`) | `test_languages_and_audio_speak_like_people` |

Piezas del 8 nov 2026 (pendientes del reproductor, puntos 1–3):

| Pieza | Para qué |
|---|---|
| `glass(x, y, w, h, r, kind, edge)` · `glass_fill(kind)` | La receta «Vidrio» en mpv: `GLASS_TOKENS` y `EDGE_TOKENS` son los números de `--color-glass`, `--color-glass-strong`, `--color-glass-selected`, `--glyph-bg` y sus filos (`test_player_glass_is_the_glass_of_the_interface` los compara con `themes/orbital.css`). «glass» en botones secundarios, píldoras («Elegir», «Cerrar»…), casillas de Versión y «Sigue reproduciendo»; «glass-strong» en el panel de columnas (flotante, separado de las orillas, `RADIUS_CARD` = `--radius-2xl`), tarjetas, avisos, el volumen y la franja de «Probar otros». Las capas se componen en una sola figura y la luz de arriba es un filo de 1,5 px. Sin desenfoque: ASS no tiene `backdrop-filter`, y así no cuesta nada en reposo ni encima del video |
| `glyph(…, solid=True)` | Sobre lo blanco (el principal, «Saltar intro») el disco del glifo es sólido (`--glyph-bg-solid`); en lo demás, de cristal (`--glyph-bg`) |
| `icon(name, cx, cy, size, color)` · `ICON_PATHS` | Íconos dibujados en una cuadrícula de 24 (como los SF Symbols): `bolt`, `cloud-down`, `doubt`, `restart`, `resume`, `phone-play`, `phone-send`, `phone-down`, `episode` |
| `_icon_rows` (`ICON_COLUMNS`) | Y › Reproducción: cada acción con su ícono y su nombre entero (hasta dos o tres renglones, partidos entre palabras); la pista («Mismo minuto») debajo. Las filas miden lo que su texto y se ven las que caben; el resto se desplaza con el foco («5 de 5» en el encabezado) |
| `CELL_STATES` · `cell_states` · `states_legend` | Y › Versión: lo de cada casilla en íconos (⚡ «Al instante» en `--color-live`, la nube «Hay que bajarla», «?» «Idioma dudoso» en `--color-warning`); la leyenda con sus nombres va en el encabezado de la columna o, si no cabe entera, abajo; la enfocada se dice en palabras abajo. La calidad («4K HDR») y el idioma se achican antes de cortarse |

**Decisión (8 nov 2026, punto 3).** En Versión, íconos con leyenda y no dos renglones: la casilla mide ~130 px en la TV y ~100 en la
Legion con la letra grande; «Hay que bajarla · Idioma dudoso» no cabía ni en dos. Como el iPhone (D10: íconos, no cápsulas de texto);
mpv no tiene lector de pantalla, así que el «nombre accesible» de cada ícono es la leyenda a la vista y la nota de la casilla enfocada.

| Estado | Qué se ve | Botones |
|---|---|---|
| Al tocar un botón | Solo la barra partida por capítulos con su punto, tiempo y «termina a las…»; abajo a la izquierda el idioma, los subtítulos y la versión (el mismo renglón que en pausa). Sin título ni «Película»: eso es de la pausa | A Pausa · X Audio y subtítulos · Y Versión (en una serie, «Episodios y versión») · B (mantener) Salir; en pausa también ◀▶ Adelantar · ↑↓ Volumen · **RT Siguiente episodio** (solo si hay siguiente; con teclado, `]`). RT con un toque pasa al siguiente y LT al anterior: sale la tarjeta «Cambio de episodio · Siguiente · E3» con la cuenta atrás de 3 s en su anillo y «B Quedarme en este» (con el dedo, «Quedarme en este»; con teclado, Esc; TB-46, 24 nov 2026: antes «Cancelar»); mantenerlo cuenta una vez |
| En pausa | Video oscurecido; el **logo del título** (el mismo recortado de la ficha, en blanco si es oscuro; mpv lo pone encima con `overlay-add` en el lugar que deja `paused_ass`, `placed["logo"]`, y se prepara por detrás al pausar) o, sin logo, su nombre grande; datos, sinopsis y botones | Los mismos |
| Adelantando (◀ ▶, LB/RB) | Solo la barra y, sobre el punto, la hora, cuánto salta y el capítulo | Mantén: más rápido |
| X | Panel abajo: Audio · Subtítulos · Tamaño · Sincronía (el video sigue). Elegir audio o subtítulos **no lo cierra**; mientras está abierto, los subtítulos suben (`sub-pos`) para verse encima. En Audio, tras las pistas de esta versión, tu idioma (y los que no trae) en otra: «Latino» con «En otra · 4K» a la derecha (corto: la columna es angosta); elegirla cambia de fuente y sigue donde ibas | ◀ ▶ columna · A elegir · B cerrar |
| Probar otros (X › Subtítulos) | Franja arriba (`sub_trial_ass`, 96 px): «Español · Subtítulo 2 de 5», del video o de tu complemento, la sincronía y, a la derecha, qué pasa (bajando, sin internet, no hay más) | ◀▶ Otro subtítulo · ↑↓ Adelantar o atrasar · A Este va bien · B Listo (se queda el último que probaste, como el iPhone) |
| Y | Panel «Más»: **Episodios** (series; el encabezado dice la temporada, «Episodios · T5», y abre en la que ves; el que ves dice «Viendo» y el que sigue «Siguiente» en ámbar, `--color-warning`; LB/RB cambian de temporada, con el dedo «‹ Temporada» y «Temporada ›») · **Versión** · Reproducción. Versión es la cuadrícula de «Versión» de la ficha (`watch.version_grid`, `_grid_rows`): un renglón por idioma y sus calidades en casillas de vidrio («1080p» y debajo sus íconos: ⚡ al instante en `--color-live`, la nube si hay que bajarla, «?» si el idioma es dudoso, con su leyenda); abre en la que ves (con contorno) y abajo dice la enfocada en palabras. Reproducción: cada acción con su ícono y su nombre entero | ↑↓ idioma · ◀ ▶ calidad (del borde, a la columna de al lado) · A cambiar (sigue donde ibas) · B cerrar |
| Tarjetas | «Saltar intro» (botón claro), «Siguiente episodio» (el **cuadro del episodio** a la izquierda, «Siguiente episodio · T1 E2» y su nombre en grande, y el anillo de cuenta atrás a la derecha; el cuadro es una imagen encima, `overlay-add`, en el lugar que deja `upnext_ass`, `placed["still"]`, bajada al pedir el siguiente; sin cuadro, la tarjeta de siempre), «¿Sigues viendo?». Al elegir el siguiente (A, la cuenta atrás o LT/RT), **la misma tarjeta pasa a «Cargando T1 E2…»**: el arco que le quedaba se vuelve uno que gira, y se va cuando el episodio da imagen; no sale otro aviso | A / B (cargando: mantén B, salir) |

El reproductor no usa ☰ (Start es de Orbital: con Home, salir del juego).

**Movimiento en el reproductor** (2 nov 2026). La pausa entra con un fundido en tres pasos (`player_ui.fade`,
`PlayerScreen.PAUSE_FADE`: cada transparencia se acerca a «nada» en lo que falta) y el logo, que es una imagen encima, entra al final.
Las tarjetas (`PlayerScreen.CARD_FRAME`, 30 cuadros por segundo, en su hilo) entran subiendo 32 px y apareciendo en 0.32 s (`ease_out`; con «Reducir movimiento», solo apareciendo), la cuenta atrás corre seguida (antes saltaba una vez por segundo) y al irse se desvanecen en 0.2 s; el cuadro del episodio entra y sale con ellas en cuatro pasos de transparencia (una copia de la imagen por paso).
Reproduciendo, mientras se ve, la barra se vuelve a pintar cada medio segundo (`HUD_TICK`): antes se quedaba quieta los 4 s. Sin
miniaturas al adelantar: pedirían abrir el video dos veces (otro mpv decodificando), y Orbital se queda ligera; al adelantar ya se ven
la hora, cuánto salta y el capítulo.

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
| `✓`, `★`, `⚠`, `◀ ▶` salen como texto (fuente Segoe UI Symbol) | Hay ícono dibujado (`ICONS.check`, `ICONS.star`) pero esos textos también viajan al iPhone. |
| Medidas sueltas en rem (.55, .6, .15…) que no coinciden con un `--space-*`, **fuera de los rellenos, márgenes y huecos** (posiciones, anchos, desplazamientos en `em`) | Son ajustes ópticos de cada pieza; un token por cada una no aclararía nada. Los rellenos, márgenes y huecos ya van todos en la escala (B1, 24 nov 2026). |
| El mosaico de Para ti llega a 9 px del borde de la pantalla | Es a propósito (los pósters pasan por los lados); con sobrebarrido de la TV, ajustar «Márgenes de la TV» no lo mueve. |
