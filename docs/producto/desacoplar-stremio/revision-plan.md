# Desacoplar Stremio · revisión del plan (29 oct 2026)

Sesión de revisión en la nube (sin Xcode ni Lenovo). Lee `main` @ 601fcad. No se escribió en ninguna cuenta.
Versión visual: [`revision-plan.html`](revision-plan.html).

## Resumen para Fernando

1. **Sí: Trakt va a ser lo que sincroniza el celular y la computadora; Stremio queda solo de respaldo.** Pero **hoy
   todavía no es cierto del lado de la computadora**: la consola arma «Seguir viendo», «Mi lista», las palomitas de
   visto y el «siguiente episodio» con Stremio. Solo usa Trakt en el momento de darle Play. Por eso hace falta un
   corte nuevo en la consola (**corte E**), del mismo tamaño que el corte A del iPhone, y tiene que ir **junto con el
   A**, no hasta la fase 3 como decía la propuesta.
2. **Stremio aparece o surte contenido en 43 lugares del celular** (27 no estaban en la propuesta). Todos
   tienen reemplazo. Lo único que se pierde es «Mi lista» de Stremio (pasa a tu watchlist de Trakt, como pediste).
   **«Lo más popular hoy» pasa a Trakt «En tendencia»** (lo que más se está viendo ahora): no pide clave, ya está en el
   código de los dos lados y es la misma fuente que ya usa la consola.
3. **Rotten Tomatoes no tiene API pública.** La forma estable es **MDBList**: un servicio gratuito que lleva las
   calificaciones de Rotten Tomatoes y arma listas con filtro «Certified Fresh» (películas) y Tomatómetro ≥ 60 %
   (series «Fresh»), con API oficial y clave gratis. Riesgo bajo para la app (si falla, la sección no sale) y
   medio en la frescura de los datos (MDBList depende de leer Rotten Tomatoes). Raspar Rotten Tomatoes directo es
   posible pero frágil y va contra sus términos: no lo recomiendo.

## 1. Trakt como sincronizador: qué falta en la computadora

### Lo que ya funciona

- Al darle Play, la consola retoma desde lo más reciente entre Stremio y Trakt (`orbital/watch.py` `resume_position`,
  L981–1011). La prueba del 29 oct lo confirmó en los dos sentidos.
- La consola ya avisa a Trakt al empezar, pausar, saltar y cerrar (`orbital/scrobble.py`, `player.py` L463–467,
  L552–563, L960).
- Lo que ya sale de Trakt en la consola y por tanto ya ve lo del iPhone: recomendaciones, «Porque viste X», «Tu año»,
  «Ocultar lo que ya vi», «¿Qué vemos?», «Tus series», «Próximos estrenos», Favoritos.

### Lo que hoy sale solo de Stremio en la consola

| Qué ves en la TV | De dónde sale hoy | Qué pasa si lo viste solo en el iPhone |
|---|---|---|
| Fila «Seguir viendo» (Inicio, Para ti, voz «sigue viendo») | Biblioteca de Stremio (`watch.py` L213–243, `catalog.py` L650–653, `foryou.py` L538, `voice.py` L844–854) | No aparece |
| «Continuar T2 E5» y la barra de avance en la ficha | `state.video_id` y `timeOffset` de Stremio (`watch.py` L1477–1498) | La ficha apunta a donde ibas antes |
| ✓ por episodio y «visto» | Bits de Stremio (`watch.py` L1487–1489) | Sin palomita |
| Siguiente episodio y «ya salió uno nuevo» | Stremio + Cinemeta (`watch.py` L523–546, L1668) | Sigue en el episodio anterior |
| «Mi lista» (fila y botón Guardar) | Biblioteca de Stremio (`catalog.py` L654–656, `watch.py` L1539–1557) | No aparece |
| Buscar por voz «continúa X», «última vez que la viste» | Índice de Stremio (`voice.py` L630, `catalog.py` L606) | No la encuentra |

### Corte E · La consola lee y escribe en Trakt (nuevo)

Todo en Python, dentro de este repo. Stremio sigue recibiendo su copia mientras dure la prueba.

