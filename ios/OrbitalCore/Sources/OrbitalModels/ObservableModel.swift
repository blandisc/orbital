import Foundation
import Observation

/// Base de los modelos de vista: avisa cuando algo cambió. Dos vías, las dos sin SwiftUI ni Combine (así todo se prueba en
/// Linux y en Mac): `onChange` para quien escucha desde código, y Observation (`track()`) para las vistas: la que lee
/// `track()` mientras se pinta se vuelve a pintar en el siguiente `changed()`.
@MainActor
open class ObservableModel: Observable {
    public final class Subscription {
        private let cancelAction: () -> Void
        init(_ cancel: @escaping () -> Void) { cancelAction = cancel }
        public func cancel() { cancelAction() }
        deinit { cancelAction() }
    }

    private var observers: [UUID: () -> Void] = [:]
    private let registrar = ObservationRegistrar()
    /// Cuántas veces ha cambiado: lo único que sigue Observation (cualquier cambio vuelve a pintar a quien lo leyó, como antes).
    private var version = 0
    public init() {}

    /// Se llama cada vez que cambia algo publicado. Guarda la suscripción mientras la quieras.
    public func onChange(_ handler: @escaping () -> Void) -> Subscription {
        let id = UUID()
        observers[id] = handler
        return Subscription { [weak self] in Task { @MainActor in self?.observers[id] = nil } }
    }

    /// Registra la lectura del modelo en el seguimiento de Observation en curso (la vista que se está pintando).
    public final func track() { registrar.access(self, keyPath: \.version) }

    public final func changed() {
        registrar.withMutation(of: self, keyPath: \.version) { version &+= 1 }
        for handler in observers.values { handler() }
    }
}
