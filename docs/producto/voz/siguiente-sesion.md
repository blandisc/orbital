# Voz en el iPhone: traspaso para publicar el canvas (29 oct 2026)

## Qué falta
Publicar `docs/producto/voz/maquetas-iphone.html` (esta rama, `claude/voz-maquetas`) como canvas de Claude Design
(Artifact tipo «Design») para que Fernando decida la fase 2 de voz. La sesión de la Mac que lo dibujó no tenía Artifact.

## Pedido original
Lo mandó la sesión «Rediseño completo de comandos de voz» (Legion Go, `session_01NHGzZJVnscJuBYkyf3EUpF`) a pedido de
Fernando: solo maquetas, sin tocar código de la app ni instalar nada. Al terminar, contestarle con `send_message` con el link
del canvas y las decisiones.

## Fuentes
- Propuesta publicada: https://claude.ai/artifact/1U4zr6e56DqqTGh1sWBh9J (secciones 04 ciclo, 05 comandos, 06 dónde
  hablarle, 08 impacto en el iPhone). **No se leyó**: compárala con las láminas y ajusta lo que no cuadre.
- Rama `claude/voz-replanteo`: `docs/voz.md` (diagnóstico y fase 2) y `alexa/commands.json` (`core` = las diez frases).
- Código real: `ios/App/Sources/Screens/RemoteSheet.swift`, `Design/Remote.swift` (VoiceCommandBar, VoiceChoices),
  `Screens/VoiceGuideView.swift`, `Platform/OrbitalIntents.swift`; tokens en `design/tokens.json`.

## Las 8 láminas (hoy y propuesta, cada una con su nota)
1. Hoja corta: micrófono grande y 3 chips por contexto (serie / TV en vivo / navegando).
2. Escuchando: transcripción grande en vivo.
3. Respuesta: «Poniendo The Office · T4 E3», «Entendí: …», «Otro» y «Elegir episodio».
4. Varias coincidencias con póster («¿Cuál Dune?», «Ninguna · escribirlo»).
5. Error con el tramo que falló (en casa / túnel) y «Probar otra vez».
6. Guía: Lo esencial (10) arriba, Dónde hablarle compacto, Por tema plegado.
7. Siri: de 29 órdenes ×6 moldes a 8 + prender + títulos; lo demás con «Habla con Orbital».
8. iPad/Mac: panel lateral con el mismo micrófono; mantener ␣ en la Mac.

Dibujadas fieles al código (no son capturas: compilar tomaba más de 2 min). Modo oscuro, español de México, frases entre «».

## Decisiones para Fernando
1. ¿Micrófono grande con chips en la hoja corta (~120 pt más alta)? Recomendado: sí.
2. ¿El chip manda la frase o solo es ejemplo? Recomendado: la manda.
3. Frases por contexto, ¿fijas o aprendidas? Recomendado: fijas.
4. Sin nada sonando, ¿hoja corta con voz o estirada con pad como hoy? Recomendado: corta con voz.
5. ¿«Otro» + «Elegir episodio» o solo «Otro»? Y los episodios, ¿en la TV o en el teléfono?
6. Error de conexión: ¿dibujo del camino o solo la frase?
7. Siri recortada: ¿cuál de las que se pierden («salta la intro», «baja el volumen», «canal siguiente», «en latino»…) se queda?
8. Mac: ¿mantener ␣ para hablar?

## Reglas
No tocar la Orbital real (nada de POST a 127.0.0.1:8710 ni al túnel). No cambiar código de la app en esta tarea.
