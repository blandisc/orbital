import SwiftUI
import MediaPlayer
import AVFoundation

/// Pone el volumen del sistema sin que aparezca el HUD nativo encima del video: la única vía documentada es un
/// `MPVolumeView` (minúsculo, fuera de la vista) cuyo control interno se mueve a mano. Es la misma vía que usan
/// Infuse y VLC. El volumen se pide con `SystemVolume.set` (fuera del estado de SwiftUI).
///
/// Como el HUD de iOS no sale, los botones de volumen del iPhone avisan por `onChange` (con el nivel nuevo, 0…1) para que el
/// reproductor enseñe su propio indicador.
struct SystemVolumeControl: UIViewRepresentable {
    let volume: SystemVolume
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
        DispatchQueue.main.async { volume.slider = view.subviews.compactMap { $0 as? UISlider }.first }   // el control interno llega después
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
        if volume.slider == nil { volume.slider = view.subviews.compactMap { $0 as? UISlider }.first }
    }
}

/// Mover el volumen del sistema al deslizar. Antes cada punto del dedo (unas 60 veces por segundo) era un cambio de volumen del
/// sistema y dos repintados del reproductor entero, y el audio se oía entrecortado (31 oct). Ahora va en pasos de 1/32 (más fino
/// que los 16 de los botones), solo cuando cambia de paso y sin pasar por el estado de SwiftUI.
@MainActor
final class SystemVolume {
    weak var slider: UISlider?
    private var applied: Float?
    static let steps: Float = 32

    func set(_ value: Float) {
        let step = (min(max(value, 0), 1) * Self.steps).rounded() / Self.steps
        guard step != applied, let slider else { return }
        applied = step
        slider.value = step
    }

    /// Al empezar a deslizar: el paso de partida es el volumen de ahora (lo pudieron cambiar los botones).
    func reset() { applied = nil }
}
