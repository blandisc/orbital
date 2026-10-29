# Canvas «Voz en el iPhone · maquetas»

Fuente del canvas de Claude Design https://claude.ai/artifact/VTbt76HyzGywz1hj1iRmRM (29 oct 2026).

- Una fila por lámina: el «hoy» (captura real del simulador Orbital QA, modo demo: `-demo -demo-tv-now -demo-open remote|remote-full|remote-idle|voice-guide`) junto a la propuesta, dibujada encima de la misma captura, y una nota con lo que cambia y la decisión.
- `capturas/`: las capturas reales que usa el canvas (subidas como assets; los `.dc.html` las nombran por su `/_blob/…`).
- Frases y respuestas alineadas con la consola en `claude/voz-replanteo` (9a71ef06): «pon Dune» pone la más popular y dice «Si no es esa, di «otro»», «busca Dune» pregunta, los chips de cada momento son los del segundo renglón de la tele.

## Contrato con la consola para el iPhone (rama `claude/voz-pistas`, cdf08a89; aún no en `main`)

- **La guía por voz:** «qué puedo decir», «ayuda», «muéstrame la guía» → la respuesta de `POST /api/voice` trae `"guide": true`. Con `"source": "iphone"` la tele no abre su guía; la abre el iPhone. Desde Alexa o la tele se abre la de la tele.
- **Las pistas:** con `"source": "iphone"`, cada respuesta trae `"hints": [tres frases]`. `GET /api/voice/hints` (mismo token, también por el túnel) devuelve `{"moment": "series"|"movie"|"live"|"home", "hints": [...]}` para la pista antes de hablar.
  - serie: «pausa», «siguiente episodio», «pon subtítulos»
  - película: «pausa», «pon subtítulos», «sube el volumen»
  - TV en vivo: «pon el canal ADN 40», «sube el volumen», «cierra el video»
  - nada puesto: «pon The Office», «sigue viendo», «qué sale hoy»
- Consola vieja: no trae `hints` y la ruta da 404 → el iPhone usa esas mismas frases, fijas.
