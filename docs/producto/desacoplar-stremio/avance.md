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

**Falta o queda para otros cortes:**

- Cuenta (corte A): «Mi lista» de Inicio (va sin sello mientras siga saliendo de Stremio), el error del botón Guardar de la
  ficha («…tu lista de Stremio», `TitleModel.swift`), el aviso de sesión de Inicio, entrar. «Mi lista» ya no está como
  tarjeta en Para ti › Listas: «Tu watchlist» de Trakt ocupa ese lugar.
- Ajustes (corte C): «Stremio conectado», el perfil «Stremio · Trakt · Orbital».
- «Aprobadas por la crítica»: el iPhone calcula Para ti él mismo (la consola solo se usa con `-demo-console`), así que la
  sección solo sale si la consola la manda y el iPhone está en modo consola. Para tenerla siempre, el iPhone tendría que
  pedirle esa lista a la consola o a MDBList. Cuando la consola la publique, confirmar el id (la demo usa `critics`).
- Sin capturas de antes y después: el simulador está ocupado por otras sesiones. Se comprueba en Buscar (el carrusel dice
  «Lo que más se está viendo ahora» con sello TRAKT) y en Para ti › Listas («De tus complementos»).
- Ya venía de `main`: `HomeView.swift` tiene 603 líneas (tope 600, `FileBudgetTests`) y `ios_strings.py --check` pide
  «%@ sustos por delante» (en `PlayerScreen+Panel.swift` el número va con `Text(verbatim:)` o como `%lld`).

## Corte B · iPhone

Pendiente.
