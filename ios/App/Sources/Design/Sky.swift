import SwiftUI
import CoreMotion

// El cielo de fondo (docs/producto/muvy-busqueda-premios/propuesta.html § Cielo): Crepúsculo de noche, Bruma lunar de día.
// Va detrás de todas las pantallas (`Backdrop`); las tarjetas son vidrio encima.

/// Un cielo mínimo: pocas estrellas en dos capas (muchas diminutas lejos, unas cuantas más grandes cerca), las tres más
/// brillantes con un halo suave, una franja de luz muy tenue en diagonal y, cada minuto, una estrella fugaz finita. Las
/// capas se deslizan despacio y se inclinan apenas al mover el teléfono. Con «Reducir movimiento», quieto.
struct SkyField: View {
    /// Sin arte detrás, el tono del crepúsculo arriba; con arte (Buscar toma el del n.º 1) solo las estrellas.
    var dusk = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var tilt = SkyTilt()

    /// Quieto con «Reducir movimiento» y en las pruebas de interfaz (`-demo-no-idle`: si no, la app nunca queda en reposo).
    private var still: Bool {
        #if DEBUG
        if Demo.noIdle { return true }
        #endif
        return systemReduceMotion
    }
    /// Solo se mueve con la app al frente (fuera de ella no gasta batería).
    private var moving: Bool { !still && scenePhase == .active }

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            if dusk {
                LinearGradient(stops: [.init(color: DS.Sky.dusk, location: 0), .init(color: .clear, location: DS.Sky.duskFade)],
                               startPoint: .top, endPoint: .bottom)
            }
            SkyBand().opacity(dark ? DS.Sky.bandOpacity : DS.Sky.bandOpacityLight)
            TimelineView(SkySchedule(paused: !moving)) { context in
                let time = still ? 0 : context.date.timeIntervalSinceReferenceDate
                Canvas { g, size in
                    SkyPainter(dark: dark, time: time, tilt: moving ? tilt.offset : .zero).paint(&g, size: size)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: moving, initial: true) { _, on in on ? tilt.start() : tilt.stop() }
        .onDisappear { tilt.stop() }
    }
}

/// Cada cuánto se pinta: el cielo es lento (pocos cuadros) y solo la estrella fugaz va fluida, el segundo que dura.
private struct SkySchedule: TimelineSchedule {
    let paused: Bool

    func entries(from start: Date, mode: Mode) -> AnyIterator<Date> {
        var next = start
        return AnyIterator {
            guard !paused else { return nil }
            let now = next
            let calm = mode == .lowFrequency || !SkyPainter.shooting(at: now.timeIntervalSinceReferenceDate)
            next = now.addingTimeInterval(calm ? DS.Sky.frame : DS.Sky.shootFrame)
            return now
        }
    }
}

