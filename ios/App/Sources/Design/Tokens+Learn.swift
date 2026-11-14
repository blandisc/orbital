import SwiftUI

// La guía de la primera vez, la vitrina, los avisos sobre la pantalla y «Aprende Orbital» (Fernando, 3 nov 2026: «A1 · B1 ·
// C1 · D1 · E1 · F3 · G3 · H1»; coreografía en docs/producto/guia-aprende/propuesta.md).
extension DS {
    /// La bienvenida (A1): siete pósters que el planeta atrapa en su órbita.
    enum Welcome {
        /// Cuántos pósters caen y su tamaño (alto de un póster de 2:3).
        static let posters = 7
        static let posterHeight: CGFloat = 66
        /// El planeta (la marca) y la órbita de los pósters, en puntos.
        static let planet: CGFloat = 120
        static let orbitWidth: CGFloat = 300, orbitHeight: CGFloat = 104   // ds-exception: la elipse de la órbita (dibujo de la marca)
        static let tilt: Double = -18   // ds-exception: la inclinación del anillo de la marca, en grados
        /// La luna, en su órbita concéntrica (más afuera que la de los pósters).
        static let moon: CGFloat = 14, moonOrbit: CGFloat = 1.18   // ds-exception: proporción de la órbita de la luna
        /// Detrás del planeta, los pósters bajan a este brillo; delante, completos. Y se encogen al entrar en órbita.
        static let behind: Double = 0.4, orbitScale: CGFloat = 0.7
        /// Los tiempos de la coreografía, en segundos desde que aparece (A1).
        static let planetIn = 0.4, fallStart = 0.3, fallStep = 0.09, fallDuration = 1.2
        static let ringAt = 1.6, moonAt = 2.4, phraseAt = 2.6, buttonAt = 3.2
        /// En reposo: una vuelta de la órbita cada 40 s y de la luna cada 24 s.
        static let orbitPeriod = 40.0, moonPeriod = 24.0
        /// Cuadros por segundo: 60 mientras entra, 30 en reposo (como el cielo).
        static let introFrame = 1.0 / 60, restFrame = 1.0 / 30
        /// Cuánto giran al caer (se enderezan al llegar) y de qué tan arriba vienen.
        static let fallTwist: Double = 8, fallFrom: CGFloat = 420   // ds-exception: grados y puntos de la caída (coreografía A1)
        /// El alto de toda la escena (la órbita de la luna incluida): en un iPhone chico se encoge a lo que quepa.
        static let sceneHeight: CGFloat = 354
        /// La frase sube esto al aparecer.
        static let rise: CGFloat = 16
    }

    /// La vitrina (B1): a los 12 s sin tocar, la bienvenida se enseña sola; dos vueltas y se detiene.
    enum Attract {
        static let idle: Duration = .seconds(12)
        static let scene: Duration = .milliseconds(1800)
        static let rounds = 2
    }

    /// La barra de avance de la guía: un arco con una marca por paso y la luna en el tuyo.
    enum OrbitArc {
        static let height: CGFloat = 28, mark: CGFloat = 5, moon: CGFloat = 12
        static let bend: CGFloat = 0.7   // ds-exception: cuánto se curva el arco (proporción de su alto)
    }

    /// Lo que te gusta (H1): la cuadrícula de pósters y las plataformas.
    enum Likes {
        static let columns = 3
    }

    /// Las historias de «Aprende Orbital» (G3). La barra, el toque para regresar y mantener para pausar son los del Wrapped
    /// (`DS.Watching`).
    enum Story {
        /// Cada tarjeta dura lo suyo (`LearnStory.Card.seconds`); la última con botón, esto más para alcanzar a tocarlo. Avanza
        /// en `ticks` pasos.
        static let lastExtra: Duration = .seconds(2)
        /// «Tu turno»: cuánto espera tu gesto antes de que lo haga el dedo fantasma, y la pausa para celebrarlo.
        static let turnWait: Duration = .seconds(6), turnPraise: Duration = .milliseconds(700)
        static let ticks = 60
        /// El ícono de la historia arriba y la mano fantasma.
        static let hand: CGFloat = 44
        /// El cubo entre historias: cuánto gira una cara al irse entera y qué tan honda se ve.
        static let cubeAngle: Double = 90, cubePerspective: CGFloat = 0.6   // ds-exception: grados y profundidad del cubo (como Instagram)
        /// Bajar más que esto la cierra.
        static let closeDrag: CGFloat = 120
        /// El círculo de Inicio: su anillo y el cuadro de adentro.
        static let ring: CGFloat = 64, ringStroke: CGFloat = 2.5, tile: CGFloat = 52
    }

