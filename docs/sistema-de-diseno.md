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
| Primitivos | `tokens.css` | Espacio (`--space-*`), radios (`--radius-*`), letra (`--text-*`, `--weight-*`, `--tracking-*`), vidrio (`--blur-glass`), movimiento (`--duration-*`, `--ease-*`, `--delay-*`, `--stagger`), capas (`--z-*`), medidas de consola (`--card-*`, `--tile-*`, `--key-height`, `--sheet-width`…). |
| Semánticos | `themes/orbital.css` | Lo que usan los componentes: `--color-*`, `--shadow-*` (cajas) y `--shadow-drop*` (siluetas), `--ring-focus`, foco invertido (`--inverse-bg/fg/scale`), sobre el arte (`--color-badge-bg`, `--gradient-tile-shade`), dentro de algo claro (`--on-light-*`) o de color (`--on-color-fill`), máscaras (`--mask-solid`), fondo de ambiente (`--color-backdrop-deep`), sombra sobre el arte (`--color-art-shade`), relieves (`--gradient-sheet`, `--gradient-console-tile`, `--gradient-launch-planet`), `--color-star`, `--color-video-bg`, `--assistant-accent`, el grafito neutro del arte (`--art-*-neutral`) y el color de cada consola (`--system-*`). |

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
| `--duration-glow` · `--duration-stars` · `--duration-stars-far` | Ambiente: la luz respira, las estrellas derivan. |
| `--duration-launch-*` | Pantalla de carga (cinemática, más lenta a propósito). |
| `--delay-1/2/3` · `--stagger` | Escalonado: cada pieza entra un poco después. |
| `--ease-out` · `--ease-in` · `--ease-spring` · `--ease-pop` · `--ease-launch` · `--ease-sweep` | Entradas · salidas · resorte corto · foco que salta · disparo · barrido. |

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
| `Badge(text, { large })` | `ui` | Etiqueta que llama la atención: «3 nuevos», «Recomendada» (sin mayúsculas). `large` sobre arte a sangre (el mosaico de Para ti). |
| `Progress(fraction)` | `ui` | Cuánto llevas de un video. |
| `SectionHead(title, { meta, end })` | `ui` | Título de una zona con su dato y algo a la derecha. |
| `ScreenHead({ eyebrow, title, lead })` + `.screen` | `ui` | Pantalla completa encima de todo (Conectar Stremio, Conectar Trakt): `.screen` es el marco (fondo, margen, entrada y salida con `screen--leaving`) y `ScreenHead` su encabezado («Cuentas» · título · una línea). |
| `KeyHint(glyph, label, { small })` | `ui` | Botón del mando + qué hace («A Continuar»). **El pie de controles se arma con esta pieza.** |
| `.tile` | `ui` | Superficie enfocable de las pantallas nuevas: mismo radio, anillo de foco y atenuado. |
| `Button({ label, glyph, variant, yields })` | `button` | Acción con su glifo. En una fila van dentro de `.button-row`: **nunca se parte ni se corta**; si no cabe, solo el botón `yields` (la alternativa, «Con Ryujinx») se encoge con «…». Casi siempre es leyenda (no se enfoca); cuando es lo único que hay que hacer (Conectar Trakt), lleva `data-focus-id` y el anillo de foco. |
| `Glyph(text, { small })` | `glyph` | El botón del mando en su color (A verde, B rojo, X azul, Y amarillo); cambia con el modo de entrada (`data-input`: mando o teclado). |
| `createKeyboard()` | `keyboard` | Teclado en pantalla (Buscar, Conectar Stremio). |

## 3. Tarjetas y tiles (`card`, `tiles`)

| Pieza | Para qué |
|---|---|
| `Card(item, { caption, showAgo, pop })` (`card`) | Portada de un juego o video en filas y cuadrículas. Sin arte: el respaldo con su nombre; apps: su ícono (`appIcon`). Esquina: estrella si es favorito (`item.favorite`), palomita si ya lo tienes en una lista de afuera (`item.owned`). |
| `FeatureTile` (`tiles`) | El destacado del Inicio: arte a sangre, logo o título, dato y botones (`.button-row`). Si solo hay caja (GBA cuadrada, Switch alta), **estuche**: la portada desenfocada de fondo y la caja encima, a la derecha. |
| `RowTile` (`tiles`) | Renglón: miniatura ancha (cápsula de Steam, fondo, o la caja recortada) y al lado el nombre grande y su dato siempre a la vista, con avance si es video. El texto nunca va encima del arte. |
| `ConsoleTile` (`tiles`) | Foto real de la consola (o logo) con brillo de su color, juegos, nuevos y lo último. |

**Ningún texto de tarjeta o botón se sale**: una línea con «…» (o `line-clamp` con espacio para las
letras que bajan: g, p, j, y).

## 4. Pantallas y vistas (cada una con su JS y su CSS del mismo nombre)

