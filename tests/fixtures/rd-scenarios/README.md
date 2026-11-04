# Escenarios comunes de Real-Debrid (iPhone y TV)

Fernando, 3 nov 2026: «análisis de fondo… para que no encuentre yo más errores». Con «El viento tiene miedo» encontró cinco
fallas; estos escenarios buscan las siguientes antes que él, en muchos tipos de título, y hacen que **el iPhone y la TV
decidan lo mismo**. Cada app los corre con su código de verdad y compara con `expected`.

**Forma v2** (3 nov, la que pidió la TV para correrlos sin inventar nada): llaves neutras en inglés, la entrada tal como la
contesta cada servicio y la salida en claves; el texto que debe ser idéntico sale de `design/vocabulario.json`.

- iPhone: `ios/OrbitalCore/Tests/OrbitalModelsTests/RDScenarioTests.swift` (y `RDScenarioRig.swift`, que arma cada uno).
- TV: `tests/test_rd_scenarios.py`.

## Qué hay aquí

- `escenarios/NN-nombre.json`: uno por escenario (entrada y `expected`). Del 01 al 23, los primeros; del 24 al 32, los que
  pidió la TV.
- `torrentio/<video>.json`: lo que contestó Torrentio **sin Real-Debrid** el 3 nov 2026 (público, sin clave, solo lectura),
  tal cual: `https://torrentio.strem.fun/stream/<tipo>/<video>.json`.
- `cinemeta/<id>.json`: el `meta` de Cinemeta del mismo día, tal cual (`kitsu_1.json`: el del complemento Anime Kitsu).
- TMDB pide clave: lo suyo va escrito a mano en cada escenario (`tmdb.source` lo dice). Nunca se usó una clave ni la cuenta
  de Fernando.

## La entrada

| Llave | Qué es |
| --- | --- |
| `id`, `name`, `why` | El archivo, el nombre y por qué existe el escenario. |
| `now` | La hora de la app (ISO, UTC). Todo lo que depende del reloj sale de aquí: «salió hoy», «sale el viernes 18», 24 h sin avanzar, la cuenta vencida. |
| `app` | Tus preferencias tal cual: `language` (`es-MX`, el idioma de la app), `audio` (`es`), `spanish` (`es-419` latino, `es-ES` castellano o `""`) y `quality` (`1080p`). |
| `title` | Lo que abres: `kind` (`movie`/`series`), `id` (el del título) y `video_id` (el episodio; en una película, el mismo id). |
| `tmdb` | Lo que contesta TMDB y usan las dos apps, o `null` (sin clave de TMDB): `find` (la respuesta de `/find/<imdb>`), `detail` (la ficha en `language=es-MX`: `title`/`name`, `original_title`/`original_name`, `original_language`, `origin_country`, `overview`), `translations` (si hace falta) y, en una serie, `season` (si hace falta). `source`: de dónde salió. |
| `cinemeta` | El archivo del `meta` de Cinemeta. Con un id de Kitsu, `kitsu` es el `meta` del complemento Anime Kitsu y `cinemeta` el de su IMDb. |
| `torrentio` | `file` (lo capturado sin Real-Debrid), `captured`, `url`; `status`: `ok`, `down` (HTTP 503: caído o bloqueado) o `rd_error` (en lugar de versiones, una sola: `{"name": "[RD error] Torrentio", "url": ".../videos/failed_access_v2.mp4"}`); `options`: `only_instant` (`debridoptions=nodownloadlinks`) y `languages_first` (`language=latino,spanish…`, tu plan B); `next`: lo capturado del siguiente episodio, si el escenario lo usa. |
| `addons` | Lo prendido en tu lista de complementos: `torrentio`, `kitsu`, `opensubtitles` (solo subtítulos). Sin `torrentio`, tu lista está armada sin nada que dé versiones. |
| `rd` | Tu Real-Debrid (ver abajo). |
| `act` | Lo que haces antes de mirar: `"request"` = tocas «Pedirlo y avisarme» una vez (y Real-Debrid contesta lo que diga `rd.error`). Sin `act`, solo abres la ficha. |

### `rd`

| Llave | Qué es |
| --- | --- |
| `key` | Si la app tiene tu clave de Real-Debrid. |
| `instant` | Las huellas que tu Real-Debrid ya tiene (las que Torrentio llama «[RD+]»). |
| `account` | `GET /user`: `id`, `premium` (bool), `expires` (ISO o `null`) y `problem`: `null`, `expired` (venció), `no_premium` (gratis) o `bad_key` (la clave ya no sirve: `/user` contesta 401, `error_code` 8). Las mismas tres causas que `DEBRID_CAUSES` de la TV. |
| `torrents` | Los de tu cuenta, como `GET /torrents` y `GET /torrents/info/<id>`: `id`, `hash`, `status`, `progress`, `seeders` (si no viene: 3 bajando, 0 si no), `files`, `links`; `unrestrict` (solo de las pruebas): enlace → lo que da `POST /unrestrict/link`. |
| `book` | La libreta de pedidos: entradas del contrato (`design/addons-contract.json` › `requests`), con sus horas (`since`, `updated`, `progress_at`) relativas a `now`. |
| `error` | Lo que contesta `POST /torrents/addMagnet` al pedir (`{code, http, name}`: el `error_code`, el HTTP y el nombre de Real-Debrid), o `null` (lo acepta: `{"id": "RNEW"}`). |

