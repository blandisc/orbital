# Desacoplar Stremio · avance

Notas cortas de cada corte al terminar: qué quedó y qué falta. El plan está en
[`revision-plan.md`](revision-plan.md) y la propuesta en
[`../desacoplar-stremio-iphone-2026-10-29.md`](../desacoplar-stremio-iphone-2026-10-29.md).

## Corte D · iPhone (29 oct 2026)

**Quedó** (commits `def0a537` y el siguiente):

- Buscar › «Lo más popular hoy» y su lista completa salen de Trakt `trending` (películas y series alternadas, hasta 100):
  «Lo que más se está viendo ahora», con sello TRAKT. Si Trakt no contesta, la última copia guardada.
- «Por género»: `trending?genres=` y, si trae menos de 20, `popular?genres=` de los últimos 3 años, sin repetir.
- Búsqueda escrita: Trakt primero. Cinemeta solo si Trakt falla, no encuentra nada (Cinemeta perdona errores de dedo) o
  tarda más de 1.2 s. Si los dos fallan: «No pude buscar. Revisa tu conexión.»
- Para ti: el mosaico de respaldo y su relleno salen de Trakt `trending`; el aviso «Lo más popular en Stremio…» salió.
  El estante de respaldo en Listas es «En tendencia».
- «Listas de Stremio» → «De tus complementos» (Para ti › Listas y el índice de secciones). Sello «Complemento» con su token
  `DS.Collections.addon`; `DS.Collections.stremio` salió del catálogo. Lo que una consola manda como «Stremio» o «Cinemeta»
  se traduce («Complemento» o sin sello).
- Inicio › destacado: sin respaldo de Cinemeta; si Trakt no contesta, se queda el guardado.
- Textos: «Guardar en…» dice «Mi lista»; el aviso tras guardar ya no dice «· Stremio»; «No pude cambiar Mi lista»;
  «No encontré este título» en una persona sin IMDb; errores de catálogo sin «Stremio»; textos huérfanos fuera del catálogo.
- Demo: los catálogos de complemento dicen «Complemento», y hay una sección «Aprobadas por la crítica» (origen
  «Rotten Tomatoes», «92 % en Rotten Tomatoes» como porqué) para ver cómo la pinta el iPhone con `-demo-console`.
- Pruebas: `TraktPublicListsTests` (popular, copia guardada, género con relleno, búsqueda Trakt primero y respaldo) y
  `RemoteForYouTests.testListOriginsNeverSayStremio`.

- «Aprobadas por la crítica» (Rotten Tomatoes) en Para ti del iPhone, siempre, armada en el teléfono igual que en la
  consola: películas de la lista pública de MDBList `tbotcotw/recent-certified-fresh` y series de la lista pública de Trakt
  `truckclancy/rotten-tomatoes-certified-fresh-tv-shows-ranked-by-tomatometer-score`, sin clave ni sesión, un día en caché y
  la última copia si no contestan (`OrbitalCore/Critics.swift`, `CriticsTests`). Filtro Películas · Series, sello «Rotten
  Tomatoes» (token `DS.Collections.critics`) y porqué «Certified Fresh» / «Fresh en Rotten Tomatoes». Si la consola la
  manda (id `critics`), se pinta igual. Las listas por configuración de la consola (`para_ti.critics_*`) no se leen todavía.

**Falta o queda para otros cortes:**

- Cuenta (corte A): «Mi lista» de Inicio (va sin sello mientras siga saliendo de Stremio), el error del botón Guardar de la
  ficha («…tu lista de Stremio», `TitleModel.swift`), el aviso de sesión de Inicio, entrar. «Mi lista» ya no está como
  tarjeta en Para ti › Listas: «Tu watchlist» de Trakt ocupa ese lugar.
- Ajustes (corte C): «Stremio conectado», el perfil «Stremio · Trakt · Orbital».
- Sin capturas de antes y después: el simulador está ocupado por otras sesiones. Se comprueba en Buscar (el carrusel dice
  «Lo que más se está viendo ahora» con sello TRAKT) y en Para ti › Listas («De tus complementos»).
- Ya venía de `main`: `HomeView.swift` tiene 603 líneas (tope 600, `FileBudgetTests`) y `ios_strings.py --check` pide
  «%@ sustos por delante» (en `PlayerScreen+Panel.swift` el número va con `Text(verbatim:)` o como `%lld`).

## Corte B · iPhone

Pendiente.

## Corte E · Consola (29 oct 2026, sesión en la nube)

**Quedó** (commit `dc8b330`):

- `orbital/trakt_sync.py`: la consola une su biblioteca de Stremio con lo de Trakt. Seguir viendo trae lo que tienes a
  medias en Trakt (`/sync/playback`) y el episodio que sigue de tus últimas 15 series (`/shows/{imdb}/progress/watched`);
  gana lo más reciente por título. Una película vista o una serie al día en otro aparato sale de la fila.
- Solo baja lo que cambió: pregunta `/sync/last_activities` al abrir Inicio (a lo más cada minuto), al arrancar y cada vez
  que la consola guarda algo en Trakt.
- Mi lista = tu watchlist de Trakt (ordenada por cuándo la guardaste); Guardar escribe en Trakt y deja copia en Stremio.
  «Quitar de Seguir viendo» borra el avance en Trakt y la consola recuerda la hora para no regresarlo con datos viejos.
- Ficha: los ✓ por episodio suman Stremio y Trakt; «Continuar» va a lo más reciente de los dos.
- Escribir como el iPhone (`orbital/scrobble.py` `plan`): respaldo cada 5 min (`start` y 2 s después `pause`), tope de
  79.9 % hasta que se da por visto (90 %, el final del episodio o los créditos), nunca una pausa bajo el 1 %; al terminar
  antes del 80 % se cierra en 80 % para que Trakt lo marque visto.
- Para ti de la consola ya no manda «Stremio» como origen (Trakt, Cinemeta o Complemento); con Trakt, Mi lista es «Tu
  watchlist».
- La voz («sigue viendo», «continúa X») encuentra lo que viste en el iPhone: los títulos de Trakt entran al mismo índice.
- Pruebas: `tests/test_trakt_sync.py` (fusión, lo que cambió, reglas de escritura, la consola completa con un Trakt falso).

**Rotten Tomatoes** (commit `f1c1da8`): Para ti › «Aprobadas por la crítica» (id `critics`): películas Certified Fresh de
los últimos 90 días (lista pública de MDBList `tbotcotw/recent-certified-fresh`) y series Certified Fresh (lista pública de
Trakt de truckclancy). Un día en caché. Sin clave sale igual; con la clave de MDBList (Ajustes › Cuentas › MDBList) va por
su API. Las listas se cambian en `config.yaml` (`para_ti.critics_movies`, `critics_series`). Pruebas: `tests/test_mdblist.py`.

**Falta:**

- Probarlo en la Lenovo con la cuenta real (aquí no hay red a Trakt ni a MDBList): abrir en el iPhone una película, pausarla
  y ver que salga en Seguir viendo de la TV en menos de un minuto al volver a Inicio.
- Confirmar que la lista pública de MDBList contesta en `/json` sin clave; si no, poner la clave en Ajustes.
- No hay sondeo aparte: si la TV está en Inicio sin tocarla, se entera al siguiente cambio de pantalla.
- Quitar de Seguir viendo una serie al día solo se recuerda en la consola (Trakt no tiene «ocultar de la fila» por
  título sin usar `/users/hidden`).
