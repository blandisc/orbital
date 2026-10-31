# Orbital, Orbital Plus y Orbital Ultra · plan (30 oct 2026)

Pedido de Fernando (30 oct 2026): dos objetivos grandes.

1. **La app, sin consola ni Stremio.** Que la use alguien que nunca ha usado Stremio y no tiene la consola.
2. **Lista para alguien no técnico.** Una guía de inicio sencilla que funcione, más llamativa y con animaciones.

Y con eso, el plan de **Orbital** (la de la App Store) y **Orbital Plus** (la tuya y de tu gente).

Página para el celular, con maquetas animadas de la guía: `plan.html` · https://claude.ai/artifact/2MpFUywvBVqD4ZuGNSQ34G
Antecedentes: `docs/producto/desacoplar-stremio/avance.md` (cortes A a E ya en `main`) y la sección 6 «Distribuir Orbital»
de `docs/producto/muvy-busqueda-premios/propuesta.html` (dos apps del mismo código, nunca una app con algo escondido).

## Cambio del 30 oct (tarde): tres versiones, y Plus primero

Fernando: «Primero hay que tener la Orbital Plus perfecta: que la pueda tomar cualquier persona y usarla. Plus no se
conecta con la computadora. Van a ser tres versiones: una para mí, que se conecta con la computadora, Orbital Plus y
Orbital normal.» Y luego: «La mía tiene todo. Orbital Plus no tiene control de la consola, no se conecta al escritorio.
Y Orbital no tiene nada de conexión a Real-Debrid. Para distinguirlas: Orbital, Orbital Plus y Orbital Ultra.»
Esto reemplaza la tabla de «Las dos apps» de más abajo.

| | **Orbital Ultra** (la de Fernando) | **Orbital Plus** | **Orbital** (App Store) |
|---|---|---|---|
| Para quién | Fernando | Cualquier persona que le pases | Cualquiera, desde la tienda |
| Ver al instante (Real-Debrid y complementos) | Sí | Sí | No (ni el código) |
| La consola: TV, control, voz, Siri de la TV, «Desde la TV» | Sí | No (ni el código) | No |
| Lo tuyo: Simpson al azar, acompañante de juegos, copia en Stremio | Sí | No | No |
| Descubrir, Trakt, «Dónde verla», tus videos | Sí | Sí | Sí |
| Cuenta | `mx.iracheta.orbital` (la de hoy) | `mx.iracheta.orbital.plus` | `mx.iracheta.orbital.app` (por decidir) |

Cómo: dos banderas de compilación. `ORBITAL_PLUS` (Real-Debrid, complementos) y `ORBITAL_ULTRA` (consola y lo de Fernando).
Ultra = las dos; Plus = solo `ORBITAL_PLUS`; Orbital = ninguna. Tres destinos en `project.yml` con el mismo código.

### Qué le falta a Plus para que la use cualquiera

**A · Separarla de la computadora (bloquea).**
1. El destino `OrbitalPlus` sin `ORBITAL_ULTRA`: fuera Ajustes › «Orbital en la TV», los atajos de Siri de la TV, el
   control del Centro de control, la tarea que revisa «Desde la TV», los textos de permisos de Alexa y de la TV, el
   Simpson al azar, el acompañante de juegos y la copia en Stremio (con su `LoginView`).
2. Prueba de que el binario de Plus no trae la consola (ni «/api/companion» ni los intents de la TV).

**B · Entrar sin atorarse (bloquea).**
3. Sin Real-Debrid de pago hoy no se termina la guía (`OnboardingModel.swift:36`). Que se pueda seguir con «Lo hago
   después»: la app sirve igual para descubrir y avisa en «Ver» qué falta.
4. Conectar Real-Debrid con un código, como Trakt, en vez de copiar «el texto largo» de real-debrid.com/apitoken.
   Real-Debrid tiene inicio de sesión con código para apps; hay que probarlo con una cuenta. Respaldo: pegar la clave.
