# Guía de inicio, avisos y «Aprende Orbital» · plan (versión 2, 3 nov 2026)

Pedido de Fernando (3 nov 2026), en el iPhone: una guía al abrir con elementos que caen en el lenguaje visual de Orbital;
una presentación que sirva a quien tiene o no la TV y que explique Real-Debrid; vitrina («attract»); ningún Stremio; avisos
sobre la pantalla la primera vez que entras a algo nuevo; y un centro de conocimiento con historias como las de Instagram.

- Página para el celular, pantalla por pantalla: `guia-celular.html` · https://claude.ai/artifact/9yLoYYTAMN4R2NdqxtLQUz
- Canvas de la primera propuesta: https://claude.ai/artifact/TX7vDeisfAjGp8HcorSg9A

## Decidido (Fernando, 3 nov)

**A1 · B1 · C1 · D1 · E1 · F3 · G3 · H1.** A1 «mucho más estilizado», y pidió ver una variante con el mosaico detrás
(abajo, A1-M). Luego pidió pasarlo por dos expertos (viaje de onboarding; animación, diseño visual y storytelling) y
cambiar el plan con lo que dijeran. Esta versión ya lo trae.

Queda abierto: **A1 sola o A1-M** y el OK para probar una vez el código de Real-Debrid con su cuenta (D1).

## La idea en una frase

La luna turquesa de la marca es tu guía: atrapa los pósters en la bienvenida, avanza por la órbita en cada paso, señala en
los avisos y se vuelve el primer círculo de «Aprende». Todos llegan a un primer «ajá» (un Inicio hecho a su gusto) en menos
de un minuto; ver el primer video aquí mismo es el segundo, cuando hay ganas de ver algo concreto.

## La guía, por versión

| Versión | Pasos |
|---|---|
| Orbital (App Store) | Bienvenida · Lo que te gusta · Trakt · Listo (4; nunca nombra Real-Debrid) |
| Plus | Bienvenida · Lo que te gusta · ¿Qué ya tienes? · Ver aquí mismo · Trakt · Listo (hasta 6) |
| Ultra | Lo de Plus + Tu TV, solo si dijiste que la tienes (hasta 7) |

iPad: los mismos pasos en dos columnas. Mac: sin vitrina, todo con teclado, y el código de Real-Debrid abre el navegador
de la misma Mac.

### 1 · Bienvenida (A1): siete pósters que el planeta atrapa

Ya no es una lluvia: son 7 pósters, y el planeta los atrapa (coreografía del experto en animación):

| Tiempo | Qué pasa |
|---|---|
| 0–400 ms | Casi negro. El planeta aparece en el centro alto (fundido, escala 0.96 → 1). Sin anillo. |
| 300–1 400 ms | Caen 7 pósters chicos desde arriba, cada 90 ms, con gravedad, girados ±8° que se enderezan. Sin rebote. |
| 900–2 200 ms | Al llegar a la altura del planeta, cada uno se curva y entra en órbita: elipse inclinada 18° (la del anillo), escala 0.7, resorte 600 ms. Detrás del planeta se tapa y baja a 40 % de brillo; delante, 100 %. Esa es la profundidad, sin brillos. |
| 1 600–2 400 ms | El anillo se dibuja como pincelada (el `OrbitalWordmark` animado que ya existe), del extremo delgado al grueso, y barre la órbita de los pósters. |
| 2 400 ms | Entra la luna turquesa con un resorte pop y un toque háptico suave. Es el primer turquesa de la app. |
| 2 600–3 100 ms | «Todo lo que quieres ver, en un solo lugar.» sube 16 pt con fundido; la línea de abajo, 80 ms después. |
| 3 200 ms | «Empezar» y «Saltar» (ícono). |
| En reposo | La órbita da una vuelta cada 40 s y la luna cada 24 s. |

**A1-M, la variante con el mosaico detrás:** tres capas. Fondo: el mosaico de «Para ti» a 0.6 de escala, desenfocado 24 pt,
18 % de opacidad, a media velocidad, con una sombra del color del fondo detrás del planeta; entra a los 1 200 ms y ninguna
pieza crece. Medio: la órbita. Frente: el texto. Giroscopio solo en el fondo (4 pt, `SkyTilt`). El primer día el mosaico
se arma con los 20 pósters que trae la app (aún no hay gustos).

**Lo que recomiendan los expertos: A1 sola.** El mosaico cuenta «mucho contenido», pero le quita protagonismo a lo único
de la marca (los pósters que el planeta atrapa); además, el mosaico es la cara de «Para ti» y repetirlo en la bienvenida le
quita sorpresa después, y son dos cosas moviéndose (batería y ruido en el iPhone SE). El mosaico luce más como fondo de la
vitrina.

### 1b · Vitrina (B1): una película de 11 s

Arranca a los 12 s sin tocar. Corre dos vueltas y se detiene en «Empezar» (un bucle sin fin parece una app trabada). No
sale con VoiceOver, ni con Reducir movimiento, ni si abriste la app desde un widget o un enlace. Cualquier toque la detiene
(fundido de 220 ms). No vibra.

