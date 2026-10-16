# Una sola experiencia: TV ↔ iPhone (propuesta)

Base: **Proyección**, el sistema del iPhone (`docs/ios-proyeccion.md`), y el sistema de diseño de la TV
(`docs/sistema-de-diseno.md`).

La regla que ya acordamos: **la TV es la fuente de verdad** del color, los nombres y el comportamiento. El iPhone es
nativo en la forma (iOS 26, Liquid Glass, hojas, Dynamic Type).

Esta propuesta compara valor por valor, no solo principios. Todo lo de aquí se midió en el código de `main` @ 38f9682.

## 1. Lo que ya es igual (y lo vigila una prueba)

| Qué | TV | iPhone | ¿Prueba? |
|---|---|---|---|
| Paleta | `palette.json` | `DesignTokens.palette` | Sí (`testPaletteMatchesOrbitalsPaletteJSON`) |
| Color del arte | `core/color.js` (tint L .20, accent L .76, neutro 205/205/211) | `ArtPalette` (misma cuenta) | Sí (los mismos casos de `color.test.mjs`) |
| Botón principal | Color del arte, texto oscuro | `.dsArtButton` | — |
| Avance y foco | Papel | Papel (tinta en claro) | — |
| Teal | Solo `--color-live` | Solo `live` | — |
| Espacios | 4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 56 (en rem) | Los mismos | No |
| Radios | .3–1.4 rem ≈ 5 · 7 · 10 · 13 · 18 · 22 | 5 · 7 · 10 · 13 · 18 · 22 | No |
| Rellenos | hairline .09, fill .10 | hairline .09, fill .10 | No |
| Textos | «T2 E5», «termina a las», «Ver la serie», motivos de `foryou.py` | Los mismos | — |
| Top 10 | rank / movement / new; ▲ ▼ Nuevo en papel y gris | Los mismos | Sí (API) |

## 2. Diferencias que hacen sentir dos apps

Para cada una, mi propuesta y quién la haría (TV = esta sesión, iPhone = la sesión de la Mac).

| # | Tema | TV | iPhone | Propuesta | Quién |
|---|---|---|---|---|---|
| 1 | **«Mi lista»** | Motivo «En Mi lista» (M mayúscula) | Botón «En mi lista» (m minúscula) y motivo «En Mi lista» | «Mi lista» es el nombre propio de tu biblioteca de Stremio: **siempre con M**. «En Mi lista» en los dos lados. | iPhone |
| 2 | Superficie (tarjetas, renglones) | ink-900 | ink-850 | La TV manda: **ink-900**. Si la prueba de contraste del iPhone lo exige, se queda en 850 y se documenta como excepción. | iPhone |
| 3 | Texto tenue (terciario) | Blanco al 50 % (≥ 4.5:1, se lee) | ink-500 (no pasa 4.5:1, «solo adornos») | **Blanco al 50 %** en oscuro: en la TV el tenue se usa para leer (placeholders, «Nada este día»). | iPhone |
| 4 | Duraciones | 140 · 220 · 320 · 520 · 700 ms | 120 · 200 · 350 · 450 · 600 ms | **Los mismos números** para fast / base / slow / enter / tint, los de la TV. En la mano no se nota y así un fundido del color del arte dura lo mismo en los dos. | iPhone |
| 5 | Nombres de los tamaños de letra | xs … 3xl (escala) | Recetas: display, title, section, cardTitle, body, secondary, footnote, caption, eyebrow, data | Hablar el mismo idioma: la TV agrega **las mismas recetas** como alias (`--type-section`, `--type-card-title`…) sobre su escala, sin cambio visual. Así «section» es lo mismo en una maqueta de cualquiera de las dos. | TV |
| 6 | Datos en monoespaciada | No (tabular-nums) | La tabla de piezas dice «`DataLine`: SF Mono»; la sección de texto dice tabulares | Corregir el documento del iPhone: **tabulares, sin SF Mono** (ya es lo que hace el código). | iPhone (doc) |
| 7 | Rótulo sobre el título | La plataforma va en una píldora sobre el arte | `Eyebrow` («Seguir viendo») | La TV adopta el rótulo en el destacado del Inicio y en la ficha («Seguir viendo», «Jugaste hace 2 h»), con la misma receta `eyebrow`. La píldora de la tienda se queda. | TV |
| 8 | Top 10 | Cifra chica en la esquina del póster + ▲ ▼ | Cifra enorme detrás del póster (`rankNumber` 132 pt) y `RankedRow` | **Opcional, decides tú**: la TV adopta la cifra grande en las listas «Top 10 en …» (es lo que la gente reconoce de Netflix). Si no, se queda como está y se documenta como diferencia a propósito. | TV |
| 9 | Vidrio | Píldoras de vidrio sobre el arte (tienda, «Atrás» táctil) | Vidrio solo en navegación (HIG) | Se queda distinto a propósito: en la TV no hay barra de navegación de vidrio y la píldora sobre el arte se lee mejor así. Se documenta en las dos guías. | Las dos (doc) |

### A propósito distinto (ya decidido)

