import Foundation

/// Base de los modelos de vista: avisa cuando algo cambió. La app conecta esto a SwiftUI (un
/// `ObservableObject` que reenvía el aviso); aquí no se importa SwiftUI ni Combine, así todo se prueba en Linux y en Mac.
@MainActor
open class ObservableModel {
    public final class Subscription {
        private let cancelAction: () -> Void
        init(_ cancel: @escaping () -> Void) { cancelAction = cancel }
        public func cancel() { cancelAction() }
        deinit { cancelAction() }
    }

    private var observers: [UUID: () -> Void] = [:]
    public init() {}

    /// Se llama cada vez que cambia algo publicado. Guarda la suscripción mientras la quieras.
    public func onChange(_ handler: @escaping () -> Void) -> Subscription {
        let id = UUID()
        observers[id] = handler
        return Subscription { [weak self] in Task { @MainActor in self?.observers[id] = nil } }
    }

    public final func changed() { for handler in observers.values { handler() } }
}
