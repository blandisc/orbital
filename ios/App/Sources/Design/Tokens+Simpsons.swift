import SwiftUI
import OrbitalCore

/// Los tokens de «Un Simpson al azar» (salieron de `Tokens+Screens.swift`, que ya pasaba su tope de líneas).
extension DS {
    /// «Un Simpson al azar»: la ruleta de episodios (ancho de cada imagen, espacio, cuánto gira y cuánto se queda el elegido
    /// antes de empezar), la dona y el amarillo de Los Simpson.
    enum Simpsons {
        // Un cambio de canal (≈2.4 s): aparece con rebote (0.25 s), tres clics con estática y su número de canal (~0.35 s),
        // se queda y brilla, se sostiene en el canal elegido (0.7 s) y la imagen crece despacio desde la pantalla hasta
        // llenar el iPhone (1.1 s, arranque suave y aterrizaje largo), una pausa breve con la imagen llena y entra el video.
        static let reelLength = 3
        /// Lo más que la tele sintoniza esperando las imágenes de los episodios (desde el Centro de control no estaban listas).
        static let imageWait: Double = 3
        /// Cuánto espera Inicio antes de preparar la ruleta (la ficha de ~650 KB no compite con el arranque).
        static let prefetchDelay: Double = 4
        static let appear: Double = 0.25, bounce: Double = 0.35, staticBurst: Double = 0.08, flip: Double = 0.1
        static let settle: Double = 0.15, flashOff: Double = 0.08, hold: Double = 0.7, zoom: Double = 1.1
        static let zoomRest: Double = 0.2   // la imagen ya llena, quieta un instante antes de que entre el reproductor
        /// Curva del crecimiento: sale lento, avanza y se posa sin frenazo (no «te la avienta»).
        static let zoomCurve = Animation.timingCurve(0.4, 0, 0.15, 1, duration: zoom)
        static let channels = [3, 7, 12]
        // La tele.
        static let screen: CGFloat = 220, screenAspect: CGFloat = 4 / 3, screenRadius: CGFloat = 28, screenFrame: CGFloat = 3   // ds-exception: la tele de Los Simpson se dibuja como el aparato
        static let tvRadius: CGFloat = 38, bezel: CGFloat = 18, tvGlow: CGFloat = 40   // ds-exception: la tele de Los Simpson se dibuja como el aparato
        static let knobSize: CGFloat = 24, knobMark: CGFloat = 3, knobTurn: Double = 45
        static let grilleLines = 4, grilleLine: CGFloat = 3, grilleGap: CGFloat = 4   // ds-exception: la tele de Los Simpson se dibuja como el aparato
        static let antennaWidth: CGFloat = 170, antennaHeight: CGFloat = 92, antennaLine: CGFloat = 3, antennaTip: CGFloat = 5
        static let antennaBase: CGFloat = 16, antennaWobble: Double = -4
        static let legSpan: CGFloat = 200, legWidth: CGFloat = 12, legHeight: CGFloat = 16
        static let appearScale: CGFloat = 0.82, tvBehind: CGFloat = 1.15, ghost: Double = 0.35, flash: Double = 0.35, osdGlow: CGFloat = 6
        static let staticLine: CGFloat = 3, captionHeight: CGFloat = 96, glow: CGFloat = 420
        static let amarillo = Color(red: 1, green: 0.85, blue: 0.12)    // el amarillo de Los Simpson
        static let tvBody = Color(red: 0.6, green: 0.42, blue: 0.74)    // la tele morada de la sala
        static let tvShade = Color(red: 0.42, green: 0.27, blue: 0.55)
        static let knob = Color(red: 0.3, green: 0.18, blue: 0.4)
        /// Las franjas de la pantalla de la tele del widget cuando la imagen es panorámica: negro, como una tele vieja.
        static let screenBars = Color.black
        static let antenna = Color(red: 0.62, green: 0.62, blue: 0.66)
        static let osd = Color(red: 0.35, green: 1, blue: 0.45)          // el número de canal verde de las teles viejas
    }
}