- **Mosaico.** iPhone con 3 carriles parejos e información abajo; TV con 6 columnas, donde la enfocada crece.
- **Modo claro.** Solo en el iPhone: la TV es una sala oscura.
- **Estantes de Listas.** Siguen siendo propios del iPhone (excepto el Top 10, punto 8).

## 3. Que no se vuelvan a separar

Hoy solo la paleta tiene una prueba que compara los dos lados. El resto depende de que alguien se acuerde. Propongo:

1. **`design/tokens.json`, un solo archivo** con todo lo compartido:
   - la paleta (sale de `palette.json`, que se queda como alias);
   - los papeles en oscuro;
   - espacios, radios, duraciones y opacidades;
   - las recetas de texto, con su tamaño relativo.
2. **Pruebas de paridad en los dos lados:**
   - `tests/web/design-system.test.mjs` compara `tokens.css` y `themes/orbital.css` contra `tokens.json`;
   - `DesignTests` del iPhone compara `DesignTokens` contra el mismo archivo (como ya hace con la paleta).

   Si alguien cambia un valor en un solo lado, falla CI.
3. **`design/vocabulario.json`**, con los textos que deben decir lo mismo en las dos apps:
   - verbos: Ver, Continuar, Ver la serie, Elegir fuente, Ver en la TV;
   - nombres: Mi lista, Tu watchlist, Seguir viendo, Para ti;
   - formatos: «T2 E5», «termina a las …», «quedan N min»;
   - los motivos.

   La TV lo usa en sus pruebas (que esas frases salgan tal cual) y `scripts/ios_strings.py` falla si el iPhone usa otra.

## 4. Orden sugerido

1. **Arreglos rápidos (iPhone):** 1, 2, 3, 4 y 6. Una tarde, sin decisiones abiertas salvo el contraste del punto 2.
2. **Mecanismo (los dos):** `tokens.json` + `vocabulario.json` + pruebas de paridad. Lo armo yo del lado de la TV y del
   archivo compartido; la sesión del iPhone conecta `DesignTests`.
3. **TV:** recetas de texto como alias (5) y el rótulo en el destacado y la ficha (7).
4. **Si dices que sí:** la cifra grande del Top 10 en la TV (8).

## 5. Decisiones (16 oct 2026)

Tú decidiste el Top 10; el resto lo decidí yo con este criterio: **igual donde la persona lo nota de una app a la otra
(nombres, color del arte, tiempos, jerarquía), distinto solo donde el aparato lo pide** (distancia, luz, gestos).

| # | Decisión | Por qué |
|---|---|---|
| 1 | «Mi lista» / «En Mi lista» siempre con M, en las dos (la TV también decía «En mi lista» en la ficha) | Es un nombre propio: escribirlo de dos formas hace pensar que son dos cosas. |
| 2 | **Superficie distinta a propósito**: ink-900 en la TV, ink-850 en el iPhone | El teléfono se usa con luz y sus renglones agrupados no llevan borde: necesitan un escalón más contra el fondo (como `secondarySystemBackground`). En la sala oscura de la TV, ink-900 ya separa y las tarjetas son puro arte. De lejos, en las dos se ve «grafito»: nadie compara 5 niveles de gris entre dos pantallas. |
| 3 | Texto tenue que **se lee** en las dos (≥ 4,5:1): blanco al 50 % (#868687 en el iPhone); el gris ink-500 queda como `decorative`, solo para adornos (la cifra del Top 10) | El iPhone usaba un gris que no pasaba contraste para textos que sí se leen. Accesibilidad no es negociable de un lado. |
| 4 | Duraciones de la TV en las dos (140 · 220 · 320 · 520 · 700 ms) | Diferencias de 20–100 ms no se ven en la mano, pero el fundido del color del arte se reconoce como «el gesto de Orbital»: que dure lo mismo cuesta nada. Las transiciones nativas de iOS (hojas, navegación) siguen siendo del sistema. |
| 5 | La TV usa los nombres de receta del iPhone (`--type-section`, `--type-eyebrow`…), sin cambio visual | Un mismo idioma para hablar de diseño; los tamaños siguen siendo los de 3 m. |
| 6 | `DataLine`: números tabulares, sin SF Mono (se corrigió la guía) | Ya era lo que hacía el código. |
| 7 | Rótulo sobre el título del destacado de Inicio en la TV («Seguir viendo», «Sigue», «Seguir jugando»); en la ficha no, porque el iPhone tampoco lo usa ahí | Dice por qué está ahí, como en el iPhone. Se esconde antes que el dato cuando falta alto. |
| 8 | **Top 10 con cifra grande en la TV** (tu decisión): la cifra gris detrás del póster, el ▲ ▼ en la esquina | Es lo que la gente reconoce de Netflix y ya era así en el iPhone. |
| 9 | Vidrio distinto a propósito (documentado en las dos guías) | La TV no tiene barra de navegación de vidrio; en el iPhone es la regla de Apple. |

**El mecanismo ya está:** `design/tokens.json` y `design/vocabulario.json`, con `tests/web/design-parity.test.mjs` (CI, lee
también el código Swift) y `DesignTests.testTokensMatchSharedJSON` en el iPhone.
