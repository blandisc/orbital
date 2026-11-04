# Escenarios comunes de Real-Debrid (iPhone y TV)

Fernando, 3 nov 2026: «análisis de fondo… para que no encuentre yo más errores». Con «El viento tiene miedo» encontró cinco
fallas; estos escenarios buscan las siguientes antes que él, en muchos tipos de título, y hacen que **el iPhone y la TV
decidan lo mismo**. Cada app los corre con su código de verdad y compara con `esperado`.

- iPhone: `ios/OrbitalCore/Tests/OrbitalModelsTests/RDScenarioTests.swift` (y `RDScenarioRig.swift`, que arma cada uno).
- TV: la misma carpeta, con su propio arnés.

## Qué hay aquí

- `escenarios/NN-nombre.json`: uno por escenario (entrada y `esperado`).
- `torrentio/<video>.json`: lo que contestó Torrentio **sin Real-Debrid** el 3 nov 2026 (público, sin clave, solo lectura),
  tal cual. `https://torrentio.strem.fun/stream/<tipo>/<video>.json`.
- `cinemeta/<id>.json`: la ficha de Cinemeta (`kitsu_1.json`: la del complemento Anime Kitsu), tal cual, del mismo día.
- TMDB pide clave: lo suyo va escrito a mano en cada escenario (`titulo.tmdb`, con `fuente`). Nunca se usó una clave ni la
  cuenta de Fernando.

## La entrada

| Campo | Qué es |
| --- | --- |
| `titulo` | `tipo` (`movie`/`series`), `meta_id`, `video_id` (el episodio), `cinemeta` (archivo) y `tmdb` (o `null`: sin TMDB). |
| `titulo.tmdb` | `original_language`, `original_title`, `title_es_MX` (lo que da TMDB con `language=es-MX`, que **no traduce al mismo idioma**: a una mexicana le da el inglés), `overview_es_MX` y, si hace falta, `translations` (las de otros países del mismo idioma). |
| `torrentio` | El archivo capturado y su dirección. |
| `torrentio_estado` | `ok`; `sin_respuesta` (HTTP 503: caído o bloqueado); `rd_error` (en lugar de versiones, una sola: `{"name": "[RD error] Torrentio", "url": ".../videos/failed_access_v2.mp4"}`). |
| `torrentio_opciones` | `solo_al_instante` (`debridoptions=nodownloadlinks`) e `idiomas_primero` (`language=latino,spanish…`: tu plan B). |
| `real_debrid` | `clave` (si hay), `cuenta` (`id` y `estado`: `premium`, `vencida`, `gratis`), `al_instante` (las huellas que tu Real-Debrid tiene) y `torrents` (los de tu cuenta, como `GET /torrents/info/<id>`, con `unrestrict`: enlace → descarga). |
| `libreta` | Los pedidos, en el formato del contrato (`design/addons-contract.json` › `requests`: `hash`, `files`, `account`, `rd_id`, `video_ids`, `by`, `state`, `all_files`…). |
| `preferencias` | `audio`, `espanol` (`es-419` latino, `es-ES` castellano) y `calidad`. Idioma de la app: español. |

### Torrentio con tu Real-Debrid (la regla para las dos apps)

De lo capturado sin Real-Debrid se arma lo que Torrentio da con él:

- `name`: `"[RD+] Torrentio\n<calidad>"` si la huella está en `al_instante`; si no, `"[RD download] Torrentio\n<calidad>"`
  (la calidad es lo que venía después del salto de línea).
- `url`: `https://torrentio.strem.fun/resolve/realdebrid/<clave>/<huella>/null/<fileIdx>/<filename>`; sin `infoHash` ni
  `fileIdx` (como de verdad).
- Con `solo_al_instante`, solo las `[RD+]`.
- Sin `clave`: lo capturado tal cual (torrents sin enlace: el iPhone no los reproduce).
- Lo que existe para pedir (Torrentio sin Real-Debrid) es siempre lo capturado tal cual.

## Lo esperado

`esperado` dice lo que las dos apps deben decidir. Una llave que empieza con `_` es una nota. En un objeto solo cuentan las
llaves que trae; una lista va completa y en orden.

