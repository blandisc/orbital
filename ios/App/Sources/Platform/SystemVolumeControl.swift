import SwiftUI
import MediaPlayer
import AVFoundation

/// Pone el volumen del sistema sin que aparezca el HUD nativo encima del video: la única vía documentada es un
/// `MPVolumeView` (minúsculo, fuera de la vista) cuyo control interno se mueve a mano. Es la misma vía que usan
/// Infuse y VLC. `volume` se pone a un valor para pedir el cambio; en cuanto se aplica, vuelve a `nil`.
///
/// Como el HUD de iOS no sale, los botones de volumen del iPhone avisan por `onChange` (con el nivel nuevo, 0…1) para que el
/// reproductor enseñe su propio indicador.
struct SystemVolumeControl: UIViewRepresentable {
    @Binding var volume: Float?
    var onChange: (Float) -> Void = { _ in }
    /// Lo mínimo para seguir «visible» para iOS.
    private static let nearlyInvisible: CGFloat = 0.0001

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsVolumeSlider = true
        // Tiene que estar en pantalla para que iOS no enseñe su HUD, pero no se debe ver: en iOS 26 su barra se pintaba como
        // una cápsula blanca en medio del video. Casi transparente (con 0 iOS lo da por oculto y vuelve a salir el HUD).
        view.alpha = Self.nearlyInvisible
        view.isUserInteractionEnabled = false
        context.coordinator.observe()
        return view
    }

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    static func dismantleUIView(_ view: MPVolumeView, coordinator: Coordinator) { coordinator.stop() }

    /// Escucha el volumen del sistema (los botones del iPhone, el Centro de control, unos audífonos).
    @MainActor
    final class Coordinator: NSObject {
        var onChange: (Float) -> Void
        private var observation: NSKeyValueObservation?

        init(onChange: @escaping (Float) -> Void) { self.onChange = onChange }

        func observe() {
            observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                Task { @MainActor in self?.onChange(value) }
            }
        }

        func stop() { observation?.invalidate(); observation = nil }
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {
        context.coordinator.onChange = onChange
        guard let volume, let slider = view.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.value = volume
        DispatchQueue.main.async { self.volume = nil }   // ya se aplicó: no se repite en el siguiente refresco
    }
}
