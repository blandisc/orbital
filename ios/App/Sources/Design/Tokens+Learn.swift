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
        /// Cuánto dura cada tarjeta: 5 s, o 7 si su texto es largo (más de `longText` letras); avanza en `ticks` pasos.
        static let card: Duration = .seconds(5), longCard: Duration = .seconds(7)
        static let longText = 90, ticks = 60
        /// El símbolo grande de una tarjeta y la mano fantasma que repite el gesto.
        static let symbol: CGFloat = 96, hand: CGFloat = 44
        static let handTravel: CGFloat = 40
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
