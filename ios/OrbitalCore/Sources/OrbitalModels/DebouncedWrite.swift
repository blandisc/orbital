import Foundation

/// Guardar lo que escribes sin escribir el disco en cada tecla: se guarda cuando dejas de teclear un momento, y al
/// cerrar (`flush`) lo que faltaba. Antes las notas del modo acompañante escribían UserDefaults en cada tecla
/// (auditoría, 31 oct 2026, C8).
@MainActor
public final class DebouncedWrite<Value: Sendable> {
    public static var typingPause: Duration { .milliseconds(600) }
    private let delay: Duration
    private var pending: (value: Value, save: (Value) -> Void)?
    private var task: Task<Void, Never>?

    public init(delay: Duration = DebouncedWrite.typingPause) { self.delay = delay }

    public func schedule(_ value: Value, save: @escaping (Value) -> Void) {
        pending = (value, save)
        task?.cancel()
        let delay = delay
        task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Lo que faltaba, ya (al cerrar la hoja o cambiar de juego).
    public func flush() {
        task?.cancel(); task = nil
        guard let (value, save) = pending else { return }
        pending = nil
        save(value)
    }
}
