# Barra de calidad visual y de experiencia (iPhone y TV)

El objetivo del producto es que Orbital se sienta **al nivel de las mejores apps del mercado** (la app
TV de Apple, Netflix, Infuse, el Plex nuevo). Este documento dice qué significa eso en concreto, para que
cualquier tarea (humana o de un agente) se mida contra lo mismo. Complementa a `docs/sistema-de-diseno.md`
(que dice *cómo* se construye) con *qué tan bien* tiene que quedar.

## 1. Principios

1. **El contenido manda.** Lo primero que se ve es arte (póster, fondo, episodio), no la marca ni el estado
   de la app. Títulos, chips y botones viven *sobre* o *junto* al arte sin taparlo.
2. **Una jerarquía por pantalla.** Un destacado, una acción principal (botón blanco), lo demás
   secundario. Nunca dos cosas compiten por la atención.
3. **Nada se corta, nada se encima.** Ni letras descendentes, ni pósters recortados por la mitad, ni la
   barra de pestañas tapando la última fila (siempre hay aire al final del scroll).
4. **Movimiento con sentido.** Cada transición explica de dónde viene algo (una ficha crece desde su
   póster; una hoja sube; un indicador se desvanece). Respeta Reducir movimiento. Nada «salta».
5. **Latencia percibida cero.** Esqueletos o el arte en caché mientras llega el resto; nunca una pantalla
   vacía y luego todo de golpe. Lo que ya se vio no vuelve a parpadear.
6. **Texto de persona.** Español natural, sin códigos ni inglés colado (sinopsis incluida). Números con
   unidad («quedan 20 min»), fechas en palabras («hoy», «mañana», «el viernes»).
7. **Con una mano.** En el iPhone lo frecuente está abajo o al alcance del pulgar; lo destructivo lejos y
   con confirmación.
8. **Detalle que se nota sin verlo.** Háptica discreta en lo que cambia de estado, sombras y vidrio con
   la misma receta en toda la app, bordes de póster con el mismo radio, logos de plataforma siempre a la
   misma altura y peso.

## 2. Checklist por pantalla (iPhone)

| Pantalla | Debe cumplir |
|---|---|
| Inicio | El destacado llena el ancho a sangre con velo inferior; el título de la app no compite (pequeño o ausente cuando hay contenido); «Seguir viendo» con avance visible; filas con aire al final (la barra de pestañas no tapa) |
| Para ti · Mosaico | Ningún póster recortado a la mitad (si no cabe, no se pinta); la pieza enfocada o tocada crece con resorte; etiquetas («Popular», «Top 10») con una sola receta de insignia; el aviso de «conecta Trakt» es un pie discreto, no una tarjeta gris arriba |
| Para ti · Listas / Ver | Logos de plataforma uniformes (misma altura, en gris o color según marca); puesto del Top 10 como número grande en la esquina (una sola pieza); filas con título y dato en dos líneas máximo |
| Ficha | Arte a sangre que se funde con el fondo (tinte del póster); botón principal blanco; acciones secundarias en una fila que no se parte; sinopsis en español; episodios con miniatura, duración y estado (visto ✓, a medias, descargado) alineados |
| Fuentes | La recomendada arriba y marcada; chips con tono (bueno/aviso) consistente; el tamaño siempre con unidad |
| Reproductor | Controles sobre vidrio, se esconden solos; gestos con indicador propio (brillo, volumen, buscar, 2×); barra de avance con capítulos; subtítulos legibles (sombra, tamaño por ajuste); Up Next con cuenta atrás; salida con animación hacia el póster |
| Descargas | Avance en vivo por fila; estado vacío con una frase y una acción («Descarga algo desde una ficha») |
| Ajustes | Agrupado como Ajustes de iOS; cada fila con su valor a la derecha; nada técnico sin explicación de una línea |

## 3. Checklist (TV)

- Foco siempre visible y único; nada enfocable fuera de pantalla; el riel y la cuadrícula no se cortan al
  entrar (ya cubierto por rondas previas: mantenerlo).
- Letra grande (Ajustes → Tamaño del texto) sin que nada se encime.
- Las listas nuevas (Top 10, plataformas) con logo real y puesto; sin «undefined», sin inglés.

## 4. Cómo se revisa

1. Captura de cada pantalla tocada (simulador o `scripts/demo_server.py`) **antes y después**.
2. Pasar la checklist de arriba fila por fila y anotar lo que no cumple.
3. Letra de accesibilidad grande (iPhone) o Tamaño del texto grande (TV): nada se corta.
4. Reducir movimiento activado: nada depende de una animación para entenderse.
5. Español e inglés (iPhone): ningún texto de un idioma en el otro.

## 5. Hallazgos del recorrido del 2026-10-15 (iPhone, modo demostración)

| Pantalla | Hallazgo | Qué hacer |
|---|---|---|
| Inicio | «Orbital / Stremio al día» ocupa la parte alta como marca; el contenido empieza más abajo | Título grande solo al bajar (`navigationTitle` con `.inline` al hacer scroll) o quitarlo cuando hay destacado; el estado de sincronización va a un pie o a Ajustes |
| Inicio | «Mi lista» queda bajo la barra de pestañas | `contentMargins(.bottom)` o `safeAreaInset` para que la última fila respire |
| Para ti | Aviso «Lo más popular en Stremio. Conecta Trakt…» es una tarjeta gris pesada encima del mosaico | Pie discreto bajo el selector o una fila «Conectar Trakt» al final |
| Para ti | Pósters recortados (Carrie, Unabomber, Lanterns cortadas por el borde del mosaico) | El mosaico debe calcular columnas enteras y nunca partir una pieza |
| Ver | Solo Buscar y dos filas; pósters sin dato (año/tipo) | Traer las listas de la consola (Top 10, plataformas, géneros), año o tipo bajo cada póster, tráiler en la ficha |
| Ficha | Sinopsis en inglés con la app en español | Sinopsis desde la consola (TMDB cacheado) o TMDB directo cuando hay clave; si no hay, al menos indicar el idioma |
| Ficha | Cuatro botones secundarios iguales (Mi lista, Descargar, Fuentes, En la TV) con el mismo peso | Mi lista y En la TV como íconos en la barra superior; Descargar y Fuentes como fila |
| Reproductor | Subtítulo grande sin sombra; controles sin agrupación visual | Sombra/contorno a los subtítulos (token), controles sobre un vidrio inferior, capítulos en la barra |
| Fuentes | Correcta pero plana | Resaltar la recomendada con el tinte del título; ícono por calidad (4K, HDR) |
