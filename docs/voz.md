# La voz en Orbital: replanteo (octubre de 2026)

Qué hay, por qué «no funciona en ningún lado», qué se decidió y qué se hizo. La guía de frases vive en
`alexa/commands.json`; esto es el **porqué** y el plan.

## 1. Diagnóstico (29 de octubre)

Lo que se comprobó en la consola, sin tocar la tele:

| Pieza | Estado | Cómo se vio |
|---|---|---|
| Intérprete (`orbital/voice.py`) | Sano: 377 pruebas en verde, 118 frases de la guía llegan a un comando | `pytest tests/test_voice*.py tests/test_alexa*.py` |
| Puerto público 8711 (solo voz, con token) | Arriba; sin token contesta 401 | `curl 127.0.0.1:8711/api/ping` |
| Túnel (Tailscale Funnel) | **Responde desde fuera** (401 sin token, que es lo correcto) | petición desde un servidor ajeno a la casa |
| `voz.log` (cada orden que llega) | **23 órdenes en total; la última el 21 de octubre.** Ocho días sin una sola | `%LOCALAPPDATA%\orbital\voz.log` |
| Dictado en Buscar (Edge, Web Speech) | El servicio de voz de Edge contesta `network` en esta máquina | Edge sin ventana con micrófono falso |
| Micrófono de la Legion Go | Existe (Realtek), pero la consola está junto a la tele, a metros de quien habla | hardware + uso real |

**Conclusión.** La consola entiende y hace; lo que falla ocurre **antes** de que la orden llegue, y hoy nada lo
deja ver. Las cuatro entradas fallan por motivos distintos y ninguna avisa:

- **Alexa.** El Echo tiene que transcribir «mi consola» y abrir la skill. Si no lo hace, Alexa intenta hacerlo
  sola («quiero ver X» se va al Roku) y Orbital no se entera. Las pruebas escritas en el simulador no ven esto;
  solo la voz real y el historial de Alexa.
- **Siri.** Solo reconoce frases registradas (App Shortcuts): «Dile a Orbital que …» con una orden de la lista o un
  título conocido. Fuera de eso contesta «Orbital no puede hacer eso» y la consola tampoco se entera.
- **Micrófono del iPhone.** Es el único camino que depende de nosotros de punta a punta, pero está escondido
  (estirar el control hacia arriba) y, fuera de casa, pasa por el túnel, que a veces se traba aunque diga «on».
- **Dictar en la tele.** Promete lo que no puede cumplir: el micrófono está lejos y el servicio de Edge no responde.

Y el problema de uso que se suma: **118 frases** en una lista plana. Nadie sabe «qué pedirle», y la tele solo
enseña la guía si Alexa está configurada.

## 2. Principios del replanteo

1. **Cada entrada tiene un papel; la tele no es micrófono.** La tele **enseña y confirma** (qué puedes decir aquí,
   qué oyó, qué hizo). El **iPhone es el micrófono principal** (está en tu mano y lo controlamos de punta a
   punta). **Alexa** es manos libres para lo esencial. **Siri**, atajos cortos.
2. **Diez frases esenciales, el resto por tema.** `core` en `commands.json`: lo único que se enseña de entrada,
   en los tres lugares. Todo lo demás sigue entendiéndose, pero vive en «Por tema».
3. **Nada falla en silencio.** Cada orden que llega deja rastro (`voz.log`, ya existía) y la tele lo enseña:
   **«Qué ha oído la consola»** dice cuándo llegó la última orden de cada lado y las últimas con lo que se dijo,
   lo que se entendió y lo que contestó. Regla para el usuario: *si lo que acabas de decir no aparece ahí, no
   llegó a Orbital; la falla está en Alexa, Siri o la conexión del iPhone.* Esa sola frase ubica el 90 % de los
   «no funciona».
4. **Las frases se dicen igual en todas partes** (ya era así: `voice.py` es el único intérprete). Cambiar la guía
   es cambiar un JSON y una prueba comprueba que cada frase llega a un comando.

## 3. Lo hecho en esta vuelta (rama `claude/voz-replanteo`)

- `GET /api/voice/status`: por dónde llegó la última orden (Alexa, iPhone/Siri, aquí), las últimas 12 con lo
  dicho, lo entendido y la respuesta, si Alexa está configurada y la dirección del túnel. Sobrevive al reinicio
  (lee `voz.log`, `voice_log.last_seen`).
- Tele, ☰ › **Lo que puedes decir**: «Lo esencial» (las diez), «Dónde hablarle» (iPhone primero, Alexa, Siri, cada
  uno con «Hace 5 min» / «Hace 8 días» / «Nunca»), «Por tema», **«Qué ha oído la consola»** y «Si no funciona»
  (que, con dos días sin una orden, abre diciendo que la falla está antes de la consola y por dónde empezar).
- Dictar en Buscar: si Edge falla dice la verdad (`network`, sin micrófono, sin permiso) y señala el micrófono del
  iPhone (`keyboard.dictationProblem`).
- Guía: `core` con las diez frases, copiada al iPhone (`AlexaCommands.json`; la app ignora las claves que no
  conoce hasta que la use).

