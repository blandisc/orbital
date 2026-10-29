# Desacoplar Stremio en el iPhone: la app se vale sola (propuesta)

Fecha: 29 oct 2026 (tres rondas el mismo día). Alcance: **solo la app de iPhone/iPad/Mac** (`ios/`). La consola (TV)
no cambia, salvo un requisito para la fase 3.
Estado: propuesta para decidir; **no se implementa todavía**.

## 1. Qué se pide, en una frase

Que la app de iPhone funcione completa sin Stremio: los complementos (add-ons) y Real-Debrid se manejan
dentro de la app, con una guía al abrirla por primera vez; **Trakt** es el que sincroniza el avance, lo visto y Mi lista
entre aparatos y con la nube; Stremio sigue recibiendo una copia mientras
se prueba, y se suelta cuando la comparación sale bien.

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

*Actualizado el 29 oct con lo que decidió Fernando: el flujo inicial no pide Stremio para nada. Real-Debrid y
Trakt sí son necesarios. Stremio se ofrece al final, como opción.*

Maquetas de las 13 pantallas: [`desacoplar-stremio/maquetas.html`](desacoplar-stremio/maquetas.html) (y su captura en
PNG en la misma carpeta).

**El flujo de la primera vez:**

| # | Pantalla | ¿Se puede saltar? |
|---|---|---|
| 1 | Bienvenida | — |
| 2 | Cómo funciona: tres piezas (Real-Debrid, Trakt, tu TV) | — |
| 3 | Real-Debrid · qué es, cuánto cuesta, que no se renueva solo, «Ya tengo cuenta» o «Crear cuenta» | No |
| 4 | Real-Debrid · tu clave: abrir real-debrid.com/apitoken, copiar, pegar; la app la comprueba y dice «Premium · te quedan 143 días» | No |
| 5 | Real-Debrid · clave con problema (incompleta, o cuenta gratuita sin Premium) | — |
| 6 | Complementos: los recomendados ya armados con tu clave, con interruptores | Se puede seguir con los recomendados |
| 7 | Trakt · qué es y el código para trakt.tv/activate | No |
| 8 | Trakt · conectado, con cuánto se trajo | — |
| 9 | Tu TV · escanear el QR de la consola | Sí |
| 10 | Listo, con una tarjeta aparte: «¿Usas Stremio? Conéctalo» | Stremio, sí |

Stremio aparece **solo** en la pantalla 10 y en Ajustes. Mientras dure la prueba (ver §4, «Transición»), conectarlo
hace que lo que veas también se copie allá, para que la TV y la app de Stremio lo sigan viendo.

**Después de la guía, en Ajustes:**

- **Cuentas**: *Real-Debrid* (estado, días que quedan, vencimiento, «Renovar», avisos a 14 días, a 3 días y el día que
  vence); *Trakt · principal* (cuenta, última sincronización); *Stremio · respaldo* (conectar o no; «Lo que ves también
  se guarda ahí, como copia»); *Tu Orbital*.
- **Complementos** como sección propia: lista ordenable, interruptor por complemento, «Agregar» con tres caminos
  (recomendados, pegar dirección, escanear QR), y en cada uno qué aporta y si usa tu Real-Debrid. Los que vinieron de
  Stremio dicen «Importado de Stremio».
- La guía se reabre desde Ajustes › «Cómo funciona Orbital».

En toda la app «Stremio» desaparece salvo en Ajustes. «Mi lista» es tu watchlist de Trakt. Las listas públicas que
hoy dicen «de Stremio» cambian de fuente (§4, corte D).

### Qué gana y qué pierde

| | Gana | Pierde o cuesta |
|---|---|---|
| Quien usa la app | Entra sin cuenta de terceros. Sabe cuándo pagar Real-Debrid antes de que falle un viernes en la noche. Entiende qué es cada pieza. | Un paso más la primera vez (la guía). |
| El producto | El iPhone deja de depender de una API no oficial para existir. Si Stremio cambia, se rompe la sincronización, no la app. | Dos lugares donde vive el avance (teléfono y Stremio): hay que fusionar bien. |
| La TV | Nada cambia mientras Stremio recibe la copia. | Para soltar Stremio, la consola tiene que leer Trakt como principal (§4, «Transición»). |

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

**Stremio** sigue recibiendo una copia mientras se prueba (ver «Transición», abajo). Para quien no lo conecta,
no existe.

**Lo que hay que resolver antes de implementar:**

