import SwiftUI
import OrbitalCore

/// La bienvenida (A1, Fernando, 3 nov 2026: «mucho más estilizado»): siete pósters caen y el planeta de la marca los atrapa.
/// Al llegar a su altura se curvan y entran en una órbita inclinada como el anillo; detrás del planeta se apagan, delante
/// brillan (esa es la profundidad, sin brillos extra). Luego el anillo se dibuja (`OrbitalMark`) y entra la luna turquesa.
/// En reposo, la órbita da una vuelta cada 40 s. Un solo reloj (`TimelineView`) para todo, a 60 cuadros mientras entra y a
/// 30 después; se pausa en segundo plano. Con «Reducir movimiento», todo quieto y ya armado.
struct OrbitCatch: View {
    @Environment(\.titleName) var titleName
    /// Los pósters (sus direcciones); si faltan, sus lugares quedan con el color de la superficie.
    let posters: [Suggestion]
    /// Llegó la luna (para el toque en la mano, que pone la pantalla).
    var onMoon: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var start = Date()
    @State private var settled = false
    @State private var moonLanded = false

    var body: some View {
        let still = reduceMotion
        let frame = settled ? DS.Welcome.restFrame : DS.Welcome.introFrame
        TimelineView(.animation(minimumInterval: frame, paused: still || scenePhase != .active)) { context in
            let t = still ? DS.Welcome.buttonAt + 1 : context.date.timeIntervalSince(start)
            scene(at: t)
        }
        .frame(width: DS.Welcome.orbitWidth, height: DS.Welcome.orbitWidth * DS.Welcome.moonOrbit)
        .accessibilityHidden(true)
        .task {
            start = Date()
            guard !reduceMotion else { moonLanded = true; settled = true; return }
            try? await Task.sleep(for: .seconds(DS.Welcome.moonAt))
            moonLanded = true; onMoon()
            try? await Task.sleep(for: .seconds(DS.Welcome.buttonAt - DS.Welcome.moonAt))
            settled = true
        }
    }

    @ViewBuilder private func scene(at t: Double) -> some View {
        let items = (0..<DS.Welcome.posters).map { place($0, at: t) }
        ZStack {
            ForEach(items.filter { !$0.front }, id: \.index) { poster($0) }
            // El planeta solo; a su hora, la marca completa, cuyo anillo se dibuja de una punta a la otra.
            Group {
                if t >= DS.Welcome.ringAt { OrbitalMark(size: DS.Welcome.planet, animated: !reduceMotion) }
                else { MarkPlanet().frame(width: DS.Welcome.planet, height: DS.Welcome.planet) }
            }
                .opacity(min(1, t / DS.Welcome.planetIn))
                .scaleEffect(DS.Motion.leaveScale + (1 - DS.Motion.leaveScale) * min(1, t / DS.Welcome.planetIn))
                .foregroundStyle(DS.text)
            ForEach(items.filter(\.front), id: \.index) { poster($0) }
            moon(at: t)
        }
    }

    /// Dónde va cada póster: cayendo hasta su punto de la órbita y, desde ahí, girando.
    private struct Placed { let index: Int; let point: CGPoint; let scale: CGFloat; let twist: Double; let bright: Double; let front: Bool; let shown: Double }

    private func place(_ i: Int, at t: Double) -> Placed {
        let count = Double(DS.Welcome.posters)
        let begin = DS.Welcome.fallStart + Double(i) * DS.Welcome.fallStep
        let caught = begin + DS.Welcome.fallDuration
        let base = 2 * Double.pi * Double(i) / count
        let spin = max(0, t - caught) / DS.Welcome.orbitPeriod * 2 * .pi
        let angle = base + spin
        let onOrbit = orbitPoint(angle, scale: 1)
        let front = sin(angle) > 0
        guard t < caught else {
            return Placed(index: i, point: onOrbit, scale: DS.Welcome.orbitScale, twist: 0, bright: front ? 1 : DS.Welcome.behind, front: front, shown: 1)
        }
        // La caída: empieza lenta y acelera (gravedad), girada y enderezándose; al final se curva hacia su punto.
        let p = max(0, min(1, (t - begin) / DS.Welcome.fallDuration))
        let g = p * p
        let from = CGPoint(x: onOrbit.x, y: onOrbit.y - DS.Welcome.fallFrom)
        let point = CGPoint(x: from.x + (onOrbit.x - from.x) * (1 - pow(1 - p, 3)), y: from.y + (onOrbit.y - from.y) * g)
        let scale = 1 - (1 - DS.Welcome.orbitScale) * p
        let twist = (i.isMultiple(of: 2) ? 1 : -1) * DS.Welcome.fallTwist * (1 - p)
        return Placed(index: i, point: point, scale: scale, twist: twist, bright: 1 - (1 - (front ? 1 : DS.Welcome.behind)) * p, front: true, shown: min(1, p * 4))
    }

    /// Un punto de la elipse inclinada (como el anillo), desde el centro de la escena.
    private func orbitPoint(_ angle: Double, scale: CGFloat) -> CGPoint {
        let a = DS.Welcome.orbitWidth / 2 * scale, b = DS.Welcome.orbitHeight / 2 * scale
        // Con tipos dichos: el Swift de la CI no sabía qué `cos` usar (Double o CGFloat).
        let x: CGFloat = a * CGFloat(Foundation.cos(angle)), y: CGFloat = b * CGFloat(Foundation.sin(angle))
        let tilt: Double = DS.Welcome.tilt * .pi / 180
        let ct = CGFloat(Foundation.cos(tilt)), st = CGFloat(Foundation.sin(tilt))
        return CGPoint(x: x * ct - y * st, y: x * st + y * ct)
    }

    @ViewBuilder private func poster(_ p: Placed) -> some View {
        let item = p.index < posters.count ? posters[p.index] : nil
        PosterView(url: item?.poster, title: item.map { titleName($0.title, id: $0.imdb, kind: $0.kind) } ?? "", maxPoints: DS.Welcome.posterHeight)
            .frame(height: DS.Welcome.posterHeight)
            .brightness(p.bright - 1)
            .rotationEffect(.degrees(p.twist))
            .scaleEffect(p.scale)
            .opacity(p.shown)
            .offset(x: p.point.x, y: p.point.y)
    }

    @ViewBuilder private func moon(at t: Double) -> some View {
        let angle = -Double.pi / 4 + max(0, t - DS.Welcome.moonAt) / DS.Welcome.moonPeriod * 2 * .pi
        let point = orbitPoint(angle, scale: DS.Welcome.moonOrbit)
        Circle().fill(DS.brandMoon)
            .frame(width: DS.Welcome.moon, height: DS.Welcome.moon)
            .scaleEffect(moonLanded ? 1 : DS.Brand.moonFromScale)
            .opacity(moonLanded ? 1 : 0)
            .animation(DS.Motion.pop(reduceMotion), value: moonLanded)
            .offset(x: point.x, y: point.y)
    }
}
