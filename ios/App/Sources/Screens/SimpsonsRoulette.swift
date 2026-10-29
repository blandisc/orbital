import SwiftUI
import OrbitalModels
import OrbitalCore

/// «Un Simpson al azar» como un cambio de canal en la tele de la sala de Los Simpson (≈1.2 s): la tele (morada, con su antena
/// de conejo chueca, perillas, bocina y patitas) aparece con un rebote; estática y tres clics de canal con su número en
/// verde; se queda en el elegido, la pantalla se ilumina, el nombre aparece y la imagen del episodio crece desde la pantalla
/// hasta el lugar del video en el reproductor vertical (a lo ancho), donde empieza. Con «Reducir movimiento», directo al elegido.
struct SimpsonsRoulette: View {
    /// Los colores del fondo de Inicio: la ruleta sale sobre el mismo fondo (antes era otro y el cambio era de golpe).
    var tint: ArtColors? = nil
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draw: SimpsonsModel.Draw?
    /// Qué canal se ve (un índice de `draw.reel`; el último es el elegido).
    @State private var channel = 0
    @State private var staticOn = true
    @State private var shown = false
    @State private var landed = false
    @State private var glow = false
    /// La imagen del episodio sale de la pantalla de la tele y crece hasta el lugar del video en vertical.
    @State private var expanded = false
    /// Dónde está la pantalla de la tele (de ahí sale la imagen al crecer).
    @State private var screenRect: CGRect = .zero
    @State private var clicks = 0
    @State private var run: Task<Void, Never>?
    /// El episodio que se está viendo, encima de la ruleta (al cerrarlo, la ruleta se va con él).
    @State private var playing: PlayRequest?
    /// El episodio ya se cerró: la ruleta se va; nada vuelve a girar en lo que desaparece.
    @State private var finished = false
    /// Dónde va el video en el reproductor vertical: la imagen crece hasta ahí (no a toda la pantalla).
    @AppStorage(PlayerScreen.portraitCenterKey) private var portraitCenter = Double(DS.PlayerPanel.portraitCenter)