- **La TV.** Hoy la consola lee el avance de Stremio y usa Trakt de respaldo. Para que el iPhone y la TV se sigan
  entendiendo solo por Trakt, la consola tiene que leer `/sync/playback` como fuente principal (o el iPhone sigue
  escribiendo también en Stremio mientras tanto). Es un cambio en la consola, fuera de este alcance, pero es
  requisito para no perder la continuidad TV ↔ iPhone.
- **Cuenta gratuita de Trakt.** Tiene límites (entre ellos, de apps conectadas; la de Stremio ya ocupa una). Hay que
  confirmar con tu cuenta qué cabe antes de depender de ella.
- **Anime con ids de Kitsu.** Trakt no los reconoce: esos títulos se quedan solo en el teléfono.
- **Precisión.** Ver el estudio completo en §5.
- **Ritmo.** Trakt limita las escrituras a una por segundo. El scrobble actual (al iniciar, pausar, saltar y cerrar)
  queda muy por debajo.

Cambios en código: `LocalLibrary` (actor nuevo, archivo en `AppFiles`); `WatchService` lee y escribe ahí y deja de
depender de `StremioAPI`; `ResumePoint.latest` compara local contra Trakt en vez de Stremio contra Trakt;
`SaveDestination` pasa a «Mi lista local + watchlist de Trakt si está conectado»; `RootView` deja de exigir sesión;
`StremioAPI` + `StremioLibrary` se quedan solo para la importación.

Pruebas nuevas: fusión de avance (local más nuevo, Trakt más nuevo, empate), visto que se suma, desmarcar que viaja,
avance viejo descartado al volver la red, arranque sin ninguna cuenta, importación de Stremio.

### Transición: Trakt principal, Stremio de respaldo, y luego se suelta

*Decidido por Fernando el 29 oct.* No se desconecta Stremio de golpe. Tres fases:

| Fase | El iPhone lee de | El iPhone escribe en | Se termina cuando |
|---|---|---|---|
| **1 · Prueba** | Teléfono + Trakt | Teléfono → Trakt **y** Stremio (copia) | Pasan las pruebas de la fase 2 |
| **2 · Comparar** | Igual que la 1 | Igual que la 1, y anota cada vez que Trakt y Stremio no coinciden | Dos semanas de uso normal sin diferencias que importen (más de 30 s de avance, o un visto que falte) |
| **3 · Soltar** | Teléfono + Trakt | Teléfono → Trakt | — |

- **Qué pierdes en la fase 3 y no antes.** En las fases 1 y 2 no pierdes nada: Stremio sigue recibiendo todo. En la
  fase 3, la app de Stremio (la oficial) y la consola ya no ven lo que avances en el iPhone **salvo que la consola
  lea Trakt**. Por eso la fase 3 tiene un requisito fuera de este alcance: que la consola lea el avance de Trakt como
  principal.
- **La comparación de la fase 2** la hace la app sola, sin pantallas nuevas: cada vez que reanuda un título, apunta en
  la bitácora (la misma del reproductor) qué decía el teléfono, qué decía Trakt y qué decía Stremio. Un resumen en
  Ajustes › Avanzado dice «Trakt y Stremio coinciden en 97 de 100 títulos».
- **La copia a Stremio** es la escritura de hoy (`StremioLibrary.withProgress`), solo que deja de ser la principal:
  si Stremio falla, no se avisa ni se bloquea nada; se reintenta.
- **Sin Stremio conectado** (cualquiera que no sea Fernando) la app va directo a la fase 3.

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
  con `NavigationStack` (un paso empuja al siguiente; Real-Debrid y Trakt no dejan avanzar sin quedar conectados; solo la TV y Stremio tienen «Ahora no»). Bandera `hasSeenOnboarding` en
  `KeyValueStore`; la guía se reabre desde Ajustes. Piezas de `Design/` (`HeroCard` para la portada, `SettingsRow`,
  `CheckRow` para el estado de cada cuenta); nada nuevo suelto, como manda `docs/ios-proyeccion.md`.
- Paso Real-Debrid: `TextField` para la clave + «Pegar» del portapapeles + verificación en vivo con `DebridStatus`;
  enlaces con `Link` a `real-debrid.com` y `real-debrid.com/apitoken`.
- Paso Trakt: el enlace por código que ya existe en `SettingsModel` (L133–180), con el código grande y «Abrir Trakt».
- Paso Complementos: lista de recomendados con interruptores; «Activar» crea los `InstalledAddon` con la clave.
- `SettingsView`: nueva sección **Complementos** (ordenable con `.onMove`, `Toggle` por fila, menú «Agregar»), sección
  **Real-Debrid** (estado, días, fecha, «Renovar», «Cambiar clave», «Quitar»), **Trakt · principal** y **Stremio · respaldo** en Cuentas.
