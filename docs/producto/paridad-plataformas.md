# Una sola experiencia: paridad entre la consola (TV) y el iPhone

Análisis holístico del 2026-10-15 con capturas de las dos plataformas (consola en `scripts/demo_server.py`,
iPhone en el simulador en modo demostración). La pregunta no es «¿se parecen?» sino **«¿se sienten como el
mismo producto, igual de pulido, y se ayudan entre sí?»**. Complementa `diagnostico-2026-10.md` y
`barra-de-calidad-visual.md`.

## 1. La firma de Orbital (lo que hace que se reconozca en cualquier pantalla)

De las capturas de la consola salen ocho rasgos que son *la marca sensorial* de Orbital. El iPhone debe
tenerlos todos, traducidos a su medio (dedo, vertical, componentes nativos de iOS 26), no copiados:

| # | Rasgo de firma | En la consola hoy | En el iPhone hoy | Veredicto |
|---|---|---|---|---|
| F1 | **El arte manda y el fondo lo sigue** (`--art-tint`: el fondo toma el tono del título enfocado; espacio vivo con estrellas en Inicio/Para ti) | Sí, en todas las vistas | Solo en el destacado de Inicio y la ficha (`averageColor`); el resto es grafito plano | Brecha |
| F2 | **Mosaico vivo** (6 columnas, la enfocada crece ×2,3 y enseña etiqueta + **logo del título** + dato; cascada; ambiente a los 30 s; «cobra vida» al quedarse quieto; ninguna pieza partida) | Sí | 3 columnas fijas, la del centro siempre ancha, título en texto (sin logo), sin cascada ni ambiente, **pósters cortados por el borde** | **Crudo**: el ejemplo del usuario |
| F3 | **Logos de título** (metahub) en vez de texto en destacados y piezas grandes | Sí (Hades, The Last of Us) | No: siempre texto | Brecha |
| F4 | **Etiquetas con una sola voz** («En tendencia», «Popular», «Recomendada», «Seguir viendo», «Top 10») y **datos de una línea** («Serie · 16 episodios», «jugaste hace 30 min · 48 h en total», «quedan 20 min») | Sí, generados en Python (`foryou.py`, `watch.py`) | Parcial: los textos se rehacen en Swift y a veces difieren | Brecha de integración |
| F5 | **Riel con identidad** (fotos de consolas, logos de plataformas de TMDB, íconos propios de fuente) | Sí | Chips de texto (Todo · Trakt · Netflix…) sin logo | Brecha |
| F6 | **Ficha que se funde con el arte** (máscara, logo, de dónde es, hasta cuatro datos, sinopsis en español, acciones con glifo) | Sí | Arte arriba con esquinas, título en texto, sinopsis en inglés sin TMDB, cuatro botones iguales | Brecha |
| F7 | **Cinemática de apertura** (la portada en órbita sobre estrellas y el salto a velocidad luz) | Sí, al abrir cualquier cosa | No: el reproductor abre en negro con un spinner | Brecha |
| F8 | **Un solo idioma de botones y pistas** (A abre · X secundaria · Y opciones · B atrás) | Sí | Equivalente nativo correcto (toque, mantener, deslizar, menú ⋯) | OK: no copiar |

Donde el iPhone va **por delante** y la consola debe aprender: miniaturas y estado por episodio en la
ficha, descargas con avance en vivo, «En la TV» desde la ficha, y los estados vacíos con una frase y una acción.

## 2. Paridad por superficie

