# Desacoplar Stremio en el iPhone: la app se vale sola (propuesta)

Fecha: 29 oct 2026. Alcance: **solo la app de iPhone/iPad/Mac** (`ios/`). La consola (TV) no cambia.
Estado: propuesta para decidir; **no se implementa todavía**.

## 1. Qué se pide, en una frase

Que la app de iPhone funcione completa sin Stremio: los complementos (add-ons) y Real-Debrid se manejan
dentro de la app, con una guía al abrirla por primera vez; **Trakt** es el que sincroniza el avance, lo visto y Mi lista
entre aparatos y con la nube; Stremio queda como importación opcional.

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
5. **Sincronizar (opcional).** «Conecta Trakt para que tu avance, lo visto y Mi lista te sigan en la TV, el iPad y
   la Mac». Se explica como lo que es: la copia en la nube, no un requisito. Debajo, discreto: «¿Vienes de Stremio?
   Trae lo tuyo una vez».

Después de la guía, cambia Ajustes:

- **Cuentas** se divide en: *Real-Debrid* (estado, días que quedan, fecha de vencimiento, «Renovar» que abre la web,
  avisos a 14 y 3 días y el día que vence), *Trakt* (la sincronización: conectada / no, última
  sincronización), *Stremio* (solo «Importar» avance, Mi lista y complementos, una vez) y *Tu Orbital* como hoy.
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
| La TV | Nada cambia en esta etapa. | Para que siga viendo el avance del iPhone, la consola tiene que leer Trakt como fuente principal (ver corte A). |

## 4. La propuesta técnica (para la sesión que lo implemente)

Tres cortes, en este orden. Cada uno deja la app funcionando y se puede entregar solo.

### Corte A · Lo tuyo vive en el teléfono; Trakt lo lleva a la nube

*Actualizado el 29 oct: Fernando decidió que el sincronizador entre dispositivos sea **Trakt**, no Stremio.*

**Qué es «lo tuyo».** Tres cosas, y cada una tiene su lugar en Trakt:

| Lo tuyo | En el teléfono | En Trakt | Ya existe en `Trakt.swift` |
|---|---|---|---|
| **Avance** (dónde te quedaste) | segundos exactos y duración | `/sync/playback` (en porcentaje) vía `scrobble` start/pause/stop | Sí: `playback`, `scrobble` |
| **Visto** (✓ por película o episodio) | marca por título y episodio | `/sync/history` | Sí: `history`, `addToHistory`, `watchedIDs` |
| **Mi lista** (lo que guardaste) | lista local | `/sync/watchlist` | Sí: `watchlist`, `setWatchlist` |

**Cómo conviven el teléfono y Trakt.** El teléfono es la verdad para la pantalla; Trakt es la copia en la nube que
comparten tus aparatos.

```
 Tú tocas algo                 Al abrir la app, al volver de segundo plano
      │                        o al jalar para actualizar
      ▼                                     │
 ┌──────────────┐  cola de salida   ┌──────┴───────┐
 │ LocalLibrary │ ────────────────► │    Trakt     │ ◄── la TV, el iPad, la Mac
 │ (el teléfono)│ ◄──────────────── │   (la nube)  │     escriben lo mismo
 └──────────────┘  solo lo que      └──────────────┘
   la pantalla      cambió
   lee de aquí      (last_activities)
```

1. **Escribir: primero el teléfono, luego Trakt.** Pausar, terminar, marcar visto o guardar se escribe al instante
   en `LocalLibrary` (la pantalla responde sin red) y se encola para Trakt. Las colas ya existen
   (`TraktOutbox`, `PendingWork`); se juntan en una sola.
2. **Leer: solo lo que cambió.** Al abrir, se pide `/sync/last_activities` (una llamada pequeña con la hora del último
   cambio de cada cosa). Si el avance cambió desde la última vez, se baja `/sync/playback`; si cambió lo visto,
   el historial desde esa hora; si cambió la watchlist, la watchlist. Si nada cambió, no se baja nada.
3. **Fusionar, una regla por cosa:**
   - *Avance*: gana el más reciente por título (`paused_at` de Trakt contra la hora local). Si gana el local, se
     usan los segundos exactos del teléfono; si gana Trakt, se convierte el porcentaje a segundos con la duración.
   - *Visto*: se suma. Lo que está visto en cualquier lado queda visto. Desmarcar es un acto explícito que se manda
     a Trakt (`/sync/history/remove`).
   - *Mi lista*: espejo de la watchlist de Trakt; agregar y quitar viajan por la cola.
