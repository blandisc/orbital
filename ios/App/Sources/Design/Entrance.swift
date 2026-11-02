import SwiftUI

/// Los estantes entran escalonados (como la TV): la primera vez que llega cada uno en la sesión sube un poco con un fundido,
/// un instante después del de arriba. Al volver a la pestaña o al desplazar de regreso ya están (no se repite el paseo). Con
/// «Reducir movimiento», solo el fundido.
private struct Entrance: ViewModifier {
    let id: String
    let order: Int
    @State private var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Lo que ya entró en esta sesión.
    @MainActor static var seen = Set<String>()

    init(id: String, order: Int) {
        self.id = id; self.order = order
        _shown = State(initialValue: Self.seen.contains(id))
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : DS.Motion.entranceRise)
            .onAppear {
                guard !shown else { return }
                Self.seen.insert(id)
                withAnimation((DS.Motion.enter(reduceMotion) ?? DS.Motion.fade).delay(Double(min(order, DS.Motion.entranceMax)) * DS.Motion.entranceStep)) { shown = true }
            }
    }
}

extension View {
    /// Entra escalonado la primera vez de la sesión (`order`: su lugar entre los que llegan juntos).
    func entrance(_ id: String, order: Int) -> some View { modifier(Entrance(id: id, order: order)) }
}
