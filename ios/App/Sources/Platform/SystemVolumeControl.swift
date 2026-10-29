import SwiftUI
import MediaPlayer

/// Pone el volumen del sistema sin que aparezca el HUD nativo encima del video: la única vía documentada es un
/// `MPVolumeView` (minúsculo, fuera de la vista) cuyo control interno se mueve a mano. Es la misma vía que usan
/// Infuse y VLC. `volume` se pone a un valor para pedir el cambio; en cuanto se aplica, vuelve a `nil`.
struct SystemVolumeControl: UIViewRepresentable {
    @Binding var volume: Float?
    /// Lo mínimo para seguir «visible» para iOS.
    private static let nearlyInvisible: CGFloat = 0.0001

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsVolumeSlider = true
        // Tiene que estar en pantalla para que iOS no enseñe su HUD, pero no se debe ver: en iOS 26 su barra se pintaba como
        // una cápsula blanca en medio del video. Casi transparente (con 0 iOS lo da por oculto y vuelve a salir el HUD).
        view.alpha = Self.nearlyInvisible
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {
        guard let volume, let slider = view.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.value = volume
        DispatchQueue.main.async { self.volume = nil }   // ya se aplicó: no se repite en el siguiente refresco
    }
}