### Torrentio con tu Real-Debrid (la regla para las dos apps)

De lo capturado sin Real-Debrid se arma lo que Torrentio da con él, versión por versión, en el mismo orden:

- `name`: `"[RD+] Torrentio\n<calidad>"` si su `infoHash` está en `rd.instant`; si no, `"[RD download] Torrentio\n<calidad>"`
  (`<calidad>` es lo que venía después del salto de línea; sin salto, solo `"[RD+] Torrentio"`).
- `url`: `https://torrentio.strem.fun/resolve/realdebrid/<KEY>/<infoHash>/null/<fileIdx o "undefined">/<behaviorHints.filename
  con %-escape de ruta, o "video.mkv">`. `<KEY>` es cualquier clave fija de prueba (el iPhone usa 52 «K»).
- Se quitan `infoHash` y `fileIdx` (como de verdad); `title` y `behaviorHints` quedan igual.
- Con `torrentio.options.only_instant`, solo las «[RD+]».
- Sin `rd.key`: lo capturado tal cual (torrents sin enlace: el iPhone no los reproduce).
- Lo que existe para pedir (Torrentio sin Real-Debrid) es siempre lo capturado tal cual.

## Lo esperado

`expected` dice lo que las dos apps deben decidir. Una llave que empieza con `_` es una nota. En un objeto solo cuentan las
llaves que trae; una lista va completa y en orden.

| Llave | Qué es |
| --- | --- |
| `title`, `logo` | El nombre de la ficha (texto exacto) y si lleva el logo de metahub (en inglés; no si está hecha en tu idioma). |
| `video_id` | El video del botón principal. |
| `primary` | El botón principal: `play` («Ver»), `request` («Pedirlo y avisarme»), `requested` (ya pedido y en camino: «En cola», «Bajando en Real-Debrid · 42 %»…) o `fix` (un problema con su salida en `fix`). |
| `cause`, `cause_arg` | La causa que se ve (la clave de la tabla de abajo) y lo que cambia en su texto (`"el viernes 18 de diciembre"`, `"42 %"`), o `null`. Con `request`, la causa es `not_in_rd` (su renglón). |
| `fix` | La salida de cada problema: `renew` («Renovar»), `settings` («Ajustes»), `retry` («Reintentar»), `other_version` («Probar otra versión» / «Elegir otra versión»), `request` («Pedirlo y avisarme») o `notify` («Avisarme cuando aparezca»); `null` si no hay problema. |
| `offer` | Lo que pediría «Pedirlo y avisarme»: `{hash, language, res}`, o `null`. |
| `instant_aside` | «Verlo en X al instante»: `{hash, language, res}`, o `null`. |
| `recommended` | Lo que pone «Ver»: `{hash, file, language, res}` (`file`: su `fileIdx`), o `null`. |
| `rows` | Las tarjetas de arriba de «Versión», en orden: `{code, hash, res, state, recommended, other}`. `code` es la fila (`es-419`, `es-ES`, `es` = «Español (no dice cuál)», `en`, `ja`…); una dual sale en sus dos filas. `state`: `instant`, `requested_ready` («Al instante · la pediste»), `to_request` («↓ Por pedir») o `direct`. `other`: marcada «¿Otro título?» / «¿Otro episodio?». |
| `to_request` | «Hay que pedirlas · tardan»: `{code, hash, res}`. |
| `hidden` | Cuántas se esconden (de cine, tráileres). |
| `play_now` | Lo que pone «Ver ahora» del aviso de listo (el reproductor sin versión elegida): la huella, `"ready_source"` (el enlace de tu Real-Debrid de un pedido listo que Torrentio no lista) o `null`. |
| `request` | El pedido de tu cuenta que trae este video (el anotado o el paquete que lo trae): `{hash, state, percent, stuck}` (`state` del contrato; `stuck`: 24 h sin avanzar), o `null`. |
| `other_account` | Lo que otra cuenta (la TV con la suya) pide de este video y sigue en camino: `{state}`, o `null`. |
| `next_episode` | En una serie: el siguiente episodio (`video_id`) y si un pedido tuyo ya lo trae (`request`: su huella; `ready`). |

### Las causas, en el orden de `design/vocabulario.json › causas`

