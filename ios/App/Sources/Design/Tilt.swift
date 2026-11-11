import SwiftUI

/// El arte grande tiene cuerpo (la portada de Inicio y la ficha): mantén el dedo un instante y muévelo, y el arte se inclina
/// hacia donde lo llevas con un brillo que lo cruza, como un objeto; al soltar regresa. Hace falta mantener antes de mover, así
/// desplazar la pantalla (o la portada de lado) no lo inclina. Quieto con «Reducir movimiento».
private struct Tiltable: ViewModifier {
    /// nil: sin inclinar; si no, cuánto se ha movido el dedo desde que se mantuvo.
    @State private var drag: CGSize?
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
                // Con el reconocedor de UIKit (no `LongPressGesture` + `DragGesture` de SwiftUI): el arrastre de SwiftUI, aunque
                // fuera simultáneo, se quedaba con el dedo y la pantalla no se desplazaba si empezabas sobre el arte (Fernando,
                // 6 nov: «el scroll no sirve sobre la imagen»). Este no estorba al desplazamiento: si el dedo se mueve antes de
                // mantener, gana el scroll.
                .gesture(HoldAndMove(hold: DS.Tilt.hold) { drag = $0 })
                .dsFeedback(.impact(flexibility: .soft), trigger: drag == nil) { was, now in was && !now }   // lo «agarraste»
        }
    }

    private func clamp(_ v: CGFloat) -> CGFloat { min(1, max(-1, v)) }
}

/// Mantener y mover (UIKit): da cuánto se movió el dedo desde que se mantuvo; nil al soltar o si el scroll se lo lleva.
private struct HoldAndMove: UIGestureRecognizerRepresentable {
    let hold: Double
    let moved: (CGSize?) -> Void

    /// Sin reconocer a la vez que el scroll: si el dedo se mueve antes de mantener, desplaza; si mantuvo, inclina y no desplaza.
    final class Coordinator { var start: CGPoint = .zero }
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let press = UILongPressGestureRecognizer()
        press.minimumPressDuration = hold
        press.cancelsTouchesInView = false
        return press
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let at = recognizer.location(in: recognizer.view)
        switch recognizer.state {
        case .began: context.coordinator.start = at; moved(.zero)
        case .changed: moved(CGSize(width: at.x - context.coordinator.start.x, height: at.y - context.coordinator.start.y))
        default: moved(nil)
        }
    }
}

extension View {
    /// Mantener y mover inclina el arte con un brillo (`Tiltable`).
    func tiltable() -> some View { modifier(Tiltable()) }
}