| Superficie | Consola | iPhone | Qué sobra o falta para que sea «lo mismo» |
|---|---|---|---|
| Inicio | Saludo («Buenas tardes»), destacado con logo y dato, «También tenías», Tus consolas | Marca «Orbital» + estado, destacado con póster y «quedan 20 min», Seguir viendo, Mi lista | iPhone: saludo en vez de marca; logo de título en el destacado; fila «También tenías» con los mismos datos. Consola: nada |
| Para ti · Mosaico | F2 completo | Crudo (ver F2) | **CEN-36** |
| Para ti · Listas | Riel con logos + encabezado grande + filtros + cuadrícula + ficha lateral | Chips de texto + cuadrícula | Logos en los chips, encabezado de lista con su dato («Lo más popular en México»), puesto del Top 10 (CEN-17/18) |
| Buscar / Ver | Teclado en pantalla, grupos (En tu consola, Películas, Series), dictado | `.searchable` + 2 filas populares | iPhone: año y tipo bajo cada póster (ya hecho), mismas listas que la consola (CEN-21) |
| Ficha | F6 | Ver F6 | **CEN-37**: tinte del arte en todo el fondo, logo de título, línea de datos igual que la consola, sinopsis en español desde la consola (CEN-24) |
| Fuentes | Lista con chips (idioma, calidad, tamaño, Al instante) | Igual, mismos chips, misma puntuación | OK (compartido por diseño) |
| Reproductor | mpv con panel propio, capítulos, Saltar intro, Up Next, ¿Sigues viendo? | Nativo con lo mismo; faltan gestos (CEN-16) y cinemática de apertura (CEN-38) | Apertura: la misma órbita antes de que arranque el video |
| Estados vacíos / errores | En palabras, con «Reintentar» | En palabras, con acción | OK |
| Conexión entre pantallas | QR, «Ver en la TV», claves y sesión prestadas | Ídem | Falta el camino de vuelta (CEN-19), «Seguir en el iPhone» (CEN-20) y Para ti compartido (CEN-18) |

## 3. Cómo se garantiza la paridad (no con buena memoria)

1. **Un vocabulario compartido, generado una vez.** Las etiquetas (`badge`) y las líneas de dato se
   calculan en Python y ya viajan en la API; el iPhone conectado las **enseña tal cual** y solo las
   rehace sin consola. `scripts/ios_golden.py` ya compara funciones Python↔Swift: se extiende con
   `runtime_text`, `hours_text`, `time_left` y las etiquetas (CEN-39).
2. **Catálogo de piezas espejo.** Cada pieza de firma existe en los dos catálogos con el mismo nombre y
   la misma descripción en los dos documentos de sistema de diseño (`Mosaic`, `FeatureTile`, `Badge`,
   `Chip`, `Rail`, `DetailPanel`, `LaunchOrbit`); `design-system.test.mjs` y `DesignTests` ya impiden
   piezas sueltas. Falta la tabla de equivalencias en `docs/sistema-de-diseno.md` (CEN-39).
3. **Capturas gemelas.** Para cada superficie, una captura de la consola y una del iPhone en la misma
   carpeta (`docs/producto/capturas/`), que se renuevan en cada tarea de interfaz y se revisan contra
   `barra-de-calidad-visual.md`.

## 4. Tareas que salen de este análisis

| Id | Qué | Prioridad |
|---|---|---|
| CEN-36 | Mosaico del iPhone con la firma de la consola: columnas calculadas sin cortes, pieza enfocada que crece con resorte y enseña etiqueta + logo + dato, cascada al desplazar, ambiente a los 30 s, «cobra vida», respeta Reducir movimiento | Alta (ola 1) |
| CEN-37 | Ficha e Inicio del iPhone con la firma: tinte del arte en el fondo de toda la pantalla, logo de título (metahub) con caída a texto, línea de datos idéntica a la consola, saludo en Inicio, fila «También tenías» | Alta (ola 1) |
| CEN-38 | Cinemática de apertura en el iPhone: la órbita de Orbital (póster + anillo + estrellas) mientras el reproductor busca fuente y arranca; con Reducir movimiento, un fundido | Media (ola 2) |
| CEN-39 | Vocabulario y catálogo espejo: goldens de textos Python↔Swift, tabla de equivalencias de piezas en los dos sistemas de diseño, carpeta de capturas gemelas | Media (ola 2) |
| CEN-40 | Riel/chips de Para ti › Listas en el iPhone con logos de plataforma y encabezado con dato, como el riel de la consola | Media (ola 2) |