5. Explicar Real-Debrid para quien nunca lo oyó: qué es en dos renglones, cuánto cuesta y **cómo se paga** (es lo más
   difícil para alguien no técnico; una guía con capturas de la página de pago).
6. Los complementos vienen puestos y no se explican (Torrentio, OpenSubtitles; Comet cuando se pruebe con tu cuenta).
7. Trakt opcional («Ahora no»).
8. La guía nueva, animada (maqueta en la página).

**C · Que «Ver» funcione siempre.**
9. Mensajes que hoy mandan a Stremio («Agrégalos en Stremio…», `Degraded.swift:73,78`; `UserMessages.swift`;
   `SessionModel.swift:21`) y los 53 textos de Stremio del catálogo: reescribir o borrar.
10. Quitar el respaldo a la lista de complementos de la cuenta de Stremio (`Addons.swift:109-112`).
11. Tocar el aviso de «se te acaba Real-Debrid» abre la página de renovar (hoy abre la app).
12. Cuando no hay versiones de un título, decirlo en palabras («Aún no hay versiones de este título; prueba mañana») y no
    dejar al usuario en una lista vacía.
13. **Cada persona, su propia cuenta de Real-Debrid.** Real-Debrid corta si dos lugares usan la misma cuenta a la vez:
    no se puede repartir la de Ultra. La guía lo dice.

**D · Ajustes para cualquiera.**
14. Sin claves a la vista: clave de TMDB y Client ID de Trakt solo en «Avanzado», y Avanzado al final y cerrado.
15. Mi media (OneDrive) se esconde en Plus hasta que haya una app de Microsoft registrada (hoy pide registrar una en
    Entra).
16. Un botón «Mandar un reporte a Fernando» (Ajustes › Ayuda) que comparte la bitácora del iPhone, para ayudar a
    distancia sin ver su teléfono.

**E · Repartirla.**
17. Cuenta de desarrollador de Apple (99 USD al año), si no la hay ya: sin ella no hay TestFlight y las apps de Xcode duran 7
    días.
18. TestFlight interno: cada persona entra a tu equipo de App Store Connect (correo de invitación) e instala TestFlight;
    hasta 100 personas. Cada versión dura 90 días: un script que suba una nueva cada mes. El TestFlight externo (liga
    pública) pasa por revisión de Apple y una app con Real-Debrid puede no pasar.
19. La clave de TMDB incluida viaja en cada versión que subas (hoy vive solo en la Mac, `Secrets.xcconfig`).
20. Ícono propio de Plus para que se distinga de Ultra en tu iPhone.

**F · Comprobarlo.**
21. Una persona que nunca usó Stremio instala Plus desde TestFlight, crea su Real-Debrid y ve algo, sin ayuda. Se graba
    y se corrige lo que tropiece.

Orden propuesto: A (separar) → B y C (entrar y ver) → D → E → F. Orbital (App Store) queda para después.

## Dónde estamos (auditoría del 30 oct)

Lo grande ya está hecho: no hace falta cuenta de Stremio, lo tuyo vive en el teléfono y se sincroniza con Trakt, los
complementos y Real-Debrid viven en la app, y la consola se prende en Ajustes › «Usar con tu Orbital».

Lo que todavía falla para alguien nuevo:

