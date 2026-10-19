import SwiftUI
import OrbitalCore

/// «Un Simpson al azar» como un cambio de canal en la tele de la sala de Los Simpson (≈1.2 s): la tele (morada, con su antena
/// de conejo chueca, perillas, bocina y patitas) aparece con un rebote; estática y tres clics de canal con su número en
/// verde; se queda en el elegido, la pantalla se ilumina, el nombre aparece y la imagen del episodio crece desde la pantalla
/// hasta llenar el iPhone, donde empieza. Con «Reducir movimiento», directo al elegido.
struct SimpsonsRoulette: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draw: AppEnvironment.SimpsonsDraw?
    /// Qué canal se ve (un índice de `draw.reel`; el último es el elegido).
    @State private var channel = 0
    @State private var staticOn = true
    @State private var shown = false
    @State private var landed = false
    @State private var glow = false
    /// La imagen del episodio sale de la pantalla de la tele y crece hasta llenar el iPhone.
    @State private var expanded = false
    /// Dónde está la pantalla de la tele (de ahí sale la imagen al crecer).
    @State private var screenRect: CGRect = .zero
    @State private var clicks = 0
    @State private var run: Task<Void, Never>?

    var body: some View {
        ZStack {
                DS.backdropDeep.ignoresSafeArea()
                RadialGradient(colors: [DS.Simpsons.amarillo.opacity(DesignTokens.Opacity.faint), .clear], center: .center, startRadius: 0, endRadius: DS.Simpsons.glow)
                    .ignoresSafeArea().opacity(landed ? 1 : DS.Simpsons.ghost)
                VStack(spacing: DS.Space.s6) {
                    Spacer(minLength: 0)
                    tv
                    caption.opacity(expanded ? 0 : 1)
                    Spacer(minLength: 0)
                    Button("Cancelar") { run?.cancel(); dismiss() }.buttonStyle(.glass).opacity(expanded ? 0 : 1)
                }
                .padding(.vertical, DS.Space.s8)
                // El episodio, justo encima de la pantalla de la tele; al crecer, de ese rectángulo a toda la pantalla.
                if landed, let still, screenRect != .zero {
                    GeometryReader { geo in
                        let full = CGRect(origin: .zero, size: geo.size)
                        let rect = expanded ? full : screenRect
                        PosterView(url: still, title: "", aspect: nil, bleed: true)
                            .frame(width: rect.width, height: rect.height)
                            .clipShape(RoundedRectangle(cornerRadius: expanded ? 0 : DS.Simpsons.screenRadius, style: .continuous))
                            .position(x: rect.midX, y: rect.midY)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
        }
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.selection, trigger: clicks)
        .sensoryFeedback(.success, trigger: landed) { _, now in now }
        .task { await roll() }
        .onDisappear { run?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Un Simpson al azar"))
    }

    private var still: String? {
        draw.map { d in
            let item = d.reel[min(channel, d.reel.count - 1)]
            return AppEnvironment.simpsonsStill(season: item.season, episode: item.episode.episode)
        }
    }

    /// La tele de la sala.
    private var tv: some View {
        VStack(spacing: 0) {
            RabbitEars().stroke(DS.Simpsons.antenna, style: StrokeStyle(lineWidth: DS.Simpsons.antennaLine, lineCap: .round))
                .overlay(RabbitEarTips().fill(DS.Simpsons.antenna))
                .frame(width: DS.Simpsons.antennaWidth, height: DS.Simpsons.antennaHeight)
                .rotationEffect(.degrees(landed ? 0 : DS.Simpsons.antennaWobble), anchor: .bottom)
            HStack(spacing: DS.Space.s4) {
                screen
                // Perillas y bocina.
                VStack(spacing: DS.Space.s3) {
                    knob.rotationEffect(.degrees(Double(clicks) * DS.Simpsons.knobTurn))
                    knob
                    VStack(spacing: DS.Simpsons.grilleGap) {
                        ForEach(0..<DS.Simpsons.grilleLines, id: \.self) { _ in
                            Capsule().fill(DS.Simpsons.knob).frame(width: DS.Simpsons.knobSize, height: DS.Simpsons.grilleLine)
                        }
                    }
                }
            }
            .padding(DS.Simpsons.bezel)
            .background(
                RoundedRectangle(cornerRadius: DS.Simpsons.tvRadius, style: .continuous)
                    .fill(LinearGradient(colors: [DS.Simpsons.tvBody, DS.Simpsons.tvShade], startPoint: .top, endPoint: .bottom))
                    .shadow(color: DS.Simpsons.tvBody.opacity(DesignTokens.Opacity.faint), radius: landed ? DS.Simpsons.tvGlow : 0)
            )
            HStack { leg; Spacer(); leg }.frame(width: DS.Simpsons.legSpan)
        }
        .scaleEffect(shown ? (expanded ? DS.Simpsons.tvBehind : 1) : DS.Simpsons.appearScale)
        .opacity(shown ? (expanded ? 0 : 1) : 0)
        .accessibilityHidden(true)
    }

    /// La pantalla: cristal curvo con su marco, la imagen del canal, la estática, el número de canal y el brillo.
    private var screen: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Simpsons.screenRadius, style: .continuous)
        return ZStack(alignment: .topTrailing) {
            Color.black
            if let still { PosterView(url: still, title: "", aspect: DS.Simpsons.screenAspect, bleed: true).opacity(staticOn ? DS.Simpsons.ghost : 1) }
            if staticOn { TVStatic().transition(.opacity) }
            // El viñeteado del cristal de una tele vieja.
            RadialGradient(colors: [.clear, .black.opacity(DesignTokens.Opacity.faint)], center: .center, startRadius: DS.Simpsons.screen / 4, endRadius: DS.Simpsons.screen * 0.75)
            if !landed, clicks > 0 {
                Text(verbatim: "CH \(DS.Simpsons.channels[(clicks - 1) % DS.Simpsons.channels.count])")
                    .font(.system(.title3, design: .monospaced).weight(.heavy)).foregroundStyle(DS.Simpsons.osd)
                    .shadow(color: DS.Simpsons.osd, radius: DS.Simpsons.osdGlow)
                    .padding(DS.Space.s2)
            }
            if glow { Color.white.opacity(DS.Simpsons.flash).blendMode(.plusLighter) }
        }
        .frame(width: DS.Simpsons.screen, height: DS.Simpsons.screen / DS.Simpsons.screenAspect)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { screenRect = $0 }
        .clipShape(shape)
        .overlay(shape.strokeBorder(DS.Simpsons.tvShade, lineWidth: DS.Simpsons.screenFrame))
    }

    private var knob: some View {
        Circle().fill(DS.Simpsons.knob).frame(width: DS.Simpsons.knobSize, height: DS.Simpsons.knobSize)
            .overlay(Capsule().fill(DS.Simpsons.tvBody).frame(width: DS.Simpsons.knobMark, height: DS.Simpsons.knobSize / 2).offset(y: -DS.Simpsons.knobSize / 4))
    }

    private var leg: some View {
        Capsule().fill(DS.Simpsons.tvShade).frame(width: DS.Simpsons.legWidth, height: DS.Simpsons.legHeight)
    }

    /// El canal en el que se quedó: temporada, episodio y nombre.
    private var caption: some View {
        VStack(spacing: DS.Space.s1) {
            Text("Un Simpson al azar").recipe(.footnote)
            if landed, let chosen = draw?.chosen {
                Text(verbatim: Strings.episode(season: chosen.season, episode: chosen.episode.episode, language: env.services.appSettings.uiLanguage))
                    .recipe(.eyebrow, color: DS.Simpsons.amarillo)
                if chosen.episode.hasTitle { Text(verbatim: chosen.episode.title).recipe(.section).multilineTextAlignment(.center).foregroundStyle(DS.text) }
            }
        }
        .frame(minHeight: DS.Simpsons.captionHeight, alignment: .top)
        .padding(.horizontal, DS.Space.gutter)
        .animation(DS.Motion.base(reduceMotion), value: landed)
    }

    private func roll() async {
        run?.cancel()
        guard let found = await env.takeSimpsons() else { dismiss(); return }
        draw = found; channel = 0; landed = false; expanded = false
        if reduceMotion {
            shown = true; staticOn = false; channel = found.reel.count - 1; landed = true
            try? await Task.sleep(nanoseconds: UInt64(DS.Simpsons.hold * 1_000_000_000))
            start(); return
        }
        run = Task { @MainActor in
            func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
            withAnimation(.spring(duration: DS.Simpsons.appear, bounce: DS.Simpsons.bounce)) { shown = true }
            await wait(DS.Simpsons.appear * 0.7)
            // Clic, clic, clic: estática, el número del canal y su imagen.
            for i in 0..<found.reel.count where !Task.isCancelled {
                staticOn = true; channel = i; clicks += 1
                await wait(DS.Simpsons.staticBurst)
                withAnimation(.easeOut(duration: DS.Simpsons.staticBurst)) { staticOn = false }
                await wait(DS.Simpsons.flip)
            }
            guard !Task.isCancelled else { return }
            // Se queda: la pantalla brilla un instante y aparece el nombre.
            withAnimation(.easeOut(duration: DS.Simpsons.settle)) { landed = true; glow = true }
            withAnimation(.easeOut(duration: DS.Simpsons.settle).delay(DS.Simpsons.flashOff)) { glow = false }
            await wait(DS.Simpsons.hold)
            guard !Task.isCancelled else { return }
            // La imagen crece desde la pantalla hasta llenar el iPhone.
            withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: DS.Simpsons.zoom)) { expanded = true }
            await wait(DS.Simpsons.zoom)
            if !Task.isCancelled { start() }
        }
    }

    /// El reproductor entra y esta pantalla se va sin animación (si no, se veía Inicio un instante entre las dos).
    private func start() {
        run?.cancel()
        guard let draw else { return }
        var quiet = Transaction(); quiet.disablesAnimations = true
        withTransaction(quiet) { dismiss() }
        // En cuanto se quitó esta pantalla (no se pueden presentar dos a la vez), el reproductor, también sin animación.
        let env = env
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(DS.Simpsons.handoff * 1_000_000_000))
            withTransaction(quiet) { env.playSimpsons(draw) }
        }
    }
}