4. **Sin conexión.** Todo funciona y se acumula. Al volver la red, antes de mandar un avance viejo se compara con
   Trakt: si Trakt tiene uno más nuevo (lo viste en la TV mientras tanto), el viejo se descarta. Trakt no deja fechar
   un scrobble en el pasado, así que esta comparación es la que evita retroceder tu avance.
5. **Sin Trakt.** La app funciona completa en un solo aparato. Al conectar Trakt, lo local se sube una vez.

**Stremio** queda como **importación única** («Traer mi avance, lo visto y Mi lista de Stremio»), opcional, para
quien viene de ahí. Ya no se escribe en la cuenta de Stremio desde el iPhone.

**Lo que hay que resolver antes de implementar:**

- **La TV.** Hoy la consola lee el avance de Stremio y usa Trakt de respaldo. Para que el iPhone y la TV se sigan
  entendiendo solo por Trakt, la consola tiene que leer `/sync/playback` como fuente principal (o el iPhone sigue
  escribiendo también en Stremio mientras tanto). Es un cambio en la consola, fuera de este alcance, pero es
  requisito para no perder la continuidad TV ↔ iPhone.
- **Cuenta gratuita de Trakt.** Tiene límites (entre ellos, de apps conectadas; la de Stremio ya ocupa una). Hay que
  confirmar con tu cuenta qué cabe antes de depender de ella.
- **Anime con ids de Kitsu.** Trakt no los reconoce: esos títulos se quedan solo en el teléfono.
- **Precisión.** Trakt guarda el avance en porcentaje con decimales; en una película de 2 h eso es del orden de
  segundos, suficiente. El teléfono guarda los segundos exactos para lo suyo.
- **Ritmo.** Trakt limita las escrituras a una por segundo. El scrobble actual (al iniciar, pausar, saltar y cerrar)
  queda muy por debajo.

Cambios en código: `LocalLibrary` (actor nuevo, archivo en `AppFiles`); `WatchService` lee y escribe ahí y deja de
depender de `StremioAPI`; `ResumePoint.latest` compara local contra Trakt en vez de Stremio contra Trakt;
`SaveDestination` pasa a «Mi lista local + watchlist de Trakt si está conectado»; `RootView` deja de exigir sesión;
`StremioAPI` + `StremioLibrary` se quedan solo para la importación.

Pruebas nuevas: fusión de avance (local más nuevo, Trakt más nuevo, empate), visto que se suma, desmarcar que viaja,
avance viejo descartado al volver la red, arranque sin ninguna cuenta, importación de Stremio.

### Corte B · Los complementos y Real-Debrid se manejan dentro de la app

**El problema de hoy, en simple.** Para tener fuentes, alguien entra a la web de Torrentio, pega su clave de
Real-Debrid, y Torrentio le da una URL larga con la clave escondida adentro. Esa URL se instala en la cuenta de
Stremio, y el iPhone la lee de ahí. Consecuencias:

- Sin Stremio no hay fuentes.
- La app no sabe que tienes Real-Debrid ni cuánto te queda. Si vence, solo ves «no hay fuentes», sin explicación.
- Cambiar de clave es ir a otra web, reconfigurar y volver a instalar.

**Lo que propongo: dos cosas en Ajustes, y la app une las dos.**

```
 ┌───────────────────────┐      ┌────────────────────────────┐
 │  Tu Real-Debrid       │      │  Tus complementos          │
 │  clave (una vez)      │─────►│  ☑ Torrentio   (usa tu RD) │
 │  fernando · Premium   │ la   │  ☑ Comet       (usa tu RD) │
 │  quedan 143 días      │ app  │  ☐ OpenSubtitles           │
 │  vence 21 mar 2027    │ mete │  + Agregar                 │
 │  [Renovar]            │ la   └─────────────┬──────────────┘
 └───────────────────────┘ clave              │ al tocar «Ver»
                                              ▼
                        cada complemento, en tu orden, busca versiones
                        → Real-Debrid las entrega → el reproductor
```

