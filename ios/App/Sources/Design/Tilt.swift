import SwiftUI

/// El arte grande tiene cuerpo (la portada de Inicio y la ficha): mantén el dedo un instante y muévelo, y el arte se inclina
/// hacia donde lo llevas con un brillo que lo cruza, como un objeto; al soltar regresa. Hace falta mantener antes de mover, así
/// desplazar la pantalla (o la portada de lado) no lo inclina. Quieto con «Reducir movimiento».
private struct Tiltable: ViewModifier {
    /// nil: sin inclinar; si no, cuánto se ha movido el dedo desde que se mantuvo.
    @GestureState private var drag: CGSize?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion { content } else {
            let x = clamp((drag?.width ?? 0) / DS.Tilt.reach), y = clamp((drag?.height ?? 0) / DS.Tilt.reach)
            content
                .overlay {
                    // El brillo: una franja clara que sigue al dedo de lado a lado.
                    LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: DS.paper.opacity(DS.Tilt.shine), location: 0.5),
                                           .init(color: .clear, location: 0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .offset(x: x * DS.Tilt.shineTravel)
                        .blendMode(.plusLighter)
                        .opacity(drag == nil ? 0 : 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .rotation3DEffect(.degrees(Double(hypot(x, y)) * DS.Tilt.maxDegrees), axis: (x: -y, y: x, z: 0), perspective: DS.Tilt.perspective)
                .scaleEffect(drag == nil ? 1 : DS.Tilt.held)
                .animation(DS.Motion.snap(reduceMotion), value: drag)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: DS.Tilt.hold)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .updating($drag) { value, state, _ in
                            if case .second(true, let moved) = value { state = moved?.translation ?? .zero }
                        }
                )
                .sensoryFeedback(.impact(flexibility: .soft), trigger: drag == nil) { was, now in was && !now }   // lo «agarraste»
        }
    }

    private func clamp(_ v: CGFloat) -> CGFloat { min(1, max(-1, v)) }
}

/// Un póster que se toca se hunde un poco mientras el dedo está encima (como la TV con la A): la respuesta llega antes que la
/// ficha. Es el estilo de botón de Apple sin nada más que eso (la etiqueta tal cual, como `.plain`), porque solo un estilo sabe
/// cuándo se está presionando sin agregar un gesto: un gesto encima de cada póster le ganaba al deslizar la fila.
struct PosterPress: ButtonStyle {   // ds-exception: el hundido del póster al tocarlo (solo escala; la etiqueta queda como .plain)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? DS.Tilt.pressed : 1)
            .animation(DS.Motion.snap(reduceMotion), value: configuration.isPressed)
    }
}

extension View {
    /// Mantener y mover inclina el arte con un brillo (`Tiltable`).
    func tiltable() -> some View { modifier(Tiltable()) }
}
