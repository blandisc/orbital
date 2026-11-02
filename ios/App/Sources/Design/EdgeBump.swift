import SwiftUI

/// Al llegar al final (o al principio) de una fila y seguir empujando, un golpe suave en la mano: la orilla se siente, como en
/// la TV con el mando. El rebote ya lo da iOS; el golpe va una sola vez por empujón (no cada vez que rozas la orilla).
private struct EdgeBump: ViewModifier {
    @State private var bumps = 0
    @State private var past = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geo in
                let end = max(0, geo.contentSize.width + geo.contentInsets.leading + geo.contentInsets.trailing - geo.containerSize.width)
                let x = geo.contentOffset.x + geo.contentInsets.leading
                return x < -DS.Motion.edgeOverscroll || x > end + DS.Motion.edgeOverscroll
            } action: { _, beyond in
                if beyond, !past { bumps += 1 }
                past = beyond
            }
            .sensoryFeedback(.impact(weight: .light, intensity: DS.Motion.edgeIntensity), trigger: bumps)
    }
}

extension View {
    /// Golpe suave al empujar más allá del final de una fila horizontal.
    func edgeBump() -> some View { modifier(EdgeBump()) }
}
