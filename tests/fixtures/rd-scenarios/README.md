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
  pidió la TV; el 33, tu orden de idiomas con inglés y castellano al instante; el 34 y el 35, «Muchas descargas activas» en el
  siguiente vistazo (N3-A); del 36 al 38, los códigos de error de Real-Debrid que cambian de causa con la tabla única
  (A15, `design/realdebrid-errors.json`: 36 y 23 son «Muchas descargas activas», 28 rechaza la versión).
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
| `app` | Tus preferencias tal cual: `language` (`es-MX`, el idioma de la app), `audio` (`es`), `spanish` (`es-419` latino, `es-ES` castellano o `""`), `languages` («Tus idiomas», ver abajo), `quality` (`1080p`) y, si importa, `device` (lo que aguanta el aparato, N5-A, ver abajo; sin él, sin límites). |
| `title` | Lo que abres: `kind` (`movie`/`series`), `id` (el del título) y `video_id` (el episodio; en una película, el mismo id). |
| `tmdb` | Lo que contesta TMDB y usan las dos apps, o `null` (sin clave de TMDB): `find` (la respuesta de `/find/<imdb>`), `detail` (la ficha en `language=es-MX`: `title`/`name`, `original_title`/`original_name`, `original_language`, `origin_country`, `overview`), `translations` (si hace falta) y, en una serie, `season` (si hace falta). `source`: de dónde salió. |
| `cinemeta` | El archivo del `meta` de Cinemeta. Con un id de Kitsu, `kitsu` es el `meta` del complemento Anime Kitsu y `cinemeta` el de su IMDb. |
| `torrentio` | `file` (lo capturado sin Real-Debrid), `captured`, `url`; `status`: `ok`, `down` (HTTP 503: caído o bloqueado) o `rd_error` (en lugar de versiones, una sola: `{"name": "[RD error] Torrentio", "url": ".../videos/failed_access_v2.mp4"}`); `options`: `only_instant` (`debridoptions=nodownloadlinks`) y `languages_first` (`language=latino,spanish…`, tu plan B); `next`: lo capturado del siguiente episodio, si el escenario lo usa. |
| `addons` | Lo prendido en tu lista de complementos: `torrentio`, `kitsu`, `opensubtitles` (solo subtítulos). Sin `torrentio`, tu lista está armada sin nada que dé versiones. |
| `rd` | Tu Real-Debrid (ver abajo). |
| `act` | Lo que haces antes de mirar: `"request"` = tocas «Pedir a la nube» una vez (y Real-Debrid contesta lo que diga `rd.error`); `"request_and_check"` = además, el siguiente vistazo a tus pedidos (N3-A: con `rd.slots` y `rd.retry_error`). Sin `act`, solo abres la ficha. |

### Tu orden de idiomas (`app.languages`)

Fernando, 3 nov: **latino → el idioma original de la obra («natal») → inglés → castellano**, el orden por omisión con latino
(es-MX): `["es-419", "original", "en", "es-ES"]`. `original` es un renglón: el idioma original de cada título (japonés en un
anime, inglés en «Dune», castellano en «Mar adentro»). Tus «Idiomas primero» de Torrentio se suman al final, sin repetir.
El español que no dice cuál (`es`: «Spanish», 🇪🇸 sin decir latino ni castellano) va **justo después del latino y antes
del original** (acordado con la TV, 3 nov: es español y muchas veces sí es latino); la fila «Español (no dice cuál)» va en ese
mismo lugar. Escenario `26`.

Los pesos exactos del idioma (lo demás de la puntuación no cambia), con latino:

| Idioma de la versión | Puntos |
| --- | --- |
| Latino (`es-419`) | lo que vale su prueba: 340 comprobado, 300 nombre / sitio / original, 260 supuesto, 60 «tal vez» |
| Español que no dice cuál (`es`) | lo mismo − 100 (200 si lo dice el nombre) |
| Renglón *n* de tu orden (0 = original, 1 = inglés, 2 = castellano, luego los de Torrentio) | −300 − 40·*n* + (su prueba − 300) |
| Fuera de tu orden | −1600 |

