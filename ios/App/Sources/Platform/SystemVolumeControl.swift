import SwiftUI
import MediaPlayer

/// Pone el volumen del sistema sin que aparezca el HUD nativo encima del video: la única vía documentada es un
/// `MPVolumeView` (minúsculo, fuera de la vista) cuyo control interno se mueve a mano. Es la misma vía que usan
/// Infuse y VLC. `volume` se pone a un valor para pedir el cambio; en cuanto se aplica, vuelve a `nil`.
struct SystemVolumeControl: UIViewRepresentable {
    @Binding var volume: Float?

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.showsVolumeSlider = true
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {
        guard let volume, let slider = view.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.value = volume
        DispatchQueue.main.async { self.volume = nil }   // ya se aplicó: no se repite en el siguiente refresco
    }
}