- Textos: barrido de «Stremio» en `ListsView`, `CollectionsView`, `SaveSheet` («Mi lista»), `Badges`, `HomeView`.
  `UserMessages` conserva las traducciones de errores de Stremio solo para la sección de sincronización.
- Pruebas de UI: `OnboardingUITests` (completar, clave mala, cuenta gratuita, saltar TV y Stremio, reabrir) en iPhone SE, mini y Pro Max; `-demo-first-run`.

### Corte D · Las listas públicas dejan de decir «Stremio»

Casi todo lo que hoy dice «de Stremio» **no** viene de tu cuenta: viene de **Cinemeta**, el catálogo público de
Stremio, que no pide cuenta. Funciona sin Stremio, pero lleva su nombre y su criterio de «popular». Como Trakt ya es
obligatorio, sus listas públicas siempre están disponibles.

| Dónde | Hoy | Propuesta |
|---|---|---|
| Buscar › «Lo más popular hoy» (`BrowseView.swift` L230–236) | Top de Cinemeta, «Lo que más se ve hoy en Stremio» | Trakt «En tendencia» (`trending`), películas y series alternadas: «Lo que más se ve hoy» |
| Buscar › lista completa (`PopularRoute`, `CatalogModel`) y géneros (`cinemeta.catalog(kind, genre:)`) | Cinemeta por género | Trakt `popular` y `trending` con filtro de género (Trakt lo admite con `genres=`). Con clave de TMDB, TMDB `discover` por género como alternativa |
| Inicio › Destacado sin Trakt (`HomeModel.swift` L242–252) | Cae a Cinemeta | Desaparece el caso: Trakt es obligatorio. Si Trakt no contesta, se queda la última copia guardada |
| Para ti › mosaico sin fuentes (`ParaTiModel.swift` L123, L333–356; `ParaTiView.swift` L30) | «Lo más popular en Stremio» | Trakt `trending`; el aviso «Conecta Trakt» desaparece |
| Para ti › Listas (`ListsView.swift` L35–61, L161–163, L412–437) | Grupo «Listas de Stremio» (catálogos de tus complementos y de Cinemeta) y estante «Lo más popular en Stremio» | «De tus complementos» para los catálogos de complementos; el de Cinemeta sale; el estante de respaldo pasa a Trakt |
| Colecciones (`CollectionsView.swift` L10, `Design/Collections.swift` L90) | «Listas de Stremio», color de Stremio | «De tus complementos» |
| Inicio › «Mi lista» (`HomeView.swift` L110) y Guardar (`SaveSheet`, `SaveDestination`) | Biblioteca de Stremio | Tu watchlist de Trakt |
| Buscar (`SearchModel.swift` L77–116) | Cinemeta primero; Trakt completa lo que falte | **Trakt primero** (ya está conectado), Cinemeta de respaldo si Trakt no contesta. Las fichas se siguen traduciendo con TMDB como hoy |
| Mensajes (`HomeView.swift` L45, `CatalogModel.swift` L41, `AppEnvironment+Titles.swift` L41, L58) | «Tu sesión de Stremio se cerró», «No pude leer el catálogo de Stremio», «No pude cambiar tu lista de Stremio» | Solo en Ajustes, y solo si conectaste Stremio. Los demás dicen qué pasó sin nombrar servicios |

**Lo que se queda con Cinemeta (a propósito).** Las fichas, las temporadas y episodios, la duración y el año siguen
saliendo de Cinemeta. Es público, no pide cuenta, y usa los mismos identificadores que entienden los complementos
(`tt…:2:5`). Cambiarlo por TMDB es otro proyecto grande, sin beneficio visible para quien usa la app. Si un día
Cinemeta falla, TMDB ya está como respaldo para la sinopsis.

**Costo de Trakt.** Las listas públicas de Trakt solo piden el identificador de la app, no gastan la sesión. Se
guardan unas horas, como hoy las de Cinemeta.

### Qué no cambia

- La consola sigue usando la cuenta de Stremio como eje (está fuera del alcance).
- Los ids de títulos (`tt…:S:E`, `kitsu:`) siguen en formato Stremio: es el formato de los complementos, no de la
  cuenta, y la TV lo usa.
- Infuse, descargas, reproductor, Trakt: igual. Las descargas ya guardan la URL de la fuente en el llavero.

## 5. Estudio de precisión: ¿Trakt guarda bien dónde te quedaste?