1. **Tu Real-Debrid.** Pegas la clave una vez (sale de real-debrid.com/apitoken). La app la comprueba en el momento
   con la API de Real-Debrid (`/rest/1.0/user`, solo lectura) y muestra usuario, si es Premium, días que quedan y
   fecha de vencimiento. Avisa a 14 días, a 3 días y el día que vence. Botón «Renovar» que abre la web. Si vence,
   al tocar «Ver» dice «Tu Real-Debrid venció hace 2 días» en vez de «no hay fuentes».
2. **Tus complementos.** Viven en el teléfono, no en una cuenta. Los recomendados vienen armados: la app construye
   la misma URL que te daría la web de Torrentio, con tu clave, sin que la teclees. Puedes prender y apagar cada uno,
   ordenarlos (cuál se pregunta primero), agregar uno pegando su URL o escaneando un QR, e importar una vez los que
   tengas en Stremio. Cada uno dice qué aporta (fuentes, catálogos, subtítulos) y si usa tu Real-Debrid.
3. **Cambiar la clave** la cambia en todos los complementos recomendados de una vez.

Lo que pasa al tocar «Ver» **no cambia**: la app pregunta a los complementos, el complemento habla con Real-Debrid
y devuelve el enlace. Solo cambia de dónde sale la lista y que la app ya sabe el estado de tu cuenta.

**Por qué un módulo aparte (`OrbitalAddons`).** Un target nuevo en `ios/OrbitalCore/Package.swift` que no conoce a
Stremio ni a Trakt. Así se prueba solo, no se rompe si cambia una cuenta y sirve igual para una futura app de
Apple TV. Adentro:

- `InstalledAddon { id, nombre, recursos, encendido, orden, origen (recomendado · pegado · importado), usaDebrid }`.
  Lo no secreto en `KeyValueStore`; la URL completa en el llavero (`SecretKey.addon(id)`), como ya se hace con las
  descargas.
- `AddonCatalog`: los recomendados como **plantilla** (Torrentio:
  `https://torrentio.strem.fun/realdebrid={CLAVE}/manifest.json`, con calidad e idioma como opciones). La URL se
  arma al vuelo con la clave del llavero.
- `DebridProvider` (protocolo) con `RealDebrid` primero → `DebridStatus { usuario, esPremium, díasQueQuedan,
  vence }`, guardado un día y refrescado al abrir Ajustes. AllDebrid, Premiumize o TorBox caben después sin tocar lo demás.
- `AddonRegistry` (hoy en `Addons.swift`) se queda, pero lee la lista local en orden y respeta el apagado; su lectura
  de la cuenta de Stremio pasa a la importación.
- Las etiquetas `[RD+]` de las fuentes se siguen leyendo igual (las manda el complemento); «Ya está en tu
  Real-Debrid» solo se enseña si tienes Real-Debrid configurado.

Pruebas: plantilla con la clave inyectada y tapada en bitácoras (`redact`), orden y apagado respetados, lectura de
`/user` con cuenta Premium, gratuita, vencida y clave inválida, cálculo de días, avisos programados una sola vez,
cambio de clave que regenera las URLs. La demo finge `api.real-debrid.com` como ya finge `api.strem.io`.

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
| La TV y el iPhone dejan de compartir el avance | La consola lee `/sync/playback` de Trakt antes de quitar la escritura a Stremio desde el iPhone; hasta entonces, el iPhone sigue escribiendo también en Stremio |
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
| A · Lo tuyo en el teléfono + Trakt como sincronizador | Entrar sin cuenta; avance y Mi lista en el teléfono; migración invisible | Grande (el corazón de `WatchService`, `HomeModel`, `TitleModel`, `RootView`) |
| B · `OrbitalAddons` + Real-Debrid | Complementos locales con orden y apagado; plantillas con la clave; días restantes y avisos | Medio |
| C · Guía + Ajustes nuevos | Onboarding de 5 pasos; secciones Complementos, Real-Debrid y Stremio; barrido de textos | Medio, casi todo interfaz |

Se pueden entregar como tres PR independientes en ese orden. B se puede adelantar en paralelo con A porque no se
tocan (B vive en el paquete nuevo).

Cuando decidas los cuatro puntos del §6, el siguiente paso es el spec del corte A con la skill `orquesta`.