| # | Qué pasa hoy | Dónde | Gravedad |
|---|---|---|---|
| 1 | **Sin Real-Debrid de pago no se puede terminar la guía.** «Continuar» se queda apagado hasta que la clave es Premium y la guía no se puede saltar | `OnboardingModel.swift:36`, `OnboardingDebrid.swift:43`, `OnboardingView.swift:25` | Bloquea |
| 2 | La guía pide copiar «el texto largo» de real-debrid.com/apitoken y pegarlo; explica «complementos», Torrentio y Comet; el código de Trakt es obligatorio | `Onboarding/*` | Bloquea a quien no es técnico |
| 3 | Mensajes que mandan a Stremio: «Agrégalos en Stremio y vuelve a entrar», «revisa tus complementos en Stremio»; 53 textos de Stremio en el catálogo (varios muertos) | `Degraded.swift:73,78`, `UserMessages.swift:10,12`, `SessionModel.swift:21`, `Localizable.xcstrings` | Confunde |
| 4 | Si la lista de complementos del teléfono está vacía, toma la de la cuenta de Stremio | `Addons.swift:85,109-112,152` | Código viejo |
| 5 | La información de títulos sale de Cinemeta (servidor de Stremio) y los subtítulos de OpenSubtitles en strem.io | `Cinemeta.swift:71`, `StreamFinder.swift:189` | Dependencia escondida |
| 6 | Mi media (OneDrive) pide registrar una app en Microsoft Entra | `OneDriveSettings.swift:21`, `Settings.swift:61` | Bloquea Mi media |
| 7 | Con la consola apagada siguen ahí: Ajustes › «Orbital en la TV», los atajos de Siri de la TV, el control del Centro de control, la tarea que revisa «Desde la TV», los textos de permisos que hablan de la TV y de Alexa | `SettingsView.swift:84,146`, `OrbitalIntents.swift`, `RemoteControl.swift`, `project.yml` | Ruido |
| 8 | Cosas solo tuyas a la vista de todos: «Un Simpson al azar», el acompañante de juegos | `HomeView`, `SimpsonsControl`, `GameCompanionView` | Ruido |
| 9 | Ajustes pide claves: TMDB (opcional, ya viene incluida), Client ID de Trakt, dirección y token de la consola, dirección de un complemento | `SettingsView.swift:332,421`, `AddonsSettings.swift:56` | Técnico |
| 10 | Una sola app (`mx.iracheta.orbital`), sin forma de compilar una versión sin Real-Debrid | `project.yml` | Impide la App Store |

Lo que sí funciona sin nada: la guía de Trakt con código, todo el descubrimiento (Inicio, Para ti, Buscar, Lo que ves), y
reproducir videos que abres desde Archivos o AirDrop.

## Las dos apps

Un solo código, dos apps que se compilan aparte. La de la tienda **no trae** el código de Real-Debrid, complementos,
consola ni Stremio: no está escondido, no existe ahí (regla 2.5.19 de Apple).

| | **Orbital** · App Store | **Orbital Plus** · tú y tu gente |
|---|---|---|
| Para quién | Cualquiera | Tú, tu familia y amigos |
| Qué es | Tu historial de cine y series, qué ver hoy, dónde verlo | Todo lo de Orbital y además ver todo aquí mismo |
| Descubrir (Inicio, Para ti, Buscar, Lo que ves, Premios, mazo) | Sí | Sí |
| Seguir lo que ves (Trakt opcional) | Sí | Sí |
| «Dónde verla» abre Netflix, Max, Disney+… | Sí | Sí |
| Reproducir tus archivos (Archivos, AirDrop, OneDrive; luego Plex y Jellyfin) | Sí | Sí |
| Ver cualquier título al instante (Real-Debrid y complementos) | No (ni el código) | Sí |
| La consola de la TV, control, voz, Siri de la TV | No | Sí, en Ajustes |
| Copia en Stremio, Simpson al azar, acompañante de juegos | No | Sí |
| Cómo se instala | App Store | TestFlight interno (hasta 100 personas de tu equipo, cada versión dura 90 días) o desde Xcode |
| Cuenta | `mx.iracheta.orbital` | `mx.iracheta.orbital.plus` (conviven en el mismo iPhone) |
| Ícono | El de siempre | El de siempre con una marca (por ejemplo, la luna llena) |

Reglas: Orbital nunca menciona Plus ni Real-Debrid (nada de «Solo en Orbital Plus»: la maqueta de bibliotecas de la
propuesta Muvy lo tenía y hay que quitarlo). Plus no se cobra.