*Rehecho el 29 oct. El estudio anterior (commit 6dfea233, «Trakt: cada app con su sesión…») concluyó: retomar desde
lo más reciente entre Stremio y Trakt, pasar el porcentaje de Trakt a segundos con la duración del video y, en la
consola, retroceder 10 s. Eso sigue en pie. Lo nuevo es lo que cambia si Trakt pasa a ser el principal.*

### Lo que se encontró

**1. Trakt cambió su API y nuestro código no.** Desde finales de 2025, según el desarrollador de Infuse, Trakt quitó
el aviso de pausa (`/scrobble/pause`), y el aviso de cierre (`/scrobble/stop`) ahora pide un avance mínimo. Infuse
tuvo que corregirlo en su versión 8.3.5 (17 dic 2025), y en enero un usuario reportó que el problema regresó. La
app del iPhone (`Trakt.swift` L430, `ScrobbleAction.pause`) y la consola (`orbital/scrobble.py`) **siguen mandando
`pause`**. Si de verdad se quitó, hoy pausar no le dice nada a Trakt, y el avance a medias solo llega cuando cierras
el video. **No se pudo comprobar sin una cuenta real.** Es la primera prueba que hay que hacer (abajo), antes de
cualquier otra cosa.

**2. El redondeo no es el problema.** Trakt recibe el avance como número con decimales; no publica cuántos guarda.

| Si Trakt guarda… | Error en una película de 2 h | En un episodio de 45 min |
|---|---|---|
| 2 decimales (45.67 %) | menos de 1 s | menos de 1 s |
| 1 decimal | hasta 7 s | hasta 3 s |
| Entero (46 %) | hasta 72 s | hasta 27 s |

Con un entero, el error ya se nota. La prueba de abajo lo resuelve.

**3. Cuándo se guarda importa más que el redondeo.** Stremio recibe el avance cada 60 s. Trakt solo recibe avisos al
empezar, al saltar 30 s o más y al cerrar. Si el teléfono se apaga, la app se cierra a la fuerza o entra una llamada a
media película, Trakt se queda con el último aviso.

| Qué pasa | Teléfono (local) | Stremio hoy | Trakt hoy |
|---|---|---|---|
| Cierras el video | exacto | ≤ 60 s | exacto (al cerrar) |
| Pausas y te vas a la TV | exacto | ≤ 60 s | **depende del punto 1** |
| Batería muerta a los 40 min sin tocar nada | exacto | ≤ 60 s | **lo que había al empezar** |
| La app se va a segundo plano con el audio sonando | exacto | se guarda | no se avisa |

Con el teléfono como principal, en el **mismo** aparato nunca se pierde nada: lo local guarda cada pocos segundos.
La pérdida solo es entre aparatos, y solo en los casos marcados.

**4. El 80 % de Trakt marca visto demasiado pronto.** Trakt marca visto todo cierre por encima del 80 %. La app
considera visto al 90 % (como Stremio) o al empezar los créditos. En una película de 2 h, el 80 % deja **24 min** por
ver. En un episodio de 45 min, deja **9 min**. Si cierras ahí, Trakt lo marca visto y borra tu punto de reanudación.
Hoy no se nota porque manda Stremio. Con Trakt como principal, sí se notaría.

**5. Versiones distintas en cada aparato.** La TV y el iPhone pueden reproducir archivos distintos del mismo título.
El porcentaje aguanta mejor que los segundos cuando la diferencia es de velocidad. Ninguno de los dos sirve si es otra
edición.

| Diferencia | Ejemplo (2 h, vas en el minuto 72) | Con segundos | Con porcentaje |
|---|---|---|---|
| Unos segundos de logos | ±10 s | ±10 s | ±10 s |
| Versión europea (25 cuadros, 4 % más corta) | dura 115 min | 3 min adelante | exacto |
| Edición extendida (+20 min) | dura 140 min | depende de dónde está lo agregado | depende de dónde está lo agregado |

### Qué se propone

1. **Primero, probar con tu cuenta (unos 10 min, la sesión que implemente).** Mandar `pause` y ver si contesta 404.
   Mandar `stop` al 45.67 % y leer `/sync/playback` para saber los decimales. Mandar `stop` al 0.5 % y al 2 % para
   encontrar el mínimo. El resultado se apunta aquí.
2. **Dejar de usar `pause`.** Al pausar, al ir a segundo plano y al cerrar se manda `stop` con el avance real, y al
   seguir, `start`. Trakt queda al día cada vez que sueltas el teléfono.
