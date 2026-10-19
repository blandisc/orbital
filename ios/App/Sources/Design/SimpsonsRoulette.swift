import SwiftUI
import OrbitalCore

/// «Un Simpson al azar» como un cambio de canal en la tele morada de la sala (un segundo): la tele aparece, estática y tres
/// clics de canal (pasan tres episodios de un parpadeo), se queda en el elegido con su nombre y la pantalla crece hasta
/// volverse el reproductor. Con «Reducir movimiento», directo al elegido.
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
    @State private var zoom = false
    @State private var clicks = 0
    @State private var run: Task<Void, Never>?

    var body: some View {
        ZStack {
            DS.backdropDeep.ignoresSafeArea()
            RadialGradient(colors: [DS.Simpsons.amarillo.opacity(DesignTokens.Opacity.faint), .clear], center: .center, startRadius: 0, endRadius: DS.Simpsons.glow)
                .ignoresSafeArea().opacity(zoom ? 0 : 1)
            VStack(spacing: DS.Space.s5) {
                Spacer(minLength: 0)
                tv
                caption.opacity(zoom ? 0 : 1)
                Spacer(minLength: 0)
                Button("Cancelar") { run?.cancel(); dismiss() }.buttonStyle(.glass).opacity(zoom ? 0 : 1)
            }
            .padding(.vertical, DS.Space.s8)
        }
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.selection, trigger: clicks)
        .sensoryFeedback(.success, trigger: landed) { _, now in now }
        .task { await roll() }
        .onDisappear { run?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Un Simpson al azar"))
    }

    /// La tele de la sala: cuerpo morado, pantalla con la imagen del canal (o estática) y dos perillas.
    private var tv: some View {
        let still = draw.map { d -> String in
            let item = d.reel[min(channel, d.reel.count - 1)]
            return AppEnvironment.simpsonsStill(season: item.season, episode: item.episode.episode)
        }
        return HStack(spacing: DS.Space.s3) {
            ZStack {
                PosterView(url: still, title: "", aspect: DS.Simpsons.screenAspect, bleed: true)
                    .opacity(staticOn ? DS.Simpsons.ghost : 1)
                if staticOn { TVStatic().transition(.opacity) }
            }
            .frame(width: DS.Simpsons.screen, height: DS.Simpsons.screen / DS.Simpsons.screenAspect)
            .clipShape(RoundedRectangle(cornerRadius: DS.Simpsons.screenRadius, style: .continuous))
            VStack(spacing: DS.Space.s3) {
                Circle().fill(DS.Simpsons.knob).frame(width: DS.Simpsons.knobSize, height: DS.Simpsons.knobSize)
                    .rotationEffect(.degrees(Double(clicks) * DS.Simpsons.knobTurn))
                Circle().fill(DS.Simpsons.knob).frame(width: DS.Simpsons.knobSize, height: DS.Simpsons.knobSize)
            }
            .opacity(zoom ? 0 : 1)
        }
        .padding(DS.Space.s4)
        .background(DS.Simpsons.tvBody.opacity(zoom ? 0 : 1), in: RoundedRectangle(cornerRadius: DS.Simpsons.tvRadius, style: .continuous))
        .scaleEffect(zoom ? DS.Simpsons.zoomScale : (shown ? 1 : DS.Simpsons.appearScale))
        .opacity(shown ? 1 : 0)
        .accessibilityHidden(true)
    }

    /// El canal en el que se quedó: temporada, episodio y nombre.
    @ViewBuilder private var caption: some View {
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
    }

    private func roll() async {
        run?.cancel()
        guard let found = await env.takeSimpsons() else { dismiss(); return }
        // Las imágenes de los canales, antes de cambiar (si no, pasaban en negro); con un tope corto.
        let stills = found.reel.map { AppEnvironment.simpsonsStill(season: $0.season, episode: $0.episode.episode) }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await ImagePipeline.shared.warmPosters(stills) }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(DS.Simpsons.warmWait * 1_000_000_000)) }
            await group.next(); group.cancelAll()
        }
        draw = found; channel = 0; landed = false; zoom = false
        if reduceMotion {
            shown = true; staticOn = false; channel = found.reel.count - 1; landed = true
            try? await Task.sleep(nanoseconds: UInt64(DS.Simpsons.hold * 1_000_000_000))
            start(); return
        }
        run = Task { @MainActor in
            func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
            withAnimation(.spring(duration: DS.Simpsons.appear)) { shown = true }
            await wait(DS.Simpsons.appear)
            // Clic, clic, clic: cada canal, un parpadeo de estática y luego su imagen.
            for i in 0..<found.reel.count where !Task.isCancelled {
                staticOn = true; channel = i; clicks += 1
                await wait(DS.Simpsons.staticBurst)
                withAnimation(.easeOut(duration: DS.Simpsons.staticBurst)) { staticOn = false }
                if i < found.reel.count - 1 { await wait(DS.Simpsons.flip) }
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: DS.Simpsons.settle)) { landed = true }
            await wait(DS.Simpsons.hold)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: DS.Simpsons.zoom)) { zoom = true }   // la pantalla se vuelve el reproductor
            await wait(DS.Simpsons.zoom)
            if !Task.isCancelled { start() }
        }
    }

    private func start() {
        run?.cancel()
        guard let draw else { return }
        dismiss()
        env.playSimpsons(draw)
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
