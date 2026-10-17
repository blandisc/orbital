import AVFoundation
import MediaPlayer
import SwiftUI

/// Los botones de volumen del iPhone como botones del control (como el control del Apple TV): mientras esta vista está en
/// pantalla, subir o bajar llama a `onPress` y el volumen del iPhone se regresa a donde estaba (no cambia, ni sale el aviso
/// del sistema: lo tapa un `MPVolumeView` invisible). Al irse, el volumen queda como lo tenías.
struct HardwareVolumeButtons: UIViewRepresentable {
    /// `true` al subir, `false` al bajar.
    let onPress: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPress: onPress) }

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 1, height: 1))   // fuera de la vista: solo tapa el aviso
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        context.coordinator.attach(view)
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) { context.coordinator.onPress = onPress }

    static func dismantleUIView(_ view: MPVolumeView, coordinator: Coordinator) { coordinator.detach() }

    @MainActor
    final class Coordinator: NSObject {
        var onPress: (Bool) -> Void
        private var observation: NSKeyValueObservation?
        private weak var slider: UISlider?
        /// El volumen al que se regresa después de cada botón, y el que tenías al abrir (se devuelve al cerrar).
        private var base: Float = 0.5
        private var original: Float?
        private var resetting = false

        init(onPress: @escaping (Bool) -> Void) { self.onPress = onPress }

        func attach(_ view: MPVolumeView) {
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(true)   // sin sesión activa iOS no avisa del volumen
            original = session.outputVolume
            base = session.outputVolume
            // En un extremo (0 o 100 %) un botón no cambiaría nada: se acerca al centro (y se devuelve al cerrar).
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.slider = view.subviews.compactMap { $0 as? UISlider }.first
                if self.base < Self.edge || self.base > 1 - Self.edge { self.set(Self.middle); self.base = Self.middle }
            }
            observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                Task { @MainActor in self?.changed(value) }
            }
        }

        private func changed(_ value: Float) {
            if resetting { resetting = false; return }
            guard abs(value - base) > Self.noise else { return }
            onPress(value > base)
            set(base)
        }

        private func set(_ value: Float) {
            // Solo si de verdad cambia: si no, iOS no avisa y el siguiente botón se tomaría por el regreso.
            guard let slider, abs(AVAudioSession.sharedInstance().outputVolume - value) > Self.noise else { return }
            resetting = true
            slider.value = value
            slider.sendActions(for: .valueChanged)
        }

        func detach() {
            observation?.invalidate()
            observation = nil
            if let original, abs(original - base) > Self.noise { set(original) }
        }

        static let edge: Float = 0.07, middle: Float = 0.5, noise: Float = 0.001
    }
}
