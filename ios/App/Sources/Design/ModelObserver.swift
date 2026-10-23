import SwiftUI
import OrbitalModels

/// Conecta un modelo de `OrbitalModels` con SwiftUI (Observation): la vista que lee `model` mientras se pinta se vuelve
/// a pintar con cada cambio del modelo. Vive en un `@State`; como `@State` evalúa su valor inicial en cada `init` de la
/// vista, el modelo se arma la primera vez que se lee (una sola vez, como hacía `@StateObject`), no al crear el observador.
@MainActor
final class ModelObserver<Model: ObservableModel> {
    private var make: (() -> Model)?
    private var made: Model?

    init(_ model: @autoclosure @escaping () -> Model) { make = model }

    var model: Model {
        let model = made ?? {
            let new = make!()
            made = new; make = nil
            return new
        }()
        model.track()
        return model
    }

    /// Vuelve a pintar a quien lee el modelo sin que el modelo haya cambiado (p. ej. tras cambiar un ajuste que la vista lee aparte).
    func invalidate() { model.changed() }
}
