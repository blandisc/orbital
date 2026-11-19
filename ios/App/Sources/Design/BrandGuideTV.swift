import SwiftUI

/// U7 · «¿Ya usas Orbital en la TV?» (Fernando, 18 nov 2026; prototipo `screens/tvfirst.js`): tu iPhone a la izquierda y la
/// TV con Orbital a la derecha, un poco apagada. Antes de conectar, de tu iPhone sale un anillo que nace pequeño y se apaga
/// antes de salirse, y la TV parpadea como quien contesta. Al conectar, un arco punteado se dibuja del iPhone a la TV, la TV se
/// prende, el planeta rebota y un eco sale de su centro. Con «Reducir movimiento», quieta en su final.
struct GuideTVScene: View {
    let connected: Bool
    let start: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size = CGSize(width: 402, height: 232)
    static let askEnd = 2.4, doneEnd = 1.3
    private static let phone = CGRect(x: 46, y: 78, width: 84, height: 150), tv = CGRect(x: 196, y: 40, width: 180, height: 106)
    private static var rings: CGPoint { CGPoint(x: phone.midX, y: phone.minY + 58) }
    private static var tvCenter: CGPoint { CGPoint(x: tv.midX, y: tv.midY) }

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / Self.size.width
            TimelineView(.animation(minimumInterval: DS.Welcome.introFrame, paused: reduceMotion)) { ctx in
                let end = connected ? Self.doneEnd : Self.askEnd
                let t = reduceMotion ? end + 1 : ctx.date.timeIntervalSince(start)
                scene(t).frame(width: Self.size.width, height: Self.size.height).scaleEffect(scale, anchor: .topLeading)
            }
        }
        .aspectRatio(Self.size.width / Self.size.height, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(connected ? Text("Tu iPhone y tu TV, conectados") : Text("Tu iPhone y tu TV con Orbital"))
    }

    private var arcPath: Path {
        Path { p in
            p.move(to: CGPoint(x: Self.rings.x + 10, y: Self.phone.minY - 6))
            p.addQuadCurve(to: CGPoint(x: Self.tv.minX - 6, y: Self.tv.minY + 34), control: CGPoint(x: 150, y: -2))
        }
    }

    @ViewBuilder private func scene(_ t: Double) -> some View {
        let M = GuideTraktScene.Motion.self
        let devL = M.item(t, 0, 10), devR = M.item(t, 0.06, 10)
        // Antes: un anillo a 0.75 s y la TV parpadea a 1.87 s. Al conectar: arco, se prende, el planeta rebota y su eco.
        let ring = min(max((t - 0.75) / 1.1, 0), 1)
        let blink = connected ? 0 : max(0, 1 - pow((t - 1.87) / 0.12, 2))
        let lit = connected ? M.easeOut((t - 0.22) / 0.25) : 0.0
        let reveal = connected ? M.easeOut((t - 0.1) / 0.3) : 0
        let pop = connected ? 1 + 0.18 * max(0, sin(.pi * min(max((t - 0.32) / 0.35, 0), 1))) : 1
        let echo = connected ? min(max((t - 0.4) / 0.7, 0), 1) : 0
        ZStack(alignment: .topLeading) {
            if !connected {
                Circle().stroke(DS.fresh, lineWidth: 1.5).frame(width: 2 * 150 * ring, height: 2 * 150 * ring)
                    .position(Self.rings).opacity(t < 0.75 ? 0 : 0.7 * (1 - ring))
            }
            arcPath.trim(from: 0, to: reveal).stroke(DS.fresh, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [3, 5]))
                .opacity(connected ? 1 : 0)
            tvSet(lit: lit, blink: blink, pop: pop, echo: echo).opacity(devR.opacity).offset(y: devR.rise)
            phoneSet.opacity(devL.opacity).offset(y: devL.rise)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }

    private func tvSet(lit: Double, blink: Double, pop: Double, echo: Double) -> some View {
        let tv = Self.tv, screen = RoundedRectangle(cornerRadius: 3, style: .continuous)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(DS.surface)
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(DS.ink500, lineWidth: 2))
                .frame(width: tv.width, height: tv.height)
            ZStack {
                screen.fill(DS.bg)
                OrbitalMark(size: 52).foregroundStyle(DS.text).scaleEffect(pop)
                screen.fill(DS.scrimStrong).opacity(0.42 * (1 - lit) * (1 - 0.6 * blink))
                screen.fill(DS.fresh).opacity(0.12 * blink)
                Circle().stroke(DS.fresh, lineWidth: 1.5).frame(width: 2 * 70 * echo, height: 2 * 70 * echo)
                    .opacity(echo > 0 ? 0.6 * (1 - echo) : 0)
            }
            .frame(width: tv.width - 10, height: tv.height - 10).clipShape(screen).offset(x: 5, y: 5)
            Rectangle().fill(DS.ink500).frame(width: 12, height: 14).offset(x: tv.width / 2 - 6, y: tv.height)
            Capsule().fill(DS.ink500).frame(width: 60, height: 4).offset(x: tv.width / 2 - 30, y: tv.height + 13)
        }
        .offset(x: tv.minX, y: tv.minY)
    }

    private var phoneSet: some View {
        let ph = Self.phone
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DS.surface)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(DS.ink500, lineWidth: 2))
            RoundedRectangle(cornerRadius: 13, style: .continuous).fill(DS.bg).padding(5)
            Capsule().fill(DS.scrimStrong).frame(width: 26, height: 7).offset(x: ph.width / 2 - 13, y: 9)
            VStack(alignment: .leading, spacing: 7) {
                Capsule().fill(DS.text.opacity(0.09)).frame(width: (ph.width - 28) * 0.85, height: 4)
                Capsule().fill(DS.text.opacity(0.09)).frame(width: (ph.width - 28) * 0.62, height: 4)
            }
            .offset(x: 14, y: 30)
        }
        .frame(width: ph.width, height: ph.height)
        .offset(x: ph.minX, y: ph.minY)
    }
}