## 3b. Fase 2, el ciclo (hecho en la misma rama)

- **Poner implica prender.** Toda orden que pone algo (película, serie, episodio, seguir viendo, canal, juego, «otro»)
  prende la tele y la pone en la entrada de Orbital en segundo plano (`WAKES` en `voice.py`). Si ya está en esa entrada,
  la Roku no recibe nada (`roku.RokuTv.turn_on` mira la app activa).
- **Una serie se pone.** Sin progreso en Stremio, su primer episodio que ya salió (sin especiales); con progreso, donde
  ibas, como antes. Sin la lista de episodios (Cinemeta caído), su ficha para elegir.
- **Ante la duda, la más popular.** «pon Dune» pone la primera, dice «Si no es esa, di otro» y el iPhone recibe todas
  para tocar. «busca Dune» sí pregunta (pediste buscar).
- **«otro»**: la siguiente de la misma búsqueda (30 min); en la TV en vivo, el siguiente canal.
- **«siguiente» / «anterior»** con un canal al aire cambian de canal.
- **«prende la tele»** prende la tele (antes abría la TV en vivo; los canales son «pon la tele en vivo» o «pon los
  canales»). **«apaga la tele»** guarda dónde ibas, cierra el video y apaga la tele; «apaga» a secas solo cierra el video.
- **Avisos con segundo renglón:** lo que puedes decir ahora («Di «pausa» o «siguiente episodio»»), qué oyó cuando abrió
  algo parecido («Entendí «jades». Si no era, di «cierra el juego»»), y lo no entendido también se ve en la tele.
- **Alexa:** el modelo (`alexa/interaction_model.es-MX.json`) suma `TurnOffTvIntent`, `OtherIntent` y «prende la tele»
  en `OpenOrbitalIntent`. **Hay que pegarlo otra vez en la consola de Alexa** (y la skill, por la ayuda nueva).
- Pruebas: `tests/test_voice_ciclo.py` y `tests/test_roku.py`.

## 4. Lo que sigue (por orden)

### Fase 2, iPhone (Mac): el micrófono como primera opción
- Botón de micrófono **a la vista** en la hoja del control (hoy hay que estirarla) y en la ficha de un título
  («Decir»), con las tres frases esenciales como chips según el contexto (viendo algo: «pausa», «siguiente
  episodio», «pon subtítulos»; en Inicio: «sigue viendo», «pon la tele», «qué sale hoy»).
- La respuesta siempre con «Entendí: …» y, si la consola no contestó, **qué conexión falló** (misma red o túnel) con
  el botón «Probar la conexión» que ya existe en Ajustes.
- La guía del iPhone lee `core` (las diez) arriba de todo; «Por tema» plegado.

### Fase 2, Alexa: menos promesa, más fiable
- La skill se queda como está (el modelo es correcto), pero la guía y la tele enseñan **una sola forma** de
  pedir: «Alexa, pídele a mi consola que …». Nada de «abre mi consola» y luego hablar (el Echo corta la sesión y
  confunde).
- Rutina sugerida en la app Alexa para lo esencial sin la fórmula: «Alexa, a ver la tele» → «pídele a mi consola
  que ponga la tele».
- Comprobar con voz real y el historial (amazon.com.mx/alexa-privacy): si el Echo no transcribe «mi consola» en
  tres de tres intentos, cambiar el nombre de invocación por uno de dos palabras sonoras (p. ej. «la pantalla»).

### Fase 2, Siri: solo lo esencial
- Dejar las frases de `OrbitalCommand` en las diez esenciales más los títulos de «Seguir viendo». Menos frases
  registradas = más aciertos de Siri.

### Fase 3, tele
- Al llegar una orden, la barra ya pulsa «Te escuché»; sumar **qué entendió** en el aviso cuando falló («No
  entendí “pon jades”») con la frase esencial más parecida.
- La guía siempre alcanzable (hoy solo si Alexa está configurada): ☰ › Lo que puedes decir, aunque el único
  camino sea el iPhone.

## 5. Cómo probar que funciona (lo que no se puede desde la consola)

1. iPhone en la misma red: app › control › «Dile a Orbital» › «pon la tele». En la tele: ☰ › Lo que puedes decir ›
   Qué ha oído la consola debe mostrar «pon la tele · iPhone o Siri · Hace un momento».
2. iPhone con datos (fuera del Wi-Fi): lo mismo. Si dice «Tu Orbital no contesta», es el túnel: en la consola,
   `tailscale funnel --https=443 off` y `tailscale funnel --bg http://127.0.0.1:8711`.
3. Alexa: «Alexa, pídele a mi consola que ponga la tele». Si Alexa contesta otra cosa, abrir el historial de voz y
   leer qué transcribió; si no dice «mi consola», es el nombre de invocación.
4. Siri: «Oye Siri, pausa en Orbital» y «Oye Siri, habla con Orbital» › «pon la tele».

Cada prueba deja (o no deja) su línea en «Qué ha oído la consola»: esa es la evidencia.