| Componente | Qué es |
|---|---|
| `status-bar` | Barra de arriba: marca, Buscar, pestañas (LB/RB), Alexa (navegable: muestra ejemplos de órdenes), batería y hora. |
| `hints` | Pie de controles del momento (piezas `KeyHint`). |
| `foryou` | Para ti (a la izquierda del Inicio): recomendaciones en dos modos, Mosaico y Listas; X cambia de uno a otro con el selector del centro del pie. A ve o juega, Y abre Más (ficha, «No me interesa»). |
| `foryou-mosaic` | Mosaico de Para ti: columnas de imágenes; la enfocada crece y enseña etiqueta, logo y un dato; bajar sube todo (cascada) y quieto ~30 s entra en ambiente. Ícono de esquina: la consola del juego, o serie / película. |
| `foryou-lists` | Listas de Para ti, con las mismas piezas que Juegos (`rail`, `browse`, `detail-panel`): tus listas en el riel (Trakt, plataformas con su logo de TMDB, juegos de RAWG), Series · Películas en las grandes, portadas y la ficha de lo enfocado. Una lista que explica algo (Conectar Trakt) lleva su botón, enfocable. |
| `trakt-link` | Conectar Trakt: un código grande para escribir en trakt.tv/activate desde el celular. |
| `home` | Inicio: saludo, el destacado (enseña lo enfocado) y «También tenías» en renglones a la derecha; Tus consolas asoman abajo y al bajar a ellas el Inicio se desliza. |
| `games` | Juegos: tus consolas en el riel (cruceta o LT/RT), encabezado de consola, filtros y cuadrícula; la ficha del juego enfocado. Armado con `rail`, `browse` y `detail-panel`. |
| `rail` | Riel lateral de una vista con secciones (consolas, listas): casillas con foto, logo de marca o ícono; RePág/AvPág arriba y abajo; grupos con su nombre. **Al enfocarlo se abre como pestaña** y enseña el nombre y un dato de cada sección; lo de atrás se aparta. |
| `browse` | El centro de una vista con secciones: encabezado (`BrowseHead`: la sección en su casilla, nombre grande y lo esencial), filtros en píldora (`fillFilters`, se compactan si no caben en una fila) y la cuadrícula de portadas (`keepInView`). Juegos y las Listas de Para ti son la misma vista con otros datos. |
| `detail-panel` | Ficha lateral de lo enfocado (un juego, una película, una serie): arte que se funde con la ficha (máscara, sin bordes), logo o nombre, de dónde es, hasta cuatro datos, la descripción y sus acciones (o una nota: «No lo tienes»). |
| `hero` + `shelf` | Películas y series / Apps: el destacado arriba y las filas de portadas. El destacado cede la descripción antes que cortar los botones. |
| `title` | Ficha de una película o serie: datos, botones, temporadas (LB/RB) y episodios. |
| `sources` | Elegir fuente de un video. |
| `search` | Buscar con el teclado en pantalla y resultados vivos. |
| `login` | Conectar Stremio con el teclado en pantalla. |
| `sheet` | Hojas laterales (menús, ajustes, atajos). Encabezados de sección (`heading: true`) que no se enfocan; se desplaza con el foco. |
| `toast` | Aviso corto arriba a la derecha (nunca encima de una hoja). |
| `launch-overlay` | Pantalla de carga al abrir algo. |
| `viewer` | Visor de capturas. |
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
- **Pistas del pie**: dicen lo que hace cada botón *aquí*; nada de pistas que no apliquen (p. ej. «Cambiar
  de fila» con una sola fila).

## 6. Texto

- Español, frases normales. **Sin mayúsculas espaciadas** (se ven «de IA»): ni en etiquetas, ni pestañas,
  ni insignias.
- Tamaños solo con `--text-*` (escalan con Ajustes → Tamaño del texto).
- Títulos con `line-clamp`: `padding-bottom` de ~.2em para que no se corten las letras que bajan.

## 7. Excepciones

Cada una se marca en el código con `ds-exception: <motivo>` usando exactamente el motivo de aquí.

| Motivo | Dónde | Por qué |
|---|---|---|
| — | — | Ninguna hoy. |

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

**Con el dedo (o el ratón)** no hay glifos del mando: `TOUCH` cambia `hints` por `pills` (botones que se
tocan) y cada pieza tocable anota su lugar en `targets` (`hit()` dice qué tocaste). Reproduciendo: «−10 s ·
Pausa · +10 s · Audio y subtítulos · Episodios · Salir» abajo, al centro; tocar la barra salta ahí; tocar el
video enseña o esconde los botones. En los paneles se toca la opción (o la columna) y «Cerrar»; en las
tarjetas, sus botones («Seguir viendo», «Salir»). mpv avisa dónde tocaste (`script-message orbital-tap`) y
cualquier botón del mando vuelve a los glifos. Si el video se abrió con el dedo, empieza ya así.

## 9. Arte

Todo tiene imagen. Orden: arte propio de Orbital (scraper) → el de ES-DE si sirve → respaldo de
`img/placeholders/` (varias opciones por consola, generadas con Grok Imagine; a cada juego le toca
siempre la misma). Fotos de consolas en `img/consoles/` (Evan-Amos, dominio público).
