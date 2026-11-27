import SwiftUI

/// Lo que la ficha mide de sí misma: la pantalla visible, el margen de arriba y lo que hay bajo el arte hasta las acciones.
struct TitleMeasure: Equatable {
    var viewport: CGSize = .zero
    var topInset: CGFloat = 0
    var belowHero: CGFloat = 0

    /// Junta las medidas que llegan en la misma vuelta del hilo de la pantalla y las entrega una sola vez, en la siguiente.
    @MainActor final class Box {
        private var pending: TitleMeasure?
        func add(to current: TitleMeasure, _ change: (inout TitleMeasure) -> Void, apply: @escaping (TitleMeasure) -> Void) {
            let first = pending == nil
            var next = pending ?? current
            change(&next)
            pending = next
            guard first else { return }
            DispatchQueue.main.async { [self] in
                guard let ready = pending else { return }
                pending = nil
                if ready != current { apply(ready) }
            }
        }
    }
}