Una versión con varios idiomas vale lo de su mejor idioma. Cómo pesa (las dos apps igual): el tuyo arriba; cada renglón de tu orden debajo, en su orden, **a 600 o más del tuyo** (más
que lo que baja un nombre que no dice el título, −500: en tu idioma le sigue ganando, FQ3-A) y **a menos de 1400** (lo que
separa arrancar al instante, +1000, de tener que pedirla, −400): la que arranca ya en tu orden le gana a la tuya por pedir
(FQ1-A). Un idioma fuera de tu orden pesa más que arrancar al instante. Las filas de «Versión» van en ese mismo orden.

### `rd`

| Llave | Qué es |
| --- | --- |
| `key` | Si la app tiene tu clave de Real-Debrid. |
| `instant` | Las huellas que tu Real-Debrid ya tiene (las que Torrentio llama «[RD+]»). |
| `account` | `GET /user`: `id`, `premium` (bool), `expires` (ISO o `null`) y `problem`: `null`, `expired` (venció), `no_premium` (gratis) o `bad_key` (la clave ya no sirve: `/user` contesta 401, `error_code` 8). Las mismas tres causas que `DEBRID_CAUSES` de la TV. |
| `torrents` | Los de tu cuenta, como `GET /torrents` y `GET /torrents/info/<id>`: `id`, `hash`, `status`, `progress`, `seeders` (si no viene: 3 bajando, 0 si no), `files`, `links`; `unrestrict` (solo de las pruebas): enlace → lo que da `POST /unrestrict/link`. |
| `book` | La libreta de pedidos: entradas del contrato (`design/addons-contract.json` › `requests`), con sus horas (`since`, `updated`, `progress_at`) relativas a `now`. |
| `error` | Lo que contesta `POST /torrents/addMagnet` al pedir (`{code, http, name}`: el `error_code`, el HTTP y el nombre de Real-Debrid), o `null` (lo acepta: `{"id": "RNEW"}`). |
| `slots` | Con `act: "request_and_check"`: lo que contesta `GET /torrents/activeCount` en el siguiente vistazo (`{active, limit}`: `nb` y `limit`). |
| `retry_error` | Con `act: "request_and_check"`: lo que contesta `addMagnet` al volver a pedirlo solo (como `error`; `null`, lo acepta). |

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
| `primary` | El botón principal: `play` («Ver»), `request` («Pedir a la nube»), `requested` (ya pedido y en camino: «En cola», «Bajando en la nube · 42 %»…), `play_on_tv` («Ver en la TV»: tu TV lo tiene listo con otra cuenta, FQ5-A) o `fix` (un problema con su salida en `fix`). |
| `cause`, `cause_arg` | La causa que se ve (la clave de la tabla de abajo) y lo que cambia en su texto (`"el viernes 18 de diciembre"`, `"42 %"`), o `null`. Con `request`, la causa es `not_in_rd` (su renglón). |
| `fix` | La salida de cada problema: `renew` («Renovar»), `settings` («Ajustes»), `retry` («Reintentar»), `other_version` («Probar otra versión» / «Elegir otra versión»), `request` («Pedir a la nube») o `notify` («Avisarme cuando aparezca»); `null` si no hay problema. |
| `offer` | Lo que pediría «Pedir a la nube»: `{hash, language, res}`, o `null`. |
| `request_aside` | Al lado de «Ver», «Pedir a la nube en latino» (FQ1-A): «Ver» arranca ya en otro idioma de tu orden y el tuyo existe pero hay que pedirlo (solo si su nombre o su sitio dicen tu idioma, sin «¿Otro título?» ni rechazada). `{hash, language, res}`, o `null`. |
| `instant_aside` | «Verlo en X al instante»: `{hash, language, res}`, o `null`. |
| `recommended` | Lo que pone «Ver»: `{hash, file, language, res}` (`file`: su `fileIdx`), o `null`. |
| `rows` | Las tarjetas de arriba de «Versión», en orden: `{code, hash, res, state, recommended, other}`. `code` es la fila (`es-419`, `es-ES`, `es` = «Español (no dice cuál)», `en`, `ja`…); una dual sale en sus dos filas. `state`: `instant`, `requested_ready` («Al instante · la pediste»), `requested_pending` (la pediste o un paquete tuyo la trae y sigue en camino: «Bajando · 40 %», «En cola»…; tocarla abre el pedido, nunca lo pide otra vez; nunca va en «Hay que pedirlas», N2-A), `to_request` («↓ Por pedir»), `refused` («Real-Debrid no lo dejó bajar», FQ2-A: nunca la recomendada ni la ofrecida, y no va en «Hay que pedirlas») o `direct`. `other`: marcada «¿Otro título?» / «¿Otro episodio?». |
| `to_request` | «Hay que pedirlas · tardan»: `{code, hash, res}`. |
| `hidden` | Cuántas se esconden (de cine, tráileres). |
| `play_now` | Lo que pone «Ver ahora» del aviso de listo (el reproductor sin versión elegida): la huella, `"ready_source"` (el enlace de tu Real-Debrid de un pedido listo que Torrentio no lista) o `null`. |
| `request` | El pedido de tu cuenta que trae este video (el anotado o el paquete que lo trae): `{hash, state, percent, stuck, auto_retry}` (`state` del contrato; `stuck`: 24 h sin avanzar; `auto_retry`: «Muchas descargas activas» que todavía se va a volver a pedir solo, N3-A), o `null`. |
| `plays_poorly` | N5-A: la versión de un idioma que va antes en tu orden y no ganó «Ver» porque en este aparato no se ve bien: `{hash, language, res, why, gb}` (`why`: `heavy` pesa demasiado, con `gb` redondeado; `format`, un formato que el motor no abre), o `null`. |
| `other_account` | Lo que otra cuenta (la TV con la suya) pidió de este video: en camino o listo (`ready`, FQ5-A). `{state}`, o `null`. |
| `next_episode` | En una serie: el siguiente episodio (`video_id`) y si un pedido tuyo ya lo trae (`request`: su huella; `ready`). |
| `notify_until` | Con «Avisarme cuando aparezca»: el último día que se revisa (ISO): su estreno más 14 días o, si ya salió, 14 desde `now` (FQ4-A). |