3. **Un aviso de respaldo cada 5 minutos** mientras reproduces: `stop` seguido de `start` al momento. En el peor caso
   se pierden 5 min entre aparatos. Trakt permite una escritura por segundo, así que sobra margen. El costo es que
   «Viendo ahora» en Trakt puede parpadear un instante. Si resulta molesto, se sube a 10 min.
4. **Proteger el punto de reanudación del 80 %.** Si cierras entre el 80 % y el final real (créditos, o el 90 %), a
   Trakt se le manda 79.9 % y no se marca visto. El teléfono guarda el segundo exacto. Otro aparato retomaría como
   mucho 12 min antes en una película de 2 h, o 4 min antes en un episodio. Al llegar a los créditos, se manda el
   avance real y queda visto.
5. **Retroceder 10 s al retomar en otro aparato**, como ya hace la consola. Cubre el redondeo y los logos.
6. **Retomar desde el porcentaje**, con la duración del archivo que vas a reproducir. Así la versión europea cae
   exacta.

## 5b. Riesgos y cómo se acotan

| Riesgo | Cómo se acota |
|---|---|
| Fusión mal hecha entre teléfono y Trakt (se pierde un avance) | Regla única: gana el más reciente por título, probada con casos cruzados; lo visto se suma; la fase 2 compara contra Stremio antes de soltarlo |
| Real-Debrid cambia su API o sus términos | Solo usamos `/user` (lectura); si falla, la app sigue sirviendo con la clave que ya está en las URLs. Nada se bloquea por no poder leer el estado |
| La clave de Real-Debrid queda en más lugares | Un solo secreto (`realDebridToken`) y las URLs se **derivan**; `redact` ya tapa la clave en pantalla y bitácoras. Cambiar la clave regenera las URLs de los recomendados |
| La TV y el iPhone dejan de compartir el avance | La consola lee `/sync/playback` de Trakt antes de quitar la escritura a Stremio desde el iPhone; hasta entonces, el iPhone sigue escribiendo también en Stremio |
| Más pantallas = más mantenimiento | La guía reutiliza piezas del catálogo y sus textos viven en un solo archivo de vocabulario |

## 6. Decisiones

**Ya decididas por Fernando (29 oct):**

- Trakt es el principal para el avance, lo visto y Mi lista. Stremio sigue recibiendo una copia mientras se prueba, y
  se suelta solo si la comparación sale bien (§4, «Transición»).
- El flujo inicial no pide Stremio. Real-Debrid y Trakt son obligatorios. Stremio se ofrece al final.
- Las listas públicas que hoy dicen «Stremio» pasan a Trakt (§4, corte D).
- Los complementos no se escriben de regreso a la cuenta de Stremio: solo se importan una vez.

**Pendientes:**

1. **¿Solo Real-Debrid, o también AllDebrid, Premiumize y TorBox?** Recomiendo solo Real-Debrid, con el protocolo
   listo para los otros. Es el que usas.
2. **El aviso de respaldo cada 5 minutos** (§5, punto 3). Recomiendo que sí: sin él, una batería muerta a media
   película deja a la TV sin saber dónde ibas.
3. **Proteger el punto de reanudación del 80 %** (§5, punto 4). Recomiendo que sí. Si no, cerrar una película con 20
   minutos por delante la marca vista en Trakt.

## 7. Orden y tamaño

| Paso | Qué entrega | Tamaño |
|---|---|---|
| 0 · Prueba con la cuenta de Trakt | Saber si `pause` sigue vivo, los decimales y el mínimo de `stop` (§5) | 10 min |
| A · Lo tuyo en el teléfono + Trakt principal + Stremio de copia | Entrar sin Stremio; avance, visto y Mi lista locales con Trakt; fase 1 de la transición; reglas de §5 | Grande |
| B · `OrbitalAddons` + Real-Debrid | Complementos locales con orden y apagado; la clave en las plantillas; días restantes y avisos | Medio |
| C · Guía + Ajustes nuevos | Las 10 pantallas del flujo y Ajustes (Cuentas, Complementos) | Medio, casi todo interfaz |
| D · Listas públicas de Trakt | Buscar, Para ti y Colecciones sin «Stremio»; búsqueda con Trakt primero | Chico |
| Fase 2 y 3 | Comparación automática dos semanas; luego soltar Stremio (con la consola leyendo Trakt) | Chico en el iPhone |

El paso 0 va antes que todo: si `pause` ya no existe, el corte A cambia. B y D se pueden hacer en paralelo con A
porque no se tocan.

