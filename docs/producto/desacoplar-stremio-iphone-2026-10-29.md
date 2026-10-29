# Desacoplar Stremio en el iPhone: la app se vale sola (propuesta)

Fecha: 29 oct 2026. Alcance: **solo la app de iPhone/iPad/Mac** (`ios/`). La consola (TV) no cambia.
Estado: propuesta para decidir; **no se implementa todavía**.

## 1. Qué se pide, en una frase

Que la app de iPhone funcione completa sin Stremio: los complementos (add-ons) y Real-Debrid se manejan
dentro de la app, con una guía al abrirla por primera vez; la cuenta de Stremio queda **solo para sincronizar**
(avance, visto, Mi lista) con la TV, igual que hoy Trakt es opcional.

## 2. Cómo está hoy (medido en `main` @ 58464353)

| Tema | Hoy | Dónde |
|---|---|---|
| Entrar | Sin cuenta de Stremio no se pasa de la pantalla de entrada. Es la única puerta. | `App/Sources/Screens/RootView.swift` L60–64, `LoginView.swift` |
| Avance, visto, Mi lista | Viven **solo** en la cuenta de Stremio. Sin ella no hay «Seguir viendo» ni ✓. Lo único local es la cola de pendientes sin conexión. | `OrbitalCore/Watch.swift` (`WatchService`), `StremioAPI.swift` |
| Lista de complementos | La de la cuenta de Stremio (solo lectura) + las URLs que pegues en Ajustes › Avanzado. No se puede ordenar, apagar ni quitar los de la cuenta. | `OrbitalCore/Addons.swift` (`AddonRegistry`), `SettingsView.swift` L324–336 |
| Real-Debrid | La app **nunca** habla con Real-Debrid. La clave va escondida en la URL del complemento (Torrentio `…/realdebrid=CLAVE/…`). No sabe si tienes cuenta, ni cuánto le queda. «Real-Debrid» en pantalla se deduce de la etiqueta `[RD+]` que manda el complemento. | `Streams.swift` L268, `docs/ios-companera.md` L351 |
| Onboarding | No existe. Splash → entrada de Stremio. | — |
| Trakt | Ya es una capa aparte y opcional: buen molde para lo que debe ser Stremio. | `OrbitalCore/Trakt.swift`, `SaveDestination.swift` |

El acoplamiento de fondo: **la cuenta de Stremio es a la vez la llave de entrada, la base de datos y el catálogo de
complementos**. Hay que separar esas tres cosas.

## 3. La propuesta, para quien usa la app

Al abrir Orbital por primera vez ves una guía de 5 pasos, cada uno con «Saltar»:

1. **Qué es Orbital.** Películas y series, tu TV y tu bolsillo. Una pantalla.
2. **Real-Debrid, la pieza que paga.** Qué es (un servicio que convierte los enlaces de la red en un archivo que se
   reproduce al instante, sin esperar ni compartir nada desde tu teléfono), por qué hace falta, cuánto cuesta
   aproximadamente y que se paga por adelantado y **no se renueva solo**. Botón «Crear cuenta» (abre real-debrid.com),
   botón «Ya tengo cuenta → pegar mi clave» (abre real-debrid.com/apitoken, con la instrucción «copia el texto largo y
   vuelve»). Al pegarla, la app la verifica en el momento y te dice: «Hola, fernando · Premium · te quedan 143 días».
3. **Complementos (de dónde salen las fuentes).** Explicado en una línea: son «buscadores» de enlaces. La app trae
   los recomendados listos (Torrentio primero) y les pone tu clave de Real-Debrid sola. «Activar los recomendados»
   o «Lo configuro después».
4. **Tu TV (opcional).** Escanea el QR de la consola. Ya existe (`orbital-ios://pair`).
5. **Sincronizar (opcional).** «¿Usas Stremio o Trakt? Conéctalos para que lo que ves aquí aparezca allá». Las dos
   se explican como lo que son: **respaldo y espejo**, no requisito. Aquí se avisa claro: *si quieres que la TV y el
   iPhone compartan el avance, conecta Stremio* (la consola sigue usando esa cuenta).

