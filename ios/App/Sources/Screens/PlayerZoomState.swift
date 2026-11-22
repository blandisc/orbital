import SwiftUI
import OrbitalCore
import OrbitalModels

/// El encuadre del video (llenar o ajustar) por orientación, el pellizco en curso y la píldora que lo anuncia.
/// Vive aparte de `PlayerScreen` (ver `PlayerDragState`): las vistas que lo leen se vuelven a pintar con cada cambio.
@MainActor
@Observable
final class PlayerZoomState {
    /// El zoom del video (botón de arriba y pellizco, como Infuse); se recuerda en ajustes. `zoomToast`: el aviso con su nombre.
    /// El zoom de horizontal, que se recuerda (Ajustes). En vertical no hay zoom (`PlayerScreen.zoom`).
    var landscapeZoom: VideoZoom = .fit
    /// Cuándo cambió el sentido: un pellizco que termina justo después (los pulgares al girar) no cuenta.
    var rotatedAt = Date.distantPast
    var pinchStartedAt: Date?
    /// Mientras pellizcas: a qué modo vas si sueltas ahora (nil en la zona muerta). La guía de arriba lo dice en vivo.
    var pinching = false
    var pinchPreview: VideoZoom?
    /// Lo que el video crece con los dedos mientras pellizcas (nil sin pellizco). Lo lee solo `PinchScaled`.
    var pinchScale: CGFloat?
    var zoomBeforePinch: (zoom: VideoZoom, at: Date)?
    var lastPinch = 0.0
    var zoomToast: VideoZoom?
    var zoomToastTask: Task<Void, Never>?
}

/// El video al tamaño del pellizco en curso. Aparte para que cada movimiento de los dedos repinte solo el video, no el reproductor.
struct PinchScaled: ViewModifier {
    let framing: PlayerZoomState
    func body(content: Content) -> some View { content.scaleEffect(framing.pinchScale ?? 1) }
}
