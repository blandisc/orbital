# Guía de inicio, recorrido y «Aprende Orbital» · propuesta (3 nov 2026)

Pedido de Fernando (3 nov 2026), en el iPhone:

1. Una guía al abrir la app por primera vez, con elementos animados que caen y que hablan el lenguaje visual de Orbital.
2. Una presentación fácil, que sirva a quien tiene o no tiene la TV (la consola), y que explique qué es Real-Debrid.
3. Que tenga «attract» (modo vitrina: la app se enseña sola si no la tocas).
4. Ningún elemento de Stremio en la app.
5. Un recorrido con avisos sobre la pantalla (coach marks) la primera vez que entras a algo nuevo.
6. Un centro de conocimiento con historias, como las de Instagram, que recuerda la guía y profundiza en cada función.

Lo que todos entienden (tocar un póster abre la ficha) no se explica. Lo que sí: Real-Debrid, ver al instante y las
versiones, la búsqueda avanzada, Explorar y Decide, Lo que ves, Trakt, los gestos del reproductor, Descargas y, en Ultra,
la TV.

Canvas con las pantallas y las decisiones: https://claude.ai/artifact/TX7vDeisfAjGp8HcorSg9A

Parte de las maquetas del 30 oct (`docs/producto/orbital-y-plus/guia-maquetas.html`), que no se construyeron, y de sus
cuatro decisiones pendientes.

## La guía (unos 60 segundos, nada obligatorio)

| # | Paso | Qué pasa |
|---|---|---|
| 1 | Bienvenida | Lluvia de pósters que caen y entran en órbita alrededor del planeta de la marca. «Todo lo que ves, en un solo lugar.» Si no la tocas, a los 8 s arranca la vitrina (attract). |
| 2 | ¿Qué te gusta? | Cuadrícula de pósters populares; tocar uno rebota y se enciende. Son gustos, no vistos. |
| 3 | Tus plataformas | Logos que se encienden; país automático. |
| 4 | ¿Qué ya tienes? | Tres tarjetas: Real-Debrid, Trakt y (solo Ultra) Orbital en la TV. «Sí, ya tengo» / «No, ¿qué es?» / «Después». Decide qué pasos siguen. |
| 5 | Ver aquí mismo (Real-Debrid) | Solo en Plus y Ultra. Qué es (3 pasos animados), cuánto cuesta y cómo se paga, una cuenta por persona. Conectar con código; pegar la clave en «Otra forma». |
| 6 | Trakt | Opcional, código grande. |
| 7 | Tu TV | Solo Ultra y solo si dijo que la tiene. |
| 8 | Avisos | Una notificación de ejemplo cae desde arriba antes de pedir el permiso. |
| 9 | Listo | Tus pósters giran y aterrizan en Inicio; aparecen los círculos de «Aprende». |

## Decisiones (códigos para dictar)

- **A · Qué cae en la bienvenida.** A1 pósters que caen y entran en órbita (recomendado: enseña el contenido desde el primer
  segundo). A2 lunas y estrellas del Cielo nocturno que se juntan en la marca (más calmado, no enseña nada de la app).
- **B · Vitrina (attract).** B1 si no tocas la bienvenida 8 s, se reproduce sola en bucle: elegir un póster → ficha → «Ver»
  → arranca al instante; cualquier toque la detiene (recomendado). B2 sin vitrina.
- **C · Presentación.** C1 «¿Qué ya tienes?» arma la guía a tu medida (recomendado: quien ya tiene todo termina en 4 pasos;
  quien no tiene nada entiende cada pieza). C2 la misma guía para todos.
- **D · Conectar Real-Debrid.** D1 con código, como Trakt (recomendado; requiere tu OK para probarlo una vez con tu cuenta).
  D2 pegar la clave, guiado.
- **E · Stremio fuera.** E1 de las tres versiones, también de Ultra: sin iniciar sesión, sin copia, sin «Traídos de tu
  Stremio» (los complementos que ya trajiste se quedan como tuyos) y sin mensajes que lo nombren (recomendado: es lo que
  pediste y Trakt ya hace el trabajo). E2 fuera de Plus y Orbital, y la copia sigue en Ultra.
- **F · Recorrido sobre la pantalla.** F1 foco: oscurece todo menos el botón y una burbuja dice qué hace, 1 a 3 pasos, la
  primera vez que entras (recomendado para las 6 pantallas difíciles). F2 avisos chicos sin oscurecer (TipKit de Apple),
  uno a la vez.
- **G · Dónde viven las historias.** G1 círculos arriba de Inicio siempre. G2 solo en Ajustes › «Aprende Orbital». G3
  arriba de Inicio mientras haya alguna sin ver (anillo turquesa = nuevo) y después en Ajustes; vuelven a Inicio cuando sale
  una historia nueva (recomendado).
- **H · Los pósters que eliges.** H1 solo gustos (recomendado: no ensucia tu historial de Trakt). H2 cuentan como vistos.

## Recorrido (dónde aparece la primera vez)

