# «No sé qué ver» · propuesta para Canvas (TV, 16 nov 2026)

Encargo de la sesión de la TV: pasar esta propuesta a un **Canvas** para Fernando. Nada de esto está aplicado.

## Formato que pide Fernando

- «Original» y «Propuesta» lado a lado, con capturas reales; cada cambio en un recuadro rojo con su etiqueta (NQ-1…).
- Debajo, la lista numerada de cambios; lo que no se puede dibujar va en un bloque «Sin marca en pantalla».
- Debe leerse bien en el teléfono (cuadrículas que se apilan, títulos fluidos).
- Fernando contesta por ID («NQ-1 sí»); nada se construye hasta que conteste.
- `propuesta-no-se-que-ver.html` es la misma lámina ya armada en HTML (con las imágenes dentro): sirve de guía.

## Imágenes

Las `.jpg` miden 1280×720. `rects.json` trae los recuadros en coordenadas de 1920×1080 (`[x, y, ancho, alto]`):
multiplica por 2/3 para las `.jpg`, o úsalos en porcentaje (x/19.2 %, y/10.8 %).

| Imagen | Qué es | Recuadros |
| --- | --- | --- |
| `1-explorar.jpg` | Hoy: Explorar, la única puerta (X en el pie) | «única puerta» en [298, 1004, 214, 40] |
| `4-inicio.jpg` | Hoy: Inicio, sin puerta | — |
| `5-peliculas.jpg` | Hoy: Películas y series, sin puerta | — |
| `2-tres-que-caben.jpg` | Hoy: adentro, las preguntas ocupan media pantalla | «media pantalla» [470, 668, 1000, 262] · «A = ficha» [77, 1004, 212, 40] |
| `m-inicio.jpg` | Propuesta NQ-1 | `inicio` |
| `m-peliculas.jpg` | Propuesta NQ-2 | `pill` |
| `m-explorar.jpg` | Propuesta NQ-3 | `explorar` |
| `m-dudas.jpg` | Propuesta NQ-4 y NQ-5 | `nudge` |
| `m-adentro.jpg` | Propuesta NQ-9 a NQ-12 | `modes` NQ-9 · `lead` NQ-10 · `go` NQ-11 · `afinar` NQ-12 |

## Diagnóstico

- **Una sola puerta, escondida.** En la TV solo se llega con X dentro de Explorar, y esa X es una pista del pie, no algo
  que se vea. El menú ☰ ya no lo tiene: el comando «decide» quedó sin quien lo llame.
- **No está donde nace la duda:** al prender (Inicio), al recorrer filas sin decidir (Películas y series), al terminar
  algo o con Buscar vacío.
- **El iPhone tiene dos puertas** (Inicio y Explorar) y la TV una.
- **Adentro, las pestañas no dicen qué hacen**, las preguntas ocupan media pantalla y A abre la ficha en lugar de
  poner la película.
- **No hay atajo ni voz** para «no sé qué ver».

## Cambios

### Las puertas

- **NQ-1 · Inicio.** Tarjeta «¿No sabes qué ver? · Decide por mí» en *A continuación*, segunda, con el abanico de tres
  pósters de hoy y una línea que sigue la hora («Tres para esta noche»). Es la puerta que ya tiene el Inicio del iPhone.
- **NQ-2 · Películas y series.** «✦ Decide por mí» en la fila de arriba, el primer botón después de «Todo · Películas ·
  Series».
- **NQ-3 · Explorar.** El botón visible también con el mando (hoy solo con el dedo): «¿No sabes qué ver? Decide por mí · X».
- **NQ-4 · Cuando dudas.** Tras ~45 s (o 20 movimientos) en Películas y series sin abrir nada, una píldora abajo a la
  derecha: «¿Te ayudo a decidir? R3 Decide por mí». Una vez por sesión, se va a los 8 s, nunca con un video abierto.
- **NQ-5 · Atajo global.** R3 (clic del stick derecho, hoy libre) o la tecla D abren «Decide por mí» desde cualquier
  sección. NQ-4 y la primera semana de pistas lo enseñan.
- **NQ-6 · Voz.** «Alexa, dile a Orbital que no sé qué ver» (o «que decida por mí») abre la pantalla en la tele.
- **NQ-7 · Al terminar.** Al acabar una película, o el último capítulo que salió de una serie: «¿Y ahora? Decide por mí»
  junto a lo que sigue.
- **NQ-8 · Buscar vacío.** Antes de escribir, la primera fila: «¿No sabes qué buscar? Decide por mí».

### Adentro

- **NQ-9 · Pestañas que se explican.** «Tres que caben · elige entre tres» y «Una por una · sí o no, rápido».
- **NQ-10 · Por qué caben.** La frase de arriba con la hora real: «Cabe en tu noche: termina antes de las 9».
- **NQ-11 · Lista para ver.** La enfocada lleva «Ver ya» (A) y «Ficha» (Y), como «Una por una». Cambia los botones: hoy
  A abre la ficha y Y es «Hoy no»; «Hoy no» y «No me interesa» pasarían a ☰; X sigue barajando.
- **NQ-12 · Afinar en un renglón.** Tipo, Duración y Ánimo resumidos en un renglón de píldoras con lo elegido; ↓ los
  abre ahí mismo.

### Para saber si funcionó

- **NQ-13 · Medir las puertas.** Anotar por cuál puerta entraste y si terminaste viendo algo; a las dos semanas se
  quitan las que no sirvan.

## Sin marca en pantalla

NQ-5 a NQ-8 y NQ-13 no tienen captura. Recomendación para empezar: **NQ-1, NQ-2, NQ-5, NQ-9 y NQ-12**; NQ-4 después de
medir (NQ-13). **iPhone:** NQ-1 ya existe allá; NQ-9 a NQ-12 tocan la misma pantalla en las dos apps, así que antes de
construir pasan por revisión adversarial y alineación con la sesión del iPhone.
