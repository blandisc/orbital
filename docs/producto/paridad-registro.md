# Registro de paridad: una sola Orbital

Lo que la TV y el iPhone todavía no hacen igual, con su ola y quién lo hace. Se lee **antes de empezar cualquier trabajo de
interfaz** en cualquiera de las dos apps, y se actualiza en el mismo commit que lo resuelve.

Cómo se mantiene:

- Cuando se decide algo del iPhone, el commit dice qué pasa en la TV: «En la TV: igual», «En la TV: distinto a propósito
  (motivo)» o «En la TV: pendiente (ola N)». Lo pendiente entra aquí.
- Los textos pendientes se marcan en `design/vocabulario.json` (`pendiente`, por lado). Las piezas pendientes, en la tabla
  espejo de `docs/sistema-de-diseno.md`. `tests/web/design-parity.test.mjs` falla si un pendiente no está aquí, si un lado ya
  cumple y sigue marcado, o si un papel nuevo del iPhone no tiene renglón en la tabla espejo.
- Análisis de origen: «Una sola Orbital» (31 oct 2026), https://claude.ai/artifact/APC5mXnkx3msJtg1TvSEhc.

## Decisiones de Fernando (31 oct 2026)

| Decisión | En el iPhone | En la TV |
|---|---|---|
| La sección de descubrir se llama **Explorar** | Ya (31 oct) | Ya (ola 1; la voz entiende «Explorar» y «Para ti») |
| Las listas (Plataformas, Premios, Años…) | En Explorar | **Se quedan en Películas y series**: en la TV conviven juegos y video, y Explorar es el mosaico |
| Películas y series es el Inicio del iPhone (Seguir viendo, Lo nuevo de lo tuyo, Por lo que viste, Top 10, Mi lista) | — | Ya (ola 2: arriba; las listas siguen abajo; sin Mi media de OneDrive, decisión de Fernando) |
| Filtro avanzado | En Buscar | Ya (ola 3: ☰ › Filtro avanzado; formato, género, época, calificación, fama, dónde verla y país, cada uno con su color del arcoíris). Distinto a propósito: en filas con ‹ › (el mando) en vez de mosaicos, y sin premios ni estudios (están en Películas y series y en Colecciones) |
| Mazo «¿Qué vemos hoy?» (Paso · Ver ya · Guardar en «Tu match perfecto» de Trakt) | Ya | Ya (ola 2: ☰; el mismo orden diario que el iPhone; lo descartado se recuerda en cada aparato) |
| «Mi lista» es tu watchlist de Trakt | Ya (quedan textos) | Ya (ola 2: «Guardar en…», la fila, la lista y su porqué; la biblioteca de Stremio queda de respaldo) |
| Los canales de tus series: una lista guardada en Trakt («Tus canales»), para Ultra, Plus y Orbital | **Pendiente (sesión del iPhone): hoy los guarda en el teléfono; debe leer y escribir la lista de Trakt «Tus canales»** | Ya (ola 2: categoría «Tus canales» en TV en vivo, de esa lista; sin ella, las cinco de arranque del iPhone; Opciones › Agregar a Tus canales). Distinto a propósito: el horario es el de los canales de Orbital (con doblaje latino), no el `ChannelSchedule` del iPhone |
| Porqué en turquesa, solo si ayuda; sección = rótulo con ícono y línea | Ya | Ya (ola 1: `SectionHead` en dos niveles, `--color-reason`, `--color-orbital`) |
| Un botón sólido y redondos con su nombre debajo | — | Ya (ola 1: `Button({ icon })`) |
| Pie de tres pistas y ☰ | — | Ya (ola 1: `capHints`; «Atrás» y «Volver a…» se dejan de dibujar primero, y «Volver a…» está en ☰ con «Home en el mando») |
| Calificar: estrellas en la ficha y aviso al terminar | Ya | Ya (ola 3: en la ficha, en Opciones y en el aviso al terminar, con Y) |
| «Lo que ves» reemplaza a «Tu año» | Ya | Ya (ola 3: la entrada y el título; «Tu año, día por día» es la vista de adentro) |
| Entrega: una rama por ola, con capturas de antes y después de las cuatro superficies | — | — |
| «Por género»: 20 géneros con el mismo arte (Grok Imagine) en Buscar, la TV y el filtro avanzado (31 oct, tarde) | Ya (20) | Ya (19: «Musical» no está en el catálogo de Stremio, distinto a propósito) |
| «No recomendar por esta»: dejar picado el mazo de «Por lo que viste» | Ya | Ya (ola 2: Opciones en uno de tus títulos de «Porque viste»; Y deshace). Se recuerda en cada aparato, como el iPhone |
| El país de lo popular (Top 10 de Netflix y JustWatch) es el del teléfono hasta que elijas otro | Ya | Distinto a propósito: la TV usa el país de su `config.yaml` |
| El arcoíris del azul de Orbital (misma luz e intensidad, `design/tokens.json` › rainbow) como acento: categorías de TV en vivo y filtros | Pendiente: los colores de sus filtros con esta familia (sesión del iPhone) | Ya (categorías de TV en vivo y el filtro avanzado) |
| Una colección de Colecciones se filtra como una lista (series o películas, género, calificación, década, sin lo que ya vi), con el mismo menú y sus cápsulas (Fernando, 31 oct, noche) | Ya | **Pendiente (sesión de la TV)**: el mismo filtro en la colección abierta desde ☰ › Colecciones |
| «Crear una lista» al final de Tus listas: una lista nueva (privada) en tu Trakt (1 nov) | Ya | **Pendiente (sesión de la TV)**: con mando, escribir el nombre es incómodo; quizá solo desde el iPhone (por decidir con Fernando) |
| Letterboxd (solo leer, 1 nov): tu usuario y tu archivo en Ajustes › Cuentas, «Tus reseñas» en Lo que ves, tu reseña en la ficha, «Pasarlas a Trakt» y tus listas de Letterboxd en Tus listas (docs/producto/letterboxd/propuesta.html) | Ya | **Pendiente (sesión de la TV)**: tus reseñas en Lo que ves y en la ficha, y tus listas en Películas y series; se conecta solo desde el iPhone |

