import SwiftUI
import OrbitalCore
import OrbitalModels

/// El encuadre del video (llenar o ajustar) por orientación, el pellizco en curso y la píldora que lo anuncia.
/// Vive aparte de `PlayerScreen` (ver `PlayerDragState`): las vistas que lo leen se vuelven a pintar con cada cambio.
@MainActor
@Observable
final class PlayerZoomState {
    /// El zoom del video (botón de arriba y pellizco, como Infuse); se recuerda en ajustes. `zoomToast`: el aviso con su nombre.
    /// El zoom de cada sentido: el de horizontal se recuerda (Ajustes); el de vertical arranca siempre en el cuadro completo. Antes
    /// era uno solo y al volver de horizontal con «Llenar» el video quedaba en vertical a pantalla completa, recortado.
    var landscapeZoom: VideoZoom = .fit
    var portraitZoom: VideoZoom = .fit
    /// Cuándo cambió el sentido: un pellizco que termina justo después (los pulgares al girar) no cuenta.
    var rotatedAt = Date.distantPast
    var pinchStartedAt: Date?
    var zoomBeforePinch: (zoom: VideoZoom, at: Date)?
    var lastPinch = 0.0
    var zoomToast: VideoZoom?
    var zoomToastTask: Task<Void, Never>?
}