/// La franja de luz: una banda ancha y desenfocada en diagonal (el desenfoque lo hace la tarjeta gráfica una vez; no se
/// vuelve a calcular en cada cuadro).
private struct SkyBand: View {
    var body: some View {
        GeometryReader { geo in
            let (a, b) = (CGPoint(x: DS.Sky.bandFrom.x * geo.size.width, y: DS.Sky.bandFrom.y * geo.size.height),
                          CGPoint(x: DS.Sky.bandTo.x * geo.size.width, y: DS.Sky.bandTo.y * geo.size.height))
            Capsule()
                .fill(LinearGradient(colors: [.clear, DS.Sky.band, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: hypot(b.x - a.x, b.y - a.y), height: geo.size.width * DS.Sky.bandWidth)
                .rotationEffect(.radians(atan2(b.y - a.y, b.x - a.x)))
                .position(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                .blur(radius: DS.Sky.bandBlur)
        }
    }
}

/// Una estrella: dónde está (de 0 a 1 en la pantalla), su capa, su tamaño, su color y cómo titila.
private struct SkyStar {
    enum Tone { case white, cold, warm }
    var x: CGFloat, y: CGFloat, r: CGFloat, layer: Int, tone: Tone, phase: Double, period: Double
}

/// Pinta un cuadro del cielo. Las estrellas salen siempre iguales (de una semilla) para que el cielo no cambie al volver.
private struct SkyPainter {
    let dark: Bool, time: TimeInterval, tilt: CGPoint

    /// Las de cada capa; las de cerca, de la más grande a la más chica (las primeras llevan halo).
    static let stars: [SkyStar] = {
        var rng = SkyRandom(seed: DS.Sky.seed)
        var out: [SkyStar] = []
        for (layer, count) in DS.Sky.counts.enumerated() {
            let range = DS.Sky.radius[layer]
            var layerStars = (0..<count).map { _ -> SkyStar in
                let size = rng.unit(), pick = rng.unit()
                let tone: SkyStar.Tone = pick < DS.Sky.coldShare ? .cold : pick < DS.Sky.coldShare + DS.Sky.warmShare ? .warm : .white
                // Al cubo: casi todas del tamaño menor y pocas grandes, como en el cielo real.
                return SkyStar(x: rng.unit(), y: rng.unit(), r: range.lowerBound + (range.upperBound - range.lowerBound) * size * size * size,
                               layer: layer, tone: tone, phase: rng.unit() * 2 * .pi,
                               period: DS.Sky.twinkle.lowerBound + rng.unit() * (DS.Sky.twinkle.upperBound - DS.Sky.twinkle.lowerBound))
            }
            if layer == DS.Sky.counts.count - 1 { layerStars.sort { $0.r > $1.r } }
            out += layerStars
        }
        return out
    }()

    /// Si a esta hora cruza la estrella fugaz (a la mitad de cada minuto, lo que dura).
    static func shooting(at time: TimeInterval) -> Bool { shot(at: time) != nil }
    /// La fugaz de este minuto (su número, para que salga en otro lugar cada vez) y qué tan avanzada va (0…1).
    private static func shot(at time: TimeInterval) -> (cycle: Double, progress: Double)? {
        guard time > 0 else { return nil }
        let cycle = (time / DS.Sky.shootEvery).rounded(.down)
        let local = time - cycle * DS.Sky.shootEvery - DS.Sky.shootEvery / 2
        return local >= 0 && local < DS.Sky.shootFor ? (cycle, local / DS.Sky.shootFor) : nil
    }

    func paint(_ g: inout GraphicsContext, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let env = g.environment
        let white = Color(DS.Sky.star.resolve(in: env))
        let tones: [SkyStar.Tone: Color] = [.white: white, .cold: Color(DS.Sky.cold.resolve(in: env)), .warm: Color(DS.Sky.warm.resolve(in: env))]
        let fade = dark ? 1 : DS.Sky.lightStars
        let near = DS.Sky.counts.count - 1
        var haloed = 0
        for star in Self.stars {
            let layer = star.layer
            let shift = CGFloat(time) * DS.Sky.drift[layer] + tilt.x * DS.Sky.tilt[layer]
            let x = (star.x * size.width + shift).truncatingRemainder(dividingBy: size.width)
            let p = CGPoint(x: x < 0 ? x + size.width : x, y: star.y * size.height + tilt.y * DS.Sky.tilt[layer])
            var alpha = DS.Sky.opacity[layer] * fade
            if layer == near {   // las de cerca titilan despacio
                alpha *= 1 - DS.Sky.twinkleDepth * (0.5 + 0.5 * sin(time * 2 * .pi / star.period + star.phase))
            }
            let color = tones[star.tone] ?? white
            if layer == near, dark, haloed < DS.Sky.halos {
                haloed += 1
                let h = star.r * DS.Sky.haloScale
                g.fill(Path(ellipseIn: CGRect(x: p.x - h, y: p.y - h, width: h * 2, height: h * 2)),
                       with: .radialGradient(Gradient(colors: [color.opacity(alpha * DS.Sky.haloOpacity), .clear]), center: p, startRadius: 0, endRadius: h))
            }
            g.fill(Path(ellipseIn: CGRect(x: p.x - star.r, y: p.y - star.r, width: star.r * 2, height: star.r * 2)), with: .color(color.opacity(alpha)))
        }
        shootingStar(&g, size: size, color: white.opacity(fade))
    }

    /// Una estrella fugaz finita, en un lugar distinto cada minuto, que aparece y se apaga.
    private func shootingStar(_ g: inout GraphicsContext, size: CGSize, color: Color) {
        guard let shot = Self.shot(at: time) else { return }
        var rng = SkyRandom(seed: DS.Sky.seed &+ UInt64(shot.cycle))
        let start = CGPoint(x: size.width * (0.4 + 0.5 * rng.unit()), y: size.height * (0.05 + 0.25 * rng.unit()))
        let angle = .pi * (0.8 + 0.08 * rng.unit())   // hacia abajo a la izquierda
        let dir = CGPoint(x: cos(angle), y: sin(angle)), run = DS.Sky.shootLength * 2 * shot.progress
        let head = CGPoint(x: start.x + dir.x * run, y: start.y + dir.y * run)
        let tail = CGPoint(x: head.x - dir.x * DS.Sky.shootLength, y: head.y - dir.y * DS.Sky.shootLength)
        var path = Path(); path.move(to: tail); path.addLine(to: head)
        g.stroke(path, with: .linearGradient(Gradient(colors: [.clear, color.opacity(sin(.pi * shot.progress) * DS.Sky.shootOpacity)]),
                                             startPoint: tail, endPoint: head),
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
/// en cada cuadro, así no vuelve a pintar la pantalla por cada lectura del sensor.
@MainActor
final class SkyTilt {
    private(set) var offset: CGPoint = .zero
    /// Se crea al empezar, no al armar la vista (SwiftUI arma `SkyField` muchas veces y Apple pide uno solo a la vez).
    private var motion: CMMotionManager?
    private var rest: CGPoint?

    func start() {
        let motion = self.motion ?? CMMotionManager()
        self.motion = motion
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = DS.Sky.motionInterval
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let g = data?.gravity else { return }
            let now = CGPoint(x: g.x, y: g.y)
            // El reposo sigue despacio a tu mano: se nota el movimiento, no cómo sostienes el teléfono.
            let rest = self.rest.map { CGPoint(x: $0.x + (now.x - $0.x) * DS.Sky.restFollow, y: $0.y + (now.y - $0.y) * DS.Sky.restFollow) } ?? now
            self.rest = rest
            func clamp(_ v: CGFloat) -> CGFloat { max(-1, min(1, v * DS.Sky.tiltGain)) }
            let target = CGPoint(x: clamp(now.x - rest.x), y: clamp(now.y - rest.y))
            self.offset = CGPoint(x: self.offset.x + (target.x - self.offset.x) * DS.Sky.tiltEase,
                                  y: self.offset.y + (target.y - self.offset.y) * DS.Sky.tiltEase)
        }
    }

    func stop() {
        motion?.stopDeviceMotionUpdates()
        rest = nil; offset = .zero
    }
}
