import SwiftUI
import OrbitalModels

/// Conecta un modelo de `OrbitalModels` con SwiftUI: cada cambio del modelo vuelve a pintar la vista.
@MainActor
final class ModelObserver<Model: ObservableModel>: ObservableObject {
    let model: Model
    private var subscription: ObservableModel.Subscription?

    init(_ model: Model) {
        self.model = model
        subscription = model.onChange { [weak self] in self?.objectWillChange.send() }
    }
}