1. 0–1,5 s: la órbita se abre y aparece el mosaico al frente.
2. 1,5–3 s: la luna se posa sobre un póster, que crece con resorte.
3. 3–5 s: el póster se expande y se vuelve la ficha (zoom de Apple).
4. 5–8,5 s: los tres pasos de la nube (`DebridFlowStrip`), uno cada 1,1 s. En Orbital, «Dónde verla».
5. 8,5–10 s: «Ver» se presiona y la pantalla se va a negro.
6. 10–11 s: regresa a la órbita.

### 2 · Lo que te gusta (H1)

«¿Qué te gusta? Elige 3 o más.», con contador, y «¿Dónde ves hoy?» para las plataformas, en la misma pantalla. Son gustos,
no vistos. Se puede saltar: entonces Inicio muestra populares y la tarjeta «Dime qué te gusta y lo armo para ti». Vibración
de selección al elegir.

### 3 · ¿Qué ya tienes? (C1)

«Así te explico solo lo que te falta.» Tarjetas de Real-Debrid, Trakt y (Ultra) la TV, con «Ya lo tengo», «¿Qué es?» y
«Después» como botones completos, no cápsulas.

### 4 · Ver aquí mismo (D1): el pago ya no bloquea

- «Ver aquí mismo, sin esperar.» Los tres pasos animados, «Cuesta unos 3 € cada 15 días y lo pagas en su página.», una
  cuenta por persona, no ocupa espacio en tu iPhone.
- Dos salidas: **«Conectar ahora»** o **«Cuando quiera ver algo»**. Quien elige la segunda termina la guía; la primera vez
  que toca «Ver» sin Real-Debrid, la hoja de conectar sale ahí mismo.
- «Abrir Real-Debrid» copia el código. Al volver a la app, revisa solo: «Revisando tu cuenta…» → «Listo, ya puedes ver
  aquí mismo.» o «Aún no veo el pago. Te espero aquí.». «Ya pagué, revisar» queda de respaldo. Si el código vence, sale
  uno nuevo solo.
- D1 se construye solo si la clave que se renueva sola se reescribe también en los buscadores y en la TV; si la prueba con
  tu cuenta falla, se queda pegar la clave (D2), guiado.

### 5 a 7 · Trakt, Tu TV, Listo

- Trakt: «Guarda lo que ves en todos tus aparatos. Gratis.» y el código grande. Opcional.
- Tu TV: solo Ultra y solo si dijiste que la tienes.
- Listo (1,6 s): «Tu Orbital ya está lista.» Los pósters elegidos salen de la órbita y aterrizan en su lugar en Inicio
  (resorte de 600 ms, cada 60 ms); la luna se encoge y se vuelve el anillo del primer círculo de Aprende. Vibración de éxito.
  «Ir a Inicio».
- El permiso de avisos no se pide en la guía: se pide al seguir una serie o al pedir algo a la nube.

### Entre pasos

- La barra de avance es un arco fino con una marca por paso; la luna avanza una marca (resorte de 320 ms). Sin texto.
- Lo que sale se encoge a 0.96 y se desvanece (220 ms); lo que entra sube 16 pt (520 ms). La luna es lo único que viaja de
  una pantalla a otra: va del arco a lo nuevo de esa pantalla (el código, la tarjeta que eliges).
- Si cierras la app a medias: antes de 24 h sigues donde ibas; después, nunca se vuelve a imponer, y Inicio muestra
  «Termina de preparar Orbital · 2 de 4».

## Avisos sobre la pantalla (F3)

- Foco solo en la ficha («Ver» y «Versión») y en la búsqueda avanzada: el velo oscurece al 75 % en 320 ms, el hueco se
  abre del tamaño del botón más 8 pt, un anillo turquesa de 2 pt se dibuja una vez en 520 ms y no late, y la burbuja sube
  8 pt 120 ms después. «"Ver" elige la mejor versión en tu idioma.» · «Entendido» · «Ver la historia».
- Aviso chico de Apple (TipKit) en lo demás, también en las pestañas y en el reproductor (solo en pausa).
- Ninguno en la misma sesión de la guía; como máximo uno por visita; nunca si ya usaste la función; «Saltar avisos».

## Aprende Orbital (G3)

- Máximo 4 círculos en Inicio, ordenados por lo que te falta: «Cómo pagar» (si no conectaste Real-Debrid), «Búsqueda
  avanzada», «El reproductor»… Se van a Ajustes › Aprende Orbital cuando los viste todos o a los 14 días; vuelve uno solo
  si hay una función nueva o si tu cuenta venció.
- El anillo de lo no visto es un trazo fijo turquesa que se dibuja una vez al entrar a Inicio (700 ms), sin girar; al verla,
  se vacía y queda gris (320 ms).
- Lo que ya viste en la guía (Real-Debrid, Trakt) cuenta como visto en su historia, y la tarjeta «Así funciona» de la
  sesión de Real-Debrid se recuerda con la misma llave (`learn.seen.debrid-flow`).
