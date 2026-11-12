import AVFoundation
import MediaPlayer
import SwiftUI

extension Notification.Name {
    /// La voz del control soltó la sesión de audio (al terminar de escuchar o de hablar).
    static let orbitalAudioReleased = Notification.Name("orbital.audio-released")
}

/// Los botones de volumen del iPhone como botones del control (como el control del Apple TV): mientras esta vista está en
/// pantalla, subir o bajar llama a `onPress` y el volumen del iPhone se regresa a donde estaba (no cambia, ni sale el aviso
/// del sistema: lo tapa un `MPVolumeView` invisible). Al irse, el volumen queda como lo tenías.
///
/// Con el reproductor en pantalla los botones son del video (`yieldsToPlayer`): no se tocan ni se regresan. Antes, si el control
/// seguía montado detrás del reproductor, cada botón se deshacía al instante y el volumen del iPhone no subía ni bajaba (31 oct).
///
/// Regla «El volumen no se mueve solo» (`docs/ios-interfaz.md`, Fernando, 11 nov 2026: «cuando abro Orbital como que aparece
/// la barra de volumen, como si hubiera cambiado el volumen»): la app solo mueve el volumen del iPhone con su tapa del aviso
/// ya puesta en la ventana (nunca al montar ni al desmontar la vista), y al volver a la app el volumen que encuentre es el
/// nuevo punto de partida: no cuenta como botón ni se regresa.
struct HardwareVolumeButtons: UIViewRepresentable {
    /// `true` al subir, `false` al bajar.
    let onPress: (Bool) -> Void
    /// Hay un reproductor en pantalla: los botones de volumen son suyos.
    @MainActor static var yieldsToPlayer = false

    func makeCoordinator() -> Coordinator { Coordinator(onPress: onPress) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        context.coordinator.attach()
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { context.coordinator.onPress = onPress }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.detach() }

    @MainActor
    final class Coordinator: NSObject {
        var onPress: (Bool) -> Void
        private var observation: NSKeyValueObservation?
        private var observers: [NSObjectProtocol] = []
        /// La tapa del aviso del sistema. Vive en la ventana (no en la hoja del control) para seguir puesta mientras se
        /// regresa el volumen al cerrar: dentro de la hoja ya se había ido y el aviso salía.
        private var cover: MPVolumeView?
        private var slider: UISlider? { cover?.subviews.compactMap { $0 as? UISlider }.first }
        /// El volumen al que se regresa después de cada botón, y el que tenías al abrir (se devuelve al cerrar).
        private var base: Float = 0.5
        private var original: Float?
        private var resetting = false
        /// La app no está al frente: lo que cambie el volumen no es un botón del control.
        private var away = false

        init(onPress: @escaping (Bool) -> Void) { self.onPress = onPress }

        func attach() {
            let session = AVAudioSession.sharedInstance()
            // Mezclando con lo que suene (tu música no se para por abrir el control) y activa: sin sesión activa iOS no avisa
            // del volumen.
            Self.activate()
            let center = NotificationCenter.default
            // Tras la voz del control (que suelta la sesión), se vuelve a tomar: si no, los botones volvían a ser del iPhone.
            observers.append(center.addObserver(forName: .orbitalAudioReleased, object: nil, queue: .main) { _ in
                Task { @MainActor in if !HardwareVolumeButtons.yieldsToPlayer { Self.activate() } }
            })
            // Salir y volver a la app con el control abierto: lo que haya pasado con el volumen afuera (los botones, unos
            // audífonos, otra app) no es un botón del control. Antes se tomaba por uno: movía la TV y regresaba el volumen.
            observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.away = true }
            })
            observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.cameBack() }
            })
            original = session.outputVolume
            base = session.outputVolume
            let cover = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 1, height: 1))   // fuera de la vista: solo tapa el aviso
            cover.alpha = 0.01
            cover.isUserInteractionEnabled = false
            Self.window?.addSubview(cover)
            self.cover = cover
            // En un extremo (0 o 100 %) un botón no cambiaría nada: se acerca al centro (y se devuelve al cerrar). Con la
            // tapa ya asentada en la ventana: movido antes, salía el aviso del sistema.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle) { [weak self] in self?.leaveTheEdge() }
            observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                Task { @MainActor in self?.changed(value) }
            }
        }

        private func leaveTheEdge() {
            guard cover != nil, !away, !HardwareVolumeButtons.yieldsToPlayer else { return }
            if base < Self.edge || base > 1 - Self.edge { set(Self.middle); base = Self.middle }
        }

        private func cameBack() {
            away = false
            guard !HardwareVolumeButtons.yieldsToPlayer else { return }
            Self.activate()
            let now = AVAudioSession.sharedInstance().outputVolume
            // Cambió mientras no estabas: ese es ahora tu volumen (el de partida y el que se deja al cerrar).
            if abs(now - base) > Self.noise { base = now; original = now; resetting = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle) { [weak self] in self?.leaveTheEdge() }
        }

        private func changed(_ value: Float) {
            if resetting { resetting = false; return }
            // El volumen es del video, o cambió con la app atrás: se toma como el nuevo punto de partida.
            if HardwareVolumeButtons.yieldsToPlayer || away { base = value; original = value; return }
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

        static func activate() {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? session.setActive(true)
        }

        func detach() {
            observation?.invalidate()
            observation = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            let cover = self.cover
            // La tapa se queda un momento más en la ventana: quitada junto con el regreso del volumen, el aviso salía.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle * 2) { cover?.removeFromSuperview() }
            // Con el video en pantalla la sesión es suya: soltarla (o regresar el volumen) le quitaba el sonido o el volumen.
            guard !HardwareVolumeButtons.yieldsToPlayer else { self.cover = nil; return }
            if let original, abs(original - base) > Self.noise { set(original) }
            self.cover = nil
            // Se suelta la sesión avisando a las demás apps (tu música sigue, sin cortarse); el reproductor pone la suya al abrir.
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }

        private static var window: UIWindow? {
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            return windows.first(where: \.isKeyWindow) ?? windows.first
        }

        static let edge: Float = 0.07, middle: Float = 0.5, noise: Float = 0.001
        /// Lo que tarda la tapa en asentarse en la ventana antes de mover el volumen sin que salga el aviso.
        static let settle: TimeInterval = 0.35
    }
}