## Textos pendientes (`design/vocabulario.json`)

| Término | Lado | Qué falta | Ola |
|---|---|---|---|
| «Mi lista» | iPhone | Avisos y Ajustes con «tu watchlist» | sesión del iPhone |
| «Decide por mí» | iPhone | Dos textos con «¿Qué vemos?» | sesión del iPhone |
| «Colecciones» | iPhone | Un texto dice «… del canon en tu repisa» | sesión del iPhone |
| «Reintentar» | iPhone | Dos textos con «Intentar de nuevo» | sesión del iPhone |

## Olas de la TV

- **Ola 0 · el mecanismo** (este registro, el vocabulario con pendientes, la tabla espejo y sus pruebas).
- **Ola 1 · el lenguaje** (rama `claude/tv-ola-1-lenguaje`): hecho Explorar, rótulos de sección y porqué, botones redondos, pie de tres pistas, «Nuevo» como listón y pestañas de texto. **Ola 1b** (rama `claude/tv-ola-1b-piezas`): `Veil`, `EmptyState`, el esqueleto de carga y el espacio del título a lo suyo (`--layout-title-to-content`); los otros tres espacios no aplican a la TV (filas de alto fijo; `design/tokens.json` › layout dice por qué). Por decidir: dónde va el acento arcoíris del azul de Orbital.
- **Ola 2 · los lugares** (hecha, 31 oct): Películas y series como el Inicio del iPhone, el mazo, Decide por mí, Mi lista, Tus canales, «No recomendar por esta».
- **Ola 3 · lo tuyo** (hecha, 31 oct): calificar, «¿Cuándo la viste?» (en la TV, «Otro día…» ofrece días comunes en lugar del calendario: distinto a propósito), Lo que ves, Colecciones, filtro avanzado.
- **Rediseño estilo Apple TV** (31 oct): el lenguaje de la TV (docs/sistema-de-diseno.md § 0) en todas sus pantallas y el reproductor; ver la tabla «Revisión por pantalla».
- **Lo que le toca al iPhone** (su sesión): «Tus canales» en la lista de Trakt, los textos de arriba y el arcoíris en sus filtros.
- **Pedidos de Fernando para la TV (1 nov):** hecho: en pausa, más aire entre «En pausa» y el título, y los subtítulos se quedan en su lugar; el protector vuelve a moverse; el Inicio refinado (vidrio sutil) y el selector de consolas que se desliza. Juegos, la segunda fila: «el arte se queda» (hecho). Pendiente: el filtro en una colección abierta (ver la tabla de arriba).

- **Plan replanteado (1 nov, Fernando: «homogeneizar lo visual, la experiencia y las funciones»)**, maqueta y detalle en
  https://claude.ai/artifact/61nWawWCfd3nPPuLxvSyjW:
  - **Ola 4 · la ficha:** las partes y los nombres del iPhone («Tu calificación», «Quién sale y quién la hizo», «Si te gusta
    esta», «Los datos de la ficha», «Cuando salió cada episodio»); abrirla desde el póster.
  - **Ola 5 · funciones:** filtrar una colección, Próximas temporadas, Lo que ves completo (mapa del año, dona, cómo
    calificas, tu semana) y Letterboxd para leer.
  - **Ola 6 · piezas:** el rótulo de parte grande en Películas y series, un solo encabezado de hojas y menús, Opciones con
    las mismas entradas que el iPhone y la tabla espejo al día.
  - Por decidir con Fernando: «Crear una lista» en la TV.

## Distinto a propósito

Descargas, gestos del reproductor, PiP, modo claro y el cielo que se mueve son del teléfono. Juegos, TV en vivo, la voz y el
mando son de la TV. El aviso va abajo en el iPhone y arriba a la derecha en la TV. La superficie de las tarjetas es ink-850 en el
iPhone e ink-900 en la TV.
