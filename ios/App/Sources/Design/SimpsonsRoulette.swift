import SwiftUI
import OrbitalCore

/// «Un Simpson al azar» como ruleta: las imágenes de los episodios pasan como en una tragamonedas, frenan en el elegido,
/// se dice cuál es (temporada, episodio y nombre) y arranca solo en el iPhone. «Otro» vuelve a tirar; «Ver ya», sin esperar.
struct SimpsonsRoulette: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draw: AppEnvironment.SimpsonsDraw?
    @State private var offset: CGFloat = 0
    @State private var landed = false
    @State private var spin = 0.0
    @State private var autoplay: Task<Void, Never>?

    private var step: CGFloat { DS.Simpsons.card + DS.Simpsons.gap }

    var body: some View {
        ZStack {
            DS.backdropDeep.ignoresSafeArea()
            RadialGradient(colors: [DS.Simpsons.amarillo.opacity(DesignTokens.Opacity.faint), .clear], center: .top, startRadius: 0, endRadius: DS.Simpsons.glow)
                .ignoresSafeArea()
            VStack(spacing: DS.Space.s5) {
                Image("Glyphs/donut").resizable().frame(width: DS.Simpsons.donut, height: DS.Simpsons.donut)
                    .rotationEffect(.degrees(spin))
                    .accessibilityHidden(true)
                Text("Un Simpson al azar").recipe(.title).foregroundStyle(DS.text)
                reel
                reveal
                Spacer(minLength: 0)
                Button("Cancelar") { autoplay?.cancel(); dismiss() }.buttonStyle(.glass)
            }
            .padding(.vertical, DS.Space.s8)
        }
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.success, trigger: landed) { _, now in now }
        .task { await roll() }
        .onDisappear { autoplay?.cancel() }
    }

    /// La tira de imágenes: el elegido es la última y queda al centro.
    private var reel: some View {
        GeometryReader { geo in
            HStack(spacing: DS.Simpsons.gap) {
                ForEach(Array((draw?.reel ?? []).enumerated()), id: \.offset) { i, item in
                    let isChosen = landed && i == (draw?.reel.count ?? 0) - 1
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        PosterView(url: AppEnvironment.simpsonsStill(season: item.season, episode: item.episode.episode), title: "", aspect: DS.Poster.stillAspect)
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(isChosen ? DS.Simpsons.amarillo : .clear, lineWidth: DS.SettingsLook.optionRing))
                        Text(verbatim: Strings.episode(season: item.season, episode: item.episode.episode, language: env.services.appSettings.uiLanguage))
                            .recipe(.caption, color: isChosen ? DS.Simpsons.amarillo : DS.textMuted).fontWeight(.semibold)
                    }
                    .frame(width: DS.Simpsons.card)
                    .scaleEffect(isChosen ? DS.Simpsons.chosenScale : 1)
                    .opacity(landed && !isChosen ? DesignTokens.Opacity.disabled : 1)
                }
            }
            .offset(x: geo.size.width / 2 - DS.Simpsons.card / 2 + offset)
        }
        .frame(height: DS.Simpsons.card / DS.Poster.stillAspect + DS.Space.s6)
        .overlay { if draw == nil { ProgressView() } }
        .accessibilityHidden(true)
    }

    /// Cuál salió y qué hacer.
    @ViewBuilder private var reveal: some View {
        if landed, let chosen = draw?.chosen {
            VStack(spacing: DS.Space.s2) {
                Text(verbatim: Strings.episode(season: chosen.season, episode: chosen.episode.episode, language: env.services.appSettings.uiLanguage))
                    .recipe(.eyebrow, color: DS.Simpsons.amarillo)
                if chosen.episode.hasTitle { Text(verbatim: chosen.episode.title).recipe(.section).multilineTextAlignment(.center).foregroundStyle(DS.text) }
                Text("Empieza en un momento…").recipe(.footnote)
                HStack(spacing: DS.Space.s3) {
                    Button("Otro", systemImage: "arrow.triangle.2.circlepath") { Task { await roll() } }.buttonStyle(.glass).controlSize(.large)
                    Button("Ver ya", systemImage: "play.fill") { start() }.dsPrimaryButton().controlSize(.large)
                }
                .padding(.top, DS.Space.s2)
            }
            .padding(.horizontal, DS.Space.gutter)
            .transition(.opacity.combined(with: .scale(scale: DS.Simpsons.revealScale)))
            .accessibilityElement(children: .contain)
        }
    }

    private func roll() async {
        autoplay?.cancel()
        withAnimation(DS.Motion.base(reduceMotion)) { landed = false }
        offset = 0
        guard let found = await env.drawSimpsons(reelLength: DS.Simpsons.reelLength) else { dismiss(); return }
        // Las imágenes, antes de girar (si no, pasaban en gris).
        let stills = found.reel.map { AppEnvironment.simpsonsStill(season: $0.season, episode: $0.episode.episode) }
        await withTaskGroup(of: Void.self) { group in   // todas, con un tope: si la red tarda, gira igual
            group.addTask { await ImagePipeline.shared.warmPosters(stills) }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(DS.Simpsons.warmWait * 1_000_000_000)) }
            await group.next(); group.cancelAll()
        }
        draw = found
        let end = -CGFloat(found.reel.count - 1) * step
        if reduceMotion {
            offset = end; landed = true
        } else {
            withAnimation(.timingCurve(0.12, 0.8, 0.18, 1, duration: DS.Simpsons.spin)) { offset = end; spin += DS.Simpsons.donutTurns }
            completion: { withAnimation(DS.Motion.base(reduceMotion)) { landed = true } }
        }
        autoplay = Task {
            try? await Task.sleep(nanoseconds: UInt64(((reduceMotion ? 0 : DS.Simpsons.spin) + DS.Simpsons.hold) * 1_000_000_000))
            if !Task.isCancelled { start() }
        }
    }

    private func start() {
        autoplay?.cancel()
        guard let draw else { return }
        dismiss()
        env.playSimpsons(draw)
    }
}
