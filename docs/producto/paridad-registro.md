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
| El mazo como Tinder (1 nov): ✕ Paso en rojo (←), ★ «Para hoy» en el azul de Orbital (↑, guardada y primera en Mi lista ese día, el aviso ofrece «Ver ya») y ♥ Guardar en verde (→); la carta es el póster grande con su porqué, datos, géneros, Trakt y el ▶ de «Ver ya», y al decidir se tiñe, asoma su sello y sale volando | Ya | Ya (con el mando: ← ↑ → y A «Ver ya») |
| Sin ánimos en el mazo (Fernando, 1 nov: fuera «Todos, Ligera, Intensa, Para pensar, En pareja»; un solo mazo, de todo) | Ya (2 nov: sin selector ni filtro de ánimo en MatchDeckModel) | Ya |
| «Mi lista» es tu watchlist de Trakt | Ya (quedan textos) | Ya (ola 2: «Guardar en…», la fila, la lista y su porqué; la biblioteca de Stremio queda de respaldo) |
| Los canales de tus series: una lista guardada en Trakt («Tus canales»), para Ultra, Plus y Orbital | **Pendiente (sesión del iPhone): hoy los guarda en el teléfono; debe leer y escribir la lista de Trakt «Tus canales»** | Ya (ola 2: categoría «Tus canales» en TV en vivo, de esa lista; sin ella, las cinco de arranque del iPhone; Opciones › Agregar a Tus canales). Distinto a propósito: el horario es el de los canales de Orbital (con doblaje latino), no el `ChannelSchedule` del iPhone |
| Porqué en turquesa, solo si ayuda; sección = rótulo con ícono y línea | Ya | Ya (ola 1: `SectionHead` en dos niveles, `--color-reason`, `--color-orbital`) |
| Un botón sólido y redondos con su nombre debajo | — | Ya (ola 1: `Button({ icon })`) |
| Pie de tres pistas y ☰ | — | Ya (ola 1: `capHints`; «Atrás» y «Volver a…» se dejan de dibujar primero, y «Volver a…» está en ☰ con «Home en el mando») |
| Calificar: estrellas en la ficha y aviso al terminar | Ya | Ya (ola 3: en la ficha, en Opciones y en el aviso al terminar, con Y) |
| «Lo que ves» reemplaza a «Tu año» | Ya | Distinto a propósito: solo en el iPhone (Fernando, 1 nov 2026: «no la pongas en escritorio»; la TV ya no la tiene) |
| Entrega: una rama por ola, con capturas de antes y después de las cuatro superficies | — | — |
| «Por género»: 20 géneros con el mismo arte (Grok Imagine) en Buscar, la TV y el filtro avanzado (31 oct, tarde) | Ya (20) | Ya (19: «Musical» no está en el catálogo de Stremio, distinto a propósito) |
| «No recomendar por esta»: dejar picado el mazo de «Por lo que viste» | Ya | Ya (ola 2: Opciones en uno de tus títulos de «Porque viste»; Y deshace). Se recuerda en cada aparato, como el iPhone |
| El país de lo popular (Top 10 de Netflix y JustWatch) es el del teléfono hasta que elijas otro | Ya | Distinto a propósito: la TV usa el país de su `config.yaml` |
| El arcoíris del azul de Orbital (misma luz e intensidad, `design/tokens.json` › rainbow) como acento: categorías de TV en vivo y filtros | Ya (los colores de sus filtros, 2 nov: Género coral, Época y Premios ámbar, Tiempo cielo, Calificación lima, Qué tan conocida verde, Origen lavanda; Dónde verla en el azul de Orbital) | Ya (categorías de TV en vivo y el filtro avanzado) |
| Una colección de Colecciones se filtra como una lista (series o películas, género, calificación, década, sin lo que ya vi), con el mismo menú y sus cápsulas (Fernando, 31 oct, noche) | Ya | Ya (ola 5: ☰ › Ordenar y filtrar en toda lista y colección, con Calificación y Década) |
| «Crear una lista» al final de Tus listas: una lista nueva (privada) en tu Trakt (1 nov) | Ya | Distinto a propósito: solo en el iPhone (Fernando, 1 nov 2026; con el mando, escribir el nombre es incómodo) |
| Temporadas (1 nov): en la ficha de la serie, lista desplegable; las cápsulas «T1, T2…» solo en el reproductor | Ya (tanda 6 de la auditoría iOS) | Distinto a propósito (1 nov): con el mando, LB/RB cambian de temporada con todas a la vista en cápsulas; una lista desplegable pediría abrirla y elegir (un paso más, sin ver cuántas hay) |
| Dejar de seguir una serie (1 nov): la campana «Siguiendo» de la ficha; Trakt la oculta del calendario y del progreso | Ya | Ya (la campana en la ficha de la serie, con Trakt: «Siguiendo» o «Seguir»; deja de salir en «A continuación», Lo nuevo de lo tuyo y el calendario) |
| Letterboxd (solo leer, 1 nov): tu usuario y tu archivo en Ajustes › Cuentas, tu reseña en la ficha, «Pasarlas a Trakt» y tus listas de Letterboxd en Tus listas (docs/producto/letterboxd/propuesta.html) | Ya | Ya (Ajustes › Cuentas › Letterboxd: tu usuario; en la ficha, su promedio junto a IMDb, TMDB y Trakt y «Reseñas en Letterboxd»: la tuya con el borde verde y las populares, con spoilers tapados; «Listas de Letterboxd» en Películas y series, cuando Letterboxd deja leer esa página). Distinto a propósito: sin «Pasarlas a Trakt» ni el archivo de exportación (se hace en el iPhone) |
| «Decide por mí» propone la serie completa, no un episodio (Fernando, 2 nov): «Ver la serie» o «Continuar la serie» y «42 min por episodio» | Ya | Ya (la carta ya no dice «Sigue T2 E5») |
| El número de resultados del filtro avanzado, opción A (Fernando, 2 nov): la cifra grande con «títulos», debajo películas y series con su ícono y «Antes de quitar las que ya viste»; en la puerta, «860 películas y 380 series la última vez» | Ya | Distinto a propósito (Fernando, 2 nov: no se hace en la TV): su filtro va en filas con el mando y enseña los resultados en una cuadrícula; la cifra con desglose es del cajón del iPhone |
| El número en el botón del filtro avanzado (Fernando, 2 nov): «Ver 1 240 resultados», «Ver hasta…» con Letterboxd o duración de series, «Nada con estos filtros» con cero | Ya | **Pendiente (ola de la TV)**: el botón de resultados del filtro avanzado de la TV dice cuántos saldrían, igual |
| Lo premium (2 nov, propuesta https://claude.ai/artifact/DhegvqEaNMkrsCDWHU9gfS): continuidad, foco con cuerpo, nada salta, sonido y vibración como idioma, resortes con nombre, tipografía de cerca, fondo vivo, reproductor, velocidad y respeto | Ya en lo suyo: los resortes con nombre (`DS.Motion.smooth`, `.snap`), el tracking óptico de SF Pro, la vibración (`sensoryFeedback`) y «Reducir movimiento» en cada animación. Pendiente: la ficha que vuelve a su póster (zoom de navegación) | Ya (2 nov): la ficha vuelve a su tarjeta, el foco con empujón, destello y hundido, sonidos `edge` y `success` con su pulso, `--ease-smooth`/`--ease-snappy` con los nombres del iPhone, `--type-*-tracking`, el fondo que se acerca y se queda, la pausa con fundido y la barra que avanza, y la prueba de velocidad. Distinto a propósito: sin miniaturas al adelantar (otro mpv) |

## Textos pendientes (`design/vocabulario.json`)

Ninguno (2 nov): «Mi lista», «Decide por mí», «Colecciones» y «Reintentar» ya se dicen igual en las dos apps; las traducciones viejas con «tu watchlist», «tu repisa», «Intentar de nuevo» y «¿Qué vemos?» salieron del iPhone.

## Olas de la TV

- **Ola 0 · el mecanismo** (este registro, el vocabulario con pendientes, la tabla espejo y sus pruebas).
- **Ola 1 · el lenguaje** (rama `claude/tv-ola-1-lenguaje`): hecho Explorar, rótulos de sección y porqué, botones redondos, pie de tres pistas, «Nuevo» como listón y pestañas de texto. **Ola 1b** (rama `claude/tv-ola-1b-piezas`): `Veil`, `EmptyState`, el esqueleto de carga y el espacio del título a lo suyo (`--layout-title-to-content`); los otros tres espacios no aplican a la TV (filas de alto fijo; `design/tokens.json` › layout dice por qué). Por decidir: dónde va el acento arcoíris del azul de Orbital.
- **Ola 2 · los lugares** (hecha, 31 oct): Películas y series como el Inicio del iPhone, el mazo, Decide por mí, Mi lista, Tus canales, «No recomendar por esta».
- **Ola 3 · lo tuyo** (hecha, 31 oct): calificar, «¿Cuándo la viste?» (en la TV, «Otro día…» ofrece días comunes en lugar del calendario: distinto a propósito), Lo que ves, Colecciones, filtro avanzado. «Lo que ves» salió de la TV el 1 nov (Fernando): solo en el iPhone.
- **Rediseño estilo Apple TV** (31 oct): el lenguaje de la TV (docs/sistema-de-diseno.md § 0) en todas sus pantallas y el reproductor; ver la tabla «Revisión por pantalla».
- **Lo que le toca al iPhone** (su sesión): «Tus canales» en la lista de Trakt. Los textos, hechos el 2 nov.
- **Pedidos de Fernando para la TV (1 nov):** hecho: en pausa, más aire entre «En pausa» y el título, y los subtítulos se quedan en su lugar; el protector vuelve a moverse; el Inicio refinado (vidrio sutil) y el selector de consolas que se desliza. Juegos, la segunda fila: «el arte se queda» (hecho). El filtro en una colección abierta también (ola 5: ☰ › Ordenar y filtrar).

- **Plan replanteado (1 nov, Fernando: «homogeneizar lo visual, la experiencia y las funciones»)**, maqueta y detalle en
  https://claude.ai/artifact/61nWawWCfd3nPPuLxvSyjW:
  - **Ola 4 · la ficha:** las partes y los nombres del iPhone («Tu calificación», «Quién sale y quién la hizo», «Si te gusta
    esta», «Los datos de la ficha», «Cuando salió cada episodio»); abrirla desde el póster.
  - **Ola 5 · funciones:** filtrar una colección, Próximas temporadas y Letterboxd para leer (sin «Lo que ves»: solo en el iPhone).
  - **Ola 6 · piezas:** el rótulo de parte grande en Películas y series, un solo encabezado de hojas y menús, Opciones con
    las mismas entradas que el iPhone y la tabla espejo al día.
  - «Crear una lista»: solo en el iPhone (Fernando, 1 nov).

## Distinto a propósito

Descargas, gestos del reproductor, PiP, modo claro y el cielo que se mueve son del teléfono. Juegos, TV en vivo, la voz y el
mando son de la TV. El aviso va abajo en el iPhone y arriba a la derecha en la TV. La superficie de las tarjetas es ink-850 en el
iPhone e ink-900 en la TV.
