import AVFoundation
import Speech
import SwiftUI

/// El micrófono del control de tu Orbital: escucha una orden en español (o inglés, según la app), la va escribiendo mientras
/// hablas y se detiene sola cuando dejas de hablar. Luego dice en voz alta lo que contestó la consola.
@MainActor
final class SpeechInput: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var listening = false
    /// Sin permiso de micrófono o de dictado: se avisa en vez del botón.
    @Published private(set) var denied = false
    /// No se oyó nada (o el reconocimiento falló): se dice, en vez de quedarse callado.
    @Published private(set) var heardNothing = false

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silence: Task<Void, Never>?
    private var onFinish: ((String) -> Void)?
    private let voice = AVSpeechSynthesizer()
    /// Pidiendo permisos: un segundo toque en ese rato no arranca otra vez (instalaría dos veces el micrófono y truena).
    private var starting = false

    /// Cuánto silencio cierra la orden (s), y cuánto se espera a que empieces a hablar.
    static let silenceSeconds = 1.4
    static let firstWordSeconds = 5.0

    /// `hints`: nombres que es probable que digas (lo que se ve en la TV, tu biblioteca): el dictado los escribe mejor.
    func start(language: String, hints: [String] = [], onFinish: @escaping (String) -> Void) async {
        guard !listening, !starting else { return }
        starting = true
        defer { starting = false }
        // Si todavía está diciendo la respuesta anterior, se calla: si no, el micrófono se oye a sí mismo.
        voice.stopSpeaking(at: .immediate)
        self.onFinish = onFinish
        let speechOK = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard speechOK, micOK, let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.hasPrefix("en") ? "en-US" : "es-MX")),
              recognizer.isAvailable else { denied = true; return }
        denied = false
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // Sin exigir el reconocimiento en el iPhone: si el español no está descargado para eso, fallaba sin decir nada.
            // iOS usa el del teléfono cuando puede.
            request.requiresOnDeviceRecognition = false
            request.taskHint = .search
            request.contextualStrings = Array(hints.prefix(100))
            self.request = request
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in request.append(buffer) }
            engine.prepare()
            try engine.start()
            transcript = ""
            heardNothing = false
            listening = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString; self.armSilence(Self.silenceSeconds) }
                    if error != nil || result?.isFinal == true { self.finish() }
                }
            }
            armSilence(Self.firstWordSeconds)
        } catch {
            stopEngine()
            denied = true
        }
    }

    /// Terminar ya (otro toque al micrófono): manda lo que se alcanzó a oír.
    func finish() {
        guard listening else { return }
        stopEngine()
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { heardNothing = true } else { onFinish?(text) }
        onFinish = nil
    }

    /// Cerrar sin mandar nada (se cerró la hoja): el micrófono no se queda abierto.
    func cancel() {
        onFinish = nil
        stopEngine()
        voice.stopSpeaking(at: .immediate)
    }

    /// La respuesta de la consola, dicha en voz alta (como Alexa).
    func speak(_ text: String, language: String) {
        guard !text.isEmpty, !listening else { return }
        // Para hablar, la sesión de reproducción (la de grabar, en modo medición, la decía casi sin volumen).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.hasPrefix("en") ? "en-US" : "es-MX")
        voice.speak(utterance)
    }

    private func armSilence(_ seconds: Double) {
        silence?.cancel()
        silence = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func stopEngine() {
        silence?.cancel()
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil
        listening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        NotificationCenter.default.post(name: .orbitalAudioReleased, object: nil)
    }
}