### Las causas, en el orden de `design/vocabulario.json › causas`

| Clave | Texto |
| --- | --- |
| `downloading` | «Bajando en la nube · » + `cause_arg` |
| `unreleased` | «Aún no se estrena · sale » + `cause_arg` (el día de estreno de Cinemeta, dicho en UTC: es un día, no una hora) |
| `cannot_search` | «No puedo buscar versiones» |
| `expired` | «Tu Real-Debrid venció» |
| `no_premium` | «Tu cuenta no tiene Premium» |
| `bad_key` | «Vuelve a conectar Real-Debrid» |
| `refused` | «Real-Debrid no lo dejó bajar» |
| `addons_offline` | «No pude conectar con tus complementos» |
| `no_addons` | «No tienes complementos prendidos» |
| `not_in_rd` | «Todavía no está en la nube» |
| `nobody_has_it` | «Nadie lo tiene todavía en internet» |

El texto exacto es el de `vocabulario.json` (si cambia ahí, cambia en las dos apps y aquí no hay que tocar nada): la
invariante 9 lo revisa.

## Las invariantes (en todos los escenarios)

En el iPhone, `RDScenarioTests.testInvariantsHoldInEveryScenario` (la 4 cuenta también lo rechazado, FQ2-A):

1. La ficha y «Versión» no se contradicen: lo que la ficha ofrece existe en la lista con la misma etiqueta, y la recomendada
   de la lista es la que pone «Ver».
2. Nada dice «al instante» si no arrancaría ya; nada dice «Todavía no está en la nube» (ni «Pedir a la nube») si hay una al
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

## Lo que eran preguntas abiertas (decididas)

Fernando, 3 nov: «todo con tus sugerencias». Las dos apps lo construyen; los `expected` ya lo dicen.

- **FQ1-A · Tu idioma no está al instante y otro de tu orden sí** (`05`, `26`, `33`): «Ver» es la mejor que arranca ya según
  tu orden («Ver · 🇪🇸 · 1080p» en `05`, inglés en `33`) y al lado, «Pedir a la nube en latino» (`request_aside`).
- **FQ2-A · Lo que Real-Debrid rechazó** (`18`, `29`): «Real-Debrid no lo dejó bajar» en «Versión» (`state: refused`); nunca
  la recomendada ni la ofrecida; tampoco en «Hay que pedirlas».
- **FQ3-A · Un nombre que no menciona el título** (`10`, `27`): sin cambios: solo baja (−500) y en tu idioma le gana a otro.
- **FQ4-A · Una película por estrenarse** (`14`): «Avisarme cuando aparezca» revisa hasta el estreno más 14 días
  («Reviso una vez al día, hasta el 1 de enero»; `notify_until`).
