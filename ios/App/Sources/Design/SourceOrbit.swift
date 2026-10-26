import SwiftUI

/// «Buscando la mejor versión», con la marca de Orbital: el planeta al centro y una órbita que se llena con un punto por
/// cada versión que de verdad llega de tus complementos. Mientras se pregunta, un barrido gira en la órbita; al elegir, el
/// punto de la elegida se pinta del turquesa de la luna y viaja al planeta. Si una versión no arranca y se prueba otra,
/// el punto que falló se apaga y otro toma su lugar. Con «Reducir movimiento», sin giro ni viaje: solo cambian los textos.
struct SourceOrbit: View {
    /// Cuántas versiones llegaron (un punto por cada una, hasta `DS.SourceOrbit.maxDots`).
    let found: Int
    /// Ya se eligió una y se está abriendo.
    let chosen: Bool
    /// Cuántas se probaron y no arrancaron (sus puntos quedan apagados).
    let failed: Int
    let title: Text
    let detail: Text?
    /// El ancho de la órbita.
    var size: CGFloat = DS.SourceOrbit.size
    /// En horizontal: la órbita a la izquierda y los textos a su derecha (en vertical, uno sobre otro).
    var sideBySide = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Cuántos puntos ya se ven: aunque las versiones lleguen todas juntas (ya estaban guardadas), salen una tras otra; y la
    /// elegida se marca cuando ya están todas. Es solo la vista: el video no espera nada.
    @State private var revealed = 0

    var body: some View {
        let layout = sideBySide ? AnyLayout(HStackLayout(spacing: DS.Space.s6)) : AnyLayout(VStackLayout(spacing: DS.Space.s4))
        layout {
            orbit.frame(width: size, height: size)
            VStack(alignment: sideBySide ? .leading : .center, spacing: DS.Space.s1) {
                title.font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.text)
                if let detail { detail.font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted) }
            }
            .multilineTextAlignment(sideBySide ? .leading : .center)
            .frame(minWidth: sideBySide ? DS.SourceOrbit.textWidth : nil, alignment: sideBySide ? .leading : .center)
            .contentTransition(.opacity)
        }
        .animation(DS.Motion.base(reduceMotion), value: revealed)
        .animation(DS.Motion.spring(reduceMotion), value: picked)
        .animation(DS.Motion.base(reduceMotion), value: failed)
        .accessibilityElement(children: .combine)
        .task(id: min(found, DS.SourceOrbit.maxDots)) {
            let target = min(found, DS.SourceOrbit.maxDots)
            if reduceMotion { revealed = target; return }
            while revealed < target, !Task.isCancelled {
                revealed += 1
                try? await Task.sleep(for: .seconds(DS.SourceOrbit.revealStep))
            }
        }
    }

    /// La elegida se marca cuando ya se ven todos los puntos.
    private var picked: Bool { chosen && revealed >= min(found, DS.SourceOrbit.maxDots) }

    private var orbit: some View {
        let radius = size / 2 - DS.SourceOrbit.dot
        let shown = revealed
        let pick = min(failed, max(shown - 1, 0))
        let chosen = picked
        return ZStack {
            Circle().stroke(DS.track, lineWidth: DS.SourceOrbit.ringWidth).padding(DS.SourceOrbit.dot)
            if !chosen && !reduceMotion { Sweep(size: size) }
            ForEach(0..<shown, id: \.self) { i in
                let isPick = chosen && i == pick
                let angle = Angle.degrees(Double(i) * DS.SourceOrbit.goldenAngle - 90)
                Circle()
                    .fill(isPick ? DS.brandMoon : DS.text)
                    .frame(width: isPick ? DS.SourceOrbit.chosenDot : DS.SourceOrbit.dot, height: isPick ? DS.SourceOrbit.chosenDot : DS.SourceOrbit.dot)
                    .opacity(i < pick ? DS.SourceOrbit.failedOpacity : chosen && !isPick ? DS.SourceOrbit.dimOpacity : 1)
                    // La elegida viaja al planeta (sin «Reducir movimiento»); las demás se quedan en la órbita.
                    .offset(x: isPick && !reduceMotion ? 0 : radius * cos(angle.radians), y: isPick && !reduceMotion ? 0 : radius * sin(angle.radians))
                    .transition(.scale.combined(with: .opacity))
            }
            Circle().stroke(DS.text, lineWidth: DS.SourceOrbit.planetWidth)
                .frame(width: size * DS.SourceOrbit.planetShare, height: size * DS.SourceOrbit.planetShare)
            // Abriendo la elegida: una luna gira alrededor del planeta hasta que empieza el video.
            if chosen && !reduceMotion { Moon(radius: size * DS.SourceOrbit.planetShare * DS.SourceOrbit.moonOrbit) }
        }
        .accessibilityHidden(true)
    }

    /// La luna turquesa que gira alrededor del planeta mientras se abre la versión elegida.
    private struct Moon: View {
        let radius: CGFloat
        var body: some View {
            TimelineView(.animation) { context in
                let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: DS.SourceOrbit.moonSeconds) / DS.SourceOrbit.moonSeconds
                let angle = turn * 2 * .pi
                Circle().fill(DS.brandMoon)
                    .frame(width: DS.SourceOrbit.dot, height: DS.SourceOrbit.dot)
                    .offset(x: radius * cos(angle), y: radius * sin(angle))
            }
        }
    }

    /// El barrido que gira en la órbita mientras se pregunta a los complementos.
    private struct Sweep: View {
        let size: CGFloat
        var body: some View {
            TimelineView(.animation) { context in
                let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: DS.SourceOrbit.sweepSeconds) / DS.SourceOrbit.sweepSeconds
                Circle().trim(from: 0, to: DS.SourceOrbit.sweepLength)
                    .stroke(DS.text, style: StrokeStyle(lineWidth: DS.SourceOrbit.sweepWidth, lineCap: .round))
                    .padding(DS.SourceOrbit.dot)
                    .rotationEffect(.degrees(turn * 360))
            }
        }
    }
}
