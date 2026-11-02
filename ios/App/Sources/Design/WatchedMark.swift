import SwiftUI

/// La palomita de «Visto». Al marcar algo como visto (no al aparecer ya visto) el círculo se cierra y la palomita se dibuja, con
/// un toque de «listo» en la mano: es un pequeño logro y se siente. Con «Reducir movimiento», solo aparece con un fundido.
struct WatchedMark: View {
    let watched: Bool
    var tint: Color = DS.good
    /// 0…1: cuánto va dibujado (empieza completo si ya estaba visto al aparecer).
    @State private var drawn: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(watched: Bool, tint: Color = DS.good) {
        self.watched = watched
        self.tint = tint
        _drawn = State(initialValue: watched ? 1 : 0)
    }

    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: drawn).stroke(tint, style: StrokeStyle(lineWidth: DS.WatchedMark.line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Check().trim(from: 0, to: max(0, drawn * 2 - 1)).stroke(tint, style: StrokeStyle(lineWidth: DS.WatchedMark.line, lineCap: .round, lineJoin: .round))
                .padding(DS.WatchedMark.checkInset)
        }
        .frame(width: DS.WatchedMark.size, height: DS.WatchedMark.size)
        .opacity(drawn > 0 ? 1 : 0)
        .sensoryFeedback(.success, trigger: watched) { old, new in !old && new }
        .onChange(of: watched) { _, now in
            // Se dibuja con la entrada de siempre (sin resorte: un trazo que rebota se ve roto); quitarla, con un fundido.
            withAnimation(now ? DS.Motion.enter(reduceMotion) ?? DS.Motion.fade : DS.Motion.fade) { drawn = now ? 1 : 0 }
        }
        .accessibilityHidden(!watched)
        .accessibilityLabel(Text("Visto"))
    }

    /// La palomita, en proporción al cuadro que le toca.
    private struct Check: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.12))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
            return path
        }
    }
}