| Pantalla | Qué señala |
|---|---|
| Inicio | Los círculos de Aprende; el porqué en turquesa |
| Explorar | Para ti y Decide (deslizar para elegir entre dos) |
| Buscar | La búsqueda avanzada (filtros que se combinan) |
| Ficha | «Ver», «Versión» y pedirle a Real-Debrid |
| Reproductor | Gestos: deslizar brillo/volumen, doble toque, candado |
| Descargas | Qué se baja y dónde queda |

Cada burbuja termina con «Ver la historia completa», que abre la historia de esa función. Se ven una vez; Ajustes ›
Aprende › «Volver a ver los avisos» los reinicia.

## Historias (cada una de 3 a 5 tarjetas animadas)

Real-Debrid · Ver al instante y versiones · Búsqueda avanzada · Explorar y Decide · Lo que ves y tu Wrapped · Trakt ·
El reproductor · Descargas · Calendario de estrenos · (Ultra) Orbital en la TV.

Se tocan a los lados para cambiar, se mantiene para pausar, se baja para cerrar. La última tarjeta tiene un botón que te
lleva a la función («Probar la búsqueda avanzada»).

## Alineado con la sesión de Real-Debrid (3 nov)

- La página de Real-Debrid de la guía y su historia usan la pieza de tres pasos de `Design/Explainer.swift`
  (`DebridFlowStrip`) y sus textos (RX3-A): Orbital la encuentra › Real-Debrid la consigue en su nube › la ves al instante.
- Palabras (RX4-A): «nube» para Real-Debrid («Pedir a la nube», «Bajando en la nube»); «Descargar» solo para guardar en el
  iPhone.
- La tarjeta «Así funciona» de las versiones «Por pedir» no sale si ya viste esa página o esa historia; se recuerda con la
  llave `learn.seen.debrid-flow`, que lee `LearnModel`.

## Cómo se construye (resumen técnico)

- Piezas nuevas al catálogo: `DSFallingPosters` (lluvia y órbita), `DSAttractLoop`, `DSCoachMark` (foco y burbuja,
  `anchorPreference`), `DSStoryRing` y `StoryPlayer` (sale de `WrappedView`, que se reusa), `DSOrbitProgress`.
- Modelo en OrbitalCore: `LearnModel` (qué historias y avisos ya viste, en `kv`), contenido de las historias como datos.
- Con «Reducir movimiento», nada cae ni gira: fundidos.
- Pruebas: `OnboardingUITests` (SE, mini, Pro Max, iOS 27), `LearnModelTests`, `DesignTests` sin «Stremio» en textos.
- La TV: la guía de la TV ya existe; se le avisa de las historias y el recorrido para paridad (registro en
  `docs/producto/paridad-registro.md`).

## Ajustes tras las dos revisiones (producto y técnica, 3 nov)

- La guía queda en 7 pasos: gustos y plataformas en una pantalla; el permiso de avisos sale de la guía y se pide en el
  momento (al seguir una serie o pedir algo a la nube). «Saltar» con ícono, siempre visible.
- Real-Debrid: «Ya pagué, revisar» al volver de pagar, la guía recuerda el paso, historia propia «Cómo pagar y renovar».
  En Orbital (App Store) no se nombra Real-Debrid en ningún paso.
- Quien ya usa la app (guía terminada, o Real-Debrid o Trakt conectados) no ve la guía ni los avisos; solo los círculos.
- Vitrina (B1): a los 12 s, no 8; sin prometer «al instante» donde no hay Real-Debrid; no existe en la Mac. Un revisor
  prefería B2.
- D1 solo si la clave renovada se reescribe sola en la dirección de los buscadores y en la copia de la TV
  (`DebridModel+TV.swift`); si no, D2. Hoy solo se usa la clave fija (`OrbitalAddons/Debrid.swift`).
- F3: foco en la ficha y en la búsqueda avanzada (`overlayPreferenceValue` dentro de cada `NavigationStack`, anclas
  `Equatable`); TipKit en lo demás, también para las pestañas (la barra es del sistema) y el reproductor (solo en pausa).
  Uno por visita, nunca justo después de la guía ni si ya usaste la función; «Saltar avisos».
- Historias suman «Cómo pagar y renovar» y «Cuando no hay versiones»; el calendario va dentro de «Avisos y estrenos».
- Pósters que caen: un solo `TimelineView` con `Canvas`, pausa en segundo plano y con Reducir movimiento; unos 20 pósters
  dentro de la app para que la bienvenida no salga vacía sin red ni clave de TMDB.
- `StoryPlayer` genérico sale de `WrappedView` (`Design/Stories.swift`); VoiceOver: no avanza sola; Mac: flechas y Escape.
- Archivos de menos de 600 líneas (`FileBudgetTests`); pruebas `OnboardingUITests` ampliada, `CoachMarkUITests`,
  `StoriesUITests`, banderas `-demo-onboarding`, `-demo-coach`, y el simulador de iPad.
- Stremio (E1): fuera `StremioAPI`, `SecretKey.stremioAuth`, `LoginView`, la copia y la fusión en `LibraryMerge`; Cinemeta y
  subtítulos siguen (dominios públicos, sin nombre a la vista); `StremioLibrary.*` se renombra. `DesignTests` busca el
  nombre en `Localizable.xcstrings`.
