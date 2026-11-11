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
    /// En un modelo que se observa por propiedad (`observesByProperty`) no hace nada: la vista sigue solo lo que lee (V9).
    public final func track() { if !observesByProperty { trackAll() } }
    /// Sigue TODO el modelo (cualquier `changed()` vuelve a pintar), también en uno que se observa por propiedad.
    public final func trackAll() { registrar.access(self, keyPath: \.version) }

    /// V9 (repintado fino): `true` en los modelos cuyas propiedades publicadas son todas `@Tracked` (o leen una que lo es).
    /// La vista que lee una de ellas se vuelve a pintar solo cuando cambia esa, no con cualquier cambio del modelo.
    open var observesByProperty: Bool { false }

    /// Lo que usan `@Tracked` y los modelos que avisan a mano por propiedad: la lectura y el cambio de una sola llave.
    public final func access<Model: ObservableModel, Member>(_ model: Model, _ keyPath: KeyPath<Model, Member>) {
        registrar.access(model, keyPath: keyPath)
    }
    public final func mutate<Model: ObservableModel, Member>(_ model: Model, _ keyPath: KeyPath<Model, Member>, _ apply: () -> Void) {
        registrar.withMutation(of: model, keyPath: keyPath, apply)
    }

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
        notifyListeners()
    }

    /// Solo a quien escucha desde código (`onChange`), sin volver a pintar a quien sigue todo el modelo: lo usa una propiedad
    /// `@Tracked(alone: true)`, que avisa a las vistas por su propia llave.
    public final func notifyListeners() { for handler in observers.values { handler() } }
}

/// Una propiedad publicada que avisa sola (V9): la vista que la lee se vuelve a pintar solo cuando ESTA cambia, y quien
/// escucha todo el modelo (`onChange`, `trackAll`) se entera igual que antes con `changed()`. Con un valor `Equatable`, poner
/// el mismo valor no avisa (como el `didSet { if oldValue != … }` de antes); `always: true` avisa siempre.
@MainActor
@propertyWrapper
public struct Tracked<Value> {
    private var value: Value
    private let same: ((Value, Value) -> Bool)?
    /// Solo avisa por su llave (y a `onChange`): quien sigue todo el modelo (`track()`, `trackAll()`) no se vuelve a pintar.
    private let alone: Bool

    public init(wrappedValue: Value) { value = wrappedValue; same = nil; alone = false }
    public init(wrappedValue: Value) where Value: Equatable { value = wrappedValue; same = { $0 == $1 }; alone = false }
    /// `always: true`: avisa con cada asignación aunque sea el mismo valor (como el `didSet { changed() }` de antes).
    public init(wrappedValue: Value, always: Bool) { precondition(always); value = wrappedValue; same = nil; alone = false }
    public init(wrappedValue: Value, alone: Bool) where Value: Equatable { value = wrappedValue; same = { $0 == $1 }; self.alone = alone }

    @available(*, unavailable, message: "@Tracked solo vale en un ObservableModel")
    public var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }

    public static subscript<Model: ObservableModel>(
        _enclosingInstance model: Model,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<Model, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<Model, Tracked<Value>>
    ) -> Value {
        get {
            model.access(model, wrappedKeyPath)
            return model[keyPath: storageKeyPath].value
        }
        set {
            let storage = model[keyPath: storageKeyPath]
            if let same = storage.same, same(storage.value, newValue) { return }
            model.mutate(model, wrappedKeyPath) { model[keyPath: storageKeyPath].value = newValue }
            if storage.alone { model.notifyListeners() } else { model.changed() }
        }
    }
}
