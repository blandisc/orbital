# Inicio del iPhone, cómo está hoy (29 oct 2026)

Revisión del Inicio del iPhone después de los cambios del 28 y 29 oct (corte A: lo tuyo vive en el teléfono y viaja
por Trakt; corte D: lo popular sale de Trakt «En tendencia»; Favoritos). Se leyó en el código de `main`
(`ios/App/Sources/Screens/HomeView.swift`, `ios/OrbitalCore/Sources/OrbitalModels/HomeModel.swift`). Sin capturas:
los altos son por cálculo.

El rediseño («Esta noche», tres propuestas) sigue en pausa por decisión de Fernando. Esto no lo retoma: dice cómo
quedó el Inicio y qué cambios chicos se podrían hacer sin tocar el rediseño. No se cambió código.

Antecedente: `analisis-ux-tecnico-2026-10-28.md` §2 y §5, `inicio-descubrir/tres-propuestas.html`.

---

## 1. Qué hay hoy, de arriba abajo

| # | Pieza | Qué enseña | De dónde sale |
|---|---|---|---|
| — | Barra | Logo · control de la TV · dona (Un Simpson al azar) · perfil | — |
| 1 | Aviso | «Sin conexión: se ve lo último que guardé» + Intentar de nuevo (solo sin red) | — |
| 2 | De la TV | Lo que mandaste con «Enviar al iPhone» (y «Viendo en la TV» solo en iOS 26.0) | Consola |
| 3 | **En tendencia** | Carrusel grande (300 pt de arte + encabezado + filtro Película/Serie), 10 tarjetas | Trakt: en tendencia y popular |
| 4 | **Seguir viendo** | Lo que tienes a medias y el siguiente episodio | El teléfono, al día con Trakt |
| 5 | Para ti | Recomendadas con lo que ves | Trakt |
| 6 | Top 10 en Netflix (o el servicio que elijas) | Series o películas, del 1 al 10 | Netflix (semanal) o JustWatch (del día) |
| 7 | Mi lista | Lo que dejaste pendiente | El teléfono + datos de Trakt |
| 8 | Sale hoy / Sale pronto | Episodios nuevos de lo que sigues + calendario del mes | Trakt |
| 9 | Favoritos | Lo que marcaste con el corazón | Trakt |

## 2. Qué mejoró desde el análisis del 28

- **Lo tuyo ya no depende de Stremio.** Seguir viendo y Mi lista salen del teléfono al instante y Trakt los pone al
  día después. Sin red se ve lo último, no una pantalla vacía.
- **Abre rápido.** Las cinco cargas van en paralelo y cada fila se pinta en cuanto llega lo suyo; al volver de otra
  pestaña no se pide nada si pasó menos de un minuto.
- **Lo personal salió del carrusel.** El destacado ya es solo «lo que todos ven»; tus recomendaciones bajaron a su
  propia fila con su porqué.
- **Lo que estás viendo no se repite** en el carrusel ni en Para ti.
- **Favoritos** cambia al momento y se puede quitar con Deshacer. Ya no sale «N cambios por subir».

## 3. Lo que sigue estorbando

| # | Problema | Qué siente quien usa la app | Dónde |
|---|---|---|---|
| 1 | **El carrusel de tendencias va antes de Seguir viendo.** Ocupa ~400 pt con su encabezado. En un iPhone SE, Seguir viendo queda en la orilla de abajo o fuera de la pantalla | Abres para seguir tu serie y primero ves lo de todos; hay que bajar | `HomeView.swift:77-95` |
| 2 | **El carrusel enseña cosas que ya viste.** Solo quita lo que tienes a medias, no lo terminado | «Esa ya la vi» en la portada | `HomeModel.mixSpotlight` (excluye solo `continueWatching`) |
| 3 | **Lo mismo vive en dos pestañas.** Recomendadas de Trakt, Top 10 de Netflix/JustWatch y Mi lista salen en Inicio y otra vez en Para ti | Para ti se siente repetido; no queda claro para qué es cada pestaña | `ForYou.swift:93-117`, `ParaTiModel.swift:212-219` |
| 4 | **«Sale hoy» va casi al final**, después de Mi lista. Es lo único del Inicio que cambia cada día | El episodio nuevo de hoy se pierde abajo | `HomeView.swift:102` |
| 5 | **Nada te ayuda a decidir.** «¿Qué vemos?» no está en Inicio; la dona es la única pieza de «elige por mí», y solo para Los Simpson | El «no sé qué ver» se resuelve bajando por 9 filas | — |
| 6 | **Jerga de servicios:** «Lo más visto hoy · JustWatch» | Un nombre que no dice nada a quien ve | `HomeView.swift:232` |
| 7 | **El Top 10 arranca en Netflix y la lista de servicios es fija**, no las plataformas que tú usas | Ves el ranking de un servicio que quizá no usas | `HomeModel.topServices`, `Charts.swift` |
| 8 | **Todas las filas se ven igual** (encabezado de dos líneas, misma tarjeta) | Nada guía la vista; lo urgente y lo de relleno pesan lo mismo | — |

## 4. Cambios chicos (sin retomar el rediseño)

Ordenados por lo que ganas contra lo que cuestan. Ninguno es «Esta noche»; todos sirven después si se retoma.

| | Cambio | Ganas | Pierdes | Esfuerzo |
|---|---|---|---|---|
| **A** | Seguir viendo arriba del carrusel cuando hay algo a medias; sin nada a medias, el carrusel abre como hoy | Seguir tu serie en un toque, sin bajar, también en el SE | El carrusel deja de ser lo primero que se ve casi siempre | Bajo |
| **B** | Quitar del carrusel lo que ya viste | Una portada que no repite lo terminado | Nada | Bajo |
| **C** | «Sale hoy» sube justo debajo de Seguir viendo cuando hay algo de hoy; si no, se queda abajo como «Sale pronto» | El episodio nuevo se ve al abrir | Mi lista baja un lugar ese día | Bajo |
| **D** | Cambiar «· JustWatch» por «en México» | Se lee en tu idioma | Nada | Mínimo |
| **E** | Quitar de Para ti lo que ya está en Inicio (recomendadas, Top 10, Mi lista) | Cada pestaña con su papel: Inicio es lo tuyo y lo de hoy; Para ti es pasear | Para ti se queda más corta | Medio (toca Para ti, no Inicio) |

**Recomendación:** A + B + C juntos. Contestan las dos primeras preguntas de quien abre la app («¿dónde me quedé?»
y «¿salió algo de lo mío?») sin tocar el rediseño, y caben en una tarde con sus pruebas en SE, mini y Pro Max.
D va de pasada. E conviene dejarla para cuando se retome el rediseño, porque ahí se decide qué es Para ti.

Esto choca con la pausa del Inicio del 29 oct: no se hace nada hasta que Fernando diga.