Después de la guía, cambia Ajustes:

- **Cuentas** se divide en: *Real-Debrid* (estado, días que quedan, fecha de vencimiento, «Renovar» que abre la web,
  avisos a 14 y 3 días y el día que vence), *Stremio* (sincronización: conectada / no; última sincronización; «Importar
  mis complementos de Stremio» una vez), *Trakt* y *Tu Orbital* como hoy.
- **Complementos** sube de «Avanzado» a sección propia: lista ordenable, interruptor por complemento, «Agregar» con
  tres caminos (recomendados, pegar URL, escanear QR), y en cada uno qué aporta (fuentes, catálogos, subtítulos) y si
  está usando tu Real-Debrid. Los que vinieron de Stremio se marcan «Importado».
- La guía se puede volver a abrir desde Ajustes › «Cómo funciona Orbital».

Y en toda la app desaparece la palabra «Stremio» salvo en la sección de sincronización: «Mi lista» es **tu** lista
(se guarda en el teléfono y, si conectaste Stremio, también allá); «Lo más popular en Stremio» pasa a «Lo más popular».

### Qué gana y qué pierde

| | Gana | Pierde o cuesta |
|---|---|---|
| Quien usa la app | Entra sin cuenta de terceros. Sabe cuándo pagar Real-Debrid antes de que falle un viernes en la noche. Entiende qué es cada pieza. | Un paso más la primera vez (la guía). |
| El producto | El iPhone deja de depender de una API no oficial para existir. Si Stremio cambia, se rompe la sincronización, no la app. | Dos lugares donde vive el avance (teléfono y Stremio): hay que fusionar bien. |
| La TV | Nada cambia. | Si alguien no conecta Stremio en el iPhone, la TV no ve su avance. Se avisa en el paso 5. |

## 4. La propuesta técnica (para la sesión que lo implemente)

Tres cortes, en este orden. Cada uno deja la app funcionando y se puede entregar solo.

### Corte A · La biblioteca vive en el teléfono; Stremio es un sincronizador

Hoy `WatchService` lee y escribe `libraryItem` de Stremio en cada paso. Propuesta:

- Nuevo almacén local `LocalLibrary` (actor, archivo JSON o SwiftData en `AppFiles`; una entrada por título con
  `timeOffset`, `duration`, `watched` (el mismo bitfield), `inLibrary`, `removed`, `lastWatched`, `mtime`). Es la
  **fuente de verdad** del iPhone. `Watchable` se queda como modelo; deja de significar «ítem de Stremio».
- Protocolo `LibrarySync` con dos implementaciones: `StremioSync` (lo que hoy hace `StremioAPI` + `StremioLibrary`,
  movido a su archivo) y, más adelante, `TraktSync` (hoy Trakt ya hace `playback`/`history`; se formaliza).
  Operaciones: `pull() -> [Watchable]`, `push([Watchable])`, con regla de fusión **gana el `mtime` más nuevo por
  título** (es la regla que ya aplica `flushPending`, Watch.swift L362–389).
- `WatchService` escribe siempre en `LocalLibrary` y encola el `push` a los sincronizadores conectados. `PendingWork`
  se queda como cola de salida por sincronizador.
- `RootView` deja de bloquear: `SessionModel.State` ya no es la puerta; la app abre a `MainTabs` siempre. `LoginView`
  se convierte en la hoja «Conectar Stremio» dentro de Ajustes y del paso 5 de la guía.
- `HomeModel` sin Stremio: «Seguir viendo» y «Mi lista» salen de `LocalLibrary`; `sessionExpired` solo pinta un aviso
  en la sección de sincronización.

Migración: al actualizar, si hay `authKey` en el llavero, el primer `pull` llena `LocalLibrary` y nadie nota nada.

Pruebas que cambian: `WatchTests`, `ContinueReturnTests`, `ScreenModelsTests.testSignInStoresOnlyTheSessionKey`;
nuevas: fusión por `mtime`, arranque sin cuenta, migración.