- **FQ5-A · Lo que tu TV pidió con otra cuenta y ya está** (`21`): «Lo tiene tu TV con otra cuenta», con «Ver en la TV» (manda
  el título y el episodio, nunca el enlace) y aparte «Pedir a la nube aquí».

### Tus idiomas (`app.languages`, N4-A)

Fernando, 4 nov: «asegúrate que sea fácil cambiar tus idiomas preferidos, que esté claro en ajustes». «Tus idiomas» es **una
sola lista en Ajustes** (en el iPhone, Ajustes › Idiomas y subtítulos › Tus idiomas; en la TV, Ajustes › Ver › Tus idiomas),
en orden, con `original` («Idioma original») como un renglón que se mueve; por omisión con latino: `["es-419", "original",
"en", "es-ES"]`. El primero es tu idioma: `original` nunca queda primero (si quedaría, el siguiente sube). Es la única fuente:
la puntuación (los pesos de arriba: el primero es «el tuyo», los demás son los renglones de tu orden), el plan B del
reproductor (las pistas de audio en ese orden; `original` = el idioma original de la versión) y los «Idiomas primero» de
Torrentio (`language=` sale de la lista sin `original` ni inglés: `es-419` → `latino`, `es-ES` y `es` → `spanish`). Lo que ya
tenías (tu audio, latino o castellano, y los «Idiomas primero» de Torrentio, al final y sin repetir) se migra una vez.

### Lo que aquí se ve bien (`app.device`, N5-A)

Fernando, 4 nov (N5-A): si la mejor versión según tu orden **no se ve bien en este aparato**, gana «Ver» la que sí, y la ficha
dice por qué en una línea («La de inglés pesa 64 GB y aquí no se ve bien»). La regla es la misma en las dos apps; cada una pone
lo que aguanta su aparato:

| Llave de `app.device` | Qué es | iPhone, iPad y Mac |
| --- | --- | --- |
| `max_gb` | Lo más pesado que se ve bien, en GB, por resolución (`"4K"`, `"1440p"`, `"1080p"`; `""` las demás), de una película | 60 · 40 · 40 · 20 |
| `episode_share` | Un episodio: esta parte de lo de una película | 0.3 |
| `cannot_decode` | Lo que el motor no abre (etiquetas: `AV1`, `3D`, `DV`…) | nada (AetherEngine abre HEVC, HDR10, Dolby Vision y Atmos) |

Una versión que no se ve bien pierde **−900** (con «ver», no al descargar): más que lo que separa tu idioma del último renglón de
tu orden (unos 850) y menos que un idioma fuera de tu orden (−1600) y que arrancar al instante contra pedirla (1400). Así la que
se ve bien gana dentro de tu orden, pero una que arranca ya le sigue ganando a una que hay que pedir. Lo demás de la
puntuación no cambia (−150 por pesada y −200 por solo Dolby Vision siguen). La línea sale cuando la mejor del idioma que va
antes en tu orden (la que arranca igual que «Ver», sin cine, tráiler, 3D, otro título u otro episodio) es justo la que no se ve
bien; si esa se ve bien, perdió por otra cosa y no se dice nada (`plays_poorly`). Sin `app.device`, el escenario no pone
límites. Escenario `05`.

## Lo que eran preguntas abiertas de la TV (decididas el 4 nov)

Fernando, 4 nov: «ve con tus sugerencias [N2-A, N3-A, N4-A, N5-A]»
(https://claude.ai/artifact/Hebg83bMjNgXtRf1AveTMx).

- **N2-A · El paquete que bajas en «Versión»** (`24`, `30`): su tarjeta dice «Bajando · 40 %» (`requested_pending`) y tocarla
  abre el pedido, nunca lo vuelve a pedir.
- **N3-A · «Muchas descargas activas»** (`28`, `34`, `35`): «Muchas descargas activas · Lo vuelvo a pedir cuando se libere un
  lugar» con «Pedir a la nube». En el siguiente vistazo, si ya hay lugar (`activeCount`: menos activos que tu máximo), el
  aparato que lo pidió lo vuelve a pedir solo, **una vez** (`auto_retry` pasa a `false`); si Real-Debrid vuelve a decir 21,
  queda «Muchas descargas activas · Cancela otra descarga o pídelo otra vez más tarde» y «Pedir a la nube» a mano.
- **N4-A · «Idioma original» en Ajustes**: «Tus idiomas», arriba.
- **N5-A · Lo que no se ve bien aquí** (`05`): la regla de arriba.
