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
| Películas y series es el Inicio del iPhone (Seguir viendo, Lo nuevo de lo tuyo, Por lo que viste, Top 10, Mi lista) | — | Pendiente · ola 2 (arriba; las listas siguen abajo) |
| Filtro avanzado | En Buscar | **En Películas y series y en ☰** · Pendiente · ola 3 |
| Mazo «¿Qué vemos hoy?», opción A (Paso · Ver ya · Mi lista) | Ya | Pendiente · ola 2 |
| «Mi lista» es tu watchlist de Trakt | Ya (quedan textos) | Ya (ola 2: «Guardar en…», la fila, la lista y su porqué; la biblioteca de Stremio queda de respaldo) |
| Los canales de tus series: una lista guardada en Trakt, para Ultra, Plus y Orbital | En el teléfono | Pendiente · ola 2 (categoría en TV en vivo). Nombre propuesto: «Tus canales» (en el glosario, «Tus series» son las que estás viendo) |
| Porqué en turquesa, solo si ayuda; sección = rótulo con ícono y línea | Ya | Ya (ola 1: `SectionHead` en dos niveles, `--color-reason`, `--color-orbital`) |
| Un botón sólido y redondos con su nombre debajo | — | Ya (ola 1: `Button({ icon })`) |
| Pie de tres pistas y ☰ | — | Ya (ola 1: `capHints`; «Atrás» y «Volver a…» se dejan de dibujar primero, y «Volver a…» está en ☰ con «Home en el mando») |
| Calificar: estrellas en la ficha y aviso al terminar | Ya | Pendiente · ola 3 |
| «Lo que ves» reemplaza a «Tu año» | Ya | Pendiente · ola 3 |
| Entrega: una rama por ola, con capturas de antes y después de las cuatro superficies | — | — |
| El arcoíris del azul de Orbital (misma luz e intensidad, `design/tokens.json` › rainbow) como acento: categorías de TV en vivo y filtros | Pendiente: los colores de sus filtros con esta familia (sesión del iPhone) | Ya en las categorías de TV en vivo; los filtros llegan con la ola 3 |

## Textos pendientes (`design/vocabulario.json`)

| Término | Lado | Qué falta | Ola |
|---|---|---|---|
| «Mi lista» | iPhone | Avisos y Ajustes con «tu watchlist» | sesión del iPhone |
| «Decide por mí» | iPhone | Dos textos con «¿Qué vemos?» | sesión del iPhone |
| «¿Qué vemos hoy?» | TV | El mazo no existe | 2 |
| «Colecciones» | TV | La vitrina no existe | 3 |
| «Colecciones» | iPhone | Un texto dice «… del canon en tu repisa» | sesión del iPhone |
| «Lo que ves» | TV | La entrada es «Tu año» | 3 |
| «¿Cuándo la viste?» | TV | Marcar como vista no pregunta la fecha | 3 |
| «Reintentar» | iPhone | Dos textos con «Intentar de nuevo» | sesión del iPhone |

## Olas de la TV

- **Ola 0 · el mecanismo** (este registro, el vocabulario con pendientes, la tabla espejo y sus pruebas).
- **Ola 1 · el lenguaje** (rama `claude/tv-ola-1-lenguaje`): hecho Explorar, rótulos de sección y porqué, botones redondos, pie de tres pistas, «Nuevo» como listón y pestañas de texto. **Ola 1b** (rama `claude/tv-ola-1b-piezas`): `Veil`, `EmptyState`, el esqueleto de carga y el espacio del título a lo suyo (`--layout-title-to-content`); los otros tres espacios no aplican a la TV (filas de alto fijo; `design/tokens.json` › layout dice por qué). Por decidir: dónde va el acento arcoíris del azul de Orbital.
- **Ola 2 · los lugares**: Películas y series como el Inicio del iPhone, el mazo, Decide por mí, Mi lista, tus canales.
- **Ola 3 · lo tuyo**: calificar, «¿Cuándo la viste?», Lo que ves, Colecciones, filtro avanzado.

## Distinto a propósito

Descargas, gestos del reproductor, PiP, modo claro y el cielo que se mueve son del teléfono. Juegos, TV en vivo, la voz y el
mando son de la TV. El aviso va abajo en el iPhone y arriba a la derecha en la TV. La superficie de las tarjetas es ink-850 en el
iPhone e ink-900 en la TV.