- Las 11 historias: Real-Debrid · Cómo pagar y renovar · Trakt · Búsqueda avanzada · Explorar y Decide · Avisos y estrenos ·
  Ver al instante y versiones · Cuando no hay versiones · El reproductor · Descargas y la nube · Lo que ves y tu Wrapped. En
  Ultra, también la TV.
- Cinco plantillas de tarjeta, como datos: portada (planeta chico y una frase), tres pasos (`DebridFlowStrip`), gesto (una
  mano fantasma de 44 pt lo repite dos veces), antes y ahora (un deslizador que se mueve solo) y botón final que lleva a la
  función. Una idea por tarjeta; 5 s cada una (7 s con texto largo).
- Encadenado: el aviso lleva a la historia y la historia lleva a probar la función; nunca al revés.

## Quien vuelve y las pantallas vacías

- Quien ya usaba la app no ve la guía ni los avisos; solo los círculos.
- Si vuelves después de semanas con Real-Debrid vencido: barra arriba «Tu Real-Debrid venció · Renovar», que abre «Cómo
  pagar y renovar». Arriba de todo, «Sigue viendo».
- Pantallas vacías con salida: ficha sin Real-Debrid («Conecta Real-Debrid para verla aquí»), Descargas («Lo que guardes
  para ver sin internet aparece aquí»), Lo que ves («Ve tu primera película y empieza tu año»).

## Stremio fuera (E1)

Fuera `StremioAPI`, `SecretKey.stremioAuth`, `LoginView`, la sección de Ajustes, «¿Usas Stremio?», la copia y la fusión en
`LibraryMerge`, y los mensajes que mandan a Stremio. «Traídos de tu Stremio» → «Agregados por ti» (los complementos se
quedan). La información de títulos (Cinemeta) y los subtítulos siguen: son servicios públicos en dominios de Stremio, sin
nombre a la vista. `StremioLibrary.*` se renombra. `DesignTests` revisa que ningún texto diga «Stremio».

## Movimiento, rendimiento y accesibilidad

- Un solo `TimelineView` con `Canvas` para la órbita, la caída y la luna; pósters dibujados una vez; 60 cuadros por segundo
  en la entrada y 30 en reposo (como el horario del Cielo); pausa en segundo plano y fuera de la pantalla.
- Vibración solo en 3 momentos: llega la luna, eliges un gusto, «Listo».
- Reducir movimiento: fundidos de 220 ms, la órbita quieta y armada, sin vitrina, historias que no avanzan solas.
- VoiceOver: los avisos se anuncian y se cierran con el gesto de escape; los pósters dicen su título; las historias no
  avanzan solas. Letra grande sin cortes.
- 20 pósters dentro de la app para que la bienvenida y la vitrina no salgan vacías sin internet ni clave de TMDB.

## Qué medimos

Guía: `onboarding_step_viewed`, `onboarding_skipped` (con el paso), `onboarding_completed` (con la duración).
Real-Debrid: `rd_explained`, `rd_open_site`, `rd_returned`, `rd_connected` (minutos desde que abrió la página),
`rd_code_expired`. Primer video: `first_play` (minutos desde la instalación). Avisos e historias: `coach_shown`,
`coach_dismissed`, `story_opened`, `story_completed`, `story_cta_tapped`. Regreso: `d1_return`, `d7_return`.

Las tres cifras que importan: de los que abren la página de Real-Debrid, cuántos conectan; cuánto tardan en ver el primer
video; cuántos vuelven a la semana. Se guardan solo en el iPhone (bitácora), sin mandarse a ningún servicio.

## Cómo se construye

- Piezas nuevas al catálogo: `DSOrbitCatch` (los 7 pósters y la luna, `TimelineView` + `Canvas`), `DSOrbitProgress`,
  `DSAttractFilm`, `DSCoachMark` (`overlayPreferenceValue` dentro de cada `NavigationStack`, anclas `Equatable`),
  `StoryPlayer` (sale de `WrappedView`, que pasa a ser su primer uso) y `DSStoryRing`. Archivos de menos de 600 líneas.
- Modelos en OrbitalCore: `OnboardingModel` sin pasos obligatorios, con el paso guardado y la guía por versión;
  `LearnModel` (visto, orden por lo que falta, 14 días) con el contenido de las historias en `LearnContent`.
- Pruebas: `OnboardingUITests` ampliada (las rutas de C1, saltar, la vitrina se detiene, reanudar), `CoachMarkUITests`,
  `StoriesUITests`, `LearnModelTests`, `DesignTests` sin «Stremio»; banderas `-demo-onboarding`, `-demo-coach`,
  `-demo-no-idle`; SE, mini, Pro Max, iOS 27 y el iPad.
- La TV: su guía ya existe; los avisos y las historias entran al registro de paridad.

## Orden de construcción

1. Stremio fuera (E1): no depende de nada y limpia la guía.
2. `OnboardingModel` nuevo y las pantallas 2 a 7 (sin animación fina).
3. La bienvenida A1 (o A1-M) y la vitrina.
4. `StoryPlayer`, `LearnModel` y los círculos.
5. Los avisos sobre la pantalla.
6. Real-Debrid con código, tras la prueba con tu cuenta.