| Pieza | Qué hace | Dónde |
|---|---|---|
| E1 · Seguir viendo desde Trakt | Une `/sync/playback` (películas y episodios a medias) con `/shows/{id}/progress/watched` (el siguiente episodio de las series que vas al día) y con Stremio; gana lo más reciente por título | `watch.py` (fuente nueva `continue`), `trakt.py` `playback()` y `watching()` ya existen |
| E2 · La ficha con Trakt | «Continuar T2 E6», barra de avance y ✓ por episodio desde `progress/watched`; películas vistas desde `/sync/watched` | `watch.py` L1477–1498, `web/js/core/watch.js` |
| E3 · Mi lista = watchlist de Trakt | La fila y el botón Guardar leen y escriben `/sync/watchlist` (ya existe `set_watchlist`); Stremio recibe copia | `watch.py` `set_in_library`, `catalog.py` |
| E4 · Escribir como el iPhone | Respaldo cada 5 min (`start` + 2 s + `pause`), nunca menos de 1 %, como mucho 79.9 % hasta el 90 % o los créditos, y entonces marcar visto con `POST /sync/history` (no existe todavía) | `scrobble.py`, `player.py` (junto a `SAVE_EVERY`), `trakt.py` |
| E5 · Enterarse rápido | Preguntar `/sync/last_activities` (una llamada chica) cada pocos minutos y al volver a Inicio; si algo cambió, refrescar y avisar a la pantalla (`library-changed`). Hoy solo Favoritos lo usa y Para ti guarda 15 min | `trakt.py`, `foryou.py` |
| E6 · Voz | «Sigue viendo» y «continúa X» buscan también en lo de Trakt | `voice.py` |
| E7 · Etiqueta que viaja al iPhone | Para ti manda `"source": "Stremio"` en Cinemeta y en catálogos de complementos; el iPhone lo pinta como sello | `foryou.py` L566–570 |

Tamaño: grande, parecido al corte A. Pruebas: fusión Stremio/Trakt por título (los dos lados, empate), serie al día
con episodio terminado en otro aparato, el tope de 79.9 %, el respaldo de 5 min con reloj falso, watchlist que viaja.

### Cambio al orden de la propuesta

| Antes | Ahora |
|---|---|
| «La consola no cambia, salvo un requisito para la fase 3» | El corte E va **en paralelo con el A**. Sin él, la fase 2 (comparar dos semanas) solo mide al iPhone |
| Fase 3 = el iPhone deja de escribir en Stremio | Fase 3 = **los dos** dejan de depender de Stremio; la consola puede seguir escribiéndole una copia sin costo |

Pendiente que ya estaba: confirmar los límites de la cuenta gratuita de Trakt (watchlist y listas) con tu cuenta.

## 2. Inventario: todo lo del celular que viene de Stremio o dice «Stremio»

Fuente: «cuenta» es tu biblioteca o tus complementos de Stremio; «Cinemeta» es el catálogo público de Stremio (no pide
cuenta, pero lleva su nombre y su criterio). Las rutas parten de `ios/`. ★ = no estaba en la propuesta.

### Inicio

| Lugar | Hoy | Fuente | Reemplazo |
|---|---|---|---|
| «Seguir viendo» | Tu avance | cuenta (`HomeModel.swift` L208–219) | Teléfono + Trakt `/sync/playback` y `progress/watched` (corte A) |
| «Quitar de Seguir viendo» | Escribe en Stremio | cuenta (`Watch.swift` L461) | Local + `DELETE /sync/playback/{id}` |
| «Mi lista» y su cuadrícula | Sello STREMIO | cuenta (`HomeView.swift` L108–115) | **Se pierde lo de Stremio**; la fila es tu watchlist de Trakt |
| Destacado sin Trakt | Popular de Cinemeta | Cinemeta (`HomeModel.swift` L249–251) | Desaparece (Trakt es obligatorio); si no contesta, la última copia |
| Aviso de sesión | «Tu sesión de Stremio se cerró…» | texto (`HomeView.swift` L42–47) | Sale; solo en Ajustes si conectaste Stremio |
| ★ Widget «Lo siguiente para ti» | Los 3 primeros de Seguir viendo | cuenta (`WidgetSnapshotBuilder.swift`) | Sale solo de lo nuevo de Seguir viendo |
| ★ Vocabulario de Siri | Títulos de Seguir viendo y Mi lista | cuenta (`HomeModel.swift` L309) | Igual, con las fuentes nuevas |

### Buscar