| Clave | Texto |
| --- | --- |
| `downloading` | «Bajando en Real-Debrid · » + `cause_arg` |
| `unreleased` | «Aún no se estrena · sale » + `cause_arg` (el día de estreno de Cinemeta, dicho en UTC: es un día, no una hora) |
| `cannot_search` | «No puedo buscar versiones» |
| `expired` | «Tu Real-Debrid venció» |
| `no_premium` | «Tu cuenta no tiene Premium» |
| `bad_key` | «Vuelve a conectar Real-Debrid» |
| `refused` | «Real-Debrid no lo dejó bajar» |
| `needs_stremio` | «Necesita Stremio abierto» (solo la TV) |
| `addons_offline` | «No pude conectar con tus complementos» |
| `no_addons` | «No tienes complementos prendidos» |
| `not_in_rd` | «Real-Debrid todavía no lo tiene» |
| `nobody_has_it` | «Nadie lo tiene todavía en internet» |

El texto exacto es el de `vocabulario.json` (si cambia ahí, cambia en las dos apps y aquí no hay que tocar nada): la
invariante 9 lo revisa.

## Las invariantes (en todos los escenarios)

En el iPhone, `RDScenarioTests.testInvariantsHoldInEveryScenario`:

1. La ficha y «Versión» no se contradicen: lo que la ficha ofrece existe en la lista con la misma etiqueta, y la recomendada
   de la lista es la que pone «Ver».
2. Nada dice «al instante» si no arrancaría ya; nada dice «Real-Debrid no lo tiene» (ni «Pedirlo y avisarme») si hay una al
   instante en tu idioma.
3. Lo que pediste y ya está va primero y es lo que ponen «Ver» y «Ver ahora».
4. Nunca una de cine, un tráiler, en 3D, de otro año («¿Otro título?») o de otra temporada («¿Otro episodio?») como
   recomendada u ofrecida (si hay otra).
5. Todo problema tiene su salida: sin «Ver» que funcione, la causa trae su botón.
6. Títulos: en español si existe; el original si su idioma original es el de la app.
7. La misma versión (torrent) nunca sale dos veces en «Versión» con dos promesas: al instante en un lado y por pedir en otro
   («Hay que pedirlas» incluida). Una dual sale en sus dos filas, igual en las dos.
8. «Ver ahora» de un pedido listo pone exactamente ese torrent (su huella o su `ready_source`), nunca «la mejor».
9. La causa dice exactamente el texto de `vocabulario.json › causas` (más su `cause_arg`).

## Preguntas abiertas (decisiones de producto, sin inventar)

Las de Fernando, sin construir:

- **FQ1 · Quieres latino y solo el castellano está al instante** (`05`). Hoy: «Ver · 🇪🇸 · 1080p» y no se ofrece pedir la
  latina. Recomendación: dejar «Ver» en castellano (arranca ya) y poner al lado «Pedirla en latino», como hoy «Verlo en
  inglés al instante» va al lado de «Pedirlo y avisarme».
- **FQ2 · Una que Real-Debrid rechazó** (`18`, `29`) sigue en «Versión» como «por pedir» y recomendada, sin decirlo.
  Recomendación: marcarla «Real-Debrid no la dejó bajar» y no recomendarla.
- **FQ3 · Un nombre que no menciona el título** (`10`: «Farsante» es «Phony» en España; `27`: «Dexter Resurreccion»): hoy solo
  baja (−500) y en tu idioma le gana a otro idioma, con «¿Otro título?» en la tarjeta. Recomendación: dejarlo así y sumar a
  los nombres del título los de TMDB en tu idioma (ya van con clave).
- **FQ4 · Una película que aún no se estrena** (`14`): «Avisarme cuando aparezca» revisa 14 días; si sale en seis semanas, se
  acaba antes. Recomendación: revisar hasta su estreno más 14 días.
- **FQ5 · Lo que la TV pidió con otra cuenta y ya está** (`21`): no se ve en el iPhone (ese enlace no existe en tu cuenta).
  Recomendación: decirlo en la ficha («Lo tiene la TV con otra cuenta · Ver en la TV»).

Nuevas, de los casos de la TV:

- **N1 · Al instante solo hay «español» sin decir cuál y quieres latino** (`26`): hoy «Ver · español · 4K» y no se ofrece
  pedir la latina. Es FQ1 con una versión que tal vez sí es latina. Recomendación: la misma respuesta que FQ1.
- **N2 · El paquete que bajas sale «↓ Por pedir» en «Versión»** (`24`): la ficha dice «Bajando · 40 %», pero su tarjeta no.
  Recomendación: la tarjeta dice «Bajando · 40 %» y tocarla abre el pedido (no lo vuelve a pedir).
- **N3 · «Muchas descargas activas» nadie lo reintenta solo** (`28`): el contrato dice «se reintenta más tarde», pero ninguna
  app lo hace; hoy se ofrece pedirlo otra vez a mano. Recomendación: en el siguiente vistazo, si ya hay lugar
  (`activeCount`), pedirlo una vez solo y avisar.
