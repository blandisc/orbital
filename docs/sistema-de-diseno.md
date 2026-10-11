# Sistema de diseño de Orbital

Regla de oro: **una pantalla nueva se arma con estas piezas**. Si falta algo, se agrega aquí (al
sistema), no dentro de la pantalla. Así un chip, una tecla o un foco se ven igual en todas partes.

## 1. Tokens (`orbital/web/styles/`)

| Capa | Archivo | Qué hay |
|---|---|---|
| Paleta | `palette.json` + `tokens.css` (`--palette-*`) | Los colores crudos. **Una sola paleta** para la interfaz y la barra del reproductor (`player_ui.py` la lee del JSON). Una prueba verifica que coinciden. |
| Primitivos | `tokens.css` | Espacio (`--space-*`), radios (`--radius-*`, `--tile-radius`), tipografía (`--text-*`, `--weight-*`), movimiento (`--duration-*`, `--ease-*`), capas (`--z-*`), medidas de consola (`--card-*`, `--tile-*`, `--key-height`). |
| Semánticos | `themes/orbital.css` | Lo que usan los componentes: `--color-*`, `--shadow-*`, `--ring-focus`, foco invertido (`--inverse-bg/fg`), sobre el arte (`--color-badge-bg`, `--gradient-tile-shade`), dentro de algo claro (`--on-light-*`) y el color de cada consola (`--system-switch`, `--system-gc`…). |

Los componentes **solo usan tokens semánticos** (nunca `#hex` ni `rgba(...)` sueltos, salvo el negro de
las máscaras).

## 2. Piezas base (`js/components/ui.js` + `styles/components/ui.css`)

| Pieza | Para qué |
|---|---|
| `Chip(text, { tone })` | Un dato corto: «4K», «Inglés», «Al instante» (`good`/`warn`). |
| `Badge(text)` | Etiqueta que llama la atención: «+2 nuevos», «Recomendada». |
| `Progress(fraction)` | Cuánto llevas de un video. |
| `SectionHead(title, { meta, end })` | Título de una zona con su dato y algo a la derecha. |
| `KeyHint(glyph, label)` | Botón del mando + qué hace («A Continuar»). |
| `.tile` | Superficie enfocable de las pantallas nuevas: mismo radio, anillo de foco y atenuado. |
| `Button`, `Glyph` | Acciones con su glifo; el glifo del botón del mando en su color. |
| `createKeyboard()` | Teclado en pantalla (Buscar, Conectar Stremio). |

## 3. Tiles (`js/components/tiles.js` + `styles/components/tiles.css`)

`FeatureTile` (lo último, a lo grande, con A/X/Y), `WideTile` (arte horizontal a sangre),
y `ConsoleTile` (foto real de la consola, juegos, nuevos, lo último).

## 4. Comportamiento con el mando

- **Navegación espacial** (`core/spatial.js`): las piezas llevan `data-focus-id`; `nextFocus()` decide a
  cuál vas con ↑↓←→. Sirve para cualquier acomodo, no solo filas.
- **Vistas encima** (`OVERLAYS` en `main.js`): una vista nueva solo declara `{ handle, hints, isOpen }`.
- **Mismo idioma de botones en todas partes**: A abre · X la acción secundaria (otro emulador, o la
  ficha en videos) · Y Opciones · B atrás · LB/RB sección · LT/RT saltan (de 5 en 5, o entre zonas) ·
  ☰ menú · ⧉ buscar.
- **Foco**: anillo blanco (`--ring-focus`) en portadas y tiles; foco invertido (fondo claro) en teclas,
  chips y opciones. Lo enfocado lleva `aria-current`.

## 5. Arte

Todo tiene imagen. Orden: arte propio de Orbital (scraper) → el de ES-DE si sirve → respaldo de
`img/placeholders/` (varias opciones por consola, generadas con Grok Imagine; a cada juego le toca
siempre la misma). Fotos de consolas en `img/consoles/` (Evan-Amos, dominio público).
