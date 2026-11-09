import Foundation

/// Los topes de tiempo de una búsqueda de versiones (Fernando, 9 nov: «Los Simpson» 8x3 y 7x2 se quedaron buscando para
/// siempre). Cada espera tiene su tope y la búsqueda entera también: lo que no llega a tiempo cuenta como «no contestó»,
/// nunca como una espera sin fin. Las pruebas los achican.
public struct SearchLimits: Sendable {
    /// Lo más que se espera a un complemento, aunque su servidor no deje de gotear ni haga caso a la cancelación.
    public var perAddon: TimeInterval
    /// El origen del título (TMDB y Cinemeta): sin él se ordena igual, solo sin saber su idioma original.
    public var origin: TimeInterval
    /// El enlace de un pedido listo de Real-Debrid que Torrentio no lista.
    public var readyLink: TimeInterval
    /// La búsqueda entera de un video (la lista de complementos más sus respuestas), también para quien se une a una que
    /// ya iba en camino (la de la ficha, «calentar desde la ficha»).
    public var total: TimeInterval
    public init(perAddon: TimeInterval = StreamFinder.slowAfter + 2, origin: TimeInterval = 4, readyLink: TimeInterval = 6, total: TimeInterval = 22) {
        self.perAddon = perAddon; self.origin = origin; self.readyLink = readyLink; self.total = total
    }
}

/// Espera algo con tope: pasado el tiempo (o si quien espera se cancela) regresa `fallback` y cancela el trabajo. A
/// diferencia de un grupo de tareas, no se queda esperando a un trabajo que ignora la cancelación.
enum Deadline {
    static func within<T: Sendable>(_ seconds: TimeInterval, or fallback: T, _ work: @escaping @Sendable () async -> T) async -> T {
        let once = Once<T>()
        let worker = Task { once.resume(await work()) }
        let timer = Task { try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)); once.resume(fallback) }
        let value = await withTaskCancellationHandler {
            await withCheckedContinuation { once.attach($0) }
        } onCancel: { once.resume(fallback) }
        worker.cancel(); timer.cancel()
        return value
    }

    /// Lo primero que llega gana (el trabajo, el tope o la cancelación); lo demás se ignora.
    private final class Once<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var waiting: CheckedContinuation<T, Never>?
        private var value: T?
        private var done = false

        func resume(_ result: T) {
            let target: CheckedContinuation<T, Never>? = lock.withLock {
                guard !done else { return nil }
                done = true
                if let waiting { self.waiting = nil; return waiting }
                value = result
                return nil
            }
            target?.resume(returning: result)
        }

        func attach(_ continuation: CheckedContinuation<T, Never>) {
            let ready: T? = lock.withLock {
                if done, let value { return value }
                waiting = continuation
                return nil
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }
}
