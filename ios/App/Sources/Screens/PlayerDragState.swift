import SwiftUI
import OrbitalModels

/// El estado del arrastre sobre el video (brillo, volumen, buscar arrastrando y el 2× al mantener), como en Infuse. Vive
/// aparte de `PlayerScreen` (que ya carga demasiado estado) y las vistas que lo leen se vuelven a pintar con cada cambio.
/// La aritmética (eje dominante, segundos por punto, brillo y volumen 0…1) sigue en `PlayerGestures` (OrbitalModels, con pruebas).
@MainActor
@Observable
final class PlayerDragState {
    var dragAxis: GestureAxis = .undecided
    var verticalKind: VerticalGesture?
    var brightnessAtDragStart: Double = 1
    var volumeAtDragStart: Double = 0
    var originalBrightness: Double = 1
    var indicator: (kind: VerticalGesture, symbol: String, value: Double)?
    /// Aparte de `indicator` (que se actualiza en cada punto del arrastre, sin animar) para que solo la entrada
    /// y la salida se animen; moverlo de golpe en cada cuadro se vería tembloroso.
    var indicatorVisible = false
    var indicatorHideTask: Task<Void, Never>?
    var seekPositionAtDragStart: Double?
    var seekPreview: Double?
    var isFastForwarding = false
    /// ×2 fijo: deslizaste hacia abajo hasta que vibró; sigue al soltar y un toque en la píldora lo quita.
    var fastForwardLocked = false
    /// El dedo sigue puesto después de la pulsación larga (el ×2 dura lo que dure el dedo, como TikTok).
    var fastForwardHolding = false
    /// El ×2 se quedó con este toque (aunque ya hayas deslizado hacia arriba para quitarlo): el arrastre del video no lo roba.
    var fastForwardOwnsTouch = false
    /// Cómo estaba al empezar a mantener: si ya iba fijo, el aviso dice deslizar hacia arriba para quitarlo.
    var fastForwardLockedAtStart = false
    var fastForwardToggledThisHold = false
    /// Dónde empezó el toque (el ×2 es del lado derecho, como YouTube; hacia abajo se mide desde aquí).
    var touchStartX: CGFloat?
    var touchStartY: CGFloat?
}