| Lugar | Hoy | Fuente | Reemplazo |
|---|---|---|---|
| «Lo más popular hoy» | «Lo que más se ve hoy en Stremio», sello STREMIO | Cinemeta (`BrowseView.swift` L230–236, `CatalogModel.swift` L36–55) | **Trakt «En tendencia»**, películas y series alternadas: «Lo que más se está viendo ahora» (ver abajo) |
| Su lista completa | `PopularGridView` | Cinemeta (`BrowseView.swift` L138, L325) | Trakt `trending`, hasta 100 |
| «Por género» (10) | Popular por género | Cinemeta (`CatalogModel.swift` L70–90) | Trakt `trending?genres=` y, si sale corto, `popular?genres=` de los últimos 3 años |
| Búsqueda escrita | Cinemeta primero | Cinemeta (`SearchModel.swift` L72–116) | Trakt primero, Cinemeta de respaldo |
| Errores | «No pude leer el catálogo de Stremio», ★ «Cinemeta no contestó» | texto (`CatalogModel.swift` L41, `Cinemeta.swift` L7–8, `BrowseView.swift` L165) | «No pude cargar lo popular. Revisa tu conexión.» |

### Para ti y Colecciones

| Lugar | Hoy | Fuente | Reemplazo |
|---|---|---|---|
| Mosaico sin fuentes | «Lo más popular en Stremio. Conecta Trakt…» | Cinemeta (`ParaTiView.swift` L29–30) | Trakt `trending`; el aviso sale |
| ★ Relleno del mosaico | Completa con Cinemeta | Cinemeta (`ParaTiModel.swift` L355–362) | Trakt `trending` |
| Listas › grupo «Listas de Stremio» | Mi lista + catálogos de complementos | cuenta (`ListsView.swift` L35–62) | «De tus complementos» (complementos del teléfono, corte B); Mi lista va con Trakt |
| Listas › estante de respaldo | «Lo más popular en Stremio» | Cinemeta (`ListsView.swift` L434–437) | Trakt `trending` |
| ★ Estantes de complementos | «De <complemento>», sello STREMIO | cuenta (`ForYou.swift` L215–262) | Mismos catálogos desde los complementos del teléfono; sello «Complemento» |
| ★ Para ti armado por la consola | «Lo más popular», sello STREMIO | Cinemeta vía la TV (`ListsView.swift` L409–412, `orbital/foryou.py` L566) | La consola manda Trakt o «Complemento» (corte E7) |
| ★ «¿Qué vemos?» › De dónde | Chip «Stremio» | texto (`DecideView.swift` L491–503) | «Complemento» |
| Colecciones › índice | «Listas de Stremio» | texto (`CollectionsView.swift` L10) | «De tus complementos» |
| ★ Colecciones › «Mi lista» | Cuadrícula | cuenta (`CollectionsModel.swift` L48–56) | Watchlist de Trakt |
| Sello de origen | STREMIO morado, ★ accesibilidad «De Stremio», ★ color `DS.Collections.stremio` | texto/token (`Design/Collections.swift` L90–109, `Tokens+Screens.swift` L273) | Sello «Complemento» con su token; el de Stremio se borra del catálogo |

### La ficha y el reproductor

| Lugar | Hoy | Fuente | Reemplazo |
|---|---|---|---|
| ★ «Continuar T2 E5», temporada inicial, minutos que quedan | `state.video_id` | cuenta (`TitleModel.swift` L260–321) | Local + Trakt `progress/watched` |
| ★ ✓ por episodio y «N de M vistos» | Bits de Stremio | cuenta (`TitleModel.swift` L249, `EpisodeRows.swift`) | Local + Trakt `progress/watched` |
| ★ Botón Guardar | Estado y error «…tu lista de Stremio» | cuenta (`TitleModel.swift` L372–377) | Watchlist de Trakt |
| Hoja «Guardar en…» | «Mi lista (Stremio)» | texto (`SaveSheet.swift`, `SaveDestination.swift`) | «Mi lista» |
| ★ Aviso tras guardar | «Guardada en Mi lista · Stremio» | texto (`AppEnvironment+Titles.swift` L91) | «Guardada en Mi lista» |
| Errores de póster | «No pude cambiar tu lista de Stremio» | texto (`AppEnvironment+Titles.swift` L41, L58) | «No pude cambiar Mi lista» |
| ★ Marcar como vista | Escribe en Stremio (y Trakt) | cuenta (`TitleActions.swift` L72–76) | Local + `POST /sync/history`; Stremio copia en fases 1–2 |
| ★ Reanudar al dar Play (y en Infuse) | Lo más reciente entre Stremio y Trakt | cuenta (`Watch.swift` L224–243) | Local contra Trakt (corte A) |
| ★ Guardar el avance y visto al terminar | Sube a Stremio | cuenta (`Watch.swift` L321–357) | Local → Trakt; Stremio copia |
| ★ Fuentes y descargas | Salen de los complementos de tu cuenta | cuenta (`StreamFinder.swift`) | Complementos del teléfono (corte B) |
| ★ «Ya está para ver» (avisos de estreno) | Depende de tus complementos | cuenta (`ReleaseAlerts.swift`) | Complementos del teléfono |
| ★ Persona sin IMDb | «Este título no está en Stremio» | texto (`PersonView.swift` L15) | «No encontré este título» (el fallo es de TMDB) |

