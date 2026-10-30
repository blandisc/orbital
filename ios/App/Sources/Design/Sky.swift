import SwiftUI
import CoreMotion

// El cielo de fondo (docs/producto/muvy-busqueda-premios/propuesta.html § Cielo): Crepúsculo de noche, Bruma lunar de día.
// Va detrás de las pantallas con poco contenido («Lo que ves», Buscar) con `Backdrop(sky: true)`; las tarjetas son vidrio encima.

/// Estrellas con física: pocas grandes y muchas diminutas, unas frías y otras cálidas; las cinco más brillantes con halo y
/// una cruz de luz. Una franja de polvo cruza en diagonal, tres capas se deslizan a distinta velocidad y se inclinan apenas
/// al mover el teléfono. Las brillantes respiran y cada minuto cruza una estrella fugaz. Con «Reducir movimiento», quieto.
struct SkyField: View {
    /// Sin arte detrás, el tono del crepúsculo arriba; con arte (Buscar toma el del n.º 1) solo las estrellas.
    var dusk = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var tilt = SkyTilt()
    /// Quieto con «Reducir movimiento» y en las pruebas de interfaz (`-demo-no-idle`): si no, la app nunca queda en reposo.
    private var reduceMotion: Bool { systemReduceMotion || Demo.noIdle }

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            if dusk {
                LinearGradient(stops: [.init(color: DS.Sky.dusk, location: 0), .init(color: .clear, location: DS.Sky.duskFade)],
                               startPoint: .top, endPoint: .bottom)
            }
            SkyBand().opacity(dark ? DS.Sky.bandOpacity : DS.Sky.bandOpacityLight)
            TimelineView(.animation(minimumInterval: DS.Sky.frame, paused: reduceMotion)) { context in
                let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                Canvas { g, size in
                    SkyPainter(dark: dark, time: time, tilt: reduceMotion ? .zero : tilt.offset).paint(&g, size: size)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { if !reduceMotion { tilt.start() } }
        .onDisappear { tilt.stop() }
        .onChange(of: systemReduceMotion) { reduceMotion ? tilt.stop() : tilt.start() }
    }
}

/// La franja de polvo: una banda ancha y desenfocada en diagonal (el desenfoque lo hace la tarjeta gráfica una vez; no se
/// vuelve a calcular en cada cuadro).
private struct SkyBand: View {
    var body: some View {
        GeometryReader { geo in
            let (a, b) = SkyPainter.band(in: geo.size)
            Capsule()
                .fill(LinearGradient(colors: [.clear, DS.Sky.band, DS.Sky.band, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: hypot(b.x - a.x, b.y - a.y), height: geo.size.width * DS.Sky.bandWidth)
                .rotationEffect(.radians(atan2(b.y - a.y, b.x - a.x)))
                .position(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                .blur(radius: DS.Sky.bandBlur)
        }
    }
}

/// Una estrella: dónde está (de 0 a 1 en la pantalla), su capa, su tamaño, su color y cómo respira.
private struct SkyStar {
    enum Tone { case white, cold, warm }
    var x: CGFloat, y: CGFloat, r: CGFloat, layer: Int, tone: Tone, phase: Double, period: Double
}

/// Pinta un cuadro del cielo. Las estrellas salen siempre iguales (de una semilla) para que el cielo no cambie al volver.
private struct SkyPainter {
    let dark: Bool, time: TimeInterval, tilt: CGPoint

    /// Las estrellas de cada capa (las de cerca, de la más grande a la más chica: las primeras llevan halo) y el polvo.
    static let stars: [SkyStar] = {
        var rng = SkyRandom(seed: DS.Sky.seed)
        var out: [SkyStar] = []
        for (layer, count) in DS.Sky.counts.enumerated() {
            let range = DS.Sky.radius[layer]
            var layerStars = (0..<count).map { _ -> SkyStar in
                let u = rng.unit(), pick = rng.unit()
                let tone: SkyStar.Tone = pick < DS.Sky.coldShare ? .cold : pick < DS.Sky.coldShare + DS.Sky.warmShare ? .warm : .white
                // Al cubo: casi todas cerca del tamaño menor y pocas grandes.
                return SkyStar(x: rng.unit(), y: rng.unit(), r: range.lowerBound + (range.upperBound - range.lowerBound) * u * u * u,
                               layer: layer, tone: tone, phase: rng.unit() * 2 * .pi,
                               period: DS.Sky.breath.lowerBound + rng.unit() * (DS.Sky.breath.upperBound - DS.Sky.breath.lowerBound))
            }
            if layer == DS.Sky.counts.count - 1 { layerStars.sort { $0.r > $1.r } }
            out += layerStars
        }
        return out
    }()

    /// Los granitos de la franja: a lo largo de ella (u) y a un lado u otro, juntos al centro (la suma de tres al azar).
    static let dust: [(u: CGFloat, across: CGFloat, r: CGFloat)] = {
        var rng = SkyRandom(seed: DS.Sky.seed &+ 1)
        return (0..<DS.Sky.dust).map { _ in (rng.unit(), (rng.unit() + rng.unit() + rng.unit() - 1.5) / 1.5, 0.3 + rng.unit() * 0.4) }
    }()

    /// De dónde a dónde cruza la franja: de abajo a la izquierda a arriba a la derecha, un poco fuera de la pantalla.
    static func band(in size: CGSize) -> (CGPoint, CGPoint) {
        (CGPoint(x: -0.1 * size.width, y: 0.66 * size.height), CGPoint(x: 1.1 * size.width, y: 0.14 * size.height))
    }

    func paint(_ g: inout GraphicsContext, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let env = g.environment
        let colors: [SkyStar.Tone: Color] = [.white: Color(DS.Sky.star.resolve(in: env)), .cold: Color(DS.Sky.cold.resolve(in: env)),
                                             .warm: Color(DS.Sky.warm.resolve(in: env))]
        let fade = dark ? 1 : DS.Sky.lightStars
        let white = colors[.white] ?? .white

        // El polvo de la franja: no se desliza (va pegado a ella).
        let (a, b) = Self.band(in: size)
        let along = CGPoint(x: b.x - a.x, y: b.y - a.y), length = hypot(along.x, along.y)
        let across = CGPoint(x: -along.y / length, y: along.x / length), spread = size.width * DS.Sky.dustSpread
        for d in Self.dust {
            let p = CGPoint(x: a.x + along.x * d.u + across.x * d.across * spread, y: a.y + along.y * d.u + across.y * d.across * spread)
            dot(&g, at: p, r: d.r, color: white.opacity(DS.Sky.dustOpacity * fade))
        }

        let near = DS.Sky.counts.count - 1
        var haloed = 0
        for star in Self.stars {
            let layer = star.layer
            let shift = CGFloat(time) * DS.Sky.drift[layer] + tilt.x * DS.Sky.tilt[layer]
            let x = (star.x * size.width + shift).truncatingRemainder(dividingBy: size.width)
            let p = CGPoint(x: x < 0 ? x + size.width : x, y: star.y * size.height + tilt.y * DS.Sky.tilt[layer])
            var alpha = DS.Sky.opacity[layer] * fade
            if layer == near {   // las brillantes respiran despacio
                alpha *= 1 - DS.Sky.breathDepth * (0.5 + 0.5 * sin(time * 2 * .pi / star.period + star.phase))
            }
            let color = colors[star.tone] ?? white
            if layer == near, haloed < DS.Sky.halos, dark {
                haloed += 1
                halo(&g, at: p, r: star.r, color: color, alpha: alpha)
            }
            dot(&g, at: p, r: star.r, color: color.opacity(alpha))
        }
        shootingStar(&g, size: size, color: white.opacity(fade))
    }

    private func dot(_ g: inout GraphicsContext, at p: CGPoint, r: CGFloat, color: Color) {
        g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
    }

    /// El halo y la cruz de luz casi invisible de las cinco más brillantes.
    private func halo(_ g: inout GraphicsContext, at p: CGPoint, r: CGFloat, color: Color, alpha: Double) {
        let h = r * DS.Sky.haloScale
        g.fill(Path(ellipseIn: CGRect(x: p.x - h, y: p.y - h, width: h * 2, height: h * 2)),
               with: .radialGradient(Gradient(colors: [color.opacity(alpha * DS.Sky.haloOpacity), .clear]), center: p, startRadius: 0, endRadius: h))
        var cross = Path()
        let c = DS.Sky.crossLength
        cross.move(to: CGPoint(x: p.x - c, y: p.y)); cross.addLine(to: CGPoint(x: p.x + c, y: p.y))
        cross.move(to: CGPoint(x: p.x, y: p.y - c)); cross.addLine(to: CGPoint(x: p.x, y: p.y + c))
        g.stroke(cross, with: .color(color.opacity(alpha * DS.Sky.crossOpacity)), lineWidth: DS.Sky.crossWidth)
    }

    /// Una estrella fugaz finita a la mitad de cada minuto, en un lugar distinto cada vez.
    private func shootingStar(_ g: inout GraphicsContext, size: CGSize, color: Color) {
        guard time > 0 else { return }
        let cycle = (time / DS.Sky.shootEvery).rounded(.down)
        let local = time - cycle * DS.Sky.shootEvery - DS.Sky.shootEvery / 2
        guard local >= 0, local < DS.Sky.shootFor else { return }
        var rng = SkyRandom(seed: DS.Sky.seed &+ UInt64(cycle))
        let start = CGPoint(x: size.width * (0.35 + 0.55 * rng.unit()), y: size.height * (0.05 + 0.3 * rng.unit()))
        let angle = .pi * (0.78 + 0.1 * rng.unit())   // hacia abajo a la izquierda
        let dir = CGPoint(x: cos(angle), y: sin(angle))
        let progress = local / DS.Sky.shootFor, run = DS.Sky.shootLength * 2
        let head = CGPoint(x: start.x + dir.x * run * progress, y: start.y + dir.y * run * progress)
        let tail = CGPoint(x: head.x - dir.x * DS.Sky.shootLength, y: head.y - dir.y * DS.Sky.shootLength)
        var path = Path(); path.move(to: tail); path.addLine(to: head)
        let alpha = sin(.pi * progress) * DS.Sky.shootOpacity
        g.stroke(path, with: .linearGradient(Gradient(colors: [.clear, color.opacity(alpha)]), startPoint: tail, endPoint: head),
                 style: StrokeStyle(lineWidth: DS.Sky.shootWidth, lineCap: .round))
    }
}

/// Números al azar que salen siempre iguales con la misma semilla (SplitMix64).
private struct SkyRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func unit() -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return CGFloat((z ^ (z >> 31)) >> 11) / CGFloat(1 << 53)
    }
}

/// Cuánto está inclinado el teléfono respecto a como lo tomaste (de -1 a 1), suavizado. No avisa a SwiftUI: el cielo lo lee
/// en cada cuadro, así no vuelve a pintar la pantalla por cada movimiento.
@MainActor
final class SkyTilt {
    private(set) var offset: CGPoint = .zero
    private let motion = CMMotionManager()
    private var rest: CGPoint?

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = DS.Sky.frame
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let g = data?.gravity else { return }
            let now = CGPoint(x: g.x, y: g.y)
            // El reposo sigue despacio a tu mano: lo que se nota es el movimiento, no cómo lo sostienes.
            let rest = self.rest.map { CGPoint(x: $0.x + (now.x - $0.x) * 0.01, y: $0.y + (now.y - $0.y) * 0.01) } ?? now
            self.rest = rest
            let target = CGPoint(x: max(-1, min(1, (now.x - rest.x) * 3)), y: max(-1, min(1, (now.y - rest.y) * 3)))
            self.offset = CGPoint(x: self.offset.x + (target.x - self.offset.x) * 0.2, y: self.offset.y + (target.y - self.offset.y) * 0.2)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        rest = nil; offset = .zero
    }
}