### Corte B · Módulo `OrbitalAddons` y Real-Debrid como cuenta propia

Nuevo target del paquete `ios/OrbitalCore/Package.swift`: **`OrbitalAddons`**, sin `import` de nada de Stremio.

- `InstalledAddon { id, manifestURL, name, resources, enabled, order, origin (.recommended | .pasted | .importedFromStremio), debrid: DebridProvider? }`.
  Se guarda en `KeyValueStore` (lo no secreto) y la URL completa en el llavero (`SecretKey.addon(id)`), como ya se
  hace con las descargas.
- `AddonCatalog`: los recomendados con **plantilla** de URL. Torrentio: `https://torrentio.strem.fun/realdebrid={CLAVE}/manifest.json`
  (más opciones de calidad e idioma como parámetros de la plantilla). Comet y MediaFusion después, si hacen falta.
  La clave se inyecta al construir la URL, nunca se teclea.
- `AddonRegistry` se queda, pero su entrada es `[InstalledAddon]` local; `fromAccount` (Addons.swift L145–151) se
  vuelve `StremioSync.importAddons()` y solo corre cuando el usuario toca «Importar». No escribimos de regreso a la
  cuenta de Stremio (`addonCollectionSet`) en esta etapa: la cuenta es solo sincronización de biblioteca.
- `DebridProvider` (protocolo) con `RealDebrid` primero: `GET https://api.real-debrid.com/rest/1.0/user` con
  `Authorization: Bearer <clave>`; devuelve `type` (premium/free), `premium` (segundos restantes) y `expiration`.
  Se guarda en `SecretKey.realDebridToken`. `DebridStatus { username, isPremium, daysLeft, expiration }` con caché de
  un día y refresco al abrir Ajustes o la guía. (AllDebrid, Premiumize y TorBox encajan en el mismo protocolo; no se
  hacen ahora.)
- Avisos: reutilizar la sección «Avisos» (notificaciones locales que ya existen para estrenos) con tres fechas:
  14 días, 3 días y el día del vencimiento. Texto: «Tu Real-Debrid vence el 21 de marzo. Renuévalo para seguir viendo».
- `Streams.swift` sigue detectando `[RD+]` por nombre (es lo que manda el complemento), pero el texto «Ya está en tu
  Real-Debrid» solo se enseña si hay proveedor configurado; si no, «Listo para ver».

Pruebas: manifest de plantilla con clave inyectada y redactada en logs (`redact`), orden y apagado respetados por
`serving(resource:)`, parse de `/user` con cuenta premium, gratuita y clave inválida (401), cálculo de días, los tres
avisos programados una sola vez. Demo: `DemoHTTPClient` ya finge `api.strem.io`; se agrega `api.real-debrid.com`.

### Corte C · La guía (onboarding) y los Ajustes nuevos

- `OnboardingView` en `App/Sources/Screens/Onboarding/` (un archivo por paso para respetar el tope de 600 líneas),
  con `TabView(.page)` nativo, botón «Saltar» siempre visible y «Listo» al final. Bandera `hasSeenOnboarding` en
  `KeyValueStore`; la guía se reabre desde Ajustes. Piezas de `Design/` (`HeroCard` para la portada, `SettingsRow`,
  `CheckRow` para el estado de cada cuenta); nada nuevo suelto, como manda `docs/ios-proyeccion.md`.
- Paso Real-Debrid: `TextField` para la clave + «Pegar» del portapapeles + verificación en vivo con `DebridStatus`;
  enlaces con `Link` a `real-debrid.com` y `real-debrid.com/apitoken`.
- Paso Complementos: lista de recomendados con interruptores; «Activar» crea los `InstalledAddon` con la clave.
- `SettingsView`: nueva sección **Complementos** (ordenable con `.onMove`, `Toggle` por fila, menú «Agregar»), sección
  **Real-Debrid** (estado, días, fecha, «Renovar», «Cambiar clave», «Quitar»), **Stremio** como sincronización.