    /// Los avisos sobre la pantalla (F3).
    enum Coach {
        /// El velo del foco y el aire alrededor del botón señalado.
        static let veil = 0.75
        static let hole: CGFloat = 8
        static let ring: CGFloat = 2
        static let bubble: CGFloat = 300
        /// La escena en miniatura dentro de la burbuja.
        static let scene: CGFloat = 130
        /// Lo alto que debe medir la pantalla entera para que la burbuja lleve su miniatura (el SE, 667, no llega).
        static let roomForScene: CGFloat = 700
    }
}

extension DS.ListTint {
    /// El color de una historia por su nombre (`LearnStory.tint`).
    static func named(_ name: String) -> Color {
        switch name {
        case "flame": flame
        case "watching": watching
        case "chart": chart
        case "spark": spark
        case "bookmark": bookmark
        case "series": series
        case "trend": trend
        case "library": library
        case "calendar": calendar
        default: addon
        }
    }
}

extension DS.Coach {
    /// Cuánto espera un aviso a que la pantalla se acomode antes de salir.
    static let wait: Duration = .milliseconds(1200)
}

/// Las historias en el encabezado de Inicio (HE1-B, Fernando, 4 nov 2026): en reposo, dos círculos se asoman en la orilla
/// derecha a la altura de «Todo · Películas · Series»; al deslizar a la izquierda, las historias ocupan todo el encabezado; al
/// bajar, se achican en su mismo lugar y pierden el nombre.
extension DS {
    /// SX1: el selector de Inicio. Cerrado, cada ícono mide `closed`; abierto crece a `open` para tocarlo fácil.
    enum KindPill {
        static let closed: CGFloat = 34, open: CGFloat = 42
        /// En el renglón de controles de una lista (R1): cabe con el nombre de lo elegido (KT1).
        static let dense: CGFloat = 38
        /// Lo que llega nace de este tamaño junto a lo que ves (nunca de la nada: antes 0.4, un brinco); al apretar un ícono se
        /// hunde a `pressed` (tantito: es respuesta al dedo, no un golpe).
        static let enterScale: CGFloat = 0.8, pressed: CGFloat = 0.92   // ds-exception: escalas
        /// El ícono de series es más ancho que los otros dos; así se ven del mismo tamaño.
        static let seriesOptical: CGFloat = 0.86   // ds-exception: escala óptica
        /// Cada opción que llega entra este tiempo después de la anterior, empezando por la más cercana a lo que ves.
        static let stagger: Double = 0.04
        /// Lo que la pastilla se queda abierta tras elegir: el círculo llega, se ve un momento en su lugar y entonces se recoge
        /// (Fernando, 13 nov 2026: «debería pasar un poquito más tiempo antes de volverse a comprimir»; antes 240 ms). En ese
        /// momento se lee el nombre de lo elegido, por eso alcanza para leer una palabra.
        static let settle: Duration = .milliseconds(1100)
        /// El círculo blanco es este tanto más chico que su lugar, por lado: cabe dentro de la pastilla con aire.
        static let markInset = DS.Space.s1 / 2
        /// El aire entre la orilla de la pastilla y el nombre de lo elegido (KT2).
        static let nameInset = DS.Space.s3
        /// La pastilla abre, viaja y se recoge con las curvas de siempre (`DS.Motion.grow`/`fold`), a este paso: más pausada,
        /// para que se sienta suave (Fernando, 13 nov 2026).
        static let pace = 0.8   // ds-exception: velocidad relativa de una animación
        /// Al cerrar, la cápsula de al lado regresa este tanto después: cuando la pastilla ya le dejó el lugar.
        static let returnDelay: Double = 0.1
        /// Más angosto que esto (iPhone SE, mini), tu foto también se hace a un lado mientras eliges.
        static let narrowScreen: CGFloat = 390
    }