    var body: some View {
        ZStack {
                // El mismo fondo de Inicio (con el tono de su destacado): la tele aparece sobre lo que ya veías. Al crecer, se
                // oscurece despacio al negro del reproductor (la imagen queda como el video, no flotando en la sala).
                Backdrop(tint: tint).ignoresSafeArea()
                DS.video.ignoresSafeArea().opacity(expanded ? 1 : 0)
                // El brillo de la tele entra con ella (antes ya estaba ahí desde el primer cuadro).
                RadialGradient(colors: [DS.Simpsons.amarillo.opacity(DesignTokens.Opacity.faint), .clear], center: .center, startRadius: 0, endRadius: DS.Simpsons.glow)
                    .ignoresSafeArea().opacity(expanded ? 0 : landed ? 1 : shown ? DS.Simpsons.ghost : 0)
                VStack(spacing: DS.Space.s6) {
                    Spacer(minLength: 0)
                    tv
                    caption.opacity(expanded ? 0 : 1)
                    Spacer(minLength: 0)
                    Button("Cancelar") { run?.cancel(); dismiss() }.buttonStyle(.glass).opacity(expanded ? 0 : 1)
                }
                .padding(.vertical, DS.Space.s8)
                // El episodio, justo encima de la pantalla de la tele; al crecer, de ese rectángulo al lugar del video en el
                // reproductor vertical (a lo ancho, en su proporción): el episodio empieza justo donde quedó la imagen.
                if landed, let still, screenRect != .zero {
                    GeometryReader { geo in
                        let inset = PlayerScreen.windowSafeArea
                        let safe = CGSize(width: geo.size.width, height: max(0, geo.size.height - inset.top - inset.bottom))
                        let rect = expanded ? PlayerScreen.portraitVideoRect(in: safe, center: portraitCenter).offsetBy(dx: 0, dy: inset.top) : screenRect
                        let shape = RoundedRectangle(cornerRadius: expanded ? 0 : DS.Simpsons.screenRadius, style: .continuous)
                        PosterView(url: still, title: "", aspect: nil, bleed: true)
                            // El viñeteado y el marco de la pantalla siguen encima de la imagen (antes la imagen los tapaba y la
                            // tele se quedaba sin su contorno); al crecer hacia el reproductor se desvanecen.
                            .overlay { Self.vignette.opacity(expanded ? 0 : 1) }
                            .frame(width: rect.width, height: rect.height)
                            .clipShape(shape)
                            .overlay(shape.strokeBorder(DS.Simpsons.tvShade, lineWidth: DS.Simpsons.screenFrame).opacity(expanded ? 0 : 1))
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
        // Gira una vez. Esta vista vuelve a «aparecer» con el episodio ya encima (al mandar el video a la ventana de PiP o salir
        // de la app lo vuelve a presentar el sistema), y antes cada vez giraba otra vez y abría otro episodio al azar debajo.
        .task { guard playing == nil, !finished else { return }; await roll() }
        .onDisappear { run?.cancel() }
        // Al cerrar el reproductor, la ruleta ya cumplió: se va también, sin animación (debajo está Inicio, como siempre).
        .fullScreenCover(item: $playing, onDismiss: {
            finished = true
            var quiet = Transaction(); quiet.disablesAnimations = true
            withTransaction(quiet) { dismiss() }
        }) { request in PlayerScreen(request: request) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Un Simpson al azar"))
    }

    private var still: String? {
        draw.map { d in
            let item = d.reel[min(channel, d.reel.count - 1)]
            return SimpsonsModel.still(season: item.season, episode: item.episode.episode)
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

    /// El viñeteado del cristal de una tele vieja.
    private static var vignette: some View {
        RadialGradient(colors: [.clear, .black.opacity(DesignTokens.Opacity.faint)], center: .center, startRadius: DS.Simpsons.screen / 4, endRadius: DS.Simpsons.screen * 0.75)
    }

    /// La pantalla: cristal curvo con su marco, la imagen del canal, la estática, el número de canal y el brillo.
    private var screen: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Simpsons.screenRadius, style: .continuous)
        return ZStack(alignment: .topTrailing) {
            Color.black   // ds-exception: la tele de Los Simpson es siempre oscura (es arte, no un papel del modo claro u oscuro)
            if let still { PosterView(url: still, title: "", aspect: DS.Simpsons.screenAspect, bleed: true).opacity(staticOn ? DS.Simpsons.ghost : 1) }
            if staticOn { TVStatic().transition(.opacity) }
            Self.vignette
            if !landed, clicks > 0 {
                Text(verbatim: "CH \(DS.Simpsons.channels[(clicks - 1) % DS.Simpsons.channels.count])")
                    .font(.system(.title3, design: .monospaced).weight(.heavy)).foregroundStyle(DS.Simpsons.osd)
                    .shadow(color: DS.Simpsons.osd, radius: DS.Simpsons.osdGlow)
                    .padding(DS.Space.s2)
            }
            if glow { Color.white.opacity(DS.Simpsons.flash).blendMode(.plusLighter) }   // ds-exception: la tele de Los Simpson es siempre oscura (es arte, no un papel del modo claro u oscuro)
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
        guard let found = await env.simpsons.take() else { dismiss(); return }
        draw = found; channel = 0; landed = false; expanded = false
        if reduceMotion {
            shown = true; staticOn = false; channel = found.reel.count - 1; landed = true
            try? await Task.sleep(nanoseconds: UInt64(DS.Simpsons.hold * 1_000_000_000))
            start(); return
        }
        run = Task { @MainActor in
            func wait(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }
            withAnimation(.spring(duration: DS.Simpsons.appear, bounce: DS.Simpsons.bounce)) { shown = true }
            // Desde el Centro de control la app acaba de abrir y las imágenes no estaban listas (desde la dona sí): la tele
            // sintoniza con estática hasta que llegan (o hasta `imageWait`). Antes crecía en negro y la imagen salía al final.
            staticOn = true
            let stills = found.reel.map { SimpsonsModel.still(season: $0.season, episode: $0.episode.episode) }
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await ImagePipeline.shared.warmPosters(stills) }
                group.addTask { try? await Task.sleep(nanoseconds: UInt64(DS.Simpsons.imageWait * 1_000_000_000)) }
                await group.next()
                group.cancelAll()
            }
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
            #if DEBUG
            if Demo.isOn, Demo.open == "simpsons" { return }   // `-demo-open simpsons`: la ruleta se queda en el canal elegido (capturas)
            #endif
            // La imagen crece desde la pantalla hasta donde va el video en vertical.
            withAnimation(DS.Simpsons.zoomCurve) { expanded = true }
            await wait(DS.Simpsons.zoom + DS.Simpsons.zoomRest)
            #if DEBUG
            if Demo.isOn, Demo.open == "simpsons-zoom" { return }   // `-demo-open simpsons-zoom`: se queda ya crecida (capturas)
            #endif
            if !Task.isCancelled { start() }
        }
    }

    /// El reproductor entra encima de la ruleta, sin animación: la imagen que creció queda bajo su negro de carga y el
    /// episodio arranca ahí mismo. Antes la ruleta se cerraba primero y entre las dos se veía Inicio un instante.
    private func start() {
        run?.cancel()
        guard let draw, playing == nil, !finished else { return }   // ya hay un episodio encima: no se cambia por otro
        var quiet = Transaction(); quiet.disablesAnimations = true
        withTransaction(quiet) { playing = env.simpsons.request(draw) }
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