- Textos: barrido de «Stremio» en `ListsView`, `CollectionsView`, `SaveSheet` («Mi lista»), `Badges`, `HomeView`.
  `UserMessages` conserva las traducciones de errores de Stremio solo para la sección de sincronización.
- Pruebas de UI: `OnboardingUITests` (completar, saltar, reabrir) en iPhone SE, mini y Pro Max; `-demo-first-run`.

### Qué no cambia

- La consola sigue usando la cuenta de Stremio como eje (está fuera del alcance).
- Los ids de títulos (`tt…:S:E`, `kitsu:`) siguen en formato Stremio: es el formato de los complementos, no de la
  cuenta, y la TV lo usa.
- Infuse, descargas, reproductor, Trakt: igual. Las descargas ya guardan la URL de la fuente en el llavero.

## 5. Riesgos y cómo se acotan

| Riesgo | Cómo se acota |
|---|---|
| Fusión mal hecha entre teléfono y Stremio (se pierde un avance) | Regla única: gana el `mtime` más nuevo por título, probada con casos cruzados; el `pull` nunca borra lo local, solo lo marca `removed` si Stremio lo dice con fecha más nueva |
| Real-Debrid cambia su API o sus términos | Solo usamos `/user` (lectura); si falla, la app sigue sirviendo con la clave que ya está en las URLs. Nada se bloquea por no poder leer el estado |
| La clave de Real-Debrid queda en más lugares | Un solo secreto (`realDebridToken`) y las URLs se **derivan**; `redact` ya tapa la clave en pantalla y bitácoras. Cambiar la clave regenera las URLs de los recomendados |
| Alguien se queda sin Stremio y no entiende por qué la TV no ve su avance | Lo dice el paso 5 y la sección Stremio en Ajustes («La TV usa esta cuenta para ver tu avance») |
| Más pantallas = más mantenimiento | La guía reutiliza piezas del catálogo y sus textos viven en un solo archivo de vocabulario |

## 6. Decisiones que son tuyas

1. **¿La app abre sin ninguna cuenta?** Recomiendo **sí**: sin Real-Debrid se puede explorar y guardar; al tocar «Ver»
   se explica qué falta. La alternativa (exigir Real-Debrid para entrar) es más simple pero repite el problema de hoy
   con otro nombre.
2. **¿Escribimos los complementos de regreso a la cuenta de Stremio?** Recomiendo **no por ahora**: solo importar una
   vez. Escribir de regreso toca la colección completa (`addonCollectionSet`) y podría pisar lo que configuraste
   desde la TV. Se puede sumar después como «Enviar mis complementos a Stremio».
3. **¿Solo Real-Debrid o también AllDebrid, Premiumize y TorBox?** Recomiendo **solo Real-Debrid**, con el protocolo
   listo para los otros. Es el que usas y el que paga la gente que te rodea.
4. **¿La guía es obligatoria la primera vez?** Recomiendo **sí, con «Saltar» en cada paso** y reabrible desde Ajustes.
   Pasos 2 y 3 son los que evitan el «no me sale nada al darle Ver».

## 7. Orden y tamaño

| Corte | Qué entrega | Tamaño estimado |
|---|---|---|
| A · Biblioteca local + Stremio como sincronizador | Entrar sin cuenta; avance y Mi lista en el teléfono; migración invisible | Grande (el corazón de `WatchService`, `HomeModel`, `TitleModel`, `RootView`) |
| B · `OrbitalAddons` + Real-Debrid | Complementos locales con orden y apagado; plantillas con la clave; días restantes y avisos | Medio |
| C · Guía + Ajustes nuevos | Onboarding de 5 pasos; secciones Complementos, Real-Debrid y Stremio; barrido de textos | Medio, casi todo interfaz |

Se pueden entregar como tres PR independientes en ese orden. B se puede adelantar en paralelo con A porque no se
tocan (B vive en el paquete nuevo).

Cuando decidas los cuatro puntos del §6, el siguiente paso es el spec del corte A con la skill `orquesta`.