/// La antena de conejo: dos varillas desde una base redonda, chuecas (una más abierta y más larga que la otra).
private struct RabbitEars: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let base = CGPoint(x: rect.midX, y: rect.maxY - DS.Simpsons.antennaBase / 2)
        p.move(to: base); p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.12))
        p.move(to: base); p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.minY + rect.height * 0.34))
        p.addEllipse(in: CGRect(x: base.x - DS.Simpsons.antennaBase, y: base.y - DS.Simpsons.antennaBase / 2,
                                width: DS.Simpsons.antennaBase * 2, height: DS.Simpsons.antennaBase))
        return p
    }
}

/// Las bolitas de las puntas de la antena.
private struct RabbitEarTips: Shape {
    func path(in rect: CGRect) -> Path {
        let r = DS.Simpsons.antennaTip
        var p = Path()
        for tip in [CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.12),
                    CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.minY + rect.height * 0.34)] {
            p.addEllipse(in: CGRect(x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2))
        }
        return p
    }
}

/// La estática de una tele vieja: rayas grises al azar que cambian en cada cuadro.
private struct TVStatic: View {
    var body: some View {
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                var rng = SeededNoise(seed: UInt64(context.date.timeIntervalSinceReferenceDate * 60))
                let rows = Int(size.height / DS.Simpsons.staticLine)
                for r in 0..<rows {
                    let y = CGFloat(r) * DS.Simpsons.staticLine
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: DS.Simpsons.staticLine)), with: .color(DS.text.opacity(rng.next())))
                }
            }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
    }
}

/// Números al azar repetibles por cuadro (la estática no depende del generador del sistema).
private struct SeededNoise {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) % 1000) / 1000 * DesignTokens.Opacity.faint
    }
}
