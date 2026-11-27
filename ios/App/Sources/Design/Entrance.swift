import SwiftUI

/// Los estantes entran escalonados (como la TV): la primera vez que llega cada uno en la sesión sube un poco con un fundido,
/// un instante después del de arriba. Al volver a la pestaña o al desplazar de regreso ya están (no se repite el paseo). Con
/// «Reducir movimiento», solo el fundido. Lo que llega deslizando (después de `DS.Motion.entranceWindow` de que entró lo
/// primero de su pantalla) ya está: aparecer con retraso y fundido mientras deslizas se sentía lento (26 nov 2026).
private struct Entrance: ViewModifier {
    let id: String
    let order: Int
    @State private var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Lo que ya entró en esta sesión.
    @MainActor static var seen = Set<String>()
    /// Cuándo entró lo primero de cada pantalla (lo de antes de «:» en el id: «home», «shelf»).
    @MainActor static var opened: [Substring: CFTimeInterval] = [:]

    init(id: String, order: Int) {
        self.id = id; self.order = order
        let screen = id.split(separator: ":").first ?? Substring(id), now = CACurrentMediaTime()
        let first = Self.opened[screen] ?? now
        if Self.opened[screen] == nil { Self.opened[screen] = now }
        let late = now - first > DS.Motion.entranceWindow
        if late { Self.seen.insert(id) }
        _shown = State(initialValue: late || Self.seen.contains(id))
        #if MAC_DRIVE
        if MacDrive.noEntrance { _shown = State(initialValue: true) }
        #endif
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
