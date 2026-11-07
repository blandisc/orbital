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

    /// Dentro de `coalescing` los cambios se juntan: se avisa una sola vez al final (una pasada de la vista, no una por campo).
    private var coalesceDepth = 0
    private var pendingChange = false

    /// Junta los cambios de `body` en un solo aviso: la ficha ponía 6–8 campos seguidos al hallar la versión y cada uno
    /// volvía a pintar toda la vista mientras te desplazabas (los tirones de «Buscando versión…», 6 nov).
    public final func coalescing<T>(_ body: () throws -> T) rethrows -> T {
        coalesceDepth += 1
        defer {
            coalesceDepth -= 1
            if coalesceDepth == 0, pendingChange { pendingChange = false; changed() }
        }
        return try body()
    }

    public final func changed() {
        if coalesceDepth > 0 { pendingChange = true; return }
        registrar.withMutation(of: self, keyPath: \.version) { version &+= 1 }
        for handler in observers.values { handler() }
    }
}
