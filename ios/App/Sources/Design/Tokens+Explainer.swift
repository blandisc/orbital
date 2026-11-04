import SwiftUI

extension DS {
    /// «¿Qué es esto?» (`DSExplainerCard`, `DebridFlowStrip`): el lado del cuadro de color de cada tarjeta, el de los tres
    /// pasos animados, lo tenue del relleno (el color va en el símbolo) y lo que dura cada paso de la animación.
    enum Explainer {
        static let tile: CGFloat = 44, flowTile: CGFloat = 56
        static let tileFill = 0.18
        /// Lo más que crece el cuadro con la letra de accesibilidad (sin tope tapaba la hoja).
        static let maxScale: CGFloat = 1.4
        /// Los pasos que no son el de ahora, un poco más chicos: el de ahora «brinca» al frente.
        static let restScale: CGFloat = 0.92
        static let step: Duration = .seconds(1.6)
        /// RX3-A · «Así funciona» espera esto antes de salir: que se vea primero lo que la trajo (la versión «↓ Por pedir»).
        static let introDelay: Duration = .milliseconds(600)
    }
}