    enum HomeStories {
        /// El círculo encogido al bajar (el normal es `DS.Story.ring`).
        static let compactRing: CGFloat = 40, compactTile: CGFloat = 32
        /// HH3: el círculo de historia dentro de la cápsula, del alto de tu foto.
        static let capsuleRing: CGFloat = 28, capsuleTile: CGFloat = 22
        /// HH2: cuánto crece tu foto al latir una vez.
        static let pulse: CGFloat = 1.12   // ds-exception: escala, no un tamaño
        /// HH2: cuánto espera para latir al llegar, y cuánto dura crecida.
        static let pulseDelay: Duration = .milliseconds(600), pulseHold: Duration = .milliseconds(250)
        /// Deslizar más de esta fracción del ancho (o rápido) abre o cierra.
        static let commit: CGFloat = 0.28   // ds-exception: fracción del ancho, no un espacio
        /// Lo que sale se aleja un poco y se apaga, para que se lea la profundidad (no se va entero de golpe).
        static let away: CGFloat = 0.35   // ds-exception: fracción del ancho del encabezado
        /// Cuánto hay que bajar para que el encabezado se encoja, y hasta dónde hay que subir para que vuelva a crecer: el margen
        /// es más grande que lo que cambia de alto el encabezado, así nunca rebota entre los dos.
        static let collapseAt: CGFloat = 96, expandAt: CGFloat = 16
    }
}

/// Las escenas de las historias (versión final, 4 nov 2026): la pantalla de la app en miniatura, un dedo fantasma y lo que
/// pasa. Medidas en proporción de la escena; el ritmo, en compases.
extension DS {
    enum Scene {
        /// El ancho de la miniatura sobre su alto (un iPhone).
        static let phoneAspect: CGFloat = 0.52   // ds-exception: proporción de un iPhone
        /// Lo más alta que crece la escena en la tarjeta.
        static let maxHeight: CGFloat = 420
        /// El dedo fantasma: un círculo del tamaño de una yema.
        static let finger: CGFloat = 26
        /// Un compás: cada cuánto pasa lo siguiente dentro de la escena.
        static let beat: Duration = .milliseconds(900)
        /// Lo que se toca se hunde a esto; lo que se levanta crece a esto.
        static let pressed: CGFloat = 0.94, lifted: CGFloat = 1.06   // ds-exception: escala del toque (física de la escena)
        /// Los renglones de texto fingido (las líneas grises de una ficha).
        static let line: CGFloat = 6
        /// El texto llega después del gesto: el título aparece a esta fracción de la tarjeta.
        static let textAt = 0.35
    }
}

/// Las escenas de la guía de bienvenida (revisión del director, 4 nov 2026).
extension DS {
    enum GuideScene {
        /// Tu órbita (G2): el anillo, el planeta y las miniaturas que entran.
        static let orbitWidth: CGFloat = 240, orbitHeight: CGFloat = 74, planet: CGFloat = 46, mini: CGFloat = 42
        /// Tu Inicio en miniatura (G7): sus pósters, los logos y cuánto crece al volverse el de verdad.
        static let homePoster: CGFloat = 78, logo: CGFloat = 44
        static let grow: CGFloat = 1.5   // ds-exception: el Inicio en miniatura crece a pantalla completa
        static let landStep = 0.07
        /// La luna que viaja de pantalla en pantalla, y dónde queda el arco de avance (fracción del ancho).
        static let flight = 0.45, fadeOut = 0.25
        static let arcStart = 0.08, arcSpan = 0.62   // ds-exception: el arco de arriba en fracción del ancho
        /// Los pósters de G2 entran cayendo, uno tras otro (vienen de la órbita de la bienvenida).
        static let dropStep = 0.04
        /// Los objetos de «¿Qué ya tienes?» (G3).
        static let object: CGFloat = 52
        /// La escena viva de «Ver aquí mismo» (G4).
        static let sceneHeight: CGFloat = 220
        /// Al elegir, el póster se voltea.
        static let flip: Double = 180   // ds-exception: media vuelta del póster
    }
}