## Objetivo 1 · Cerrar el desacople

1. **Dos apps.** En `project.yml`, un segundo destino `OrbitalPlus` con la bandera `ORBITAL_PLUS`. Detrás de la bandera:
   Real-Debrid, complementos, `StreamFinder` de internet, consola (`Services.orbitalOn`, `OrbitalSetup`, intents de la TV,
   control del Centro de control, tarea `inbox`), Stremio (respaldo, importar una vez, `LoginView`), Simpsons y acompañante
   de juegos. Los textos de permisos de cámara, micrófono y voz cambian por app. Una prueba revisa que el binario de
   Orbital no tenga «real-debrid», «torrentio» ni «strem.io».
2. **Stremio fuera** (#3, #4, #5): reescribir o borrar los mensajes; quitar el respaldo a la lista de la cuenta de
   Stremio; la información de títulos sale de TMDB (la clave ya va incluida) y Cinemeta queda solo como respaldo en Plus;
   OpenSubtitles solo en Plus. Limpiar los textos muertos del catálogo.
3. **Sin claves a la vista** (#6, #9): registrar una app de Microsoft para Orbital e incluir su Id. (como el Client ID de
   Trakt); el Client ID de Trakt y la clave de TMDB pasan a una sola pantalla «Avanzado» que no hace falta abrir nunca.
   La clave de TMDB incluida tiene que llegar a las versiones que se publiquen (hoy vive solo en la Mac).
4. **Consola** (#7, #8): todo eso pasa a Plus (con el destino aparte, los atajos de Siri de la TV ya no se declaran en
   Orbital y desaparece el problema de que Apple no deja esconderlos).
5. **Seguridad de red:** Orbital sin `NSAllowsArbitraryLoads` (solo https); Plus lo conserva para la consola.

## Objetivo 2 · Lista para alguien no técnico

### La guía nueva (Orbital, unos 60 segundos, nada obligatorio)

1. **Bienvenida.** El logotipo que se dibuja (ya existe) sobre el muro de pósters en vaivén de Para ti. «Todo lo que ves,
   en un solo lugar.» · Empezar.
2. **Lo que ya viste.** Una cuadrícula de pósters populares en tu país. Tocar uno lo marca: rebota, se enciende el borde
   turquesa y aparece la palomita. «Elige 3 o más.» Arma Para ti y Lo que ves desde el primer minuto.
3. **Tus plataformas.** Los logos de Netflix, Max, Disney+, Prime Video, Apple TV+… se encienden al tocarlos. El país sale
   solo (con su bandera) y se puede cambiar. Alimenta «Dónde verla» y «Nuevo en tus plataformas».
4. **Trae tu historial · opcional.** Trakt con su código grande y un botón que abre Trakt; «Ahora no» siempre visible.
   Más adelante, importar de TV Time y Letterboxd.
5. **Avisos.** Una notificación de ejemplo baja desde arriba («Sale hoy: The Bear T4») antes de pedir el permiso.
6. **Listo.** Los pósters que elegiste giran en órbita alrededor de la luna y vuelan a su lugar en Inicio.

**En Plus** se suma, después de las plataformas, «Ver aquí mismo»: qué es Real-Debrid en dos renglones, y «Conectar» con
un código como el de Trakt (sin copiar ni pegar la clave; Real-Debrid tiene inicio de sesión con código para apps: hay que
confirmarlo con una prueba). «Pegar la clave» queda en «Otra forma». «Lo hago después» siempre se puede. Los complementos
vienen puestos (Torrentio y OpenSubtitles; Comet cuando se pruebe con tu cuenta) y la guía ya no los explica.

### Cómo se mueve

- Una sola transición entre pasos (el contenido sale a la izquierda y entra el siguiente con resorte suave), y la barra de
  avance pasa a ser una órbita con lunas que se encienden.
- Cada toque responde: rebote (`DS.Motion.pop`), brillo y una vibración ligera solo en la guía.
- Todo con tokens de `DS.Motion`; con «Reducir movimiento», solo fundidos.
- Piezas nuevas al catálogo (`docs/ios-proyeccion.md`): `DSPickGrid` (cuadrícula de pósters para elegir),
  `DSPlatformPicker` (logos que se encienden), `DSOrbitProgress` (avance en órbita), `DSNotificationPreview`. El muro de
  pósters y el logotipo animado ya existen y se reusan.

### Más allá de la guía

- **Glosario sin jerga:** fuera de Avanzado, ningún texto dice clave, token, API, complemento, manifest, Client ID ni
  servidor. `DesignTests` lo revisa (como las demás reglas del lenguaje).
- **Cada error dice qué hacer**, en una frase y con un botón (Reintentar, Abrir Ajustes…).
- **Primer día sin historial:** Inicio, Para ti y Lo que ves con un estado vacío bonito que invita (nunca filas vacías).
- **Prueba con una persona real:** alguien que nunca usó Stremio instala, entra y hace cinco cosas sin ayuda (encontrar
  una película, ver dónde está, marcar algo visto, guardar en Mi lista, abrir un video suyo). Se graba y se corrige.
- Letra grande (Dynamic Type) y VoiceOver en toda la guía.

## Fases, en orden

| Fase | Qué | Cómo se sabe que quedó |
|---|---|---|
| 0 | Decisiones de Fernando (abajo) | Respuestas en este archivo |
| 1 | Dos apps de un código | Las dos compilan y se instalan juntas; la prueba del binario pasa |
| 2 | Cerrar el desacople (#3 a #9) | Ningún «Stremio» ni clave a la vista en Orbital; `swift test` y `DesignTests` en verde |
| 3 | Guía nueva: maquetas aprobadas → piezas al catálogo → pantallas | `OnboardingUITests` en SE, mini y Pro Max; video antes y después |
| 4 | Pulido para no técnicos (glosario, errores, estados vacíos) y prueba con una persona | La persona hace las cinco tareas sola |
| 5 | Lista para la App Store | Ver abajo |

**Fase 5 · App Store:** cuenta de desarrollador (99 USD al año), política de privacidad, logo y aviso de TMDB, registrar
Orbital como app pública en Trakt, la app de Microsoft para OneDrive, revisar que el nombre «Orbital» esté libre, notas
para el revisor de Apple, capturas de la tienda. Después: importar de TV Time, Plex y Jellyfin (Orbital 1.1).

## Decisiones para Fernando

1. **Qué reproduce Orbital al salir.** Recomendado: «Dónde verla» más tus archivos (Archivos, AirDrop y OneDrive) y Plex y
   Jellyfin en la 1.1. Así sale antes; lo que pierde es que el botón «Ver» de la tienda abre otra app casi siempre.
2. **Trakt en Orbital.** Recomendado: opcional. Lo tuyo se guarda en el teléfono igual; quien conecta Trakt no lo pierde
   al cambiar de iPhone. Obligatorio espanta a quien no lo conoce.
3. **OneDrive.** Recomendado: registrar una app de Microsoft para Orbital (10 minutos, gratis) en vez de esconder Mi media.
4. **Cómo reparte Plus.** Recomendado: TestFlight interno (se instala con una liga, se actualiza solo; cada versión dura
   90 días y la gente tiene que estar en tu equipo de App Store Connect). La otra es instalar desde Xcode, una por una.
5. **Real-Debrid con código.** Recomendado: sí, si la prueba confirma que funciona; si no, pegar la clave pero con un
   botón «Copiar de la página» guiado.
6. **El orden.** Recomendado: fase 1 primero (las dos apps), porque decide qué entra en cada guía; la guía nueva va
   después, con maquetas antes de construir.