### Otros

| Lugar | Hoy | Fuente | Reemplazo |
|---|---|---|---|
| Entrada | «Entra con tu cuenta de Stremio…» | cuenta (`LoginView.swift`, `RootView.swift`) | La guía nueva (corte C) |
| ★ Ajustes › perfil | «Conectado: Stremio · Trakt · Orbital» | texto (`SettingsView.swift` L168–173) | Solo lo que conectaste |
| ★ Ajustes › Cuenta | «Stremio conectado», «¿Cerrar sesión de Stremio?» | texto (`SettingsView.swift` L96, L108) | Cuentas › «Stremio · respaldo» (único lugar donde dice Stremio) |
| Ajustes › Complementos | Los de tu cuenta | cuenta (`Addons.swift` L145–150) | Sección propia (corte B) |
| ★ Mi media (OneDrive) › Ver serie | Empieza donde ibas en Stremio | cuenta (`MiMediaModel.swift` L146–151) | Local + Trakt |
| ★ Video abierto desde otra app | Guarda el avance en Stremio | cuenta (`AppEnvironment.swift` L340–350) | Local + Trakt |
| ★ Mensajes de error | «Conecta tu cuenta de Stremio en Ajustes», «No pude conectar con Stremio…», «Ese correo no tiene cuenta de Stremio» | texto (`Watch.swift` L393, L434, L449; `StremioAPI.swift`; `UserMessages.swift`; `SessionModel.swift` L21) | Solo en Ajustes › Stremio |
| ★ Textos sin uso | «Stremio al día», «Este título no está en Stremio.» | `Localizable.xcstrings` | Borrar |
| ★ Modo demo | Listas «Stremio», «De Cinemeta» | `DemoHTTPClient.swift` L228 | Actualizar con lo nuevo |

**Lo que se queda con Cinemeta a propósito** (no dice Stremio en pantalla): la ficha, temporadas y episodios, duración,
año, reconocer títulos de archivos y de OneDrive, Simpson, premios, Siri «pon X». Es público, sin cuenta, y usa los
mismos identificadores que los complementos. Dos cambios chicos: la calificación «IMDb de Cinemeta»
(`RichTitle.swift` L28) dice solo «IMDb».

### «Lo más popular hoy»: qué fuente

| Candidata | Qué mide | Pide | Ya está | Veredicto |
|---|---|---|---|---|
| **Trakt `trending`** | Lo que la gente está viendo en este momento | Solo el id de la app | `Trakt.swift` L279, `trakt.py` L472 | **Recomendada** |
| Trakt `watched/weekly` | Lo más visto en 7 días | Solo el id de la app | No | Buena, pero es «esta semana», no «hoy» |
| TMDB `trending/day` | Interés del día en TMDB | Clave de TMDB (opcional en la app) | Parcial | Respaldo solo si hay clave |
| Top 10 Netflix / JustWatch | Lo más visto por plataforma | Nada | Sí, en Para ti | Ya sale en Recomendadas; repetirlo en Buscar duplica |

Por qué Trakt `trending`: es lo único que dice «hoy» de verdad, no pide nada extra, ya lo usa la consola en Para ti
(«En tendencia»), trae películas y series y acepta filtro de género (sirve también para «Por género»). Se guarda unas
horas, como hoy Cinemeta. Detalle: Trakt cuenta usuarios de Trakt, que ven más series y anime que el promedio;
para «lo más popular» de todo el mundo no hay fuente gratis mejor.

## 3. Rotten Tomatoes en Para ti

### De dónde sale «RT: Certified Fresh» en el código

