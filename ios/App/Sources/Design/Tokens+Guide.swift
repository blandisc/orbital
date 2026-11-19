import SwiftUI

/// Tokens de la guía de la primera vez (antes en `Tokens+Screens.swift`, que llegó a su tope de líneas el 18 nov 2026).
extension DS {
    /// La guía de la primera vez: el grueso de las rayitas de los pasos, el ícono de cada pieza y el número de cada paso.
    enum Guide {
        /// El póster de la sugerencia de «Trajimos lo tuyo».
        static let whyPoster = CGSize(width: 40, height: 60)
        /// «¿Qué plataformas tienes?»: el póster de la ficha de ejemplo, el hueco del logo (y su contorno punteado) y la
        /// altura de cada casilla (54 pt: más que el mínimo para tocar).
        static let platformPoster = CGSize(width: 44, height: 66)
        static let slot: CGFloat = 28, slotDash: [CGFloat] = [3, 3.4], platformTile: CGFloat = 54
        static let readyPoster = CGSize(width: 62, height: 93)
        /// TK-L2: tu foto (la inicial en el anillo de la marca), su palomita y la rayita entre los tres números.
        static let avatar: CGFloat = 104, avatarBadge: CGFloat = 32, countDivider: CGFloat = 36
        /// La foto crece con un resorte pequeño; la palomita, con el de la marca; los números cuentan a la vez.
        static let avatarIn: Animation = .spring(duration: 0.5, bounce: 0.25), badgePop: Animation = .spring(duration: 0.55, bounce: 0.45)
        static let countUp: Animation = .easeOut(duration: 0.6)
        /// «Listo, <nombre>» (TK-L2): tu inicial, 0.12 s el texto, 0.16 s el sello y 0.04 s después cuentan los números.
        static let textAfterAvatar: Duration = .milliseconds(120), badgeAfterText: Duration = .milliseconds(160), countAfterBadge: Duration = .milliseconds(40)
        static let pieceIcon: CGFloat = 40
        static let stepNumber: CGFloat = 28
        /// El código de Trakt: separación entre letras (se lee de lejos, desde la TV).
        static let codeTracking: CGFloat = 4
        /// Lo más ancho que crece una página de la guía (iPad, Mac): se lee como una columna.
        static var readable: CGFloat { Mac.sized(560) }   // en la Mac crece con la letra (MAC-A)
        /// La ilustración de una página del tutorial de Orbital (`GuideArt`): su alto y el del ícono grande.
        static let artHeight: CGFloat = 220, artSymbol: CGFloat = 88
        /// El recuadro que apunta al código de la TV en el lector (`QRScanner`).
        static let scanFrame: CGFloat = 240
    }
}
