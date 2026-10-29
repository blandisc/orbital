# Desacoplar Stremio · traspaso para los detalles (29 oct 2026, noche)

El trabajo pesado ya está en `main`: cortes A, B, C y D en el iPhone, corte E en la consola y Rotten Tomatoes en Para ti.
Lo dejó la sesión de la nube «revisión del plan» antes de archivarse; las dos sesiones de la Mac ya se archivaron.
El traspaso anterior (el de antes de construir) sigue en la historia de git de este archivo.

## Dónde está todo

| Qué | Dónde |
|---|---|
| Qué se hizo en cada corte y qué falta | `docs/producto/desacoplar-stremio/avance.md` |
| El flujo completo con 31 capturas reales (Canvas) | https://claude.ai/artifact/H5Vobbrwuw76ugoexVvYmr · `docs/producto/desacoplar-stremio/flujo/index.html` |
| Las capturas originales y su `flujo.json` (qué hace cada botón) | `docs/producto/desacoplar-stremio/capturas/flujo/` (se sacan con `FlowCaptureUITests`, `TEST_RUNNER_SHOTS=<carpeta>`) |
| La revisión del plan (inventario de 43 lugares con «Stremio», Trakt como sincronizador, Rotten Tomatoes) | `revision-plan.md` y https://claude.ai/artifact/3N63HHhVNExc4tcDvJhpLb |
| La propuesta original | `docs/producto/desacoplar-stremio-iphone-2026-10-29.md` |

Commits clave: consola `dc8b330` (corte E: `orbital/trakt_sync.py`, reglas de escritura en `orbital/scrobble.py` `plan`),
`f1c1da8` (Rotten Tomatoes en la consola, `orbital/library/mdblist.py`); iPhone `7ad9052` (A), `9737482` (B), `750c2f4` (C),
`def0a53` (D), `4d2b625` (Rotten Tomatoes en el iPhone), `b6da508` (pruebas de la guía en SE, mini y Pro Max, capturas).

## Lo que pidió Fernando para esta sesión (29 oct, viendo el Canvas)

### 1. La app es standalone; Orbital se prende en Ajustes

La app se va a compartir: para casi todos va a ser una app sola, sin consola. Fernando:

- **Quitar de la guía todo lo de la TV**: el paso «Tu TV» (pantalla 13 del Canvas; `Onboarding/OnboardingFinish.swift`
  `OnboardingTV`), la pieza «Tu Orbital en la TV · Opcional» de «Cómo funciona» (`OnboardingIntro.swift` L23–36) y «TV · No
  conectada» de «Todo listo» (`OnboardingFinish.swift` L46–49). El texto de Trakt «…para que la TV, el iPad y la Mac sepan
  lo mismo» (`OnboardingTrakt.swift` L20) pasa a hablar de tus aparatos sin nombrar la TV. Bienvenida ya dice «Tus
  películas y series en tu bolsillo.»: no poner «en tu TV» en ningún copy de la guía.
- **Un interruptor en Ajustes que prende toda la funcionalidad de Orbital** (hoy `Services.allowsOrbital` =
  `ThisDevice.talksToOrbital` = «no es Mac», `DeviceInfo.swift` L43; el usuario no lo decide). Apagado por defecto. Al
  prenderlo: **primero sincronizar** (emparejar con la consola: escanear el QR **dentro de la app** y «Conectar a mano»),
  **luego un mini tutorial** («mira, lo puedes hacer con el control…»: control remoto, voz, ver en la TV, la bandeja «Desde la
  TV», el acompañante de juegos). Debe poder apagarse y quedar desacoplado otra vez.
- Con el interruptor apagado no se ve nada de Orbital. Hoy se ven aunque no haya consola (todo depende solo de
  `allowsOrbital`): los atajos de Siri (`OrbitalIntents.swift` L242, contestan «Conecta tu Orbital…»), el control en el
  Centro de control (`OrbitalWidgets.swift` L12), Ajustes › «Voz y Siri» (`SettingsView.swift` L78), el botón «Ver en la TV»
  de la notificación de estrenos (`ReleaseNotifier.swift` L63, y si no hay consola sale un error), Ajustes › Cuentas › «Tu
  Orbital». La excepción: «descarga X» por Siri funciona sin consola; puede quedarse.
- Pieza nueva al catálogo para el tutorial (nada suelto, `docs/ios-proyeccion.md`); maquetas antes de construir si cambia
  mucho, con antes y después.

### 2. Análisis: de qué depende hoy el iPhone de la consola

Hecho en esta sesión (inventario completo con archivo y línea en el informe de abajo). Lo que importa para standalone:

| Qué | Hoy sin consola | Qué hacer |
|---|---|---|
| **Clave de TMDB** | No hay clave incluida: llega de la consola (`/api/companion`, `Services.swift` L257–283) o a mano en Ajustes › Avanzado. Sin ella se pierden fichas y títulos en español, la sinopsis en español, Estudios, Temporadas y Géneros, «Nuevo en tus plataformas», arte alto, sagas y la calificación TMDB | **Bloqueante.** Proponer a Fernando incluir una clave de la app (como el Client ID de Trakt: `project.yml` L60 → Info.plist) y dejar el campo de Ajustes como opción |
| **OneDrive (Mi media)** | No usa la consola, pero pide registrar una app propia en Microsoft Entra (`OneDriveSettings.swift` L21, «Usa la misma de la TV») | Bloqueante para un usuario normal: incluir un Id. de aplicación de la app, o esconder Mi media hasta configurarlo |
| Trakt | Funciona: Client ID incluido (PKCE), sesión propia | Quitar el texto viejo «Conecta tu Orbital y Trakt queda listo» (`SettingsView.swift` L364). **Defecto:** con consola y Trakt conectados la fila dice «Desde tu Orbital» y no se puede tocar (`SettingsView+Cuentas.swift` L16–17): no se puede desconectar Trakt |
| Para ti desde la consola | Ya apagado en producción (`forYouFromConsole = false`, `Services.swift` L66–69) | Nada |
| Al conectar la consola | `connectOrbital` **sobrescribe el país** (`Services.swift` L274–275); la clave de TMDB y el Client ID solo si faltan | Que el país también sea «solo si falta» |
| Ver en la TV, «Viendo en la TV», control, voz, bandeja, acompañante de juegos, audio y subtítulos por título | Se esconden con `orbital.isConfigured` o funcionan local | Pasan detrás del interruptor y entran al tutorial |

### 3. «Aprobadas por la crítica» (pantalla 30 del Canvas)

- El título se parte en dos renglones («Aproba-das por…») junto al sello: corregirlo (que el título no se parta; el sello
  cede espacio).
- El sello lleva **el ícono de Rotten Tomatoes** (el jitomate), no texto: «ROTTEN TOMATOES» y nunca «TRAKT» aunque las series
  vengan de una lista de Trakt. Traer el ícono como asset (es marca de Fandango; para la app de Fernando está bien) y
  agregarlo al catálogo como los logos de plataformas (`DSPlatformLogo`). Revisar lo mismo en la consola
  (`orbital/web/js/components/collection-card.js` `SourceBadge`) si se muestra ahí.

### 4. Lo que sigue pendiente de antes

- Complementos recomendados: solo Torrentio y OpenSubtitles; falta Comet (y probarlo con la cuenta de Fernando).
- Pruebas con cuentas reales: las hace Fernando (pausar en la TV y ver «Seguir viendo» en el iPhone, y al revés; MDBList).
- La fase 2 (comparar Trakt contra Stremio dos semanas) la hace Fernando a mano. No construirla.

## Reglas que siguen

- Ambiente: si la sesión corre en la nube, no hay Xcode. El iPhone se construye en la Mac (`~/code/orbital`, ambiente
  «Fers-MBP:orbital») con `create_session`; ya hay permiso de dispositivo de confianza para eso. La consola (Python) se
  prueba en la nube: `pip install` de `requirements-dev.lock` sin los paquetes `winrt` y `pywebview`; 10 pruebas fallan en
  Linux por ser de Windows (ya fallaban).
- Varias sesiones en el mismo checkout de la Mac: commit solo de tus rutas; nunca stash, reset ni `pull` con lo ajeno
  encima. Si el push choca: `git worktree add /tmp/wt origin/main`, `cherry-pick`, push, borra el worktree.
- No escribir en cuentas reales (Trakt, Stremio, Real-Debrid, MDBList) sin el OK directo de Fernando. Nunca teclas ni POST a
  la Orbital real (127.0.0.1:8710).
- Decisiones para Fernando como PM no técnico, con algo visual (Canvas) y antes y después en cada corrección.
- Las pruebas de la guía: `OnboardingUITests` en iPhone SE, 13 mini y 17 Pro Max; la demo recorre la guía sin red
  (`-demo -demo-first-run`; clave «BAD…» no reconocida, «FREE…» gratuita).

## Prompt para iniciar la siguiente sesión

```
Hola. Continúas «Desacoplar Stremio» de Orbital, ahora con los detalles: el trabajo grande ya está en main.

Antes de nada, lee:
1. docs/producto/desacoplar-stremio/siguiente-sesion.md (este traspaso: lo que pedí y el análisis de dependencias).
2. docs/producto/desacoplar-stremio/avance.md y el Canvas del flujo (https://claude.ai/artifact/H5Vobbrwuw76ugoexVvYmr).
3. CLAUDE.md y docs/ios-proyeccion.md.

Lo que quiero, en orden:
1. La app es standalone: quita todo lo de la TV de la guía, y en Ajustes pon un interruptor que prenda toda la
   funcionalidad de Orbital: primero sincronizar (con escanear el QR dentro de la app) y luego un mini tutorial. Apagado,
   no se ve nada de Orbital. Antes de construir, enséñame maquetas del interruptor, la sincronización y el tutorial.
2. Propónme qué hacer con la clave de TMDB y con OneDrive para que la app funcione sin la consola, y arregla los detalles
   del análisis (Trakt «Desde tu Orbital», el país que se sobrescribe, textos viejos).
3. «Aprobadas por la crítica»: que el título no se parta y que el sello sea el ícono de Rotten Tomatoes.
4. Agrega Comet a los complementos recomendados.
Al final, capturas de antes y después en un Canvas.
```