No es una lista que el código cargue. Es un **ejemplo** en comentarios y pruebas (`orbital/foryou.py` L10, L251, L523;
`ListsView.swift` L499; `tests/test_foryou.py` L1059) del nombre que tendría una lista de Trakt o el catálogo de un
complemento. Probablemente viene del complemento «Top Movies» de Deflix, que tiene un catálogo así.

### Opciones

| Opción | Qué es | Estable | Riesgo |
|---|---|---|---|
| API oficial | Solo para socios, por Fandango, con contrato pagado | Sí | Inalcanzable para un uso personal |
| Raspar rottentomatoes.com | Leer sus páginas de exploración («Certified Fresh» en casa, series «Fresh») | Baja: cambian el sitio y se rompe | Va contra los términos de Fandango; bloqueos; mantenimiento |
| **MDBList** | Servicio que junta calificaciones (IMDb, Rotten Tomatoes, Metacritic…) y arma listas con filtros; API oficial con clave gratis (1 000 consultas al día) | Media-alta: lleva años, lo usan Kometa, Plex y complementos de Stremio | MDBList depende de leer Rotten Tomatoes; si se corta, la lista se queda vieja, no se rompe la app |
| Listas de Trakt que copian RT | Listas públicas que MDBList u otros mantienen en Trakt | Media: dependen de un tercero que no conoces | Pueden dejar de actualizarse; hay que agregar «leer listas públicas» (hoy solo se leen las tuyas) |
| Complemento «Top Movies» (Deflix) | Catálogo «RT Certified Fresh» | Baja: sin cambios en ~3 años | Solo películas; puede apagarse |

### Recomendación

**MDBList, con dos listas que Orbital lee por su API:** «Certified Fresh» (películas, las más recientes primero) y
«Series Fresh» (Tomatómetro ≥ 60 %, temporada reciente). La consola las pide una vez al día y se las pasa al iPhone en
Para ti, como ya hace con Netflix y JustWatch. Sección «Aprobadas por la crítica», con el porcentaje en el póster.

- Lo que necesito de ti: crear una cuenta en mdblist.com (entras con Trakt) y la clave de API gratuita. Las dos
  listas las armo yo con sus filtros; o, si prefieres no tocar nada, se usan listas públicas ya hechas.
- Por confirmar desde la Lenovo o la Mac (aquí la red no deja entrar a rottentomatoes.com ni a mdblist.com): que el
  filtro «Certified Fresh» exista para series (en películas está confirmado; para series se usa el Tomatómetro ≥ 60 %).
- Nombre y logo: «Rotten Tomatoes» y «Certified Fresh» son marcas de Fandango. Para uso personal no hay problema;
  la sección dice «Aprobadas por la crítica» y el dato «94 % en Rotten Tomatoes».

## 4. Lo que necesito de Fernando para empezar

1. **OK al corte E** (la consola lee y escribe en Trakt) en paralelo con el A, y a que Trakt sea el principal
   también en la TV.
2. **OK a Trakt «En tendencia»** para «Lo más popular hoy» y «Por género».
3. **Rotten Tomatoes:** ¿vamos con MDBList? Si sí, la clave de API de mdblist.com (en Ajustes de la consola, nunca
   en el repo).
4. **Tu plan de Trakt** (gratis o VIP), para revisar los límites de la watchlist antes de que «Mi lista» dependa de
   ella.

Orden propuesto: A (iPhone) + E (consola) juntos; B y D en paralelo; luego C; fase 2 cuando A y E estén en las dos
pantallas.

## Fuentes de la investigación de Rotten Tomatoes

- MDBList, API y límites: https://docs.mdblist.com/docs/api
- MDBList, filtros por Rotten Tomatoes y Certified Fresh: https://forums.plex.tv/t/ultimate-trakt-tv-list-setup-mdblist-com/632436
- Kometa, MDBList como fuente de listas: https://kometa.wiki/en/latest/files/builders/mdblist/
- API oficial solo para socios: https://api.market/blog/proapi/rotten-tomatoes/best-rotten-tomatoes-api
- Términos de Fandango (rigen a Rotten Tomatoes): https://www.fandango.com/Terms-and-Policies
- Cliente no oficial (raspado de la página «Certified Fresh»): https://pypi.org/project/rotten_tomatoes_client
- Complemento Top Movies de Deflix: https://github.com/deflix-tv/stremio-top-movies
- Requisitos de Certified Fresh: https://editorial.rottentomatoes.com/guide/best-movies-of-2019/