| Llave | Qué es |
| --- | --- |
| `titulo`, `logo` | El nombre de la ficha y si lleva el logo de metahub (en inglés; no si está hecha en tu idioma). |
| `video` | El video de «Ver». |
| `boton` | `ver`, `pedirlo_y_avisarme`, `pedido_en_camino`, `probar_otra_version`, `avisarme_cuando_aparezca`, `sale_el` o `sin_version` (la causa debajo y su salida al tocarlo). |
| `boton_version` | Lo que va debajo: con `ver`, «idioma · calidad · …»; con «Pedirlo y avisarme», su renglón. |
| `causa` | La de la tabla común (`design/vocabulario.json` › `causas`), en clave: `real_debrid_vencio`, `vuelve_a_conectar`, `complementos_no_contestan`, `aun_no_se_estrena`, `nadie_lo_tiene`… |
| `pedir` | Lo que pediría «Pedirlo y avisarme» (huella e idioma). |
| `al_instante_aparte` | «Verlo en X al instante»: la versión y su idioma. |
| `recomendada`, `recomendada_idioma` | Lo que pone «Ver» (huella y archivo) y en qué idioma suena. |
| `filas` | Las de arriba de «Versión», en orden: su idioma y, por calidad, la mejor con su `velocidad` (`al_instante`, `al_instante_la_pediste`, `por_pedir`, `directa`), si es la recomendada y si va marcada «¿Otro título?» / «¿Otro episodio?» (`otro_titulo`). |
| `hay_que_pedirlas` | «Hay que pedirlas · tardan»: idioma, calidad y huella. |
| `ver_ahora` | Lo que pone «Ver ahora» del aviso de listo (el reproductor sin versión elegida). |
| `escondidas` | Cuántas se esconden (de cine, tráileres). |

Las reglas que valen en **todos** (invariantes, en `RDScenarioTests.testInvariantsHoldInEveryScenario`):

1. La ficha y «Versión» no se contradicen: lo que la ficha ofrece existe en la lista con la misma etiqueta, y la recomendada
   de la lista es la que pone «Ver».
2. Nada dice «al instante» si no arrancaría ya; nada dice «Real-Debrid no lo tiene» (ni «Pedirlo y avisarme») si hay una al
   instante en tu idioma.
3. Lo que pediste y ya está va primero y es lo que ponen «Ver» y «Ver ahora».
4. Nunca una de cine, un tráiler, en 3D, de otro año («¿Otro título?») o de otra temporada («¿Otro episodio?») como
   recomendada u ofrecida (si hay otra).
5. Todo problema tiene su salida: sin «Ver» que funcione, la causa trae su botón.
6. Títulos: en español si existe; el original si su idioma original es el de la app.

## Preguntas abiertas (decisiones de producto, sin inventar)

1. **Quieres latino y solo el castellano está al instante** (`05`). Hoy: «Ver · 🇪🇸 · 1080p» y no se ofrece pedir la latina.
   Recomendación: dejar «Ver» en castellano (arranca ya) y poner al lado «Pedirla en latino», como hoy «Verlo en inglés al
   instante» va al lado de «Pedirlo y avisarme».
2. **Una que Real-Debrid rechazó** (`18`) sigue en «Versión» como «por pedir», sin decirlo. Recomendación: marcarla «Real-Debrid
   no la dejó bajar» y no recomendarla.
3. **Un nombre que no menciona el título** (`10`, «Farsante» es «Phony» en España): hoy solo baja (−500) y en tu idioma le
   gana a otro idioma. Recomendación: dejarlo así y sumar a los nombres del título los de TMDB en tu idioma (ya van con clave).
4. **Una película que aún no se estrena** (`14`): «Avisarme cuando aparezca» revisa 14 días; si sale en seis semanas, se acaba
   antes. Recomendación: revisar hasta su estreno más 14 días.
5. **Lo que la TV pidió con otra cuenta y ya está** (`21`): no se ve en el iPhone (ese enlace no existe en tu cuenta).
   Recomendación: decirlo en la ficha («Lo tiene la TV con otra cuenta · Ver en la TV»).
